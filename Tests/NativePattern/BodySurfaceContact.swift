import Foundation

/// Geometric body-surface regressions. The independent oracle tests proper
/// triangle intersections against the visible body, without an SDF lookup.
#if !BODY_SURFACE_INTEGRATION
@main
#endif
struct BodySurfaceContactRegression {
    typealias Contact = GarmentCodeBodySurfaceContact
    typealias Cloth = GarmentCodeClothContact
    typealias V = GarmentCodeCircleDrape.Vector3
    enum Failure: Error { case check(String) }
    struct Mesh { let positions: [V]; let indices: [UInt32] }
    struct Face {
        let a: V, b: V, c: V, low: V, high: V, normal: V
        init(_ a: V, _ b: V, _ c: V) {
            self.a=a;self.b=b;self.c=c
            low = v(min(a.x,b.x,c.x),min(a.y,b.y,c.y),min(a.z,b.z,c.z))
            high = v(max(a.x,b.x,c.x),max(a.y,b.y,c.y),max(a.z,b.z,c.z))
            let n=(b-a).cross(c-a);normal=n.length>1e-15 ? n/n.length : .zero
        }
        func overlaps(_ other: Face) -> Bool {
            low.x<=other.high.x && other.low.x<=high.x && low.y<=other.high.y && other.low.y<=high.y && low.z<=other.high.z && other.low.z<=high.z
        }
    }
    static func v(_ x: Double,_ y: Double,_ z: Double)->V {.init(x:x,y:y,z:z)}
    static func dot(_ a: V,_ b: V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    static func segmentDistance(_ a:V,_ b:V,_ c:V,_ d:V)->Double {
        let u=b-a,w=d-c,r=a-c,aa=dot(u,u),bb=dot(u,w),cc=dot(w,w),dd=dot(u,r),ee=dot(w,r),denominator=aa*cc-bb*bb
        var s=denominator>1e-20 ? max(0,min(1,(bb*ee-cc*dd)/denominator)) : 0
        var t=(bb*s+ee)/cc
        if t<0 {t=0;s=max(0,min(1,-dd/aa))}
        if t>1 {t=1;s=max(0,min(1,(bb-dd)/aa))}
        return (a+u*s-c-w*t).length
    }
    static func require(_ value: @autoclosure ()->Bool,_ message: String)throws {if !value(){throw Failure.check(message)}}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func faces(_ mesh:Mesh)->[Face] {
        stride(from:0,to:mesh.indices.count,by:3).map {
            Face(mesh.positions[Int(mesh.indices[$0])],mesh.positions[Int(mesh.indices[$0+1])],mesh.positions[Int(mesh.indices[$0+2])])
        }
    }
    /// Moller/Trumbore segment/triangle hit. Plane straddles and a nonzero
    /// intersection segment are checked separately, so touches are excluded.
    static func hit(_ start:V,_ end:V,_ face:Face)->V? {
        let direction=end-start,e1=face.b-face.a,e2=face.c-face.a,p=direction.cross(e2),det=dot(e1,p)
        if abs(det)<1e-15{return nil}
        let offset=start-face.a,u=dot(offset,p)/det
        if u < -1e-9 || u > 1+1e-9{return nil}
        let q=offset.cross(e1),w=dot(direction,q)/det,t=dot(e2,q)/det
        if w < -1e-9 || u+w > 1+1e-9 || t < -1e-9 || t > 1+1e-9{return nil}
        return start+direction*t
    }
    static func properCross(_ a:Face,_ b:Face)->Bool {
        if !a.overlaps(b) || a.normal.lengthSquared<0.5 || b.normal.lengthSquared<0.5{return false}
        let da=[dot(a.a-b.a,b.normal),dot(a.b-b.a,b.normal),dot(a.c-b.a,b.normal)]
        let db=[dot(b.a-a.a,a.normal),dot(b.b-a.a,a.normal),dot(b.c-a.a,a.normal)]
        guard da.min()! < -1e-9,da.max()! > 1e-9,db.min()! < -1e-9,db.max()! > 1e-9 else{return false}
        let points=[hit(a.a,a.b,b),hit(a.b,a.c,b),hit(a.c,a.a,b),hit(b.a,b.b,a),hit(b.b,b.c,a),hit(b.c,b.a,a)].compactMap{$0}
        for p in points {for q in points where (p-q).length>1e-7{return true}}
        return false
    }
    static func oracleCount(cloth:Mesh,body:Mesh)->Int {
        let first=faces(cloth),second=faces(body)
        var count=0
        for a in first {for b in second where a.overlaps(b) {if properCross(a,b){count += 1}}}
        return count
    }
    static func tetra(apexZ:Double=0.10,baseZ:Double = -0.10,size:Double=0.04)->Mesh {
        let positions=[v(0,0,apexZ),v(-size,-size/sqrt(3),baseZ),v(size,-size/sqrt(3),baseZ),v(0,2*size/sqrt(3),baseZ)]
        let center=positions.reduce(.zero,+)/4
        var indices:[UInt32]=[]
        for ids in [[0,1,2],[0,2,3],[0,3,1],[1,3,2]] {
            var a=ids
            let normal=(positions[a[1]]-positions[a[0]]).cross(positions[a[2]]-positions[a[0]])
            let midpoint=(positions[a[0]]+positions[a[1]]+positions[a[2]])/3
            if dot(normal,midpoint-center)<0 {a.swapAt(1,2)}
            indices += a.map(UInt32.init)
        }
        return .init(positions:positions,indices:indices)
    }
    static func box(center:V,half:V)->Mesh {
        let p=[v(-1,-1,-1),v(1,-1,-1),v(1,1,-1),v(-1,1,-1),v(-1,-1,1),v(1,-1,1),v(1,1,1),v(-1,1,1)]
            .map{center+v($0.x*half.x,$0.y*half.y,$0.z*half.z)}
        return .init(positions:p,indices:[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5])
    }
    static func reverse(_ mesh:Mesh)->Mesh {
        var indices=mesh.indices
        for i in stride(from:0,to:indices.count,by:3){indices.swapAt(i+1,i+2)}
        return .init(positions:mesh.positions,indices:indices)
    }
    static func combine(_ a:Mesh,_ b:Mesh)->Mesh {.init(positions:a.positions+b.positions,indices:a.indices+b.indices.map{$0+UInt32(a.positions.count)})}
    static func body(_ mesh:Mesh)throws->Contact.BodyMesh {try .init(positions:mesh.positions,triangleIndices:mesh.indices)}
    static func topology(_ mesh:Mesh)throws->Cloth.Topology {try .init(vertexCount:mesh.positions.count,triangleIndices:mesh.indices)}
    static func repair(_ positions:inout[V],indices:[UInt32],body:Contact.BodyMesh,weights:[Double],thickness:Double=0.005,passes:Int=96)throws->Int {
        let t=try Cloth.Topology(vertexCount:positions.count,triangleIndices:indices)
        var performed=0
        for _ in 0..<passes {
            _=try Contact.project(positions:&positions,inverseMass:weights,topology:t,body:body,thickness:thickness)
            performed += 1
            let q=try Contact.inspect(positions:positions,topology:t,body:body,thickness:thickness)
            if q.intersectingTrianglePairs==0 {break}
        }
        return performed
    }
    static func insideConvex(_ p:V,mesh:Mesh)->Bool {faces(mesh).allSatisfy{dot(p-$0.a,$0.normal)<(-1e-7)}}

    static func syntheticChecks()throws {
        let solid=tetra(),fixed=try body(solid)
        let sheet=Mesh(positions:[v(-0.4,-0.4,0),v(0.4,-0.4,0),v(0,0.4,0)],indices:[0,1,2])
        let top=try topology(sheet)
        try require(sheet.positions.allSatisfy{!insideConvex($0,mesh:solid)},"Face-poke fixture must have every cloth vertex outside the solid")
        let expected=oracleCount(cloth:sheet,body:solid)
        let before=try Contact.inspect(positions:sheet.positions,topology:top,body:fixed,thickness:0.005)
        try require(expected==3 && before.intersectingTrianglePairs==expected,"Body edges piercing a cloth face were not counted independently of vertex penetration")
        var moved=sheet.positions
        let passes=try repair(&moved,indices:sheet.indices,body:fixed,weights:[1,1,1])
        let after=try Contact.inspect(positions:moved,topology:top,body:fixed,thickness:0.005)
        try require(after.intersectingTrianglePairs==0 && oracleCount(cloth:.init(positions:moved,indices:sheet.indices),body:solid)==0,"Body-face pierce repair left a real surface crossing")
        try require(moved.allSatisfy(\.isFinite) && moved.allSatisfy{!insideConvex($0,mesh:solid)},"A repair put the cloth inside the closed body")
        log("face-interior body poke: \(expected) -> 0 in \(passes) passes (all initial cloth vertices outside)")

        var pinned=sheet.positions
        let pinnedStats=try Contact.project(positions:&pinned,inverseMass:[0,0,0],topology:top,body:fixed,thickness:0.005)
        try require(pinned==sheet.positions && pinnedStats.unresolvedPinnedContacts>0,"Pinned contacts must be disclosed without moving fixed cloth")
        let pinnedQuality=try Contact.inspect(positions:pinned,topology:top,body:fixed,thickness:0.005)
        try require(pinnedQuality.intersectingTrianglePairs==expected,"Pinned intersections were silently hidden")

        // Reverse the complete closed solid: contact remains outward and the
        // actual crossing count is independent of the input winding choice.
        let reversed=try body(reverse(solid))
        let reversedQuality=try Contact.inspect(positions:sheet.positions,topology:top,body:reversed,thickness:0.005)
        try require(reversedQuality.intersectingTrianglePairs==expected,"Reversed closed body changed intersection count")
        var reversedCloth=sheet.positions
        _=try repair(&reversedCloth,indices:sheet.indices,body:reversed,weights:[1,1,1])
        try require(oracleCount(cloth:.init(positions:reversedCloth,indices:sheet.indices),body:solid)==0,"Reversed winding repaired toward the body interior")

        // A fixed body's apex sits beneath a coarse cloth face. The movable
        // corners must share its barrier correction by barycentric inverse
        // mass, with the zero-mass corner staying exactly fixed.
        let small=tetra(apexZ:0,baseZ:-0.04,size:0.015),smallBody=try body(small)
        let s=0.12,z=0.001
        let weighted=Mesh(positions:[v(-s,-s/sqrt(3),z),v(s,-s/sqrt(3),z),v(0,2*s/sqrt(3),z)],indices:[0,1,2])
        var weightedPositions=weighted.positions
        let weightedStats=try Contact.project(positions:&weightedPositions,inverseMass:[0,1,3],topology:try topology(weighted),body:smallBody,thickness:0.005)
        let first=weightedPositions[1].z-z,second=weightedPositions[2].z-z
        try require(weightedStats.bodyVertexTriangleContacts>0 && weightedPositions[0]==weighted.positions[0],"Body vertex / cloth face barrier bypassed the fixed corner")
        try require(first>0 && second/first>2.5 && second/first<3.5,"Barycentric correction did not respect the 1:3 inverse mass ratio")
        try require((weightedPositions.reduce(.zero,+)/3).z>0.0048,"A coarse face remained closer to the apex than its barrier thickness")

        // A center fan and the coarse triangle agree on the physical barrier
        // even though contact lands on a newly introduced cloth vertex.
        var coarse=weighted.positions
        for _ in 0..<4 {_=try Contact.project(positions:&coarse,inverseMass:[1,1,1],topology:try topology(weighted),body:smallBody,thickness:0.005)}
        let fanIndices:[UInt32]=[0,1,3,1,2,3,2,0,3]
        var fan=weighted.positions+[v(0,0,z)]
        let fanTopology=try Cloth.Topology(vertexCount:4,triangleIndices:fanIndices)
        for _ in 0..<4 {_=try Contact.project(positions:&fan,inverseMass:[1.5,1.5,1.5,1],topology:fanTopology,body:smallBody,thickness:0.005)}
        let coarseHeight=(coarse.reduce(.zero,+)/3).z
        try require(coarseHeight>=0.0048 && fan[3].z>=0.0048 && abs(coarseHeight-fan[3].z)<0.0003,"Changing cloth resolution lost the body-face barrier")

        // Long edges approach in their interiors; no vertex of either top
        // triangle is near the opposite triangle. A vertex-only test misses it.
        let prism=Mesh(positions:[v(-0.12,0,0),v(0.12,-0.12,0),v(0.12,0,0),v(-0.12,0,-0.02),v(0.12,-0.12,-0.02),v(0.12,0,-0.02)],
                       indices:[0,1,2,3,5,4,0,3,4,0,4,1,1,4,5,1,5,2,2,5,3,2,3,0])
        let edgeSheet=Mesh(positions:[v(0,-0.12,0.002),v(0,0.12,0.002),v(-0.12,0.12,0.002)],indices:[0,1,2])
        var edgePositions=edgeSheet.positions
        let edgeBody=try body(prism)
        var edgeContacts=0
        for _ in 0..<8 {
            let stats=try Contact.project(positions:&edgePositions,inverseMass:[1,1,1],topology:try topology(edgeSheet),body:edgeBody,thickness:0.006)
            edgeContacts += stats.edgeEdgeContacts
        }
        let clearance=segmentDistance(edgePositions[0],edgePositions[1],prism.positions[0],prism.positions[2])
        log("edge-interior barrier: contacts=\(edgeContacts), actual_segment_clearance_m=\(clearance)")
        try require(edgeContacts>0 && clearance>0.0055,"Interior edge-edge proximity did not establish outward clearance")
        try require(oracleCount(cloth:.init(positions:edgePositions,indices:edgeSheet.indices),body:prism)==0,"Edge proximity projection introduced a proper surface crossing")

        // Two disconnected legs remain two solids. The gap is free space,
        // and each inner face points toward it even when one input component
        // uses the opposite winding.
        let left=box(center:v(-0.10,0,0),half:v(0.03,0.15,0.03))
        let right=reverse(box(center:v(0.10,0,0),half:v(0.03,0.15,0.03)))
        let legs=combine(left,right),legBody=try body(legs)
        let gap=Mesh(positions:[v(-0.015,-0.02,0),v(0.015,-0.02,0),v(0,0.02,0)],indices:[0,1,2])
        var gapPositions=gap.positions
        _=try Contact.project(positions:&gapPositions,inverseMass:[1,1,1],topology:try topology(gap),body:legBody,thickness:0.005)
        try require(gapPositions==gap.positions,"The empty gap between two legs was treated as a solid hull")
        let inner=Mesh(positions:[v(-0.071,-0.02,-0.01),v(-0.071,0.02,-0.01),v(-0.071,0,0.01),v(0.071,-0.02,-0.01),v(0.071,0.02,-0.01),v(0.071,0,0.01)],indices:[0,1,2,3,4,5])
        var innerPositions=inner.positions
        for _ in 0..<8 {_=try Contact.project(positions:&innerPositions,inverseMass:Array(repeating:1,count:6),topology:try topology(inner),body:legBody,thickness:0.005)}
        try require(innerPositions.prefix(3).allSatisfy{$0.x > -0.0655} && innerPositions.suffix(3).allSatisfy{$0.x < 0.0655},"Disconnected leg contact normals pushed the cloth into a leg")

        var invalid=false
        do {_=try Contact.BodyMesh(positions:[v(0,0,0),v(1,0,0),v(0,1,0)],triangleIndices:[0,1,2])} catch Contact.ContactError.invalid {invalid=true}
        try require(invalid,"An open body mesh was accepted as a closed solid")
        var broken=solid.indices;broken.swapAt(1,2);invalid=false
        do {_=try Contact.BodyMesh(positions:solid.positions,triangleIndices:broken)} catch Contact.ContactError.invalid {invalid=true}
        try require(invalid,"An inconsistently wound body face was accepted")
        var nanBody=solid.positions;nanBody[0].x = .nan;invalid=false
        do {_=try Contact.BodyMesh(positions:nanBody,triangleIndices:solid.indices)} catch Contact.ContactError.invalid {invalid=true}
        try require(invalid,"Non-finite body entered spatial indexing")
        var nanCloth=sheet.positions;nanCloth[0].y = .infinity;invalid=false
        do {_=try Contact.inspect(positions:nanCloth,topology:top,body:fixed,thickness:0.005)} catch Contact.ContactError.invalid {invalid=true}
        try require(invalid,"Non-finite cloth entered body spatial indexing")

        var cancelled=false,cancelPositions=sheet.positions
        do {_=try Contact.project(positions:&cancelPositions,inverseMass:[1,1,1],topology:top,body:fixed,thickness:0.005,isCancelled:{true})} catch is CancellationError {cancelled=true}
        try require(cancelled && cancelPositions==sheet.positions,"Pre-cancelled body contact moved cloth or returned success")
        cancelled=false
        do {_=try Contact.inspect(positions:sheet.positions,topology:top,body:fixed,thickness:0.005,isCancelled:{true})} catch is CancellationError {cancelled=true}
        try require(cancelled,"Cancelled body inspection returned a quality result")
        var budget=false
        do {_=try Contact.inspect(positions:sheet.positions,topology:top,body:fixed,thickness:0.005,maximumCandidatePairs:1)} catch Contact.ContactError.budgetExceeded {budget=true}
        try require(budget,"Candidate exhaustion silently omitted body/cloth pairs")
        log("synthetic checks: proper surface cuts, outward weighted/pinned/resolution contact, edge clearance, two-leg gap, winding, validation, cancellation and budgets PASS")
    }

    static func actualPokeRegression(root:URL,directory:URL)throws {
        let source=root.appendingPathComponent("Tests/NativePattern/Reports/2026-10-25-skirt2-3d/generated/skirt2-default-mesh.json")
        let beforeBytes=try Data(contentsOf:source)
        let old=try JSONDecoder().decode(GarmentCodeCircleDrape.Output.self,from:beforeBytes)
        let solid=Mesh(positions:old.mannequinPositions,indices:old.mannequinTriangleIndices)
        let sheet=Mesh(positions:old.positions,indices:old.triangleIndices)
        let fixed=try body(solid),top=try topology(sheet)
        let independentBefore=oracleCount(cloth:sheet,body:solid)
        let before=try Contact.inspect(positions:sheet.positions,topology:top,body:fixed,thickness:0.0025)
        log("legacy Skirt2 visible-body crossings: oracle=\(independentBefore), module=\(before.intersectingTrianglePairs); former SDF vertex penetration=\(old.diagnostics.maxBodyPenetrationMeters)m")
        try require(independentBefore>0,"The immutable old Skirt2 report no longer reproduces its actual face poke")
        try require(before.intersectingTrianglePairs==independentBefore,"Body quality count disagrees with the independent actual triangle intersection oracle")
        var positions=sheet.positions
        let passes=try repair(&positions,indices:sheet.indices,body:fixed,weights:Array(repeating:1,count:positions.count),thickness:0.0025,passes:128)
        let after=try Contact.inspect(positions:positions,topology:top,body:fixed,thickness:0.0025)
        let independentAfter=oracleCount(cloth:.init(positions:positions,indices:sheet.indices),body:solid)
        let sourceAfter=try Data(contentsOf:source)
        try require(beforeBytes==sourceAfter,"Body contact rewrote the frozen source/report")
        let summary:[String:Any]=["fixture":"2026-10-25-skirt2-3d/generated/skirt2-default-mesh.json","beforeOracleCrossings":independentBefore,"beforeReportedCrossings":before.intersectingTrianglePairs,"afterOracleCrossings":independentAfter,"afterReportedCrossings":after.intersectingTrianglePairs,"passes":passes,"sourceUnchanged":beforeBytes==sourceAfter,"scope":"Contact-only repair of the immutable old visible-body poke. Full source strain and settled drape require the separate solver integration regression."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("old-skirt2-body-surface-summary.json"),options:.atomic)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(positions).write(to:directory.appendingPathComponent("old-skirt2-contact-repaired-positions.json"),options:.atomic)
        log("legacy Skirt2 contact-only repair: \(independentBefore) -> \(independentAfter) actual crossings in \(passes) passes")
        try require(after.intersectingTrianglePairs==0 && independentAfter==0,"Old visible-body face pokes survived the actual surface contact pass")
        try require(positions.allSatisfy(\.isFinite) && after.degenerateClothTriangles==0,"Body contact collapsed a cloth face or produced non-finite geometry")
    }

    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_BODY_CONTACT_OUTPUT_DIR"] ?? "/private/tmp/TailorAssBodySurfaceContact")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try syntheticChecks()
        try actualPokeRegression(root:root,directory:directory)
        print("PASS: actual body/cloth triangle-surface contact, independent poke oracle, weighted/pinned and two-leg contact, cancellation and bounded failure")
    }
}
