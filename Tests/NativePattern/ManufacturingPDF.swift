import Foundation
import CoreGraphics
import PDFKit

/// Combined manufacturing-settings -> physical print-layout -> actual PDF gate.
/// Tests the same native services used by the editor, not a second renderer.
@main
struct ManufacturingPDFRegression {
    enum Failure: LocalizedError {
        case check(String)
        var errorDescription: String? { switch self { case let .check(message): message } }
    }

    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure.check(message) }
    }

    static func near(_ a: Double, _ b: Double, tolerance: Double = 0.005) -> Bool { abs(a - b) <= tolerance }
    static func same(_ a: CGRect, _ b: CGRect, tolerance: Double = 0.02) -> Bool {
        near(a.minX, b.minX, tolerance: tolerance) && near(a.minY, b.minY, tolerance: tolerance) &&
            near(a.width, b.width, tolerance: tolerance) && near(a.height, b.height, tolerance: tolerance)
    }

    static func requireBothNotchLabels(_ text: String) throws {
        let compact = String(text.filter { !$0.isWhitespace })
        for label in ["缝1·单", "缝1·双"] {
            let count = compact.components(separatedBy: label).count - 1
            try require(count == 2, "Full-sheet PDF must print \(label) on both sides, got \(count)")
        }
    }

    static func rectangle(_ name: String, width: Double = 10, height: Double = 20,
                          curvedLeft: Bool = false) -> [String: Any] {
        var edges: [[String: Any]] = [["endpoints": [0, 1]], ["endpoints": [1, 2]],
                                     ["endpoints": [2, 3]], ["endpoints": [3, 0]]]
        if curvedLeft { edges[3]["curvature"] = ["type": "quadratic", "params": [[0.5, 0.1]]] }
        return ["vertices": [[0.0, 0], [width, 0], [width, height], [0, height]], "edges": edges]
    }

    static func document(curvedLeft: Bool = false) throws -> (GarmentCodePatternFile, Data) {
        let object: [String: Any] = [
            "pattern": ["panels": ["skirt_front": rectangle("skirt_front", curvedLeft: curvedLeft),
                                    "skirt_back": rectangle("skirt_back")],
                        "stitches": [[["panel": "skirt_front", "edge": 1],
                                       ["panel": "skirt_back", "edge": 3]]],
                        "panel_order": ["skirt_front", "skirt_back"]],
            "properties": ["units_in_meter": 100, "curvature_coords": "relative"]
        ]
        let source = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return (try GarmentCodePatternFile.validatedImport(from: source), source)
    }

    static func crowdedDocument() throws -> GarmentCodePatternFile {
        // Split each straight side into four independently stitched edges,
        // producing dense but valid paired labels on one very small piece.
        let side = 1.6, count = 4
        var vertices: [[Double]] = []
        for index in 0..<count { vertices.append([Double(index) * side / Double(count), 0]) }
        for index in 0..<count { vertices.append([side, Double(index) * side / Double(count)]) }
        for index in 0..<count { vertices.append([side - Double(index) * side / Double(count), side]) }
        for index in 0..<count { vertices.append([0, side - Double(index) * side / Double(count)]) }
        let panel: [String: Any] = ["vertices": vertices, "edges": vertices.indices.map {
            ["endpoints": [$0, ($0 + 1) % vertices.count]]
        }]
        let stitches = vertices.indices.map { edge in
            [["panel": "skirt_front", "edge": edge], ["panel": "skirt_back", "edge": edge]]
        }
        let object: [String: Any] = [
            "pattern": ["panels": ["skirt_front": panel, "skirt_back": panel],
                        "stitches": stitches,
                        "panel_order": ["skirt_front", "skirt_back"]],
            "properties": ["units_in_meter": 100, "curvature_coords": "relative"]
        ]
        return try GarmentCodePatternFile.validatedImport(from: JSONSerialization.data(withJSONObject: object))
    }

    static func settings() -> GarmentCodeDraftingSettings {
        var settings = GarmentCodeDraftingSettings()
        settings.addSeamAllowance = true
        settings.standardAllowanceCM = 1
        settings.hemAllowanceCM = 3
        settings.showNotches = true
        for name in ["skirt_front", "skirt_back"] {
            var panel = GarmentCodeDraftingSettings.PanelSettings()
            panel.cutQuantity = 2
            panel.grainline = .init(angleDegrees: name == "skirt_front" ? 90 : 45,
                                   centerXRatio: 0.5, centerYRatio: 0.5, lengthRatio: 0.6)
            panel.edges[0] = .init(kind: .hem)
            // Explicit override equals the global width, testing serialization
            // and resolving an override without changing expected dimensions.
            panel.edges[2] = .init(kind: .seam, customWidthCM: 1)
            settings.panels[name] = panel
        }
        settings.setTreatment(.init(kind: .fold), panel: "skirt_front", edge: 3)
        return settings
    }

    static func signature(_ path: CGPath, relativeTo origin: CGPoint) -> [Double] {
        var result: [Double] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            result.append(Double(element.type.rawValue))
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            for index in 0..<count {
                result += [element.points[index].x - origin.x, element.points[index].y - origin.y]
            }
        }
        return result
    }

    static func rejects(_ label: String, document: GarmentCodePatternFile,
                         settings: GarmentCodeDraftingSettings) throws {
        do {
            _ = try GarmentCodePrintPlan(document: document, drafting: settings)
        } catch {
            try require(!error.localizedDescription.isEmpty, "\(label): empty diagnostic")
            return
        }
        throw Failure.check("\(label): invalid manufacture settings were accepted")
    }

    static func main() throws {
        let (document, sourceBytes) = try document()
        let originalBytes = sourceBytes
        let settings = settings()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sourceEncoded = try encoder.encode(document)
        let encodedSettings = try encoder.encode(settings)
        try require(try JSONDecoder().decode(GarmentCodeDraftingSettings.self, from: encodedSettings) == settings,
                    "Manufacture settings failed Codable roundtrip")
        let baseline = try GarmentCodePrintPlan(document: document)
        let plan = try GarmentCodePrintPlan(document: document, drafting: settings)
        try require(plan.includesSeamAllowance && plan.includesNotches && plan.panels.count == 2,
                    "Print plan lost manufacture options or panels")
        let board = CGRect(origin: .zero, size: plan.boardSizeCM)
        let lastTile = plan.tiles.last!.boardRectCM
        try require(lastTile.maxX >= board.maxX - 1e-8 && lastTile.maxY >= board.maxY - 1e-8,
                    "A4 tiles do not cover expanded board")
        var notchCounts: [String: Int] = [:]
        for panel in plan.panels {
            let original = baseline.panels.first { $0.name == panel.name }!
            let originalBounds = original.pathCM.boundingBoxOfPath
            let sourceBounds = panel.pathCM.boundingBoxOfPath
            try require(near(sourceBounds.width, 10) && near(sourceBounds.height, 20),
                        "\(panel.name): original seam-line dimensions changed")
            let a = signature(original.pathCM, relativeTo: originalBounds.origin)
            let b = signature(panel.pathCM, relativeTo: sourceBounds.origin)
            try require(a.count == b.count && zip(a, b).allSatisfy { near($0, $1, tolerance: 1e-8) },
                        "\(panel.name): original vector commands changed")
            for index in original.edgePathsCM.indices {
                let source = signature(original.edgePathsCM[index], relativeTo: originalBounds.origin)
                let current = signature(panel.edgePathsCM[index], relativeTo: sourceBounds.origin)
                try require(source.count == current.count && zip(source, current).allSatisfy { near($0, $1, tolerance: 1e-8) },
                            "\(panel.name): original edge \(index) changed")
            }
            guard let cut = panel.cutPathCM else { throw Failure.check("Missing cut path") }
            let bounds = cut.boundingBoxOfPath
            let expectedLeft = panel.name == "skirt_front" ? 0.0 : 1.0
            try require(near(sourceBounds.minX - bounds.minX, expectedLeft), "Fold/left allowance changed")
            try require(near(bounds.maxX - sourceBounds.maxX, 1), "Ordinary allowance is not 1 cm")
            // Print coordinates have y downwards: bottom hem is maximum y.
            try require(near(sourceBounds.minY - bounds.minY, 1), "Top allowance is not 1 cm")
            try require(near(bounds.maxY - sourceBounds.maxY, 3), "Hem allowance is not 3 cm")
            try require(panel.cutQuantity == 2 && panel.allowanceSummary.contains("缝份"),
                        "Cut quantity/allowance summary missing")
            try require(!panel.labelRectCM.intersects(bounds), "Label overlaps expanded cut path")
            try require(board.contains(bounds) && board.contains(panel.labelRectCM), "Cut path/label escapes physical board")
            try require(!panel.markingPathsCM.isEmpty, "Manufacture marking vectors missing")
            for marking in panel.markingPathsCM {
                try require(board.insetBy(dx: -1e-6, dy: -1e-6).contains(marking.boundingBoxOfPath),
                            "Marking vector escapes physical print board")
            }
            let texts = panel.markingLabelsCM.map(\.text)
            try require(texts.contains(where: { $0.contains("布纹方向") }), "Manual grainline label missing")
            if panel.name == "skirt_front" { try require(texts.contains("对折边"), "Fold-edge label missing") }
            for text in texts where text.hasPrefix("缝1·") { notchCounts[text, default: 0] += 1 }
        }
        try require(notchCounts["缝1·单"] == 2 && notchCounts["缝1·双"] == 2,
                    "Automatic single/double notches must be paired on both panels")
        var shallowNotch = settings
        shallowNotch.setTreatment(.init(kind: .seam, customWidthCM: 0.0001), panel: "skirt_front", edge: 1)
        let shallowPlan = try GarmentCodePrintPlan(document: document, drafting: shallowNotch)
        try require(shallowPlan.panels.allSatisfy { panel in
            panel.markingLabelsCM.allSatisfy { !$0.text.hasPrefix("缝1·") }
        }, "A locally unsafe shallow notch left an orphan marker on the other panel")
        try require(shallowPlan.warnings.contains { $0.contains("未能在两侧") },
                    "Omitted paired notches need an explicit manufacture warning")

        let output = ProcessInfo.processInfo.environment["GARMENTCODE_PDF_OUTPUT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("TailorAssManufacturingQA-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var checkedPages = 0
        for format in [GarmentCodePDFFormat.fullSize, .a4Tiled] {
            let data = try GarmentCodePDFExporter.data(document: document,
                options: .init(format: format, showSeams: false, drafting: settings))
            let filename = format == .fullSize ? "manufacturing-full-size.pdf" : "manufacturing-a4-tiled.pdf"
            try data.write(to: output.appendingPathComponent(filename), options: .atomic)
            guard let pdf = PDFDocument(data: data), let cg = CGPDFDocument(CGDataProvider(data: data as CFData)!) else {
                throw Failure.check("Generated manufacture PDF cannot be reopened")
            }
            let count = format == .fullSize ? 1 : plan.tiles.count + 1
            try require(pdf.pageCount == count && cg.numberOfPages == count, "Wrong manufacture PDF page count")
            let allText = pdf.string ?? ""
            for expected in ["裁 2 片", "布纹方向", "对折边", "缝1·单", "缝1·双", "实线裁剪线", "虚线原始制版线", "100%"] {
                try require(allText.contains(expected), "\(format): missing PDF text \(expected)")
            }
            if format == .fullSize { try requireBothNotchLabels(allText) }
            var dashed = 0, solid = 0
            for index in 0..<count {
                let page = cg.page(at: index + 1)!
                let scan = ManufacturingVectorScan.scan(page)
                dashed += scan.dashedStrokeCount; solid += scan.solidStrokeCount
                try require(scan.imageCount == 0, "Manufacture PDF rasterized its physical patterns")
                if index == 0 { try require(scan.hasTenCMSquare, "Manufacture PDF lost its physical 10 cm calibration") }
                let size = format == .fullSize ? plan.boardSizeCM : GarmentCodePrintPlan.a4SizeCM
                let media = page.getBoxRect(.mediaBox)
                try require(near(media.width, size.width * GarmentCodePrintPlan.pointsPerCM, tolerance: 0.002) &&
                            near(media.height, size.height * GarmentCodePrintPlan.pointsPerCM, tolerance: 0.002),
                            "Manufacture PDF changed physical MediaBox")
                if format == .fullSize || index > 0 {
                    let tile = format == .fullSize ? nil : plan.tiles[index - 1]
                    for panel in plan.panels {
                        let cut = panel.cutPathCM!.boundingBoxOfPath
                        guard tile == nil || tile!.boardRectCM.intersects(cut) else { continue }
                        let offset = tile.map { CGPoint(x: GarmentCodePrintPlan.tilePageOriginCM.x - $0.boardRectCM.minX,
                                                        y: GarmentCodePrintPlan.tilePageOriginCM.y - $0.boardRectCM.minY) } ?? .zero
                        let expected = CGRect(x: (cut.minX + offset.x) * GarmentCodePrintPlan.pointsPerCM,
                                              y: (cut.minY + offset.y) * GarmentCodePrintPlan.pointsPerCM,
                                              width: cut.width * GarmentCodePrintPlan.pointsPerCM,
                                              height: cut.height * GarmentCodePrintPlan.pointsPerCM)
                        // Clipped PDF tiles retain the actual full vector cut
                        // path. Its continuous board transform must agree on
                        // every intersecting tile, not merely on the cover.
                        try require(scan.solidBoundsTopDown.contains { same($0, expected) },
                                    "\(format) page \(index + 1): expanded cut path lost/shifted on tile")
                    }
                }
            }
            try require(dashed >= 2 && solid >= 2, "Original dashed seam/cut solid strokes are not distinguishable")
            checkedPages += count
        }

        // Seam-color badges have white backgrounds. They must never erase a
        // physical cutting line when seam colors and manufacture marks coexist.
        let seamsData = try GarmentCodePDFExporter.data(document: document,
            options: .init(format: .fullSize, showSeams: true, drafting: settings))
        try seamsData.write(to: output.appendingPathComponent("manufacturing-seams-full-size.pdf"), options: .atomic)
        guard let seamsPDF = PDFDocument(data: seamsData),
              let seamsCG = CGPDFDocument(CGDataProvider(data: seamsData as CFData)!) else {
            throw Failure.check("Colored-seam manufacturing PDF cannot be reopened")
        }
        try requireBothNotchLabels(seamsPDF.string ?? "")
        let seamsScan = ManufacturingVectorScan.scan(seamsCG.page(at: 1)!)
        try require(!seamsScan.whiteRectsTopDown.isEmpty, "Colored-seam sample did not exercise white badges")
        for panel in plan.panels {
            var transform = CGAffineTransform(scaleX: GarmentCodePrintPlan.pointsPerCM,
                                              y: GarmentCodePrintPlan.pointsPerCM)
            guard let cut = panel.cutPathCM?.copy(using: &transform) else { throw Failure.check("Missing physical cutting path") }
            let ink = cut.copy(strokingWithWidth: 0.85, lineCap: .round, lineJoin: .round, miterLimit: 4)
            for rect in seamsScan.whiteRectsTopDown {
                try require(!ink.intersects(CGPath(rect: rect, transform: nil), using: .winding),
                            "A white seam badge obscures the physical cutting line")
            }
        }
        checkedPages += 1

        // Crowded auxiliary labels may be omitted, but omission must be
        // explicit, and a paired notch label may never survive on just one side.
        let crowded = try crowdedDocument()
        var crowdedSettings = GarmentCodeDraftingSettings()
        crowdedSettings.addSeamAllowance = true
        crowdedSettings.standardAllowanceCM = 0.2
        crowdedSettings.showNotches = true
        let crowdedPlan = try GarmentCodePrintPlan(document: crowded, drafting: crowdedSettings)
        try require(crowdedPlan.panels.reduce(0) { $0 + $1.markingLabelsCM.count } == 64,
                    "Crowding fixture lost its input notch labels")
        let crowdedWarnings = GarmentCodePDFExporter.annotationWarnings(plan: crowdedPlan, showSeams: true,
                                                                         stitches: crowded.pattern.stitches)
        try require(crowdedWarnings.contains { $0.contains("省略") && $0.contains("成对") },
                    "Crowded PDF labels were omitted without an explicit paired-label warning")
        let crowdedData = try GarmentCodePDFExporter.data(document: crowded,
            options: .init(format: .fullSize, showSeams: true, drafting: crowdedSettings))
        guard let crowdedPDF = PDFDocument(data: crowdedData) else { throw Failure.check("Crowded PDF cannot be reopened") }
        let crowdedText = String((crowdedPDF.string ?? "").filter { !$0.isWhitespace })
        for seam in 1...16 {
            for ordinal in ["单", "双"] {
                let label = "缝\(seam)·\(ordinal)"
                let count = crowdedText.components(separatedBy: label).count - 1
                try require(count == 0 || count == 2, "Crowding left an unmatched \(label) label")
            }
        }
        try require(crowdedText.contains("密集区域可能省略辅助文字"), "Crowded PDF omitted its printed annotation caution")

        var invalid = settings
        invalid.standardAllowanceCM = -1
        try rejects("Negative allowance", document: document, settings: invalid)
        invalid = settings; invalid.hemAllowanceCM = .infinity
        try rejects("Nonfinite hem", document: document, settings: invalid)
        invalid = settings
        invalid.setTreatment(.init(kind: .fold), panel: "skirt_front", edge: 1)
        try rejects("Stitched fold", document: document, settings: invalid)
        let curved = try Self.document(curvedLeft: true).0
        try rejects("Curved fold", document: curved, settings: settings)
        invalid = settings
        invalid.panels["skirt_front"]!.grainline!.centerXRatio = 0
        try rejects("Boundary grainline", document: document, settings: invalid)
        invalid = settings
        invalid.panels["skirt_front"]!.grainline!.angleDegrees = .nan
        try rejects("Nonfinite grainline", document: document, settings: invalid)
        let finalEncoding = try encoder.encode(document)
        try require(finalEncoding == sourceEncoded && sourceBytes == originalBytes,
                    "Manufacture export mutated source JSON")
        let officialURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/pencil-skirt.json")
        let officialBytes = try Data(contentsOf: officialURL)
        let official = try GarmentCodePatternFile.validatedImport(from: officialBytes)
        let officialEncoding = try encoder.encode(official)
        var officialSettings = GarmentCodeDraftingSettings()
        // This gate verifies serialization isolation on an official shape,
        // not the separate per-fixture seam-allowance acceptance matrix.
        officialSettings.showNotches = true
        _ = try GarmentCodePDFExporter.data(document: official,
                                           options: .init(format: .fullSize, drafting: officialSettings))
        try require(try encoder.encode(official) == officialEncoding && Data(contentsOf: officialURL) == officialBytes,
                    "Manufacturing export changed official fixture source")
        print("PASS: manufacturing settings -> print plan -> vector PDFs; \(checkedPages) physical pages, variable/fold allowances, unchanged source curves/JSON, paired notch labels, crowding warnings/pairwise omission, white seam badges clear cutting lines, manual grainlines, cut quantities, continuous A4 expanded contours, solid/dashed strokes, calibration and invalid-settings rejection")
        print("Manufacturing PDF QA samples: \(output.path)")
    }
}

