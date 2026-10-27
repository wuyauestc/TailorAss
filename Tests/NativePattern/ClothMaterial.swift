import Foundation

@main
struct ClothMaterialRegression {
    enum Failure: Error { case check(String) }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.check(message) }
    }
    static func near(_ a: Double, _ b: Double, _ message: String, tolerance: Double = 1e-12) throws {
        try require(abs(a-b) <= tolerance, "\(message): \(a) != \(b)")
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch is GarmentCodeClothMaterial.MaterialError { return }
        throw Failure.check("Did not reject: \(message)")
    }

    static func main() throws {
        typealias Material = GarmentCodeClothMaterial
        let positions: [SIMD3<Double>] = [[0,0,0],[1,0,0],[1,1,0],[0,1,0]]
        let triangles: [UInt32] = [0,1,2,0,2,3]
        let square = try Material.lumpedMasses(referencePositions: positions,
                                                triangleIndices: triangles,
                                                arealDensity: 0.18)
        try near(square.totalAreaSquareMeters, 1, "Square has one square metre of area")
        try near(square.totalMassKg, 0.18, "180g/m² times 1m² must be .18kg")
        for (actual, expected) in zip(square.massesKg, [0.06, 0.03, 0.06, 0.03]) {
            try near(actual, expected, "Lumped area shares, not equal particle masses")
        }
        try near(square.meanMassKg, 0.045, "Mean particle mass")
        try near(square.normalizedInverseMasses[0], 0.75, "Mass normalization")
        try near(square.normalizedInverseMasses[1], 1.5, "Light corner inverse mass")

        // Refinement changes particle masses, but not total area or cloth mass.
        let subdivisions = 10
        var refined: [SIMD3<Double>] = []
        var faces: [UInt32] = []
        for row in 0...subdivisions {
            for column in 0...subdivisions {
                refined.append([Double(column)/Double(subdivisions), Double(row)/Double(subdivisions), 0])
            }
        }
        for row in 0..<subdivisions {
            for column in 0..<subdivisions {
                let a = UInt32(row*(subdivisions+1)+column)
                let b = a+1, c = a+UInt32(subdivisions+1), d = c+1
                faces += [a,b,c,b,d,c]
            }
        }
        let fine = try Material.lumpedMasses(referencePositions: refined, triangleIndices: faces, arealDensity: 0.18)
        try near(fine.totalMassKg, square.totalMassKg, "Refining a fixed physical patch must preserve total mass")
        try near(fine.totalAreaSquareMeters, square.totalAreaSquareMeters, "Refinement preserves area")
        try require(fine.meanMassKg < square.meanMassKg, "Finer vertices carry smaller masses")
        try require(fine.massesKg.allSatisfy { $0 > 0 }, "Every used vertex has positive mass")

        // Two panel-local triangles share seam DOFs only after area integration.
        let panels: [SIMD3<Double>] = [[0,0,0],[1,0,0],[0,1,0], [0,0,0],[0,1,0],[-1,0,0]]
        let welded = try Material.lumpedMasses(referencePositions: panels,
                                               triangleIndices: [0,1,2,3,4,5],
                                               referenceToSimulation: [0,1,2,0,2,3],
                                               simulationVertexCount: 4, arealDensity: 0.18)
        try near(welded.totalMassKg, 0.18, "Seam welding cannot add or lose panel area/mass")
        for (actual, expected) in zip(welded.massesKg, [0.06,0.03,0.06,0.03]) {
            try near(actual, expected, "Both adjacent panels contribute to seam mass")
        }
        let doubleDensity = try Material.lumpedMasses(referencePositions: positions,
                                                       triangleIndices: triangles, arealDensity: 0.36)
        try near(doubleDensity.totalMassKg, square.totalMassKg*2, "Density is a real mass multiplier")
        for (a, b) in zip(doubleDensity.normalizedInverseMasses, square.normalizedInverseMasses) {
            try near(a, b, "Common mass normalization does not change the shape of area weights")
        }

        for preset in Material.Preset.allCases {
            try preset.parameters.validate()
            try require(preset.title.contains("实验预设"), "Preset title must not imply measured fabric")
            let p = preset.parameters
            try near(p.gramsPerSquareMeter, p.arealDensityKgPerSquareMeter*1000, "kg/m² to g/m²")
            let full = try p.velocityRetention(timeStep: 1.0/120)
            let half = try p.velocityRetention(timeStep: 1.0/240)
            try near(full, 0.5, "Reference damping retention")
            try near(half*half, full, "Damping must depend on elapsed seconds, not frame count")
            let data = try JSONEncoder().encode(p)
            let decoded = try JSONDecoder().decode(Material.Parameters.self, from: data)
            try require(decoded == p, "Material SI values survive Codable round trip")
        }
        let soft = Material.Preset.soft.parameters, medium = Material.Preset.medium.parameters, firm = Material.Preset.firm.parameters
        try require(soft.arealDensityKgPerSquareMeter < medium.arealDensityKgPerSquareMeter && medium.arealDensityKgPerSquareMeter < firm.arealDensityKgPerSquareMeter, "Experimental weight ordering")
        try require(soft.stretchCompliance > medium.stretchCompliance && medium.stretchCompliance > firm.stretchCompliance, "Lower stretch compliance means firmer")
        try require(soft.shearCompliance > medium.shearCompliance && medium.shearCompliance > firm.shearCompliance, "Shear compliance ordering")
        try require(soft.bendDistanceCompliance > medium.bendDistanceCompliance && medium.bendDistanceCompliance > firm.bendDistanceCompliance, "Bend-distance compliance ordering")

        // A common scale of inverse mass and compliance leaves XPBD corrections
        // unchanged, including the accumulated lambda across iterations.
        let meanMass = 0.00015, compliance = 2e-6, dt = 1.0/120
        let scaledCompliance = try Material.normalizedCompliance(physicalCompliance: compliance, meanMassKg: meanMass)
        let unscaled = try Material.physicalCompliance(unitMassCompliance: scaledCompliance, meanMassKg: meanMass)
        try near(unscaled, compliance, "Compliance conversion inverse")
        var physical = [0.0, 1.1], normalized = physical
        var physicalLambda = 0.0, normalizedLambda = 0.0
        func project(_ values: inout [Double], _ lambda: inout Double, weights: [Double], compliance: Double) {
            let delta = values[0]-values[1], length = abs(delta)
            let alpha = compliance/(dt*dt)
            let change = (-(length-1)-alpha*lambda)/(weights[0]+weights[1]+alpha)
            lambda += change
            let direction = delta/length
            values[0] += direction*change*weights[0]
            values[1] -= direction*change*weights[1]
        }
        for _ in 0..<6 {
            project(&physical, &physicalLambda, weights: [10000,5000], compliance: compliance)
            project(&normalized, &normalizedLambda, weights: [10000*meanMass,5000*meanMass], compliance: scaledCompliance)
        }
        for (a, b) in zip(physical, normalized) { try near(a, b, "Normalized XPBD correction matches physical-mass formulation") }
        try near(normalizedLambda*meanMass, physicalLambda, "Lambda transforms inversely to the common mass scale")
        try near(try Material.normalizedCompliance(physicalCompliance: 0, meanMassKg: 0.1), 0, "Rigid distance constraint remains zero compliance")

        for density in [Double.nan, .infinity, 0, -1, 3] {
            try rejects("invalid density") { _ = try Material.lumpedMasses(referencePositions: positions, triangleIndices: triangles, arealDensity: density) }
        }
        var bad = medium
        bad.shearCompliance = .nan
        try rejects("non-finite compliance") { try bad.validate() }
        bad = medium; bad.bendDistanceCompliance = -1
        try rejects("negative compliance") { try bad.validate() }
        bad = medium; bad.dampingRatePerSecond = .infinity
        try rejects("non-finite damping") { try bad.validate() }
        try rejects("zero mean mass") { _ = try Material.normalizedCompliance(physicalCompliance: 1, meanMassKg: 0) }
        try rejects("bad timestep") { _ = try medium.velocityRetention(timeStep: .nan) }
        try rejects("bad mapping") { _ = try Material.lumpedMasses(referencePositions: panels, triangleIndices: [0,1,2,3,4,5], referenceToSimulation: [0,1,2,0,2,4], simulationVertexCount: 4, arealDensity: 0.18) }
        try rejects("weld collapsed a triangle") { _ = try Material.lumpedMasses(referencePositions: positions, triangleIndices: triangles, referenceToSimulation: [0,0,1,2], simulationVertexCount: 3, arealDensity: 0.18) }
        try rejects("orphan particle") { _ = try Material.lumpedMasses(referencePositions: positions+[[2,2,0]], triangleIndices: triangles, arealDensity: 0.18) }
        try rejects("index out of bounds") { _ = try Material.lumpedMasses(referencePositions: positions, triangleIndices: [0,1,UInt32.max], arealDensity: 0.18) }
        try rejects("duplicate triangle") { _ = try Material.lumpedMasses(referencePositions: positions, triangleIndices: triangles+[2,1,0], arealDensity: 0.18) }
        try rejects("degenerate triangle") { _ = try Material.lumpedMasses(referencePositions: [[0,0,0],[1,0,0],[2,0,0]], triangleIndices: [0,1,2], arealDensity: 0.18) }
        try rejects("non-finite coordinate") { _ = try Material.lumpedMasses(referencePositions: [[.nan,0,0],[1,0,0],[0,1,0]], triangleIndices: [0,1,2], arealDensity: 0.18) }
        print("PASS: SI material presets, triangle area masses, mesh refinement, welded seam mass, density, damping time units, XPBD mass normalization, validation")
    }
}
