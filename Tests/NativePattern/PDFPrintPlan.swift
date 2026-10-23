import Foundation
import CoreGraphics

@main
struct PDFPrintPlanRegression {
    static func main() throws {
        func close(_ actual: Double, _ expected: Double, _ epsilon: Double = 1e-8) {
            precondition(actual.isFinite && abs(actual - expected) <= epsilon,
                         "Expected \(expected), got \(actual)")
        }
        func reject(_ body: () throws -> Void) {
            do { try body(); preconditionFailure("Expected invalid print input to fail") }
            catch { }
        }
        func flattened(_ path: CGPath) -> [CGPoint] {
            var result: [CGPoint] = []
            var current = CGPoint.zero
            path.applyWithBlock { pointer in
                let element = pointer.pointee
                switch element.type {
                case .moveToPoint:
                    current = element.points[0]
                    result.append(current)
                case .addLineToPoint:
                    current = element.points[0]
                    result.append(current)
                case .addQuadCurveToPoint:
                    let start = current, control = element.points[0], end = element.points[1]
                    for i in 1...1024 {
                        let t = Double(i) / 1024, u = 1 - t
                        result.append(CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                              y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
                    }
                    current = end
                case .addCurveToPoint:
                    let start = current, c1 = element.points[0], c2 = element.points[1], end = element.points[2]
                    for i in 1...1024 {
                        let t = Double(i) / 1024, u = 1 - t
                        result.append(CGPoint(
                            x: u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                            y: u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y))
                    }
                    current = end
                case .closeSubpath: break
                @unknown default: preconditionFailure("Unknown path operation")
                }
            }
            return result
        }
        func distance(_ p: CGPoint, toPolyline points: [CGPoint]) -> Double {
            zip(points, points.dropFirst()).map { a, b in
                let dx = b.x - a.x, dy = b.y - a.y
                let squared = dx * dx + dy * dy
                let t = squared > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared)) : 0
                return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
            }.min() ?? .infinity
        }
        func polygon(_ vertices: [[Double]], firstCurve: GarmentCodeCurvature? = nil) -> GarmentCodePanel {
            .init(vertices: vertices, edges: vertices.indices.map { index in
                .init(endpoints: [index, (index + 1) % vertices.count], label: nil,
                      curvature: index == 0 ? firstCurve : nil)
            }, label: nil)
        }
        func rectangle(_ width: Double = 10, _ height: Double = 10,
                       x: Double = 0, y: Double = 0) -> GarmentCodePanel {
            polygon([[x, y], [x + width, y], [x + width, y + height], [x, y + height]])
        }
        func document(_ panels: [String: GarmentCodePanel], order: [String]? = nil,
                      units: Double = 100, absolute: Bool = false) -> GarmentCodePatternFile {
            .init(pattern: .init(panels: panels, stitches: [], panelOrder: order),
                  properties: ["units_in_meter": .number(units),
                               "curvature_coords": .string(absolute ? "absolute" : "relative")])
        }
        func verifyCoverage(_ plan: GarmentCodePrintPlan) {
            precondition(!plan.tiles.isEmpty && plan.tiles.count == plan.columns * plan.rows)
            precondition(plan.tiles.map(\.id) == Array(1...plan.tiles.count))
            let last = plan.tiles.last!
            precondition(last.boardRectCM.maxX >= plan.boardSizeCM.width - 1e-8)
            precondition(last.boardRectCM.maxY >= plan.boardSizeCM.height - 1e-8)
            for tile in plan.tiles {
                precondition(tile.id == tile.row * plan.columns + tile.column + 1)
                close(tile.boardRectCM.width, 19)
                close(tile.boardRectCM.height, 26.7)
                close(tile.boardRectCM.minX, Double(tile.column) * 18)
                close(tile.boardRectCM.minY, Double(tile.row) * 25.7)
                if tile.column + 1 < plan.columns {
                    let next = plan.tiles[tile.id]
                    close(tile.boardRectCM.intersection(next.boardRectCM).width, 1)
                    // A shared board point has the same physical location after
                    // undoing each page's origin and tile translation.
                    let p = CGPoint(x: next.boardRectCM.minX + 0.5, y: tile.boardRectCM.minY + 4)
                    let localA = CGPoint(x: p.x - tile.boardRectCM.minX + 1, y: p.y - tile.boardRectCM.minY + 1.5)
                    let localB = CGPoint(x: p.x - next.boardRectCM.minX + 1, y: p.y - next.boardRectCM.minY + 1.5)
                    close(localA.x - 1 + tile.boardRectCM.minX, localB.x - 1 + next.boardRectCM.minX)
                    close(localA.y - 1.5 + tile.boardRectCM.minY, localB.y - 1.5 + next.boardRectCM.minY)
                }
                if tile.row + 1 < plan.rows {
                    let next = plan.tiles[tile.id - 1 + plan.columns]
                    close(tile.boardRectCM.intersection(next.boardRectCM).height, 1)
                }
            }
            let board = CGRect(origin: .zero, size: plan.boardSizeCM)
            let calibration = CGRect(x: 1, y: 3, width: 12, height: 14)
            precondition(board.contains(calibration))
            for (index, panel) in plan.panels.enumerated() {
                precondition(board.contains(panel.boundsCM) && board.contains(panel.labelRectCM))
                precondition(!panel.boundsCM.intersects(panel.labelRectCM))
                let slot = panel.boundsCM.union(panel.labelRectCM)
                precondition(!slot.intersects(calibration))
                for other in plan.panels.dropFirst(index + 1) {
                    precondition(!slot.intersects(other.boundsCM.union(other.labelRectCM)),
                                 "Panel/label print slots must not overlap")
                }
                precondition(panel.edgePathsCM.count == panel.edgeMidpointsCM.count)
            }
        }

