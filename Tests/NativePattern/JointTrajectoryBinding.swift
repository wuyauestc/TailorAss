import Foundation
import Synchronization

@MainActor enum JointTrajectoryBindingChecks {
    typealias S=GarmentCodeJointSimulation
    typealias V=S.V
    typealias E=S.ConfigurationLineEndpoints
    enum Failure:Error {case failed(String)}
    static func need(_ b:Bool,_ m:String)throws {if !b{throw Failure.failed(m)}}
    static func line(_ a:Double,_ b:Double)->E {.init(previous:[V(x:a,y:0,z:0)],candidate:[V(x:b,y:0,z:0)])}
    static func reject(_ label:String,_ run:()throws->Void)throws {
        do{try run()}catch S.SimulationError.invalid(_){return};throw Failure.failed("Expected invalid binding: "+label)
    }
    static func run(root:URL,output:URL)throws {
        func bind(_ trajectory:[E],_ candidates:[E],_ first:Double=0,_ last:Double=2)throws->[Int] {
            try S.configurationCertificateIndices(initial:[V(x:first,y:0,z:0)],final:[V(x:last,y:0,z:0)],trajectory:trajectory,checkedLines:candidates)
        }
        let actual=[line(0,1),line(1,2)],attempts=[line(0,0.5),line(0,1),line(1,1.5),line(1,2)]
        try need(try bind(actual,attempts)==[1,3],"Skip discarded candidates; bind actual accepted chain")
        try need(try bind([],[],0,0).isEmpty,"A true zero-motion chain needs no invented segment")
        try reject("missing"){_=try bind(actual,[line(0,1)])}
        try reject("reverse certificate order"){_=try bind(actual,[line(1,2),line(0,1)])}
        try reject("disconnected actual chain"){_=try bind([line(0,1),line(0,2)],attempts)}
        try reject("wrong final"){_=try bind(actual,attempts,0,3)}
        try reject("zero actual segment"){_=try bind([line(0,0)],[],0,0)}
        try reject("actual segment budget"){_=try bind(Array(repeating:line(0,1),count:97),[])}
        try reject("candidate budget"){_=try bind(actual,Array(repeating:line(0,1),count:193))}
        var signed=line(0,1);signed = .init(previous:[V(x:-0.0,y:0,z:0)],candidate:signed.candidate)
        try reject("signed zero endpoints differ"){_=try bind([line(0,1)],[signed],0,1)}
        try reject("wrong vertex count"){_=try bind(actual,[.init(previous:[],candidate:[])])}
        try reject("nonfinite candidate"){_=try bind(actual,[line(0,.nan)])}
        do{_=try S.configurationCertificateIndices(initial:actual[0].previous,final:actual[1].candidate,trajectory:actual,checkedLines:attempts,isCancelled:{true});throw Failure.failed("Early cancel returned indices")}
        catch is CancellationError{}
        let count=Mutex(0)
        do{_=try S.configurationCertificateIndices(initial:actual[0].previous,final:actual[1].candidate,trajectory:actual,checkedLines:attempts,
            isCancelled:{count.withLock{$0+=1;return $0>=5}});throw Failure.failed("Mid-binding cancel returned partial indices")}
        catch is CancellationError{}
        struct Segment:Decodable {let previous:[V],accepted:[V];let source:GarmentCodeMembranePath.Report}
        struct Native:Decodable {
            struct Statistics:Decodable {let completedAllFeatures:Bool;let completedDomainCertificates:Bool?}
            let status:String,safeTime:Double,minimumSeparation:Double,statistics:Statistics
        }
        struct Path:Decodable {
            let previous:[[Double]],candidate:[[Double]],clear:Bool,body:Native,cloth:Native
            enum CodingKeys:String,CodingKey {case previous,candidate,clear,body;case cloth="self"}
            func endpoints()throws->E {
                func positions(_ rows:[[Double]])throws->[V] {try rows.map{row in
                    guard row.count==3 else {throw Failure.failed("Actual witness endpoint arity")};return V(x:row[0],y:row[1],z:row[2])}}
                return try .init(previous:positions(previous),candidate:positions(candidate))
            }
        }
        struct Case:Decodable {let label:String,sourceSHA256:String;let segments:[Segment],final:[V],paths:[Path]}
        struct Fixture:Decodable {let cases:[Case]}
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:root.appendingPathComponent("ActualTrajectoryBinding.json")))
        var rows:[[String:Any]]=[]
        for c in fixture.cases {
            try need(!c.segments.isEmpty && c.paths.count>c.segments.count,"Actual case must contain discarded certified candidates")
            for p in c.paths {
                try need(p.clear && p.body.status=="clear" && p.body.safeTime==1 && p.body.minimumSeparation==0.0005 && p.body.statistics.completedAllFeatures &&
                    p.cloth.status=="clear" && p.cloth.safeTime==1 && p.cloth.minimumSeparation==0 && p.cloth.statistics.completedAllFeatures &&
                    p.cloth.statistics.completedDomainCertificates==true,"Original native reports must be complete, not invented from endpoints")
            }
            try need(c.segments.allSatisfy{$0.source.status == .clear && $0.source.completedAllTriangles},"Original actual source certificates")
            let indices=try S.configurationCertificateIndices(initial:c.segments[0].previous,final:c.final,
                trajectory:c.segments.map{.init(previous:$0.previous,candidate:$0.accepted)},checkedLines:try c.paths.map{try $0.endpoints()})
            try need(indices.count==c.segments.count && Set(indices).count==indices.count,"Every actual accepted segment matched exactly once")
            rows.append(["label":c.label,"sourceSHA256":c.sourceSHA256,"acceptedSegments":c.segments.count,"allClearAttempts":c.paths.count,
                "matchedIndices":indices,"discardedCertifiedAttempts":c.paths.count-indices.count,"allNativeAndSourceReportsComplete":true])
        }
        let summary:[String:Any]=["passed":true,"actualCases":rows,"pureEndpointSelectionOnly":true,"noPhysicalCapabilityMinted":true,
            "missingReverseDisconnectedNonfiniteZeroAndBudgetRejected":true,"atomicCancellationVerified":true,"noSessionStateFabricated":true]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("trajectory-binding-summary.json"))
    }
}
