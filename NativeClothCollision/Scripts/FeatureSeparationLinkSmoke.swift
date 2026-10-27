import NativeClothCollision
@main struct FeatureSeparationLinkSmoke {
    static func main()throws {
        typealias V=SIMD3<Double>
        let body=[V(1,-1,0),V(0,1,-1),V(-1,0,1)],point=V(0.0004,0.0004,0.0004)
        let feature=[point]+body
        let certificate=FeatureSeparationCertificate.certify(kind:.vertexFace,start:feature,end:feature,minimumSeparation:0.0005)
        guard FloatingPointEnvironment.isNearestRounding,certificate.distanceSeparatedForWholeMotion,
              certificate.requiresIndependentPrimitiveDomainCertificate,certificate.motionSHA256.count==64,
              (certificate.minimumCertifiedDistanceLowerBoundMeters ?? 0)>0.0005 else {fatalError("Euclidean supporting separation client")}
        // Exact first original actual-circle247-vf witness. Build the same
        // nondegenerate lifted triangle as the permanent integration test.
        let start=V(0.13118351594076577,-0.0935980970882334,-0.10726168532825801)
        let end=V(0.13113284716532334,-0.09367060274768545,-0.10699681519260612)
        let actualBody=[V(0.11877559999999998,-0.0778093,-0.09969539999999999),
                        V(0.14088669999999998,-0.096304,-0.10330649999999998),
                        V(0.12187939999999998,-0.096565,-0.11272339999999999)]
        func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
        func cross(_ a:V,_ b:V)->V {V(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)}
        func unit(_ a:V)->V {a/dot(a,a).squareRoot()}
        var n=unit(cross(actualBody[1]-actualBody[0],actualBody[2]-actualBody[0]))
        if dot(n,start-actualBody[0])<0 {n = -n}
        let u=unit(actualBody[1]-actualBody[0]),v=cross(n,u)
        let offsets=[V.zero,u*0.003+n*0.01,v*0.003+n*0.01]
        let previous=offsets.map{start+$0},candidate=offsets.map{end+$0}
        let prepared=try ContinuousBodyContact.Prepared(bodyPositions:actualBody,triangleIndices:[0,1,2])
        let report=prepared.guardMotion(previous:previous,candidate:candidate,clothTriangleIndices:[0,1,2],
            options:.init(minimumSeparation:0.0005,distanceTolerance:1e-8,maximumIterationsPerFeature:10_000))
        guard report.permitsWholeCandidate,report.statistics.completedAllFeatures,
              report.statistics.nativeQueries==15,
              report.statistics.euclideanCertificateAttempts>0,
              report.statistics.euclideanCertifiedFeatures>0 else {fatalError("complete CBC Euclidean certificate client")}

    }
}
