import Foundation
import CryptoKit

nonisolated private final class EnvelopeCancellation:@unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    private let threshold:Int
    init(_ threshold:Int){self.threshold=threshold}
    func check()->Bool {lock.lock();defer{lock.unlock()};count += 1;return count>=threshold}
}

@main @MainActor
struct BodyEnvelopeRegression {
    typealias E=GarmentCodeBodyEnvelope
    typealias V=E.Vector3
    enum Failure:Error {case check(String)}
    static func require(_ value:@autoclosure()throws->Bool,_ message:String)throws {if try !value(){throw Failure.check(message)}}
    static func near(_ a:Double,_ b:Double,_ message:String,tolerance:Double=1e-8)throws {try require(abs(a-b)<=tolerance,"\(message): \(a) vs \(b)")}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func coord(_ p:V,_ axis:Int)->Double {axis==0 ? p.x : (axis==1 ? p.y : p.z)}
    static func encode<T:Encodable>(_ v:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(v)}
    static func sha(_ d:Data)->String {SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
    static let boxVertices:[V] = [
        .init(x:-1,y:-1,z:-1),.init(x:1,y:-1,z:-1),.init(x:1,y:1,z:-1),.init(x:-1,y:1,z:-1),
        .init(x:-1,y:-1,z:1),.init(x:1,y:-1,z:1),.init(x:1,y:1,z:1),.init(x:-1,y:1,z:1)]
    static let boxTriangles:[UInt32] = [0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]

    nonisolated static func actorFreeAPI()throws {
        let surface=try E.PreparedSurface(positions:[V(x:0,y:0,z:0),V(x:1,y:0,z:1),V(x:0,y:1,z:1)],triangleIndices:[0,1,2])
        _=try surface.query(axis:.z,first:0.2,second:0.3)
        _=try surface.frontBackAt(x:0.2,y:0.3)
        _=try surface.ray(from:V(x:0.2,y:0.3,z:2),axis:.z,direction:.negative)
        _=try surface.candidateTriangles(axis:.z,first:0.1...0.2,second:0.1...0.2)
        _=try surface.triangleBounds(at:0)
    }

    /// Independent unindexed plane intersection. It does not call the indexed
    /// implementation, use its normals/barycentrics or consult the SDF.
    static func brute(_ positions:[V],_ indices:[UInt32],axis:Int,first:Double,second:Double)->[Double] {
        let u=(axis+1)%3,v=(axis+2)%3
        var hits:[Double]=[]
        for i in stride(from:0,to:indices.count,by:3) {
            let a=positions[Int(indices[i])],b=positions[Int(indices[i+1])],c=positions[Int(indices[i+2])]
            let ab=b-a,ac=c-a,normal=ab.cross(ac),den=coord(normal,axis)
            if abs(den)<1e-14{continue}
            let axisPosition=coord(a,axis)-(coord(normal,u)*(first-coord(a,u))+coord(normal,v)*(second-coord(a,v)))/den
            var p=V.zero
            switch axis {case 0:p = .init(x:axisPosition,y:first,z:second);case 1:p = .init(x:second,y:axisPosition,z:first);default:p = .init(x:first,y:second,z:axisPosition)}
            let ap=p-a,d00=dot(ab,ab),d01=dot(ab,ac),d11=dot(ac,ac),d20=dot(ap,ab),d21=dot(ap,ac),det=d00*d11-d01*d01
            if det<=1e-24{continue}
            let beta=(d11*d20-d01*d21)/det,gamma=(d00*d21-d01*d20)/det
            if beta>=(-1e-10),gamma>=(-1e-10),beta+gamma<=1+1e-10 {hits.append(axisPosition)}
        }
        var unique:[Double]=[]
        for hit in hits.sorted() where unique.last.map({abs($0-hit)>4e-8}) ?? true {unique.append(hit)}
        return unique
    }
    static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}

