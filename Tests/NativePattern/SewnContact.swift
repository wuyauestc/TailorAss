import Foundation

/// A sewn boundary can touch without becoming a whole-face collision mask.
/// Every adversarial crossing below uses the very same declared face pair.
@main
@MainActor
struct SewnContactRegression {
    typealias C=GarmentCodeClothContact
    typealias S=GarmentCodeSewing
    typealias V=C.Vector3
    enum Failure:Error {case check(String)}
    static func v(_ x:Double,_ y:Double,_ z:Double=0)->V {.init(x:x,y:y,z:z)}
    static func require(_ value:@autoclosure()->Bool,_ text:String)throws {if !value(){throw Failure.check(text)}}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func point(_ id:Int)->C.BoundaryPoint {.init(vertexIDs:[id],weights:[1])}
    static func rule(_ a:Int,_ b:Int,_ a0:C.BoundaryPoint,_ a1:C.BoundaryPoint,_ b0:C.BoundaryPoint,_ b1:C.BoundaryPoint)->C.SewnBoundaryContact {
        .init(firstTriangle:a,secondTriangle:b,firstStart:a0,firstEnd:a1,secondStart:b0,secondEnd:b1)
    }
    static func inspect(_ positions:[V],_ topology:C.Topology)throws->C.Quality {
        try C.inspect(positions:positions,topology:topology,thickness:0.005)
    }
    static func repair(_ positions:inout[V],_ topology:C.Topology,_ weights:[Double],passes:Int=64)throws {
        let original=positions
        for _ in 0..<passes {
            _=try C.project(positions:&positions,previousPositions:original,inverseMass:weights,topology:topology,thickness:0.005)
            if try inspect(positions,topology).intersectingTrianglePairs==0 {return}
        }
    }
    static func syntheticChecks()throws {
        let indices:[UInt32]=[0,1,2,3,5,4]
        let seam=rule(0,1,point(0),point(1),point(3),point(4))
        let topology=try C.Topology(vertexCount:6,triangleIndices:indices,sewnBoundaryContacts:[seam])
        let plain=try C.Topology(vertexCount:6,triangleIndices:indices)
        let closed=[v(0,0),v(0.12,0),v(0.06,0.12),v(0,0),v(0.12,0),v(0.06,-0.12)]
        let plainQuality=try inspect(closed,plain),closedQuality=try inspect(closed,topology)
        log("ordinary closed edge: plain_cross=\(plainQuality.intersectingTrianglePairs), sewn_cross=\(closedQuality.intersectingTrianglePairs), plain_close=\(plainQuality.closeSurfacePairs), sewn_close=\(closedQuality.closeSurfacePairs)")
        try require(plainQuality.closeSurfacePairs>0 && closedQuality.closeSurfacePairs==0 && closedQuality.intersectingTrianglePairs==0,"Only the explicitly matched boundary proximity should be permitted")
        try require(topology.permitsSewnTouch(firstFace:0,secondFace:1,firstPoint:v(0.03,0),secondPoint:v(0.03,0),positions:closed),"Ordinary interval failed to match its interior boundary point")
        try require(!topology.permitsSewnTouch(firstFace:0,secondFace:1,firstPoint:v(0.03,0),secondPoint:v(0.08,0),positions:closed),"Different seam parameters were treated as corresponding points")
        var projected=closed
        let stats=try C.project(positions:&projected,inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.005)
        try require(projected==closed && stats.maximumCorrectionMeters==0,"Closed sewn boundary was repelled by cloth contact")
        var approaching=closed
        for i in 3..<6 {approaching[i].z=0.001}
        let approachingOriginal=approaching
        _=try C.project(positions:&approaching,inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.005)
        try require(approaching==approachingOriginal,"Corresponding boundary points were repelled before their finite sewing gap could close")

        // A valid adjacent source strip can be narrower than the numerical
        // padding. Its interior vertex is 2 mm from its matched ordinary seam;
        // proximity must not peel it away from the continuous cloth surface.
        let ribbon=[v(0,0),v(0,0.04),v(-0.002,0.02),v(0,0),v(0,0.04),v(0.04,0.02)]
        var ribbonProjected=ribbon,plainRibbon=ribbon
        _=try C.project(positions:&plainRibbon,inverseMass:Array(repeating:1,count:6),topology:plain,thickness:0.005)
        try require(plainRibbon != ribbon,"Near-seam ribbon fixture did not exercise actual padding contact")
        _=try C.project(positions:&ribbonProjected,inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.005)
        try require(ribbonProjected==ribbon,"Padding peeled a valid narrow ordinary-seam strip apart")
        let ribbonQuality=try inspect(ribbonProjected,topology)
        try require(ribbonQuality.intersectingTrianglePairs==0,"Narrow seam fixture has actual face overlap")

        let wrongRule=rule(0,1,point(0),point(1),point(4),point(3))
        let wrong=try C.Topology(vertexCount:6,triangleIndices:indices,sewnBoundaryContacts:[wrongRule])
        let wrongQuality=try inspect(closed,wrong)
        try require(wrongQuality.closeSurfacePairs>0,"A reversed correspondence silently allowed an entire coincident edge")

        // The allowed full edge is still not permission for coplanar AREA
        // overlap. Lift only the free third vertex to resolve the bad fold.
        var overlap=closed;overlap[5]=v(0.06,0.05)
        let overlapBefore=try inspect(overlap,topology)
        try require(overlapBefore.intersectingTrianglePairs==1,"Declared seam hid coplanar face area overlap")
        let fixed=[overlap[0],overlap[1],overlap[2],overlap[3],overlap[4]]
        try repair(&overlap,topology,[0,0,0,0,0,1])
        let overlapAfter=try inspect(overlap,topology)
        try require(overlapAfter.intersectingTrianglePairs==0 && overlapAfter.degenerateTriangles==0 && overlap.allSatisfy(\.isFinite) && Array(overlap.prefix(5))==fixed,"Coplanar overlap was not repaired independently of its fixed sewn edge")

        // A single shared tack at the origin must not exempt the rest of a
        // line passing through both triangle interiors.
        let deepIndices:[UInt32]=[0,1,2,3,4,5]
        let tack=rule(0,1,point(0),point(0),point(3),point(3))
        let tackTopology=try C.Topology(vertexCount:6,triangleIndices:deepIndices,sewnBoundaryContacts:[tack])
        var deep=[v(0,0),v(0.12,0.12),v(0.12,-0.12),v(0,0),v(0.12,0,0.12),v(0.12,0,-0.12)]
        try require(tackTopology.permitsSewnTouch(firstFace:0,secondFace:1,firstPoint:v(0,0),secondPoint:v(0,0),positions:deep),"Exact finite tack was not recognized")
        try require(!tackTopology.permitsSewnTouch(firstFace:0,secondFace:1,firstPoint:v(0.06,0),secondPoint:v(0.06,0),positions:deep),"A finite tack became a whole-face exemption")
        let deepBefore=try inspect(deep,tackTopology)
        try require(deepBefore.intersectingTrianglePairs==1,"Deep interior crossing of the same tacked face pair was suppressed")
        let pinned=Array(deep.prefix(3))+[deep[3]]
        try repair(&deep,tackTopology,[0,0,0,0,1,1])
        let deepAfter=try inspect(deep,tackTopology)
        try require(deepAfter.intersectingTrianglePairs==0 && deepAfter.degenerateTriangles==0 && deep.allSatisfy(\.isFinite) && Array(deep.prefix(4))==pinned,"Deep tacked-face crossing was not repaired while retaining the fixed tack")
        // Put the same genuine crossing wholly inside the 5 mm padding
        // neighbourhood. A proximity exception must never hide its geometry.
        var nearTackCross=[v(0,0),v(0.12,0.12),v(0.12,-0.12),v(0,0),v(0.12,0,0.12),v(0.12,0,-0.12)].map{$0*0.02}
        let nearCrossBefore=try inspect(nearTackCross,tackTopology)
        try require(nearCrossBefore.intersectingTrianglePairs==1,"A true crossing inside the tack padding was hidden")
        try repair(&nearTackCross,tackTopology,[0,0,0,0,1,1])
        let nearCrossAfter=try inspect(nearTackCross,tackTopology)
        try require(nearCrossAfter.intersectingTrianglePairs==0 && nearCrossAfter.degenerateTriangles==0,"A true crossing inside the tack padding was not repaired")
        let midpoint=C.BoundaryPoint(vertexIDs:[0,1],weights:[0.5,0.5])
        let otherMidpoint=C.BoundaryPoint(vertexIDs:[3,4],weights:[0.5,0.5])
        let midRule=rule(0,1,midpoint,midpoint,otherMidpoint,otherMidpoint)
        let midTopology=try C.Topology(vertexCount:6,triangleIndices:deepIndices,sewnBoundaryContacts:[midRule])
        let untackedFold=[v(-0.12,0),v(0.12,0),v(0,0.12),v(0,-0.12),v(0,0.12),v(0.12,0,0.12)]
        let untacked=try inspect(untackedFold,midTopology)
        try require(untacked.intersectingTrianglePairs==1,"An interior edge tack suppressed an untacked fold intersection")

        // A point on the shared diagonal is NOT a boundary span, even though
        // both of its endpoint vertices happen to be on the outer boundary.
        let squareIndices:[UInt32]=[0,1,2,1,3,2,4,5,6]
        let interiorRule=rule(0,2,point(1),point(2),point(4),point(5))
        var rejected=false
        do {_=try C.Topology(vertexCount:7,triangleIndices:squareIndices,sewnBoundaryContacts:[interiorRule])} catch C.ContactError.invalid {rejected=true}
        try require(rejected,"Interior edge contact metadata was accepted as a sewn boundary")
        var cancelled=false,cancelPositions=closed
        do {_=try C.project(positions:&cancelPositions,inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.005,isCancelled:{true})} catch is CancellationError {cancelled=true}
        try require(cancelled && cancelPositions==closed,"Cancelled sewn contact changed a cloth state")
        var budget=false
        do {_=try C.Topology(vertexCount:6,triangleIndices:indices,sewnBoundaryContacts:Array(repeating:seam,count:40_001))} catch C.ContactError.budgetExceeded {budget=true}
        try require(budget,"Excess sewn-contact metadata was silently truncated")
        log("PASS sewn boundaries: matched touches/proximity, correspondence, coplanar overlap, deep same-pair crossing, untacked folds, interior-edge rejection, cancellation and metadata budgets")
    }

