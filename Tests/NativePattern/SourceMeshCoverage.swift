import Foundation

/// Full-source triangulation coverage, deliberately separate from actual
/// placement, stitching, physical drape and App acceptance.
@main @MainActor
struct SourceMeshCoverage {
    typealias Oracle = PanelMesherRegression
    static func main() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body)
        let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_SOURCE_MESH_OUTPUT"] ?? "/private/tmp/TailorAssSourceMeshCoverage")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let specs=SourceMeshCaseDefinitions.cases()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        var cases:[[String:Any]]=[],failures:[String]=[]
        let target=0.04,flatness=0.00005
        for spec in specs {
            do {
                var design=GarmentCodeDesignParameters(catalog:catalog)
                _=design.setValue(spec.upper.map(JSONValue.string) ?? .null,at:["meta","upper"])
                _=design.setValue(spec.waistband.map(JSONValue.string) ?? .null,at:["meta","wb"])
                _=design.setValue(spec.bottom.map(JSONValue.string) ?? .null,at:["meta","bottom"])
                for (path,value) in spec.changes {try Oracle.require(design.setValue(value,at:path),"Unknown catalog path: \(path)")}
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
                let before=try encoder.encode(document),geometry=try document.geometryPanels()
                try before.write(to:directory.appendingPathComponent(spec.id+"-source.json"))
                var panels:[[String:Any]]=[],totalVertices=0,totalTriangles=0
                for id in geometry.keys.sorted() {
                    let panel=geometry[id]!
                    let mesh=try GarmentCodePanelMesher.prepare(panel:panel,targetEdgeMeters:target,flatnessMeters:flatness,
                        maximumVertices:8000,maximumTriangles:24000)
                    panels.append(try Oracle.check(mesh,panel:panel,target:target,flatness:flatness))
                    totalVertices += mesh.flatPositions.count;totalTriangles += mesh.triangleIndices.count/3
                }
                let after=try encoder.encode(document)
                try Oracle.require(before==after && panels.count==geometry.count,"Source mesh coverage changed or omitted a real panel")
                cases.append(["case":spec.id,"passed":true,"panels":panels,"totalVertices":totalVertices,
                              "totalTriangles":totalTriangles,"fitsCurrentAssemblyVertexBudget":totalVertices<=20000,
                              "fitsCurrentAssemblyTriangleBudget":totalTriangles<=40000])
                Oracle.log("PASS source meshing \(spec.id): all \(panels.count) real panels, V=\(totalVertices), T=\(totalTriangles); no placement or drape claim")
            }catch{
                let message="\(spec.id): \(error)";failures.append(message)
                cases.append(["case":spec.id,"passed":false,"failure":message])
                Oracle.log("FAIL source meshing "+message)
            }
        }
        let result:[String:Any]=["passed":failures.isEmpty,"cases":cases,"failures":failures,
            "targetEdgeMeters":target,"flatnessMeters":flatness,
            "scope":"All panels of the 12 default garment families and listed collar/sleeve/cuff/major-circle/full-outfit sources. Independent flat source geometry checks only: not initial 3D placement, actual sewn drape, all parameters or App support."]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("source-mesh-coverage-summary.json"))
        if !failures.isEmpty {throw Oracle.Failure.check(failures.joined(separator:"\n"))}
        print("PASS \(cases.count) complete source-mesh cases; physical and App coverage remain separately tracked")
    }
}
