import Foundation

/// Import/export safety checks independent of curve-solver diagnostics.
@main
struct PatternImportExportRegression {
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var checks = 0
        for filename in ["shirt.json", "pants.json", "pencil-skirt-SIGGRAPH_logo.json",
                         "waistband-straight.json"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/\(filename)"))
            let document = try GarmentCodePatternFile.validatedImport(from: data)
            let restored = try GarmentCodePatternFile.validatedImport(
                from: JSONEncoder().encode(document))
            precondition(document.pattern.panels == restored.pattern.panels)
            precondition(document.pattern.stitches == restored.pattern.stitches)
            let originalGeometry = try document.geometryPanels()
            let restoredGeometry = try restored.geometryPanels()
            precondition(originalGeometry.count == restoredGeometry.count)
            checks += 1
        }
        let rectangle: [String: Any] = [
            "pattern": ["panels": ["a": ["vertices": [[0, 0], [10, 0], [10, 20], [0, 20]],
                "edges": [["endpoints": [0, 1]], ["endpoints": [1, 2]],
                          ["endpoints": [2, 3]], ["endpoints": [3, 0]]]]], "stitches": []],
            "properties": ["units_in_meter": 100, "curvature_coords": "relative"]
        ]
        func encode(_ object: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        func mustReject(_ object: [String: Any], _ label: String) throws {
            let data = try encode(object)
            do {
                _ = try GarmentCodePatternFile.validatedImport(from: data)
                preconditionFailure("Import accepted \(label)")
            } catch { checks += 1 }
        }
        _ = try GarmentCodePatternFile.validatedImport(from: encode(rectangle))
        for mode: Any in ["unsupported", 42, NSNull()] {
            var bad = rectangle
            bad["properties"] = ["curvature_coords": mode]
            try mustReject(bad, "invalid coordinate mode \(mode)")
        }
        for units in [0.0, -100.0, 1e-320, 1e-306] {
            var bad = rectangle
            bad["properties"] = ["units_in_meter": units]
            try mustReject(bad, "invalid or overflowing unit conversion \(units)")
        }
        var badStitch = rectangle
        var pattern = badStitch["pattern"] as! [String: Any]
        pattern["stitches"] = [[["panel": "missing", "edge": 0], ["panel": "a", "edge": 0]]]
        badStitch["pattern"] = pattern
        try mustReject(badStitch, "dangling stitch")
        var millimeters = rectangle
        millimeters["properties"] = ["units_in_meter": 1000, "curvature_coords": "absolute"]
        let normalized = try GarmentCodePatternFile.validatedImport(from: encode(millimeters)).geometryPanels()
        precondition(normalized["a"]!.edges[0].end == .init(x: 1, y: 0))
        let huge = GarmentCodeGeometryEdge(id: "large", start: .zero, end: .init(x: 1e20, y: 0))
        precondition(huge.sample().count == 513, "Sampling must cap before converting length to Int")
        precondition(huge.sample(minimumSegments: Int.max).count == 513)
        print("PASS: \(checks) import/roundtrip cases, unit normalization and bounded sampling; NOT full garment acceptance")
    }
}
