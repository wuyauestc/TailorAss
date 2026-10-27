import Foundation

/// The joint solver receives the existing full-source validation envelope.
/// This bridge computes the original SI area masses, not the legacy normalized
/// inverse masses, and retains the exact body, source bindings and sewing plan.
nonisolated enum GarmentCodeJointInput {
    typealias J=GarmentCodeJointObjective
    struct Prepared:Sendable {
        let source:GarmentCodeSewnDrape.PreparedInput
        let objective:J.Prepared
        var sourceSHA256:String {source.sourceSHA256}
        fileprivate init(source:GarmentCodeSewnDrape.PreparedInput,objective:J.Prepared) {
            self.source=source;self.objective=objective
        }
    }
    static func prepare(source:GarmentCodeSewnDrape.PreparedInput,material:J.M.Material,
                        strainBarrier:J.M.StrainBarrier,bendingMaterial:J.H.Material,
                        sewingComplianceMetersPerNewton:Double,
                        isCancelled:@Sendable()->Bool={false})throws->Prepared {
        if isCancelled(){throw CancellationError()}
        let cloth=source.cloth,n=cloth.positions.count
        guard source.sourceSHA256==source.plan.sourceSHA256,
              cloth.referenceToSimulation==Array(0..<n),cloth.pinned.allSatisfy({!$0}),
              let preset=cloth.settings.material else {
            throw J.ObjectiveError.invalid("联立成衣输入需要完整同源计划、独立自由度及无人工固定点的原始质量。")
        }
        let masses=try GarmentCodeClothMaterial.lumpedMasses(
            referencePositions:cloth.referencePositions.map{SIMD3($0.x,$0.y,$0.z)},
            triangleIndices:cloth.referenceTriangles,arealDensity:preset.parameters.arealDensityKgPerSquareMeter)
        guard let total=cloth.totalFabricMassKg,
              abs(masses.totalMassKg-total)<=max(1e-12,masses.totalMassKg*1e-10),
              abs(masses.meanMassKg-cloth.meanParticleMassKg)<=max(1e-14,masses.meanMassKg*1e-10) else {
            throw J.ObjectiveError.invalid("联立输入的原始面积质量与完整源校验不一致。")
        }
        let groups=source.panelBindings.map{binding in
            J.H.PanelGroup(panelID:binding.mesh.panelID,vertexIDs:binding.vertexIDs,triangleIDs:binding.triangleIDs)
        }
        let objective=try J.Prepared(referencePositions:cloth.referencePositions,referenceTriangles:cloth.referenceTriangles,
            panelGroups:groups,massesKg:masses.massesKg,stitches:source.plan.constraints,
            material:material,strainBarrier:strainBarrier,bendingMaterial:bendingMaterial,
            sewingComplianceMetersPerNewton:sewingComplianceMetersPerNewton,isCancelled:isCancelled)
        if isCancelled(){throw CancellationError()}
        return Prepared(source:source,objective:objective)
    }
}
