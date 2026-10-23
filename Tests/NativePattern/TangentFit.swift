import Foundation

/// Isolated upstream optimizer inputs/outputs; never substitute for full-garment tests.
@main
struct TangentFitDiagnostic {
    struct Oracle: Decodable {
        let source: [[Double]]
        let start_tangent: [Double]
        let end_tangent: [Double]
        let length: Double
        let expected: [[Double]]
        let optimizer: Optimizer
        struct Optimizer: Decodable { let trajectory: [[Double]]; let objective: Double }
    }

    static func main() throws {
        let quadratic = GarmentCodeSimplex.minimize(dimension: 5, initialStep: 1) { x in
            x.enumerated().reduce(0) { $0 + pow($1.element - Double($1.offset + 1), 2) }
        }
        precondition(quadratic.converged && quadratic.value < 1e-12)
        let cusp = GarmentCodeSimplex.minimize(dimension: 2, initialStep: 1) { x in
            max(abs(x[0] - 2), abs(x[1] + 3))
        }
        precondition(cusp.converged && cusp.value < 1e-7)
        print("PASS: native simplex smooth and nonsmooth objectives")
        if CommandLine.arguments.contains("--simplex-only") { return }
        let compact = GarmentCodeLBFGSCompact.direction(gradient: [1, 2, 3],
            s: [[1, 0, 0], [0, 1, 1]], y: [[2, 0.2, 0.1], [0, 1, 1]], curvature: [2, 2])!
        // scipy.optimize.LbfgsInvHessProduct on the same correction history.
        precondition(zip(compact, [-0.5375, -1.975, -3.025]).allSatisfy { abs($0 - $1) < 1e-12 })
        precondition(GarmentCodeLBFGSCompact.direction(gradient: [2, -3], s: [], y: [], curvature: []) == [-2, 3])
        precondition(GarmentCodeLBFGSCompact.direction(gradient: [1], s: [[1]], y: [[-1]], curvature: [-1]) == nil)
        // Independently build dense inverse-BFGS matrices for all memory sizes.
        for count in 1...10 {
            let s = (1...count).map { k in (1...5).map { j in sin(Double(k * j)) } }
            let y = s.map { v in v.enumerated().map { Double($0.offset + 1) * $0.element } }
            func dot(_ a: [Double], _ b: [Double]) -> Double {
                zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
            }
            let curvature = zip(s, y).map { dot($0, $1) }
            let gamma = curvature.last! / dot(y.last!, y.last!)
            var h = (0..<5).map { i in (0..<5).map { j in i == j ? gamma : 0 } }
            for k in 0..<count {
                let hy = h.map { dot($0, y[k]) }
                let scale = (1 + dot(y[k], hy) / curvature[k]) / curvature[k]
                for i in 0..<5 {
                    for j in 0..<5 {
                        h[i][j] += scale * s[k][i] * s[k][j] -
                            (hy[i] * s[k][j] + s[k][i] * hy[j]) / curvature[k]
                    }
                }
            }
            let gradient = [1.0, -2, 3, -4, 5]
            let expected = h.map { -dot($0, gradient) }
            let actual = GarmentCodeLBFGSCompact.direction(gradient: gradient, s: s, y: y, curvature: curvature)!
            precondition(zip(actual, expected).allSatisfy { abs($0 - $1) < 1e-9 },
                         "Compact direction differs from dense inverse BFGS for memory size \(count)")
        }
        FileHandle.standardOutput.write(Data("PASS: compact inverse-Hessian direction oracle\n".utf8))
        if CommandLine.arguments.contains("--matrix-only") { return }
        precondition(abs(GarmentCodeQuadrature.integrate { pow($0, 8) } - 1.0 / 9) < 1e-14)
        precondition(abs(GarmentCodeQuadrature.integrate { sqrt($0) } - 2.0 / 3) < 1e-8)
        let sCurve = GarmentCodeGeometryEdge(id: "s-curve", start: .zero, end: .init(x: 10, y: 0),
            curvature: .init(type: "cubic", params: [[0.3, 0.5], [0.7, -0.5]]))
        // Pinned svgpathtools CubicBezier(0, 3+5j, 7-5j, 10).length().
        precondition(abs(sCurve.length() - 11.931715684553971) < 1e-8,
                     "S-curve arc length must not collapse to the endpoint chord")
        let halves = sCurve.split(at: 0.5)
        precondition(abs(halves.0.length() + halves.1.length() - sCurve.length()) < 1e-8)
        FileHandle.standardOutput.write(Data("PASS: inflected Bezier arc length and split additivity\n".utf8))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        if CommandLine.arguments.contains("--hood-inputs") {
            let repo = root.deletingLastPathComponent().deletingLastPathComponent()
            let catalog = try GarmentCodeParameterCatalog.load(from:
                repo.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
            for upper in ["Shirt", "FittedShirt"] {
                var design = GarmentCodeDesignParameters(catalog: catalog)
                _ = design.setValue(.string(upper), at: ["meta", "upper"])
                _ = design.setValue(.string("Hood2Panels"), at: ["collar", "component", "style"])
                FileHandle.standardError.write(Data("GARMENT \(upper)\n".utf8))
                _ = try GarmentCodeNativeGenerator.generate(body: .init(values: catalog.body), design: design)
            }
            print("INPUT DIAGNOSTIC ONLY: no garment acceptance comparison performed")
            return
        }
        let cases = try JSONDecoder().decode([Oracle].self,
            from: Data(contentsOf: root.appendingPathComponent("Fixtures/tangent-fit-oracles.json")))
        func point(_ p: [Double]) -> GarmentCodePoint { .init(x: p[0], y: p[1]) }
        var passed = true
        var stable = true
        var quality = true
        for (index, item) in cases.enumerated() {
            let points = item.source.map(point)
            let expectedPoints = item.expected.map(point)
            let source = GarmentCodeGeometryEdge(id: "oracle-\(index)", start: points[0], end: points[3],
                                                curvature: GarmentCodeGeometryEdge.curvature(for: points))
            let expected = GarmentCodeGeometryEdge(id: "expected", start: expectedPoints[0], end: expectedPoints[3],
                                                  curvature: GarmentCodeGeometryEdge.curvature(for: expectedPoints))
            var trajectory: [[Double]] = []
            var objectiveValue = Double.nan
            let actual = try GarmentCodeGeometryEdge.cubicMatchingTangents(source,
                targetStartTangent: point(item.start_tangent), targetEndTangent: point(item.end_tangent),
                targetLength: item.length,
                absoluteControlPoints: CommandLine.arguments.contains("--absolute-inputs") ? points : nil,
                useLegacyOptimizer: CommandLine.arguments.contains("--legacy-optimizer"),
                objectiveObserver: { objectiveValue = $0 },
                iterationObserver: { trajectory.append($0) })
            if CommandLine.arguments.contains("--legacy-optimizer") {
            guard let first = trajectory.first, let expectedFirst = item.optimizer.trajectory.first else {
                preconditionFailure("Missing first optimizer step for case \(index)")
            }
            precondition(zip(first, expectedFirst).allSatisfy { abs($0 - $1) < 1e-5 },
                         "First accepted step differs from upstream in case \(index)")
            for (iteration, pair) in zip(trajectory, item.optimizer.trajectory).enumerated() {
                let shiftError = zip(pair.0, pair.1).map { abs($0 - $1) }.max()!
                if shiftError > 1e-5 {
                    FileHandle.standardOutput.write(Data("FIRST_ITERATION_DIVERGENCE case=\(index) iteration=\(iteration + 1) max_shift_error=\(shiftError) native=\(pair.0) upstream=\(pair.1)\n".utf8))
                    break
                }
            }
            }
            let error = (0...100).map {
                actual.point(at: Double($0) / 100).distance(to: expected.point(at: Double($0) / 100))
            }.max()!
            let report = "TANGENT \(index): max sampled contour error \(error) cm; length error \(actual.length() - expected.length()) cm\n"
            FileHandle.standardOutput.write(Data(report.utf8))
            if objectiveValue.isFinite {
                FileHandle.standardOutput.write(Data("OBJECTIVE \(index): native=\(objectiveValue) official=\(item.optimizer.objective)\n".utf8))
            }
            func tangentError(_ edge: GarmentCodeGeometryEdge) -> Double {
                let chord = edge.end - edge.start
                let controls = edge.curvature!.params!.map {
                    edge.start + chord * $0[0] + chord.leftNormal * $0[1]
                }
                return max((controls[0] - edge.start).normalized.distance(to: point(item.start_tangent).normalized),
                           (edge.end - controls[1]).normalized.distance(to: point(item.end_tangent).normalized))
            }
            FileHandle.standardOutput.write(Data("QUALITY \(index): target_length_error_cm=\(abs(actual.length() - item.length)) official=\(abs(expected.length() - item.length)) tangent_unit_error=\(tangentError(actual)) official=\(tangentError(expected))\n".utf8))
            quality = quality && abs(actual.length() - item.length) < 0.01 &&
                tangentError(actual) <= max(0.005, tangentError(expected) * 1.05) &&
                objectiveValue.isFinite && objectiveValue <= item.optimizer.objective * 1.001 + 1e-12
            if CommandLine.arguments.contains("--stability-only") {
                let exact = try GarmentCodeGeometryEdge.cubicMatchingTangents(source,
                    targetStartTangent: point(item.start_tangent), targetEndTangent: point(item.end_tangent),
                    targetLength: item.length, absoluteControlPoints: points)
                var perturbed = points
                perturbed[1].y = perturbed[1].y.nextUp
                let shifted = try GarmentCodeGeometryEdge.cubicMatchingTangents(source,
                    targetStartTangent: point(item.start_tangent), targetEndTangent: point(item.end_tangent),
                    targetLength: item.length, absoluteControlPoints: perturbed)
                let deviation = (0...100).map {
                    exact.point(at: Double($0) / 100).distance(to: shifted.point(at: Double($0) / 100))
                }.max()!
                stable = stable && deviation < 0.001
                FileHandle.standardOutput.write(Data("STABILITY \(index): one-ULP contour change \(deviation) cm (limit 0.001 cm)\n".utf8))
            }
            passed = passed && error < 0.01
        }
        if CommandLine.arguments.contains("--stability-only") {
            precondition(stable, "Native tangent fit is sensitive to one-ULP input perturbations")
            print("PASS: sampled one-ULP input stability; NOT full contour/garment acceptance")
            return
        }
        if CommandLine.arguments.contains("--quality-only") {
            precondition(quality, "Target length, endpoint tangent or upstream objective quality regressed")
            print("PASS: target length <0.01 cm, endpoint tangent quality, objective <=100.1% of official; NOT full contour/garment acceptance")
            return
        }
        if CommandLine.arguments.contains("--first-step-only") {
            precondition(CommandLine.arguments.contains("--legacy-optimizer"),
                         "First-step diagnostics apply only to the explicit legacy optimizer")
            print("PASS: first accepted optimizer step in all fixtures; NOT full contour acceptance")
            return
        }
        guard passed else { throw NSError(domain: "TangentFit", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Isolated tangent fits exceed 0.01 cm diagnostic target"]) }
    }
}
