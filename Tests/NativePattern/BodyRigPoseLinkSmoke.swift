import Foundation
@main @MainActor struct BodyRigPoseLinkSmoke {
    static func main()throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"/unavailable")
        let body=try GarmentCodeStandardBody.load(body:.init(values:["height":171.99,"waist":84.3338,"hips":103.478,"hips_line":23.4837,"_waist_level":108.7725]),resourceDirectory:directory)
        let rig=try GarmentCodeBodyRig.load(resourceDirectory:directory)
        let result=try rig.pose(visiblePositions:body.positions,triangleIndices:body.triangleIndices,
                               bodyValues:["height":171.99,"waist":84.3338,"hips":103.478,"hips_line":23.4837,"_waist_level":108.7725],pose:.arms(alphaDegrees:45))
        if let fixed=result.validatedBody {
            let queries=try GarmentCodeBodyMeshQueries.Prepared(positions:fixed.positions,triangleIndices:fixed.triangleIndices)
            print(fixed.geometrySHA256,queries.geometrySHA256,fixed.jointAnchors.count,fixed.statistics.retainedWeightPairs)
        } else {print(result.rejectionReasons)}
    }
}
