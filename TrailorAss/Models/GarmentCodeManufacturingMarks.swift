import Foundation
import CoreGraphics

/// Optional sewing guides, kept entirely outside the official garment model.
/// Paths are in the input panel's local centimetres, with positive y upwards.
enum GarmentCodeManufacturingMarks {
    struct Label {
        let text: String
        let point: CGPoint
    }
    struct Result {
        let paths: [CGPath]
        let labels: [Label]
        let warnings: [String]
    }
    enum MarkError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { switch self { case let .invalid(message): message } }
    }

    static func build(panelName: String, panel: GarmentCodePanelGeometry,
                      seamPath: CGPath, cutPath: CGPath?, settings: GarmentCodeDraftingSettings,
                      geometry: [String: GarmentCodePanelGeometry], stitches: [GarmentCodeStitch]) throws -> Result {
        let boundary = try segments(seamPath)
        let area = boundary.reduce(0.0) { $0 + cross($1.a, $1.b) } / 2
        guard area.isFinite, abs(area) > 1e-9 else { throw MarkError.invalid("裁片轮廓退化，无法放置制作标记。") }
        let name = GarmentCodeChinese.panel(panelName)
        let guide = GarmentCodeSeamGuide(stitches: stitches)
        var paths: [CGPath] = [], labels: [Label] = [], warnings: [String] = []

        if let grain = settings.panelSettings(panelName).grainline {
            guard [grain.angleDegrees, grain.centerXRatio, grain.centerYRatio, grain.lengthRatio].allSatisfy(\.isFinite),
                  (-180...180).contains(grain.angleDegrees), (0...1).contains(grain.centerXRatio),
                  (0...1).contains(grain.centerYRatio), (0.1...0.9).contains(grain.lengthRatio) else {
                throw MarkError.invalid("“\(name)”的布纹线设置无效，请检查角度、位置和长度。")
            }
            let bounds = seamPath.boundingBoxOfPath
            let center = V(x: bounds.minX + bounds.width * grain.centerXRatio,
                           y: bounds.minY + bounds.height * grain.centerYRatio)
            guard inside(center, path: seamPath, boundary: boundary, clearance: 0.04) else {
                throw MarkError.invalid("“\(name)”的布纹线中心不在片身安全区域内，请调整横向或纵向位置，避开省口。")
            }
            let angle = grain.angleDegrees * .pi / 180
            let direction = V(x: cos(angle), y: sin(angle)), normal = direction.left
            let forward = rayDistances(center, direction, boundary).filter { $0 > 1e-6 }.min()
            let backward = rayDistances(center, direction * -1, boundary).filter { $0 > 1e-6 }.min()
            guard let forward, let backward else {
                throw MarkError.invalid("“\(name)”的布纹线无法在片身内完整放置，请调整位置或角度。")
            }
            let half = min(forward, backward) * grain.lengthRatio
            guard half >= 0.5 else {
                throw MarkError.invalid("“\(name)”的布纹线可用空间不足，请调整位置、角度或长度比例。")
            }
            let a = center - direction * half, b = center + direction * half
            let head = min(0.5, half * 0.3), side = min(0.18, head * 0.4)
            let strokes: [Segment] = [
                .init(a: a, b: b),
                .init(a: a, b: a + direction * head + normal * side),
                .init(a: a, b: a + direction * head - normal * side),
                .init(a: b, b: b - direction * head + normal * side),
                .init(a: b, b: b - direction * head - normal * side)
            ]
            guard strokes.allSatisfy({ safe($0, path: seamPath, boundary: boundary, clearance: 0.025) }) else {
                throw MarkError.invalid("“\(name)”的布纹箭头靠近边界或省口，请调整位置、角度或缩短布纹线。")
            }
            paths.append(makePath(strokes))
            let label = center + normal * 0.45
            labels.append(.init(text: "布纹方向（手动）", point: (inside(label, path: seamPath, boundary: boundary) ? label : center).cg))
        }

        for (index, edge) in panel.edges.enumerated() {
            let treatment = settings.treatment(panel: panelName, edge: index, stitches: stitches)
            guard treatment.kind == .fold else { continue }
            guard edge.curvature == nil,
                  guide.groups(for: .init(panel: panelName, edge: index)).isEmpty else {
                throw MarkError.invalid("“\(name)”第 \(index + 1) 边不能作为对折边；仅可选择未缝合的直边。")
            }
            let direction = V(edge.end - edge.start).unit
            let inward = direction.left * (area > 0 ? 1 : -1)
            var fold: [Segment] = []
            for fraction in [0.25, 0.75] {
                let tip = V(edge.point(at: fraction))
                let base = tip + inward * 0.65
                let left = tip + inward * 0.22 + direction * 0.12
                let right = tip + inward * 0.22 - direction * 0.12
                guard inside(base, path: seamPath, boundary: boundary),
                      inside(left, path: seamPath, boundary: boundary),
                      inside(right, path: seamPath, boundary: boundary) else { continue }
                fold += [.init(a: base, b: tip), .init(a: tip, b: left), .init(a: tip, b: right)]
            }
            if fold.isEmpty {
                warnings.append("“\(name)”第 \(index + 1) 边对折标记空间不足，请人工标注。")
            } else {
                paths.append(makePath(fold))
                let point = V(edge.point(at: 0.5)) + inward * 0.6
                labels.append(.init(text: "对折边", point: point.cg))
            }
        }

        if settings.showNotches {
            let cutBoundary = try cutPath.map { try segments($0) }
            for group in guide.groups(forPanel: panelName) {
                guard group.sides.count == 2 else { throw MarkError.invalid("接缝引用不完整，无法生成定位标记。") }
                let first = group.sides[0], second = group.sides[1]
                guard first.panel != second.panel else {
                    warnings.append("接缝 \(group.number) 为同片省道，未自动生成定位剪口；省道需人工确认。")
                    continue
                }
                guard group.sides.allSatisfy({ guide.groups(for: $0).count == 1 }) else {
                    warnings.append("接缝 \(group.number) 存在共边多组引用，未自动生成定位标记。")
                    continue
                }
                guard let sourceA = geometry[first.panel], let sourceB = geometry[second.panel],
                      sourceA.edges.indices.contains(first.edge), sourceB.edges.indices.contains(second.edge) else {
                    throw MarkError.invalid("接缝引用无效，无法生成定位标记。")
                }
                let lengthA = sourceA.edges[first.edge].length(), lengthB = sourceB.edges[second.edge].length()
                guard lengthA.isFinite, lengthB.isFinite, min(lengthA, lengthB) > 1e-8 else {
                    throw MarkError.invalid("接缝边长度无效，无法生成定位标记。")
                }
                guard abs(lengthA - lengthB) <= 0.05 + 1e-9 else {
                    warnings.append("接缝 \(group.number) 两边不等长（可能含抽褶或吃势），未自动生成刀口，需人工确认。")
                    continue
                }
                guard let sideIndex = group.sides.firstIndex(where: { $0.panel == panelName }) else { continue }
                let side = group.sides[sideIndex]
                guard panel.edges.indices.contains(side.edge) else { throw MarkError.invalid("当前裁片接缝引用无效。") }
                let edge = panel.edges[side.edge]
                let table = try ArcTable(edge)
                let treatment = settings.treatment(panel: panelName, edge: side.edge, stitches: stitches)
                let width = settings.addSeamAllowance ? settings.widthCM(for: treatment) : 0
                guard width.isFinite, (0...5).contains(width) else { throw MarkError.invalid("定位边的缝份宽度无效。") }
                let positive = width > 1e-6
                if positive && cutBoundary == nil {
                    warnings.append("接缝 \(group.number) 尚无有效裁剪线，未生成定位剪口。")
                    continue
                }
                var marked = false
                for ordinal in [1, 2] {
                    var fraction = Double(ordinal) / 3
                    // Pinned GarmentCode boxmeshgen.py:655/802 reverses one
                    // vertex range for ordinary right-to-right stitching.
                    if sideIndex == 1 && !group.rightWrong { fraction = 1 - fraction }
                    let offsets = ordinal == 1 ? [0.0] : [-0.10 / table.total, 0.10 / table.total]
                    var ticks: [Segment] = [], anchors: [V] = []
                    for offset in offsets {
                        let value = table.location(at: min(0.98, max(0.02, fraction + offset)))
                        let outward = value.tangent.left * (area > 0 ? -1 : 1)
                        if positive, let cutPath, let cutBoundary {
                            guard let distance = rayDistances(value.point, outward, cutBoundary)
                                .filter({ $0 > 1e-5 }).min(), distance <= max(0.1, width * 4) else { continue }
                            let tip = value.point + outward * distance
                            let depth = min(0.25, width / 2, distance / 2)
                            guard depth > 1e-4 else { continue }
                            let end = tip - outward * depth
                            guard !inside(end, path: seamPath, boundary: boundary),
                                  cutPath.contains(end.cg, using: .winding) else { continue }
                            ticks.append(.init(a: tip, b: end)); anchors.append(tip + outward * 0.4)
                        } else {
                            let end = value.point + outward * 0.25
                            // Zero allowance is a transfer/reference mark only;
                            // never draw a cut into the original piece body.
                            let tick = Segment(a: value.point, b: end)
                            guard (1...10).allSatisfy({ step in
                                !seamPath.contains((tick.a + (tick.b - tick.a) * (Double(step) / 10)).cg, using: .winding)
                            }) else { continue }
                            ticks.append(tick); anchors.append(end + outward * 0.2)
                        }
                    }
                    guard ticks.count == offsets.count else {
                        warnings.append("接缝 \(group.number) 局部轮廓过窄或转角受限，部分定位标记未生成，请人工确认。")
                        continue
                    }
                    paths.append(makePath(ticks))
                    let anchor = anchors.reduce(.zero) { $0 + $1 } * (1 / Double(anchors.count))
                    labels.append(.init(text: "缝\(group.number)·\(ordinal == 1 ? "单" : "双")", point: anchor.cg))
                    marked = true
                }
                if marked && !positive {
                    warnings.append("接缝 \(group.number) 未加缝份，仅显示外向定位线；不得沿记号剪入原始片身。")
                }
            }
            warnings.append("定位记号仅作缝合参考，不挖除裁片轮廓；下刀前请人工核对配对关系及深度。")
        }
        var seen: Set<String> = []
        return Result(paths: paths, labels: labels, warnings: warnings.filter { seen.insert($0).inserted })
    }

    private struct V {
        var x: Double, y: Double
        init(x: Double, y: Double) { self.x = x; self.y = y }
        init(_ point: GarmentCodePoint) { x = point.x; y = point.y }
        init(_ point: CGPoint) { x = point.x; y = point.y }
        static let zero = V(x: 0, y: 0)
        static func + (a: V, b: V) -> V { V(x: a.x + b.x, y: a.y + b.y) }
        static func - (a: V, b: V) -> V { V(x: a.x - b.x, y: a.y - b.y) }
        static func * (a: V, b: Double) -> V { V(x: a.x * b, y: a.y * b) }
        var length: Double { hypot(x, y) }
        var unit: V { length > 1e-12 ? V(x: x / length, y: y / length) : .zero }
        var left: V { V(x: -y, y: x) }
        var cg: CGPoint { CGPoint(x: x, y: y) }
        func dot(_ b: V) -> Double { x * b.x + y * b.y }
    }
    private struct Segment { let a: V, b: V }
    private static func cross(_ a: V, _ b: V) -> Double { a.x * b.y - a.y * b.x }

    private static func segments(_ source: CGPath) throws -> [Segment] {
        var result: [Segment] = [], start: V?, previous: V?, finite = true
        source.flattened(threshold: 0.002).applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                let point = V(element.points[0]); start = point; previous = point
            case .addLineToPoint:
                let point = V(element.points[0])
                if let previous, (point - previous).length > 1e-10 { result.append(.init(a: previous, b: point)) }
                previous = point
            case .closeSubpath:
                if let previous, let start, (start - previous).length > 1e-10 { result.append(.init(a: previous, b: start)) }
                previous = start
            default: finite = false
            }
            if let previous, !previous.x.isFinite || !previous.y.isFinite { finite = false }
        }
        guard finite, !result.isEmpty, result.count <= 100_000 else {
            throw MarkError.invalid("裁片路径无效或过于复杂，无法生成制作标记。")
        }
        return result
    }

    private static func makePath(_ segments: [Segment]) -> CGPath {
        let path = CGMutablePath()
        for segment in segments { path.move(to: segment.a.cg); path.addLine(to: segment.b.cg) }
        return path
    }

    private static func rayDistances(_ origin: V, _ direction: V, _ boundary: [Segment]) -> [Double] {
        boundary.compactMap { segment in
            let edge = segment.b - segment.a, denominator = cross(direction, edge)
            guard abs(denominator) > 1e-12 else { return nil }
            let offset = segment.a - origin
            let t = cross(offset, edge) / denominator, u = cross(offset, direction) / denominator
            return t.isFinite && u >= -1e-9 && u <= 1 + 1e-9 ? t : nil
        }
    }

    private static func distance(_ point: V, to segment: Segment) -> Double {
        let vector = segment.b - segment.a, square = vector.dot(vector)
        guard square > 1e-20 else { return (point - segment.a).length }
        let t = min(1, max(0, (point - segment.a).dot(vector) / square))
        return (point - (segment.a + vector * t)).length
    }

    private static func inside(_ point: V, path: CGPath, boundary: [Segment], clearance: Double = 0) -> Bool {
        guard path.contains(point.cg, using: .winding) else { return false }
        return clearance == 0 || boundary.allSatisfy { distance(point, to: $0) >= clearance }
    }

    private static func safe(_ segment: Segment, path: CGPath, boundary: [Segment], clearance: Double) -> Bool {
        (0...32).allSatisfy { step in
            inside(segment.a + (segment.b - segment.a) * (Double(step) / 32),
                   path: path, boundary: boundary, clearance: clearance)
        }
    }

    /// An arc-length lookup table, not parameter-fraction placement. A minimum
    /// 128 samples also handles collinear Beziers with nonuniform parameter speed.
    private struct ArcTable {
        let edge: GarmentCodeGeometryEdge
        let points: [V]
        let cumulative: [Double]
        let total: Double
        init(_ edge: GarmentCodeGeometryEdge) throws {
            let length = edge.length()
            guard length.isFinite, length > 1e-9 else { throw MarkError.invalid("接缝曲线长度无效。") }
            let count = Int(min(4096, max(128, ceil(length / 0.05))))
            let points = (0...count).map { V(edge.point(at: Double($0) / Double(count))) }
            var cumulative = [0.0]
            for (a, b) in zip(points, points.dropFirst()) { cumulative.append(cumulative.last! + (b - a).length) }
            guard let total = cumulative.last, total.isFinite, total > 1e-9,
                  points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw MarkError.invalid("接缝曲线无效。") }
            self.edge = edge; self.points = points; self.cumulative = cumulative; self.total = total
        }
        func location(at fraction: Double) -> (point: V, tangent: V) {
            let distance = min(1, max(0, fraction)) * total
            var lower = 0, upper = cumulative.count - 1
            while lower + 1 < upper {
                let middle = (lower + upper) / 2
                if cumulative[middle] < distance { lower = middle } else { upper = middle }
            }
            let length = cumulative[upper] - cumulative[lower]
            let local = length > 1e-12 ? (distance - cumulative[lower]) / length : 0
            let parameter = (Double(lower) + local) / Double(points.count - 1)
            let delta = 0.0001
            var tangent = V(edge.point(at: min(1, parameter + delta)) - edge.point(at: max(0, parameter - delta))).unit
            if tangent.length < 1e-9 { tangent = (points[upper] - points[lower]).unit }
            return (V(edge.point(at: parameter)), tangent)
        }
    }
}
