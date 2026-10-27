import Foundation
import CryptoKit

/// Exact value signature for preserving existing initialization contracts.
/// No timing, resource URL, warnings or new optional proof is included.
@MainActor enum NativeInitializationState {
    typealias K=GarmentCodeCircleDrape
    struct Spring:Encodable {let a:Int,b:Int,length:Double,isShear:Bool;init(_ s:K.Spring){a=s.a;b=s.b;length=s.length;isShear=s.isShear}}
    struct Binding:Encodable {let mesh:GarmentCodePanelMesher.Mesh,vertices:[Int],triangles:[Int]}
    struct State:Encodable {
        let sourceSHA256:String,planSHA256:String
        let positions:[K.Vector3],referencePositions:[K.Vector3],mannequinPositions:[K.Vector3]
        let triangles:[UInt32],referenceTriangles:[UInt32],mannequinTriangles:[UInt32]
        let pinned:[Bool],inverseMasses:[Double],referenceToSimulation:[Int]
        let springs:[Spring],bending:[Spring],bindings:[Binding]
        let referenceAreaSquareMeters:Double,totalMassKg:Double?,meanMassKg:Double
    }
    static func encode<T:Encodable>(_ v:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(v)}
    static func hash(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func signature(_ p:GarmentCodeSewnDrape.PreparedInput)throws->String{
        let c=p.cloth,s=State(sourceSHA256:p.sourceSHA256,planSHA256:try hash(encode(p.plan)),positions:c.positions,referencePositions:c.referencePositions,mannequinPositions:c.mannequinPositions,
            triangles:c.triangleIndices,referenceTriangles:c.referenceTriangles,mannequinTriangles:c.mannequinTriangleIndices,pinned:c.pinned,inverseMasses:c.inverseMasses,referenceToSimulation:c.referenceToSimulation,
            springs:c.springs.map(Spring.init),bending:c.bendingSprings.map(Spring.init),bindings:p.panelBindings.map{.init(mesh:$0.mesh,vertices:$0.vertexIDs,triangles:$0.triangleIDs)},referenceAreaSquareMeters:c.referenceAreaSquareMeters,totalMassKg:c.totalFabricMassKg,meanMassKg:c.meanParticleMassKg)
        return try hash(encode(s))
    }
}
