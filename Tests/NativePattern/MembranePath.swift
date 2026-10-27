import Foundation
import Darwin
import CryptoKit

typealias P=GarmentCodeMembranePath
typealias V=P.V
nonisolated final class PathCancel:@unchecked Sendable {
    private let lock=NSLock();private var n=0;private let limit:Int
    init(_ limit:Int){self.limit=limit}
    func check()->Bool {lock.lock();defer{lock.unlock()};n+=1;return n>=limit}
}
@main @MainActor struct MembranePathRegression {
    enum Failure:Error {case failed(String)}
    struct State:Decodable {let positions:[V]}
    struct Reference:Decodable {let referencePositions:[V],referenceTriangles:[UInt32],sourcePatternSHA256:String}
    struct Export:Decodable {
        struct Triangle:Decodable {let ids:[Int],du:[Double],dv:[Double],area:Double}
        let triangles:[Triangle]
    }
    static func require(_ ok:Bool,_ message:String)throws {if !ok{throw Failure.failed(message)}}
    static func v(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
    static func barrier()throws->P.M.StrainBarrier {try .init(lowerLimit:0.93,lowerActivation:0.97,upperActivation:1.03,upperLimit:1.07,stiffnessNewtonPerMeter:11)}
    static func rotated(_ x:[V],degrees:Double)->[V] {let a=degrees*Double.pi/180;return x.map{v($0.x*cos(a)+$0.z*sin(a),$0.y,-$0.x*sin(a)+$0.z*cos(a))}}
    static func rejected(_ f:()throws->Void)throws {
        do {try f()}catch is P.PathError{return};throw Failure.failed("Invalid path input accepted")
    }
    static func main()throws {
        let fixture=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let ref=[v(0,0,0),v(0.2,0,0),v(0.02,0.13,0)],m=try P.M.Prepared(referencePositions:ref,triangleIndices:[0,1,2])
        let prepared=try P.Prepared(membrane:m),b=try barrier()
        var results:[String:Any]=["scope":"Whole straight source-strain path bounds only. No body/self contact or garment acceptance."]
        let stationary=try prepared.certify(from:ref,to:ref,barrier:b)
        try require(stationary.status == .clear && stationary.completedAllTriangles,"Stationary source state")
        let twenty=rotated(ref,degrees:20),clear=try prepared.certify(from:ref,to:twenty,barrier:b)
        try require(clear.status == .clear && clear.subdividedNodes>0,"Safe rotation needs adaptive subdivision")
        var noSplit=P.Limits();noSplit.maximumDepth=0
        let uncertain=try P.Prepared(membrane:m,limits:noSplit).certify(from:ref,to:twenty,barrier:b)
        try require(uncertain.status == .indeterminate && !uncertain.completedAllTriangles,"Depth exhaustion is not clear")
        // For this isometric rotation the exact straight-path minimum is
        // cos(theta/2)=.931. Eight levels cannot prove its narrow margin;
        // deeper bounded work must certify it without changing .93/.1.07.
        let narrow=rotated(ref,degrees:2*acos(0.931)*180/Double.pi)
        var eight=P.Limits();eight.maximumDepth=8
        let shallow=try P.Prepared(membrane:m,limits:eight).certify(from:ref,to:narrow,barrier:b)
        let deep=try prepared.certify(from:ref,to:narrow,barrier:b)
        try require(shallow.status == .indeterminate && deep.status == .clear && deep.completedAllTriangles &&
            deep.maximumDepthReached>8 && deep.minimumCertifiedPrincipalStretch!>0.93 && deep.maximumCertifiedPrincipalStretch!<1.07,
            "Finite deeper source proof must retain the original physical domain")
        results["analyticNarrowMarginShallow"]=try object(shallow)
        results["analyticNarrowMarginDeep"]=try object(deep)
        for angle in [60.0,180] {
            let end=rotated(ref,degrees:angle),startQ=try m.inspect(positions:ref),endQ=try m.inspect(positions:end)
            try require(startQ.maximumAbsolutePrincipalStrain<1e-12 && endQ.maximumAbsolutePrincipalStrain<1e-12,"Isometric endpoints")
            let report=try prepared.certify(from:ref,to:end,barrier:b)
            try require(report.status == .outsideDomain && report.witnessParameter==0.5,"Must catch interior compression/collapse despite safe endpoints")
        }
        let outside=try prepared.certify(from:ref,to:ref.map{$0*1.08},barrier:b)
        try require(outside.status == .outsideDomain && outside.witnessParameter==1,"Invalid endpoint")
        var oneNode=P.Limits();oneNode.maximumIntervalNodes=1
        let limited=try P.Prepared(membrane:m,limits:oneNode).certify(from:ref,to:twenty,barrier:b)
        try require(limited.status == .budgetExceeded && !limited.completedAllTriangles,"Node budget cannot yield partial clear")
        for cancel in [PathCancel(1),PathCancel(3)] {
            do {_ = try prepared.certify(from:ref,to:twenty,barrier:b,isCancelled:{cancel.check()});throw Failure.failed("Cancellation ignored")} catch is CancellationError{}
        }
        try rejected{_ = try prepared.certify(from:ref,to:Array(ref.dropLast()),barrier:b)}
        try rejected{var invalid=ref;invalid[0].x = .nan;_ = try prepared.certify(from:invalid,to:ref,barrier:b)}
        try rejected{var invalid=P.Limits();invalid.maximumDepth=13;_ = try P.Prepared(membrane:m,limits:invalid)}
        // This checks the API contract for rounding mode, restoring it even if
        // the test throws. No production call changes floating-point state.
        let mode=fegetround()
        do {
            defer{_ = fesetround(mode)}
            try require(fesetround(FE_DOWNWARD)==0,"Set rounding mode for negative control")
            try rejected{_ = try prepared.certify(from:ref,to:ref,barrier:b)}
        }
        // Extreme coordinate scaling exposes arithmetic cancellation. Widened
        // intervals may be more conservative, but cannot certify a bad path.
        let shifted=ref.map{$0+v(60,30,-20)},translated=try prepared.certify(from:shifted,to:rotated(shifted,degrees:20),barrier:b)
        try require(translated.status == .clear,"Rigidly rotated remote source path")
        results["analyticSafeRotation"]=try object(clear);results["analyticDepthExhaustion"]=try object(uncertain)
        let decoder=JSONDecoder(),source=try decoder.decode(Reference.self,from:Data(contentsOf:fixture.appendingPathComponent("reference-mesh.json")))
        let start=try decoder.decode(State.self,from:Data(contentsOf:fixture.appendingPathComponent("start-r62-accepted.json")))
        let end=try decoder.decode(State.self,from:Data(contentsOf:fixture.appendingPathComponent("candidate-r63-newton3-blocked.json")))
        let exported=try decoder.decode(Export.self,from:Data(contentsOf:fixture.appendingPathComponent("prepared-triangles.json")))
        let actual=try P.M.Prepared(referencePositions:source.referencePositions,triangleIndices:source.referenceTriangles)
        try require(actual.triangles.count==3472 && actual.vertexCount==2000 && exported.triangles.count==3472,"Whole source fixture")
        for (a,e) in zip(actual.triangles,exported.triangles) {
            try require([a.a,a.b,a.c]==e.ids && [a.du.x,a.du.y,a.du.z]==e.du && [a.dv.x,a.dv.y,a.dv.z]==e.dv && a.referenceAreaSquareMeters==e.area,"Exact actual source coefficients")
        }
        let stamp=Date(),proof=try P.Prepared(membrane:actual).certify(from:start.positions,to:end.positions,barrier:b),seconds=Date().timeIntervalSince(stamp)
        let prior=try P.Prepared(membrane:actual,limits:noSplit).certify(from:start.positions,to:end.positions,barrier:b)
        try require(proof.status == .clear && proof.completedAllTriangles && proof.maximumDepthReached==1 && proof.intervalNodes==3474 && prior.status == .indeterminate,"Recorded rejected r63 path: one segment insufficient, bounded subdivision succeeds")
        try require(proof.minimumCertifiedPrincipalStretch!>0.93 && proof.maximumCertifiedPrincipalStretch!<1.07,"Original strict source interval retained")
        results["actualR63"]=try object(proof);results["actualR63Seconds"]=seconds
        results["sourceSHA256"]=source.sourcePatternSHA256;results["passed"]=true;results["physicalStepAccepted"]=false
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("membrane-path-summary.json"))
        print("Membrane path: actual r63 bounded certificate and real interior-failure controls passed; no physical step accepted.")
    }
    static func object<T:Encodable>(_ x:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(x))}
}
