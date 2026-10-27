import Foundation
import CryptoKit

nonisolated private final class CircleAssemblyCancellation: @unchecked Sendable {
    private let lock=NSLock()
    private var calls=0
    func check()->Bool {lock.lock();defer{lock.unlock()};calls += 1;return calls>=4}
}

/// Default mode validates preparation only. The optional physical smoke test
/// explicitly enables the caller's .05 numerical strain limiter; nil-limiter
/// physics is not validated by this suite. CLI timing is not an iPhone result.
@main @MainActor
struct CircleAssemblyRegression {
    typealias K=GarmentCodeCircleDrape
    typealias S=GarmentCodeSewing
    typealias D=GarmentCodeSewnDrape
    typealias V=K.Vector3
    enum Failure:Error {case check(String)}
    struct Edge:Hashable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int){self.a=min(a,b);self.b=max(a,b)}
    }
    struct RestEdge:Codable {let a:Int,b:Int;let length:Double}
    struct Reference:Codable {
        let positions:[V],triangleIndices:[UInt32],sourceToSimulation:[Int]
        let initialPositions:[V],pinned:[Bool],restEdges:[RestEdge]
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
            try CircleAssemblyRegression.require(edges.values.allSatisfy{$0.0==2 && $0.1==0} && volume>0,"Body parity requires an outward closed two-manifold")
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
    static func require(_ condition:@autoclosure()throws->Bool,_ reason:String)throws {
        if try !condition(){throw Failure.check(reason)}
    }
    static func encode<T:Encodable>(_ value:T)throws->Data {
        let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)
    }
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func design(_ suns:Double,catalog:GarmentCodeParameterCatalog)->GarmentCodeDesignParameters {
        var d=GarmentCodeDesignParameters(catalog:catalog)
        _=d.setValue(.null,at:["meta","upper"]);_=d.setValue(.null,at:["meta","wb"])
        _=d.setValue(.string("SkirtCircle"),at:["meta","bottom"])
        _=d.setValue(.number(suns),at:["flare-skirt","suns"])
        _=d.setValue(.number(0.2),at:["flare-skirt","length"])
        _=d.setValue(.number(1),at:["flare-skirt","rise"])
        _=d.setValue(.bool(false),at:["flare-skirt","cut","add"])
        return d
    }
    static func settings(root:URL,limiter:Double?=nil)->K.Settings {
        var s=K.Settings();s.bodyMode = .standardMannequin;s.material = .medium
        s.useSurfaceCollision=true;s.useBodySurfaceCollision=true;s.solverIterations=32
        s.sourceStrainLimit=limiter;s.sourceStrainLimitPasses=40
        s.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        return s
    }

    static func validatePreparation(_ prepared:D.PreparedInput,document:GarmentCodePatternFile,
                                    suns:Double,body:GarmentCodeBodyParameters,settings:K.Settings)throws->[String:Any] {
        let input=prepared.cloth,geometry=try document.geometryPanels(),names=["skirt_front","skirt_back"]
        try require(Set(geometry.keys)==Set(names),"Source panels were omitted")
        try require(prepared.sourceSHA256==hash(encode(document)),"Source SHA differs from independent canonical encoding")
        try require(input.settings.sourceStrainLimit==settings.sourceStrainLimit && input.settings.sourceStrainLimitPasses==40,"Factory changed the caller's optional limiter")
        try require(input.referenceToSimulation==Array(input.positions.indices) && input.referencePositions.count==input.positions.count,"Source particles were merged")
        try require(input.seamVertexPairs.isEmpty && input.seamPaths.count==4 && prepared.plan.sharedTopologicalCornerAnchors==0,"Independent seams were replaced by welded particle pairs")
        let flat=input.referencePositions
        var expectedFlat:[V]=[],expectedReference:[UInt32]=[],expectedSimulation:[UInt32]=[],expectedPins=Set<Int>()
        var originalTop=0.0,originalHem=0.0,analyticArea=0.0,sourcePerimeter=0.0
        var panelCounts:[String:Int]=[:],boundaryCount=0
        let paths=Dictionary(uniqueKeysWithValues:prepared.plan.allBoundaryPaths.map{($0.edge,$0)})
        for (index,name) in names.enumerated() {
            let panel=geometry[name]!,top=index==0 ? 3 : 0,hem=index==0 ? 1 : 2
            let inner=panel.edges[top].curvature!.circle!.radius/100,outer=panel.edges[hem].curvature!.circle!.radius/100
            let topLength=panel.edges[top].length()/100,hemLength=panel.edges[hem].length()/100,angle=topLength/inner
            try require(abs(angle-Double.pi*suns)<1e-7 && abs(hemLength/outer-angle)<1e-7,"Source annular angles changed")
            originalTop += topLength;originalHem += hemLength;analyticArea += angle*(outer*outer-inner*inner)/2
            sourcePerimeter += panel.edges.reduce(0){$0+$1.length()/100}
            let mesh=try GarmentCodePanelMesher.prepare(panel:panel,targetEdgeMeters:settings.targetEdgeMeters,maximumVertices:4000,maximumTriangles:12000)
            let offset=expectedFlat.count;expectedFlat += mesh.flatPositions;panelCounts[name]=mesh.flatPositions.count
            for i in stride(from:0,to:mesh.triangleIndices.count,by:3) {
                let ids=(0..<3).map{UInt32(offset)+mesh.triangleIndices[i+$0]}
                expectedReference += ids;var normal=ids;if mesh.sourceClockwise {normal.swapAt(1,2)}
                expectedSimulation += normal
            }
            for boundary in mesh.boundaries {
                boundaryCount += 1
                let key=S.EdgeKey(panelID:name,edgeIndex:boundary.edgeIndex)
                guard let path=paths[key] else {throw Failure.check("Missing original source boundary")}
                try require(path.vertexIDs==boundary.vertexIDs.map{offset+$0} && path.edgeID==boundary.edgeID,"Boundary IDs or panel provenance changed")
                try require(path.sourceParameters==boundary.sourceParameters && path.sourceArcFractions==boundary.arcFractions,"Source boundary sampling changed")
                let edge=panel.edges[boundary.edgeIndex]
                try require(abs(path.sourceLengthMeters-edge.length()/100)<1e-9,"Original source boundary length changed")
                for j in path.vertexIDs.indices {
                    let t=path.sourceParameters[j],p=edge.point(at:t),actual=flat[path.vertexIDs[j]]
                    try require((actual-V(x:p.x/100,y:p.y/100,z:0)).length<1e-9,"Boundary particle is not on the real source curve")
                    // Every supported edge has constant parameter speed:
                    // straight line or circle. Its true arc fraction is t.
                    try require(abs(path.sourceArcFractions[j]-t)<1e-8,"Circle/line arc fraction differs from its analytic constant-speed value")
                }
                if boundary.edgeIndex==top {expectedPins.formUnion(path.vertexIDs)}
            }
        }
        try require(flat==expectedFlat && input.referenceTriangles==expectedReference && input.triangleIndices==expectedSimulation,"Actual source geometry, CCW reference faces or original simulation normals changed")
        try require(paths.count==boundaryCount && input.positions.count<=8000,"Missing boundary or source vertex budget exceeded")
        try require(input.pinned.indices.allSatisfy{input.pinned[$0]==expectedPins.contains($0)},"Source top-boundary support pins changed")
        try require(abs(originalTop-body["waist"]!/100)<1e-8 && abs(input.waistCircumferenceMeters-originalTop)<1e-9 && abs(input.hemCircumferenceMeters-originalHem)<1e-9,"Natural waist or original hem circumference changed")
        var area=0.0,vertexAreas=Array(repeating:0.0,count:flat.count),sourceEdges:[Edge:Double]=[:],adjacent:[Edge:[Int]]=[:]
        for i in stride(from:0,to:input.referenceTriangles.count,by:3) {
            let ids=(0..<3).map{Int(input.referenceTriangles[i+$0])},a=flat[ids[0]],b=flat[ids[1]],c=flat[ids[2]]
            let signed=(b-a).cross(c-a).z/2
            try require(signed>1e-14,"Reference triangle is degenerate or not CCW")
            area += signed;for id in ids {vertexAreas[id] += signed/3}
            for (x,y,z) in [(ids[0],ids[1],ids[2]),(ids[1],ids[2],ids[0]),(ids[2],ids[0],ids[1])] {
                sourceEdges[.init(x,y)]=(flat[x]-flat[y]).length;adjacent[.init(x,y),default:[]].append(z)
            }
        }
        try require(abs(area-analyticArea)<=sourcePerimeter*0.00005+1e-9 && abs(area-input.referenceAreaSquareMeters)<1e-10,"Source analytic or triangulated fabric area changed")
        let maxEdge=sourceEdges.values.max()!
        try require(maxEdge<=settings.targetEdgeMeters*(1+1e-6),"Generic source triangle edge exceeds the requested cap")
        let actualEdges=Dictionary(uniqueKeysWithValues:input.springs.map{(Edge($0.a,$0.b),$0.length)})
        try require(actualEdges.count==input.springs.count && actualEdges.count==sourceEdges.count,"A source edge is missing or duplicated")
        for (edge,length) in sourceEdges {try require(abs((actualEdges[edge] ?? -1)-length)<1e-12,"Structural rest metric differs from the actual source triangle edge")}
        let expectedBends=Set(adjacent.values.filter{$0.count==2}.map{Edge($0[0],$0[1])}.filter{$0.a != $0.b && sourceEdges[$0]==nil})
        try require(Set(input.bendingSprings.map{Edge($0.a,$0.b)})==expectedBends,"Opposite-vertex bends are not the original within-panel hinges")
        for edge in input.bendingSprings {try require(abs(edge.length-(flat[edge.a]-flat[edge.b]).length)<1e-12,"Bend changed its source distance")}
        let density=settings.material!.parameters.arealDensityKgPerSquareMeter,totalMass=area*density,mean=totalMass/Double(flat.count)
        try require(abs((input.totalFabricMassKg ?? -1)-totalMass)<1e-12 && abs(input.meanParticleMassKg-mean)<1e-14,"Independent area-mass integration differs")
        for i in flat.indices {
            let wanted=input.pinned[i] ? 0 : mean/(vertexAreas[i]*density)
            try require(abs(input.inverseMasses[i]-wanted)<=max(1e-12,abs(wanted)*1e-9),"Separate source particle mass or zero pin weight changed")
        }
        try require(!prepared.plan.constraints.isEmpty && prepared.plan.foldIntervals.isEmpty && !prepared.plan.usesFiniteCoarseTacks,"Ordinary circle side seams were replaced by inferred gathering")
        for anchor in prepared.plan.anchors {
            let stitch=document.pattern.stitches[anchor.stitchIndex]
            try require(anchor.a.edge == .init(panelID:stitch.sides[0].panel,edgeIndex:stitch.sides[0].edge) && anchor.b.edge == .init(panelID:stitch.sides[1].panel,edgeIndex:stitch.sides[1].edge),"Plan omits or changes a real source stitch")
            try require(abs(anchor.a.sourceArcFraction-anchor.normalizedSeamFraction)<1e-10 && abs(anchor.b.sourceArcFraction-(1-anchor.normalizedSeamFraction))<1e-10,"Known ordinary A-forward/B-reverse direction changed")
            try require(Set(anchor.a.attachment.vertexIDs).isDisjoint(with:Set(anchor.b.attachment.vertexIDs)),"Sewing attachment silently shares source particles")
        }
        let gap=try S.inspect(positions:input.positions,constraints:prepared.plan.constraints)
        try require(gap.maximumGapMeters<1e-7,"Initial continuous cone has a mismatched side seam")
        return ["suns":suns,"sourceSHA256":prepared.sourceSHA256,"sourceUnchanged":true,"panelVertexCounts":panelCounts,
            "independentParticleCount":flat.count,"triangleCount":input.referenceTriangles.count/3,"sourceEdgeCount":sourceEdges.count,
            "sourceAreaSquareMeters":area,"sourceMassKg":totalMass,"maximumSourceEdgeMeters":maxEdge,
            "actualInitialSeamGapMeters":gap.maximumGapMeters,"sewingConstraintCount":prepared.plan.constraints.count,
            "callerSourceStrainLimit":settings.sourceStrainLimit.map{$0 as Any} ?? NSNull(),"sourceStrainLimitPasses":settings.sourceStrainLimitPasses]
    }

    static func smoke(_ document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,root:URL,out:URL)throws->[String:Any] {
        let s=settings(root:root,limiter:0.05),before=try encode(document)
        let prepared=try GarmentCodeCircleAssembly.prepare(document:document,body:body,settings:s)
        _=try validatePreparation(prepared,document:document,suns:0.75,body:body,settings:s)
        log("START optional Circle .75 smoke: caller explicitly enables .05/40 strain limiting; 32 solver iterations, .2 m sewing path/.02 m single correction; Mac timing is not an iPhone benchmark")
        let result=try D.simulate(input:prepared,maximumSewingProjectionTravelPerFrameMeters:0.2,maximumSewingSingleProjectionMeters:0.02)
        try encode(result).write(to:out.appendingPathComponent("circle-0.75-mesh.json"))
        try result.objString.write(to:out.appendingPathComponent("circle-0.75.obj"),atomically:true,encoding:.utf8)
        let input=prepared.cloth,d=result.diagnostics
        let strain=input.springs.map{abs((result.positions[$0.a]-result.positions[$0.b]).length/(input.referencePositions[$0.a]-input.referencePositions[$0.b]).length-1)}.max()!
        let gap=try S.inspect(positions:result.positions,constraints:prepared.plan.constraints)
        let crossing=BodySurfaceContactRegression.oracleCount(cloth:.init(positions:result.positions,indices:result.triangleIndices),body:.init(positions:result.mannequinPositions,indices:result.mannequinTriangleIndices))
        let volume=try BodyVolume(positions:result.mannequinPositions,indices:result.mannequinTriangleIndices)
        let vertices=volume.classify(result.positions)
        let centers=stride(from:0,to:result.triangleIndices.count,by:3).map{i in (0..<3).reduce(V.zero){$0+result.positions[Int(result.triangleIndices[i+$1])]} / 3}
        let centroids=volume.classify(centers)
        try require(d.converged && strain<0.08 && d.maxSpeedMetersPerSecond<0.025,"Unchanged source/motion gates failed")
        try require(abs(strain-d.maxEdgeStrain)<1e-12 && gap.maximumGapMeters<0.0005 && abs(gap.maximumGapMeters-d.maxSeamGapMeters)<1e-12,"Actual source strain or sewing gap differs from diagnostics/gates")
        try require(crossing==0 && d.bodySurfaceIntersectionCount==0 && d.surfaceIntersectionCount==0 && d.maxBodyPenetrationMeters<0.003,"Body/self contact or original penetration gates failed")
        try require(vertices.inside==0 && vertices.ambiguous==0 && centroids.inside==0 && centroids.ambiguous==0,"Independent body volume is inside or ambiguous")
        try require(result.positions.count==input.positions.count && result.triangleIndices==input.triangleIndices && input.referenceToSimulation==Array(input.positions.indices),"Independent source particles or topology changed")
        try require(result.positions.indices.allSatisfy{!input.pinned[$0] || result.positions[$0]==input.positions[$0]},"Supported source particles moved")
        try require(result.diagnostics.totalFabricMassKg==input.totalFabricMassKg && before==encode(document),"Source paper or source mass changed")
        try require(d.sourceStrainLimitFraction==0.05 && d.sourceStrainLimitPassCount==40 && d.sewingProjectionTravelBudgetMeters==0.2 && d.sewingSingleProjectionLimitMeters==0.02,"Explicit numerical smoke settings were not preserved")
        struct Volumes:Codable {let vertices:Parity,triangleCentroids:Parity}
        try encode(Volumes(vertices:vertices,triangleCentroids:centroids)).write(to:out.appendingPathComponent("circle-0.75-volume.json"))
        log("PASS optional .75 smoke: source \(strain), actual seam \(gap.maximumGapMeters)m, body/self0, independent volume outside; Mac CLI seconds \(d.computationSeconds)")
        return ["passed":true,"maximumIndependentSourceStrain":strain,"actualSeamGapMeters":gap.maximumGapMeters,
            "independentBodyTriangleCrossings":crossing,"insideVertices":vertices.inside,"ambiguousVertices":vertices.ambiguous,
            "insideCentroids":centroids.inside,"ambiguousCentroids":centroids.ambiguous,"macComputationSeconds":d.computationSeconds,
            "sourceStrainLimitFraction":0.05,"sourceStrainLimitPasses":40,"solverIterations":32,
            "sewingProjectionTravelBudgetMeters":0.2,"sewingSingleProjectionLimitMeters":0.02]
    }

    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let env=ProcessInfo.processInfo.environment,flag=env["GARMENTCODE_CIRCLE_ASSEMBLY_SMOKE"] ?? "0"
        try require(flag=="0" || flag=="1","GARMENTCODE_CIRCLE_ASSEMBLY_SMOKE must be 0 or 1")
        let out=URL(fileURLWithPath:env["GARMENTCODE_CIRCLE_ASSEMBLY_OUTPUT"] ?? "/private/tmp/TailorAssCircleAssembly")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),body=GarmentCodeBodyParameters(values:catalog.body)
        let bodyBefore=try encode(body),s=settings(root:root)
        var rows:[[String:Any]]=[],smokeDocument:GarmentCodePatternFile?
        for suns in [0.5,0.75,1.0] {
            let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(suns,catalog:catalog)),before=try encode(document)
            let prepared=try GarmentCodeCircleAssembly.prepare(document:document,body:body,settings:s)
            rows.append(try validatePreparation(prepared,document:document,suns:suns,body:body,settings:s))
            try require(before==encode(document) && bodyBefore==encode(body),"Preparation changed source paper or body parameters")
            try before.write(to:out.appendingPathComponent("circle-\(suns)-source.json"))
            try encode(prepared.plan).write(to:out.appendingPathComponent("circle-\(suns)-plan.json"))
            let input=prepared.cloth
            try encode(Reference(positions:input.referencePositions,triangleIndices:input.referenceTriangles,
                sourceToSimulation:input.referenceToSimulation,initialPositions:input.positions,pinned:input.pinned,
                restEdges:input.springs.map{.init(a:$0.a,b:$0.b,length:$0.length)})).write(to:out.appendingPathComponent("circle-\(suns)-reference.json"))
            if suns==0.75 {smokeDocument=document}
            log("PASS prepare suns\(suns): \(input.positions.count) independent source particles; caller limiter=nil, physics not run")
        }
        var cancelled=false
        do{_=try GarmentCodeCircleAssembly.prepare(document:smokeDocument!,body:body,settings:s,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Pre-cancelled circle preparation returned an input")
        let counter=CircleAssemblyCancellation();cancelled=false
        do{_=try GarmentCodeCircleAssembly.prepare(document:smokeDocument!,body:body,settings:s,isCancelled:{counter.check()})}catch is CancellationError{cancelled=true}
        try require(cancelled,"In-progress circle preparation ignored cancellation")
        let smokeResult:Any=flag=="1" ? try smoke(smokeDocument!,body:body,root:root,out:out) : NSNull()
        let summary:[String:Any]=["passed":true,"preparationCases":rows,"preparationCancellationVerified":true,
            "smokeRequested":flag=="1","smoke":smokeResult,
            "scope":"Default: source-faithful preparation only for suns .5/.75/1, caller limiter=nil; no nil-limiter physics claim. Optional .75 3D smoke explicitly enables .05/40 and preserves32iterations/.2m cumulative/.02m single sewing correction and all original quality gates. Mac CLI timing is not an iPhone measurement; experimental/discrete results do not certify physical fit or continuous collision."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("circle-assembly-summary.json"))
        print(flag=="1" ? "PASS circle preparation + explicit optional .75 strict smoke" : "PASS 3 circle preparations; 3D smoke NOT requested or run; nil-limiter physics remains unverified")
    }
}