    static func actualHit(_ hit:E.Hit,surface:E.PreparedSurface,axis:E.Axis,first:Double,second:Double)throws {
        let t=hit.triangleID*3,ids=(0..<3).map{Int(surface.triangleIndices[t+$0])}
        let a=surface.positions[ids[0]],b=surface.positions[ids[1]],c=surface.positions[ids[2]],p=hit.point
        let n=(b-a).cross(c-a),normal=n/n.length
        try near(dot(p-a,normal),0,"Hit left its actual triangle plane")
        let ab=b-a,ac=c-a,ap=p-a,d00=dot(ab,ab),d01=dot(ab,ac),d11=dot(ac,ac),det=d00*d11-d01*d01
        let beta=(d11*dot(ap,ab)-d01*dot(ap,ac))/det,gamma=(d00*dot(ap,ac)-d01*dot(ap,ab))/det
        try require(beta>=(-1e-7) && gamma>=(-1e-7) && beta+gamma<=1+1e-7,"Reported hit lies outside its original actual triangle")
        try near(coord(p,(axis.rawValue+1)%3),first,"Hit changed the first fixed coordinate")
        try near(coord(p,(axis.rawValue+2)%3),second,"Hit changed the second fixed coordinate")
        try near(hit.normal.length,1,"Hit normal is not normalized")
        try require(hit.incidentTriangleIDs.contains(hit.triangleID),"Representative triangle was lost from feature provenance")
    }

    static func analytic()throws->[String:Any] {
        let box=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles)
        try require(box.positions==boxVertices && box.triangleIndices==boxTriangles && box.isClosed && box.components.count==1,"Box source geometry or closed topology changed")
        try near(box.components[0].signedVolumeCubicMeters!,8,"Outward box volume")
        for axis in [E.Axis.x,.y,.z] {
            let line=try box.query(axis:axis,first:0.13,second:0.21)
            try require(line.isUnambiguous && line.hits.count==2,"Analytic box lost an entry/exit")
            try near(coord(line.hits[0].point,axis.rawValue),-1,"Analytic back intersection")
            try near(coord(line.hits[1].point,axis.rawValue),1,"Analytic front intersection")
            try near(coord(line.hits[0].normal,axis.rawValue),-1,"Back outward normal")
            try near(coord(line.hits[1].normal,axis.rawValue),1,"Front outward normal")
            for hit in line.hits {try actualHit(hit,surface:box,axis:axis,first:0.13,second:0.21);try require(hit.normalIsOutward,"Closed surface lacks verified outward normals")}
        }
        let positive=try box.ray(from:.init(x:0.13,y:0.21,z:-2),axis:.z,direction:.positive)
        let negative=try box.ray(from:.init(x:0.13,y:0.21,z:2),axis:.z,direction:.negative)
        try require(positive.hits.count==2 && negative.hits.count==2,"Positive/negative rays lost crossings")
        try near(positive.hits[0].point.z,-1,"Positive ray order")
        try near(negative.hits[0].point.z,1,"Negative ray order")
        try require(try box.ray(from:.init(x:0.13,y:0.21,z:-2),axis:.z,direction:.negative).hits.isEmpty,"Ray behind body returned forward intersections")
        try require(try box.ray(from:.init(x:0.13,y:0.21,z:-2),axis:.z,direction:.positive,maximumDistanceMeters:0.5).hits.isEmpty,"Ray maximum distance was ignored")
        try require(try box.query(axis:.z,first:1e200,second:0).hits.isEmpty,"Finite far miss overflowed indexing")
        let envelope=try box.frontBackAt(x:0.13,y:0.21)
        try require(envelope.envelope != nil,"Closed unambiguous box lacks an envelope")
        try near(envelope.envelope!.front.point.z,1,"Front wrapper")
        try near(envelope.envelope!.back.point.z,-1,"Back wrapper")
        let grazing=try box.frontBackAt(x:1,y:0)
        try require(!grazing.line.coplanarTriangleIDs.isEmpty && !grazing.line.isUnambiguous && grazing.envelope==nil,"Coplanar box-edge line fabricated a unique usable envelope")

