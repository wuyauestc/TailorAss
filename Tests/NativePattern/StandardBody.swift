import Foundation

@main
struct StandardBodyRegression {
    enum Failure:Error {case check(String)}
    static func require(_ value:Bool,_ message:String)throws {if !value{throw Failure.check(message)}}
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources=root.appendingPathComponent("TrailorAss/Resources")
        let catalog=try GarmentCodeParameterCatalog.load(from:resources.appendingPathComponent("GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body)
        let standard=try GarmentCodeStandardBody.load(body:body,resourceDirectory:resources)
        typealias V=GarmentCodeCircleDrape.Vector3
        try require(standard.positions.count==13380,"Unexpected anatomical body count")
        try require(standard.triangleIndices.count==26756*3,"Unexpected anatomical triangle count")
        try require(standard.positions.allSatisfy(\.isFinite),"Non-finite anatomical mesh")
        let minY=standard.positions.map(\.y).min()!,maxY=standard.positions.map(\.y).max()!
        try require(abs(maxY-minY-(body["height"] ?? 0)/100)<1e-5,"Body stature normalization failed")
        try require(abs(minY+(body["_waist_level"] ?? 0)/100)<1e-5,"Waist-to-ground normalization failed")
        let inside=V(x:0,y:-0.1,z:0)
        try require((standard.signedDistance(inside) ?? 1)<(-0.05),"Deep body interior lost negative distance")
        try require(standard.penetration(inside)>0.05,"Deep interior incorrectly reported clean")
        try require((standard.signedDistance(.init(x:0.4,y:-0.4,z:0)) ?? -1)>0.1,"Outside body sign")
        try require((standard.signedDistance(.init(x:0,y:-0.6,z:-0.02)) ?? -1)>0,"Anatomical leg gap must remain free, not a tube")
        var perimeter=0.0,maxWaistError=0.0
        for i in 0..<1024 {
            let p=standard.waistPoint(arcFraction:Double(i)/1024)
            let q=standard.waistPoint(arcFraction:Double(i+1)/1024)
            perimeter+=(q-p).length
            maxWaistError=max(maxWaistError,abs(standard.signedDistance(p) ?? 1))
        }
        try require(abs(perimeter-(body["waist"] ?? 0)/100)<0.0003,"Waist support arc-length mismatch")
        try require(maxWaistError<0.003,"Waist support does not follow visible collision surface")
        let projected=standard.project(.init(x:0.1,y:-0.1,z:0),thickness:0.003)
        try require(projected.isFinite,"Projection became non-finite")
        try require(standard.penetration(projected)<0.002,"Projection failed to leave visible body field")
        // A dimensional fit and its inverse-warped field must stay aligned.
        var edited=catalog.body;edited["waist"]! *= 1.05;edited["hips"]! *= 1.04
        let fitted=try GarmentCodeStandardBody.load(body:.init(values:edited),resourceDirectory:resources)
        let fittedPoint=fitted.waistPoint(arcFraction:0.2)
        try require(abs(fitted.signedDistance(fittedPoint) ?? 1)<0.003,"Fitted surface/field mismatch")
        // A valid negative field with no gradient must remain penetrating,
        // even though the projector has no reliable outward direction.
        let flatDirectory=FileManager.default.temporaryDirectory.appendingPathComponent("TailorAssFlatBodyField-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:flatDirectory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:flatDirectory)}
        try FileManager.default.copyItem(at:resources.appendingPathComponent("GarmentCodeStandardBody.json"),to:flatDirectory.appendingPathComponent("GarmentCodeStandardBody.json"))
        let fieldSize=try Data(contentsOf:resources.appendingPathComponent("GarmentCodeStandardBodySDF.bin")).count
        var field=Data(count:fieldSize)
        field.withUnsafeMutableBytes {raw in
            for i in stride(from:0,to:fieldSize,by:4) {raw.storeBytes(of:Float(-0.01).bitPattern.littleEndian,toByteOffset:i,as:UInt32.self)}
        }
        try field.write(to:flatDirectory.appendingPathComponent("GarmentCodeStandardBodySDF.bin"))
        let noGradient=try GarmentCodeStandardBody.load(body:body,resourceDirectory:flatDirectory)
        try require(noGradient.penetration(inside)>0.009,"Zero gradient erased a negative signed distance")
        try require(noGradient.penetration(noGradient.project(inside,thickness:0.003))>0.009,"Unresolved flat contact was hidden")
        print("PASS: anatomical CC0 mesh, body sign/deep penetration, free leg gap, waist support, stature, field alignment and projection; waist SDF error \(maxWaistError*1000) mm")
    }
}
