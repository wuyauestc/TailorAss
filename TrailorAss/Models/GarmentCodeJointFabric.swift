import Foundation
import NativeClothCollision

/// Explicit SI presets for the joint constitutive solver. Legacy distance
/// compliance values are not reinterpreted as membrane or bending moduli.
/// These are experimental numerical materials, not measured fabric samples.
nonisolated enum GarmentCodeJointFabric {
    typealias Preset = GarmentCodeClothMaterial.Preset
    typealias S = GarmentCodeJointSimulation
    struct Parameters: Codable, Equatable, Sendable {
        let arealDensityKgPerSquareMeter: Double
        let shearStiffnessNewtonPerMeter: Double
        let areaStiffnessNewtonPerMeter: Double
        let bendingStiffnessNewtonMeter: Double
        let sewingComplianceMetersPerNewton: Double
    }
    static func parameters(_ preset: Preset) -> Parameters {
        let shear: Double, area: Double, bending: Double
        switch preset {
        case .soft: shear = 155; area = 85; bending = 5e-5
        case .medium: shear = 310; area = 170; bending = 2e-4
        case .firm: shear = 620; area = 340; bending = 8e-4
        }
        return .init(arealDensityKgPerSquareMeter: preset.parameters.arealDensityKgPerSquareMeter,
                     shearStiffnessNewtonPerMeter: shear, areaStiffnessNewtonPerMeter: area,
                     bendingStiffnessNewtonMeter: bending, sewingComplianceMetersPerNewton: 1e-8)
    }
    static func materials(_ preset: Preset) throws -> S.Materials {
        let p = parameters(preset)
        return .init(membrane: try .init(shearStiffnessNewtonPerMeter: p.shearStiffnessNewtonPerMeter,
                                        areaStiffnessNewtonPerMeter: p.areaStiffnessNewtonPerMeter),
                     strainBarrier: try .init(lowerLimit: 0.93, lowerActivation: 0.97, upperActivation: 1.03,
                                              upperLimit: 1.07, stiffnessNewtonPerMeter: 11),
                     bending: try .init(bendingStiffnessNewtonMeter: p.bendingStiffnessNewtonMeter),
                     sewingComplianceMetersPerNewton: p.sewingComplianceMetersPerNewton,
                     bodyContact: .init(stiffnessPascals: 35, minimumDistanceMeters: 0.0005, activationGapMeters: 0.002),
                     selfContact: .init(stiffnessPascals: 35, minimumDistanceMeters: 0, activationGapMeters: 0.0005))
    }
    /// Keep the area-mass preset and constitutive preset selected together.
    /// The body and self gaps are numerical, independent of fabric thickness.
    static func sourceSettings(_ preset: Preset, bodyResourceDirectory: URL? = nil,
                               targetEdgeMeters: Double = 0.04) -> S.K.Settings {
        var settings = S.K.Settings()
        settings.material = preset; settings.bodyMode = .standardMannequin
        settings.useSurfaceCollision = true; settings.useBodySurfaceCollision = true
        settings.targetEdgeMeters = targetEdgeMeters; settings.bodyResourceDirectory = bodyResourceDirectory
        return settings
    }
}
