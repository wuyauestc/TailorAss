import Foundation

/// Full numerical regressions with the visible-body surface barrier enabled.
/// Old snapshots remain immutable and are also checked with the option off.
@main
struct ClothBodySurfaceRegression {
    typealias Drape=GarmentCodeCircleDrape
    typealias Oracle=BodySurfaceContactRegression
    enum Failure:Error {case check(String)}
    struct Case {
        let tag:String,style:String
        var length=0.2,flare=0.0,suns=0.75
        var material=GarmentCodeClothMaterial.Preset.medium
    }
    static func require(_ value:@autoclosure()->Bool,_ message:String)throws {if !value(){throw Failure.check(message)}}
    static func encode<T:Encodable>(_ value:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];return try e.encode(value)}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body),bodyBefore=try encode(body)
        let env=ProcessInfo.processInfo.environment
        let filter=env["GARMENTCODE_BODY_SURFACE_CASE_FILTER"]
        let selected=Set((filter ?? "").split(separator:",").map(String.init))
        func includes(_ tag:String)->Bool {filter==nil || selected.contains(tag)}
        let directory=URL(fileURLWithPath:env["GARMENTCODE_BODY_SURFACE_OUTPUT_DIR"] ?? "/private/tmp/TailorAssBodySurface")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        func design(_ item:Case)->GarmentCodeDesignParameters {
            var result=GarmentCodeDesignParameters(catalog:catalog)
            _=result.setValue(.null,at:["meta","upper"]);_=result.setValue(.null,at:["meta","wb"])
            _=result.setValue(.string(item.style),at:["meta","bottom"])
            _=result.setValue(.number(item.length),at:["skirt","length"])
            _=result.setValue(.number(1.3),at:["skirt","ruffle"])
            _=result.setValue(.number(item.flare),at:["skirt","flare"])
            _=result.setValue(.number(0),at:["skirt","bottom_cut"])
            _=result.setValue(.number(item.length),at:["flare-skirt","length"])
            _=result.setValue(.number(item.suns),at:["flare-skirt","suns"])
            _=result.setValue(.bool(false),at:["flare-skirt","cut","add"])
            return result
        }
        func settings(enabled:Bool,material:GarmentCodeClothMaterial.Preset)->Drape.Settings {
            var s=Drape.Settings();s.bodyMode = .standardMannequin;s.material=material
            s.useSurfaceCollision=true;s.useBodySurfaceCollision=enabled;s.solverIterations=32
            s.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
            return s
        }
        var executed:[String]=[],failures:[String]=[]
        if includes("flag-off-reference") {
            executed.append("flag-off-reference")
            do {
                let circle=Case(tag:"legacy-circle",style:"SkirtCircle")
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(circle))
                let input=try GarmentCodeSkirtDrape.prepare(document:document,body:body)
                try require(!input.settings.useBodySurfaceCollision && input.bodySurfaceMesh==nil,"New body contact must remain opt-in for legacy snapshots")
                let output=try Drape.simulate(input:input)
                let old=try JSONDecoder().decode(Drape.Output.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Reports/2026-10-25-3d/generated/circle-0.75-mesh.json")))
                try require(output.positions==old.positions && output.triangleIndices==old.triangleIndices,"Flag-off circle changed a legacy vertex")
                let skirt=Case(tag:"legacy-skirt2",style:"Skirt2")
                let skirtDocument=try GarmentCodeNativeGenerator.generate(body:body,design:design(skirt))
                let skirtInput=try GarmentCodeSkirtDrape.prepare(document:skirtDocument,body:body,settings:settings(enabled:false,material:.medium))
                let skirtOutput=try Drape.simulate(input:skirtInput)
                let oldSkirt=try JSONDecoder().decode(Drape.Output.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Reports/2026-10-25-skirt2-3d/generated/skirt2-default-mesh.json")))
                try require(skirtOutput.positions==oldSkirt.positions,"Flag-off standard-body Skirt2 changed a legacy vertex")
                log("flag-off-reference: circle +standard-body Skirt2 maximum_position_delta_m=0")
            } catch {failures.append("flag-off-reference: \(error)");log("FAIL flag-off-reference: \(error)")}
        }
        let cases:[Case]=[
            .init(tag:"skirt2-default",style:"Skirt2"),
            .init(tag:"skirt2-longer",style:"Skirt2",length:0.35),
            .init(tag:"skirt2-flare10",style:"Skirt2",flare:10),
            .init(tag:"skirt2-soft",style:"Skirt2",material:.soft),
            .init(tag:"skirt2-firm",style:"Skirt2",material:.firm),
            .init(tag:"circle-0.5",style:"SkirtCircle",suns:0.5),
            .init(tag:"circle-0.75",style:"SkirtCircle",suns:0.75),
            .init(tag:"circle-1.0",style:"SkirtCircle",suns:1)
        ]
        for item in cases where includes(item.tag) {
            executed.append(item.tag)
            do {
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(item)),before=try encode(document)
                let input=try GarmentCodeSkirtDrape.prepare(document:document,body:body,settings:settings(enabled:true,material:item.material))
                try require(input.settings.useBodySurfaceCollision && input.bodySurfaceMesh != nil,"Enabled visible-body contact did not prepare its actual surface")
                let waistEdges=input.springs.filter {input.pinned[$0.a] && input.pinned[$0.b]}
                let pinStrain=waistEdges.map {abs((input.positions[$0.a]-input.positions[$0.b]).length/$0.length-1)}.max() ?? .infinity
                let pinLength=waistEdges.reduce(0.0) {$0+(input.positions[$1.a]-input.positions[$1.b]).length}
                log("\(item.tag) prepare-ring: pinned_source_strain=\(pinStrain), support_polyline_m=\(pinLength), source_waist_m=\(input.waistCircumferenceMeters)")
                if let worst=waistEdges.max(by:{abs((input.positions[$0.a]-input.positions[$0.b]).length/$0.length-1)<abs((input.positions[$1.a]-input.positions[$1.b]).length/$1.length-1)}),pinStrain>=0.08 {
                    log("  fixed_worst \(worst.a)-\(worst.b) rest=\(worst.length) actual=\((input.positions[worst.a]-input.positions[worst.b]).length)")
                }
                try require(pinStrain<0.08,"Fixed waist support already violates the original source edge gate")
                if item.style == "Skirt2" {try require(abs(pinLength-input.waistCircumferenceMeters)<1e-4,"Clearance changed the real gathered source waist length")}
                let output=try Drape.simulate(input:input)
                let d=output.diagnostics
                try encode(output).write(to:directory.appendingPathComponent(item.tag+"-mesh.json"),options:.atomic)
                try encode(document).write(to:directory.appendingPathComponent(item.tag+"-pattern.json"),options:.atomic)
                try encode(d).write(to:directory.appendingPathComponent(item.tag+"-diagnostics.json"),options:.atomic)
                try output.objString.write(to:directory.appendingPathComponent(item.tag+".obj"),atomically:true,encoding:.utf8)
                let actual=Oracle.oracleCount(cloth:.init(positions:output.positions,indices:output.triangleIndices),body:.init(positions:output.mannequinPositions,indices:output.mannequinTriangleIndices))
                log("\(item.tag): strain=\(d.maxEdgeStrain), speed=\(d.maxSpeedMetersPerSecond), vertex_penetration=\(d.maxBodyPenetrationMeters), self_cross=\(d.surfaceIntersectionCount.map(String.init) ?? "nil"), visible_body_cross=\(d.bodySurfaceIntersectionCount.map(String.init) ?? "nil"), independent_cross=\(actual), converged=\(d.converged), Mac_seconds=\(d.computationSeconds)")
                if !d.converged {
                    let worst=input.springs.sorted{abs((output.positions[$0.a]-output.positions[$0.b]).length/$0.length-1)>abs((output.positions[$1.a]-output.positions[$1.b]).length/$1.length-1)}.prefix(3)
                    for s in worst {log("  worst \(s.a)-\(s.b) strain=\(abs((output.positions[s.a]-output.positions[s.b]).length/s.length-1)) pins=\(input.pinned[s.a])-\(input.pinned[s.b])")}
                }
                let after=try encode(document),bodyAfter=try encode(body)
                try require(before==after && bodyBefore==bodyAfter,"Body contact changed source dimensions")
                try require(output.positions.allSatisfy(\.isFinite) && output.triangleIndices==input.triangleIndices,"Contact invalidated the original cloth topology")
                try require(d.bodySurfaceIntersectionCount==actual,"Visible-body quality disagrees with independent triangle intersections")
                try require(d.bodySurfaceClearanceMeters==input.settings.bodySurfaceClearanceMeters && d.waistSupportClearanceMeters==0.005,"Body surface and fixed-support margins were not disclosed accurately")
                try require(actual==0,"A face of the visible body still crosses the cloth")
                try require(d.maxEdgeStrain<0.08,"Original 8% source edge gate")
                try require(d.maxSpeedMetersPerSecond<0.025,"Original .025m/s motion gate")
                try require(d.maxBodyPenetrationMeters<0.003,"Original 3mm body estimate gate")
                try require(d.surfaceIntersectionCount==0,"Original zero cloth self-crossing gate")
                try require(d.maxSeamGapMeters==0 && d.converged,"Shared seams or sustained convergence failed")
                var cancelled=false
                do {_=try Drape.simulate(input:input,isCancelled:{true})} catch is CancellationError {cancelled=true}
                try require(cancelled,"Cancelled surface-enabled solve returned a mesh")
            } catch {failures.append("\(item.tag): \(error)");log("FAIL \(item.tag): \(error)")}
        }
        try require(!executed.isEmpty,"Unknown body-surface case filter")
        try require(filter==nil || Set(executed)==selected,"Unknown body-surface case in filter")
        let summary:[String:Any]=["executed":executed,"passed":failures.isEmpty,"failures":failures,"settings":"Standard body, cloth +actual visible-body surface contact, 32 iterations, unchanged existing quality gates plus zero independently counted body/cloth triangle intersections."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("body-surface-summary.json"),options:.atomic)
        if !failures.isEmpty {throw Failure.check(failures.joined(separator:"\n"))}
        print("PASS: body-surface integration (\(executed.joined(separator:", ")))")
    }
}
