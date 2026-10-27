import Foundation

/// Numerical distance-constraint presets, not measured real-world fabrics.
/// SI masses are computed from the original panel triangles before seam DOFs
/// are merged. No silk/cotton/denim fit or drape calibration is implied.
nonisolated enum GarmentCodeClothMaterial {
    enum Preset: String, CaseIterable, Codable, Identifiable, Sendable {
        case soft, medium, firm

        var id: String { rawValue }
        var title: String {
            switch self {
            case .soft: return "柔软（实验预设）"
            case .medium: return "中等（实验预设）"
            case .firm: return "挺括（实验预设）"
            }
        }

        var parameters: Parameters {
            // The damping is held constant to isolate the mass/compliance
            // experiment and preserve the reference quasi-static settling.
            let damping = log(2.0) * 120
            switch self {
            case .soft:
                return .init(arealDensityKgPerSquareMeter: 0.12,
                             stretchCompliance: 1.3333333333333333e-6,
                             shearCompliance: 4e-6,
                             bendDistanceCompliance: 20,
                             dampingRatePerSecond: damping)
            case .medium:
                return .init(arealDensityKgPerSquareMeter: 0.18,
                             stretchCompliance: 6.666666666666667e-7,
                             shearCompliance: 2e-6,
                             bendDistanceCompliance: 6.666666666666667,
                             dampingRatePerSecond: damping)
            case .firm:
                return .init(arealDensityKgPerSquareMeter: 0.28,
                             stretchCompliance: 3.3333333333333335e-7,
                             shearCompliance: 1e-6,
                             bendDistanceCompliance: 1.3333333333333333,
                             dampingRatePerSecond: damping)
            }
        }
    }

    struct Parameters: Codable, Equatable, Sendable {
        /// kg/m²; multiplying by 1000 gives the familiar g/m².
        var arealDensityKgPerSquareMeter: Double
        /// m/N = s²/kg for distance constraints C = length - restLength.
        var stretchCompliance: Double
        var shearCompliance: Double
        /// Also m/N: this solver uses two-hop distances, not an angular
        /// constitutive bending law or measured flexural rigidity.
        var bendDistanceCompliance: Double
        /// Velocity retention is exp(-rate * dt); this is a numerical settling
        /// parameter and has not been measured from a fabric sample.
        var dampingRatePerSecond: Double

        var gramsPerSquareMeter: Double { arealDensityKgPerSquareMeter * 1000 }

        func validate() throws {
            guard arealDensityKgPerSquareMeter.isFinite,
                  (0.01...2).contains(arealDensityKgPerSquareMeter) else {
                throw MaterialError.invalid("面料单位面积质量需为 10～2000 g/m² 的有限数值。")
            }
            guard [stretchCompliance, shearCompliance, bendDistanceCompliance]
                .allSatisfy({ $0.isFinite && (0...10_000).contains($0) }) else {
                throw MaterialError.invalid("面料距离柔顺度需为 0～10000 m/N 的有限数值。")
            }
            guard dampingRatePerSecond.isFinite,
                  (0...200).contains(dampingRatePerSecond) else {
                throw MaterialError.invalid("面料实验阻尼率需为 0～200 s⁻¹ 的有限数值。")
            }
        }

        func velocityRetention(timeStep: Double) throws -> Double {
            try validate()
            guard timeStep.isFinite, timeStep > 0, timeStep <= 1 else {
                throw MaterialError.invalid("布料时间步长需为 0～1 秒之间的有限正数。")
            }
            return exp(-dampingRatePerSecond * timeStep)
        }
    }

    struct MassDistribution: Sendable {
        let massesKg: [Double]
        let inverseMassesPerKg: [Double]
        let vertexAreasSquareMeters: [Double]
        let totalAreaSquareMeters: Double
        let totalMassKg: Double
        let meanMassKg: Double

        /// The solver may apply its pin mask afterward. Pinned vertices still
        /// have physical mass and are included in the total cloth mass.
        var normalizedInverseMasses: [Double] {
            inverseMassesPerKg.map { $0 * meanMassKg }
        }
    }

    enum MaterialError: LocalizedError, Sendable {
        case invalid(String)
        var errorDescription: String? {
            if case let .invalid(message) = self { return message }
            return nil
        }
    }

    /// Integrate linear triangle shape functions: each face contributes one
    /// third of its rest area to each corner. Optional welding is applied only
    /// to mass accumulation; the panel-local rest triangles are not moved.
    static func lumpedMasses(referencePositions: [SIMD3<Double>],
                             triangleIndices: [UInt32],
                             referenceToSimulation: [Int]? = nil,
                             simulationVertexCount: Int? = nil,
                             arealDensity: Double) throws -> MassDistribution {
        guard arealDensity.isFinite, (0.01...2).contains(arealDensity),
              !referencePositions.isEmpty, referencePositions.count <= 100_000,
              !triangleIndices.isEmpty, triangleIndices.count % 3 == 0,
              triangleIndices.count <= 600_000 else {
            throw MaterialError.invalid("面料质量计算的密度、顶点或三角网格预算无效。")
        }
        guard referencePositions.allSatisfy({ p in
            p.x.isFinite && p.y.isFinite && p.z.isFinite &&
                max(abs(p.x), max(abs(p.y), abs(p.z))) <= 100
        }) else {
            throw MaterialError.invalid("面料参考网格需使用米，坐标必须有限且不超过 100 米。")
        }
        let mapping: [Int]
        let count: Int
        if let referenceToSimulation {
            guard let simulationVertexCount,
                  simulationVertexCount > 0, simulationVertexCount <= referencePositions.count,
                  referenceToSimulation.count == referencePositions.count,
                  referenceToSimulation.allSatisfy({ (0..<simulationVertexCount).contains($0) }) else {
                throw MaterialError.invalid("面料质量的接缝顶点映射无效。")
            }
            mapping = referenceToSimulation
            count = simulationVertexCount
        } else {
            guard simulationVertexCount == nil || simulationVertexCount == referencePositions.count else {
                throw MaterialError.invalid("没有接缝映射时，质量顶点数必须等于参考顶点数。")
            }
            mapping = Array(referencePositions.indices)
            count = referencePositions.count
        }

        struct Face: Hashable { let a: UInt32; let b: UInt32; let c: UInt32 }
        var faces: Set<Face> = []
        var areas = Array(repeating: 0.0, count: count)
        var totalArea = 0.0
        for offset in stride(from: 0, to: triangleIndices.count, by: 3) {
            let ids = Array(triangleIndices[offset..<(offset+3)])
            guard ids.allSatisfy({ Int($0) < referencePositions.count }), Set(ids).count == 3 else {
                throw MaterialError.invalid("面料三角面包含越界或重复顶点。")
            }
            guard Set(ids.map { mapping[Int($0)] }).count == 3 else {
                throw MaterialError.invalid("接缝映射将同一三角面的角点合并，参考网格已退化。")
            }
            let sorted = ids.sorted()
            guard faces.insert(.init(a: sorted[0], b: sorted[1], c: sorted[2])).inserted else {
                throw MaterialError.invalid("面料参考网格包含重复三角面，不能重复计算质量。")
            }
            let a = referencePositions[Int(ids[0])]
            let u = referencePositions[Int(ids[1])] - a
            let v = referencePositions[Int(ids[2])] - a
            let cross = SIMD3<Double>(u.y*v.z-u.z*v.y, u.z*v.x-u.x*v.z, u.x*v.y-u.y*v.x)
            let area = sqrt(cross.x*cross.x+cross.y*cross.y+cross.z*cross.z)/2
            guard area.isFinite, area > 1e-12 else {
                throw MaterialError.invalid("面料参考网格含零面积或过小的退化三角面。")
            }
            totalArea += area
            for id in ids { areas[mapping[Int(id)]] += area/3 }
        }
        let masses = areas.map { $0 * arealDensity }
        guard totalArea.isFinite, totalArea > 0,
              masses.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw MaterialError.invalid("面料网格存在无质量顶点或无效面积。")
        }
        let totalMass = masses.reduce(0, +)
        let inverse = masses.map { 1/$0 }
        guard totalMass.isFinite, inverse.allSatisfy(\.isFinite) else {
            throw MaterialError.invalid("面料质量过小或过大，无法稳定计算。")
        }
        return .init(massesKg: masses, inverseMassesPerKg: inverse,
                     vertexAreasSquareMeters: areas, totalAreaSquareMeters: totalArea,
                     totalMassKg: totalMass, meanMassKg: totalMass/Double(count))
    }

    /// With normalized inverse masses w' = meanMassKg / massKg, scale physical
    /// XPBD distance compliance by the same mean mass: alpha' = c * meanMass/dt².
    /// With lambda' = lambda / meanMass, this gives the same positional
    /// correction as inverse masses in kg⁻¹. This is a numerical
    /// conditioning conversion, not fabric calibration or resolution invariance.
    static func normalizedCompliance(physicalCompliance: Double,
                                     meanMassKg: Double) throws -> Double {
        guard physicalCompliance.isFinite, physicalCompliance >= 0,
              meanMassKg.isFinite, meanMassKg > 0 else {
            throw MaterialError.invalid("柔顺度与参考粒子质量必须是有效的非负／正数。")
        }
        let result = physicalCompliance * meanMassKg
        guard result.isFinite else { throw MaterialError.invalid("柔顺度换算超出数值范围。") }
        return result
    }

    /// Conversely preserve a legacy unit-mass constraint at a chosen mean mass.
    static func physicalCompliance(unitMassCompliance: Double,
                                   meanMassKg: Double) throws -> Double {
        guard unitMassCompliance.isFinite, unitMassCompliance >= 0,
              meanMassKg.isFinite, meanMassKg > 0 else {
            throw MaterialError.invalid("柔顺度与参考粒子质量必须是有效的非负／正数。")
        }
        let result = unitMassCompliance / meanMassKg
        guard result.isFinite else { throw MaterialError.invalid("柔顺度换算超出数值范围。") }
        return result
    }
}
