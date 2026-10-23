import Foundation
import CoreGraphics

/// A print-only outer offset in centimetres. Curves are stroked natively and
/// joined with a bounded miter; filled-path unions remove overlapping offsets.
/// The original seam path is never edited or rescaled.
enum GarmentCodeSeamAllowance {
    struct Result {
        let cutPath: CGPath
        let bounds: CGRect
        let warnings: [String]
    }

    enum AllowanceError: LocalizedError {
        case invalidInput, invalidWidth, selfIntersection, invalidFold, unreliableOffset, tooComplex
        var errorDescription: String? {
            switch self {
            case .invalidInput: "制版轮廓或边的连接无效，无法生成缝份。"
            case .invalidWidth: "缝份必须是 0～5 cm 的有限数值。"
            case .selfIntersection: "原始制版轮廓有自交、重叠或退化边，请先修正纸样。"
            case .invalidFold: "对折边必须是直线，且整片裁片位于该直线的同一侧。"
            case .unreliableOffset: "当前缝份无法形成可靠的单一裁剪轮廓，请减小缝份或调整边设置。"
            case .tooComplex: "裁片轮廓过于复杂，暂不能可靠生成缝份。"
            }
        }
    }

    private static let flattenTolerance: CGFloat = 0.002 // 0.02 mm
    private static let joinTolerance: CGFloat = 1e-5
    private static let topologyTolerance: CGFloat = 1e-7

    private struct Loop {
        var points: [CGPoint]
        let closed: Bool
    }
    private struct Edge {
        let path: CGPath
        let points: [CGPoint]
        var start: CGPoint { points[0] }
        var end: CGPoint { points[points.count - 1] }
        var startDirection: CGPoint { unit(points[1] - points[0]) }
        var endDirection: CGPoint { unit(points[points.count - 1] - points[points.count - 2]) }
    }

