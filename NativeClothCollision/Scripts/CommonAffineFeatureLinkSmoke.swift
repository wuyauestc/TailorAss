import NativeClothCollision
@main struct CommonAffineFeatureSmoke {
 static func main() {
  typealias V=SIMD3<Double>
  let start=[V(Double(bitPattern:0x3fc39a4263c5a49a),Double(bitPattern:0xbfb078ed57b27ab3),Double(bitPattern:0x3fa257c80b0ee15e)),V(Double(bitPattern:0x3fc306943c71886b),Double(bitPattern:0xbfb0cb8aeb062bb2),Double(bitPattern:0x3fa50a88021da7e4)),V(Double(bitPattern:0x3fc147a8858400c9),Double(bitPattern:0xbfb1bc03ee005907),Double(bitPattern:0x3fad1c61cffe3439)),V(Double(bitPattern:0x3fc39a422711bb67),Double(bitPattern:0xbfb078e79cc8dbaf),Double(bitPattern:0x3fa257c9d4c53dd9))]
  let end=[V(Double(bitPattern:0x3fc39a61d06df7a0),Double(bitPattern:0xbfb0796f97c81325),Double(bitPattern:0x3fa257a1789c0385)),V(Double(bitPattern:0x3fc3053eadcdafd1),Double(bitPattern:0xbfb0c8a173773d54),Double(bitPattern:0x3fa506a638aa5345)),V(Double(bitPattern:0x3fc148ad0ce1a2c1),Double(bitPattern:0xbfb1be8d858bf53c),Double(bitPattern:0x3fad1f923ed42e74)),V(Double(bitPattern:0x3fc39a61a7bf2104),Double(bitPattern:0xbfb07969dfcab36b),Double(bitPattern:0x3fa257a381ebc446))]
  var limits=FeatureSeparationCertificate.Limits();limits.recordLeafCertificates=true
  let r=FeatureSeparationCertificate.certify(kind:.edgeEdge,start:start,end:end,minimumSeparation:0,limits:limits)
  precondition(r.distanceSeparatedForWholeMotion && r.affineNormalIntervalsCertified>0)
  precondition(r.affineNormalAttempts>r.movingNormalAttempts)
  precondition(r.maximumDepthReached<=12 && r.processedNodes<=8191 && r.expansionOperations<=1048576)
  precondition(r.minimumCertifiedDistanceLowerBoundMeters!>0)
  print(r.affineNormalAttempts,r.expansionOperations,FloatingPointEnvironment.isNearestRounding)
 }
}
