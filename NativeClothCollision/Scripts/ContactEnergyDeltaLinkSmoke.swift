import NativeClothCollision
@main struct Smoke { static func main()throws {
 let x=[SIMD3<Double>(0,0,0),SIMD3<Double>(0.001,0,0)],y=[SIMD3<Double>(0,0,0),SIMD3<Double>(0.001000001,0,0)]
 let params=ContactEnergyDelta.Parameters(stiffnessPascals:35,minimumDistanceMeters:0,activationGapMeters:0.002)
 let p=try ContactEnergyDelta.Prepared(restPositions:x,bodyParameters:params,clothParameters:params)
 let leaf=ContactEnergyDelta.Leaf(kind:0,vertexIDs:[0,1],cachedDistanceType:0,signedRestAreaSquareMeters:0.0001,roundedEnergyJoules:0)
 let a=try p.capture(positions:x,bodyLeaves:[],clothLeaves:[leaf]),b=try p.capture(positions:y,bodyLeaves:[],clothLeaves:[leaf])
 let d=try p.difference(from:a,to:b)
 print(d.cloth.deltaJoules,d.cloth.fixedLeaves,d.isDoubleEstimate,FloatingPointEnvironment.isNearestRounding)
} }
