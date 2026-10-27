import NativeClothCollision
@main struct ExpansionFeatureSmoke {
    static func main() {
        typealias V=SIMD3<Double>
        let start=[V(Double(bitPattern:0x3fc3b7d065a2f7e9),Double(bitPattern:0xbfa9286e63106c47),Double(bitPattern:0xbfa4dd6529992290)),V(Double(bitPattern:0x3fc403d014ed752f),Double(bitPattern:0xbfa9290b448eb77e),Double(bitPattern:0xbfa1cb152d621c11)),V(Double(bitPattern:0x3fc47e46ccc31981),Double(bitPattern:0xbfa9af3c972111fc),Double(bitPattern:0xbf90bf68361f27f3)),V(Double(bitPattern:0x3fc3c7a958896548),Double(bitPattern:0xbfa9073bc0934316),Double(bitPattern:0xbfa54a131bbf725a))]
        let end=[V(Double(bitPattern:0x3fc3bffa46ce7c6c),Double(bitPattern:0xbfa928195c7f1d02),Double(bitPattern:0xbfa4efea8816e4d2)),V(Double(bitPattern:0x3fc40be705671ff8),Double(bitPattern:0xbfa91a9bd03aede5),Double(bitPattern:0xbfa1dd4b13bc4729)),V(Double(bitPattern:0x3fc482147d9089a5),Double(bitPattern:0xbfa9b5eac275e58c),Double(bitPattern:0xbf90cd164dc8e8f7)),V(Double(bitPattern:0x3fc3c5703a833a09),Double(bitPattern:0xbfa910615ab63900),Double(bitPattern:0xbfa54739451a5384))]
        var limits=FeatureSeparationCertificate.Limits();limits.recordLeafCertificates=true
        let r=FeatureSeparationCertificate.certify(kind:.edgeEdge,start:start,end:end,minimumSeparation:1e-16,limits:limits)
        precondition(r.distanceSeparatedForWholeMotion && r.expansionIntervalsCertified>0)
        let c=r.expansionCertificates[0]
        precondition((3...8).contains(c.projectionDegree) && c.scaledProjectionBernsteinBounds.count==c.projectionDegree+1)
        print(c.absoluteScaledProjectionLowerBound,r.expansionOperations,r.maximumExpansionWords,
            FloatingPointEnvironment.isNearestRounding)
    }
}
