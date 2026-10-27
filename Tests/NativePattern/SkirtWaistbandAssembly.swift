import Foundation
import CryptoKit

/// Independent four-panel source acceptance. Physics is an explicit opt-in;
/// numeric presets and Mac timing are not physical calibration or phone timing.
@main @MainActor
struct SkirtWaistbandAssemblyRegression {
    typealias K=GarmentCodeCircleDrape
    typealias S=GarmentCodeSewing
    typealias D=GarmentCodeSewnDrape
    typealias A=GarmentCodeSkirtWaistbandAssembly
    typealias V=K.Vector3
    enum Failure:Error {case check(String)}
    struct Edge:Hashable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int) {self.a=min(a,b);self.b=max(a,b)}
    }
    struct Rest:Codable {let a:Int,b:Int;let length:Double}
    struct Reference:Codable {
        let positions:[V],triangleIndices:[UInt32],initialPositions:[V],pinned:[Bool]
        let sourceToSimulation:[Int],restEdges:[Rest]
    }
    struct Cell:Hashable {let u:Int,v:Int}
    struct RayTriangle {
        let a:V,e1u:Double,e1v:Double,e2u:Double,e2v:Double,det:Double,axis1:Double,axis2:Double
    }
    struct Parity:Codable {var outside=0,inside=0,ambiguous=0}
    /// Independent +X/+Y/+Z parity against actual closed body triangles.
    /// It never consults the production SDF or body-contact implementation.
    struct BodyVolume {
        let bins:[[Cell:[RayTriangle]]]
        static let cell=0.025,epsilon=1e-7
        static func coord(_ p:V,_ axis:Int)->Double {axis==0 ? p.x : (axis==1 ? p.y : p.z)}
        @MainActor init(positions:[V],indices:[UInt32])throws {
            var edges:[Edge:(Int,Int)]=[:],volume=0.0,all=Array(repeating:[Cell:[RayTriangle]](),count:3)
            for offset in stride(from:0,to:indices.count,by:3) {
                let ids=(0..<3).map{Int(indices[offset+$0])},a=positions[ids[0]],b=positions[ids[1]],c=positions[ids[2]]
                volume += a.x*(b.y*c.z-b.z*c.y)+a.y*(b.z*c.x-b.x*c.z)+a.z*(b.x*c.y-b.y*c.x)
                for (x,y) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])] {
                    let key=Edge(x,y),old=edges[key] ?? (0,0)
                    edges[key]=(old.0+1,old.1+(x<y ? 1 : -1))
                }
                for axis in 0..<3 {
                    let u=(axis+1)%3,v=(axis+2)%3
                    let x=Self.coord(b,u)-Self.coord(a,u),y=Self.coord(b,v)-Self.coord(a,v)
                    let z=Self.coord(c,u)-Self.coord(a,u),w=Self.coord(c,v)-Self.coord(a,v),det=x*w-y*z
                    if abs(det)<1e-18 {continue}
                    let packet=RayTriangle(a:a,e1u:x,e1v:y,e2u:z,e2v:w,det:det,axis1:Self.coord(b,axis)-Self.coord(a,axis),axis2:Self.coord(c,axis)-Self.coord(a,axis))
                    let loU=Int(floor(min(Self.coord(a,u),Self.coord(b,u),Self.coord(c,u))/Self.cell)),hiU=Int(floor(max(Self.coord(a,u),Self.coord(b,u),Self.coord(c,u))/Self.cell))
                    let loV=Int(floor(min(Self.coord(a,v),Self.coord(b,v),Self.coord(c,v))/Self.cell)),hiV=Int(floor(max(Self.coord(a,v),Self.coord(b,v),Self.coord(c,v))/Self.cell))
                    for i in loU...hiU {for j in loV...hiV {all[axis][.init(u:i,v:j),default:[]].append(packet)}}
                }
            }
            try SkirtWaistbandAssemblyRegression.require(edges.values.allSatisfy{$0.0==2 && $0.1==0} && volume>0,"Body parity requires an outward closed two-manifold")
            bins=all
        }
        func classify(_ points:[V])->Parity {
            var result=Parity()
            for p in points {
                var bits:[Bool]=[],uncertain=false
                for axis in 0..<3 {
                    let u=(axis+1)%3,v=(axis+2)%3,key=Cell(u:Int(floor(Self.coord(p,u)/Self.cell)),v:Int(floor(Self.coord(p,v)/Self.cell)))
                    var hits:[(Double,Int)]=[]
                    for q in bins[axis][key] ?? [] {
                        let pu=Self.coord(p,u)-Self.coord(q.a,u),pv=Self.coord(p,v)-Self.coord(q.a,v)
                        let b=(pu*q.e2v-pv*q.e2u)/q.det,c=(q.e1u*pv-q.e1v*pu)/q.det
                        if b < -1e-10 || c < -1e-10 || b+c>1+1e-10 {continue}
                        let t=Self.coord(q.a,axis)+b*q.axis1+c*q.axis2-Self.coord(p,axis)
                        if abs(t)<=Self.epsilon {uncertain=true}
                        else if t>Self.epsilon {hits.append((t,q.det>0 ? 1 : -1))}
                    }
                    hits.sort{$0.0<$1.0}
                    var count=0,last = -Double.infinity,sign=0
                    for hit in hits {
                        if abs(hit.0-last)<=Self.epsilon {if hit.1 != sign {uncertain=true}}
                        else {count += 1;last=hit.0;sign=hit.1}
                    }
                    bits.append(count%2==1)
                }
                if uncertain || Set(bits).count != 1 {result.ambiguous += 1}
                else if bits[0] {result.inside += 1}
                else {result.outside += 1}
            }
            return result
        }
    }
    static func require(_ value:@autoclosure()throws->Bool,_ message:String)throws {if try !value(){throw Failure.check(message)}}
    static func encode<T:Encodable>(_ value:T)throws->Data {
        let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)
    }
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func hash(_ bytes:Data)->String{SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()}
    static func design(_ style:String,catalog:GarmentCodeParameterCatalog,suns:Double=0.75)->GarmentCodeDesignParameters {
        var d=GarmentCodeDesignParameters(catalog:catalog)
        _=d.setValue(.null,at:["meta","upper"]);_=d.setValue(.string(style),at:["meta","wb"])
        _=d.setValue(.string("SkirtCircle"),at:["meta","bottom"])
        _=d.setValue(.number(suns),at:["flare-skirt","suns"])
        _=d.setValue(.number(0.2),at:["flare-skirt","length"])
        _=d.setValue(.number(1),at:["flare-skirt","rise"])
        _=d.setValue(.bool(false),at:["flare-skirt","cut","add"])
        return d
    }
    static func settings(_ root:URL)->K.Settings {
        var s=K.Settings();s.bodyMode = .standardMannequin;s.material = .medium
        s.useSurfaceCollision=true;s.useBodySurfaceCollision=true;s.solverIterations=32
        s.sourceStrainLimit=0.05;s.sourceStrainLimitPasses=40
        s.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        return s
    }
    static func validate(_ prepared:D.PreparedInput,document:GarmentCodePatternFile,style:String)throws->[String:Any] {
        let input=prepared.cloth,n=input.positions.count,flat=input.referencePositions
        let source=try document.geometryPanels()
        try require(prepared.sourceSHA256==hash(encode(document)),"Final plan uses a component hash instead of the complete original document")
        try require(prepared.panelBindings.count==4 && Set(prepared.panelBindings.map{$0.mesh.panelID})==Set(source.keys),"A composed paper panel is omitted")
        try require(input.referenceToSimulation==Array(0..<n) && input.seamVertexPairs.isEmpty && flat.count==n,"Source particles were welded or dropped")
        try require(prepared.plan.anchors.allSatisfy {anchor in
            let original=document.pattern.stitches[anchor.stitchIndex]
            return anchor.a.edge == .init(panelID:original.sides[0].panel,edgeIndex:original.sides[0].edge) &&
                anchor.b.edge == .init(panelID:original.sides[1].panel,edgeIndex:original.sides[1].edge)
        },"A runtime seam does not refer to its original full-document stitch")
        try require(Set(prepared.plan.anchors.map(\.stitchIndex))==Set(0..<6),"The real waistband, skirt or connecting seams are missing")
        var seen=Set<Int>(),expectedPins=Set<Int>(),seenFaces=Set<Int>(),sourceArea=0.0
        var vertexAreas=Array(repeating:0.0,count:n),edges:[Edge:Double]=[:]
        for binding in prepared.panelBindings {
            let mesh=binding.mesh,panel=source[mesh.panelID]!
            var sourcePolyline:[V]=[]
            for edge in panel.edges {
                let count=edge.curvature==nil ? 1 : 4096
                sourcePolyline += (0..<count).map {i in let p=edge.point(at:Double(i)/Double(count));return V(x:p.x/100,y:p.y/100,z:0)}
            }
            let analyticApprox=sourcePolyline.indices.reduce(0.0) {sum,i in
                let a=sourcePolyline[i],b=sourcePolyline[(i+1)%sourcePolyline.count]
                return sum+(a.x*b.y-a.y*b.x)/2
            }
            try require(abs(mesh.sourceSignedAreaSquareMeters-analyticApprox)<1e-7,"The source area differs from an independent dense integral")
            sourceArea += abs(analyticApprox)
            for (i,id) in binding.vertexIDs.enumerated() {
                try require(seen.insert(id).inserted && flat[id]==mesh.flatPositions[i],"Separate original panel vertex is repeated or changed")
            }
            for boundary in mesh.boundaries {
                let edge=panel.edges[boundary.edgeIndex]
                try require(abs(boundary.sourceLengthMeters-edge.length(tolerance:1e-9)/100)<1e-9,"Source boundary length was compressed to match the connector")
                for i in boundary.vertexIDs.indices {
                    let p=edge.point(at:boundary.sourceParameters[i]),id=binding.vertexIDs[boundary.vertexIDs[i]]
                    try require((flat[id]-V(x:p.x/100,y:p.y/100,z:0)).length<1e-9,"A refined source boundary vertex left the actual source curve")
                }
            }
            if mesh.panelID.hasPrefix("wb_") {
                let top=style=="StraightWB" ? (mesh.panelID=="wb_front" ? 2 : 1) : (mesh.panelID=="wb_front" ? 3 : 0)
                expectedPins.formUnion(mesh.boundaries[top].vertexIDs.map {binding.vertexIDs[$0]})
            }
            for t in binding.triangleIDs.indices {
                let global=(0..<3).map {binding.vertexIDs[Int(mesh.triangleIndices[t*3+$0])]}
                let slot=binding.triangleIDs[t]*3
                try require(seenFaces.insert(slot/3).inserted && (0..<3).allSatisfy{Int(input.referenceTriangles[slot+$0])==global[$0]},"Source reference face is omitted, duplicated or flipped")
                var facing=global;if analyticApprox<0{facing.swapAt(1,2)}
                try require((0..<3).allSatisfy{Int(input.triangleIndices[slot+$0])==facing[$0]},"Original fabric-facing direction changed")
                let a=flat[global[0]],b=flat[global[1]],c=flat[global[2]],area=(b-a).cross(c-a).z/2
                try require(area>1e-14,"CCW reference triangle is degenerate")
                for id in global{vertexAreas[id] += area/3}
                for (x,y) in [(global[0],global[1]),(global[1],global[2]),(global[2],global[0])]{edges[.init(x,y)]=(flat[x]-flat[y]).length}
            }
        }
        try require(seen.count==n && seenFaces.count==input.referenceTriangles.count/3,"The full original paper does not reach the actual mesh")
        try require(input.pinned.indices.allSatisfy{input.pinned[$0]==expectedPins.contains($0)},"Skirt upper edge or other unsewn particles were silently fixed")
        let springs=Dictionary(uniqueKeysWithValues:input.springs.map{(Edge($0.a,$0.b),$0.length)})
        try require(springs.count==input.springs.count && springs.count==edges.count,"Source spring graph is missing or repeated")
        for (key,length) in edges{try require(abs((springs[key] ?? -1)-length)<1e-12,"An original rest length was replaced by a fitted length")}
        let area=vertexAreas.reduce(0,+),density=input.settings.material!.parameters.arealDensityKgPerSquareMeter,mass=area*density,mean=mass/Double(n)
        try require(abs(area-input.referenceAreaSquareMeters)<1e-10 && abs(area-sourceArea)<0.0003,"Original composed paper area changed")
        try require(abs((input.totalFabricMassKg ?? -1)-mass)<1e-12 && abs(input.meanParticleMassKg-mean)<1e-14,"Source mass was omitted or welded away")
        for i in 0..<n {
            let wanted=input.pinned[i] ? 0 : mean/(vertexAreas[i]*density)
            try require(abs(input.inverseMasses[i]-wanted)<max(1e-12,abs(wanted)*1e-9),"Independent source-particle mass changed")
        }
        let attached=Set(prepared.plan.constraints.flatMap{$0.a.vertexIDs+$0.b.vertexIDs})
        for fold in prepared.plan.foldIntervals {
            try require(fold.untackedBoundaryVertexIDs.count>=fold.minimumFreeBoundaryNodes &&
                fold.untackedBoundaryVertexIDs.allSatisfy{!attached.contains($0) && !input.pinned[$0]},"Known interface ease lost real untacked free boundary nodes")
        }
        try require(input.settings.sourceStrainLimit==0.05 && input.settings.solverIterations==32 && input.settings.sourceStrainLimitPasses==40,"Numerical settings were silently altered")
        let initial=try S.inspect(positions:input.positions,constraints:prepared.plan.constraints)
        return ["passed":true,"style":style,"independentParticles":n,"triangles":input.triangleIndices.count/3,
            "sourceSHA256":prepared.sourceSHA256,"sourceAreaSquareMeters":area,"sourceMassKg":mass,
            "onlyWaistbandTopFixed":true,"fixedParticles":expectedPins.count,"sourceStitchCount":6,
            "sewingConstraintCount":prepared.plan.constraints.count,"foldIntervalCount":prepared.plan.foldIntervals.count,
            "actualInitialSeamGapMeters":initial.maximumGapMeters,"sourceUnchanged":true]
    }
    static func save(_ prepared:D.PreparedInput,document:GarmentCodePatternFile,tag:String,out:URL)throws {
        let input=prepared.cloth
        try encode(document).write(to:out.appendingPathComponent(tag+"-source.json"))
        try encode(prepared.plan).write(to:out.appendingPathComponent(tag+"-plan.json"))
        try encode(Reference(positions:input.referencePositions,triangleIndices:input.referenceTriangles,
            initialPositions:input.positions,pinned:input.pinned,sourceToSimulation:input.referenceToSimulation,
            restEdges:input.springs.map{.init(a:$0.a,b:$0.b,length:$0.length)})).write(to:out.appendingPathComponent(tag+"-reference.json"))
    }
    static func smoke(_ prepared:D.PreparedInput,document:GarmentCodePatternFile,out:URL,initialPlacement:A.InitialPlacement)throws->[String:Any] {
        let option=ProcessInfo.processInfo.environment["GARMENTCODE_SKIRT_WAISTBAND_COUPLED"] ?? "0"
        try require(option=="0" || option=="1","Coupled profile flag must be 0 or 1")
        let coupled=option=="1"
        let pointOption=ProcessInfo.processInfo.environment["GARMENTCODE_SKIRT_WAISTBAND_POINT_BLOCK"] ?? "0"
        try require(pointOption=="0" || pointOption=="1","Point block profile flag must be 0 or 1")
        let pointBlock=pointOption=="1"
        try require(!pointBlock || coupled,"The point block experiment requires the explicit coupled profile")
        guard let staticFrames=Int(ProcessInfo.processInfo.environment["GARMENTCODE_SKIRT_WAISTBAND_STATIC_FRAMES"] ?? "480"),
            (0...1200).contains(staticFrames) else {throw Failure.check("Static-frame count must be an integer in0...1200")}
        var coupling=D.CouplingOptions()
        if coupled {
            coupling.timeStepSeconds=1.0/240;coupling.selfContactPaddingMeters=0.0005
            coupling.projectVirtualSewingPoints=true;coupling.useSourcePathBounds=true
            coupling.sourceAwareContactRibbons=true
            coupling.simultaneousFinalSewing=pointBlock
        }
        let schedule=coupled ? D.AssemblySchedule(staticFrames:staticFrames,gravityRampFrames:240) : .immediate
        log(coupled ? "START strict combined source/contact integration: dt240, static\(staticFrames)/ramp240, finalPointBlock=\(pointBlock), 32/40/.05, path.5/single.02, original quality gates; Mac timing only"
            : "START strict default StraightWB+Circle .75 smoke: original32/40/.05/.2/.02, no weakened quality gates; Mac timing only")
        let output=try D.simulate(input:prepared,assemblyFrames:coupled ? 480 : 240,schedule:schedule,coupling:coupling,
            maximumSewingProjectionTravelPerFrameMeters:coupled ? 0.5 : 0.2,maximumSewingSingleProjectionMeters:0.02)
        try encode(output).write(to:out.appendingPathComponent("straight-default-mesh.json"))
        try output.objString.write(to:out.appendingPathComponent("straight-default.obj"),atomically:true,encoding:.utf8)
        let input=prepared.cloth,d=output.diagnostics
        let strain=input.springs.map{abs((output.positions[$0.a]-output.positions[$0.b]).length/(input.referencePositions[$0.a]-input.referencePositions[$0.b]).length-1)}.max()!
        let gap=try S.inspect(positions:output.positions,constraints:prepared.plan.constraints)
        let crossing=BodySurfaceContactRegression.oracleCount(cloth:.init(positions:output.positions,indices:output.triangleIndices),body:.init(positions:output.mannequinPositions,indices:output.mannequinTriangleIndices))
        let volume=try BodyVolume(positions:output.mannequinPositions,indices:output.mannequinTriangleIndices)
        let vertices=volume.classify(output.positions)
        let centers=stride(from:0,to:output.triangleIndices.count,by:3).map{i in (0..<3).reduce(V.zero){$0+output.positions[Int(output.triangleIndices[i+$1])]} / 3}
        let centroids=volume.classify(centers)
        let passed=d.converged && strain<0.08 && d.maxSpeedMetersPerSecond<0.025 && gap.maximumGapMeters<0.0005 &&
            crossing==0 && d.bodySurfaceIntersectionCount==0 && d.surfaceIntersectionCount==0 && d.maxBodyPenetrationMeters<0.003 &&
            vertices.inside==0 && vertices.ambiguous==0 && centroids.inside==0 && centroids.ambiguous==0
        let report:[String:Any]=["passed":passed,"converged":d.converged,"initialPlacement":initialPlacement.rawValue,"maximumIndependentSourceStrain":strain,
            "maximumActualSeamGapMeters":gap.maximumGapMeters,"maximumFinalSpeedMetersPerSecond":d.maxSpeedMetersPerSecond,
            "independentBodyTriangleCrossings":crossing,"bodyCrossings":d.bodySurfaceIntersectionCount ?? -1,"selfCrossings":d.surfaceIntersectionCount ?? -1,
            "insideVertices":vertices.inside,"ambiguousVertices":vertices.ambiguous,"insideCentroids":centroids.inside,"ambiguousCentroids":centroids.ambiguous,
            "macComputationSeconds":d.computationSeconds,
            "settings":coupled ? "Explicit coupled profile: dt240, static\(staticFrames)/gravityRamp240, source ramps480, finalPointBlock=\(pointBlock), virtual attachment body shell, source-path bounds, source-aware contact ribbons, contact projection.5mm, final inspect5mm,32/40/.05,path.5/single.02; original final gates"
                : "32 solver iterations, .05 source target/40 passes, .2m cumulative sewing path/.02m single correction, original gates"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("straight-default-smoke.json"))
        try require(abs(strain-d.maxEdgeStrain)<1e-12 && abs(gap.maximumGapMeters-d.maxSeamGapMeters)<1e-12,"Independent actual source strain/seam gap disagree with diagnostics")
        try require(output.positions.count==input.positions.count && output.triangleIndices==input.triangleIndices &&
            output.positions.indices.allSatisfy{!input.pinned[$0] || output.positions[$0]==input.positions[$0]},"Simulation changed source topology or supported points")
        try require(passed,"Strict composed garment did not converge; actual rejected output and gates were retained")
        log("PASS strict four-panel smoke: source \(strain), gap \(gap.maximumGapMeters)m, body/self/volume0")
        return report
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let env=ProcessInfo.processInfo.environment,flag=env["GARMENTCODE_SKIRT_WAISTBAND_SMOKE"] ?? "0"
        try require(flag=="0" || flag=="1","Smoke flag must be 0 or 1")
        guard let placement=A.InitialPlacement(rawValue:env["GARMENTCODE_SKIRT_WAISTBAND_PLACEMENT"] ?? "connectedCone") else {
            throw Failure.check("Unknown explicit initial placement")
        }
        let out=URL(fileURLWithPath:env["GARMENTCODE_SKIRT_WAISTBAND_OUTPUT"] ?? "/private/tmp/TailorAssSkirtWaistbandAssembly")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body),s=settings(root)
        var symmetricValues=body.values;symmetricValues["waist_back_width"]=body["waist"]!/2
        let symmetric=GarmentCodeBodyParameters(values:symmetricValues)
        var rows:[[String:Any]]=[],defaultPrepared:D.PreparedInput?,defaultDocument:GarmentCodePatternFile?
        for (tag,style,bodyValue) in [("straight-default","StraightWB",body),("fitted-default","FittedWB",body),("straight-equal-interface","StraightWB",symmetric)] {
            let document=try GarmentCodeNativeGenerator.generate(body:bodyValue,design:design(style,catalog:catalog)),before=try encode(document)
            log("START prepare \(tag)")
            let prepared=try A.prepare(document:document,body:bodyValue,settings:s,initialPlacement:placement)
            let result=try validate(prepared,document:document,style:style)
            try require(before==encode(document),"Assembly rewrote the original composed source")
            if tag=="straight-equal-interface" {try require(prepared.plan.foldIntervals.isEmpty,"Known equal-length interface was unnecessarily treated as ease")}
            else {try require(!prepared.plan.foldIntervals.isEmpty,"Unequal default interface pretends to be ordinary")}
            rows.append(result.merging(["case":tag]){_,b in b});try save(prepared,document:document,tag:tag,out:out)
            if tag=="straight-default"{defaultPrepared=prepared;defaultDocument=document}
            log("PASS prepare \(tag): \(prepared.cloth.positions.count)V / \(prepared.cloth.triangleIndices.count/3)T, six original seams, skirt free")
        }
        var cancelled=false
        do{_=try A.prepare(document:defaultDocument!,body:body,settings:s,initialPlacement:placement,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Pre-cancelled composed assembly returned an input")
        var alteredProperties=defaultDocument!.properties ?? [:];alteredProperties["unknown-source"] = .bool(true)
        let unknown=GarmentCodePatternFile(pattern:defaultDocument!.pattern,parameters:defaultDocument!.parameters,
            parameterOrder:defaultDocument!.parameterOrder,properties:alteredProperties)
        var rejected=false
        do{_=try A.prepare(document:unknown,body:body,settings:s,initialPlacement:placement)}catch K.DrapeError.unsupported{rejected=true}
        try require(rejected,"Unknown unequal imported interface acquired inferred eating/gather intent")
        let smokeResult:Any
        do {
            smokeResult=flag=="1" ? try smoke(defaultPrepared!,document:defaultDocument!,out:out,initialPlacement:placement) : NSNull()
        } catch {
            let failure:[String:Any]=["passed":false,"preparationPassed":true,"preparationCases":rows,
                "smokeRequested":true,"initialPlacement":placement.rawValue,"error":String(describing:error),
                "sourceSHA256":defaultPrepared!.sourceSHA256,"sourceAndPlanRetained":true,
                "scope":"Original strict 3D gates were not lowered. A solver rejection before returning Output cannot be represented as an accepted mesh; source/plan/reference remain available for diagnosis."]
            try JSONSerialization.data(withJSONObject:failure,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("skirt-waistband-summary.json"))
            throw error
        }
        let summary:[String:Any]=["passed":true,"preparationCases":rows,"preCancelledRejected":true,"unknownUnequalSourceRejected":true,
            "initialPlacement":placement.rawValue,
            "smokeRequested":flag=="1","smoke":smokeResult,
            "scope":"Full four-panel immutable source preparation: default Straight/Fitted known-native eased connectors and a real equal-length straight interface. Physics is only the explicitly requested default Straight .75 smoke; no all-dimensions, all-materials, continuous collision, physical fit or phone-performance claim."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("skirt-waistband-summary.json"))
        print(flag=="1" ? "PASS composed source preparation + strict default Straight 3D smoke" : "PASS three complete composed source preparations; physics not requested")
    }
}
