import Foundation

/// Run with Scripts/test-garmentcode-import.sh; no simulator or third-party dependencies.
@main
struct GarmentCodeImportSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Pass the official GarmentCode JSON fixture path")
        }
        let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let official = try GarmentCodePatternFile.validatedImport(from: fixture)
        precondition(official.panels.count == 8 && official.stitchCount == 16)

        var passed = 1
        func accept(_ name: String, _ data: Data) throws {
            _ = try GarmentCodePatternFile.validatedImport(from: data)
            passed += 1
            print("PASS valid: \(name)")
        }
        func reject(_ name: String, _ data: Data) {
            do {
                _ = try GarmentCodePatternFile.validatedImport(from: data)
                fatalError("Unexpectedly accepted malformed JSON: \(name)")
            } catch {
                precondition(!error.localizedDescription.isEmpty)
                passed += 1
                print("PASS rejected: \(name)")
            }
        }

        try accept("straight closed panel", document())
        for (type, params) in [
            ("quadratic", [[0.5, 0.2]]),
            ("cubic", [[0.3, 0.2], [0.7, 0.2]])
        ] {
            try accept(type, document(curvature: ["type": type, "params": params]))
        }
        try accept("circular edge", document(curvature: ["type": "circle", "params": [8, 0, 1]]))

        reject("empty panels", Data(#"{"pattern":{"panels":{},"stitches":[]}}"#.utf8))
        for coordinates: [Any] in [[], [0], [0, 0, 0], ["zero", 0]] {
            reject("malformed vertex \(coordinates)", document(firstVertex: coordinates))
        }
        reject("nonfinite coordinate", Data(String(decoding: document(), as: UTF8.self)
            .replacingOccurrences(of: "10", with: "1e400").utf8))
        reject("missing endpoint", document(firstEndpoints: [0]))
        reject("out-of-range endpoint", document(firstEndpoints: [0, 99]))
        reject("negative endpoint", document(firstEndpoints: [-1, 1]))
        reject("zero-length edge", document(firstEndpoints: [0, 0]))
        reject("disconnected boundary", document(firstEndpoints: [0, 2]))
        reject("unknown curve", document(curvature: ["type": "spline", "params": [[0.5, 0.2]]]))
        reject("short control point", document(curvature: ["type": "quadratic", "params": [[0.5]]]))
        reject("missing cubic control", document(curvature: ["type": "cubic", "params": [[0.5, 0.2]]]))
        reject("zero arc radius", document(curvature: ["type": "circle", "params": [0, 0, 1]]))
        reject("invalid arc flag", document(curvature: ["type": "circle", "params": [8, 2, 1]]))
        reject("incomplete arc parameters", document(curvature: ["type": "circle", "params": [8, 0]]))
        reject("missing stitched panel", document(stitches: [[
            ["panel": "piece", "edge": 0], ["panel": "missing", "edge": 1]
        ]]))
        reject("missing stitched edge", document(stitches: [[
            ["panel": "piece", "edge": 0], ["panel": "piece", "edge": 99]
        ]]))
        reject("incomplete stitch", document(stitches: [[["panel": "piece", "edge": 0]]]))
        for units: Any in [0, -100, "cm"] {
            reject("invalid units \(units)", document(units: units))
        }
        print("PASS \(passed) import checks, including official 8-panel / 16-stitch fixture")
    }

    private static func document(
        firstVertex: [Any] = [0, 0],
        firstEndpoints: [Int] = [0, 1],
        curvature: [String: Any]? = nil,
        stitches: [[[String: Any]]] = [],
        units: Any = 100
    ) -> Data {
        var firstEdge: [String: Any] = ["endpoints": firstEndpoints]
        if let curvature { firstEdge["curvature"] = curvature }
        let value: [String: Any] = [
            "pattern": [
                "panels": ["piece": [
                    "vertices": [firstVertex, [10, 0], [10, 10], [0, 10]],
                    "edges": [firstEdge, ["endpoints": [1, 2]], ["endpoints": [2, 3]], ["endpoints": [3, 0]]]
                ],
                "stitches": stitches
            ],
            "properties": ["units_in_meter": units]
        ]
        return try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