private final class ManufacturingVectorScan {
    var transform = CGAffineTransform.identity
    var dashCount = 0
    var fillIsWhite = false
    var fillComponentCount = 1
    var stack: [(CGAffineTransform, Int, Bool, Int)] = []
    var points: [CGPoint] = []
    var pageHeight: CGFloat = 0
    var dashedStrokeCount = 0
    var solidStrokeCount = 0
    var solidBoundsTopDown: [CGRect] = []
    var whiteRectsTopDown: [CGRect] = []
    var hasTenCMSquare = false
    var imageCount = 0
    var resources: CGPDFDictionaryRef?

    func detectSquare(_ p: [CGPoint]) {
        guard p.count == 4 else { return }
        let ten = 10 * GarmentCodePrintPlan.pointsPerCM
        let lengths = (0..<4).map { i in hypot(p[(i + 1) % 4].x - p[i].x, p[(i + 1) % 4].y - p[i].y) }
        if lengths.allSatisfy({ abs($0 - ten) < 0.005 }) { hasTenCMSquare = true }
    }

    static func scan(_ page: CGPDFPage) -> ManufacturingVectorScan {
        let state = ManufacturingVectorScan()
        state.pageHeight = page.getBoxRect(.mediaBox).height
        _ = CGPDFDictionaryGetDictionary(page.dictionary!, "Resources", &state.resources)
        let table = CGPDFOperatorTableCreate()!
        func set(_ name: String, _ callback: @escaping CGPDFOperatorCallback) {
            CGPDFOperatorTableSetCallback(table, name, callback)
        }
        set("q") { _, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            s.stack.append((s.transform, s.dashCount, s.fillIsWhite, s.fillComponentCount))
        }
        set("Q") { _, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            if let restored = s.stack.popLast() {
                s.transform = restored.0; s.dashCount = restored.1; s.fillIsWhite = restored.2
                s.fillComponentCount = restored.3
            }
        }
        set("cm") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var a = CGPDFReal(), b = CGPDFReal(), c = CGPDFReal(), d = CGPDFReal(), x = CGPDFReal(), y = CGPDFReal()
            guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x),
                  CGPDFScannerPopNumber(scanner, &d), CGPDFScannerPopNumber(scanner, &c),
                  CGPDFScannerPopNumber(scanner, &b), CGPDFScannerPopNumber(scanner, &a) else { return }
            s.transform = CGAffineTransform(a: a, b: b, c: c, d: d, tx: x, ty: y).concatenating(s.transform)
        }
        set("d") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var phase = CGPDFReal(), array: CGPDFArrayRef?
            guard CGPDFScannerPopNumber(scanner, &phase), CGPDFScannerPopArray(scanner, &array), let array else { return }
            s.dashCount = CGPDFArrayGetCount(array)
        }
        set("g") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var gray = CGPDFReal()
            if CGPDFScannerPopNumber(scanner, &gray) { s.fillIsWhite = abs(gray - 1) < 1e-6; s.fillComponentCount = 1 }
        }
        set("rg") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var r = CGPDFReal(), g = CGPDFReal(), b = CGPDFReal()
            if CGPDFScannerPopNumber(scanner, &b), CGPDFScannerPopNumber(scanner, &g), CGPDFScannerPopNumber(scanner, &r) {
                s.fillIsWhite = abs(r - 1) < 1e-6 && abs(g - 1) < 1e-6 && abs(b - 1) < 1e-6
                s.fillComponentCount = 3
            }
        }
        set("k") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var c = CGPDFReal(), m = CGPDFReal(), y = CGPDFReal(), k = CGPDFReal()
            if CGPDFScannerPopNumber(scanner, &k), CGPDFScannerPopNumber(scanner, &y),
               CGPDFScannerPopNumber(scanner, &m), CGPDFScannerPopNumber(scanner, &c) {
                s.fillIsWhite = [c, m, y, k].allSatisfy { abs($0) < 1e-6 }
                s.fillComponentCount = 4
            }
        }
        set("cs") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<CChar>?
            if CGPDFScannerPopName(scanner, &name), let name { s.fillComponentCount = s.components(for: String(cString: name)) }
        }
        // CoreGraphics serializes its DeviceGray/DeviceRGB colors through
        // named ColorSpace resources plus `sc`, rather than only `g`/`rg`.
        // Our native exporter uses gray/RGB; include CMYK white for parity
        // with the direct color operators above.
        for name in ["sc", "scn"] {
            set(name) { scanner, info in
                let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
                var values: [CGPDFReal] = [], value = CGPDFReal()
                for _ in 0..<s.fillComponentCount {
                    guard CGPDFScannerPopNumber(scanner, &value) else { s.fillIsWhite = false; return }
                    values.append(value)
                }
                s.fillIsWhite = ((values.count == 1 || values.count == 3) && values.allSatisfy { abs($0 - 1) < 1e-6 }) ||
                    (values.count == 4 && values.allSatisfy { abs($0) < 1e-6 })
            }
        }
        set("re") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var x = CGPDFReal(), y = CGPDFReal(), w = CGPDFReal(), h = CGPDFReal()
            guard CGPDFScannerPopNumber(scanner, &h), CGPDFScannerPopNumber(scanner, &w),
                  CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
            let p = [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y), CGPoint(x: x + w, y: y + h), CGPoint(x: x, y: y + h)]
                .map { $0.applying(s.transform) }
            s.detectSquare(p); s.points += p
        }
        for name in ["m", "l"] {
            set(name) { scanner, info in
                let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
                var x = CGPDFReal(), y = CGPDFReal()
                guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
                s.points.append(CGPoint(x: x, y: y).applying(s.transform))
            }
        }
        set("h") { _, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            s.detectSquare(s.points)
        }
        set("c") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            s.curve(scanner, points: 3)
        }
        for name in ["v", "y"] {
            set(name) { scanner, info in
                let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
                s.curve(scanner, points: 2)
            }
        }
        let stroke: CGPDFOperatorCallback = { _, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            if s.dashCount > 0 { s.dashedStrokeCount += 1 }
            else {
                s.solidStrokeCount += 1
                if let minX = s.points.map(\.x).min(), let maxX = s.points.map(\.x).max(),
                   let minY = s.points.map(\.y).min(), let maxY = s.points.map(\.y).max() {
                    s.solidBoundsTopDown.append(CGRect(x: minX, y: s.pageHeight - maxY,
                                                       width: maxX - minX, height: maxY - minY))
                }
            }
            s.points = []
        }
        for name in ["S", "s", "B", "B*", "b", "b*"] { set(name, stroke) }
        let fill: CGPDFOperatorCallback = { _, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            if s.fillIsWhite, s.points.count == 4,
               let minX = s.points.map(\.x).min(), let maxX = s.points.map(\.x).max(),
               let minY = s.points.map(\.y).min(), let maxY = s.points.map(\.y).max() {
                s.whiteRectsTopDown.append(CGRect(x: minX, y: s.pageHeight - maxY,
                                                  width: maxX - minX, height: maxY - minY))
            }
            s.points = []
        }
        for name in ["f", "F", "f*"] { set(name, fill) }
        set("n") { _, info in Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue().points = [] }
        set("Do") { scanner, info in
            let s = Unmanaged<ManufacturingVectorScan>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name, let resources = s.resources else { return }
            var xobjects: CGPDFDictionaryRef?, stream: CGPDFStreamRef?
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects,
                  CGPDFDictionaryGetStream(xobjects, name, &stream), let stream else { return }
            var subtype: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(CGPDFStreamGetDictionary(stream)!, "Subtype", &subtype),
               let subtype, String(cString: subtype) == "Image" { s.imageCount += 1 }
        }
        let content = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(state).toOpaque())
        _ = CGPDFScannerScan(scanner)
        return state
    }

    private func curve(_ scanner: CGPDFScannerRef, points count: Int) {
        var p: [CGPoint] = []
        for _ in 0..<count {
            var x = CGPDFReal(), y = CGPDFReal()
            guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
            p.append(CGPoint(x: x, y: y).applying(transform))
        }
        points += p.reversed()
    }

    private func components(for name: String) -> Int {
        let counts = ["DeviceGray": 1, "G": 1, "CalGray": 1, "DeviceRGB": 3, "RGB": 3, "CalRGB": 3,
                      "Lab": 3, "DeviceCMYK": 4, "CMYK": 4]
        if let count = counts[name] { return count }
        var spaces: CGPDFDictionaryRef?, direct: UnsafePointer<CChar>?, array: CGPDFArrayRef?
        guard let resources, CGPDFDictionaryGetDictionary(resources, "ColorSpace", &spaces), let spaces else { return 1 }
        if CGPDFDictionaryGetName(spaces, name, &direct), let direct { return counts[String(cString: direct)] ?? 1 }
        guard CGPDFDictionaryGetArray(spaces, name, &array), let array,
              CGPDFArrayGetName(array, 0, &direct), let direct else { return 1 }
        if String(cString: direct) == "ICCBased" {
            var stream: CGPDFStreamRef?, count = CGPDFInteger()
            if CGPDFArrayGetStream(array, 1, &stream), let stream,
               CGPDFDictionaryGetInteger(CGPDFStreamGetDictionary(stream)!, "N", &count) { return count }
        }
        return counts[String(cString: direct)] ?? 1
    }
}
