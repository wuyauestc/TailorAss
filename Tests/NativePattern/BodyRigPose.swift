import Foundation
import CryptoKit

nonisolated private final class RigCancel: @unchecked Sendable {
    private let lock=NSLock();private var calls=0
    let threshold:Int
    init(_ t:Int){threshold=t}
    func check()->Bool {lock.lock();defer{lock.unlock()};calls+=1;return calls>=threshold}
}
@main @MainActor struct BodyRigPoseRegression {
    typealias R=GarmentCodeBodyRig
    typealias V=R.V
    enum Failure:Error {case check(String)}
    static func check(_ x:Bool,_ m:String)throws{if !x{throw Failure.check(m)}}
    static func hash(_ d:Data)->String{SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
    static func same(_ a:[V],_ b:[V])->Bool {
        a.count==b.count && zip(a,b).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern}
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2]),resources=root.appendingPathComponent("resources")
        let template=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBody.json"))
        let rigData=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodyRig/rig.json"))
        let provenance=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodyRig/provenance.json"))
        let rig=try R.Prepared(templateData:template,rigData:rigData,provenanceData:provenance)
        let catalog=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let female=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("female-standing-mesher-source.json"))) as! [String:Any]
        let femaleBody=(female["parameters"] as! [String:Any])["body"] as! [String:Double]
        let profiles=[("default",GarmentCodeBodyParameters(values:catalog.body)),("female",GarmentCodeBodyParameters(values:femaleBody))]
        let raw=try JSONSerialization.jsonObject(with:rigData) as! [String:Any]
        let joints=raw["joints"] as! [[String:Any]],bones=raw["bones"] as! [[String:Any]]
        let bnames=bones.map{$0["name"] as! String}
        let points=(try JSONSerialization.jsonObject(with:template) as! [String:Any])["positions"] as! [[Double]]
        var mirror:[Int]=[],lookup:[String:Int]=[:]
        func key(_ p:[Double])->String {p.map{String(format:"%.7f",$0==0 ? 0:$0)}.joined(separator:",")}
        for (i,p) in points.enumerated(){lookup[key(p)]=i}
        for p in points {guard let i=lookup[key([-p[0],p[1],p[2]])]else{throw Failure.check("Missing independently keyed mirror point")};mirror.append(i)}
        var results:[[String:Any]]=[]
        for (name,body) in profiles {
            let standard=try GarmentCodeStandardBody.load(body:body,resourceDirectory:resources)
            let identity=try rig.pose(visiblePositions:standard.positions,triangleIndices:standard.triangleIndices,bodyValues:body.values)
            try check(same(identity.diagnosticPositions,standard.positions),"Default identity changed old visible Double bytes")
            try JSONEncoder().encode(identity.diagnosticJointAnchors).write(to:out.appendingPathComponent("identity-\(name)-joints.json"))
            let identityGate=identity.validatedBody != nil
            if let valid=identity.validatedBody {
                try check(valid.compatibleWithLegacyInverseSDF,"Identity SDF binding")
                let q=try GarmentCodeBodyMeshQueries.Prepared(positions:valid.positions,triangleIndices:valid.triangleIndices)
                try check(q.geometrySHA256==valid.geometrySHA256,"Visible posed mesh binding differs from exact query geometry")
            }
            results.append(["profile":name,"pose":"identity","bitwiseOldMeshIdentity":true,"allowed":identityGate,"geometrySHA256":identity.geometrySHA256,"reasons":identity.rejectionReasons,"selfCrossings":identity.statistics.selfInspection.intersectingTrianglePairs])
            for alpha in [30.0,45,60] {
                let a=try rig.pose(visiblePositions:standard.positions,triangleIndices:standard.triangleIndices,bodyValues:body.values,pose:.arms(alphaDegrees:alpha))
                try check(a.notIndependentlyFittedBodyFields.count==26 && !a.independentSurfaceFittingImplemented,"26 fields must not be advertised as fitted")
                try check(a.statistics.retainedWeightPairs==40156 && a.statistics.maximumInfluencesPerVertex==9,"Full weights pruned")
                try check(a.statistics.minimumTriangleCrossSquaredMeters4>1e-22 && a.statistics.minimumReferenceNormalDot>0,"Posed triangle local orientation/area failed")
                var maxMirror=0.0
                for i in mirror.indices {let p=a.diagnosticPositions[i],q=a.diagnosticPositions[mirror[i]];maxMirror=max(maxMirror,abs(p.x+q.x),abs(p.y-q.y),abs(p.z-q.z))}
                try check(maxMirror<1e-12,"Bilateral pose is not symmetric")
                var armRows:[[String:Any]]=[]
                for side in ["L","R"] {
                    let upper=bnames.firstIndex(of:"upperarm01."+side)!,elbow=bnames.firstIndex(of:"upperarm02."+side)!,wrist=bnames.firstIndex(of:"wrist."+side)!
                    let h=bones[upper]["head"] as! Int,e=bones[elbow]["tail"] as! Int,w=bones[wrist]["head"] as! Int
                    let d=a.diagnosticJointAnchors[e]-a.diagnosticJointAnchors[h],angle=atan2(-d.y,abs(d.x))*180/Double.pi
                    try check(abs(angle-alpha)<1e-11,"Arm proxy projected angle mismatches declared alpha")
                    let originalElbow=identity.diagnosticJointAnchors[e]-identity.diagnosticJointAnchors[h]
                    let originalWrist=identity.diagnosticJointAnchors[w]-identity.diagnosticJointAnchors[e]
                    try check(abs(d.length-originalElbow.length)<1e-13 && abs((a.diagnosticJointAnchors[w]-a.diagnosticJointAnchors[e]).length-originalWrist.length)<1e-13,"Arm chain length changed under rigid pose")
                    armRows.append(["side":side,"projectedBelowHorizontalDegrees":angle,"shoulderElbowLength":d.length,"shoulder":[a.diagnosticJointAnchors[h].x,a.diagnosticJointAnchors[h].y,a.diagnosticJointAnchors[h].z]])
                }
                if a.statistics.selfInspection.intersectingTrianglePairs>0 {
                    try check(a.validatedBody==nil && a.rejectionReasons.contains("nonadjacentSurfaceIntersection"),"Self intersecting pose acquired body capability")
                } else {try check(a.validatedBody != nil,"Clear geometric pose was unexpectedly rejected")}
                if let valid=a.validatedBody {
                    try check(!valid.compatibleWithLegacyInverseSDF,"Posed body cannot use original inverse SDF")
                    let q=try GarmentCodeBodyMeshQueries.Prepared(positions:valid.positions,triangleIndices:valid.triangleIndices)
                    try check(q.geometrySHA256==valid.geometrySHA256,"Posed final visible body/query SHA mismatch")
                    for index in [0,1000,10000] {try check(q.query(valid.positions[index]).classification == .onSurface,"Posed exact visible vertex is not on final body surface")}
                }
                let r:[String:Any]=["profile":name,"alpha":alpha,"allowed":a.fixedBodyPreparationAllowed,"geometrySHA256":a.geometrySHA256,"mirrorErrorMeters":maxMirror,"statistics":try JSONSerialization.jsonObject(with:JSONEncoder().encode(a.statistics)),"armProxies":armRows,"rejectionReasons":a.rejectionReasons]
                results.append(r)
                let encoded=try JSONEncoder().encode(a.diagnosticPositions);try encoded.write(to:out.appendingPathComponent("pose-\(name)-\(Int(alpha))-positions.json"))
            }
            if name=="default" {
                let bad=try rig.pose(visiblePositions:standard.positions,triangleIndices:standard.triangleIndices,bodyValues:body.values,pose:.arms(alphaDegrees:90))
                try check(bad.statistics.minimumReferenceNormalDot<0 && bad.validatedBody==nil && bad.rejectionReasons.contains("referenceTriangleOrientationReversed"),"Real 90-degree folded skinning pose acquired body capability")
                results.append(["profile":name,"alpha":90,"allowed":false,"rejectionReasons":bad.rejectionReasons,"minimumNormalDot":bad.statistics.minimumReferenceNormalDot,"selfCrossings":bad.statistics.selfInspection.intersectingTrianglePairs])
            }
            var changed=standard.positions;changed[0].x=changed[0].x.nextUp
            do{_=try rig.pose(visiblePositions:changed,triangleIndices:standard.triangleIndices,bodyValues:body.values);throw Failure.check("Changed mesh binding accepted")}catch is R.RigError{}
        }
        var invalidCases:[String]=[]
        func bad(_ label:String,_ edit:(inout [String:Any])->Void)throws {
            var value=raw;edit(&value);let data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
            var p=try JSONSerialization.jsonObject(with:provenance) as! [String:Any];p["rigResourceSHA256"]=hash(data)
            do{_=try R.Prepared(templateData:template,rigData:data,provenanceData:JSONSerialization.data(withJSONObject:p));throw Failure.check("Malformed accepted: "+label)}catch is R.RigError{invalidCases.append(label)}
        }
        try bad("invalid parent DAG"){j in var bs=j["bones"] as! [[String:Any]];bs[0]["parent"]=0;j["bones"]=bs}
        try bad("unknown source-visible map"){j in var a=j["sourceToVisible"] as! [Int];a[0]=1;j["sourceToVisible"]=a}
        try bad("negative weight"){j in var w=j["weights"] as! [String:Any],a=w["rawValues"] as! [Double];a[0] = -0.1;w["rawValues"]=a;j["weights"]=w}
        try bad("changed normalized proportions"){j in var w=j["weights"] as! [String:Any],a=w["normalizedValues"] as! [Double];a[0]+=0.1;w["normalizedValues"]=a;j["weights"]=w}
        try bad("duplicate influence"){j in var w=j["weights"] as! [String:Any],a=w["boneIndices"] as! [Int];a[1]=a[0];w["boneIndices"]=a;j["weights"]=w}
        try bad("duplicated joint ownership"){j in var bs=j["bones"] as! [[String:Any]];bs[0]["head"]=bs[1]["head"];j["bones"]=bs}
        var small=R.Limits();small.maximumResourceBytes=4096
        do{_=try R.Prepared(templateData:template,rigData:rigData,provenanceData:provenance,limits:small);throw Failure.check("Resource budget accepted")}catch R.RigError.budgetExceeded{invalidCases.append("resource byte budget")}
        do{_=try R.Prepared(templateData:template,rigData:rigData,provenanceData:provenance,isCancelled:{true});throw Failure.check("Preparation cancel accepted")}catch is CancellationError{invalidCases.append("cancel before preparation")}
        let standard=try GarmentCodeStandardBody.load(body:profiles[0].1,resourceDirectory:resources)
        let token=RigCancel(40)
        do{_=try rig.pose(visiblePositions:standard.positions,triangleIndices:standard.triangleIndices,bodyValues:profiles[0].1.values,pose:.arms(alphaDegrees:45),isCancelled:{token.check()});throw Failure.check("Mid pose cancel accepted")}catch is CancellationError{invalidCases.append("mid pose atomic cancellation")}
        var limited=R.Limits();limited.maximumCandidatePairs=1
        let lr=try R.Prepared(templateData:template,rigData:rigData,provenanceData:provenance,limits:limited)
        do{_=try lr.pose(visiblePositions:standard.positions,triangleIndices:standard.triangleIndices,bodyValues:profiles[0].1.values);throw Failure.check("Surface candidate budget accepted")}catch GarmentCodeClothContact.ContactError.budgetExceeded{invalidCases.append("surface candidate budget")}
        let summary:[String:Any]=["passed":true,"profiles":results,"invalidCases":invalidCases,"sourceRigSHA256":rig.rigResourceSHA256,"templateGeometrySHA256":rig.templateGeometrySHA256,"scope":"Optional fixed-body pose only; no 26-field surface fitter, old SDF update, App route or cloth result.","jointCount":joints.count]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("body-rig-pose-summary.json"))
        print("PASS: optional rig loader/identity, 6 real bilateral poses, full skin weights, all original triangle self-inspections and rejection/cancellation gates")
    }
}
