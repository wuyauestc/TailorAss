import NativeClothCollision
@main struct SelfGuardLinkSmoke {
    static func main()throws {
        typealias V=SIMD3<Double>
        let a=[V(0,0,0),V(0.02,0,0),V(0,0.02,0),V(0.012,0.004,0.001),V(0.004,0.012,0.001)]
        var b=a;b[3].z = -0.001;b[4].z = -0.001
        let p=try SelfContactGuard.Prepared(vertexCount:5,triangleIndices:[0,1,2,0,3,4])
        // This analytic initial pair is independently nonintersecting; shared
        // vertex0 never excludes its opposite/nonshared VF primitives.
        let q=p.guardMotion(previous:a,candidate:b)
        guard q.status == .limited,q.safeTime>0,q.safeTime<0.5,
              q.statistics.completedAllFeatures,q.statistics.completedDomainCertificates,
              q.requiresIntersectionFreeInitialState else {fatalError("self whole-path static link")}
    }
}
