import Foundation
import CoreGraphics

@main
struct ManufacturingMarkRegression {
    static func panel(_ name: String, _ points: [GarmentCodePoint]) -> GarmentCodePanelGeometry {
        .init(id: name, edges: points.indices.map { index in
            GarmentCodeGeometryEdge(id: "\(name)-\(index)", start: points[index], end: points[(index + 1) % points.count])
        })
    }
    static func rectangle(_ name: String, width: Double = 10, height: Double = 20) -> GarmentCodePanelGeometry {
        panel(name, [.zero, .init(x: width, y: 0), .init(x: width, y: height), .init(x: 0, y: height)])
    }
    static func path(_ panel: GarmentCodePanelGeometry) -> CGPath {
        let result = CGMutablePath()
        result.move(to: CGPoint(x: panel.edges[0].start.x, y: panel.edges[0].start.y))
        for edge in panel.edges {
            if let curve = edge.curvature, curve.type == "quadratic", let control = curve.params?.first {
                let chord = edge.end - edge.start
                let point = edge.start + chord * control[0] + chord.leftNormal * control[1]
                result.addQuadCurve(to: CGPoint(x: edge.end.x, y: edge.end.y), control: CGPoint(x: point.x, y: point.y))
            } else {
                result.addLine(to: CGPoint(x: edge.end.x, y: edge.end.y))
            }
        }
        result.closeSubpath()
        return result
    }
    static func lines(_ path: CGPath) -> [(CGPoint, CGPoint)] {
        var previous: CGPoint?, result: [(CGPoint, CGPoint)] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .moveToPoint { previous = element.points[0] }
            if element.type == .addLineToPoint, let prior = previous {
                result.append((prior, element.points[0])); previous = element.points[0]
            }
        }
        return result
    }
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-5) {
        precondition(abs(a - b) <= tolerance, "Expected \(a) ~= \(b)")
    }
    static func reject(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("Invalid mark placement was accepted") } catch {}
    }
    static func main() throws {
        let a = rectangle("front"), b = rectangle("back")
        let geometry = [a.id: a, b.id: b]
        let seam = GarmentCodeStitch(sides: [.init(panel: a.id, edge: 0), .init(panel: b.id, edge: 0)])
        func build(_ panel: GarmentCodePanelGeometry, _ settings: GarmentCodeDraftingSettings,
                   stitches: [GarmentCodeStitch] = [],
                   geometry: [String: GarmentCodePanelGeometry]? = nil,
                   cut: CGPath? = nil) throws -> GarmentCodeManufacturingMarks.Result {
            let result = try GarmentCodeManufacturingMarks.build(panelName: panel.id, panel: panel, seamPath: path(panel),
                cutPath: cut, settings: settings, geometry: geometry ?? [panel.id: panel], stitches: stitches)
            precondition(result.paths.count == result.labels.count,
                         "Mark paths and labels must remain paired for whole-document filtering")
            return result
        }
        let off = try build(a, .init())
        precondition(off.paths.isEmpty && off.labels.isEmpty && off.warnings.isEmpty,
                     "Grain and notches must never be inferred or enabled silently")

        var grain = GarmentCodeDraftingSettings()
        grain.panels[a.id] = .init(grainline: .init())
        let vertical = try build(a, grain)
        precondition(vertical.paths.count == 1 && vertical.labels.first?.text == "布纹方向（手动）")
        let spine = lines(vertical.paths[0])[0]
        near(spine.0.x, 5); near(spine.1.x, 5)
        near(spine.0.y, 4); near(spine.1.y, 16)
        for line in lines(vertical.paths[0]) {
            precondition(path(a).contains(line.0) && path(a).contains(line.1), "Grain arrows escaped the piece")
        }
        grain.panels[a.id]?.grainline?.angleDegrees = 45
        let diagonal = try build(a, grain)
        let diagonalLine = lines(diagonal.paths[0])[0]
        near(diagonalLine.1.x - diagonalLine.0.x, diagonalLine.1.y - diagonalLine.0.y)
        grain.panels[a.id]?.grainline?.centerXRatio = 0
        reject { _ = try build(a, grain) }
        let u = panel("u", [.zero, .init(x: 10, y: 0), .init(x: 10, y: 10), .init(x: 7, y: 10),
                            .init(x: 7, y: 3), .init(x: 3, y: 3), .init(x: 3, y: 10), .init(x: 0, y: 10)])
        var inNotch = GarmentCodeDraftingSettings(); inNotch.panels[u.id] = .init(grainline: .init())
        reject { _ = try build(u, inNotch) }
        let thin = rectangle("thin", width: 0.1, height: 4)
        var thinGrain = GarmentCodeDraftingSettings(); thinGrain.panels[thin.id] = .init(grainline: .init())
        reject { _ = try build(thin, thinGrain) }

        var fold = GarmentCodeDraftingSettings()
        fold.setTreatment(.init(kind: .fold), panel: a.id, edge: 0)
        let folded = try build(a, fold)
        precondition(folded.paths.count == 1 && folded.labels.first?.text == "对折边")
        precondition(lines(folded.paths[0]).allSatisfy { $0.0.y >= -1e-10 && $0.1.y >= -1e-10 })
        reject { _ = try build(a, fold, stitches: [seam], geometry: geometry) }
        var curved = a
        curved.edges[0].curvature = .init(type: "quadratic", params: [[0.5, 0]])
        reject { _ = try build(curved, fold) }

        var notches = GarmentCodeDraftingSettings(); notches.showNotches = true
        let nA = try build(a, notches, stitches: [seam], geometry: geometry)
        let nB = try build(b, notches, stitches: [seam], geometry: geometry)
        precondition(nA.paths.count == 2 && nB.paths.count == 2)
        near(nA.labels.first { $0.text == "缝1·单" }!.point.x, 10 / 3)
        near(nA.labels.first { $0.text == "缝1·双" }!.point.x, 20 / 3)
        near(nB.labels.first { $0.text == "缝1·单" }!.point.x, 20 / 3)
        near(nB.labels.first { $0.text == "缝1·双" }!.point.x, 10 / 3)
        precondition(lines(nA.paths[0]).count == 1 && lines(nA.paths[1]).count == 2,
                     "Single/double identifiers must remain distinguishable")
        for line in nA.paths.flatMap(lines) {
            near(line.0.y, 0); near(line.1.y, -0.25)
            precondition(!path(a).contains(line.1), "Zero-width transfer mark cut into the original body")
        }
        precondition(nA.warnings.contains { $0.contains("不得") })
        let rightWrong = GarmentCodeStitch(sides: seam.sides, rightWrong: true)
        let same = try build(b, notches, stitches: [rightWrong], geometry: geometry)
        near(same.labels.first { $0.text == "缝1·单" }!.point.x, 10 / 3)
        near(same.labels.first { $0.text == "缝1·双" }!.point.x, 20 / 3)

        var withAllowance = notches; withAllowance.addSeamAllowance = true
        let cut = CGPath(rect: CGRect(x: -1, y: -1, width: 12, height: 22), transform: nil)
        let sewn = try build(a, withAllowance, stitches: [seam], geometry: geometry, cut: cut)
        precondition(sewn.paths.count == 2)
        for line in sewn.paths.flatMap(lines) {
            near(line.0.y, -1); near(line.1.y, -0.75)
            precondition(abs(line.0.y - line.1.y) <= withAllowance.standardAllowanceCM / 2)
            precondition(!path(a).contains(line.1) && cut.contains(line.1))
        }

        let longer = rectangle("back", width: 12)
        let mismatched = try build(a, notches, stitches: [seam], geometry: [a.id: a, longer.id: longer])
        precondition(mismatched.paths.isEmpty && mismatched.warnings.contains { $0.contains("不等长") })
        let dart = GarmentCodeStitch(sides: [.init(panel: a.id, edge: 0), .init(panel: a.id, edge: 2)])
        let darts = try build(a, notches, stitches: [dart])
        precondition(darts.paths.isEmpty && darts.warnings.contains { $0.contains("省道") })
        let c = rectangle("third")
        let shared = GarmentCodeStitch(sides: [.init(panel: a.id, edge: 0), .init(panel: c.id, edge: 0)])
        let repeated = try build(a, notches, stitches: [seam, shared], geometry: [a.id: a, b.id: b, c.id: c])
        precondition(repeated.paths.isEmpty && repeated.warnings.contains { $0.contains("共边") })

        // A straight Bezier can have nonlinear parameter speed. At t=1/3
        // this control yields x=1.56, so x=3.33 proves arc-length placement.
        var nonlinear = a
        nonlinear.edges[0].curvature = .init(type: "quadratic", params: [[0.1, 0]])
        let arcMapped = try build(nonlinear, notches, stitches: [seam], geometry: [a.id: nonlinear, b.id: b])
        near(arcMapped.labels.first { $0.text == "缝1·单" }!.point.x, 10 / 3, 0.001)

        let clockwise = panel("cw", [.zero, .init(x: 0, y: 20), .init(x: 10, y: 20), .init(x: 10, y: 0)])
        let cwPair = GarmentCodeStitch(sides: [.init(panel: clockwise.id, edge: 3), .init(panel: b.id, edge: 0)])
        let cw = try build(clockwise, notches, stitches: [cwPair], geometry: [clockwise.id: clockwise, b.id: b])
        precondition(cw.paths.flatMap(lines).allSatisfy { $0.1.y < 0 }, "Clockwise winding reversed the outward marks")

        let document = try GarmentCodePatternFile(geometry: geometry, stitches: [seam])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(document)
        _ = try build(a, withAllowance, stitches: document.pattern.stitches, geometry: geometry, cut: cut)
        let after = try encoder.encode(document)
        precondition(after == original, "Manufacturing guides changed official JSON")
        print("PASS: optional manual grain and inside arrows; fold safety; paired arc-length single/double marks, right/wrong orientation, zero/positive allowance safety, unequal/dart/shared-edge warnings and unchanged JSON")
    }
}
