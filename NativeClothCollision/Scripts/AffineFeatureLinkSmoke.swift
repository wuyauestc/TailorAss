import NativeClothCollision
@main struct AffineFeatureSmoke {
 static func main() {
  typealias V=SIMD3<Double>
  let start=[V(Double(bitPattern:0x3fc39a4263c5a49a),Double(bitPattern:0xbfb078ed57b27abc),Double(bitPattern:0x3fa257c80b0ee15e)),V(Double(bitPattern:0x3fc306943c718869),Double(bitPattern:0xbfb0cb8aeb062bba),Double(bitPattern:0x3fa50a88021da7dc)),V(Double(bitPattern:0x3fc147a8858400c4),Double(bitPattern:0xbfb1bc03ee00590b),Double(bitPattern:0x3fad1c61cffe3422)),V(Double(bitPattern:0x3fc39a422711bb68),Double(bitPattern:0xbfb078e79cc8dbb8),Double(bitPattern:0x3fa257c9d4c53dd9))]
  let end=[V(Double(bitPattern:0x3fc39a61d0791bc1),Double(bitPattern:0xbfb0796f9730bf63),Double(bitPattern:0x3fa257a178a1e52a)),V(Double(bitPattern:0x3fc3053ead197e91),Double(bitPattern:0xbfb0c8a177bf9700),Double(bitPattern:0x3fa506a6348b9df2)),V(Double(bitPattern:0x3fc148ad0cbcd737),Double(bitPattern:0xbfb1be8d849c561d),Double(bitPattern:0x3fad1f923e94de5f)),V(Double(bitPattern:0x3fc39a61a7c967f4),Double(bitPattern:0xbfb07969df333ba2),Double(bitPattern:0x3fa257a381eefa19))]
  var limits=FeatureSeparationCertificate.Limits();limits.recordLeafCertificates=true
  let r=FeatureSeparationCertificate.certify(kind:.edgeEdge,start:start,end:end,minimumSeparation:0,limits:limits)
  precondition(r.distanceSeparatedForWholeMotion && r.affineNormalIntervalsCertified>0)
  precondition(r.maximumDepthReached<=12 && r.processedNodes<=8191 && r.maximumExpansionWords<=64)
  precondition(r.affineNormalCertificates.allSatisfy{$0.projectionScale==2 && $0.distanceLowerBoundMeters>0})
  print(r.affineNormalIntervalsCertified,r.expansionOperations,FloatingPointEnvironment.isNearestRounding)
 }
}
