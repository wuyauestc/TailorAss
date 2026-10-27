import Foundation

@main
struct ClothContactRegression {
    typealias Contact = GarmentCodeClothContact
    typealias V = Contact.Vector3
    enum Failure: Error { case check(String) }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.check(message) }
    }
    static func v(_ x: Double, _ y: Double, _ z: Double) -> V { .init(x:x,y:y,z:z) }

    static func main() throws {
        let topology=try Contact.Topology(vertexCount:6,triangleIndices:[0,1,2,3,4,5])
        // One edge goes through a face interior, although every vertex pair is
        // far apart. The former 5 mm vertex-only contact cannot see this.
        var crossing=[v(-0.4,-0.4,0),v(0.4,-0.4,0),v(0,0.4,0),
                      v(0,-0.15,-0.25),v(0,-0.15,0.25),v(0,0.3,0.2)]
        let original=crossing
        let minVertexDistance=(0..<3).flatMap { a in (3..<6).map { b in (crossing[a]-crossing[b]).length } }.min()!
        try require(minVertexDistance > 0.15,"Adversarial surface crossing must evade old vertex contacts")
        let before=try Contact.inspect(positions:crossing,topology:topology,thickness:0.005)
        try require(before.intersectingTrianglePairs==1,"Face-interior crossing not detected")
        var repairCount=0
        for _ in 0..<24 {
            let stats=try Contact.project(positions:&crossing,previousPositions:original,
                                          inverseMass:[0,0,0,1,1,1],topology:topology,thickness:0.005)
            repairCount += stats.crossingRepairs
        }
        let after=try Contact.inspect(positions:crossing,topology:topology,thickness:0.005)
        print("face-interior crossing: \(before.intersectingTrianglePairs) -> \(after.intersectingTrianglePairs); repairs \(repairCount)")
        try require(repairCount>0 && after.intersectingTrianglePairs==0,"Crossing correction did not separate the faces")
        try require(Array(crossing.prefix(3))==Array(original.prefix(3)),"Pinned triangle moved")
        try require(crossing.allSatisfy(\.isFinite),"Crossing projection generated non-finite data")

        // Actual legacy full-circle seam neighborhood, reduced to four faces.
        // The outer two faces cross while bridging triangles make their nodes
        // one-ring neighbors. Proximity exclusions must not hide the crossing.
        let seamTopology=try Contact.Topology(vertexCount:6,triangleIndices:[0,1,2,3,4,5,1,5,2,1,3,5])
        var seamFold=[
            v(-0.16725691056076414,-0.23276206846851855,-0.007914446607896268),
            v(-0.16359546346796125,-0.23044946434855243,-0.03160873736402228),
            v(-0.17166228361947777,-0.26623953391731203,-0.011141758570962123),
            v(-0.17202817659110461,-0.23264293042556988,-0.009404690411587972),
            v(-0.17607814039379052,-0.2659176633110149,-0.013464818678139326),
            v(-0.16142420026535936,-0.2641215869203213,-0.034911111368386004)]
        let seamBefore=try Contact.inspect(positions:seamFold,topology:seamTopology,thickness:0.005)
        try require(seamBefore.intersectingTrianglePairs==1,"Legacy welded-seam crossing fixture was not detected")
        let seamStats=try Contact.project(positions:&seamFold,inverseMass:Array(repeating:1,count:6),topology:seamTopology,thickness:0.005)
        let seamAfter=try Contact.inspect(positions:seamFold,topology:seamTopology,thickness:0.005)
        try require(seamStats.crossingRepairs>0 && seamAfter.intersectingTrianglePairs==0,"One-ring exclusions hid an actual welded-seam surface crossing")

        // Edge-edge proximity with closest points in both segment interiors.
        // All vertices remain farther apart than the contact thickness.
        var edgeFold=[v(-0.12,0,0),v(0.12,0,0),v(0.12,-0.12,0),
                      v(0,-0.12,0.002),v(0,0.12,0.002),v(-0.12,0.12,0.002)]
        let edgeOriginal=edgeFold
        let edgeBefore=try Contact.inspect(positions:edgeFold,topology:topology,thickness:0.006)
        var edges=0
        for _ in 0..<8 {
            let stats=try Contact.project(positions:&edgeFold,previousPositions:edgeOriginal,
                                          inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.006)
            edges += stats.edgeEdgeContacts
        }
        let edgeAfter=try Contact.inspect(positions:edgeFold,topology:topology,thickness:0.006)
        try require(edgeBefore.closeSurfacePairs>0 && edges>0,"Near edge-edge contact was not processed")
        try require(edgeAfter.maximumSurfaceOverlapMeters < edgeBefore.maximumSurfaceOverlapMeters,"Surface separation did not improve")

        // A normal shared-edge fold must never repel itself at its common seam.
        let adjacent=try Contact.Topology(vertexCount:4,triangleIndices:[0,1,2,1,3,2])
        var shared=[v(0,0,0),v(0.03,0,0),v(0,0.03,0),v(0.03,0.03,0)]
        let sharedBefore=shared
        let noContact=try Contact.project(positions:&shared,inverseMass:Array(repeating:1,count:4),topology:adjacent,thickness:0.005)
        try require(shared==sharedBefore && noContact.candidateTrianglePairs==0,"Adjacent triangles incorrectly collided")

        // Coincident independent faces require a finite deterministic normal.
        var coincident=[v(0,0,0),v(0.04,0,0),v(0,0.04,0),v(0,0,0),v(0.04,0,0),v(0,0.04,0)]
        let coincidentBefore=try Contact.inspect(positions:coincident,topology:topology,thickness:0.005)
        try require(coincidentBefore.intersectingTrianglePairs==1,"Coplanar coincident faces were missed")
        for _ in 0..<12 {
            _=try Contact.project(positions:&coincident,inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.005)
        }
        try require(coincident.allSatisfy(\.isFinite),"Coincident contact normal became non-finite")
        let coincidentAfter=try Contact.inspect(positions:coincident,topology:topology,thickness:0.005)
        try require(coincidentAfter.intersectingTrianglePairs==0,"Coincident faces stayed interpenetrating")

        // Degenerate triangles are handled without division by zero and are
        // disclosed separately by inspection rather than called healthy.
        var degenerate=[v(0,0,0),v(0.02,0,0),v(0.04,0,0),v(0.01,-0.02,0),v(0.01,0.02,0),v(0.01,0,0)]
        _=try Contact.project(positions:&degenerate,inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.005)
        try require(degenerate.allSatisfy(\.isFinite),"Degenerate contact generated non-finite coordinates")
        let diagnostic=try Contact.inspect(positions:original,topology:topology,thickness:0.005)
        try require(diagnostic.degenerateTriangles==0,"Valid triangles marked degenerate")

        var cancelled=false
        do { _=try Contact.project(positions:&crossing,inverseMass:Array(repeating:1,count:6),topology:topology,thickness:0.005,isCancelled:{true}) }
        catch is CancellationError { cancelled=true }
        try require(cancelled,"Cancelled contact pass returned a result")
        var invalid=false
        do { _=try Contact.Topology(vertexCount:3,triangleIndices:[0,1,9]) }
        catch { invalid=true }
        try require(invalid,"Invalid vertex reference was accepted")
        var nonfinite=original; nonfinite[0].x = .nan
        invalid=false
        do { _=try Contact.inspect(positions:nonfinite,topology:topology,thickness:0.005) }
        catch { invalid=true }
        try require(invalid,"Non-finite position was allowed into hash indexing")
        let crowdTopology=try Contact.Topology(vertexCount:9,triangleIndices:[0,1,2,3,4,5,6,7,8])
        let crowded=[v(-0.02,-0.02,0),v(0.02,-0.02,0),v(0,0.02,0),
                     v(-0.02,-0.02,0.001),v(0.02,-0.02,0.001),v(0,0.02,0.001),
                     v(-0.02,-0.02,0.002),v(0.02,-0.02,0.002),v(0,0.02,0.002)]
        var budget=false
        do { _=try Contact.inspect(positions:crowded,topology:crowdTopology,thickness:0.005,maximumCandidatePairs:1) }
        catch Contact.ContactError.budgetExceeded { budget=true }
        try require(budget,"Candidate exhaustion silently omitted contacts")
        print("PASS: surface-interior crossings, edge-edge proximity, adjacency, pinned/degenerate/coincident state, cancellation and bounded broad phase")
    }
}
