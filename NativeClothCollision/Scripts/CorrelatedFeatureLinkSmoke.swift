import NativeClothCollision
@main struct Smoke { static func main() {
 let e=1e-10
 let a=[SIMD3<Double>(0.75,0.25,0.0625+e),.zero,SIMD3<Double>(4,0,-1),SIMD3<Double>(0,4,0)]
 let b=[SIMD3<Double>(1.75,0.25,-1.9375+e),.zero,SIMD3<Double>(4,0,-5),SIMD3<Double>(0,4,0)]
 var l=FeatureSeparationCertificate.Limits();l.recordLeafCertificates=true
 let r=FeatureSeparationCertificate.certify(kind:.vertexFace,start:a,end:b,minimumSeparation:0,limits:l)
 precondition(r.distanceSeparatedForWholeMotion && r.movingNormalIntervalsCertified>0)
 print(r.movingNormalAttempts,r.movingNormalIntervalsCertified,r.movingNormalCertificates.first!.normalBernsteinBounds.count,FloatingPointEnvironment.isNearestRounding)
} }
