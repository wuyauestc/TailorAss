import NativeClothCollision

@main struct ClothPotentialLinkSmoke {
    static func main()throws {
        typealias V=SIMD3<Double>
        let rest=[V(0,0,0),V(0.02,0,0),V(0,0.02,0),V(-0.012,-0.004,0),V(-0.004,-0.012,0)]
        let current=[V(0,0,0),V(0.02,0,0),V(0,0.02,0),V(0.012,0.004,0.0002),V(0.004,0.012,0.0003)]
        let p=try ClothContactPotential.Prepared(restPositions:rest,triangleIndices:[0,1,2,0,3,4])
        let e=try p.evaluate(positions:current,parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.0005))
        let hv=try e.hessianProduct(direction:Array(repeating:V(0,0,1),count:5))
        guard FloatingPointEnvironment.isNearestRounding,e.statistics.faceVertexStencils==2,e.energyJoules>0,hv.count==5 else {fatalError("all-moving self force static link control")}
    }
}
