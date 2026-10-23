import Foundation
import CoreGraphics

@main
struct SeamAllowanceRegression {
    static func main() throws {
        func near(_ actual: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 0.003) {
            precondition(abs(actual - expected) <= tolerance, "Expected \(expected), got \(actual)")
        }
        func polygon(_ points: [CGPoint]) -> (CGPath, [CGPath]) {
            let path = CGMutablePath()
            path.move(to: points[0])
            var edges: [CGPath] = []
            for index in points.indices {
                let next = points[(index + 1) % points.count]
                path.addLine(to: next)
                let edge = CGMutablePath()
                edge.move(to: points[index]); edge.addLine(to: next)
                edges.append(edge)
            }
            path.closeSubpath()
            return (path, edges)
        }
        func build(_ points: [CGPoint], widths: [Double], folds: Set<Int> = []) throws -> GarmentCodeSeamAllowance.Result {
            let (path, edges) = polygon(points)
            return try GarmentCodeSeamAllowance.build(seamPath: path, edgePaths: edges, widthsCM: widths, foldEdges: folds)
        }
        func reject(_ action: () throws -> Void) {
            do { try action(); preconditionFailure("Invalid allowance input was accepted") }
            catch { }
        }
        let rectangle: [CGPoint] = [.init(x: 0, y: 0), .init(x: 10, y: 0),
                                    .init(x: 10, y: 20), .init(x: 0, y: 20)]
        let uniform = try build(rectangle, widths: [1, 1, 1, 1])
        near(uniform.bounds.minX, -1); near(uniform.bounds.minY, -1)
        near(uniform.bounds.width, 12); near(uniform.bounds.height, 22)
        let reversed = try build(rectangle.reversed(), widths: [1, 1, 1, 1])
        near(reversed.bounds.minX, -1); near(reversed.bounds.minY, -1)
        near(reversed.bounds.width, 12); near(reversed.bounds.height, 22)
        let variable = try build(rectangle, widths: [3, 1, 1, 1])
        near(variable.bounds.minY, -3); near(variable.bounds.height, 24)
        let zero = try build(rectangle, widths: [0, 0, 0, 0])
        near(zero.bounds.minX, 0); near(zero.bounds.width, 10); near(zero.bounds.height, 20)
        let fold = try build(rectangle, widths: [1, 1, 1, 0], folds: [3])
        near(fold.bounds.minX, 0); near(fold.bounds.maxX, 11)
        near(fold.bounds.minY, -1); near(fold.bounds.maxY, 21)
        let zeroFold = try build(rectangle, widths: [0, 0, 0, 0], folds: [3])
        near(zeroFold.bounds.width, 10)
        let triangle = try build([.zero, .init(x: 20, y: 0), .init(x: 0.05, y: 0.1)], widths: [1, 1, 1])
        precondition(triangle.bounds.width < 28.01 && triangle.bounds.height < 8.1,
                     "Acute miters must be bounded")
        precondition(triangle.warnings.contains { $0.contains("尖角") })
        let concave: [CGPoint] = [.zero, .init(x: 12, y: 0), .init(x: 12, y: 4),
                                  .init(x: 4, y: 4), .init(x: 4, y: 12), .init(x: 0, y: 12)]
        let lShape = try build(concave, widths: [1, 1, 1, 1, 1, 1])
        near(lShape.bounds.width, 14); near(lShape.bounds.height, 14)
        precondition(lShape.warnings.contains { $0.contains("凹角") })
        let noConcaveAllowance = try build(concave, widths: [0, 0, 0, 0, 0, 0])
        near(noConcaveAllowance.bounds.width, 12)
        reject { _ = try build(rectangle, widths: [1, .nan, 1, 1]) }
        reject { _ = try build(rectangle, widths: [1, 6, 1, 1]) }
        reject { _ = try build(rectangle, widths: [1, -1, 1, 1]) }
        reject { _ = try build(rectangle, widths: [1, 1, 1]) }
        reject { _ = try build(rectangle, widths: [1, 1, 1, 1], folds: [4]) }
        reject { _ = try build([.zero, .init(x: 10, y: 10), .init(x: 0, y: 10), .init(x: 10, y: 0)], widths: [1, 1, 1, 1]) }
        reject { _ = try build([.zero, .init(x: 10, y: 0), .init(x: 5, y: 0), .init(x: 0, y: 10)], widths: [1, 1, 1, 1]) }
        reject { _ = try build(concave, widths: [1, 1, 0, 1, 1, 1], folds: [2]) }
        reject { _ = try build(concave, widths: [0, 0, 0, 0, 0, 0], folds: [2]) }
        reject { _ = try build([.zero, .init(x: CGFloat.nan, y: 0), .init(x: 10, y: 10)], widths: [1, 1, 1]) }
        // Closing a narrow entrance into a genuinely large concave pocket
        // creates a visible hole, not a numerical micro-loop. Never erase it
        // silently just to manufacture a single outer cut contour.
        let pocket: [CGPoint] = [.zero, .init(x: 12, y: 0), .init(x: 12, y: 12), .init(x: 0, y: 12),
                                 .init(x: 0, y: 7), .init(x: 2, y: 7), .init(x: 2, y: 10), .init(x: 10, y: 10),
                                 .init(x: 10, y: 2), .init(x: 2, y: 2), .init(x: 2, y: 5), .init(x: 0, y: 5)]
        do {
            _ = try build(pocket, widths: Array(repeating: 1.1, count: pocket.count))
            preconditionFailure("A visible enclosed pocket must not be silently filled")
        } catch let error as GarmentCodeSeamAllowance.AllowanceError {
            guard case .unreliableOffset = error else {
                preconditionFailure("Pocket input itself must be valid; expected output-hole rejection, got \(error)")
            }
        }
        let (firstPart, firstEdges) = polygon(rectangle)
        let (secondPart, secondEdges) = polygon(rectangle.map { CGPoint(x: $0.x + 30, y: $0.y) })
        let disconnected = CGMutablePath(); disconnected.addPath(firstPart); disconnected.addPath(secondPart)
        reject {
            _ = try GarmentCodeSeamAllowance.build(seamPath: disconnected,
                edgePaths: firstEdges + secondEdges, widthsCM: Array(repeating: 1, count: 8))
        }

        func curved(_ kind: String) throws {
            let outline = CGMutablePath(), first = CGMutablePath()
            outline.move(to: .zero); first.move(to: .zero)
            switch kind {
            case "quadratic":
                outline.addQuadCurve(to: .init(x: 10, y: 0), control: .init(x: 5, y: -3))
                first.addQuadCurve(to: .init(x: 10, y: 0), control: .init(x: 5, y: -3))
            case "cubic":
                outline.addCurve(to: .init(x: 10, y: 0), control1: .init(x: 2, y: -4), control2: .init(x: 8, y: -4))
                first.addCurve(to: .init(x: 10, y: 0), control1: .init(x: 2, y: -4), control2: .init(x: 8, y: -4))
            default:
                outline.addArc(center: .init(x: 5, y: 0), radius: 5, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
                first.addArc(center: .init(x: 5, y: 0), radius: 5, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
            }
            let tail: [CGPoint] = [.init(x: 10, y: 0), .init(x: 10, y: 10), .init(x: 0, y: 10), .zero]
            var edges: [CGPath] = [first]
            for (a, b) in zip(tail, tail.dropFirst()) {
                outline.addLine(to: b)
                let edge = CGMutablePath(); edge.move(to: a); edge.addLine(to: b); edges.append(edge)
            }
            outline.closeSubpath()
            let result = try GarmentCodeSeamAllowance.build(seamPath: outline, edgePaths: edges, widthsCM: [1, 1, 1, 1])
            near(result.bounds.minX, -1); near(result.bounds.maxX, 11)
            near(result.bounds.maxY, 11)
            near(result.bounds.minY, outline.boundingBoxOfPath.minY - 1, tolerance: 0.006)
            precondition(result.cutPath.contains(CGPoint(x: 5, y: 5)))
            reject { _ = try GarmentCodeSeamAllowance.build(seamPath: outline, edgePaths: edges,
                       widthsCM: [0, 0, 0, 0], foldEdges: [0]) }
        }
        try curved("quadratic"); try curved("cubic"); try curved("circle")

        var officialCount = 0, mixedCount = 0, expectedOfficialCount = 0, safeRejections: [String] = []
#if !ALLOWANCE_KERNEL_ONLY
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for fixture in ["shirt", "fitted-shirt", "pants", "pencil-skirt"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/\(fixture).json"))
            let document = try GarmentCodePatternFile.validatedImport(from: data)
            var manufacturing = GarmentCodeDraftingSettings()
            manufacturing.addSeamAllowance = true
            let mixed = try GarmentCodePrintPlan(document: document, drafting: manufacturing)
            precondition(mixed.panels.count == document.pattern.panels.count &&
                         mixed.panels.allSatisfy { $0.cutPathCM != nil })
            mixedCount += mixed.panels.count
            expectedOfficialCount += document.pattern.panels.count
            let plan = try GarmentCodePrintPlan(document: document)
            for panel in plan.panels {
                do {
                    let result = try GarmentCodeSeamAllowance.build(seamPath: panel.pathCM,
                        edgePaths: panel.edgePathsCM, widthsCM: Array(repeating: 1, count: panel.edgePathsCM.count))
                    precondition(result.bounds.width >= panel.boundsCM.width - 0.005 &&
                                 result.bounds.height >= panel.boundsCM.height - 0.005)
                    officialCount += 1
                } catch {
                    safeRejections.append("\(fixture)/\(panel.name): \(error.localizedDescription)")
                }
            }
        }
        precondition(officialCount == expectedOfficialCount && expectedOfficialCount == 14 && safeRejections.isEmpty,
                     "Every supported official panel must pass, not silently become a safe rejection: \(safeRejections)")
        precondition(mixedCount == 14, "PrintPlan's default zero-width dart legs and nonzero exterior must all pass")
#endif
        for rejection in safeRejections { print("SAFE_REJECT: \(rejection)") }
        print("PASS: native per-edge allowances; exact rectangles and unequal widths, winding, folds, acute/concave joins, quadratic/cubic/arcs, visible-hole/multi-component and invalid-input rejection; \(officialCount) uniform-width and \(mixedCount) default mixed-width official panels, \(safeRejections.count) rejected")
    }
}
