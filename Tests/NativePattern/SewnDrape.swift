import Foundation

/// Exercises the verified, non-welded assembly solver. Independent volume and
/// triangle tests use the actual visible body, rather than its coarse SDF.
@main @MainActor
struct SewnDrapeRegression {
    typealias T=SewnInputRegression
    typealias K=T.K
    typealias S=T.S
    typealias V=T.V
    struct Mesh:Codable {
        let positions:[V],triangleIndices:[UInt32],mannequinPositions:[V],mannequinTriangleIndices:[UInt32]
        let diagnostics:K.Diagnostics
    }
    struct Reference:Codable {let positions:[V],triangleIndices:[UInt32],sourceToSimulation:[Int]}
    struct Cell:Hashable {let a:Int,b:Int}
    struct Packet {let a:V;let e1u:Double,e1v:Double,e2u:Double,e2v:Double,det:Double,axis1:Double,axis2:Double}
    struct Parity:Codable {var outside=0,inside=0,ambiguous=0}
    struct CaseResult:Codable {
        let tag:String,sourceSHA256:String,separateParticleCount:Int,sewingConstraintCount:Int,solverIterations:Int
        let initialActualAnchorGapMeters:Double,finalActualAnchorGapMeters:Double,finalRMSAnchorGapMeters:Double
        let maximumIndependentSourceEdgeStrain:Double,independentBodyTriangleCrossings:Int
        let vertexVolume:Parity,centroidVolume:Parity
        let diagnostics:K.Diagnostics
    }
    struct BodyParity {
        let bins:[[Cell:[Packet]]]
        static let cell=0.025,epsilon=1e-7
        static func coord(_ p:V,_ axis:Int)->Double {axis==0 ? p.x : (axis==1 ? p.y : p.z)}
        @MainActor init(positions:[V],indices:[UInt32])throws {
            var edgeUses:[String:(Int,Int)]=[:],volume=0.0
            var all=Array(repeating:[Cell:[Packet]](),count:3)
            for offset in stride(from:0,to:indices.count,by:3) {
                let ids=(0..<3).map{Int(indices[offset+$0])},a=positions[ids[0]],b=positions[ids[1]],c=positions[ids[2]]
                volume += a.x*(b.y*c.z-b.z*c.y)+a.y*(b.z*c.x-b.x*c.z)+a.z*(b.x*c.y-b.y*c.x)
                for (x,y) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])] {
                    let key="\(min(x,y)):\(max(x,y))",old=edgeUses[key] ?? (0,0)
                    edgeUses[key]=(old.0+1,old.1+(x<y ? 1 : -1))
                }
                for axis in 0..<3 {
                    let u=(axis+1)%3,v=(axis+2)%3
                    let e1u=Self.coord(b,u)-Self.coord(a,u),e1v=Self.coord(b,v)-Self.coord(a,v)
                    let e2u=Self.coord(c,u)-Self.coord(a,u),e2v=Self.coord(c,v)-Self.coord(a,v),det=e1u*e2v-e1v*e2u
                    if abs(det)<1e-18 {continue}
                    let packet=Packet(a:a,e1u:e1u,e1v:e1v,e2u:e2u,e2v:e2v,det:det,axis1:Self.coord(b,axis)-Self.coord(a,axis),axis2:Self.coord(c,axis)-Self.coord(a,axis))
                    let loU=Int(floor(min(Self.coord(a,u),Self.coord(b,u),Self.coord(c,u))/Self.cell)),hiU=Int(floor(max(Self.coord(a,u),Self.coord(b,u),Self.coord(c,u))/Self.cell))
                    let loV=Int(floor(min(Self.coord(a,v),Self.coord(b,v),Self.coord(c,v))/Self.cell)),hiV=Int(floor(max(Self.coord(a,v),Self.coord(b,v),Self.coord(c,v))/Self.cell))
                    for i in loU...hiU {for j in loV...hiV {all[axis][.init(a:i,b:j),default:[]].append(packet)}}
                }
            }
            try T.require(edgeUses.values.allSatisfy{$0.0==2 && $0.1==0} && volume>0,"Volume oracle requires an outward closed two-manifold body")
            bins=all
        }
        func classify(_ points:[V])->Parity {
            var result=Parity()
            for p in points {
                var parities:[Bool]=[],uncertain=false
                for axis in 0..<3 {
                    let u=(axis+1)%3,v=(axis+2)%3,key=Cell(a:Int(floor(Self.coord(p,u)/Self.cell)),b:Int(floor(Self.coord(p,v)/Self.cell)))
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
                    parities.append(count%2==1)
                }
                if uncertain || Set(parities).count != 1 {result.ambiguous += 1}
                else if parities[0] {result.inside += 1}
                else {result.outside += 1}
            }
            return result
        }
    }
    static func volumeOracleCheck()throws {
        let p:[V]=[.init(x:-1,y:-1,z:-1),.init(x:1,y:-1,z:-1),.init(x:1,y:1,z:-1),.init(x:-1,y:1,z:-1),.init(x:-1,y:-1,z:1),.init(x:1,y:-1,z:1),.init(x:1,y:1,z:1),.init(x:-1,y:1,z:1)]
        let faces:[UInt32]=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]
        let oracle=try BodyParity(positions:p,indices:faces),q=oracle.classify([.init(x:0.13,y:0.21,z:0.17),.init(x:2,y:0.21,z:0.17),.init(x:1,y:0.21,z:0.17)])
        try T.require(q.inside==1 && q.outside==1 && q.ambiguous==1,"Independent ray parity failed known inside/outside/surface cube probes")
    }
    static func productionFixture(_ style:String,catalog:GarmentCodeParameterCatalog,body:GarmentCodeBodyParameters,iterations:Int=32)throws->T.Fixture {
        let independent=try T.waistband(style,catalog:catalog,body:body)
        var settings=independent.input.settings;settings.solverIterations=iterations
        let prepared=try GarmentCodeWaistbandAssembly.prepare(document:independent.document,body:body,settings:settings)
        try T.require(prepared.sourceSHA256==independent.plan.sourceSHA256 && prepared.cloth.referencePositions==independent.input.referencePositions && prepared.cloth.referenceTriangles==independent.input.referenceTriangles,"Production assembly differs from independently meshed original paper")
        try T.require(prepared.cloth.positions==independent.input.positions && prepared.cloth.pinned==independent.input.pinned && prepared.cloth.totalFabricMassKg==independent.input.totalFabricMassKg,"Production assembly changed initial placement, source pins or area mass")
        return .init(document:independent.document,input:prepared.cloth,bindings:independent.bindings,plan:prepared.plan)
    }
    static func perturbBottom(_ f:T.Fixture)throws->T.Fixture {
        var points=f.input.positions
        let attached=Set(f.plan.constraints.flatMap{$0.a.vertexIDs+$0.b.vertexIDs})
        let eligible=f.bindings[0].vertexIDs.filter{!f.input.pinned[$0] && attached.contains($0)}
        let bottom=eligible.map{points[$0].y}.min()!
        let chosen=eligible.filter{points[$0].y<=bottom+0.003}
        try T.require(!chosen.isEmpty,"No free bottom seam particle available for the closing regression")
        for id in chosen {
            let p=points[id],radius=sqrt(p.x*p.x+p.z*p.z)
            points[id]=p+V(x:p.x/radius*0.002,y:0,z:p.z/radius*0.002)
        }
        var change=T.Changes();change.positions=points
        let input=T.copy(f.input,change),source=T.sourceStitches(f.document),sha=try T.D.canonicalSourceSHA256(document:f.document)
        let hints=source.enumerated().map{S.StitchHint(stitchIndex:$0.offset,seamID:"side\($0.offset)",a:$0.element.a,b:$0.element.b,aDirection:.forward,bDirection:.reverse,rightWrong:$0.element.rightWrong,intent:.ordinary)}
        let plan=try S.build(bindings:f.bindings,positions:points,sourceStitches:source,actualSourceSHA256:sha,assembly:.init(sourceSHA256:sha,hints:hints))
        try T.require(points.indices.allSatisfy{!input.pinned[$0] || points[$0]==f.input.positions[$0]},"Perturbation moved a supported top corner")
        let gap=try S.inspect(positions:points,constraints:plan.constraints)
        try T.require(gap.maximumGapMeters>=0.0019 && gap.maximumGapMeters<=0.002001,"Perturbed case does not exercise a real 2 mm free seam gap")
        return .init(document:f.document,input:input,bindings:f.bindings,plan:plan)
    }
    static func run(_ f:T.Fixture,tag:String,out:URL)throws->CaseResult {
        let sourceBefore=try T.encode(f.document),planBefore=try T.encode(f.plan),initial=try S.inspect(positions:f.input.positions,constraints:f.plan.constraints)
        let verified=try T.validate(f)
        T.log("START \(tag): \(f.input.positions.count) separate particles, \(f.plan.constraints.count) actual seam constraints, \(f.input.settings.solverIterations) iterations, initial actual gap \(initial.maximumGapMeters)m")
        let result=try T.D.simulate(input:verified,maximumSewingProjectionTravelPerFrameMeters:0.2,maximumSewingSingleProjectionMeters:0.02)
        let mesh=Mesh(positions:result.positions,triangleIndices:result.triangleIndices,mannequinPositions:result.mannequinPositions,mannequinTriangleIndices:result.mannequinTriangleIndices,diagnostics:result.diagnostics)
        try T.encode(mesh).write(to:out.appendingPathComponent(tag+"-mesh.json"))
        try T.encode(result.diagnostics).write(to:out.appendingPathComponent(tag+"-diagnostics.json"))
        try sourceBefore.write(to:out.appendingPathComponent(tag+"-source.json"));try planBefore.write(to:out.appendingPathComponent(tag+"-plan.json"))
        try T.encode(Reference(positions:f.input.referencePositions,triangleIndices:f.input.referenceTriangles,sourceToSimulation:f.input.referenceToSimulation)).write(to:out.appendingPathComponent(tag+"-reference.json"))
        try T.require(f.input.springs.allSatisfy{abs($0.length-(f.input.referencePositions[$0.a]-f.input.referencePositions[$0.b]).length)<1e-12},"Runtime source edge does not retain its actual flat distance")
        let maximum=f.input.springs.map{spring in let rest=(f.input.referencePositions[spring.a]-f.input.referencePositions[spring.b]).length;return abs((result.positions[spring.a]-result.positions[spring.b]).length/rest-1)}.max()!
        let actual=BodySurfaceContactRegression.oracleCount(cloth:.init(positions:result.positions,indices:result.triangleIndices),body:.init(positions:result.mannequinPositions,indices:result.mannequinTriangleIndices))
        let volume=try BodyParity(positions:result.mannequinPositions,indices:result.mannequinTriangleIndices)
        let vertexVolume=volume.classify(result.positions)
        let centroids=stride(from:0,to:result.triangleIndices.count,by:3).map{i in (0..<3).reduce(V.zero){$0+result.positions[Int(result.triangleIndices[i+$1])]} / 3}
        let centroidVolume=volume.classify(centroids),sewing=try S.inspect(positions:result.positions,constraints:f.plan.constraints)
        let check=CaseResult(tag:tag,sourceSHA256:verified.sourceSHA256,separateParticleCount:f.input.positions.count,sewingConstraintCount:f.plan.constraints.count,solverIterations:f.input.settings.solverIterations,initialActualAnchorGapMeters:initial.maximumGapMeters,finalActualAnchorGapMeters:sewing.maximumGapMeters,finalRMSAnchorGapMeters:sewing.rmsGapMeters,maximumIndependentSourceEdgeStrain:maximum,independentBodyTriangleCrossings:actual,vertexVolume:vertexVolume,centroidVolume:centroidVolume,diagnostics:result.diagnostics)
        try T.encode(check).write(to:out.appendingPathComponent(tag+"-acceptance.json"))
        T.log("RESULT \(tag): converged=\(result.diagnostics.converged), source=\(maximum), actual seam=\(sewing.maximumGapMeters)m, final net speed=\(result.diagnostics.maxSpeedMetersPerSecond)m/s, actual body crossings=\(actual), self=\(result.diagnostics.surfaceIntersectionCount ?? -1), Mac seconds=\(result.diagnostics.computationSeconds)")
        try T.require(maximum<0.08 && result.diagnostics.maxSpeedMetersPerSecond<0.025,"Strict source/motion convergence failed")
        try T.require(abs(maximum-result.diagnostics.maxEdgeStrain)<1e-12,"Reported strain is not actual original source edge strain")
        try T.require(actual==0 && result.diagnostics.bodySurfaceIntersectionCount==0 && result.diagnostics.surfaceIntersectionCount==0,"Actual body or self surface crossing remains")
        try T.require(vertexVolume.inside==0 && vertexVolume.ambiguous==0 && centroidVolume.inside==0 && centroidVolume.ambiguous==0,"Actual body volume parity is inside or ambiguous")
        try T.require(result.diagnostics.maxBodyPenetrationMeters<0.003,"SDF penetration exceeds the original gate")
        try T.require(sewing.maximumGapMeters<0.0005 && abs(sewing.maximumGapMeters-result.diagnostics.maxSeamGapMeters)<1e-12,"Actual separate-particle seam anchors did not close within 0.5 mm")
        try T.require(result.diagnostics.converged,"Solver did not certify the unchanged full convergence gate")
        try T.require(result.positions.count==f.input.positions.count && result.triangleIndices==f.input.triangleIndices && f.input.referenceToSimulation==Array(f.input.positions.indices),"Assembly merged source degrees of freedom or changed source topology")
        try T.require(stride(from:0,to:result.triangleIndices.count,by:3).allSatisfy{i in let p=(0..<3).map{result.positions[Int(result.triangleIndices[i+$0])]};return (p[1]-p[0]).cross(p[2]-p[0]).length>1e-12},"Final sewn mesh has a degenerate actual triangle")
        try T.require(result.positions.indices.allSatisfy{!f.input.pinned[$0] || result.positions[$0]==f.input.positions[$0]},"Supported source particles moved")
        try T.require(result.diagnostics.totalFabricMassKg==f.input.totalFabricMassKg,"Solver changed source fabric mass")
        try T.require(result.diagnostics.sewingProjectionTravelBudgetMeters==0.2 && result.diagnostics.sewingSingleProjectionLimitMeters==0.02,"Numerical internal path budget and single-correction cap are not disclosed accurately")
        try T.require(sourceBefore==T.encode(f.document) && planBefore==T.encode(f.plan),"Solver changed source or plan")
        return check
    }
    static func main()throws {
        try volumeOracleCheck()
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_DRAPE_OUTPUT"] ?? "/private/tmp/TailorAssSewnDrape")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let catalog=try GarmentCodeParameterCatalog.load(from:T.root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),body=GarmentCodeBodyParameters(values:catalog.body)
        let resources=["GarmentCodeStandardBody.json","GarmentCodeStandardBodySource.json","GarmentCodeStandardBodySDF.bin"].map{T.root.appendingPathComponent("TrailorAss/Resources/"+$0)}
        let resourcesBefore=try resources.map{try Data(contentsOf:$0)}
        let selected=Set((ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_DRAPE_CASE_FILTER"] ?? "").split(separator:",").map(String.init))
        let iterations=Int(ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_DRAPE_ITERATIONS"] ?? "32") ?? 32
        try T.require(iterations==32 || iterations==24,"Only the App's 32-iteration configuration or explicit 24-iteration control may be selected")
        var results:[CaseResult]=[],first:T.Fixture?
        for style in ["StraightWB","FittedWB"] {
            let f=try productionFixture(style,catalog:catalog,body:body,iterations:iterations);if first==nil {first=f}
            for perturbed in [false,true] {
                let tag=style.lowercased()+(perturbed ? "-free-bottom-2mm" : "-default")
                if !selected.isEmpty && !selected.contains(tag){continue}
                results.append(try run(perturbed ? perturbBottom(f) : f,tag:tag,out:out))
            }
        }
        try T.require(!results.isEmpty,"No sewn drape case selected")
        let f=first!,verified=try T.validate(f),before=try T.encode(f.document)
        for budget in [0.0,0.500001,Double.nan] {
            var rejected=false
            do{_=try T.D.simulate(input:verified,maximumSewingProjectionTravelPerFrameMeters:budget)}catch K.DrapeError.invalid{rejected=true}
            try T.require(rejected,"Invalid numerical sewing travel budget was accepted")
        }
        for single in [0.0,0.100001,Double.nan] {
            var rejected=false
            do{_=try T.D.simulate(input:verified,maximumSewingSingleProjectionMeters:single)}catch K.DrapeError.invalid{rejected=true}
            try T.require(rejected,"Invalid single sewing correction limit was accepted")
        }
        var cancelled=false
        do{_=try GarmentCodeWaistbandAssembly.prepare(document:f.document,body:body,settings:f.input.settings,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try T.require(cancelled,"Pre-cancelled production assembly returned an input")
        let assemblyCounter=T.CancelCounter();cancelled=false
        do{_=try GarmentCodeWaistbandAssembly.prepare(document:f.document,body:body,settings:f.input.settings,isCancelled:{assemblyCounter.cancel()})}catch is CancellationError{cancelled=true}
        try T.require(cancelled,"Production assembly ignored in-progress cancellation")
        cancelled=false
        do{_=try T.D.simulate(input:verified,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try T.require(cancelled,"Pre-cancelled separate solver returned a pose")
        let counter=T.CancelCounter();cancelled=false
        do{_=try T.D.simulate(input:verified,isCancelled:{counter.cancel()})}catch is CancellationError{cancelled=true}
        try T.require(cancelled && before==T.encode(f.document),"Mid-solve cancellation returned a pose or changed source")
        try T.require(resourcesBefore==resources.map{try Data(contentsOf:$0)},"Separate solve changed body resources")
        struct Summary:Codable {let passed:Bool,sourceUnchanged:Bool,bodyResourcesUnchanged:Bool,cancellationVerified:Bool;let cases:[CaseResult];let scope:String}
        try T.encode(Summary(passed:true,sourceUnchanged:true,bodyResourcesUnchanged:true,cancellationVerified:true,cases:results,scope:"Separate source particles and genuine finite sewing constraints; actual body triangle intersections and independent three-axis volume parity checked. Mac timing is not an iPhone benchmark. Experimental presets and discrete contact do not certify continuous collision or physical fit.")).write(to:out.appendingPathComponent("sewn-drape-summary.json"))
        print("PASS \(results.count) non-welded WB cases: source, mass, pins, actual seam gaps, body triangle/volume and self contact, cancellation")
    }
}
