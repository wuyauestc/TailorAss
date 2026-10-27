import Foundation
import Synchronization
import Darwin

@main @MainActor struct BodyMeasurementsRegression {
    typealias M=GarmentCodeBodyMeasurements
    typealias V=M.V
    struct Mesh {let p:[V],t:[UInt32]}
    enum Failure:Error {case failed(String)}
    static func require(_ x:Bool,_ m:String)throws {if !x{throw Failure.failed(m)}}
    static func v(_ x:Double,_ y:Double,_ z:Double)->V {.init(x:x,y:y,z:z)}
    static func box(center:V = .zero,scale:Double=1)->Mesh {
        let p=[v(-1,-1,-1),v(1,-1,-1),v(1,-1,1),v(-1,-1,1),v(-1,1,-1),v(1,1,-1),v(1,1,1),v(-1,1,1)]
        return .init(p:p.map{$0*scale+center},t:[0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,1,5,6,1,6,2,2,6,7,2,6,3,3,6,7,3,7,4,3,4,0])
    }
    // Correctly closed standard box; no duplicate/source repair in the module.
    static func cube(center:V = .zero,scale:Double=1)->Mesh {
        let b=box(center:center,scale:scale)
        return .init(p:b.p,t:[0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,1,5,6,1,6,2,2,6,7,2,7,3,3,7,4,3,4,0])
    }
    static func join(_ a:Mesh,_ b:Mesh)->Mesh {.init(p:a.p+b.p,t:a.t+b.t.map{$0+UInt32(a.p.count)})}
    static func encode<T:Encodable>(_ x:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes];return try e.encode(x)}
    static func reject(_ label:String,_ f:()throws->Void)throws {do{try f()}catch{return};throw Failure.failed("Expected rejection: "+label)}
    static func main()async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("resources/GarmentCodeParameterCatalog.json"))
        let values=GarmentCodeBodyParameters(values:catalog.body).values,mesh=cube()
        func prepared(_ m:Mesh,_ limits:M.Limits = .init())throws->M.Prepared {try .init(positions:m.p,triangleIndices:m.t,bodyValues:values,limits:limits)}
        func request(_ x:Double=0,_ z:Double=0,_ y:Double=0.17)throws->M.Request {
            try .init(id:"custom",formula:"Explicit analytical horizontal reference",targetKey:"waist",
                plane:.init(origin:v(0,y,0),normal:v(0,1,0)),axis:.init(origin:v(x,0,z),direction:v(0,1,0)))
        }
        func measured(_ p:M.Prepared,_ r:M.Request)throws->M.Measurement {try p.report(requests:[r]).measurements[0]}
        let p=try prepared(mesh),single=try measured(p,request())
        try require(single.status == .measuredReference && single.section.loops.count==1 && abs(single.observedMeters!-8)<1e-12,"Actual box perimeter")
        try require(single.anatomicalComparisonStatus == .unsupported && single.anatomicalComparisonIssue == .uncertifiedAnatomicalRegion,"Unique containment cannot certify anatomy")
        try require(p.height.observedMeters==2 && p.source.bodyValues==values && p.source.bodyValues.count==33,"Actual height and all33 values retained")
        let multiple=join(mesh,cube(center:v(4,0,0),scale:1.5)),multi=try measured(prepared(multiple),request())
        try require(multi.section.loops.count==2 && multi.observedMeters! == 8 && multi.section.loops.map(\.perimeterMeters).max()!>multi.observedMeters!,"Select containing anchor, neither largest nor summed loop")
        for (name,r,issue) in [("edge",try request(1,0),M.Issue.anchorOnBoundaryOrUncertain),
                              ("corner",try request(1,1),.anchorOnBoundaryOrUncertain),
                              ("oneULP-outside",try request(1.0.nextUp,0),.anchorOnBoundaryOrUncertain),
                              ("outside",try request(2,0),.noContainingLoop),
                              ("empty",try request(0,0,2),.noContainingLoop),
                              ("feature-plane",try request(0,0,1),.sectionIndeterminate)] {
            let q=try measured(p,r);try require(q.status == .unsupported && q.issue==issue && q.observedMeters==nil,name+" must be explicit unsupported")
        }
        let nested=try measured(prepared(join(mesh,cube(scale:0.5))),request())
        try require(nested.issue == .multipleContainingLoops && nested.section.loops.count==2 && nested.observedMeters==nil,"Nested contours cannot choose outer shell silently")
        let moved=cube(center:v(2,3,4)),shifted=try measured(prepared(moved),.init(id:"shifted",formula:"Shifted box and axis",targetKey:"waist",
            plane:.init(origin:v(2,3.17,4),normal:v(0,1,0)),axis:.init(origin:v(2,3,4),direction:v(0,1,0))))
        try require(shifted.status == .measuredReference && abs(shifted.observedMeters!-8)<1e-12 && shifted.section.bodyGeometrySHA256 != single.section.bodyGeometrySHA256,"Shifted actual source and axis")
        let diagonal=try measured(p,.init(id:"oblique",formula:"x+y=.1",targetKey:"waist",
            plane:.init(origin:v(0.1,0,0),normal:v(1,1,0)),axis:.init(origin:.zero,direction:v(1,1,0))))
        try require(diagonal.status == .measuredReference && abs(diagonal.observedMeters!-2*(1.9*sqrt(2)+2))<1e-11,"Oblique plane and axis actual intersection")
        let parallel=try measured(p,.init(id:"parallel",formula:"Parallel axis",targetKey:"waist",
            plane:.init(origin:v(0,0.17,0),normal:v(0,1,0)),axis:.init(origin:.zero,direction:v(1,0,0))))
        try require(parallel.issue == .axisParallelOrUncertain,"Parallel axis has no invented anchor")
        // Same geometry with a changed unused measurement must still change
        // parameter provenance, without claiming the surface was fitted.
        var other=GarmentCodeBodyParameters(values:catalog.body);other.set(values["underbust"]!+1,for:"underbust")
        let changed=try M.Prepared(positions:mesh.p,triangleIndices:mesh.t,bodyValues:other.values)
        try require(changed.source.geometrySHA256==p.source.geometrySHA256 && changed.source.parameterSHA256 != p.source.parameterSHA256,"All source values, including unused inputs, are bound")
        var limits=M.Limits();limits.maximumSelectorEdgeTests=1
        try reject("selector budget"){_=try prepared(mesh,limits).report(requests:[request()])}
        limits = .init();limits.maximumMeasurements=1
        try reject("request budget"){_=try prepared(mesh,limits).referenceReport()}
        var missing=values;missing.removeValue(forKey:"bust")
        try reject("missing source"){_=try M.Prepared(positions:mesh.p,triangleIndices:mesh.t,bodyValues:missing)}
        var altered=values;altered["_bust_line"]!+=0.001
        try reject("altered derived"){_=try M.Prepared(positions:mesh.p,triangleIndices:mesh.t,bodyValues:altered)}
        for key in ["height","bust","waist","hips"] {
            // This is a self-consistent actual BodyParameters value set, not
            // merely a stale-derived or nonfinite-input rejection.
            for target in [-1.0,0.0] {
                var nonpositive=GarmentCodeBodyParameters(values:catalog.body);nonpositive.set(target,for:key)
                try reject("nonpositive measured target "+key){_=try M.Prepared(positions:mesh.p,triangleIndices:mesh.t,bodyValues:nonpositive.values)}
            }
        }
        var extra=values;extra["unclaimed"]=1
        try reject("unknown source key"){_=try M.Prepared(positions:mesh.p,triangleIndices:mesh.t,bodyValues:extra)}
        var invalid=mesh.p;invalid[0].x = .nan
        try reject("nonfinite source"){_=try M.Prepared(positions:invalid,triangleIndices:mesh.t,bodyValues:values)}
        try reject("open source"){_=try prepared(.init(p:mesh.p,t:Array(mesh.t.dropLast(3))))}
        do{_=try M.Prepared(positions:mesh.p,triangleIndices:mesh.t,bodyValues:values,isCancelled:{true});throw Failure.failed("Immediate cancellation returned a Prepared")}
        catch is CancellationError{}
        let cancelled=Mutex(0)
        do{_=try p.referenceReport(isCancelled:{cancelled.withLock{$0+=1;return $0>=4}});throw Failure.failed("Mid report cancellation returned partial output")}catch is CancellationError{}
        let oldRound=fegetround();fesetround(FE_UPWARD)
        var roundingRejected=false
        do{_=try p.report(requests:[request()])}catch {roundingRejected=true}
        fesetround(oldRound);try require(roundingRejected,"Unsupported rounding must be rejected")
        let a=Task.detached{try p.referenceReport()},b=Task.detached{try p.referenceReport()}
        let pair=try await(a.value,b.value)
        try require(try encode(pair.0)==encode(pair.1),"Immutable concurrent deterministic reports")
        struct Female:Decodable {struct Parameters:Decodable {let body:[String:Double]};let parameters:Parameters}
        let female=try JSONDecoder().decode(Female.self,from:Data(contentsOf:root.appendingPathComponent("female-standing-mesher-source.json")))
        var profiles:[[String:Any]]=[]
        for (name,raw) in [("default",catalog.body),("female",female.parameters.body)] {
            let body=GarmentCodeBodyParameters(values:raw),actual=try GarmentCodeStandardBody.load(body:body,resourceDirectory:root.appendingPathComponent("resources"))
            let q=try M.Prepared(positions:actual.positions,triangleIndices:actual.triangleIndices,bodyValues:body.values)
            let report=try q.referenceReport()
            try require(report.measurements.allSatisfy{$0.status == .measuredReference && $0.anatomicalComparisonStatus == .unsupported},"Actual reference selection, never anatomy fit")
            try require(abs(report.height.observedMeters-body["height"]!/100)<1e-12 && !report.bodyFittingApplied,"Actual height and no deformation")
            try require(report.measurements[2].request.plane.origin.y==(body["waist_line"]!-body["vert_bust_line"]!)/100 &&
                report.measurements[2].request.plane.origin.y != (body["waist_line"]!-body["_bust_line"]!)/100,"Chest reference uses raw vertical height, never blended dart balance")
            try encode(report).write(to:out.appendingPathComponent(name+"-measurements.json"))
            let connected=try q.report(requests:[.init(id:"upper-connected-region-probe",formula:"Explicit y=.30m, not a certified chest region",targetKey:"bust",
                plane:.init(origin:v(0,0.3,0),normal:v(0,1,0)),axis:.init(origin:.zero,direction:v(0,1,0)))]).measurements[0]
            try require(connected.section.loops.count==1 && connected.status == .measuredReference && connected.anatomicalComparisonStatus == .unsupported,
                "One axis-containing upper-body ring must not certify an isolated anatomical torso")
            profiles.append(["name":name,"geometrySHA256":report.source.geometrySHA256,"allReferenceLoopsSelected":true,"bodyFittingApplied":false,
                "connectedUpperProbeAnatomyUnsupported":true,"connectedUpperProbePerimeterMeters":connected.observedMeters!])
            print(name,report.measurements.map{$0.observedMeters!},report.measurements.map{$0.section.loops.count})
        }
        let summary:[String:Any]=["passed":true,"analyticGeometryControls":["box","unequal-disjoint-rings","shifted-box-axis","oblique-rectangle"],
            "unsupportedSelectionControls":["edge","corner","oneULP-outside","outside","empty","feature-plane","nested-rings","parallel-axis"],
            "inputBudgetCancellationControls":["parameter-only-source-change","selector-budget","request-budget","missing-source","altered-derived","nonpositive-measured-targets-8-consistent-cases","unknown-key","nonfinite-source","open-source","immediate-cancel","mid-report-cancel","non-nearest-rounding","concurrent-immutable-determinism"],"profiles":profiles,
            "anatomicalFitEstablished":false,"bodyGeometryModified":false,"clothSimulationRun":false]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("swift-summary.json"))
    }
}
