import Foundation
@main @MainActor struct FittedBodySDKSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { return }
        let resource = URL(fileURLWithPath: CommandLine.arguments[1])
        let catalog = try GarmentCodeParameterCatalog.load(from: resource.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let body = GarmentCodeBodyParameters(values: catalog.body)
        let source = try GarmentCodeStandardBody.load(body: body, resourceDirectory: resource)
        let request = try GarmentCodeFittedBody.captureFit(source: source, bodyValues: body.values,
            pose: .matchPatternReference(alphaDegrees: body.values["arm_pose_angle"]!), resourceDirectory: resource)
        let result = try await Task.detached { try GarmentCodeFittedBody.fitAndPrepare(request) }.value
        try result.surface.verify(positions: result.surface.mesh.positions, triangleIndices: result.surface.mesh.triangleIndices, bodyValues: body.values)
        print(result.surface.geometrySHA256, result.exactQueries.geometrySHA256, result.surface.compatibleWithLegacyInverseSDF)
    }
}
