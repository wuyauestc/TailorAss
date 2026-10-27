import Foundation

/// Executes the real App Vector3 adapter against the locally linked native module.
/// These are motion-path checks, not a completed garment simulation.
@main @MainActor
struct ContinuousBodyContactRegression {
    typealias C=GarmentCodeContinuousBodyContact
    typealias V=GarmentCodeCircleDrape.Vector3
    enum Failure:Error {case check(String)}
    static func require(_ condition:@autoclosure()->Bool,_ message:String)throws {
        if !condition(){throw Failure.check(message)}
    }
    static func pathFailure(_ expected:String,_ operation:()throws->Void)throws {
        do {try operation();throw Failure.check("Expected rejected motion: \(expected)")}
        catch let C.MotionError.pathNotCertified(status) {
            try require(status==expected,"Unexpected path rejection \(status), expected \(expected)")
        }
    }
    static func cancelled(_ operation:()throws->Void)throws {
        do {try operation();throw Failure.check("Cancellation was not propagated")}
        catch is CancellationError {}
    }
    struct Fixture:Decodable {
        let bodyPositions:[[Double]],bodyTriangleIndices:[UInt32]
        let previous:[[Double]],candidate:[[Double]],clothTriangleIndices:[UInt32]
    }
    static func vectors(_ arrays:[[Double]])throws->[V] {
        try arrays.map {a in
            guard a.count==3 else {throw Failure.check("Malformed fixture vector")}
            return V(x:a[0],y:a[1],z:a[2])
        }
    }
    static func main()throws {
        try require(C.isAvailable,"This test must execute the real linked native package")
        try require(!GarmentCodeSewnDrape.CouplingOptions().useContinuousBodyContact,
                    "Existing sewing callers unexpectedly enabled experimental body CCD")
        let body=[V(x:-1,y:-1,z:0),V(x:1,y:-1,z:0),V(x:0,y:1,z:0)]
        let before=[V(x:-0.1,y:-0.1,z:1),V(x:0.1,y:-0.1,z:1),V(x:0,y:0.1,z:1)]
        let after=before.map{V(x:$0.x,y:$0.y,z:-1)}
        let tris:[UInt32]=[0,1,2]
        let prepared=try C.Prepared(bodyPositions:body,bodyTriangleIndices:tris)
        let limited=try prepared.guardMotion(previous:before,candidate:after,clothTriangleIndices:tris)
        try require(!limited.permitsWholeCandidate && limited.metrics.status=="limited" &&
                    limited.metrics.completedAllFeatures,"Crossing path was accepted without clipping")
        try require(abs((limited.metrics.conservativeTimeOfImpact ?? 2)-0.5)<1e-6 &&
                    limited.metrics.safeTimeFraction>0.44999 && limited.metrics.safeTimeFraction<0.45001,
                    "Analytic first contact / safe time was changed by the bridge")
        for i in before.indices {
            let expected=before[i]+(after[i]-before[i])*limited.metrics.safeTimeFraction
            try require(limited.positions[i]==expected && limited.positions[i].z>0.09999,
                        "App coordinates were not clipped with one common safe time")
        }
        let again=try prepared.guardMotion(previous:before,candidate:after,clothTriangleIndices:tris)
        try require(again.positions==limited.positions && before[0].z==1 && after[0].z == -1,
                    "Prepared body reuse or immutable input arrays changed")
        let far=before.map{$0+V(x:5,y:0,z:0)},farAfter=after.map{$0+V(x:5,y:0,z:0)}
        let clear=try prepared.guardMotion(previous:far,candidate:farAfter,clothTriangleIndices:tris)
        try require(clear.permitsWholeCandidate && clear.positions==farAfter &&
                    clear.metrics.conservativeTimeOfImpact==nil,"Clear path failed exact candidate roundtrip")
        try pathFailure("invalid") {_=try prepared.guardMotion(previous:[],candidate:after,clothTriangleIndices:tris)}
        try pathFailure("invalid") {
            var invalid=after;invalid[0].x = .nan
            _=try prepared.guardMotion(previous:before,candidate:invalid,clothTriangleIndices:tris)
        }
        try pathFailure("blockedInitialContact") {
            let touching=before.map{V(x:$0.x,y:$0.y,z:0)}
            _=try prepared.guardMotion(previous:touching,candidate:before,clothTriangleIndices:tris)
        }
        do {
            _=try C.Prepared(bodyPositions:body,bodyTriangleIndices:[0,1,9])
            throw Failure.check("Malformed body indices were accepted")
        } catch C.MotionError.invalidBody {}
        try cancelled {_=try C.Prepared(bodyPositions:body,bodyTriangleIndices:tris,isCancelled:{true})}
        try cancelled {_=try prepared.guardMotion(previous:before,candidate:after,clothTriangleIndices:tris,isCancelled:{true})}
        guard CommandLine.arguments.count==3 else {throw Failure.check("Expected real fixture and report paths")}
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let actual=try C.Prepared(bodyPositions:vectors(fixture.bodyPositions),bodyTriangleIndices:fixture.bodyTriangleIndices)
        let real=try actual.guardMotion(previous:vectors(fixture.previous),candidate:vectors(fixture.candidate),
                                       clothTriangleIndices:fixture.clothTriangleIndices)
        // A separate C++ full-scan oracle establishes the fixture first contact
        // at .1642859028; the App must return the package's conservative .9 time.
        try require(real.metrics.completedAllFeatures && real.metrics.status=="limited" &&
                    abs(real.metrics.safeTimeFraction-0.14785537719726563)<1e-8 &&
                    (real.metrics.conservativeTimeOfImpact ?? 1)<0.1642859028,
                    "Real upper-body motion lost its independently checked safe time")
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        let metrics=try encoder.encode(real.metrics)
        try metrics.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("PASS: App native bridge analytic clipping, clear roundtrip, input preservation, invalid/contact/cancel rejection, default-off compatibility, real upper-body path")
    }
}
