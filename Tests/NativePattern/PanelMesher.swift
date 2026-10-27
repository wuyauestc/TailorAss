import Foundation

/// Generic flat-panel acceptance checks use source curves and official source
/// fixtures, independently of the triangulator's own area/quality counters.
#if !PANEL_MESHER_INTEGRATION
@main
#endif
@MainActor
struct PanelMesherRegression {
    typealias Mesher=GarmentCodePanelMesher
    typealias V=GarmentCodeCircleDrape.Vector3
    enum Failure:Error {case check(String)}
    struct EdgeKey:Hashable {
        let a:Int,b:Int
        init(_ x:Int,_ y:Int){a=min(x,y);b=max(x,y)}
    }
    struct CurveOracle {
        let points:[V],lengths:[Double]
        let length:Double
        func fraction(_ t:Double)->Double {
            let value=max(0,min(1,t))*Double(points.count-1),i=min(points.count-2,Int(value)),u=value-Double(i)
            return (lengths[i]*(1-u)+lengths[i+1]*u)/lengths.last!
        }
    }
    static func require(_ value:@autoclosure()->Bool,_ message:String)throws {if !value(){throw Failure.check(message)}}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func point(_ edge:GarmentCodeGeometryEdge,_ t:Double)->V {let p=edge.point(at:t);return .init(x:p.x/100,y:p.y/100,z:0)}
    static func cross(_ a:V,_ b:V)->Double {a.x*b.y-a.y*b.x}
    static func area(_ points:[V])->Double {points.indices.reduce(0.0){$0+cross(points[$1],points[($1+1)%points.count])}/2}
    static func distance(_ p:V,_ a:V,_ b:V)->Double {
        let d=b-a,t=d.lengthSquared>0 ? max(0,min(1,((p.x-a.x)*d.x+(p.y-a.y)*d.y)/d.lengthSquared)) : 0
        return (p-a-d*t).length
    }
    static func inside(_ p:V,polygon:[V],tolerance:Double=1e-10)->Bool {
        var odd=false
        for i in polygon.indices {
            let a=polygon[i],b=polygon[(i+1)%polygon.count]
            if distance(p,a,b)<=tolerance{return true}
            if (a.y>p.y) != (b.y>p.y),p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x {odd.toggle()}
        }
        return odd
    }
    static func properCross(_ a:V,_ b:V,_ c:V,_ d:V)->Bool {
        let ab=b-a,cd=d-c
        let p=cross(ab,c-a),q=cross(ab,d-a),r=cross(cd,a-c),s=cross(cd,b-c)
        return p*q < -1e-22 && r*s < -1e-22
    }
    static func curveOracle(_ edge:GarmentCodeGeometryEdge)->CurveOracle {
        let n=edge.curvature == nil ? 1 : 8192
        var points:[V]=[],lengths=[0.0]
        for i in 0...n {
            let p=point(edge,Double(i)/Double(n))
            if let previous=points.last {lengths.append(lengths.last!+(p-previous).length)}
            points.append(p)
        }
        let coarseLength=n==1 ? lengths.last! : stride(from:0,to:n,by:2).reduce(0.0) {
            $0+(points[min(n,$1+2)]-points[$1]).length
        }
        // Independent chord integration has O(h²) error. Extrapolate two
        // actual sampling resolutions rather than rejecting a correct large
        // circular arc against the uncorrected 8192-chord approximation.
        let length=n==1 ? lengths.last! : (4*lengths.last!-coarseLength)/3
        return .init(points:points,lengths:lengths,length:length)
    }
    static func polygon(_ name:String,_ coordinates:[[Double]])->GarmentCodePanelGeometry {
        .init(id:name,edges:coordinates.indices.map {i in
            let a=coordinates[i],b=coordinates[(i+1)%coordinates.count]
            return .init(id:"\(name)-e\(i)",start:.init(x:a[0],y:a[1]),end:.init(x:b[0],y:b[1]),curvature:nil,label:nil)
        })
    }