        var reversed=boxTriangles
        for i in stride(from:0,to:reversed.count,by:3){reversed.swapAt(i+1,i+2)}
        let inward=try E.PreparedSurface(positions:boxVertices,triangleIndices:reversed)
        try require(inward.triangleIndices==reversed,"Inward source triangle order was silently rewritten")
        try near(inward.components[0].signedVolumeCubicMeters!,-8,"Inward source volume must be retained")
        try near(inward.query(axis:.z,first:0.13,second:0.21).hits.last!.normal.z,1,"Closed inward source must report geometrically outward query normals")

        let tilted=try E.PreparedSurface(positions:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:1),.init(x:0,y:1,z:1)],triangleIndices:[0,1,2])
        for (axis,first,second) in [(E.Axis.z,0.2,0.3),(.x,0.3,0.5),(.y,0.5,0.2)] {
            let line=try tilted.query(axis:axis,first:first,second:second)
            try require(line.hits.count==1 && line.isUnambiguous && !line.hits[0].normalIsOutward,"Tilted open triangle needs source-winding normals and one true intersection")
            let p=line.hits[0].point
            try near(p.x,0.2,"Tilted x");try near(p.y,0.3,"Tilted y");try near(p.z,0.5,"Tilted z")
            try actualHit(line.hits[0],surface:tilted,axis:axis,first:first,second:second)
        }
        let open=try tilted.frontBackAt(x:0.2,y:0.3)
        try require(open.envelope==nil,"Open triangle was treated as a closed body envelope")

        let square=try E.PreparedSurface(positions:[.init(x:-1,y:-1,z:0),.init(x:1,y:-1,z:0),.init(x:1,y:1,z:0),.init(x:-1,y:1,z:0)],triangleIndices:[0,1,2,0,2,3])
        let shared=try square.query(axis:.z,first:0,second:0)
        try require(shared.hits.count==1 && shared.hits[0].incidentTriangleIDs==[0,1] && shared.hits[0].kind == .crossing,"Shared source edge must deduplicate to one same-sided crossing")
        let vertex=try square.query(axis:.z,first:-1,second:-1)
        try require(vertex.hits.count==1 && vertex.hits[0].incidentTriangleIDs==[0,1],"Shared source vertex was counted twice")

        let fold=try E.PreparedSurface(positions:[.init(x:0,y:-1,z:0),.init(x:0,y:1,z:0),.init(x:1,y:0,z:1),.init(x:1,y:0,z:-1)],triangleIndices:[0,2,1,0,1,3])
        let touch=try fold.query(axis:.z,first:0,second:0)
        try require(touch.hits.count==1 && touch.hits[0].kind == .ambiguous && touch.hits[0].ambiguity.contains(.mixedNormalsAtFeature),"Opposing normals at a grazing feature became a clean crossing")
        let coincident=try E.PreparedSurface(positions:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0)],triangleIndices:[0,1,2,3,4,5])
        let duplicate=try coincident.query(axis:.z,first:0.2,second:0.2)
        try require(duplicate.hits.count==1 && duplicate.hits[0].kind == .ambiguous && duplicate.hits[0].ambiguity.contains(.coincidentIndependentSurfaces),"Independent coincident surfaces were falsely deduplicated as a source feature")
        let parallel=try E.PreparedSurface(positions:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:0,z:1)],triangleIndices:[0,1,2])
        let continuous=try parallel.query(axis:.z,first:0.2,second:0)
        try require(continuous.hits.isEmpty && continuous.coplanarTriangleIDs==[0] && !continuous.isUnambiguous,"Continuous line/triangle contact acquired a fake single point")
        var tolerant=E.Limits();tolerant.angularTolerance=1e-4
        let nearParallel=try E.PreparedSurface(positions:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1e-5,z:1)],triangleIndices:[0,1,2],limits:tolerant)
        let tangent=try nearParallel.query(axis:.z,first:0.2,second:2e-6)
        try require(tangent.hits.count==1 && tangent.hits[0].kind == .tangent && !tangent.isUnambiguous,"Configured near-parallel tangent was reported as a usable crossing")
        let local=try box.candidateTriangles(axis:.z,first:0.1...0.2,second:0.1...0.2)
        try require(local==local.sorted() && Set(local).count==local.count && !local.isEmpty,"Local box candidates are not unique and deterministic")
        for id in local {let b=try box.triangleBounds(at:id);try require(b.minimum.x<=b.maximum.x && b.minimum.y<=b.maximum.y,"Original triangle bbox is invalid")}
        log("PASS analytic box/three axes/both ray directions, tilted triangles, exact shared-feature dedup, grazing/coplanar/independent-coincident ambiguity, configured tangency")
        return ["passed":true,"boxBinReferences":box.binReferenceCount,"boxCells":box.cellCount,"sharedFeatureIncidentTriangles":shared.hits[0].incidentTriangleIDs,"ambiguityCases":4]
    }

    static func failureContracts()throws->[String:Any] {
        var cases=0
        func rejected(_ action:()throws->Void)throws {
            var failed=false;do{try action()}catch E.SurfaceError.invalid{failed=true}catch E.SurfaceError.budgetExceeded{failed=true}
            try require(failed,"Invalid/over-budget surface query was silently accepted");cases += 1
        }
        try rejected{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:[0,1,80])}
        try rejected{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:[0,1,1])}
        try rejected{_=try E.PreparedSurface(positions:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:2,y:0,z:0)],triangleIndices:[0,1,2])}
        var nonfinite=boxVertices;nonfinite[0].x = .nan
        try rejected{_=try E.PreparedSurface(positions:nonfinite,triangleIndices:boxTriangles)}
        try rejected{_=try E.PreparedSurface(positions:boxVertices+[.zero],triangleIndices:boxTriangles)}
        var flipped=boxTriangles;flipped.swapAt(1,2)
        try rejected{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:flipped)}
        try rejected{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles+[0,2,1])}
        let bowtie:[V] = [.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:-1,y:0,z:0),.init(x:0,y:-1,z:0)]
        try rejected{_=try E.PreparedSurface(positions:bowtie,triangleIndices:[0,1,2,0,3,4])}
        var resource=E.Limits();resource.maximumVertices=3
        try rejected{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,limits:resource)}
        resource=E.Limits();resource.maximumBinReferences=1
        try rejected{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,limits:resource)}
        resource=E.Limits();resource.maximumCells=1
        try rejected{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,limits:resource)}
        resource=E.Limits();resource.maximumHits=1
        let fewHits=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,limits:resource)
        try rejected{_=try fewHits.query(axis:.z,first:0.13,second:0.21)}
        resource=E.Limits();resource.maximumQueryCells=1
        let fewCells=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,limits:resource)
        try rejected{_=try fewCells.candidateTriangles(axis:.z,first:-0.1...0.1,second:-0.1...0.1)}
        resource=E.Limits();resource.maximumCandidateTriangles=1
        let fewFaces=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,limits:resource)
        try rejected{_=try fewFaces.query(axis:.z,first:0.13,second:0.21)}
        let box=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles)
        try rejected{_=try box.query(axis:.z,first:.nan,second:0)}
        try rejected{_=try box.ray(from:.zero,axis:.z,direction:.positive,maximumDistanceMeters:-1)}
        try rejected{_=try box.triangleBounds(at:-1)}
        var cancelled=false
        do{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Cancelled source construction returned an index")
        let buildCounter=EnvelopeCancellation(4);cancelled=false
        do{_=try E.PreparedSurface(positions:boxVertices,triangleIndices:boxTriangles,isCancelled:{buildCounter.check()})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Mid-construction cancellation returned a partial index")
        cancelled=false
        do{_=try box.query(axis:.z,first:0.1,second:0.2,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Cancelled query returned a line result")
        let queryCounter=EnvelopeCancellation(3);cancelled=false
        do{_=try box.query(axis:.z,first:0.1,second:0.2,isCancelled:{queryCounter.check()})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Mid-query cancellation returned a partial result")
        log("PASS \(cases) invalid/budget contracts and four cancellation paths")
        return ["passed":true,"invalidOrBudgetCases":cases,"cancellationCases":4]
    }

    static func actualBody(root:URL)throws->[String:Any] {
        let resources=root.appendingPathComponent("TrailorAss/Resources")
        let catalog=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let standard=try GarmentCodeStandardBody.load(body:.init(values:catalog.body),resourceDirectory:resources)
        let sourceJSON=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBody.json")),sourceField=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodySDF.bin"))
        let surface=try E.PreparedSurface(positions:standard.positions,triangleIndices:standard.triangleIndices)
        try require(surface.positions==standard.positions && surface.triangleIndices==standard.triangleIndices && surface.isClosed,"Visible body geometry was replaced, changed or opened")
        var rows:[[String:Any]]=[],usable=0,totalCandidates=0,totalHits=0
        for y in [0.0,-0.0469674,0.18,0.28,0.35,0.42] {
            for x in [0.0,0.037,0.1] {
                let line=try surface.query(axis:.z,first:x,second:y)
                let expected=brute(standard.positions,standard.triangleIndices,axis:2,first:x,second:y)
                for hit in line.hits{try actualHit(hit,surface:surface,axis:.z,first:x,second:y)}
                if line.isUnambiguous {
                    try require(line.hits.count==expected.count,"Indexed body ray lost or gained a source triangle intersection")
                    for (a,b) in zip(line.hits,expected){try near(a.point.z,b,"Indexed body hit disagrees with independent full-triangle scan",tolerance:1e-7)}
                }
                let envelope=try surface.frontBackAt(x:x,y:y)
                if envelope.envelope != nil{usable += 1}
                if x==0.037 && (y==0 || y == -0.0469674){try require(envelope.envelope != nil,"Actual torso waist/band-bottom must provide a resolved front/back envelope")}
                totalCandidates += line.candidateTriangleCount;totalHits += line.hits.count
                rows.append(["x":x,"y":y,"hits":line.hits.count,"candidateTriangles":line.candidateTriangleCount,
                    "unambiguous":line.isUnambiguous,"coplanarTriangleCount":line.coplanarTriangleIDs.count,
                    "frontBackAvailable":envelope.envelope != nil])
            }
        }
        for (axis,first,second) in [(E.Axis.x,0.0,0.0),(.y,0.0,0.18),(.y,0.02,0.15)] {
            let line=try surface.query(axis:axis,first:first,second:second)
            for hit in line.hits{try actualHit(hit,surface:surface,axis:axis,first:first,second:second)}
            let expected=brute(standard.positions,standard.triangleIndices,axis:axis.rawValue,first:first,second:second)
            if line.isUnambiguous {try require(line.hits.count==expected.count,"Actual body's transverse/vertical axis lost intersections");for (a,b) in zip(line.hits,expected){try near(coord(a.point,axis.rawValue),b,"Actual axis independent oracle",tolerance:1e-7)}}
            rows.append(["axis":axis.rawValue,"first":first,"second":second,"hits":line.hits.count,"unambiguous":line.isUnambiguous])
        }
        var randomState:UInt64=0xB0D1E5A7,randomQueries=0,randomHits=0,randomAmbiguous=0,randomCandidates=0
        func next()->Double {randomState=randomState &* 2862933555777941757 &+ 3037000493;return Double(randomState>>11)/9007199254740992}
        for axis in [E.Axis.x,.y,.z] {
            let u=(axis.rawValue+1)%3,v=(axis.rawValue+2)%3
            for _ in 0..<64 {
                let first=coord(surface.bounds.minimum,u)-0.03+next()*(coord(surface.bounds.maximum,u)-coord(surface.bounds.minimum,u)+0.06)
                let second=coord(surface.bounds.minimum,v)-0.03+next()*(coord(surface.bounds.maximum,v)-coord(surface.bounds.minimum,v)+0.06)
                let line=try surface.query(axis:axis,first:first,second:second)
                for hit in line.hits {try actualHit(hit,surface:surface,axis:axis,first:first,second:second)}
                if line.isUnambiguous {
                    let expected=brute(standard.positions,standard.triangleIndices,axis:axis.rawValue,first:first,second:second)
                    try require(line.hits.count==expected.count && line.hits.count%2==0,"Seeded whole-body indexed ray lost/gained a source crossing")
                    for (a,b) in zip(line.hits,expected) {try near(coord(a.point,axis.rawValue),b,"Seeded whole-body independent oracle",tolerance:1e-7)}
                }else{randomAmbiguous += 1}
                randomQueries += 1;randomHits += line.hits.count;randomCandidates += line.candidateTriangleCount
            }
        }
        try require(randomHits>=40 && randomAmbiguous<=4,"Seeded whole-body coverage became mostly misses or ambiguity")
        try require(randomCandidates<randomQueries*standard.triangleIndices.count/15,"Seeded ray queries scanned too much of the full body")
        try require(usable>=6 && totalHits>=24,"Actual-body query coverage is insufficient")
        try require(totalCandidates<18*standard.triangleIndices.count/15,"Per-point index effectively scanned the full body")
        let upward=try surface.ray(from:.init(x:0.18,y:-0.1,z:0),axis:.y,direction:.positive)
        let downward=try surface.ray(from:.init(x:0.18,y:0.6,z:0),axis:.y,direction:.negative)
        try require(!upward.hits.isEmpty && !downward.hits.isEmpty,"Actual shoulder column lacks positive/negative Y observations")
        try require(sourceJSON==Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBody.json")) && sourceField==Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodySDF.bin")),"Building/querying envelope changed body resource bytes")
        log("PASS exact MakeHuman surface: \(rows.count) named + \(randomQueries) seeded whole-body queries, \(usable) usable named Z envelopes, mean named candidate count \(Double(totalCandidates)/18)")
        return ["passed":true,"vertices":surface.positions.count,"triangles":surface.triangleIndices.count/3,
            "components":surface.components.count,"closed":surface.isClosed,"binReferences":surface.binReferenceCount,"cells":surface.cellCount,
            "bodyJSONSHA256":sha(sourceJSON),"bodyFieldSHA256":sha(sourceField),"geometryUnchanged":true,
            "usableZEnvelopes":usable,"meanCandidateTriangles":Double(totalCandidates)/18,"queries":rows,
            "seededWholeBodyQueries":randomQueries,"seededWholeBodyHits":randomHits,"seededAmbiguousQueries":randomAmbiguous,
            "seededMeanCandidates":Double(randomCandidates)/Double(randomQueries),
            "scope":"Exact source surface intersections only. No guarantee of a smooth per-point envelope across a silhouette; ambiguous/tangent/coplanar cases stay explicit. No personal body reconstruction or drape quality claim."]
    }

    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_BODY_ENVELOPE_OUTPUT"] ?? "/private/tmp/TailorAssBodyEnvelope")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        try actorFreeAPI()
        let report:[String:Any]=["passed":true,"nonisolatedAPICallsVerified":true,"analytic":try analytic(),"failures":try failureContracts(),"actualBody":try actualBody(root:root)]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("body-envelope-summary.json"))
        print("PASS source-faithful indexed body rays, exact analytic/body intersections, explicit edge/vertex/tangent/coplanar ambiguity, budgets and cancellation")
    }
}
