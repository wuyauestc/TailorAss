import NativeClothCollision

@main struct BodyPotentialLinkSmoke {
    static func main()throws {
        typealias V=SIMD3<Double>
        let cloth=[V(-0.02,-0.01,0.0013),V(0.02,-0.01,0.0013),V(0,0.025,0.0013)]
        let vertices=[V(-0.02,0.01,0),V(0.02,0.01,0),V(0,-0.025,0)]
        let indices:[UInt32]=[0,1,2]
        let body=try ContinuousBodyContact.Prepared(bodyPositions:vertices,triangleIndices:indices)
        let potential=try BodyContactPotential.Prepared(clothRestPositions:cloth,clothTriangleIndices:indices,body:body)
        let result=try potential.evaluate(clothPositions:cloth,parameters:.init(stiffnessPascals:35,minimumDistanceMeters:0.0005,activationGapMeters:0.002))
        let hv=try result.hessianProduct(direction:Array(repeating:V(0,0,1),count:3))
        let path=body.guardMotion(previous:cloth,candidate:cloth,clothTriangleIndices:indices)
        guard result.statistics.edgeEdgeStencils>0,result.statistics.clothVertexBodyFaceStencils==0,
              result.energyJoules.isFinite,hv.count==3,path.permitsWholeCandidate else {fatalError("Static linked body potential control failed")}
    }
}