        let square = try GarmentCodePrintPlan(document: document(["square": rectangle()]))
        close(square.panels[0].boundsCM.width, 10)
        close(square.panels[0].boundsCM.height, 10)
        close(GarmentCodePrintPlan.pointsPerCM * 2.54, 72)
        close(square.panels[0].boundsCM.width * GarmentCodePrintPlan.pointsPerCM, 283.46456692913387)
        close(GarmentCodePrintPlan.tilePageOriginCM.x * 2 + GarmentCodePrintPlan.tileWindowSizeCM.width,
              GarmentCodePrintPlan.a4SizeCM.width)
        close(GarmentCodePrintPlan.tilePageOriginCM.y * 2 + GarmentCodePrintPlan.tileWindowSizeCM.height,
              GarmentCodePrintPlan.a4SizeCM.height)
        verifyCoverage(square)

        let millimetres = try GarmentCodePrintPlan(document: document(
            ["square": rectangle(100, 100, x: -170, y: -230)], units: 1000))
        close(millimetres.panels[0].boundsCM.width, 10)
        close(millimetres.panels[0].boundsCM.height, 10)
        close(millimetres.panels[0].boundsCM.minX, square.panels[0].boundsCM.minX)
        close(millimetres.panels[0].boundsCM.minY, square.panels[0].boundsCM.minY)

        let ordered = try GarmentCodePrintPlan(document: document(
            ["a": rectangle(), "b": rectangle(3, 8), "c": rectangle(35, 40)],
            order: ["c", "c", "missing", "b"]))
        precondition(ordered.panels.map(\.name) == ["c", "b", "a"])
        verifyCoverage(ordered)

        // Exact Bezier extrema, not endpoint-only bounds or the preview's
        // coarse samples. CoreGraphics retains the native curve commands.
        let quadratic = polygon([[0, 0], [10, 0]],
                                firstCurve: .init(type: "quadratic", params: [[0.5, 1]]))
        let cubic = polygon([[0, 0], [10, 0]],
                            firstCurve: .init(type: "cubic", params: [[0, 1], [1, -1]]))
        let curves = try GarmentCodePrintPlan(document: document(["quad": quadratic, "cubic": cubic]))
        let q = curves.panels.first { $0.name == "quad" }!
        let c = curves.panels.first { $0.name == "cubic" }!
        close(q.boundsCM.width, 10)
        close(q.boundsCM.height, 5)
        close(c.boundsCM.width, 10)
        close(c.boundsCM.height, 10 / sqrt(3))
        var quadCommands = 0, cubicCommands = 0
        q.edgePathsCM[0].applyWithBlock { if $0.pointee.type == .addQuadCurveToPoint { quadCommands += 1 } }
        c.edgePathsCM[0].applyWithBlock { if $0.pointee.type == .addCurveToPoint { cubicCommands += 1 } }
        precondition(quadCommands == 1 && cubicCommands == 1)
        for (name, source) in [("quad", quadratic), ("cubic", cubic)] {
            let panel = curves.panels.first { $0.name == name }!
            let curve = try document([name: source]).geometryPanels()[name]!.edges[0]
            let rendered = flattened(panel.edgePathsCM[0])
            let first = rendered.first!, last = rendered.last!
            close(last.x - first.x, 10)
            close(last.y - first.y, 0)
            for i in 0...100 {
                let point = curve.point(at: Double(i) / 100)
                let expected = CGPoint(x: first.x + point.x, y: first.y - point.y)
                precondition(distance(expected, toPolyline: rendered) < 3e-5,
                             "Bezier vector controls or y-reflection differ from source geometry")
            }
            let middle = curve.point(at: 0.5)
            close(panel.edgeMidpointsCM[0].x, first.x + middle.x)
            close(panel.edgeMidpointsCM[0].y, first.y - middle.y)
        }
        verifyCoverage(curves)

