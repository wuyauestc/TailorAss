import Foundation
import CryptoKit

nonisolated private final class UpperTorsoCancellation: @unchecked Sendable {
    private let lock=NSLock()
    private var calls=0
    func check() -> Bool { lock.lock();defer { lock.unlock() };calls += 1;return calls>=4 }
}

/// Complete four-panel preparation; optional real 3D solves retain all gates.
@main @MainActor
struct UpperTorsoAssemblyRegression {
    typealias K=GarmentCodeCircleDrape
    typealias V=K.Vector3
    typealias S=GarmentCodeSewing
    typealias D=GarmentCodeSewnDrape
    enum Failure:Error {case check(String)}
    struct Edge:Hashable {let a:Int,b:Int;init(_ a:Int,_ b:Int){self.a=min(a,b);self.b=max(a,b)}}
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
            try UpperTorsoAssemblyRegression.require(edges.values.allSatisfy{$0.0==2 && $0.1==0} && volume>0,"Body parity requires an outward closed two-manifold")
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
    static func encode<T:Encodable>(_ value:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func design(_ style:String,_ variant:String,catalog:GarmentCodeParameterCatalog)->GarmentCodeDesignParameters {
        var d=GarmentCodeDesignParameters(catalog:catalog)
        _=d.setValue(.string(style),at:["meta","upper"]);_=d.setValue(.null,at:["meta","bottom"]);_=d.setValue(.null,at:["meta","wb"])
        _=d.setValue(.bool(true),at:["sleeve","sleeveless"]);_=d.setValue(.null,at:["collar","component","style"])
        if variant=="asymmetric" {_=d.setValue(.bool(true),at:["left","enable_asym"]);_=d.setValue(.number(1.10),at:["left","shirt","width"])}
        if variant=="strapless" {_=d.setValue(.bool(true),at:["shirt","strapless"])}
        if variant=="square" {_=d.setValue(.string("SquareNeckHalf"),at:["collar","f_collar"]);_=d.setValue(.string("ArmholeSquare"),at:["sleeve","armhole_shape"])}
        return d
    }
    static func check(_ p:D.PreparedInput,document:GarmentCodePatternFile)throws->[String:Any] {
        let input=p.cloth,flat=input.referencePositions
        try require(p.sourceSHA256==hash(encode(document)),"Full source SHA differs")
        try require(Set(p.panelBindings.map{$0.mesh.panelID})==Set(document.pattern.panels.keys) && p.panelBindings.count==4,"Source torso was omitted")
        try require(input.referenceToSimulation==Array(flat.indices) && input.positions.count==flat.count && input.seamVertexPairs.isEmpty,"Source particles were welded or substituted")
        var edges:[Edge:Double]=[:],area=0.0,vertexArea=Array(repeating:0.0,count:flat.count),covered=Set<Int>(),coveredFaces=Set<Int>()
        let geometry=try document.geometryPanels()
        for binding in p.panelBindings {
            let mesh=binding.mesh,panel=geometry[mesh.panelID]!
            for (i,id) in binding.vertexIDs.enumerated(){try require(covered.insert(id).inserted && flat[id]==mesh.flatPositions[i],"Source vertex changed or shared across panels")}
            for (i,face) in binding.triangleIDs.enumerated() {
                try require(coveredFaces.insert(face).inserted,"Source face repeated")
                let local=(0..<3).map{Int(mesh.triangleIndices[i*3+$0])},ids=local.map{binding.vertexIDs[$0]}
                let signed=(flat[ids[1]]-flat[ids[0]]).cross(flat[ids[2]]-flat[ids[0]]).z/2
                try require(signed>1e-14,"Source triangle is not actual CCW paper")
                area += signed;for id in ids{vertexArea[id] += signed/3}
                for (a,b) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])]{edges[.init(a,b)]=(flat[a]-flat[b]).length}
                try require((0..<3).map{Int(input.referenceTriangles[face*3+$0])}==ids,"Source triangle changed")
                var facing=ids;if mesh.sourceClockwise{facing.swapAt(1,2)}
                try require((0..<3).map{Int(input.triangleIndices[face*3+$0])}==facing,"Original source normal changed")
            }
            for boundary in mesh.boundaries {
                let edge=panel.edges[boundary.edgeIndex]
                try require(abs(edge.length()/100-boundary.sourceLengthMeters)<1e-9 && boundary.edgeID==edge.id,"Source boundary metric/identity changed")
                for i in boundary.vertexIDs.indices {
                    let q=edge.point(at:boundary.sourceParameters[i]),actual=mesh.flatPositions[boundary.vertexIDs[i]]
                    try require((actual-V(x:q.x/100,y:q.y/100,z:0)).length<1e-9,"Mesh moved the original source curve")
                }
            }
        }
        try require(covered==Set(flat.indices) && coveredFaces==Set(0..<input.referenceTriangles.count/3),"Incomplete source cover")
        try require(input.springs.count==edges.count && Set(input.springs.map{Edge($0.a,$0.b)}).count==edges.count,"Source edge omitted or duplicated")
        for e in input.springs {try require(abs(e.length-(edges[.init(e.a,e.b)] ?? -1))<1e-12,"Structural edge does not use actual source length")}
        let density=input.settings.material!.parameters.arealDensityKgPerSquareMeter,mass=area*density,mean=mass/Double(flat.count)
        try require(abs(input.referenceAreaSquareMeters-area)<1e-12 && abs(input.totalFabricMassKg!-mass)<1e-12 && abs(input.meanParticleMassKg-mean)<1e-14,"Source area/mass changed")
        for id in flat.indices {let wanted=input.pinned[id] ? 0 : mean/(vertexArea[id]*density);try require(abs(input.inverseMasses[id]-wanted)<max(1e-12,abs(wanted)*1e-10),"Original particle mass or pin weight changed")}
        let fixed=input.pinned.filter{$0}.count
        try require(fixed>0 && fixed<=8,"Auxiliary support silently became a pinned torso/rim")
        try require(Set(p.plan.anchors.map(\.stitchIndex))==Set(document.pattern.stitches.indices),"Real source dart/side/shoulder/centre stitch was omitted")
        for c in p.plan.constraints {
            if c.a.vertexIDs.allSatisfy({input.pinned[$0]}) && c.b.vertexIDs.allSatisfy({input.pinned[$0]}) {
                let gap=(try c.a.point(in:input.positions)-c.b.point(in:input.positions)).length
                try require(gap<1e-6,"Two incompatible fixed supports prevent an actual source seam from closing")
            }
        }
        let gap=try S.inspect(positions:input.positions,constraints:p.plan.constraints)
        return ["passed":true,"sourceSHA256":p.sourceSHA256,"panels":4,"sourceStitches":document.pattern.stitches.count,
            "independentParticles":flat.count,"sourceFaces":input.referenceTriangles.count/3,"sourceEdges":edges.count,
            "auxiliaryFixedSourceParticles":fixed,"sourceAreaSquareMeters":area,"sourceMassKg":mass,
            "initialActualSeamGapMeters":gap.maximumGapMeters,"finiteFoldIntervals":p.plan.foldIntervals.count]
    }
    /// Diagnostic decomposition of a real rejected pose. None of these copied
    /// buffers is published as an accepted cloth result.
    static func projectionProbe(_ p:D.PreparedInput,frame:URL,out:URL)throws {
        struct Frame:Decodable {let kind:String,sourceSHA256:String,positions:[[Double]],referencePositions:[[Double]],triangleIndices:[UInt32]}
        let f=try JSONDecoder().decode(Frame.self,from:Data(contentsOf:frame)),input=p.cloth
        let original=f.positions.map{V(x:$0[0],y:$0[1],z:$0[2])}
        try require(f.kind=="rejected_upper_torso_debug_frame" && f.sourceSHA256==p.sourceSHA256 && original.count==input.positions.count && f.triangleIndices==input.triangleIndices,
                    "Projection probe frame is not this complete source/topology")
        try require(f.referencePositions.map{V(x:$0[0],y:$0[1],z:$0[2])}==input.referencePositions,"Projection probe source metrics differ")
        let topology=input.surfaceTopology!,bodyMesh=input.bodySurfaceMesh!,body=input.standardBody!
        var rows:[[String:Any]]=[]
        func inspect(_ name:String,_ points:[V],from:[V])throws {
            let strain=input.springs.map{abs((points[$0.a]-points[$0.b]).length/$0.length-1)}.sorted()
            let gap=try S.inspect(positions:points,constraints:p.plan.constraints)
            let selfQuality=try GarmentCodeClothContact.inspect(positions:points,topology:topology,thickness:0.005)
            let bodyQuality=try GarmentCodeBodySurfaceContact.inspect(positions:points,topology:topology,body:bodyMesh,thickness:input.settings.bodySurfaceClearanceMeters)
            let maximumMove=zip(points,from).map{($0-$1).length}.max()!
            rows.append(["stage":name,"maxSourceStrain":strain.last!,"p95SourceStrain":strain[Int(Double(strain.count)*0.95)],"meanSourceStrain":strain.reduce(0,+)/Double(strain.count),"actualGapMeters":gap.maximumGapMeters,"selfCrossings":selfQuality.intersectingTrianglePairs,"bodyCrossings":bodyQuality.intersectingTrianglePairs,"SDFMaxPenetrationMeters":points.map{body.penetration($0)}.max()!,"maximumStageMoveMeters":maximumMove])
            log("PROBE \(name): source=\(strain.last!), gap=\(gap.maximumGapMeters), move=\(maximumMove), self/body=\(selfQuality.intersectingTrianglePairs)/\(bodyQuality.intersectingTrianglePairs)")
        }
        try inspect("actual-rejected-frame",original,from:original)
        var source=original,state=try S.State(constraintCount:p.plan.constraints.count,vertexCount:source.count)
        let limiter=try K.SourceStrainLimiter(vertexCount:source.count,springs:input.springs,normalizedInverseMass:input.inverseMasses,maximumAbsoluteStrain:0.05)
        for i in 0..<40 {
            _=try limiter.project(positions:&source,reverseOrder:i%2 != 0)
            _=try S.project(positions:&source,constraints:p.plan.constraints,normalizedInverseMass:input.inverseMasses,state:&state,timeStep:1.0/120,physicalCompliance:1e-8,meanParticleMassKg:input.meanParticleMassKg,rampFraction:1,maximumVertexCorrectionPerFrameMeters:0.2,maximumSingleVertexCorrectionMeters:0.02)
        }
        try inspect("40-source-and-sewing-only",source,from:original)
        var sdf=source
        for i in sdf.indices where !input.pinned[i]{sdf[i]=body.project(sdf[i],thickness:0.0025)}
        try inspect("then-SDF-2.5mm",sdf,from:source)
        var selfContact=sdf
        _=try GarmentCodeClothContact.project(positions:&selfContact,previousPositions:sdf,inverseMass:input.inverseMasses,topology:topology,thickness:0.005)
        try inspect("then-cloth-5mm",selfContact,from:sdf)
        var bodyContact=selfContact
        _=try GarmentCodeBodySurfaceContact.project(positions:&bodyContact,inverseMass:input.inverseMasses,topology:topology,body:bodyMesh,thickness:input.settings.bodySurfaceClearanceMeters,previousPositions:selfContact)
        try inspect("then-body-mesh-0.5mm",bodyContact,from:selfContact)
        var final=bodyContact
        for i in final.indices where !input.pinned[i]{final[i]=body.project(final[i],thickness:0.0025)}
        try inspect("then-final-SDF",final,from:bodyContact)
        let proof:[String:Any]=["acceptanceClaimed":false,"sourceSHA256":p.sourceSHA256,"actualRejectedFrame":frame.path,"previousPositionsNote":"Single-stage probes use the same incoming pose as previous; they diagnose projection conflicts and do not reproduce a dynamic time step.","sewingAccumulatedPathMaxMeters":state.accumulatedCorrectionsMeters.max() ?? 0,"stages":rows]
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("projection-probe.json"))
    }
    static func smoke(_ p:D.PreparedInput,tag:String,out:URL)throws->[String:Any] {
        let input=p.cloth
        let env=ProcessInfo.processInfo.environment
        guard let staticFrames=Int(env["GARMENTCODE_UPPER_TORSO_STATIC_FRAMES"] ?? "0"),let rampFrames=Int(env["GARMENTCODE_UPPER_TORSO_GRAVITY_RAMP_FRAMES"] ?? "0"),
              (0...1200).contains(staticFrames),(0...1200).contains(rampFrames),staticFrames+rampFrames<input.settings.maximumSteps else {throw Failure.check("Invalid explicit upper assembly schedule")}
        log("START actual \(tag): \(input.positions.count)V, \(input.triangleIndices.count/3)T, \(p.plan.constraints.count) true constraints; 32/40/.05/.2/.02, original gates")
        let result=try D.simulate(input:p,schedule:.init(staticFrames:staticFrames,gravityRampFrames:rampFrames),maximumSewingProjectionTravelPerFrameMeters:0.2,maximumSewingSingleProjectionMeters:0.02,
            progress: { value in
                let percent=Int(value*100)
                if percent%10 == 0 { FileHandle.standardError.write(Data(("PHYSICS \(tag): \(percent)%\n").utf8)) }
            })
        try encode(result).write(to:out.appendingPathComponent(tag+"-mesh.json"));try result.objString.write(to:out.appendingPathComponent(tag+".obj"),atomically:true,encoding:.utf8)
        let strain=input.springs.map{abs((result.positions[$0.a]-result.positions[$0.b]).length/(input.referencePositions[$0.a]-input.referencePositions[$0.b]).length-1)}.max()!
        let gap=try S.inspect(positions:result.positions,constraints:p.plan.constraints)
        let crossings=BodySurfaceContactRegression.oracleCount(cloth:.init(positions:result.positions,indices:result.triangleIndices),body:.init(positions:result.mannequinPositions,indices:result.mannequinTriangleIndices))
        let volume=try BodyVolume(positions:result.mannequinPositions,indices:result.mannequinTriangleIndices)
        let vertices=volume.classify(result.positions),centers=stride(from:0,to:result.triangleIndices.count,by:3).map{i in (0..<3).reduce(V.zero){$0+result.positions[Int(result.triangleIndices[i+$1])]} / 3},centroids=volume.classify(centers)
        let d=result.diagnostics
        let passed=d.converged && strain<0.08 && d.maxSpeedMetersPerSecond<0.025 && gap.maximumGapMeters<0.0005 && crossings==0 && d.bodySurfaceIntersectionCount==0 && d.surfaceIntersectionCount==0 && d.maxBodyPenetrationMeters<0.003 && vertices.inside==0 && vertices.ambiguous==0 && centroids.inside==0 && centroids.ambiguous==0
        let proof:[String:Any]=["passed":passed,"maximumIndependentSourceStrain":strain,"actualSeamGapMeters":gap.maximumGapMeters,"independentBodyCrossings":crossings,"vertexVolume":["outside":vertices.outside,"inside":vertices.inside,"ambiguous":vertices.ambiguous],"centroidVolume":["outside":centroids.outside,"inside":centroids.inside,"ambiguous":centroids.ambiguous],"finalSpeedMetersPerSecond":d.maxSpeedMetersPerSecond,"selfCrossings":d.surfaceIntersectionCount ?? -1,"productionBodyCrossings":d.bodySurfaceIntersectionCount ?? -1,"productionConverged":d.converged,"macSeconds":d.computationSeconds,"staticAssemblyFrames":staticFrames,"gravityRampFrames":rampFrames]
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent(tag+"-acceptance.json"))
        log("RESULT \(tag): passed=\(passed), source=\(strain), gap=\(gap.maximumGapMeters)m, speed=\(d.maxSpeedMetersPerSecond), self=\(d.surfaceIntersectionCount ?? -1), body=\(crossings), inside=\(vertices.inside)/\(centroids.inside), Mac sec=\(d.computationSeconds)")
        try require(abs(strain-d.maxEdgeStrain)<1e-12 && abs(gap.maximumGapMeters-d.maxSeamGapMeters)<1e-12,"Actual quality differs from diagnostics")
        try require(result.positions.count==input.positions.count && result.triangleIndices==input.triangleIndices && result.positions.indices.allSatisfy{!input.pinned[$0] || result.positions[$0]==input.positions[$0]},"Source/pins/topology changed")
        try require(passed,"Strict complete-torso physics gates failed; actual failure retained")
        return proof
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let env=ProcessInfo.processInfo.environment,out=URL(fileURLWithPath:env["GARMENTCODE_UPPER_TORSO_OUTPUT"] ?? "/private/tmp/TailorAssUpperTorso")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),body=GarmentCodeBodyParameters(values:catalog.body)
        var settings=K.Settings();settings.bodyMode = .standardMannequin;settings.material = .medium;settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.solverIterations=32;settings.sourceStrainLimit=0.05;settings.sourceStrainLimitPasses=40;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        let selected=Set((env["GARMENTCODE_UPPER_TORSO_CASE_FILTER"] ?? "").split(separator:",").map(String.init)),smokes=Set((env["GARMENTCODE_UPPER_TORSO_SMOKE"] ?? "").split(separator:",").map(String.init))
        var rows:[[String:Any]]=[],failures:[String]=[]
        for (style,variant) in [("Shirt","default"),("FittedShirt","default"),("Shirt","asymmetric"),("FittedShirt","asymmetric"),("FittedShirt","strapless"),("Shirt","square")] {
            let tag=style.lowercased()+"-"+variant;if !selected.isEmpty && !selected.contains(tag){continue}
            do {
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(style,variant,catalog:catalog)),before=try encode(document)
                log("PREPARE \(tag)")
                let prepared=try GarmentCodeUpperTorsoAssembly.prepare(document:document,body:body,settings:settings)
                var proof=try check(prepared,document:document);proof["tag"]=tag
                try before.write(to:out.appendingPathComponent(tag+"-source.json"));try encode(prepared.plan).write(to:out.appendingPathComponent(tag+"-plan.json"))
                struct Reference:Codable{let flat:[V],triangles:[UInt32],initial:[V],fixed:[Bool]}
                try encode(Reference(flat:prepared.cloth.referencePositions,triangles:prepared.cloth.referenceTriangles,initial:prepared.cloth.positions,fixed:prepared.cloth.pinned)).write(to:out.appendingPathComponent(tag+"-reference.json"))
                if let frame=env["GARMENTCODE_UPPER_TORSO_PROJECTION_PROBE"] {try projectionProbe(prepared,frame:URL(fileURLWithPath:frame),out:out)}
                if smokes.contains(tag) || smokes.contains("1") {proof["physics"]=try smoke(prepared,tag:tag,out:out)}else{proof["physics"]=NSNull()}
                try require(before==encode(document),"Native upper preparation changed source document")
                rows.append(proof);log("PASS prepare \(tag): \(prepared.cloth.positions.count) independent particles, \(document.pattern.stitches.count) complete source seams")
            }catch{failures.append("\(tag): \(error)");log("FAIL \(tag): \(error)")}
        }
        var cancellationVerified=false,sourceMismatchRejected=false,additionalComponentsRejected=false
        do {
            let source=try GarmentCodeNativeGenerator.generate(body:body,design:design("Shirt","default",catalog:catalog))
            var immediate=false,delayed=false
            do{_=try GarmentCodeUpperTorsoAssembly.prepare(document:source,body:body,settings:settings,isCancelled:{true})}catch is CancellationError{immediate=true}
            let counter=UpperTorsoCancellation()
            do{_=try GarmentCodeUpperTorsoAssembly.prepare(document:source,body:body,settings:settings,isCancelled:{counter.check()})}catch is CancellationError{delayed=true}
            cancellationVerified=immediate && delayed
            var properties=source.properties ?? [:];properties["unverified_upper_probe"] = .bool(true)
            let mismatched=GarmentCodePatternFile(pattern:source.pattern,parameters:source.parameters,parameterOrder:source.parameterOrder,properties:properties)
            do{_=try GarmentCodeUpperTorsoAssembly.prepare(document:mismatched,body:body,settings:settings)}catch K.DrapeError.unsupported{sourceMismatchRejected=true}
            var sleeved=design("Shirt","default",catalog:catalog);_=sleeved.setValue(.bool(false),at:["sleeve","sleeveless"])
            let complete=try GarmentCodeNativeGenerator.generate(body:body,design:sleeved)
            do{_=try GarmentCodeUpperTorsoAssembly.prepare(document:complete,body:body,settings:settings)}catch K.DrapeError.unsupported{additionalComponentsRejected=true}
            try require(cancellationVerified && sourceMismatchRejected && additionalComponentsRejected,"Cancellation, complete source SHA mismatch or additional panel omission contract failed")
            log("PASS upper contracts: immediate/periodic cancellation, full source mismatch, no silent sleeve/component omission")
        }catch{failures.append("contracts: \(error)");log("FAIL upper contracts: \(error)")}
        try require(!rows.isEmpty || !failures.isEmpty,"Empty selection is not an acceptance run")
        let result:[String:Any]=["passed":failures.isEmpty,"cases":rows,"failures":failures,"selectedCases":Array(selected).sorted(),"requestedSmokes":Array(smokes).sorted(),"cancellationVerified":cancellationVerified,"fullSourceMismatchRejected":sourceMismatchRejected,"additionalComponentsRejected":additionalComponentsRejected,"scope":"Four complete source torso panels only; additional collar/sleeve/outfit components remain unsupported. Preparation is not a drape result. Only explicitly requested successful physics are claimed. Supports and material are uncalibrated experiments; Mac times are not iPhone performance."]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("upper-torso-summary.json"))
        try require(failures.isEmpty,"Actual upper torso failures retained: \(failures)")
    }
}
