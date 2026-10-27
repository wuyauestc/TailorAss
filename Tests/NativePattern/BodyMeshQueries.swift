import Foundation
import CryptoKit
import Darwin

nonisolated private final class QueryCancellation: @unchecked Sendable {
    // Test-only deterministic cancellation counter; all state is lock protected.
    private let lock=NSLock()
    private var calls=0
    private let threshold: Int
    init(_ threshold: Int) { self.threshold=threshold }
    func cancelled()->Bool {lock.lock();defer{lock.unlock()};calls += 1;return calls>=threshold}
}
@main struct BodyMeshQueriesRegression {
    typealias Q=GarmentCodeBodyMeshQueries
    typealias V=Q.V
    enum Failure: Error {case check(String)}
    nonisolated static func check(_ ok: Bool,_ message: String)throws {if !ok {throw Failure.check(message)}}
    nonisolated static func dot(_ a: V,_ b: V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    /// Independent Ericson region algorithm, with no BVH or interval helpers.
    nonisolated static func triangleClosest(_ p: V,_ a: V,_ b: V,_ c: V)->V {
        let ab=b-a,ac=c-a,ap=p-a,d1=dot(ab,ap),d2=dot(ac,ap)
        if d1<=0 && d2<=0 {return a}
        let bp=p-b,d3=dot(ab,bp),d4=dot(ac,bp)
        if d3>=0 && d4<=d3 {return b}
        let vc=d1*d4-d3*d2
        if vc<=0 && d1>=0 && d3<=0 {return a+ab*(d1/(d1-d3))}
        let cp=p-c,d5=dot(ab,cp),d6=dot(ac,cp)
        if d6>=0 && d5<=d6 {return c}
        let vb=d5*d2-d1*d6
        if vb<=0 && d2>=0 && d6<=0 {return a+ac*(d2/(d2-d6))}
        let va=d3*d6-d5*d4
        if va<=0 && d4-d3>=0 && d5-d6>=0 {return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)))}
        let inverse=1/(va+vb+vc)
        return a+ab*(vb*inverse)+ac*(vc*inverse)
    }
    /// Full-scan distance plus generalized solid-angle oracle. This is not
    /// ray parity, and no arbitrary normal offset is assumed inside/outside.
    nonisolated static func oracle(_ p: V,_ v: [V],_ ids: [UInt32])->(Double,Bool?) {
        var d=Double.infinity,angle=0.0,correction=0.0
        for offset in stride(from:0,to:ids.count,by:3) {
            let a=v[Int(ids[offset])],b=v[Int(ids[offset+1])],c=v[Int(ids[offset+2])]
            d=min(d,(triangleClosest(p,a,b,c)-p).length)
            let x=a-p,y=b-p,z=c-p
            let denominator=x.length*y.length*z.length+dot(x,y)*z.length+dot(y,z)*x.length+dot(z,x)*y.length
            let term=2*atan2(dot(x,y.cross(z)),denominator)
            let next=angle+term
            correction += abs(angle)>=abs(term) ? (angle-next)+term:(term-next)+angle
            angle=next
        }
        let winding=abs(angle+correction)/(4*Double.pi)
        return (d,winding<1e-7 ? false:(abs(winding-1)<1e-7 ? true:nil))
    }
    nonisolated static func compare(_ p: V,_ prepared: Q.Prepared,_ label: String)throws->Double {
        let a=prepared.query(p),b=oracle(p,prepared.positions,prepared.triangleIndices)
        try check(a.issue==nil && a.classification != .uncertain,label+": unexpected unknown \(String(describing:a.issue))")
        let error=abs(a.unsignedDistanceMeters!-b.0)
        try check(error<5e-10,label+": full-scan nearest mismatch \(error)")
        if b.0>1e-7 {
            try check(b.1 != nil,label+": independent solid-angle oracle unresolved")
            try check((a.classification == .inside)==b.1,label+": parity disagrees with full solid angle")
        } else {try check(a.classification == .onSurface,label+": source surface not recognized")}
        return error
    }
    nonisolated static func cube(_ center: V = .zero,_ h: Double = 0.5)->([V],[UInt32]) {
        let vertices=[V(x:-h,y:-h,z:-h),V(x:h,y:-h,z:-h),V(x:h,y:h,z:-h),V(x:-h,y:h,z:-h),
                      V(x:-h,y:-h,z:h),V(x:h,y:-h,z:h),V(x:h,y:h,z:h),V(x:-h,y:h,z:h)].map{$0+center}
        let ids:[UInt32]=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]
        return (vertices,ids)
    }
    nonisolated static func sphere()->([V],[UInt32]) {
        // A sphere-like triangulated visible surface. Analytic sphere bounds
        // are used only where valid; distances remain to this polyhedron.
        var vertices=[V(x:1,y:0,z:0),V(x:-1,y:0,z:0),V(x:0,y:1,z:0),V(x:0,y:-1,z:0),V(x:0,y:0,z:1),V(x:0,y:0,z:-1)]
        var faces:[[Int]]=[[0,2,4],[4,2,1],[1,2,5],[5,2,0],[4,3,0],[1,3,4],[5,3,1],[0,3,5]]
        for _ in 0..<3 {
            var mids:[UInt64:Int]=[:],next:[[Int]]=[]
            func midpoint(_ a: Int,_ b: Int)->Int {
                let key=(UInt64(min(a,b))<<32)|UInt64(max(a,b))
                if let i=mids[key] {return i}
                let v=vertices[a]+vertices[b],i=vertices.count;vertices.append(v/v.length);mids[key]=i;return i
            }
            for f in faces {
                let a=f[0],b=f[1],c=f[2],x=midpoint(a,b),y=midpoint(b,c),z=midpoint(c,a)
                next += [[a,x,z],[x,b,y],[z,y,c],[x,y,z]]
            }
            faces=next
        }
        return (vertices,faces.flatMap{$0.map(UInt32.init)})
    }
    nonisolated static func invalid(_ body: ()throws->Void)throws {
        do {try body();throw Failure.check("invalid geometry/configuration was accepted")}
        catch is Failure {throw Failure.check("invalid geometry/configuration was accepted")} catch {}
    }
    @MainActor static func main()throws {
        let d=URL(fileURLWithPath:CommandLine.arguments[1])
        let resources=d.appendingPathComponent("resources")
        var checks:[String]=[],maxError=0.0
        let box=cube(),q=try Q.Prepared(positions:box.0,triangleIndices:box.1)
        for (p,inside,expected) in [(V.zero,true,0.5),(V(x:0.1,y:0.2,z:0.3),true,0.2),(V(x:0.7,y:0.1,z:-0.2),false,0.2),
                                    (V(x:0.7,y:0.8,z:0.9),false,sqrt(0.29)),(V(x:-0.501,y:0,z:0),false,0.001)] {
            let r=q.query(p);try check(r.classification == (inside ? .inside:.outside),"analytic cube sign")
            try check(abs(r.unsignedDistanceMeters!-expected)<1e-12,"analytic cube distance")
            maxError=max(maxError,try compare(p,q,"cube"))
        }
        for p in [V(x:0.5,y:0.2,z:-0.1),V(x:0.5,y:0.5,z:0),V(x:0.5,y:0.5,z:0.5)] {
            let r=q.query(p);try check(r.classification == .onSurface && r.signedDistanceMeters==0,"face/edge/vertex surface")
        }
        checks.append("analytic-cube-face-edge-vertex-inside-outside")
        let origin=q.query(.zero)
        try check(origin.statistics.rays.contains{!$0.completed} && origin.statistics.acceptedDirections==3,"edge/vertex rays must retry")
        var noRetry=Q.Options();noRetry.maximumRayDirections=3
        let feature=q.query(.zero,options:noRetry)
        try check(feature.classification == .uncertain && feature.issue == .insufficientUnambiguousDirections && feature.signedDistanceMeters==nil && feature.unsignedDistanceMeters != nil,"ambiguous directions cannot vote")
        checks.append("source-feature-retry-and-insufficient-directions-fail-closed")
        let round=sphere(),qs=try Q.Prepared(positions:round.0,triangleIndices:round.1)
        var centerDistance=Double.infinity
        for i in stride(from:0,to:round.1.count,by:3) {
            let a=round.0[Int(round.1[i])],b=round.0[Int(round.1[i+1])],c=round.0[Int(round.1[i+2])],n=(b-a).cross(c-a)
            centerDistance=min(centerDistance,abs(dot(a,n))/n.length)
        }
        try check(qs.query(.zero).classification == .inside && abs(qs.query(.zero).unsignedDistanceMeters!-centerDistance)<1e-12,"sphere polyhedron center/apothem")
        for p in [V(x:1.1,y:0,z:0),V(x:0,y:-1.1,z:0),V(x:0.2,y:0.13,z:0.17)] {maxError=max(maxError,try compare(p,qs,"sphere"))}
        try check(abs(qs.query(.init(x:1.1,y:0,z:0)).unsignedDistanceMeters!-0.1)<1e-12,"sphere vertex radial exact distance")
        checks.append("sphere-tessellation-analytic-inradius-and-circumradius")
        func rotate(_ p: V)->V {
            let c=cos(0.713),s=sin(0.713),u=V(x:1,y:2,z:3)/sqrt(14)
            return p*c+u.cross(p)*s+u*(dot(u,p)*(1-c))
        }
        let shift=V(x:2.7,y:-1.3,z:0.8)
        let rigid=try Q.Prepared(positions:box.0.map{rotate($0)+shift},triangleIndices:box.1)
        for p in [V.zero,V(x:0.12,y:0.17,z:0.23),V(x:0.8,y:0.7,z:0.1)] {
            let a=q.query(p),b=rigid.query(rotate(p)+shift)
            try check(a.classification==b.classification && abs(a.unsignedDistanceMeters!-b.unsignedDistanceMeters!)<2e-14,"rigid covariance")
        }
        try check(q.geometrySHA256 != rigid.geometrySHA256,"SHA must bind actual visible coordinates")
        let reversed=try Q.Prepared(positions:box.0,triangleIndices:stride(from:0,to:box.1.count,by:3).flatMap{[box.1[$0],box.1[$0+2],box.1[$0+1]]})
        try check(reversed.query(.zero).classification == .inside && reversed.geometrySHA256 != q.geometrySHA256,"reversed component parity and binding")
        checks.append("rigid-covariance-reversed-winding-and-exact-geometry-binding")
        let second=cube(.init(x:2,y:0,z:0)),multi=try Q.Prepared(positions:box.0+second.0,triangleIndices:box.1+second.1.map{$0+8})
        for p in [V.zero,V(x:2,y:0,z:0),V(x:1,y:0,z:0)] {maxError=max(maxError,try compare(p,multi,"disjoint-closed-components"))}
        checks.append("disjoint-closed-components")
        let skinnyVertices=[V.zero,V(x:1,y:0,z:0),V(x:0,y:1,z:0),V(x:0,y:0,z:1e-8)]
        let tetra:[UInt32]=[0,2,1,0,1,3,1,2,3,2,0,3]
        let skinny=try Q.Prepared(positions:skinnyVertices,triangleIndices:tetra)
        var precise=Q.Options();precise.surfaceToleranceMeters=1e-12
        for (p,inside) in [(V(x:0.1,y:0.1,z:1e-9),true),(V(x:0.1,y:0.1,z:-1e-9),false)] {
            let r=skinny.query(p,options:precise)
            try check(r.classification == (inside ? .inside:.outside) && abs(r.unsignedDistanceMeters!-1e-9)<1e-15,"skinny analytic tetrahedron")
        }
        checks.append("skinny-triangle-ray-arithmetic-and-small-distance")
        try invalid{_ = try Q.Prepared(positions:box.0,triangleIndices:Array(box.1.dropLast(3)))}
        var bad=box.1;bad[0]=1000;try invalid{_ = try Q.Prepared(positions:box.0,triangleIndices:bad)}
        var nonfinite=box.0;nonfinite[0].x = .nan;try invalid{_ = try Q.Prepared(positions:nonfinite,triangleIndices:box.1)}
        try invalid{_ = try Q.Prepared(positions:box.0+[V(x:8,y:8,z:8)],triangleIndices:box.1)}
        let tiny=box.0.map{$0*1e-9};try invalid{_ = try Q.Prepared(positions:tiny,triangleIndices:box.1)}
        let touching=cube(.init(x:1,y:1,z:1))
        let touchingIndices=box.1+touching.1.map{$0==0 ? 6:$0+7}
        try invalid{_ = try Q.Prepared(positions:box.0+Array(touching.0.dropFirst()),triangleIndices:touchingIndices)}
        var limit=Q.Limits();limit.maximumBVHNodes=1
        try invalid{_ = try Q.Prepared(positions:box.0,triangleIndices:box.1,limits:limit)}
        try invalid{_ = try Q.Prepared(positions:box.0,triangleIndices:box.1,isCancelled:{true})}
        checks.append("open-invalid-unreferenced-degenerate-prepare-budget-and-cancel-rejection")
        var o=Q.Options();o.maximumClosestTriangleTests=0
        let incomplete=q.query(.zero,options:o);try check(incomplete.issue == .nearestBudgetExceeded && incomplete.unsignedDistanceMeters==nil && incomplete.signedDistanceMeters==nil,"partial nearest cannot return a distance")
        o=Q.Options();o.maximumRayNodeVisits=0
        let incompleteParity=q.query(.zero,options:o);try check(incompleteParity.issue == .parityBudgetExceeded && incompleteParity.unsignedDistanceMeters==0.5 && incompleteParity.signedDistanceMeters==nil,"partial parity cannot return a sign")
        let cancellation=QueryCancellation(4)
        let cancelled=q.query(.zero,isCancelled:{cancellation.cancelled()})
        try check(cancelled.classification == .uncertain && cancelled.issue == .cancelled && cancelled.signedDistanceMeters==nil,"query cancellation not hidden")
        let invalidPoint=q.query(.init(x:.nan,y:0,z:0));try check(invalidPoint.issue == .invalidQuery && invalidPoint.unsignedDistanceMeters==nil,"invalid point")
        checks.append("nearest-and-parity-budgets-cancellation-and-invalid-query")
        let rounding=fegetround()
        try check(fesetround(FE_UPWARD)==0,"test rounding control unavailable")
        let nonnearest=q.query(.zero)
        let roundingRejected=nonnearest.issue == .unsupportedRounding && nonnearest.unsignedDistanceMeters==nil
        var prepareRoundingRejected=false
        do {_ = try Q.Prepared(positions:box.0,triangleIndices:box.1)} catch Q.PreparationError.unsupportedRounding {prepareRoundingRejected=true}
        catch {}
        try check(fesetround(rounding)==0,"restore nearest rounding")
        try check(roundingRejected && prepareRoundingRejected,"non-nearest environment silently accepted")
        checks.append("rounding-environment-rejected-without-mutation")
        let cat=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let femaleData=try JSONSerialization.jsonObject(with:Data(contentsOf:d.appendingPathComponent("female-standing-mesher-source.json"))) as! [String:Any]
        let female=(femaleData["parameters"] as! [String:Any])["body"] as! [String:Double]
        let sourceFixture=try JSONSerialization.jsonObject(with:Data(contentsOf:d.appendingPathComponent("body-mesh-queries-visible.json"))) as! [String:Any]
        let fixtureProfiles=sourceFixture["profiles"] as! [String:[String:Any]]
        var cases:[(String,[String:Double])]=[("default",cat.body),("female",female)]
        for key in cat.body.keys.sorted() {for sign in [-1.0,1.0] {
            var b=cat.body;b[key]! += sign*(key.contains("angle") || key.contains("incl") ? 5:cat.body[key]!*0.05)
            cases.append((key+(sign>0 ? "-plus":"-minus"),b))
        }}
        var profileReports:[[String:Any]]=[],surfaceCount=0,scanCount=0,totalClosest=0,totalRays=0
        let start=Date()
        for (name,values) in cases {
            let standard=try GarmentCodeStandardBody.load(body:.init(values:values),resourceDirectory:resources)
            let mesh=try Q.BodyMesh(positions:standard.positions,triangleIndices:standard.triangleIndices)
            let prepared=try Q.Prepared(body:mesh)
            var vertexMax=0.0,sdfMax=0.0,sdfBad=0,closestTests=0,rayTests=0
            // All original/female visible vertices are a direct, exact source
            // zero-distance oracle, including every former SDF error witness.
            if name=="default" || name=="female" {
                for p in standard.positions {
                    let r=prepared.query(p)
                    try check(r.issue==nil && r.classification == .onSurface && r.unsignedDistanceMeters!<1e-12,"actual visible vertex not on source surface")
                    vertexMax=max(vertexMax,r.unsignedDistanceMeters!)
                    closestTests += r.statistics.closestTriangleTests;surfaceCount += 1
                    if let s=standard.signedDistance(p) {sdfMax=max(sdfMax,abs(s));if abs(s)>0.003 {sdfBad += 1}}
                }
                for witness in fixtureProfiles[name]!["witnesses"] as! [[String:Any]] {
                    let id=witness["visibleVertex"] as! Int,point=witness["positionMeters"] as! [Double]
                    let p=V(x:point[0],y:point[1],z:point[2]),sdf=witness["swiftSignedDistanceMeters"] as! Double
                    // JSONSerialization/NSNumber may round the last binary64
                    // bit on decode. The resource SHA and source ID bind the
                    // exact geometry; this only verifies the written coordinate.
                    try check((standard.positions[id]-p).length<1e-14,"source witness is not the same visible vertex")
                    try check(abs(standard.signedDistance(p)!-sdf)<1e-12,"old grid diagnostic fixture drift")
                    let exact=prepared.query(standard.positions[id])
                    try check(exact.classification == .onSurface && exact.unsignedDistanceMeters==0,"persistent old-grid witness lost exact source distance")
                }
            }
            let fixed=[V(x:0,y:-0.1,z:0),V(x:0,y:-0.6,z:-0.02),V(x:0.9,y:0,z:0),V(x:0.03,y:0.2,z:0.02)]
            var points=fixed
            var seed:UInt64=0x7451ABC183
            func random()->Double {seed=seed &* 6364136223846793005 &+ 1442695040888963407;return Double(seed>>11)/9007199254740992}
            for _ in 0..<2 {points.append(.init(x:(random()-0.5)*1.4,y:random()*1.8-1.1,z:(random()-0.5)*0.8))}
            // Rounded normal offsets are NOT an inside/outside oracle.
            // Every such candidate is checked by independent full solid angle.
            for id in [5813,6815] {
                let f=standard.triangleIndices.indices.first{Int(standard.triangleIndices[$0])==id}!/3*3
                let a=standard.positions[Int(standard.triangleIndices[f])],b=standard.positions[Int(standard.triangleIndices[f+1])],c=standard.positions[Int(standard.triangleIndices[f+2])]
                let center=(a+b+c)/3,n=(b-a).cross(c-a),unit=n/n.length
                points += [center+unit*0.001,center-unit*0.001]
            }
            for p in points {
                maxError=max(maxError,try compare(p,prepared,name));scanCount += 1
                let r=prepared.query(p);closestTests += r.statistics.closestTriangleTests;rayTests += r.statistics.rayTriangleTests
            }
            profileReports.append(["name":name,"geometrySHA256":prepared.geometrySHA256,"vertices":standard.positions.count,
                                   "triangles":standard.triangleIndices.count/3,"surfaceVertexMaximumDistanceMeters":vertexMax,
                                   "oldGridMaximumSurfaceErrorMeters":sdfMax,"oldGridSurfaceErrorBeyond3mm":sdfBad,
                                   "closestTriangleTests":closestTests,"rayTriangleTests":rayTests])
            totalClosest += closestTests;totalRays += rayTests
        }
        checks.append("54-real-native-body-profiles-full-scan-distance-and-solid-angle-oracle")
        checks.append("all-26760-default-female-surface-vertices-including-all-old-grid-errors")
        checks.append("persistent-old-grid-error-witnesses-bound-to-original-resource-sha")
        // Verify the canonical binding independently from the old clearance
        // module (the same layout is also checked by the Python runner).
        var bytes=Data("rigid-clearance-visible-body-v1\0".utf8)
        func append<T:FixedWidthInteger>(_ x:T){var y=x.littleEndian;withUnsafeBytes(of:&y){bytes.append(contentsOf:$0)}}
        append(UInt64(box.0.count));append(UInt64(box.1.count))
        for p in box.0 {append(p.x.bitPattern);append(p.y.bitPattern);append(p.z.bitPattern)}
        for i in box.1 {append(i)}
        try check(q.geometrySHA256==SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),"canonical geometry bytes differ")
        let summary:[String:Any]=["passed":true,"checks":checks,"analyticCubeGeometrySHA256":q.geometrySHA256,"nativeProfileCount":cases.count,"allSurfaceVertices":surfaceCount,
          "fullScanOraclePoints":scanCount,"maximumIndependentDistanceErrorMeters":maxError,"nativeElapsedSeconds":Date().timeIntervalSince(start),
          "closestTriangleTests":totalClosest,"rayTriangleTests":totalRays,"profiles":profileReports]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:d.appendingPathComponent("body-mesh-queries-summary.json"))
        print("PASS: \(checks.count) groups, \(cases.count) profiles, \(surfaceCount) actual surface vertices, \(scanCount) independent full scans; max error \(maxError)")
    }
}

