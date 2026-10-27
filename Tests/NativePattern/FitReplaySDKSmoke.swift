import Foundation
@main @MainActor struct FitReplaySDKSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { return }
        let resource = URL(fileURLWithPath: CommandLine.arguments[1])
        func data(_ name: String) throws -> Data { try Data(contentsOf: resource.appendingPathComponent(name)) }
        let prepared = try GarmentCodeBodySurfaceFitter.Prepared(
            contractData: data("GarmentCodeBodySurfaceMeasurements.json"),
            templateData: data("GarmentCodeStandardBody.json"), rigData: data("GarmentCodeStandardBodyRig/rig.json"),
            auxiliaryWeightsData: data("GarmentCodeBodyFitAuxiliaryWeights.json"))
        let catalog = try GarmentCodeParameterCatalog.load(from: resource.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let body = GarmentCodeBodyParameters(values: catalog.body)
        let source = try GarmentCodeStandardBody.load(body: body, resourceDirectory: resource)
        let result = prepared.fit(source: source, bodyValues: body.values)
        print(result.status.rawValue, result.residuals.count, result.bodyCapabilityIssued)
    }
}
