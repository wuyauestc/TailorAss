import Foundation
import CryptoKit

@main @MainActor struct LevelsHemRegression {
    struct Case:Decodable {
        let id:String,originalCaseID:String
        let body:[String:Double],design:[String:JSONValue]
        let tiers:Int,expected:GarmentCodePatternFile
    }
    struct Source:Decodable {let commit:String,generatorSHA256:String}
    struct Fixture:Decodable {let format:String,source:Source;let cases:[Case]}
    enum Failure:Error {case failed(String)}
    static func require(_ value:Bool,_ message:String)throws {if !value {throw Failure.failed(message)}}
    static func seams(_ file:GarmentCodePatternFile)->[[String]] {
        file.pattern.stitches.map{$0.sides.map{"\($0.panel)#\($0.edge)"}.sorted()+($0.rightWrong ? ["right_wrong"]:[])}.sorted{$0.lexicographicallyPrecedes($1)}
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        let legacy=CommandLine.arguments.count>3 && CommandLine.arguments[3]=="legacy"
        let data=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/levels-asymmetric-oracles.json"))
        let fixture=try JSONDecoder().decode(Fixture.self,from:data)
        try require(fixture.format=="GarmentCodeAsymmetricTierOracles/v1" && fixture.source.commit=="d449629979028123a5c4dc9e732a2ec19b7fce31" && fixture.cases.count==24,"Complete pinned oracle matrix")
        let script=try Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/GenerateLevelsAsymmetricGoldens.py"))
        try require(fixture.source.generatorSHA256==SHA256.hash(data:script).map{String(format:"%02x",$0)}.joined(),"Oracle regeneration script identity")
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        var records:[[String:Any]]=[],mismatches=0,maximum=0.0
        for item in fixture.cases {
            let input=GarmentCodePatternFile(pattern:item.expected.pattern,
                parameters:["body":.object(item.body.mapValues(JSONValue.number)),"design":.object(item.design)])
            let restored=try GarmentCodeJointParameters.restore(document:input,catalog:catalog)
            let actual=try GarmentCodeNativeGenerator.generate(body:restored.body,design:restored.design)
            try require(actual.parameters?["body"]==input.parameters?["body"] && actual.parameters?["design"]==input.parameters?["design"],"Original full parameters retained")
            let a=try actual.geometryPanels(),b=try item.expected.geometryPanels()
            try require(Set(a.keys)==Set(b.keys),"\(item.id): complete panels")
            let actualSeams=seams(actual),expectedSeams=seams(item.expected)
            let seamMatches=actualSeams==expectedSeams
            if !legacy {try require(seamMatches,"\(item.id): complete source stitch references")}
            try require(a.count==2*(item.tiers+1),"Complete base and all tiers")
            var delta=0.0,edges=0,metadataMatches=true
            for id in a.keys.sorted() {
                let x=a[id]!,y=b[id]!
                try require(x.edges.count==y.edges.count,"\(item.id)/\(id): actual source topology")
                metadataMatches = metadataMatches && x.label==y.label && (x.signedArea<0)==(y.signedArea<0)
                for (left,right) in zip(x.edges,y.edges) {
                    metadataMatches = metadataMatches && left.label==right.label && left.curvature?.type==right.curvature?.type
                    for index in 0...100 {delta=max(delta,left.point(at:Double(index)/100).distance(to:right.point(at:Double(index)/100)))}
                    delta=max(delta,abs(left.length(tolerance:1e-10)-right.length(tolerance:1e-10)))
                    edges+=1
                }
            }
            let matches=delta<0.0001 && seamMatches && metadataMatches
            if !matches {mismatches+=1}
            if !legacy {try require(matches,"\(item.id): upstream geometry/roles differ by \(delta) cm, metadata \(metadataMatches)")}
            maximum=max(maximum,delta)
            let encoded=try JSONEncoder().encode(actual)
            try encoded.write(to:out.appendingPathComponent(item.id+".json"),options:.atomic)
            records.append(["id":item.id,"originalCaseID":item.originalCaseID,"tiers":item.tiers,
                "panels":a.count,"edges":edges,"maximumGeometryDeltaCentimeters":delta,"matchesPinnedOracle":matches,
                "sourceStitchesMatch":seamMatches,"sourceMetadataMatch":metadataMatches,
                "actualStitches":actualSeams,"expectedStitches":expectedSeams,
                "sourceSHA256":try GarmentCodeJointParameters.signature(actual)])
        }
        if legacy {try require(mismatches==24,"The unchanged legacy generator must reproduce all 24 actual semantic failures")}
        let result:[String:Any]=["passed":true,"legacyFailureReproductionOnly":legacy,"caseCount":records.count,
            "mismatches":mismatches,"maximumGeometryDeltaCentimeters":maximum,"records":records,
            "scope":"Complete source geometry/topology/seams and explicit parameters only; no placement/meshing/physics/garment acceptance",
            "completeGarmentAccepted":false]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("levels-hem-proof.json"),options:.atomic)
        print("PASS LevelsHem",records.count,"legacy",legacy,"mismatches",mismatches,"maximum cm",maximum)
    }
}
