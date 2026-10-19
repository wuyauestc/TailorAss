import Foundation

/// Structural regression tests for the legacy first-pass generator, NOT a fit or
/// component-assembly certification. Missing interfaces remain tracked in M7.
@main
struct NativePatternSmoke {
    static func main() throws {
        let uppers: [GarmentCodeConfigurator.Option?] = [nil] + GarmentCodeConfigurator.uppers.map { Optional($0) }
        let waistbands: [GarmentCodeConfigurator.Option?] = [nil] + GarmentCodeConfigurator.waistbands.map { Optional($0) }
        let bottoms: [GarmentCodeConfigurator.Option?] = [nil] + GarmentCodeConfigurator.bottoms.map { Optional($0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var count = 0

        for upper in uppers {
            for waistband in waistbands {
                for bottom in bottoms {
                    var spec = GarmentDesignSpec()
                    spec.upper = upper
                    spec.waistband = waistband
                    spec.bottom = bottom
                    if spec.selectedComponentNames.isEmpty {
                        precondition(!NativeGarmentPatternGenerator.validationMessages(for: spec).isEmpty)
                        continue
                    }
                    precondition(NativeGarmentPatternGenerator.validationMessages(for: spec).isEmpty)
                    let result = NativeGarmentPatternGenerator.generate(spec)
                    let issues = NativeGarmentPatternGenerator.validationMessages(for: result)
                    precondition(issues.isEmpty, "\(spec.selectedComponentNames): \(issues)")
                    let data = try encoder.encode(result)
                    let restored = try JSONDecoder().decode(NativePatternDocument.self, from: data)
                    let restoredData = try encoder.encode(restored)
                    precondition(data == restoredData, "JSON round trip changed document")
                    count += 1
                }
            }
        }
        precondition(count == 80)

        var spec = GarmentDesignSpec()
        spec.upper = .shirt
        var result = NativeGarmentPatternGenerator.generate(spec)
        let front = result.pieces.first { $0.id == "upper-front" }!
        precondition(front.edges.map(\.role) == ["neckline", "shoulder", "armhole", "armhole", "side", "hem", "center"])

        // An invalid reference must be rejected even if the other pieces are valid.
        let broken = GeneratedPatternSeam(pieceA: "missing", edgeA: "missing", pieceB: front.id,
                                          edgeB: front.edges[0].id, type: "invalid", samplingDensity: 1)
        result = NativePatternDocument(format: result.format, generator: result.generator,
                                       disclaimer: result.disclaimer, units: result.units, design: result.design,
                                       pieces: result.pieces, seams: result.seams + [broken])
        precondition(!NativeGarmentPatternGenerator.validationMessages(for: result).isEmpty)

        spec.upper = nil
        spec.bottom = .circleSkirt
        let circle = NativeGarmentPatternGenerator.generate(spec)
        for piece in circle.pieces {
            precondition(piece.edges.filter { $0.role == "side" }.count == 2)
            precondition(piece.edges.filter { $0.role == "waist" }.count == 30)
            precondition(piece.edges.filter { $0.role == "hem" }.count == 30)
        }
        spec.bottom = .levelsSkirt
        precondition(NativeGarmentPatternGenerator.generate(spec).pieces.allSatisfy {
            $0.edges.map(\.role) == ["top", "side", "hem", "side"]
        })
        spec.bottom = .pants
        precondition(NativeGarmentPatternGenerator.generate(spec).pieces.allSatisfy {
            $0.edges[0].role == "waist" && $0.edges[4].role == "hem"
        })
        spec.bottom = .pencilSkirt
        precondition(NativeGarmentPatternGenerator.generate(spec).pieces.allSatisfy {
            $0.edges[0].role == "waist" && $0.edges[3].role == "hem"
        })
        spec.waistCm = .nan
        precondition(!NativeGarmentPatternGenerator.validationMessages(for: spec).isEmpty)
        print("PASS: 80 default combinations, JSON round trips, invalid seam reference, non-finite input and edge roles")
        print("LIMIT: validates structure only; complete assembly, fit, seam allowance and production cutting are not certified")
    }
}
