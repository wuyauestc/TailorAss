import Foundation
import CryptoKit

@main @MainActor struct ContourDiagnosticChecks {
    typealias D = GarmentCodeContourDiagnostics
    struct Expected: Decodable { let panel: String; let edges: [Int]; let point: [Double] }
    struct Case: Decodable { let caseID: String, sourceSHA256: String; let paper: GarmentCodePatternFile; let expected: [Expected] }
    struct Fixture: Decodable { let independentDeliverySHA256: String; let cases: [Case] }
    struct Catalog: Decodable { struct Entry: Decodable { let caseID: String, patternFile: String, sourceSHA256: String, paperJSONBytesSHA256: String }; let cases: [Entry] }
    enum Failure: Error { case failed(String) }
    static func require(_ value: Bool, _ message: String) throws { if !value { throw Failure.failed(message) } }
    static func document(_ points: [GarmentCodePoint], first: GarmentCodeCurvature? = nil) throws -> GarmentCodePatternFile {
        let edges = points.indices.map { i in GarmentCodeGeometryEdge(id: "e\(i)", start: points[i],
            end: points[(i+1)%points.count], curvature: i == 0 ? first : nil) }
        return try .init(geometry: ["test": .init(id: "test", edges: edges)], stitches: [])
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Tests/NativePattern/Fixtures/source-contour-crossings.json")))
        try require(fixture.cases.count == 4 && fixture.independentDeliverySHA256 == "c994a895019e6778d7ad9267eb2450a651c4a5e3692697baebec552390f9f844", "independent exact root source")
        var witnesses = 0, transformedCases = 0
        for item in fixture.cases {
            try require(try GarmentCodeJointParameters.signature(item.paper) == item.sourceSHA256, "complete original source identity")
            let before = try JSONEncoder().encode(item.paper)
            let result = try D.inspect(item.paper)
            try require(!result.budgetReached && result.crossings.count == item.expected.count, "\(item.caseID): complete independent witness count")
            for witness in item.expected {
                let found = result.crossings.filter { $0.panel == witness.panel && [$0.firstEdge,$0.secondEdge] == witness.edges.sorted() }
                try require(found.count == 1 && found[0].point.distance(to: .init(x: witness.point[0], y: witness.point[1])) < 1e-8, "independent analytic source root location")
            }
            try require(D.messages(result, document: item.paper).last?.contains(item.caseID.contains("many-curve") ? "弧线系数" : "插片底边宽") == true, "specific Chinese adjustment hint")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try require(try encoder.encode(item.paper) == encoder.encode(JSONDecoder().decode(GarmentCodePatternFile.self, from: before)), "input not mutated")
            witnesses += result.crossings.count
            for scale in [0.01, 1.0, 100.0] {
                let geometry = try item.paper.geometryPanels().mapValues { panel in
                    GarmentCodePanelGeometry(id: panel.id, label: panel.label, edges: panel.edges.reversed().map { edge in
                        var x = edge.reversed()
                        x.start = x.start * scale + .init(x: 123.25, y: -52.75)
                        x.end = x.end * scale + .init(x: 123.25, y: -52.75)
                        if let c = x.curvature?.circle { x.curvature = .init(circleRadius: c.radius * scale, largeArc: c.largeArc, right: c.right) }
                        return x
                    })
                }
                let changed = try GarmentCodePatternFile(geometry: geometry, stitches: [])
                let transformed = try D.inspect(changed)
                try require(transformed.crossings.count == item.expected.count, "reverse/scale/translation source crossing")
                for witness in item.expected {
                    let panel = geometry[witness.panel]!, pivot = panel.edges.first!.start
                    let mappedEdges = witness.edges.map { panel.edges.count-1-$0 }.sorted()
                    let point = GarmentCodePoint(x:witness.point[0]*scale+123.25-Double(Int(pivot.x)),
                        y:witness.point[1]*scale-52.75-Double(Int(pivot.y)))
                    let found = transformed.crossings.filter { $0.panel==witness.panel && [$0.firstEdge,$0.secondEdge]==mappedEdges }
                    try require(found.count==1 && found[0].point.distance(to:point)<max(1,scale)*1e-8,
                        "each reversed source pair and transformed independent root, not just count")
                }
                transformedCases += 1
            }
            let bounded = try D.inspect(item.paper, maximumPairs: 0)
            try require(bounded.budgetReached && bounded.testedPairs == 0, "explicit uncompleted bounded work")
        }
        let rectangle = try document([.init(x:0,y:0),.init(x:2,y:0),.init(x:2,y:2),.init(x:0,y:2)])
        try require(try D.inspect(rectangle).crossings.isEmpty, "shared endpoints are not proper crossings")
        let bowtie = try document([.init(x:0,y:0),.init(x:2,y:2),.init(x:0,y:2),.init(x:2,y:0)])
        try require(try D.inspect(bowtie).crossings.count == 1, "transverse line witness")
        let minor = GarmentCodeCurvature(circleRadius:1,largeArc:false,right:false)
        let tangent = try document([.init(x:-1,y:0),.init(x:1,y:0),.init(x:2,y:1),.init(x:-2,y:1)],first:minor)
        try require(try D.inspect(tangent).crossings.isEmpty, "tangent is not transverse")
        let extra = try document([.init(x:-1,y:0),.init(x:1,y:0),.init(x:0,y:2)],first:minor)
        try require(try D.inspect(extra).crossings.count == 2, "two adjacent edges have secondary arc roots")
        let bezier = try document([.init(x:0,y:0),.init(x:2,y:0),.init(x:2,y:2),.init(x:0,y:2)],first:.init(type:"quadratic",params:[[0.5,-0.1]]))
        let partial = try D.inspect(bezier)
        try require(partial.unsupportedPairs == 3 && partial.crossings.isEmpty, "partial diagnostics do not certify unexamined curve types")
        let nearParallel = try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/contour-diagnostics/nearly-parallel-simple.json")))
        try require(try D.inspect(nearParallel).crossings.isEmpty, "independent exact simple quad: rounded root must not falsely block paper")
        for large in [false,true] { for right in [false,true] {
            // The horizontal segment y=.25 intersects the upper selected arc
            // twice for clockwise sweep. The counterclockwise selected arc is
            // below it; roots of the full circle must not be reported there.
            let arc = try document([.init(x:-1,y:0),.init(x:1,y:0),.init(x:2,y:0.25),.init(x:-2,y:0.25)],
                first:.init(circleRadius:1.25,largeArc:large,right:right))
            let hits = try D.inspect(arc).crossings
            try require(hits.count == (right ? 0:2), "selected minor/major arc and sweep")
            for hit in hits {
                try require(hit.firstEdge==0 && hit.secondEdge==2 && abs(hit.point.y-0.25)<1e-10,
                    "arc witness lies on actual horizontal source edge")
            }
        }}
        for radius in [0.75,1.0] { for large in [false,true] { for right in [false,true] {
            let semicircle = try document([.init(x:-1,y:0),.init(x:1,y:0),.init(x:0,y:2)],
                first:.init(circleRadius:radius,largeArc:large,right:right))
            let edge = try semicircle.geometryPanels()["test"]!.edges[0]
            try require(abs(edge.point(at:0.5).y-(right ? -1:1))<1e-12,
                "SVG diameter semicircle: large-arc cannot reverse the requested sweep")
            try require(try D.inspect(semicircle).crossings.count == (right ? 0:2),
                "semicircle original-source crossings agree with selected SVG sweep")
        }}}
        let radial = try document([.init(x:-1,y:0),.init(x:1,y:0),.init(x:0,y:-2),.init(x:0,y:2)],first:minor)
        let radialHits = try D.inspect(radial).crossings.filter { $0.firstEdge==0 && $0.secondEdge==2 }
        try require(radialHits.count==1 && radialHits[0].point.distance(to:.init(x:1,y:1))<1e-7 &&
                    abs(radialHits[0].secondParameter-0.75)<1e-7, "radial line is transverse to circle, not tangent")
        var catalogRows: [[String:Any]] = []
        let catalogURL = root.appendingPathComponent("Catalog/inputs/catalog-input-manifest.json")
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf:catalogURL))
            for entry in catalog.cases {
                let bytes = try Data(contentsOf:catalogURL.deletingLastPathComponent().appendingPathComponent(entry.patternFile))
                try require(SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()==entry.paperJSONBytesSHA256, "exact catalog paper bytes")
                let paper = try JSONDecoder().decode(GarmentCodePatternFile.self, from:bytes)
                try require(try GarmentCodeJointParameters.signature(paper)==entry.sourceSHA256, "exact catalog complete source identity")
                let report = try D.inspect(paper)
                catalogRows.append(["caseID":entry.caseID,"crossings":report.crossings.count,"budgetReached":report.budgetReached,"unsupportedPairs":report.unsupportedPairs])
            }
            let reported = catalogRows.filter { ($0["crossings"] as! Int) > 0 }.map { $0["caseID"] as! String }.sorted()
            try require(reported == fixture.cases.map(\.caseID).sorted(), "catalog: exactly four independently known crossing sources")
            try require(catalogRows.allSatisfy { !($0["budgetReached"] as! Bool) }, "catalog diagnostic work budget")
        }
        let result: [String:Any] = ["passed":true,"independentActualSourceCases":4,"independentRootWitnesses":witnesses,
            "reversedTranslatedScaledCases":transformedCases,"catalogCases":catalogRows,"analyticControls":19,
            "emptyReportMeansSimpleLoopCertificate":false,"completeGarmentAccepted":false]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("contour-diagnostics-proof.json"),options:.atomic)
        print("PASS contour diagnostics",witnesses,"actual source witnesses",catalogRows.count,"catalog cases")
    }
}