    static func check(_ mesh:Mesher.Mesh,panel:GarmentCodePanelGeometry,target:Double,flatness:Double)throws->[String:Any] {
        let points=mesh.flatPositions
        try require(mesh.panelID==panel.id,"Mesh panel identity does not match the original source")
        try require(!points.isEmpty && points.allSatisfy{$0.isFinite && abs($0.z)<1e-12},"Rest mesh is not finite source XY geometry")
        try require(mesh.triangleIndices.count%3==0 && !mesh.triangleIndices.isEmpty,"Missing triangle topology")
        try require(mesh.boundaries.count==panel.edges.count,"Source edge identity was dropped")
        let curves=panel.edges.map(curveOracle)
        let denseSource=curves.flatMap{Array($0.points.dropLast())}
        let coarseSource=curves.flatMap {curve -> [V] in
            curve.points.count==2 ? Array(curve.points.dropLast()) :
                stride(from:0,to:curve.points.count-1,by:2).map {curve.points[$0]}
        }
        let sourceArea=(4*area(denseSource)-area(coarseSource))/3
        let sourcePerimeter=curves.reduce(0.0){$0+$1.length}
        try require(mesh.sourceClockwise==(sourceArea<0),"Original source orientation was lost")
        try require(abs(mesh.sourceSignedAreaSquareMeters-sourceArea)<1e-8,"Source area differs from independent dense Green integral")
        var boundaryPolygon:[V]=[],boundaryEdges=Set<EdgeKey>(),maximumDeviation=0.0
        for i in panel.edges.indices {
            let edge=panel.edges[i],b=mesh.boundaries[i],oracle=curves[i]
            try require(b.edgeIndex==i && b.edgeID==edge.id,"Original edge index/ID correspondence changed")
            try require(b.vertexIDs.count>=2 && b.vertexIDs.count==b.sourceParameters.count && b.vertexIDs.count==b.arcFractions.count,"Incomplete boundary samples")
            try require(abs(b.sourceParameters.first!)<1e-12 && abs(b.sourceParameters.last!-1)<1e-12,"Boundary source parameter endpoints missing")
            try require(abs(b.arcFractions.first!)<1e-12 && abs(b.arcFractions.last!-1)<1e-12,"Boundary arc fraction endpoints missing")
            try require(zip(b.sourceParameters,b.sourceParameters.dropFirst()).allSatisfy{$0<$1},"Boundary parameters must retain original edge direction")
            try require(zip(b.arcFractions,b.arcFractions.dropFirst()).allSatisfy{$0<$1},"Arc fractions are not strictly monotone")
            try require(abs(b.sourceLengthMeters-oracle.length)<1e-7,"Boundary length changed the original source curve")
            for j in b.vertexIDs.indices {
                let id=b.vertexIDs[j]
                try require(points.indices.contains(id),"Invalid source-to-mesh boundary index")
                try require((points[id]-point(edge,b.sourceParameters[j])).length<1e-9,"A boundary vertex is not on its original source curve")
                try require(abs(b.arcFractions[j]-oracle.fraction(b.sourceParameters[j]))<1e-6,"Arc fraction was approximated by parameter or polyline length")
            }
            for (a,c) in zip(b.vertexIDs,b.vertexIDs.dropFirst()) {try require(a != c,"Collapsed boundary segment");boundaryEdges.insert(.init(a,c))}
            let next=mesh.boundaries[(i+1)%panel.edges.count]
            try require(b.vertexIDs.last==next.vertexIDs.first,"Adjacent source edges do not share their actual original corner")
            boundaryPolygon += b.vertexIDs.dropLast().map{points[$0]}
            // Sample the exact source curve densely, rather than merely
            // trusting a midpoint/chord test (which misses symmetric S curves).
            let samples=edge.curvature == nil ? 1 : 1024
            for k in 0...samples {
                let p=point(edge,Double(k)/Double(samples))
                let error=zip(b.vertexIDs,b.vertexIDs.dropFirst()).map {distance(p,points[$0.0],points[$0.1])}.min()!
                maximumDeviation=max(maximumDeviation,error)
            }
        }
        try require(maximumDeviation<=flatness*1.001+1e-9,"Curve flattening exceeded requested physical deviation")
        try require(mesh.maximumBoundaryDeviationMeters<=flatness*1.001+1e-9,"Mesher disclosed an out-of-range boundary approximation")
        try require(mesh.maximumBoundaryDeviationMeters+1e-8>=maximumDeviation,"Boundary deviation metric understates independently sampled curve error")
        let polygonArea=abs(area(boundaryPolygon))
        try require(abs(mesh.flattenedAreaSquareMeters-polygonArea)<1e-10,"Flattened area does not match actual sampled boundary")
        try require(abs(polygonArea-abs(sourceArea))<=sourcePerimeter*flatness*1.5+1e-8,"Sampled polygon lost source area beyond its curve error bound")

        var incidence:[EdgeKey:[(Int,Int)]]=[:],totalArea=0.0,maxEdge=0.0,minAngle=Double.infinity
        var used=Set<Int>(),triangles:[[Int]]=[]
        for i in stride(from:0,to:mesh.triangleIndices.count,by:3) {
            let ids=(0..<3).map{Int(mesh.triangleIndices[i+$0])}
            try require(ids.allSatisfy{points.indices.contains($0)} && Set(ids).count==3,"Invalid triangle indices")
            used.formUnion(ids);triangles.append(ids)
            let a=points[ids[0]],b=points[ids[1]],c=points[ids[2]],signed=cross(b-a,c-a)/2
            try require(signed>1e-14,"Triangle winding/area is degenerate instead of CCW")
            totalArea += signed
            for (j,k) in [(0,1),(1,2),(2,0)] {
                let x=ids[j],y=ids[k]
                incidence[.init(x,y),default:[]].append((x,y))
                maxEdge=max(maxEdge,(points[x]-points[y]).length)
            }
            for j in 0..<3 {
                let u=points[ids[(j+1)%3]]-points[ids[j]],v=points[ids[(j+2)%3]]-points[ids[j]]
                let cosine=max(-1,min(1,(u.x*v.x+u.y*v.y)/(u.length*v.length)))
                minAngle=min(minAngle,acos(cosine)*180/Double.pi)
            }
            // The sampled boundary is a simple polygon without holes. Every
            // triangle's vertices, edges and interior must stay inside it.
            for p in [a,b,c,(a+b)/2,(b+c)/2,(c+a)/2,(a+b+c)/3] {
                try require(inside(p,polygon:boundaryPolygon),"A triangle crossed a concave source cutout")
            }
        }
        try require(used.count==points.count,"Unreferenced mesh vertices hide dropped boundary samples")
        try require(abs(totalArea-polygonArea)<max(1e-10,polygonArea*1e-9),"Triangles overlap or leave a hole in the original flat panel")
        let actualBoundary=Set(incidence.filter{$0.value.count==1}.map{$0.key})
        try require(actualBoundary==boundaryEdges,"Mesh boundary does not preserve every original sampled edge")
        for uses in incidence.values {
            try require(uses.count<=2,"Non-manifold flat mesh")
            if uses.count==2 {try require(uses[0].0==uses[1].1 && uses[0].1==uses[1].0,"Inconsistent interior triangle winding")}
        }
        try require(points.count-incidence.count+triangles.count==1,"A simple source panel must remain a topological disk")
        var adjacency=Array(repeating:[Int](),count:points.count)
        for key in incidence.keys {adjacency[key.a].append(key.b);adjacency[key.b].append(key.a)}
        var reachable=Set<Int>(),stack=[0]
        while let id=stack.popLast() {if reachable.insert(id).inserted {stack += adjacency[id]}}
        try require(reachable.count==points.count,"Flat panel was split into disconnected mesh components")
        for key in incidence.keys where !boundaryEdges.contains(key) {
            for boundary in boundaryEdges where ![key.a,key.b].contains(boundary.a) && ![key.a,key.b].contains(boundary.b) {
                try require(!properCross(points[key.a],points[key.b],points[boundary.a],points[boundary.b]),"An internal diagonal cuts across an original boundary")
            }
        }
        try require(maxEdge<=target*(1+1e-6),"Final refinement/edge flip exceeded target edge length")
        try require(mesh.quality.vertexCount==points.count && mesh.quality.triangleCount==triangles.count,"Quality counts do not describe the actual mesh")
        try require(abs(mesh.quality.maximumEdgeMeters-maxEdge)<1e-9 && abs(mesh.quality.minimumAngleDegrees-minAngle)<1e-5,"Quality metrics disagree with independent triangle measurements")
        return ["panel":panel.id,"vertices":points.count,"triangles":triangles.count,"sourceAreaSquareMeters":sourceArea,"flatAreaSquareMeters":totalArea,"maximumEdgeMeters":maxEdge,"minimumAngleDegrees":minAngle,"maximumBoundaryDeviationMeters":maximumDeviation,"clockwiseSource":mesh.sourceClockwise]
    }

    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_PANEL_MESH_OUTPUT_DIR"] ?? "/private/tmp/TailorAssPanelMesher")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let target=0.03,flatness=0.00005
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        var summaries:[[String:Any]]=[],failures:[String]=[]
        func run(_ panel:GarmentCodePanelGeometry,tag:String)throws {
            let before=try encoder.encode(panel)
            let mesh=try Mesher.prepare(panel:panel,targetEdgeMeters:target,flatnessMeters:flatness)
            let result=try check(mesh,panel:panel,target:target,flatness:flatness)
            let after=try encoder.encode(panel)
            try require(before==after,"Triangulation changed source panel geometry or edge identity")
            summaries.append(result.merging(["case":tag]){_,b in b})
            let artifact:[String:Any]=["positions":mesh.flatPositions.map{[$0.x,$0.y,$0.z]},"triangleIndices":mesh.triangleIndices.map(Int.init),"boundaries":mesh.boundaries.map{["edgeIndex":$0.edgeIndex,"edgeID":$0.edgeID,"vertexIDs":$0.vertexIDs,"sourceParameters":$0.sourceParameters,"arcFractions":$0.arcFractions,"sourceLengthMeters":$0.sourceLengthMeters] as [String:Any]},"independentChecks":result]
            try JSONSerialization.data(withJSONObject:artifact,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent(tag+"-mesh.json"),options:.atomic)
            try before.write(to:directory.appendingPathComponent(tag+"-source.json"),options:.atomic)
            log("PASS \(tag): V=\(mesh.flatPositions.count) T=\(mesh.triangleIndices.count/3) maxEdge=\(mesh.quality.maximumEdgeMeters) minAngle=\(mesh.quality.minimumAngleDegrees)")
        }
        let fixtures:[(String,[String])]=[
            ("waistband-straight",["wb_front","wb_back"]),
            ("waistband-fitted",["wb_front","wb_back"]),
            ("shirt",["left_ftorso","left_btorso"]),
            ("shirt-armhole-ArmholeSquare",["left_ftorso"]),
            ("pants",["pant_f_l","pant_b_l"]),
            ("skirt-two-panel-cut",["skirt_front"]),
            ("fitted-shirt",["left_ftorso","left_btorso"])
        ]
        for (name,panels) in fixtures {
            let source=root.appendingPathComponent("Tests/NativePattern/Fixtures/"+name+".json")
            let bytes=try Data(contentsOf:source)
            let geometry=try GarmentCodePatternFile.validatedImport(from:bytes).geometryPanels()
            for id in panels {
                do {guard let panel=geometry[id] else {throw Failure.check("Missing pinned fixture panel \(id)")};try run(panel,tag:name+"-"+id)}
                catch {failures.append("\(name)/\(id): \(error)");log("FAIL \(name)/\(id): \(error)")}
            }
            let after=try Data(contentsOf:source)
            try require(bytes==after,"Meshing rewrote an upstream fixture")
        }
        let concave=polygon("concave-U",[[0,0],[60,0],[60,60],[40,60],[40,20],[20,20],[20,60],[0,60]])
        var sCurve=polygon("short-S-inflection",[[0,0],[2,0],[2,30],[0,30]])
        sCurve.edges[0].curvature = .init(type:"cubic",params:[[0.2,5],[0.8,-5]])
        for panel in [concave,.init(id:"concave-U-reversed",edges:concave.edges.reversed().map{$0.reversed()}),sCurve] {
            do {try run(panel,tag:panel.id)} catch {failures.append("\(panel.id): \(error)");log("FAIL \(panel.id): \(error)")}
        }
        for radius in [15.0,20.0] {for large in [false,true] {for right in [false,true] {
            let name="diameter-semicircle-r\(radius)-large\(large)-right\(right)"
            var panel=polygon(name,[[-20,0],[20,0]])
            panel.edges[0].curvature = .init(circleRadius:radius,largeArc:large,right:right)
            do {
                let mesh=try Mesher.prepare(panel:panel,targetEdgeMeters:target)
                try require(abs(abs(mesh.sourceSignedAreaSquareMeters)-Double.pi*0.2*0.2/2)<1e-10,
                            "Diameter semicircle must retain its independent analytic area")
                try require(mesh.flatPositions.allSatisfy{right ? $0.y<=1e-12:$0.y >= -1e-12},
                            "Large-arc flag must not flip a diameter source mesh across its chord")
                try run(panel,tag:name)
            } catch {failures.append("\(name): \(error)");log("FAIL \(name): \(error)")}
        }}}
        do {
            let p=polygon("local-seam-refinement",[[0,0],[40,0],[40,8],[0,8]])
            let baseline=try Mesher.prepare(panel:p,targetEdgeMeters:target)
            let empty=try Mesher.prepare(panel:p,targetEdgeMeters:target,maximumBoundarySpacingMeters:[:])
            let baselineBytes=try encoder.encode(baseline),emptyBytes=try encoder.encode(empty)
            try require(baselineBytes==emptyBytes,"Empty boundary overrides changed the existing default mesh")
            let refined=try Mesher.prepare(panel:p,targetEdgeMeters:target,maximumBoundarySpacingMeters:[0:0.005])
            _=try check(refined,panel:p,target:target,flatness:flatness)
            let b=refined.boundaries[0]
            try require(b.vertexIDs.count>baseline.boundaries[0].vertexIDs.count &&
                zip(b.arcFractions,b.arcFractions.dropFirst()).allSatisfy{($1-$0)*b.sourceLengthMeters<=0.005*(1+1e-10)},
                "Local boundary refinement did not bound true source arc spacing")
            for edge in 1..<p.edges.count {
                try require(refined.boundaries[edge].sourceParameters==baseline.boundaries[edge].sourceParameters,
                            "A local refinement changed another source edge's sampling")
            }
            for invalid in [[-1:0.01],[4:0.01],[0:0.0001],[0:Double.nan]] {
                var rejected=false
                do{_=try Mesher.prepare(panel:p,maximumBoundarySpacingMeters:invalid)}catch Mesher.MesherError.invalid{rejected=true}
                try require(rejected,"Invalid local boundary spacing was silently accepted")
            }
            log("PASS local source-edge refinement: true arc spacing, other boundaries and default mesh preserved; invalid overrides rejected")
        }catch{failures.append("local-refinement: \(error)");log("FAIL local-refinement: \(error)")}
        do {
            var cancelled=false
            do {_=try Mesher.prepare(panel:concave,isCancelled:{true})} catch is CancellationError {cancelled=true}
            try require(cancelled,"Cancelled triangulation returned a mesh")
            var budget=false
            do {_=try Mesher.prepare(panel:concave,targetEdgeMeters:0.01,maximumVertices:16)} catch Mesher.MesherError.budgetExceeded {budget=true}
            try require(budget,"Vertex exhaustion silently coarsened or truncated source geometry")
            budget=false
            do {_=try Mesher.prepare(panel:concave,maximumTriangles:16)} catch Mesher.MesherError.budgetExceeded {budget=true}
            try require(budget,"Triangle exhaustion returned an incomplete flat panel")
            // Nonzero signed area prevents a simple area-zero guard from
            // masquerading as proper self-intersection validation.
            let bowtie=polygon("bowtie",[[0,0],[100,100],[0,100],[80,0]])
            var open=concave;open.edges[0].end.x += 1
            var zero=concave;zero.edges[0].end=zero.edges[0].start
            var nonfinite=concave;nonfinite.edges[0].start.y = .nan
            for p in [bowtie,open,zero,nonfinite] {
                var rejected=false
                do {_=try Mesher.prepare(panel:p)} catch Mesher.MesherError.invalid {rejected=true}
                try require(rejected,"Invalid/self-intersecting/degenerate source panel was silently repaired")
            }
        } catch {failures.append("failure-contracts: \(error)");log("FAIL failure-contracts: \(error)")}
        let report:[String:Any]=["passed":failures.isEmpty,"failures":failures,"panels":summaries,"targetEdgeMeters":target,"flatnessMeters":flatness,"scope":"Flat source-panel triangulation acceptance; not a sewn 3D garment or a physical drape claim."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("panel-mesher-summary.json"),options:.atomic)
        if !failures.isEmpty {throw Failure.check(failures.joined(separator:"\n"))}
        print("PASS: \(summaries.count) source-faithful flat panel meshes, independent boundaries/area/manifold/quality, cancellation and explicit failure contracts")
    }
}
