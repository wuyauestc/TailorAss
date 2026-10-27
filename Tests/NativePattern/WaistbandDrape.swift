import Foundation

@main
@MainActor
struct WaistbandDrapeRegression {
    typealias Drape=GarmentCodeCircleDrape
    typealias Oracle=BodySurfaceContactRegression
    enum Failure:Error {case check(String)}
    struct Edge:Hashable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int){self.a=min(a,b);self.b=max(a,b)}
    }
    struct Case {
        let tag:String,style:String
        var width=0.2
        var waistScale=1.0
        var allowsQualityRejection=false
        var material=GarmentCodeClothMaterial.Preset.medium
    }
    static func require(_ value:@autoclosure()->Bool,_ message:String)throws {
        if !value(){throw Failure.check(message)}
    }
    static func encode<T:Encodable>(_ value:T)throws->Data {
        let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];return try e.encode(value)
    }
    static func log(_ value:String){FileHandle.standardError.write(Data((value+"\n").utf8))}
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body),bodyBefore=try encode(body)
        let env=ProcessInfo.processInfo.environment
        guard let sourceStrainPasses=Int(env["GARMENTCODE_WAISTBAND_STRAIN_PASSES"] ?? "40"),
              (1...120).contains(sourceStrainPasses) else {
            throw Failure.check("GARMENTCODE_WAISTBAND_STRAIN_PASSES must be an integer from 1 through 120")
        }
        let filter=env["GARMENTCODE_WAISTBAND_CASE_FILTER"]
        let selected=Set((filter ?? "").split(separator:",").map(String.init))
        let directory=URL(fileURLWithPath:env["GARMENTCODE_WAISTBAND_OUTPUT_DIR"] ?? "/private/tmp/TailorAssWaistbandDrape")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let cases:[Case]=[
            .init(tag:"straight-default",style:"StraightWB"),.init(tag:"fitted-default",style:"FittedWB"),
            .init(tag:"straight-narrow",style:"StraightWB",width:0.1),.init(tag:"fitted-narrow",style:"FittedWB",width:0.1),
            .init(tag:"straight-wide",style:"StraightWB",width:0.35,allowsQualityRejection:true),
            .init(tag:"fitted-wide",style:"FittedWB",width:0.35),
            .init(tag:"straight-wide-ease",style:"StraightWB",width:0.35,waistScale:1.05,allowsQualityRejection:true),
            .init(tag:"straight-soft",style:"StraightWB",material:.soft),.init(tag:"fitted-firm",style:"FittedWB",material:.firm)]
        var executed:[String]=[],failures:[String]=[],qualityRows:[[String:Any]]=[]
        var actualStrainFractions=Set<Double>(),actualStrainPassCounts=Set<Int>()
        for item in cases where filter==nil || selected.contains(item.tag) {
            executed.append(item.tag)
            do {
                var design=GarmentCodeDesignParameters(catalog:catalog)
                _=design.setValue(.null,at:["meta","upper"]);_=design.setValue(.null,at:["meta","bottom"])
                _=design.setValue(.string(item.style),at:["meta","wb"])
                _=design.setValue(.number(item.width),at:["waistband","width"])
                _=design.setValue(.number(item.waistScale),at:["waistband","waist"])
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design),before=try encode(document)
                let source=try document.geometryPanels(),fitted=item.style=="FittedWB"
                let front=source["wb_front"]!,back=source["wb_back"]!
                let top=front.edges[fitted ? 3 : 2].length()/100+back.edges[fitted ? 0 : 1].length()/100
                let bottom=front.edges[fitted ? 1 : 0].length()/100+back.edges[fitted ? 2 : 3].length()/100
                let depth=body["hips_line"]!*item.width/100
                let analyticArea=(top+bottom)*depth/2
                try require(abs(top-body["waist"]!*item.waistScale/100)<1e-8,"Source top circumference changed its explicit waistband multiplier")
                try require(fitted ? bottom>top : abs(bottom-top)<1e-10,"Source band family lost its distinct geometry")
                if fitted {
                    try require(front.edges.filter{$0.curvature?.circle != nil}.count==2 && back.edges.filter{$0.curvature?.circle != nil}.count==2,"Fitted band is not the actual two-arc source sector")
                }
                var settings=Drape.Settings();settings.bodyMode = .standardMannequin;settings.material=item.material
                settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.solverIterations=32
                settings.sourceStrainLimitPasses=sourceStrainPasses
                settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
                let input=try GarmentCodeWaistbandDrape.prepare(document:document,body:body,settings:settings)
                try require(input.garmentStyle==item.style,"Wrong generated band family")
                try require(abs(input.waistCircumferenceMeters-top)<1e-8 && abs(input.hemCircumferenceMeters-bottom)<1e-8,"Drape misreports the original top/bottom lengths")
                try require(abs(input.radialLengthMeters-depth)<1e-8,"Annular radial depth or rectangular paper depth was replaced by a bounding box height")
                let flat=input.referencePositions,map=input.referenceToSimulation
                try require(flat.count==map.count && map.allSatisfy{input.positions.indices.contains($0)},"Invalid separate-paper to simulation map")
                var restArea=0.0,sourceMetrics:[Edge:[Double]]=[:]
                for offset in stride(from:0,to:input.referenceTriangles.count,by:3) {
                    let ids=(0..<3).map{Int(input.referenceTriangles[offset+$0])}
                    restArea += (flat[ids[1]]-flat[ids[0]]).cross(flat[ids[2]]-flat[ids[0]]).length/2
                    for (a,b) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])] {
                        sourceMetrics[.init(map[a],map[b]),default:[]].append((flat[a]-flat[b]).length)
                    }
                }
                try require(abs(restArea-input.referenceAreaSquareMeters)<1e-10,"Reference fabric area changed after welding")
                let perimeter=source.values.reduce(0.0){sum,panel in sum+panel.edges.reduce(0.0){$0+$1.length()/100}}
                try require(abs(restArea-analyticArea)<=perimeter*0.00005+1e-9,"Tessellation area exceeds its source curve tolerance")
                for (edge,lengths) in sourceMetrics {
                    for length in lengths {
                        try require(input.springs.contains{Edge($0.a,$0.b)==edge && abs($0.length-length)<1e-10},"One source triangle edge lost its own rest length")
                    }
                }
                for spring in input.springs {
                    try require(sourceMetrics[.init(spring.a,spring.b)]?.contains{abs($0-spring.length)<1e-10} == true,"Invented brace or averaged source rest length")
                }
                try require(abs((input.totalFabricMassKg ?? -1)-restArea*item.material.parameters.arealDensityKgPerSquareMeter)<1e-12,"Independent source fabric mass is not conserved")
                var cancelled=false
                do {_=try GarmentCodeWaistbandDrape.prepare(document:document,body:body,settings:settings,isCancelled:{true})} catch is CancellationError {cancelled=true}
                try require(cancelled,"Cancelled band preparation returned a mesh")
                let output=try Drape.simulate(input:input),d=output.diagnostics
                guard let actualFraction=d.sourceStrainLimitFraction,let actualPassCount=d.sourceStrainLimitPassCount else {
                    throw Failure.check("Missing actual source-strain limiter diagnostics")
                }
                try require(actualFraction==input.settings.sourceStrainLimit && actualPassCount==sourceStrainPasses,
                    "Simulation did not preserve the requested limiter configuration")
                actualStrainFractions.insert(actualFraction);actualStrainPassCounts.insert(actualPassCount)
                try encode(output).write(to:directory.appendingPathComponent(item.tag+"-mesh.json"),options:.atomic)
                try encode(document).write(to:directory.appendingPathComponent(item.tag+"-pattern.json"),options:.atomic)
                try encode(d).write(to:directory.appendingPathComponent(item.tag+"-diagnostics.json"),options:.atomic)
                try output.objString.write(to:directory.appendingPathComponent(item.tag+".obj"),atomically:true,encoding:.utf8)
                let independent=Oracle.oracleCount(cloth:.init(positions:output.positions,indices:output.triangleIndices),
                    body:.init(positions:output.mannequinPositions,indices:output.mannequinTriangleIndices))
                log("\(item.tag): strain=\(d.maxEdgeStrain), speed=\(d.maxSpeedMetersPerSecond), self=\(d.surfaceIntersectionCount ?? -1), body=\(d.bodySurfaceIntersectionCount ?? -1), oracle=\(independent), converged=\(d.converged), Mac_seconds=\(d.computationSeconds)")
                let qualityPassed=d.converged && d.maxEdgeStrain<0.08 && d.maxSpeedMetersPerSecond<0.025
                    && d.maxBodyPenetrationMeters<0.003 && d.surfaceIntersectionCount==0 && independent==0
                qualityRows.append(["case":item.tag,"qualityPassed":qualityPassed,
                    "allowsQualityRejection":item.allowsQualityRejection,"waistMultiplier":item.waistScale,
                    "widthRatio":item.width,"maxEdgeStrain":d.maxEdgeStrain,
                    "sourceStrainLimitFraction":actualFraction,"sourceStrainLimitPassCount":actualPassCount])
                if !d.converged {
                    for spring in input.springs.sorted(by:{abs((output.positions[$0.a]-output.positions[$0.b]).length/$0.length-1)>abs((output.positions[$1.a]-output.positions[$1.b]).length/$1.length-1)}).prefix(4) {
                        log("  worst \(spring.a)-\(spring.b) rest=\(spring.length) strain=\(abs((output.positions[spring.a]-output.positions[spring.b]).length/spring.length-1)) pins=\(input.pinned[spring.a])-\(input.pinned[spring.b])")
                    }
                }
                let after=try encode(document),bodyAfter=try encode(body)
                try require(after==before && bodyAfter==bodyBefore,"3D changed the paper document or body parameters")
                try require(output.triangleIndices==input.triangleIndices && output.positions.allSatisfy(\.isFinite),"Simulation invalidated source topology")
                try require(d.bodySurfaceIntersectionCount==independent && independent==0,"Independent visible-body crossing check failed")
                try require(d.surfaceIntersectionCount==0 && d.maxBodyPenetrationMeters<0.003,"Self-contact or body vertex penetration gate failed")
                if !qualityPassed {
                    try require(item.allowsQualityRejection && !d.converged && d.maxEdgeStrain>=0.08,
                        "Unchanged strain/motion/sustained convergence gates failed")
                    try require(d.warnings.contains{$0.contains("未达到收敛门槛")},"Quality rejection was not disclosed")
                    log("\(item.tag): explicit quality rejection retained; the paper was not resized to obtain a pass")
                }
                try require(d.maxSeamGapMeters==0,"Admissible side seam failed to close")
                try require(output.objString.contains(fitted ? "o fitted_waistband" : "o straight_waistband"),"OBJ misidentifies waistband as a skirt")
                cancelled=false
                do {_=try Drape.simulate(input:input,isCancelled:{true})} catch is CancellationError {cancelled=true}
                try require(cancelled,"Cancelled band solve returned a mesh")
            } catch {failures.append("\(item.tag): \(error)");log("FAIL \(item.tag): \(error)")}
        }
        try require(!executed.isEmpty && (filter==nil || Set(executed)==selected),"Unknown or empty waistband case filter")
        let summary:[String:Any]=["passed":failures.isEmpty,"executed":executed,"failures":failures,"caseQuality":qualityRows,
            "requestedSourceStrainLimitPasses":sourceStrainPasses,
            "sourceStrainLimitFractions":actualStrainFractions.sorted(),"sourceStrainLimitPassCounts":actualStrainPassCounts.sorted(),
            "settings":"Standard visible body, actual paper metrics, source mass, welded admissible equal-length side seams; unchanged 8% strain, .025m/s speed, 3mm vertex and zero cloth/body-face crossing gates. A regression pass includes truthful rejection of the unchanged wide Straight source; consult each caseQuality/diagnostic, not only passed. The separate wide-ease case explicitly changes its source waist multiplier to 1.05. Mac CLI timings only."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("waistband-summary.json"),options:.atomic)
        if !failures.isEmpty {throw Failure.check(failures.joined(separator:"\n"))}
        print("PASS waistband integration: \(executed.joined(separator:", "))")
    }
}
