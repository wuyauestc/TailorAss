import Foundation
import CryptoKit
@main @MainActor struct BodyRigSleeveAxisRegression {
    typealias V=GarmentCodeCircleDrape.Vector3
    struct Panel:Decodable {let panelID:String,longitudinalLocalCoordinateAxis:[Double],worldAxisFromOfficialPointTo3D:[Double]}
    struct Case:Decodable {let upper:String,armPoseAngleInputDegrees:Double,body:[String:Double],panels:[Panel],completePatternPanelCount:Int}
    struct Fixture:Decodable {let cases:[Case],measurementCodeOrAGPLPathsUsed:Bool}
    enum E:Error {case failed(String)}
    static func require(_ b:Bool,_ s:String)throws {if !b{throw E.failed(s)}}
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let data=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/body-rig-sleeve-axes.json")),fixture=try JSONDecoder().decode(Fixture.self,from:data)
        try require(fixture.cases.count==6 && !fixture.measurementCodeOrAGPLPathsUsed,"Original MIT coordinate oracle")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"));var rows:[[String:Any]]=[],maximum=0.0
        for c in fixture.cases {
            let body=GarmentCodeBodyParameters(values:c.body);var design=GarmentCodeDesignParameters(catalog:catalog)
            _=design.setValue(.string(c.upper),at:["meta","upper"]);_=design.setValue(.null,at:["meta","wb"]);_=design.setValue(.null,at:["meta","bottom"]);_=design.setValue(.bool(false),at:["sleeve","sleeveless"])
            let document=try GarmentCodeNativeGenerator.generate(body:body,design:design),placement=try GarmentCodeUpperPlacement.sourceMap(document:document,body:body,design:design)
            try require(document.pattern.panels.count==c.completePatternPanelCount && placement.panels.count==c.completePatternPanelCount,"Complete upper source preserved")
            for p in c.panels {
                guard let panel=placement.panels[p.panelID] else{throw E.failed("Missing original sleeve "+p.panelID)}
                let a=p.longitudinalLocalCoordinateAxis,v=try panel.transform.direction(V(x:a[0],y:a[1],z:a[2])),q=p.worldAxisFromOfficialPointTo3D
                let error=max(abs(v.x-q[0]),abs(v.y-q[1]),abs(v.z-q[2]));maximum=max(maximum,error)
                try require(error<1e-12,"Swift / official sleeve coordinate direction mismatch")
                let below=atan2(-v.y,abs(v.x))*180/Double.pi,down=acos(max(-1,min(1,-v.y)))*180/Double.pi
                try require(abs(below-c.armPoseAngleInputDegrees)<1e-10 && abs(down-(90-c.armPoseAngleInputDegrees))<1e-10,"Angle convention mismatch")
                rows.append(["upper":c.upper,"panel":p.panelID,"inputAngle":c.armPoseAngleInputDegrees,"worldAxis":[v.x,v.y,v.z],"error":error,"belowHorizontal":below,"angleToDownY":down])
            }
        }
        try require(rows.count==24,"All left/right/front/back cases checked")
        let summary:[String:Any]=["passed":true,"caseCount":fixture.cases.count,"axisCount":rows.count,"maximumDirectionError":maximum,
            "oracleSHA256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),"rows":rows,
            "scope":"Author-defined sleeve longitudinal coordinate axes; not measured human-bone axes, skin fitting or sleeve centerlines.","existingBodyOrSDFModified":false]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out)
        print("Body rig sleeve coordinate axes: 6 complete original garments / 24 directions passed, max error",maximum)
    }
}
