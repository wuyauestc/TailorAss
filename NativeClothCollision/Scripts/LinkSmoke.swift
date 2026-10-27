import NativeClothCollision

@main struct NativeLinkSmoke {
    static func main() {
        let a = [0.0,0,1, -1,-1,0, 1,-1,0, 0,1,0]
        let b = [0.0,0,-1, -1,-1,0, 1,-1,0, 0,1,0]
        let r = NativeClothCollision.vertexFace(start: a, end: b)
        precondition(r.status == .conservativeHit)
        precondition(abs(r.conservativeTimeOfImpact - 0.5) < 1e-7)
        let body = [SIMD3<Double>(-1,-1,0),SIMD3<Double>(1,-1,0),SIMD3<Double>(0,1,0)]
        let cloth = [SIMD3<Double>(-0.1,-0.1,1),SIMD3<Double>(0.1,-0.1,1),SIMD3<Double>(0,0.1,1)]
        let prepared = try! ContinuousBodyContact.Prepared(bodyPositions: body, triangleIndices: [0,1,2])
        let guarded = prepared.guardMotion(previous: cloth, candidate: cloth.map { $0 + SIMD3<Double>(0,0,-2) }, clothTriangleIndices: [0,1,2])
        precondition(guarded.status == .limited && guarded.safeTime > 0 && guarded.safeTime < 0.5)
        print("NativeClothCollision + body guard Swift/C++ static link smoke passed")
    }
}
