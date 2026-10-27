import Foundation

/// Opt-in worker preparation. The legacy snapshot remains a source shape only;
/// a posed capability never carries its inverse-warp SDF into cloth contact.
nonisolated enum GarmentCodeFixedBody {
    typealias K=GarmentCodeCircleDrape
    typealias B=GarmentCodeBodySurfaceContact
    struct Recipe:Sendable {
        let source:GarmentCodeStandardBody.Snapshot
        let values:[String:Double]
        let resourceDirectory:URL
        fileprivate init(source:GarmentCodeStandardBody.Snapshot,values:[String:Double],resourceDirectory:URL) {
            self.source=source;self.values=values;self.resourceDirectory=resourceDirectory
        }
    }
    struct Prepared:Sendable {
        let surface:B.FixedSurfaceReceipt
        let exactQueries:GarmentCodeBodyMeshQueries.Prepared
        let rigStatistics:GarmentCodeBodyRig.Statistics
        private init(surface:B.FixedSurfaceReceipt,exactQueries:GarmentCodeBodyMeshQueries.Prepared,rigStatistics:GarmentCodeBodyRig.Statistics) {
            self.surface=surface;self.exactQueries=exactQueries;self.rigStatistics=rigStatistics
        }
        fileprivate static func make(recipe:Recipe,isCancelled:@Sendable()->Bool)throws->Self {
            guard let alpha=recipe.values["arm_pose_angle"],alpha.isFinite else {throw B.ContactError.invalid("参考姿态缺少有效的 arm_pose_angle。")}
            let rig=try GarmentCodeBodyRig.load(resourceDirectory:recipe.resourceDirectory,isCancelled:isCancelled)
            let attempt=try rig.pose(visiblePositions:recipe.source.positions,triangleIndices:recipe.source.triangleIndices,
                bodyValues:recipe.values,pose:.arms(alphaDegrees:alpha),isCancelled:isCancelled)
            guard let body=attempt.validatedBody,!body.compatibleWithLegacyInverseSDF else {
                throw B.ContactError.invalid("参考摆臂未通过完整可选 Rig 准备："+attempt.rejectionReasons.joined(separator:","))
            }
            // Both independent constructors inspect the actual immutable mesh.
            let queries=try GarmentCodeBodyMeshQueries.Prepared(positions:body.positions,triangleIndices:body.triangleIndices,isCancelled:isCancelled)
            guard queries.geometrySHA256==body.geometrySHA256 else {throw B.ContactError.invalid("摆臂可见表面与精确查询来源不符。")}
            func read(_ name:String)throws->Data {
                if isCancelled(){throw CancellationError()}
                let url=recipe.resourceDirectory.appendingPathComponent(name)
                guard let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=8_000_000 else {throw B.ContactError.budgetExceeded}
                let data=try Data(contentsOf:url,options:.mappedIfSafe)
                guard data.count<=8_000_000 else {throw B.ContactError.budgetExceeded}
                return data
            }
            let surface=try B.captureFixedSurface(positions:body.positions,triangleIndices:body.triangleIndices,
                expectedGeometrySHA256:body.geometrySHA256,sourcePositions:recipe.source.positions,
                sourceTriangleIndices:recipe.source.triangleIndices,rigResourceSHA256:rig.rigResourceSHA256,
                requestedAlphaDegrees:alpha,
                templateData:read("GarmentCodeStandardBody.json"),
                rigData:read("GarmentCodeStandardBodyRig/rig.json"),
                bodyValues:recipe.values,isCancelled:isCancelled)
            if isCancelled(){throw CancellationError()}
            return .init(surface:surface,exactQueries:queries,rigStatistics:body.statistics)
        }
    }
    static func recipe(source:GarmentCodeStandardBody.Snapshot,bodyValues:[String:Double],resourceDirectory:URL)->Recipe {
        .init(source:source,values:bodyValues,resourceDirectory:resourceDirectory)
    }
    static func prepare(_ recipe:Recipe,isCancelled:@Sendable()->Bool={false})throws->Prepared {
        if isCancelled(){throw CancellationError()}
        return try Prepared.make(recipe:recipe,isCancelled:isCancelled)
    }
}
