import Foundation

/// Source-aware padding is independent of strict face-intersection contact.
/// All dimensions are metres; source panels retain independent particle IDs.
@main
@MainActor
struct SewnProximityRibbonRegression {
    typealias C=GarmentCodeClothContact
    typealias V=C.Vector3
    enum Failure:Error {case check(String)}
    static var checks:[String]=[]
    static var metrics:[String:Double]=[:]
    static func v(_ x:Double,_ y:Double,_ z:Double=0)->V{.init(x:x,y:y,z:z)}
    static func require(_ value:@autoclosure()->Bool,_ message:String)throws{
        guard value() else {throw Failure.check(message)}
    }
    static func passed(_ message:String){checks.append(message);print("PASS \(message)")}
    static func point(_ id:Int)->C.BoundaryPoint{.init(vertexIDs:[id],weights:[1])}
    static func rule(_ a:Int,_ b:Int,_ a0:Int,_ a1:Int,_ b0:Int,_ b1:Int)->C.SewnBoundaryContact{
        .init(firstTriangle:a,secondTriangle:b,firstStart:point(a0),firstEnd:point(a1),secondStart:point(b0),secondEnd:point(b1))
    }
    struct Fixture {
        let source:[V],indices:[UInt32],contact:C.SewnBoundaryContact
        func topology(reference:Bool=true,radius:Double=0.0055,budget:Int=250_000)throws->C.Topology{
            try .init(vertexCount:source.count,triangleIndices:indices,sewnBoundaryContacts:[contact],
                referencePositions:reference ? source:nil,sourceRibbonRadiusMeters:radius,maximumSourceRibbonPairs:budget)
        }
    }
    /// Three actual 2-mm source layers on both sides of a 40-mm seam.
    /// Faces 2...5 and 8...11 contain neither original seam endpoint.
    static func layered()->Fixture{
        var source:[V]=[],indices:[UInt32]=[]
        for side in [-1.0,1.0] {
            let offset=source.count
            for col in 0...3 {source += [v(side*Double(col)*0.002,0),v(side*Double(col)*0.002,0.04)]}
            for col in 0..<3 {
                let a=UInt32(offset+col*2)
                indices += [a,a+2,a+1,a+2,a+3,a+1]
            }
        }
        return .init(source:source,indices:indices,contact:rule(0,6,0,1,8,9))
    }
    /// A 3-layer boundary fan isolates inter-panel padding in a full project()
    /// call: same-panel faces share the actual interior fan vertex, so their
    /// adjacency exclusions do not introduce unrelated thin-mesh contacts.
    static func fan()->Fixture{
        let half=[v(0,0),v(0,0.04),v(0.002,0.04),v(0.004,0.04),v(0.006,0.04),
                  v(0.006,0),v(0.004,0),v(0.002,0),v(0.004,0.02)]
        let local:[UInt32]=[0,1,8,1,2,8,2,3,8,3,4,8,4,5,8,5,6,8,6,7,8,7,0,8]
        return .init(source:half.map{v(-$0.x,$0.y)}+half,indices:local+local.map{$0+9},
                     contact:rule(0,8,0,1,9,10))
    }
    static func proximity(_ topology:C.Topology,_ positions:[V],_ a:Int,_ b:Int,_ p:V,_ q:V)->Bool{
        topology.permitsSewnProximity(firstFace:a,secondFace:b,firstPoint:p,secondPoint:q,
            positions:positions,paddingMeters:0.005)
    }
    static func quality(_ positions:[V],_ topology:C.Topology)throws->C.Quality{
        try C.inspect(positions:positions,topology:topology,thickness:0.005)
    }
    static func repair(_ positions:inout[V],_ topology:C.Topology,_ weights:[Double])throws->Int{
        let previous=positions
        for i in 0..<128 {
            _=try C.project(positions:&positions,previousPositions:previous,inverseMass:weights,topology:topology,thickness:0.005)
            if try quality(positions,topology).intersectingTrianglePairs==0{return i+1}
        }
        throw Failure.check("True source-ribbon face intersection was not repaired")
    }
    static func layeredChecks()throws{
        let fixture=layered(),topology=try fixture.topology(),legacy=try fixture.topology(reference:false)
        let positions=fixture.source,p=v(-0.003,0.01),q=v(0.001,0.01)
        try require(!topology.triangles[2].vertices.contains(0) && !topology.triangles[2].vertices.contains(1),"Second source layer fixture still has a seam vertex")
        try require(!topology.triangles[4].vertices.contains(0) && !topology.triangles[4].vertices.contains(1),"Third source layer fixture still has a seam vertex")
        try require(!proximity(legacy,positions,2,6,p,q),"Legacy fixture no longer reproduces missing inner-face ribbon")
        try require(proximity(topology,positions,2,6,p,q),"Second 2-mm source layer was repelled across its actual ordinary seam")
        try require(proximity(topology,positions,4,6,v(-0.0045,0.01),v(0,0.01)),"Third 2-mm source layer was repelled across its actual ordinary seam")
        try require(proximity(topology,positions,6,2,q,p),"Expanded proximity reversed its attachment orientation")
        try require(proximity(topology,positions,2,8,p,v(0.003,0.01)),"Both interior source faces did not get a ribbon rule")
        try require(!proximity(topology,positions,4,6,v(-0.0058,0.001),v(0,0.001)),"Source or world ribbon radius became an entire-panel mask")
        try require(!topology.permitsSewnTouch(firstFace:2,secondFace:6,firstPoint:p,secondPoint:p,positions:positions),"Expanded padding rule entered strict sewn boundaries")
        try require(!proximity(topology,positions,2,6,p,v(0,0.03)),"Expanded ribbon ignored mismatched seam parameters")
        try require(!proximity(topology,positions,2,6,v(-0.003,0.01,0.001),q),"An off-face world point fabricated a barycentric source membership")
        var collapsed=positions;collapsed[2]=collapsed[4];collapsed[3]=collapsed[4]
        try require(!proximity(topology,collapsed,2,6,collapsed[4],q),"A degenerate world face fabricated a source membership")
        let reversed=try C.Topology(vertexCount:positions.count,triangleIndices:fixture.indices,
            sewnBoundaryContacts:[rule(0,6,0,1,9,8)],referencePositions:positions)
        try require(!proximity(reversed,positions,2,6,p,q),"Oppositely ordered source correspondence was silently repaired")
        passed("Three 2-mm source layers, two-sided interior faces, reverse query, bounded radius and correspondence")

        let f=fan(),ribbon=try f.topology(),old=try f.topology(reference:false)
        var current=f.source,legacyPositions=current
        let oldStats=try C.project(positions:&legacyPositions,inverseMass:Array(repeating:1,count:current.count),topology:old,thickness:0.005)
        let newStats=try C.project(positions:&current,inverseMass:Array(repeating:1,count:current.count),topology:ribbon,thickness:0.005)
        let newQuality=try quality(current,ribbon)
        metrics["legacyFanMaximumCorrectionMeters"]=oldStats.maximumCorrectionMeters
        metrics["sourceRibbonFanMaximumCorrectionMeters"]=newStats.maximumCorrectionMeters
        try require(oldStats.maximumCorrectionMeters>0 && legacyPositions != f.source,"Full-project fan did not exercise actual legacy repulsion")
        try require(newStats.maximumCorrectionMeters==0 && current==f.source && newQuality.intersectingTrianglePairs==0,
            "Source-aware full contact sweep peeled an ordinary sewn fan apart")
        passed("Actual full contact projection preserves a sewn thin fan; legacy projection reproduces repulsion")
    }
    static func sourceMembershipChecks()throws{
        let source=[v(0,0),v(0.04,0),v(0.02,-0.04),v(0,0),v(0.04,0),v(0.02,0.04)]
        let indices:[UInt32]=[0,1,2,3,4,5]
        let topology=try C.Topology(vertexCount:6,triangleIndices:indices,sewnBoundaryContacts:[rule(0,1,0,1,3,4)],referencePositions:source)
        var folded=source;folded[5]=v(0.02,0.001)
        let original=folded
        try require(!proximity(topology,folded,1,0,folded[5],v(0.02,0)),"A source-distant vertex folded near the seam became exempt")
        _=try C.project(positions:&folded,inverseMass:[0,0,0,0,0,1],topology:topology,thickness:0.005)
        try require(folded[5] != original[5] && Array(folded.prefix(5))==Array(original.prefix(5)),"Source-distant folded material did not receive real padding correction")

        // The same boundary triangle is very large. The tested point is in
        // its interior, not a vertex: only barycentric source mapping exposes
        // that its material originated 20 mm from the true seam.
        let at=(original[3]+original[4])*0.25+original[5]*0.5
        try require(!proximity(topology,original,1,0,at,v(at.x,0)),"A large source triangle's far interior was exempted after folding")
        let near=(original[3]+original[4])*0.475+original[5]*0.05
        try require(proximity(topology,original,1,0,near,v(near.x,0)),"Barycentric source membership rejected an actual near-seam interior point")
        try require(source[5]==v(0.02,0.04),"Building or projecting contact modified original source positions")
        passed("Actual barycentric source membership retains source-distant folded vertices and large-face interiors as contact")

        let f=layered(),extra=[v(-0.004,0),v(-0.004,0.04),v(-0.002,0.02)]
        let refs=f.source+extra,extended=f.indices+[16,17,18]
        let disconnected=try C.Topology(vertexCount:refs.count,triangleIndices:extended,sewnBoundaryContacts:[f.contact],referencePositions:refs)
        try require(!proximity(disconnected,refs,12,6,v(-0.003,0.02),v(0,0.02)),"Spatially adjacent unsewn/slit bank entered a source ribbon without shared-edge connectivity")
        let unsewn=try C.Topology(vertexCount:refs.count,triangleIndices:extended,referencePositions:refs)
        try require(!proximity(unsewn,refs,2,6,v(-0.003,0.01),v(0,0.01)),"Source proximity invented a seam between unstitched panels")
        passed("Disconnected slit bank and coincident unsewn panels remain active contact surfaces")
    }
    static func crossingChecks()throws{
        let f=fan(),topology=try f.topology()
        let weights=Array(repeating:0.0,count:9)+Array(repeating:1.0,count:9)
        var coplanar=f.source
        for i in 9..<18 {coplanar[i].x = -coplanar[i].x}
        let before=try quality(coplanar,topology)
        try require(before.intersectingTrianglePairs>0,"Expanded source ribbons hid actual coplanar area overlap")
        let fixed=Array(coplanar.prefix(9)),coplanarPasses=try repair(&coplanar,topology,weights)
        let after=try quality(coplanar,topology)
        try require(after.intersectingTrianglePairs==0 && after.degenerateTriangles==0 && Array(coplanar.prefix(9))==fixed,"Coplanar ribbon repair failed or moved a pinned source panel")
        metrics["coplanarCrossingPairsBefore"]=Double(before.intersectingTrianglePairs)
        metrics["coplanarRepairPasses"]=Double(coplanarPasses)

        var interior=f.source
        for i in 9..<18 {interior[i]=v(-0.003,interior[i].y,interior[i].x-0.003)}
        let interiorBefore=try quality(interior,topology)
        try require(interiorBefore.intersectingTrianglePairs>0,"Expanded source ribbons hid actual noncoplanar interior intersections")
        try require(!topology.permitsSewnTouch(firstFace:2,secondFace:10,firstPoint:v(-0.003,0.035),
            secondPoint:v(-0.003,0.035),positions:interior),"Interior ribbon pair became a strict seam-touch exemption")
        let interiorPasses=try repair(&interior,topology,weights),interiorAfter=try quality(interior,topology)
        try require(interiorAfter.intersectingTrianglePairs==0 && interiorAfter.degenerateTriangles==0 && Array(interior.prefix(9))==Array(f.source.prefix(9)),"Interior ribbon repair failed or changed a fixed source panel")
        metrics["interiorCrossingPairsBefore"]=Double(interiorBefore.intersectingTrianglePairs)
        metrics["interiorRepairPasses"]=Double(interiorPasses)
        passed("True coplanar and noncoplanar crossings on expanded ribbon faces are detected and repaired")
    }
    nonisolated final class Counter:@unchecked Sendable{
        private let lock=NSLock()
        private var value=0
        func cancelled()->Bool{lock.lock();defer{lock.unlock()};value+=1;return value>4}
        var calls:Int{lock.lock();defer{lock.unlock()};return value}
    }
    static func validationChecks()throws{
        let f=layered()
        func invalid(_ refs:[V],radius:Double=0.0055,budget:Int=250_000)throws{
            var rejected=false
            do{_=try C.Topology(vertexCount:f.source.count,triangleIndices:f.indices,sewnBoundaryContacts:[f.contact],
                referencePositions:refs,sourceRibbonRadiusMeters:radius,maximumSourceRibbonPairs:budget)}
            catch C.ContactError.invalid{rejected=true}
            try require(rejected,"Invalid source reference/ribbon configuration was accepted")
        }
        try invalid(Array(f.source.dropLast()))
        var bad=f.source;bad[3].x = .nan;try invalid(bad)
        bad=f.source;bad[3].z=0.001;try invalid(bad)
        bad=f.source;bad[2]=bad[0];try invalid(bad)
        try invalid(f.source,radius:.nan);try invalid(f.source,radius:0.03);try invalid(f.source,budget:0)
        var budget=false
        do{_=try f.topology(budget:1)}catch C.ContactError.budgetExceeded{budget=true}
        try require(budget,"Source-ribbon pair budget silently truncated actual coverage")
        var cancelled=false
        do{_=try C.Topology(vertexCount:f.source.count,triangleIndices:f.indices,sewnBoundaryContacts:[f.contact],referencePositions:f.source,isCancelled:{true})}
        catch is CancellationError{cancelled=true}
        try require(cancelled,"Source-ribbon initialization ignored immediate cancellation")
        let counter=Counter();cancelled=false
        do{_=try C.Topology(vertexCount:f.source.count,triangleIndices:f.indices,
            sewnBoundaryContacts:Array(repeating:f.contact,count:500),referencePositions:f.source,isCancelled:{counter.cancelled()})}
        catch is CancellationError{cancelled=true}
        try require(cancelled && counter.calls>4,"Source-ribbon expansion ignored cancellation during actual work")
        var nonmanifold=false
        let p=[v(0,0),v(0.02,0),v(0,0.02),v(0,-0.02),v(0.01,0.02)]
        do{_=try C.Topology(vertexCount:5,triangleIndices:[0,1,2,1,0,3,0,1,4],referencePositions:p)}
        catch C.ContactError.invalid{nonmanifold=true}
        try require(nonmanifold,"Source nonmanifold edge was accepted as same-panel adjacency")
        var unused=false
        do{_=try C.Topology(vertexCount:4,triangleIndices:[0,1,2],referencePositions:[v(0,0),v(0.02,0),v(0,0.02),v(1,1)])}
        catch C.ContactError.invalid{unused=true}
        try require(unused,"Unreferenced source particle was accepted into source ownership")
        passed("Invalid references, nonmanifold ownership, budgets and immediate/mid-expansion cancellation fail explicitly")

        // Optional source arguments are inert on the nil path. Old callers
        // retain exactly the old face-pair classification and projection.
        let old=try f.topology(reference:false)
        let nilWithUnusedArguments=try C.Topology(vertexCount:f.source.count,triangleIndices:f.indices,sewnBoundaryContacts:[f.contact],
            referencePositions:nil,sourceRibbonRadiusMeters:.nan,maximumSourceRibbonPairs:0,isCancelled:{true})
        var a=f.source,b=f.source
        let sa=try C.project(positions:&a,inverseMass:Array(repeating:1,count:a.count),topology:old,thickness:0.005)
        let sb=try C.project(positions:&b,inverseMass:Array(repeating:1,count:b.count),topology:nilWithUnusedArguments,thickness:0.005)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let statsA=try encoder.encode(sa),statsB=try encoder.encode(sb)
        let qa=try encoder.encode(quality(a,old)),qb=try encoder.encode(quality(b,nilWithUnusedArguments))
        try require(a==b && statsA==statsB && qa==qb,"Nil source reference changed legacy numerical bytes")
        passed("Nil source reference preserves legacy projected coordinates and sorted JSON statistics/quality bytes")
    }
    static func main()throws{
        try layeredChecks();try sourceMembershipChecks();try crossingChecks();try validationChecks()
        let result:[String:Any]=["kind":"sewn_source_proximity_ribbon_regression","passed":true,
            "sourceRibbonRadiusMeters":0.0055,"clothPaddingMeters":0.005,
            "strictIntersectionRulesExpanded":false,"checks":checks,"metrics":metrics]
        let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        if let path=ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_PROXIMITY_OUTPUT"]{
            try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
            try data.write(to:URL(fileURLWithPath:path).appendingPathComponent("sewn-proximity-summary.json"))
        }
        print(String(decoding:data,as:UTF8.self))
    }
}
