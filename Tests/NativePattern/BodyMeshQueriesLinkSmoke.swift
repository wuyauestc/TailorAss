import Foundation
@main struct BodyMeshQueriesLinkSmoke {
    static func main()throws {
        typealias Q=GarmentCodeBodyMeshQueries
        typealias V=Q.V
        let v=[V(x:-0.5,y:-0.5,z:-0.5),V(x:0.5,y:-0.5,z:-0.5),V(x:0.5,y:0.5,z:-0.5),V(x:-0.5,y:0.5,z:-0.5),
               V(x:-0.5,y:-0.5,z:0.5),V(x:0.5,y:-0.5,z:0.5),V(x:0.5,y:0.5,z:0.5),V(x:-0.5,y:0.5,z:0.5)]
        let ids:[UInt32]=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]
        let p=try Q.Prepared(positions:v,triangleIndices:ids),q=p.query(.zero)
        precondition(q.classification == .inside && q.signedDistanceMeters == -0.5)
        precondition(p.geometrySHA256=="37118e4fcffeac9e1bd954c4f4c9464ac3d584303150add3650ba75ef30c4078")
        print(q.classification.rawValue)
    }
}

