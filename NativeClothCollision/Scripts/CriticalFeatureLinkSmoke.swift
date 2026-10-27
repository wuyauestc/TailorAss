import NativeClothCollision
@main struct CriticalFeatureSmoke {
 static func main() {
  typealias V=SIMD3<Double>
  let start=[V(Double(bitPattern:0x3fc3b7d065a2f7e7),Double(bitPattern:0xbfa9286e63106c48),Double(bitPattern:0xbfa4dd65299922b1)),V(Double(bitPattern:0x3fc403d014ed752e),Double(bitPattern:0xbfa9290b448eb77a),Double(bitPattern:0xbfa1cb152d621c34)),V(Double(bitPattern:0x3fc47e46ccc31982),Double(bitPattern:0xbfa9af3c972111f2),Double(bitPattern:0xbf90bf68361f2835)),V(Double(bitPattern:0x3fc3c7a958896544),Double(bitPattern:0xbfa9073bc0934318),Double(bitPattern:0xbfa54a131bbf7279))]
  let end=[V(Double(bitPattern:0x3fc3bffa46ce820f),Double(bitPattern:0xbfa928195c7f17c6),Double(bitPattern:0xbfa4efea8816e4da)),V(Double(bitPattern:0x3fc40be705672d50),Double(bitPattern:0xbfa91a9bd03aad66),Double(bitPattern:0xbfa1dd4b13bc550d)),V(Double(bitPattern:0x3fc482147d908acd),Double(bitPattern:0xbfa9b5eac275e33d),Double(bitPattern:0xbf90cd164dc8f5e5)),V(Double(bitPattern:0x3fc3c5703a8337c6),Double(bitPattern:0xbfa910615ab62f42),Double(bitPattern:0xbfa54739451a50e8))]
  var limits=FeatureSeparationCertificate.Limits();limits.recordLeafCertificates=true;limits.maximumDepth=0
  let r=FeatureSeparationCertificate.certify(kind:.edgeEdge,start:start,end:end,minimumSeparation:0,limits:limits)
  precondition(r.distanceSeparatedForWholeMotion && r.criticalIntervalsCertified==1 && r.processedNodes==1)
  let c=r.criticalCertificates[0]
  precondition(c.proofKind == .positiveCubicMinimum && c.distanceLowerBoundMeters>0 && c.projectionScale==3)
  print(r.expansionOperations,r.maximumExpansionWords,FloatingPointEnvironment.isNearestRounding)
 }
}