    static func mesh(_ id:String,_ positions:[V],_ triangles:[UInt32],_ boundary:[Int])->GarmentCodePanelMesher.Mesh {
        var minimum=Double.infinity,maximum=0.0
        for i in stride(from:0,to:triangles.count,by:3) {
            let ids=(0..<3).map{Int(triangles[i+$0])}
            for j in 0..<3 {
                let a=positions[ids[(j+1)%3]]-positions[ids[j]],b=positions[ids[(j+2)%3]]-positions[ids[j]]
                maximum=max(maximum,a.length)
                minimum=min(minimum,acos(max(-1,min(1,(a.x*b.x+a.y*b.y)/(a.length*b.length))))*180/Double.pi)
            }
        }
        let area=boundary.indices.reduce(0.0) {sum,i in let a=positions[boundary[i]],b=positions[boundary[(i+1)%boundary.count]];return sum+(a.x*b.y-a.y*b.x)/2}
        let paths=boundary.indices.map {i in
            let a=boundary[i],b=boundary[(i+1)%boundary.count]
            return GarmentCodePanelMesher.Boundary(edgeIndex:i,edgeID:"\(id)-e\(i)",vertexIDs:[a,b],sourceParameters:[0,1],arcFractions:[0,1],sourceLengthMeters:(positions[a]-positions[b]).length)
        }
        return .init(panelID:id,flatPositions:positions,triangleIndices:triangles,boundaries:paths,sourceClockwise:false,
                     sourceSignedAreaSquareMeters:area,flattenedAreaSquareMeters:area,maximumBoundaryDeviationMeters:0,
                     arcLengthIntegrationToleranceMeters:1e-10,quality:.init(minimumAngleDegrees:minimum,maximumEdgeMeters:maximum,triangleCount:triangles.count/3,vertexCount:positions.count))
    }
    static func cornerFanBridge()throws {
        let a=mesh("fan",[v(0,0),v(0.12,0),v(0.12,0.12),v(0,0.12),v(0.08,0.03),v(0.03,0.08)],
                   [0,1,4,0,4,5,0,5,3,1,2,4,2,5,4,2,3,5],[0,1,2,3])
        let b=mesh("other",[v(0,0),v(0.12,0),v(0,0.12)],[0,1,2],[0,1,2])
        let bindings=[try S.PanelBinding(mesh:a,vertexOffset:0,triangleOffset:0),try S.PanelBinding(mesh:b,vertexOffset:6,triangleOffset:6)]
        let positions=a.flatPositions+b.flatPositions.map{v(-$0.x/sqrt(2),-$0.y,$0.x/sqrt(2))}
        let indices=a.triangleIndices+b.triangleIndices.map{$0+6}
        let ak=S.EdgeKey(panelID:"fan",edgeIndex:0),bk=S.EdgeKey(panelID:"other",edgeIndex:0),hash=String(repeating:"1",count:64)
        let plan=try S.build(bindings:bindings,positions:positions,sourceStitches:[.init(a:ak,b:bk,rightWrong:false)],actualSourceSHA256:hash,
                             assembly:.init(sourceSHA256:hash,hints:[.init(stitchIndex:0,seamID:"fan-corner",a:ak,b:bk,aDirection:.forward,bDirection:.forward,rightWrong:false,intent:.ordinary)]))
        let topology=try GarmentCodeSewnDrape.contactTopology(vertexCount:positions.count,triangleIndices:indices,plan:plan)
        // Face 1 has only interior edges, but its vertex 0 is a genuine global
        // boundary corner. The planner must cover this incident fan face too.
        try require(topology.permitsSewnTouch(firstFace:1,secondFace:6,firstPoint:v(0,0),secondPoint:v(0,0),positions:positions),"A boundary corner's interior fan face lost its finite tack")
        let quality=try inspect(positions,topology)
        try require(quality.intersectingTrianglePairs==0,"A valid corner-only sewn touch was reported as a crossing on a fan face")
        let bad=rule(1,6,point(4),point(4),point(6),point(6))
        var rejected=false
        do {_=try C.Topology(vertexCount:positions.count,triangleIndices:indices,sewnBoundaryContacts:[bad])} catch C.ContactError.invalid {rejected=true}
        try require(rejected,"A true interior mesh vertex was accepted as a boundary-corner tack")
        log("PASS corner fan: actual sewing-plan bridge covers every incident face at a real boundary vertex, while interior vertex metadata is rejected")
    }
    static func fourPanelJunction()throws {
        let source=(0..<4).map {i in mesh("joint\(i)",[v(0,0),v(0.1,0),v(0,0.1)],[0,1,2],[0,1,2])}
        let d=0.1/sqrt(2)
        let world:[[V]]=[
            [v(0,0),v(d,d),v(d,-d)],
            [v(0,0),v(-d,d),v(-d,-d)],
            [v(0,0),v(d,0,d),v(-d,0,d)],
            [v(0,0),v(d,0,-d),v(-d,0,-d)]
        ]
        var bindings:[S.PanelBinding]=[],indices:[UInt32]=[]
        for i in 0..<4 {
            bindings.append(try .init(mesh:source[i],vertexOffset:i*3,triangleOffset:i))
            indices += source[i].triangleIndices.map {$0+UInt32(i*3)}
        }
        let positions=world.flatMap {$0},hash=String(repeating:"2",count:64)
        var stitches:[S.SourceStitch]=[],hints:[S.StitchHint]=[]
        for i in 0..<4 {
            let a=S.EdgeKey(panelID:"joint\(i)",edgeIndex:0),b=S.EdgeKey(panelID:"joint\((i+1)%4)",edgeIndex:2)
            stitches.append(.init(a:a,b:b,rightWrong:false))
            hints.append(.init(stitchIndex:i,seamID:"junction-\(i)",a:a,b:b,aDirection:.forward,
                               bDirection:.reverse,rightWrong:false,intent:.ordinary))
        }
        let plan=try S.build(bindings:bindings,positions:positions,sourceStitches:stitches,
            actualSourceSHA256:hash,assembly:.init(sourceSHA256:hash,hints:hints))
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try encoder.encode(plan)
        let topology=try GarmentCodeSewnDrape.contactTopology(vertexCount:12,triangleIndices:indices,plan:plan)
        try require(topology.vertexCount==12,"Junction closure merged independent source particles")
        try require(topology.permitsSewnTouch(firstFace:0,secondFace:2,firstPoint:v(0,0),secondPoint:v(0,0),positions:positions) &&
            topology.permitsSewnTouch(firstFace:1,secondFace:3,firstPoint:v(0,0),secondPoint:v(0,0),positions:positions),
            "A real four-panel sewn corner omitted its transitive contact pairs")
        var projected=positions
        let stats=try C.project(positions:&projected,inverseMass:Array(repeating:1,count:12),topology:topology,thickness:0.005)
        try require(projected==positions && stats.maximumCorrectionMeters==0,
                    "Contact peeled a valid four-panel corner apart")
        var crossing=positions
        crossing[7]=v(d,d,0.05);crossing[8]=v(d,-d,-0.05)
        let interior=v(d/2,0)
        try require(!topology.permitsSewnTouch(firstFace:0,secondFace:2,firstPoint:interior,secondPoint:interior,positions:crossing),
                    "Transitive corner closure became an entire-face crossing exemption")
        let crossed=try inspect(crossing,topology)
        try require(crossed.intersectingTrianglePairs>0,"Actual interior crossing between transitive corner faces was hidden")
        var weights=Array(repeating:0.0,count:12);weights[7]=1;weights[8]=1
        try repair(&crossing,topology,weights)
        let repaired=try inspect(crossing,topology)
        try require(repaired.intersectingTrianglePairs==0 && repaired.degenerateTriangles==0,
                    "Actual crossing at a transitive junction was not repaired")
        let after=try encoder.encode(plan)
        try require(before==after,"Contact junction closure modified original sewing constraints or source provenance")
        // A nearby but unstitched panel does not enter the source-corner graph.
        let extra=mesh("unstitched",[v(0,0),v(0.1,0),v(0,0.1)],[0,1,2],[0,1,2])
        let extendedBindings=bindings+[try S.PanelBinding(mesh:extra,vertexOffset:12,triangleOffset:4)]
        let extendedPositions=positions+[v(0,0),v(0.1,0),v(0,0.1)]
        let extendedPlan=try S.build(bindings:extendedBindings,positions:extendedPositions,sourceStitches:stitches,
            actualSourceSHA256:hash,assembly:.init(sourceSHA256:hash,hints:hints))
        let extended=try GarmentCodeSewnDrape.contactTopology(vertexCount:15,
            triangleIndices:indices+[12,13,14],plan:extendedPlan)
        try require(!extended.permitsSewnTouch(firstFace:0,secondFace:4,firstPoint:v(0,0),secondPoint:v(0,0),positions:extendedPositions),
                    "A coincident unstitched point was added to the sewing equivalence graph")
        log("PASS four-panel junction: real source endpoint closure, unchanged DOFs/plan, no padding repulsion; interior and unstitched contacts remain active")
    }
    static func main()throws {
        try syntheticChecks();try cornerFanBridge();try fourPanelJunction()
        print("PASS: sewn boundary contact permits only matching boundaries and finite tacks; real interior intersections remain active")
    }
}