        // Absolute millimetre controls normalize to the same curve in cm.
        let absQuad = polygon([[-20, -30], [80, -30]],
                              firstCurve: .init(type: "quadratic", params: [[30, 70]]))
        let absolute = try GarmentCodePrintPlan(document: document(["quad": absQuad], units: 1000, absolute: true))
        close(absolute.panels[0].boundsCM.width, 10)
        close(absolute.panels[0].boundsCM.height, 5)

        var arcsChecked = 0
        var maximumArcPathError = 0.0
        for radius in [8.0, 3.0] {
          for large in [false, true] {
            for right in [false, true] {
                let arc = polygon([[0, 0], [10, 0]],
                    firstCurve: .init(circleRadius: radius, largeArc: large, right: right))
                let plan = try GarmentCodePrintPlan(document: document(["arc": arc]))
                let panel = plan.panels[0]
                var nativeCurves = 0
                panel.edgePathsCM[0].applyWithBlock {
                    if $0.pointee.type == .addCurveToPoint { nativeCurves += 1 }
                }
                precondition(nativeCurves >= 1, "Arcs must remain vector curves, not coarse polyline samples")
                if large && radius == 8 { close(panel.boundsCM.width, 16, 0.005) }
                else { close(panel.boundsCM.width, 10, 0.005) }
                let curve = try document(["arc": arc]).geometryPanels()["arc"]!.edges[0]
                let rendered = flattened(panel.edgePathsCM[0])
                let first = rendered.first!, last = rendered.last!
                close(last.x - first.x, 10)
                close(last.y - first.y, 0)
                let expectedMiddle = curve.point(at: 0.5)
                close(panel.edgeMidpointsCM[0].x, first.x + expectedMiddle.x)
                close(panel.edgeMidpointsCM[0].y, first.y - expectedMiddle.y)
                for i in 0...100 {
                    let expected = curve.point(at: Double(i) / 100)
                    let boardPoint = CGPoint(x: first.x + expected.x, y: first.y - expected.y)
                    let error = distance(boardPoint, toPolyline: rendered)
                    // PDF/CoreGraphics represent circles as native cubic arc
                    // segments; their standard small approximation is distinct
                    // from (and far finer than) the preview polyline sampler.
                    precondition(error < 0.003, "Arc sweep or y-reflection differs from model geometry: \(error) cm")
                    maximumArcPathError = max(maximumArcPathError, error)
                }
                verifyCoverage(plan)
                arcsChecked += 1
            }
          }
        }

        // Exact 37 cm board width is covered by two windows: 19 + 18.
        let exactBoundary = try GarmentCodePrintPlan(document: document(["boundary": rectangle(21, 1)]))
        close(exactBoundary.boardSizeCM.width, 37)
        precondition(exactBoundary.columns == 2 && exactBoundary.rows == 1)
        verifyCoverage(exactBoundary)
        let nearBoundary = try GarmentCodePrintPlan(document: document(["boundary": rectangle(21 + 1e-10, 1)]))
        precondition(nearBoundary.columns == 2, "Sub-nanometre rounding must not add a blank column")

        reject { _ = try GarmentCodePrintPlan(document: document([:])) }
        reject { _ = try GarmentCodePrintPlan(document: document(["flat": polygon([[0, 0], [10, 0]])])) }
        reject { _ = try GarmentCodePrintPlan(document: document(["nan": rectangle(.nan, 10)])) }
        reject { _ = try GarmentCodePrintPlan(document: document(["huge": rectangle(501, 10)])) }
        reject { _ = try GarmentCodePrintPlan(document: document(["overflow": rectangle()], units: 1e-300)) }
        reject {
            let hugeArc = polygon([[0, 0], [10, 0]],
                                  firstCurve: .init(circleRadius: 1e200, largeArc: true, right: true))
            _ = try GarmentCodePrintPlan(document: document(["arc": hugeArc]))
        }
        do {
            _ = try GarmentCodePrintPlan(document: document(["many-pages": rectangle(480, 450)]))
            preconditionFailure("Expected page safety limit")
        } catch GarmentCodePrintPlan.PrintError.tooManyPages { }

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var fixtures = 0
        for name in ["shirt.json", "fitted-shirt.json", "pants.json", "pencil-skirt.json"] {
            let source = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                root.appendingPathComponent("Fixtures/\(name)")))
            let before = try encoder.encode(source)
            let plan = try GarmentCodePrintPlan(document: source)
            precondition(plan.panels.count == source.pattern.panels.count)
            verifyCoverage(plan)
            let after = try encoder.encode(source)
            precondition(after == before, "Print planning must not mutate source JSON")
            fixtures += 1
        }
        print("PASS: 1:1 centimetre/PDF-point scale, native Bezier and \(arcsChecked) arc variants (max path error \(maximumArcPathError) cm), stable nonoverlapping panel layout, A4 overlap/coverage/boundaries, safety limits and \(fixtures) official fixtures")
    }
}
