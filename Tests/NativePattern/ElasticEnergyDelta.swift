import Foundation
#if os(macOS)
import Darwin
import os
#endif

@main @MainActor struct ElasticEnergyDeltaRegression {
    typealias E=GarmentCodeElasticEnergyDelta
    typealias M=GarmentCodeMembrane
    typealias H=GarmentCodeHingeBending
    typealias V=E.V
    enum Failure:Error {case check(String)}
    struct Capture:Decodable {let referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[H.PanelGroup]}
    struct Controls:Decodable {
        struct Material:Decodable {let mu:Double,lambda:Double,kb:Double}
        struct Barrier:Decodable {let lowerLimit:Double,lowerActivation:Double,upperActivation:Double,upperLimit:Double,stiffness:Double}
        struct Triangle:Decodable {let ids:[Int],du:[Double],dv:[Double],area:Double}
        struct Hinge:Decodable {let ids:[Int],weight:Double,sourceL:Double,sourceN1:Double,sourceN2:Double,panelID:String}
        struct Row:Decodable {let ids:[Int],coefficients:[Double],targetDouble:Double}
        struct Context:Decodable {let inertial:[Double],rows:[Row],sewingStiffness:Double,base:[V],predictor:[V]}
        struct Newton:Decodable {let power:Int,alpha:Double,candidate:[V],expectedNHDelta:Double,expectedFullPhiDelta:Double,armijoIncrement:Double,expectedArmijoPass:Bool,actualRoundedGradientWork:Double}
        struct Active:Decodable {let name:String,base:[V],candidate:[V],expectedDelta:[String:Double],gradientWork:Double,activePrincipalTerms:Int}
        let canonicalSourceSHA256:String,material:Material,barrier:Barrier,storedTriangles:[Triangle],storedHinges:[Hinge],newtonContext:Context,newtonCases:[Newton],activeCases:[Active]
    }
    struct NearLimit:Decodable {
        let sourceSHA256:String,referencePositions:[V],referenceTriangles:[UInt32],storedTriangles:[Controls.Triangle]
        let before:[V],after:[V],beforeBits:[[String]],afterBits:[[String]]
        let expectedBarrierForward:Double,expectedBarrierReverse:Double,expectedFullForward:Double,expectedFullReverse:Double
        let otherForward:[String:Double],otherReverse:[String:Double]
        let rawOriginalDeltaForward:Double,rawOriginalDeltaReverse:Double
    }
    nonisolated final class Counter:@unchecked Sendable {
        let lock=NSLock();var count=0;let stop:Int
        init(_ stop:Int){self.stop=stop}
        func cancelled()->Bool{lock.lock();defer{lock.unlock()};count+=1;return count>=stop}
    }
    static func v(_ x:Double,_ y:Double=0,_ z:Double=0)->V{.init(x:x,y:y,z:z)}
    static func require(_ ok:Bool,_ message:String)throws{if !ok{throw Failure.check(message)}}
    static func dot(_ a:V,_ b:V)->Double{a.x*b.x+a.y*b.y+a.z*b.z}
    static func sum(_ a:[Double])->Double{var s=0.0,c=0.0;for x in a{let t=s+x;if abs(s)>=abs(x){c+=(s-t)+x}else{c+=(x-t)+s};s=t};return s+c}
    static func invalid(_ f:()throws->Void)throws {do{try f()}catch is E.DeltaError{return};throw Failure.check("Invalid delta input accepted")}
    static func unknown(_ f:()throws->Void)throws {do{try f()}catch E.DeltaError.precisionUnresolved{return};throw Failure.check("Numerically unresolved increment accepted")}
    static func cancelled(_ f:()throws->Void)throws {do{try f()}catch is CancellationError{return};throw Failure.check("Cancellation not propagated")}
    static func nonelastic(_ c:Controls.Context,_ candidate:[V])->Double {
        let d=zip(candidate,c.base).map{$0-$1}
        let inertia=c.base.indices.map{i in c.inertial[i]*(dot(c.base[i]-c.predictor[i],d[i])+0.5*d[i].lengthSquared)}
        func point(_ z:[V],_ r:Controls.Row)->V {zip(r.ids,r.coefficients).reduce(V.zero){$0+z[$1.0]*$1.1}}
        let sewing=c.rows.map{r->Double in
            let a=point(c.base,r),b=point(d,r),old=a.length,new=(a+b).length,den=old+new
            let dl=den>0 ? (2*dot(a,b)+b.lengthSquared)/den:0
            return c.sewingStiffness*((old-r.targetDouble)*dl+0.5*dl*dl)
        }
        return sum([sum(inertia),sum(sewing)])
    }
    static func main()throws {
        guard CommandLine.arguments.count==4 else{throw Failure.check("source-topology controls-json output-directory")}
        let decoder=JSONDecoder(),capture=try decoder.decode(Capture.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let controls=try decoder.decode(Controls.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
        let out=URL(fileURLWithPath:CommandLine.arguments[3]);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let nearURL=URL(fileURLWithPath:CommandLine.arguments[2]).deletingLastPathComponent().appendingPathComponent("near-limit413.json")
        let near=try decoder.decode(NearLimit.self,from:Data(contentsOf:nearURL))
        try require(near.sourceSHA256=="e923c793ce690109690eaf2ac63d726cc73d6138d554e1b8599c73e6048af5b4","Near-limit component is not bound to the actual complete shirt source")
        func exactBits(_ rows:[V],_ stored:[[String]])->Bool {
            rows.count==stored.count && zip(rows,stored).allSatisfy{v,b in b.count==3 && zip([v.x,v.y,v.z],b).allSatisfy{$0.bitPattern==UInt64($1,radix:16)}}
        }
        try require(exactBits(near.before,near.beforeBits) && exactBits(near.after,near.afterBits),"Actual near-limit endpoints changed binary64 coordinates")
        let nearM=try M.Prepared(referencePositions:near.referencePositions,triangleIndices:near.referenceTriangles),nearE=try E.Prepared(membrane:nearM)
        for(t,z)in zip(nearM.triangles,near.storedTriangles){try require([t.a,t.b,t.c]==z.ids && [t.du.x,t.du.y,t.du.z]==z.du && [t.dv.x,t.dv.y,t.dv.z]==z.dv && t.referenceAreaSquareMeters==z.area,"Actual near-limit source shape coefficients changed")}
        let m=try M.Prepared(referencePositions:capture.referencePositions,triangleIndices:capture.referenceTriangles)
        let h=try H.Prepared(referencePositions:capture.referencePositions,referenceTriangles:capture.referenceTriangles,panelGroups:capture.panelGroups)
        let onlyM=try E.Prepared(membrane:m),all=try E.Prepared(membrane:m,bending:h)
        try require(m.triangles.count==3472 && h.hinges.count==4948,"Incomplete actual source")
        try require(controls.storedTriangles.count==m.triangles.count && controls.storedHinges.count==h.hinges.count,"Stored source measures missing")
        for (t,s) in zip(m.triangles,controls.storedTriangles){try require([t.a,t.b,t.c]==s.ids && [t.du.x,t.du.y,t.du.z]==s.du && [t.dv.x,t.dv.y,t.dv.z]==s.dv && t.referenceAreaSquareMeters==s.area,"Actual captured source coefficients changed")}
        for (t,s) in zip(h.hinges,controls.storedHinges){try require(t.vertexIDs==s.ids && t.sourceWeight==s.weight && t.sourceEdgeLengthMeters==s.sourceL && t.sourceFirstCrossNormSquareMeters==s.sourceN1 && t.sourceSecondCrossNormSquareMeters==s.sourceN2 && t.panelID==s.panelID,"Actual captured hinge weight changed")}
        let mat=try M.Material(shearStiffnessNewtonPerMeter:controls.material.mu,areaStiffnessNewtonPerMeter:controls.material.lambda)
        let b=controls.barrier,bar=try M.StrainBarrier(lowerLimit:b.lowerLimit,lowerActivation:b.lowerActivation,upperActivation:b.upperActivation,upperLimit:b.upperLimit,stiffnessNewtonPerMeter:b.stiffness)
        let bend=try H.Material(bendingStiffnessNewtonMeter:controls.material.kb)
        let nf=try nearE.evaluate(from:near.before,to:near.after,material:mat,barrier:bar),nr=try nearE.evaluate(from:near.after,to:near.before,material:mat,barrier:bar)
        try require(abs(nf.principalBarrierDeltaJoules-near.expectedBarrierForward)<1e-29 && abs(nr.principalBarrierDeltaJoules-near.expectedBarrierReverse)<1e-29 && abs(nf.principalBarrierDeltaJoules+nr.principalBarrierDeltaJoules)<1e-29,"Near-limit barrier base-value rounding bias returned")
        func joined(_ other:[String:Double],_ barrier:Double)->Double {sum([other["inertia"]!,other["sewing"]!,other["NH"]!,barrier,other["bending"]!,other["body"]!,other["self"]!])}
        let fullForward=joined(near.otherForward,nf.principalBarrierDeltaJoules),fullReverse=joined(near.otherReverse,nr.principalBarrierDeltaJoules)
        try require(near.rawOriginalDeltaForward<0 && near.rawOriginalDeltaReverse<0 && fullForward>0 && fullReverse<0,"Actual false two-direction descent was not corrected")
        try require(abs(fullForward-near.expectedFullForward)<0.01*abs(near.expectedFullForward) && abs(fullReverse-near.expectedFullReverse)<0.01*abs(near.expectedFullReverse),"Near-limit complete source fixed-context increment differs from independent oracle")
        let ne:[String:Any]=["sourceSHA256":near.sourceSHA256,"barrierForwardJ":nf.principalBarrierDeltaJoules,"barrierReverseJ":nr.principalBarrierDeltaJoules,"oracleBarrierForwardJ":near.expectedBarrierForward,"reconstructedCompleteForwardJ":fullForward,"reconstructedCompleteReverseJ":fullReverse,"oracleCompleteForwardJ":near.expectedFullForward,"oracleCompleteReverseJ":near.expectedFullReverse,"oldBothNegativePreserved":true,"reconstructedWholeContextNotNewSimulation":true]
        let neData=try JSONSerialization.data(withJSONObject:ne,options:[.sortedKeys,.prettyPrinted]);try neData.write(to:out.appendingPathComponent("near-limit413-summary.json"))
#if os(macOS)
        // Every external callback boundary, including the final callback, must
        // fail closed if it changes the rounding mode while returning false.
        let callbackCount=OSAllocatedUnfairLock(initialState:0)
        _ = try nearE.evaluate(from:near.before,to:near.after,material:mat,barrier:bar,isCancelled:{callbackCount.withLock{$0+=1};return false})
        let totalCallbacks=callbackCount.withLock{$0};try require(totalCallbacks>=4,"Rounding callback coverage incomplete")
        for target in 1...totalCallbacks {
            let count=OSAllocatedUnfairLock(initialState:0)
            var rejected=false
            do {_ = try nearE.evaluate(from:near.before,to:near.after,material:mat,barrier:bar,isCancelled:{
                let n=count.withLock{$0+=1;return $0}
                if n==target {_ = Darwin.fesetround(Darwin.FE_UPWARD)}
                return false
            })}catch E.DeltaError.precisionUnresolved {rejected=true}
            _ = Darwin.fesetround(Darwin.FE_TONEAREST)
            try require(rejected,"Rounding change at callback boundary accepted a delta")
        }
#endif

        var rows:[[String:Any]]=[]
        for c in controls.newtonCases {
            let delta=try onlyM.evaluate(from:controls.newtonContext.base,to:c.candidate,material:mat,barrier:bar)
            let total=sum([delta.totalDeltaJoules,nonelastic(controls.newtonContext,c.candidate)])
            // A fixture accuracy check is separate from the exact Armijo sign
            // comparison below. No epsilon is added to a line-search threshold.
            try require(abs(delta.neoHookeanDeltaJoules-c.expectedNHDelta)<=1e-10*abs(c.expectedNHDelta)+1e-32,"NH increment differs from Decimal100 reference")
            try require(delta.principalBarrierDeltaJoules==0 && delta.hingeDeltaJoules==0,"Original kappa0/barrier0 control changed objective")
            try require((total<=c.armijoIncrement)==c.expectedArmijoPass,"Actual rounded full-Phi Armijo decision differs from high precision")
            rows.append(["power":c.power,"estimatedElasticDeltaJ":delta.totalDeltaJoules,"estimatedFullPhiDeltaJ":total,"decimal100FullPhiDeltaJ":c.expectedFullPhiDelta,"armijoIncrementJ":c.armijoIncrement,"armijoMatched":true,"candidateAccepted":false])
        }
        var activeRows:[[String:Any]]=[]
        for c in controls.activeCases {
            let d=try all.evaluate(from:c.base,to:c.candidate,material:mat,barrier:bar,bendingMaterial:bend)
            let values=["membrane":d.neoHookeanDeltaJoules,"barrier":d.principalBarrierDeltaJoules,"hinge":d.hingeDeltaJoules,"total":d.totalDeltaJoules]
            for key in values.keys {
                let actual=values[key]!,expected=c.expectedDelta[key]!
                try require((actual<0)==(expected<0) && (actual==0)==(expected==0),"Active component increment sign mismatch: \(c.name) \(key)")
                try require(abs(actual-expected)<=1e-3*abs(expected)+1e-30,"Active increment accuracy outside frozen diagnostic range")
            }
            try require(c.gradientWork<0 && c.activePrincipalTerms==6944,"Active source probe is not the frozen complete-source descent pair")
            activeRows.append(["case":c.name,"estimatedComponentsJ":values,"decimal100ComponentsJ":c.expectedDelta,"actualGradientWorkJ":c.gradientWork,"activePrincipalTerms":c.activePrincipalTerms,"candidateAccepted":false])
        }
        let ref=[v(0),v(1),v(0,1),v(1,1)],tris:[UInt32]=[0,1,2,1,3,2],groups=[H.PanelGroup(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0,1])]
        let sm=try M.Prepared(referencePositions:ref,triangleIndices:tris),sh=try H.Prepared(referencePositions:ref,referenceTriangles:tris,panelGroups:groups),small=try E.Prepared(membrane:sm,bending:sh)
        let flat=try small.evaluate(from:ref,to:ref,material:mat,barrier:bar,bendingMaterial:bend)
        try require(flat.totalDeltaJoules==0 && flat.unchangedCoordinates,"Identical rounded endpoint changed energy")
        func shape(_ sx:Double,_ sy:Double)->[V]{ref.map{v($0.x*sx,$0.y*sy)}}
        var analytic=0
        for (x,y) in [(shape(1.05,1.06),shape(1.049,1.059)),(shape(0.94,0.95),shape(0.941,0.951)),(shape(0.95,1.05),shape(0.951,1.049)),(shape(1.03-1e-8,1),shape(1.03+1e-8,1)),(shape(0.97+1e-8,1),shape(0.97-1e-8,1)),(shape(1.05,1.05),shape(1.05001,1.04999))] {
            let d=try small.evaluate(from:x,to:y,material:mat,barrier:bar,bendingMaterial:bend)
            let a=try sm.neoHookean(positions:x,material:mat),z=try sm.neoHookean(positions:y,material:mat)
            let ba=try sm.principalBarrier(positions:x,barrier:bar),bz=try sm.principalBarrier(positions:y,barrier:bar)
            let expected=(z.energyJoules-a.energyJoules)+(bz.energyJoules-ba.energyJoules)
            try require(abs(expected-d.totalDeltaJoules)<1e-11,"Finite nonstationary analytic energy identity")
            analytic+=1
        }
        // No general sign claim is made near an already stationary state.
        let repeated=try small.evaluate(from:shape(0.95,0.95),to:shape(0.95.nextUp,0.95.nextDown),material:mat,barrier:bar,bendingMaterial:bend)
        try require(repeated.totalDeltaJoules>0,"Repeated-stretch second-order ascent sign")
        // Frozen near-rigid pressure counterexample: g-infinity ~5e-14 N,
        // already below the consumer KKT stop. Detect severe cancellation.
        let stationary=[v(0.7,-1.1,2.3),v(1.0554482154728757,-2.034695975233203,2.3),v(1.6346959752332029,-0.7445517845271242,2.3),v(1.9901441907060786,-1.679247759760327,2.3)]
        var stationaryCandidate=stationary;stationaryCandidate[2].y = -0.7445517845271243
        try unknown{_ = try small.evaluate(from:stationary,to:stationaryCandidate,material:mat,barrier:bar,bendingMaterial:bend)}
        var rejectCount=0
        func bad(_ f:()throws->Void)throws{try invalid(f);rejectCount+=1}
        try bad{_ = try small.evaluate(from:ref,to:Array(ref.dropLast()),material:mat,barrier:bar,bendingMaterial:bend)}
        try bad{var x=ref;x[0].x = .nan;_ = try small.evaluate(from:ref,to:x,material:mat,barrier:bar,bendingMaterial:bend)}
        try bad{_ = try small.evaluate(from:shape(1.06,1),to:shape(1.07.nextUp,1),material:mat,barrier:bar,bendingMaterial:bend)}
        try bad{_ = try small.evaluate(from:shape(0.94,1),to:shape(0.93.nextDown,1),material:mat,barrier:bar,bendingMaterial:bend)}
        try bad{_ = try small.evaluate(from:ref,to:ref,material:mat)}
        try bad{var l=E.Limits();l.maximumVertices=3;_ = try E.Prepared(membrane:sm,bending:sh,limits:l)}
        try bad{var l=E.Limits();l.maximumTriangles=1;_ = try E.Prepared(membrane:sm,bending:sh,limits:l)}
        try bad{var l=E.Limits();l.maximumHinges=4947;_ = try E.Prepared(membrane:m,bending:h,limits:l)}
        let otherH=try H.Prepared(referencePositions:ref.map{$0*1.01},referenceTriangles:tris,panelGroups:groups)
        try bad{_ = try E.Prepared(membrane:sm,bending:otherH)}
        func folded(_ angle:Double)->[V]{let origin=ref[1],axis=v(-1,1)/sqrt(2),q=ref[3]-origin;var x=ref;x[3]=origin+q*cos(angle)+axis.cross(q)*sin(angle)+axis*(dot(axis,q)*(1-cos(angle)));return x}
        try bad{_ = try small.evaluate(from:folded(Double.pi-0.01),to:folded(-Double.pi+0.01),material:mat,barrier:bar,bendingMaterial:bend)}
        try bad{_ = try small.evaluate(from:ref,to:folded(Double.pi-5e-7),material:mat,barrier:bar,bendingMaterial:bend)}
        var tiny=ref;tiny[0].z=Double.leastNonzeroMagnitude
        try unknown{_ = try small.evaluate(from:ref,to:tiny,material:mat,barrier:bar,bendingMaterial:bend)}
        try cancelled{_ = try E.Prepared(membrane:m,bending:h,isCancelled:{true})}
        let constructionCancel=Counter(5)
        try cancelled{_ = try E.Prepared(membrane:m,bending:h,isCancelled:{constructionCancel.cancelled()})}
        let evaluationCancel=Counter(20)
        try cancelled{_ = try all.evaluate(from:controls.activeCases[0].base,to:controls.activeCases[0].candidate,material:mat,barrier:bar,bendingMaterial:bend,isCancelled:{evaluationCancel.cancelled()})}
        let hingeCancel=Counter(50)
        try cancelled{_ = try all.evaluate(from:controls.activeCases[0].base,to:controls.activeCases[0].candidate,material:mat,barrier:bar,bendingMaterial:bend,isCancelled:{hingeCancel.cancelled()})}
        let report:[String:Any]=["status":"pass","scope":"Elastic Double increment estimates only, no simulation or accepted update","newtonControls":rows,"activeControls":activeRows,"analyticCases":analytic,"invalidChecks":rejectCount,"explicitUnresolvedChecks":2,"cancellationChecks":4,"sourceTriangles":3472,"sourceHinges":4948,"noEnergyAcceptanceToleranceAdded":true,"noCertifiedOnlineErrorBoundClaimed":true]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("elastic-energy-delta-summary.json"))
        print("PASS elastic energy delta: 25 captured Newton + 4 complete-source active, analytic/domain/pi/unknown/budget/cancel")
    }
}
