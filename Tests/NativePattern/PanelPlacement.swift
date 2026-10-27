import Foundation
import CryptoKit

@main @MainActor
struct PanelPlacementRegression {
    typealias P = GarmentCodePanelPlacement
    typealias V = GarmentCodeCircleDrape.Vector3
    enum Failure: Error { case check(String) }
    static func require(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
        if !condition() { throw Failure.check(reason) }
    }
    static func near(_ a: V, _ b: V, _ reason: String) throws {
        try require((a-b).length < 1e-11, reason)
    }
    // Independent closed-form matrix from the actual upstream meshgen
    // rotation.py. Production applies three successive axis rotations.
    static func oracle(_ p: V, angles: [Double], translation: [Double], units: Double, waist: Double) -> V {
        let a=angles.map{$0 * Double.pi/180}, sx=sin(a[0]),cx=cos(a[0]),sy=sin(a[1]),cy=cos(a[1]),sz=sin(a[2]),cz=cos(a[2])
        return .init(x:cy*cz*p.x + (sx*sy*cz-cx*sz)*p.y + (cx*sy*cz+sx*sz)*p.z + translation[0]/units,
                     y:cy*sz*p.x + (sx*sy*sz+cx*cz)*p.y + (cx*sy*sz-sx*cz)*p.z + translation[1]/units-waist/100,
                     z: -sy*p.x + sx*cy*p.y + cx*cy*p.z + translation[2]/units)
    }
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func modified(_ source:GarmentCodePatternFile, transform:(String,GarmentCodePanel)->GarmentCodePanel,
                         properties:[String:JSONValue]?=nil)->GarmentCodePatternFile {
        .init(pattern:.init(panels:Dictionary(uniqueKeysWithValues:source.pattern.panels.map{($0.key,transform($0.key,$0.value))}),
                            stitches:source.pattern.stitches,panelOrder:source.pattern.panelOrder),
              parameters:source.parameters,parameterOrder:source.parameterOrder,properties:properties ?? source.properties)
    }
    static func main()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_PANEL_PLACEMENT_OUTPUT"] ?? "/private/tmp/TailorAssPanelPlacement")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body),waist=body["_waist_level"]!
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        for angles in [[90.0,0,0],[0,90.0,0],[0,0,90.0],[37.0,-28,13]] {
            let transform=try P.Transform(rotationDegrees:angles,translation:[20,150,-30],unitsInMeter:100,waistLevelCentimeters:100)
            for p in [V(x:1,y:0,z:0),.init(x:0,y:1,z:0),.init(x:0,y:0,z:1),.init(x:0.13,y:-0.28,z:0.07)] {
                try near(transform.point(p),oracle(p,angles:angles,translation:[20,150,-30],units:100,waist:100),"Independent rotation/translation oracle differs")
                let direction=try transform.direction(p)
                try require(abs(direction.length-p.length)<1e-12,"Rotation changed vector length")
            }
        }
        let rx=try P.Transform(rotationDegrees:[90,0,0],translation:[0,0,0],unitsInMeter:100,waistLevelCentimeters:0)
        let ry=try P.Transform(rotationDegrees:[0,90,0],translation:[0,0,0],unitsInMeter:100,waistLevelCentimeters:0)
        let rz=try P.Transform(rotationDegrees:[0,0,90],translation:[0,0,0],unitsInMeter:100,waistLevelCentimeters:0)
        try near(rx.direction(.init(x:0,y:1,z:0)),.init(x:0,y:0,z:1),"X90 basis")
        try near(ry.direction(.init(x:1,y:0,z:0)),.init(x:0,y:0,z:-1),"Y90 basis")
        try near(rz.direction(.init(x:1,y:0,z:0)),.init(x:0,y:1,z:0),"Z90 basis")
        let metre=try P.Transform(rotationDegrees:[11,22,33],translation:[0.2,1.5,-0.3],unitsInMeter:1,waistLevelCentimeters:waist)
        let centimetre=try P.Transform(rotationDegrees:[11,22,33],translation:[20,150,-30],unitsInMeter:100,waistLevelCentimeters:waist)
        try near(metre.point(.init(x:0.2,y:0.3,z:0)),centimetre.point(.init(x:0.2,y:0.3,z:0)),"Source translation units applied twice or omitted")
        var rows:[[String:Any]]=[]
        let cases:[(String,[String])]=[
            ("shirt",["left_ftorso","right_btorso"]),
            ("fitted-shirt",["right_ftorso","left_btorso"]),
            ("pants",["pant_f_l","pant_b_r"]),
            ("pencil-skirt",["skirt_front","skirt_back"]),
            ("shirt-sleeved",["right_sleeve_f","left_sleeve_b"]),
            ("shirt-collar-SimpleLapel",["right_collar_back","left_collar_back"]),
            ("shirt-collar-Hood2Panels",["right_hood","left_hood"])]
        for (name,panels) in cases {
            let source=root.appendingPathComponent("Tests/NativePattern/Fixtures/\(name).json"),bytes=try Data(contentsOf:source)
            let document=try GarmentCodePatternFile.validatedImport(from:bytes),before=try encoder.encode(document),geometry=try document.geometryPanels()
            let transforms=try P.importedTransforms(document:document,waistLevelCentimeters:waist)
            try require(Set(transforms.keys)==Set(document.pattern.panels.keys),"Import omitted a source transform")
            for name in panels {
                let raw=document.pattern.panels[name]!,mesh=try GarmentCodePanelMesher.prepare(panel:geometry[name]!,targetEdgeMeters:0.06)
                let placed=try P.place(mesh:mesh,transform:transforms[name]!),expectedNormal=oracle(.init(x:0,y:0,z:mesh.sourceClockwise ? -1:1),angles:raw.rotation!,translation:[0,0,0],units:1,waist:0)
                try require(placed.positions.count==mesh.flatPositions.count && placed.panelID==name,"Placement dropped source vertices or identity")
                for (p,q) in zip(mesh.flatPositions,placed.positions) {
                    try near(q,oracle(p,angles:raw.rotation!,translation:raw.translation!,units:document.unitsInMeter,waist:waist),"Fixture point differs from actual meshgen convention")
                }
                try near(placed.fabricNormal,expectedNormal,"Fabric normal did not use identical rotation and original source winding")
                let ids=(0..<3).map{Int(mesh.triangleIndices[$0])},a=placed.positions[ids[0]],b=placed.positions[ids[1]],c=placed.positions[ids[2]]
                var normal=(b-a).cross(c-a);if mesh.sourceClockwise {normal=normal * -1}
                try near(normal/normal.length,placed.fabricNormal,"Actual original-winding triangle normal differs")
                var cancelled=false
                do{_=try P.place(mesh:mesh,transform:transforms[name]!,isCancelled:{true})}catch is CancellationError{cancelled=true}
                try require(cancelled,"Cancelled placement returned a usable panel")
                rows.append(["fixture":source.lastPathComponent,"panel":name,"vertices":placed.positions.count,"sourceSHA256":hash(bytes),
                    "translation":raw.translation!,"rotationDegrees":raw.rotation!,"normal":[placed.fabricNormal.x,placed.fabricNormal.y,placed.fabricNormal.z]])
            }
            let after=try encoder.encode(document),afterBytes=try Data(contentsOf:source)
            try require(before==after && bytes==afterBytes,"Placement mutated imported source JSON")
        }
        let source=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/shirt.json")))
        let first=source.pattern.panels.keys.sorted()[0]
        var invalidDocuments:[GarmentCodePatternFile]=[]
        invalidDocuments.append(modified(source,transform:{_,p in .init(vertices:p.vertices,edges:p.edges,label:p.label,translation:[0,0,0],rotation:[0,0,0])}))
        invalidDocuments.append(modified(source,transform:{name,p in name==first ? .init(vertices:p.vertices,edges:p.edges,label:p.label,translation:nil,rotation:p.rotation):p}))
        invalidDocuments.append(modified(source,transform:{name,p in name==first ? .init(vertices:p.vertices,edges:p.edges,label:p.label,translation:p.translation,rotation:[0,0]):p}))
        invalidDocuments.append(modified(source,transform:{name,p in name==first ? .init(vertices:p.vertices,edges:p.edges,label:p.label,translation:[0,.nan,0],rotation:p.rotation):p}))
        var falseProperties=source.properties ?? [:]
        falseProperties["tailorass_generator"] = .object(["includes_3d_placement":.bool(false)])
        invalidDocuments.append(modified(source,transform:{_,p in p},properties:falseProperties))
        for document in invalidDocuments {
            var rejected=false
            do{_=try P.importedTransforms(document:document,waistLevelCentimeters:waist)}catch{rejected=true}
            try require(rejected,"Missing, malformed, all-zero or explicitly absent placement was accepted")
        }
        let legitimateOrigin=modified(source,transform:{name,p in name==first ? .init(vertices:p.vertices,edges:p.edges,label:p.label,translation:[0,0,0],rotation:[0,0,0]):p})
        _=try P.importedTransforms(document:legitimateOrigin,waistLevelCentimeters:waist)
        for units in [0.0,-1,.nan] {
            var rejected=false
            do{_=try P.Transform(rotationDegrees:[0,0,0],translation:[1,2,3],unitsInMeter:units,waistLevelCentimeters:waist)}catch{rejected=true}
            try require(rejected,"Invalid source units accepted")
        }
        let identity=try P.Transform(rotationDegrees:[0,0,0],translation:[0,0,0],unitsInMeter:1,waistLevelCentimeters:0)
        var rejected=false
        do{_=try identity.point(.init(x:.nan,y:0,z:0))}catch{rejected=true}
        try require(rejected,"Nonfinite source position accepted")
        let summary:[String:Any]=["passed":true,"panels":rows,"waistLevelCentimeters":waist,"sourceUnchanged":true,
            "scope":"Imported source placement and fabric-normal mapping only. Exact actual upstream meshgen Rz*Ry*Rx; independent closed-form/basis/unit/failure checks. Not a native-generated placement recipe, body pose match, sewn garment or physical drape claim."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("panel-placement-summary.json"))
        print("PASS: \(rows.count) actual fixture panels placed with source units, meshgen RzRyRx and original fabric normal; immutable source, missing/native-zero rejection and cancellation")
    }
}
