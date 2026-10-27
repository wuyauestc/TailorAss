import NativeClothCollision
@main struct ElevatedFeatureSmoke {
    static func main() {
        typealias V=SIMD3<Double>
        let start=[V(Double(bitPattern:0x3fc3b7d065a2f7e7),Double(bitPattern:0xbfa9286e63106c48),Double(bitPattern:0xbfa4dd65299922b1)),V(Double(bitPattern:0x3fc403d014ed752e),Double(bitPattern:0xbfa9290b448eb77a),Double(bitPattern:0xbfa1cb152d621c34)),V(Double(bitPattern:0x3fc47e46ccc31982),Double(bitPattern:0xbfa9af3c972111f2),Double(bitPattern:0xbf90bf68361f2835)),V(Double(bitPattern:0x3fc3c7a958896544),Double(bitPattern:0xbfa9073bc0934318),Double(bitPattern:0xbfa54a131bbf7279))]
        let end=[V(Double(bitPattern:0x3fc3bffa46ce7ca4),Double(bitPattern:0xbfa928195c7f1ce2),Double(bitPattern:0xbfa4efea8816e53d)),V(Double(bitPattern:0x3fc40be7056720a2),Double(bitPattern:0xbfa91a9bd03ae998),Double(bitPattern:0xbfa1dd4b13bc485d)),V(Double(bitPattern:0x3fc482147d9089b9),Double(bitPattern:0xbfa9b5eac275e529),Double(bitPattern:0xbf90cd164dc8e9e6)),V(Double(bitPattern:0x3fc3c5703a8339d9),Double(bitPattern:0xbfa910615ab63828),Double(bitPattern:0xbfa54739451a534d))]
        var limits=FeatureSeparationCertificate.Limits();limits.recordLeafCertificates=true
        let r=FeatureSeparationCertificate.certify(kind:.edgeEdge,start:start,end:end,minimumSeparation:1e-16,limits:limits)
        precondition(r.distanceSeparatedForWholeMotion && r.expansionCertificates.contains{$0.projectionDegree>3})
        for c in r.expansionCertificates {
            precondition((3...8).contains(c.projectionDegree) && c.scaledProjectionBernsteinBounds.count==c.projectionDegree+1)
        }
        print(r.expansionOperations,r.maximumExpansionWords,FloatingPointEnvironment.isNearestRounding)
    }
}