    static func build(seamPath: CGPath, edgePaths: [CGPath], widthsCM: [Double],
                      foldEdges: Set<Int> = []) throws -> Result {
        guard !edgePaths.isEmpty, edgePaths.count == widthsCM.count,
              foldEdges.allSatisfy(edgePaths.indices.contains) else { throw AllowanceError.invalidInput }
        guard widthsCM.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 5 }) else {
            throw AllowanceError.invalidWidth
        }
        try validateCoordinates(seamPath)
        let sourceLoops = try loops(seamPath)
        guard sourceLoops.count == 1, let source = sourceLoops.first, source.closed,
              source.points.count >= 3 else { throw AllowanceError.invalidInput }
        guard source.points.count <= 8000 else { throw AllowanceError.tooComplex }
        let sourceArea = signedArea(source.points)
        guard abs(sourceArea) > 1e-8, !hasSelfIntersection(source.points) else {
            throw AllowanceError.selfIntersection
        }
        let winding: CGFloat = sourceArea > 0 ? 1 : -1
        let edges = try edgePaths.map { path -> Edge in
            try validateCoordinates(path)
            let parts = try loops(path)
            guard parts.count == 1, let part = parts.first, !part.closed, part.points.count >= 2 else {
                throw AllowanceError.invalidInput
            }
            return Edge(path: path, points: part.points)
        }
        guard edges.reduce(0, { $0 + $1.points.count }) <= 10000 else { throw AllowanceError.tooComplex }
        for index in edges.indices {
            guard distance(edges[index].end, edges[(index + 1) % edges.count].start) <= joinTolerance else {
                throw AllowanceError.invalidInput
            }
        }
        // Public callers must not accidentally offset a different set of edges
        // than the supplied closed seam path.
        let joined = edges.flatMap { Array($0.points.dropLast()) }
        guard joined.count >= 3, abs(signedArea(joined) - sourceArea) <= max(0.01, abs(sourceArea) * 1e-4),
              sameBoundary(source.points, joined, tolerance: flattenTolerance * 3) else {
            throw AllowanceError.invalidInput
        }
        var widths = widthsCM.map { CGFloat($0) }
        for index in foldEdges { widths[index] = 0 }
        for index in foldEdges {
            let edge = edges[index]
            guard isStraight(edge.path), distance(edge.start, edge.end) > joinTolerance else {
                throw AllowanceError.invalidFold
            }
            let tangent = unit(edge.end - edge.start)
            let inward = leftNormal(tangent) * winding
            guard source.points.allSatisfy({ dot($0 - edge.start, inward) >= -joinTolerance }) else {
                throw AllowanceError.invalidFold
            }
        }
        guard widths.contains(where: { $0 > 0 }) else {
            return Result(cutPath: seamPath, bounds: seamPath.boundingBoxOfPath, warnings: [])
        }

        var result = seamPath.normalized(using: .winding)
        var cappedCorner = false
        var concave = false
        for index in edges.indices {
            let edge = edges[index], width = widths[index]
            if width > 0 {
                let strip = edge.path.copy(strokingWithWidth: width * 2, lineCap: .butt,
                                           lineJoin: .miter, miterLimit: 4)
                result = result.union(strip, using: .winding)
            }
            let nextIndex = (index + 1) % edges.count
            let next = edges[nextIndex], nextWidth = widths[nextIndex]
            let previousDirection = edge.endDirection, nextDirection = next.startDirection
            let turn = cross(previousDirection, nextDirection) * winding
            if turn < -1e-7 { concave = true }
            guard turn > 1e-9, width > 0 || nextWidth > 0 else { continue }
            let vertex = edge.end
            let p = vertex - leftNormal(previousDirection) * (winding * width)
            let q = vertex - leftNormal(nextDirection) * (winding * nextWidth)
            // Positive-area overlap prevents Quartz from leaving an otherwise
            // exactly edge-touching corner as a separate microscopic component.
            // These extensions run along existing offset lines, so their outer
            // distances remain the requested allowance widths.
            let overlap = min(0.0001, distance(edge.start, edge.end) * 0.05,
                              distance(next.start, next.end) * 0.05)
            let inside = vertex - previousDirection * overlap + nextDirection * overlap
            var corner = [inside, p - previousDirection * overlap]
            if let intersection = lineIntersection(p, previousDirection, q, nextDirection),
               distance(intersection, vertex) <= max(width, nextWidth) * 4 + joinTolerance {
                corner.append(intersection)
            } else {
                cappedCorner = true
            }
            corner.append(q + nextDirection * overlap)
            if abs(signedArea(corner)) > 1e-12 {
                result = result.union(polygon(corner), using: .winding)
            }
        }
        // A fold is a supporting straight edge, not a cut edge. Clip after all
        // unions so a neighboring allowance can never push across the fold.
        for index in foldEdges.sorted() {
            let edge = edges[index], tangent = unit(edge.end - edge.start)
            let inward = leftNormal(tangent) * winding
            let box = result.boundingBoxOfPath
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            let reach = (corners.map { distance($0, edge.start) }.max() ?? 0) + 20
            let a = edge.start - tangent * reach, b = edge.start + tangent * reach
            let halfPlane = polygon([a, b, b + inward * (reach * 2), a + inward * (reach * 2)])
            result = result.intersection(halfPlane, using: .winding)
        }
        result = result.normalized(using: .winding)
        try validateCoordinates(result)
        let output = try loops(result)
        // A zero-width dart alongside a nonzero allowance can leave a tiny
        // numerical hole at coincident Boolean intersections. Its area can be
        // about 1e-13 cm². Remove only sub-micrometre-area loops; meaningful
        // holes and disconnected contours are still rejected below.
        let meaningful = output.filter { abs(signedArea($0.points)) > 1e-8 }
        guard meaningful.count == 1, let rawCut = meaningful.first, rawCut.closed, rawCut.points.count >= 3 else {
            throw AllowanceError.unreliableOffset
        }
        // Quartz Boolean operations can leave almost zero-width, backtracking
        // slivers at coincident stroke/corner boundaries (around 1e-8 cm).
        // Remove only those numerical degeneracies. A repaired contour is a
        // vector polyline flattened at 0.002 cm, never the preview's coarse
        // sampling. Source containment is checked again after any repair.
        let cleaned = cleanNumericalArtifacts(rawCut.points)
        let cut = Loop(points: cleaned, closed: true)
        if cleaned.count != rawCut.points.count || meaningful.count != output.count { result = polygon(cleaned) }
        guard cut.points.count <= 12000 else { throw AllowanceError.tooComplex }
        guard !hasSelfIntersection(cut.points), abs(signedArea(cut.points)) >= abs(sourceArea) - 0.01 else {
            throw AllowanceError.unreliableOffset
        }
        let border = result.copy(strokingWithWidth: flattenTolerance * 5, lineCap: .round,
                                 lineJoin: .round, miterLimit: 4)
        guard source.points.allSatisfy({ result.contains($0, using: .winding) || border.contains($0, using: .winding) }) else {
            throw AllowanceError.unreliableOffset
        }
        let bounds = result.boundingBoxOfPath
        guard finite(bounds), bounds.width > 0, bounds.height > 0 else { throw AllowanceError.unreliableOffset }
        var warnings: [String] = []
        if cappedCorner { warnings.append("尖角已限长并改为斜接，请复核该处裁剪线。") }
        if concave { warnings.append("凹角和狭窄省口的缝份已合并，请复核省道、开衩及折边转角；尚未按折省状态修形。") }
        return Result(cutPath: result, bounds: bounds, warnings: warnings)
    }

    private static func validateCoordinates(_ path: CGPath) throws {
        var valid = true
        var count = 0
        path.applyWithBlock { pointer in
            let e = pointer.pointee
            let n: Int
            switch e.type {
            case .moveToPoint, .addLineToPoint: n = 1
            case .addQuadCurveToPoint: n = 2
            case .addCurveToPoint: n = 3
            case .closeSubpath: n = 0
            @unknown default: valid = false; return
            }
            count += 1
            for index in 0..<n {
                let p = e.points[index]
                if !p.x.isFinite || !p.y.isFinite || abs(p.x) > 1e6 || abs(p.y) > 1e6 { valid = false }
            }
        }
        guard valid, count > 0 else { throw AllowanceError.invalidInput }
        guard count < 5000 else { throw AllowanceError.tooComplex }
        guard finite(path.boundingBoxOfPath) else { throw AllowanceError.invalidInput }
    }

    private static func loops(_ path: CGPath) throws -> [Loop] {
        var result: [Loop] = []
        var current: [CGPoint] = []
        var malformed = false
        func finish(_ closed: Bool) {
            guard !current.isEmpty else { return }
            if closed, let first = current.first, let last = current.last,
               distance(first, last) <= 1e-9 { current.removeLast() }
            result.append(Loop(points: current, closed: closed))
            current = []
        }
        path.flattened(threshold: flattenTolerance).applyWithBlock { pointer in
            let e = pointer.pointee
            switch e.type {
            case .moveToPoint: finish(false); current = [e.points[0]]
            case .addLineToPoint:
                guard let last = current.last else { malformed = true; return }
                if distance(last, e.points[0]) > 1e-10 { current.append(e.points[0]) }
            case .closeSubpath: finish(true)
            default: malformed = true
            }
        }
        finish(false)
        guard !malformed else { throw AllowanceError.invalidInput }
        return result
    }

    private static func sameBoundary(_ a: [CGPoint], _ b: [CGPoint], tolerance: CGFloat) -> Bool {
        func matches(_ from: [CGPoint], _ to: [CGPoint]) -> Bool {
            from.allSatisfy { point in
                to.indices.contains { index in
                    let start = to[index], end = to[(index + 1) % to.count]
                    guard point.x >= min(start.x, end.x) - tolerance,
                          point.x <= max(start.x, end.x) + tolerance,
                          point.y >= min(start.y, end.y) - tolerance,
                          point.y <= max(start.y, end.y) + tolerance else { return false }
                    return pointSegmentDistance(point, start, end) <= tolerance
                }
            }
        }
        return matches(a, b) && matches(b, a)
    }

    private static func cleanNumericalArtifacts(_ input: [CGPoint]) -> [CGPoint] {
        let epsilon: CGFloat = 1e-6
        var points = input
        var changed = true
        while changed && points.count >= 3 {
            changed = false
            var deduplicated: [CGPoint] = []
            for point in points {
                if let last = deduplicated.last, distance(last, point) <= epsilon { changed = true }
                else { deduplicated.append(point) }
            }
            if let first = deduplicated.first, let last = deduplicated.last,
               deduplicated.count > 1, distance(first, last) <= epsilon {
                deduplicated.removeLast(); changed = true
            }
            points = deduplicated
            guard points.count >= 3 else { break }
            var remove: Set<Int> = []
            for index in points.indices {
                let a = points[(index + points.count - 1) % points.count]
                let b = points[index], c = points[(index + 1) % points.count]
                if distance(a, c) <= epsilon || pointSegmentDistance(b, a, c) <= epsilon {
                    // Do not remove neighboring vertices simultaneously: a
                    // very finely flattened straight run must keep endpoints.
                    let previous = (index + points.count - 1) % points.count
                    let next = (index + 1) % points.count
                    if !remove.contains(previous), !remove.contains(next) { remove.insert(index) }
                }
            }
            if !remove.isEmpty {
                points = points.enumerated().compactMap { remove.contains($0.offset) ? nil : $0.element }
                changed = true
            }
        }
        return points
    }

    private static func isStraight(_ path: CGPath) -> Bool {
        var lines = 0, other = false
        path.applyWithBlock { pointer in
            switch pointer.pointee.type {
            case .moveToPoint: break
            case .addLineToPoint: lines += 1
            default: other = true
            }
        }
        return lines == 1 && !other
    }

    private static func hasSelfIntersection(_ points: [CGPoint]) -> Bool {
        let n = points.count
        guard n >= 3 else { return true }
        for i in 0..<n {
            let a = points[i], b = points[(i + 1) % n]
            if distance(a, b) <= 1e-9 { return true }
            let c = points[(i + 2) % n]
            let ab = unit(b - a), bc = unit(c - b)
            if abs(cross(ab, bc)) < 1e-9 && dot(ab, bc) < -0.999999 { return true }
            for j in (i + 1)..<n {
                if j == i + 1 || (i == 0 && j == n - 1) { continue }
                let c = points[j], d = points[(j + 1) % n]
                if segmentsIntersect(a, b, c, d) { return true }
            }
        }
        return false
    }

    private static func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        let e = topologyTolerance
        guard max(a.x, b.x) + e >= min(c.x, d.x), max(c.x, d.x) + e >= min(a.x, b.x),
              max(a.y, b.y) + e >= min(c.y, d.y), max(c.y, d.y) + e >= min(a.y, b.y) else { return false }
        let ab = b - a, cd = d - c
        let ca = cross(ab, c - a), da = cross(ab, d - a)
        let ac = cross(cd, a - c), bc = cross(cd, b - c)
        if ca * da < 0 && ac * bc < 0 { return true }
        return pointSegmentDistance(a, c, d) <= e || pointSegmentDistance(b, c, d) <= e ||
            pointSegmentDistance(c, a, b) <= e || pointSegmentDistance(d, a, b) <= e
    }

    private static func pointSegmentDistance(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let direction = b - a, squared = dot(direction, direction)
        let t = squared > 0 ? min(1, max(0, dot(point - a, direction) / squared)) : 0
        return distance(point, a + direction * t)
    }
    private static func lineIntersection(_ p: CGPoint, _ d: CGPoint, _ q: CGPoint, _ e: CGPoint) -> CGPoint? {
        let denominator = cross(d, e)
        guard abs(denominator) > 1e-10 else { return nil }
        let result = p + d * (cross(q - p, e) / denominator)
        return result.x.isFinite && result.y.isFinite ? result : nil
    }
    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3, let anchor = points.first else { return 0 }
        return points.indices.reduce(0) { result, index in
            result + cross(points[index] - anchor, points[(index + 1) % points.count] - anchor)
        } / 2
    }
    private static func finite(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
    }
    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
    private static func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.y - a.y * b.x }
    private static func leftNormal(_ p: CGPoint) -> CGPoint { CGPoint(x: -p.y, y: p.x) }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func unit(_ p: CGPoint) -> CGPoint { let l = hypot(p.x, p.y); return l > 0 ? p * (1 / l) : .zero }
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, b: CGFloat) -> CGPoint { CGPoint(x: a.x * b, y: a.y * b) }
}
