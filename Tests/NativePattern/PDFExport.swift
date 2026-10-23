import Foundation
import CoreGraphics
import PDFKit

/// Exercises the same vector PDF renderer used by the iOS export screen.
@main
struct GarmentCodePDFExportRegression {
    enum Failure: LocalizedError {
        case check(String)
        var errorDescription: String? {
            switch self { case let .check(message): return message }
        }
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure.check(message) }
    }

    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let output = ProcessInfo.processInfo.environment["GARMENTCODE_PDF_OUTPUT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent(
            "TailorAssPDFRegression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let squareObject: [String: Any] = [
            "pattern": ["panels": ["skirt_front": [
                "vertices": [[0, 0], [10, 0], [10, 10], [0, 10]],
                "edges": [["endpoints": [0, 1]], ["endpoints": [1, 2]],
                          ["endpoints": [2, 3]], ["endpoints": [3, 0]]]
            ]], "stitches": [[["panel": "skirt_front", "edge": 0],
                               ["panel": "skirt_front", "edge": 2]]]],
            "properties": ["units_in_meter": 100, "curvature_coords": "relative"]
        ]
        let square = try GarmentCodePatternFile.validatedImport(from:
            JSONSerialization.data(withJSONObject: squareObject))
        let pants = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            root.appendingPathComponent("Fixtures/pants.json")))
        let skirt = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
            root.appendingPathComponent("Fixtures/pencil-skirt.json")))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var checkedPages = 0
        for (name, document) in [("square", square), ("pants", pants), ("pencil-skirt", skirt)] {
            let before = try encoder.encode(document)
            let plan = try GarmentCodePrintPlan(document: document)
            for format in [GarmentCodePDFFormat.fullSize, .a4Tiled] {
                let options = GarmentCodePDFOptions(format: format, showSeams: true)
                let data = try GarmentCodePDFExporter.data(document: document, options: options)
                if name != "pencil-skirt" {
                    let filename = name + (format == .fullSize ? "-full-size.pdf" : "-a4-tiled.pdf")
                    try data.write(to: output.appendingPathComponent(filename), options: .atomic)
                }
                let pdf = try checkedDocument(data)
                let cg = CGPDFDocument(CGDataProvider(data: data as CFData)!)!
                let expectedCount = format == .fullSize ? 1 : plan.tiles.count + 1
                try require(pdf.pageCount == expectedCount && cg.numberOfPages == expectedCount,
                            "\(name) \(format): wrong PDF page count")
                for index in 0..<pdf.pageCount {
                    let page = pdf.page(at: index)!
                    let box = page.bounds(for: .mediaBox)
                    let widthCM = format == .fullSize ? plan.boardSizeCM.width : 21
                    let heightCM = format == .fullSize ? plan.boardSizeCM.height : 29.7
                    try require(abs(box.width - widthCM * GarmentCodePrintPlan.pointsPerCM) < 0.002,
                                "\(name) page \(index + 1): physical page width changed")
                    try require(abs(box.height - heightCM * GarmentCodePrintPlan.pointsPerCM) < 0.002,
                                "\(name) page \(index + 1): physical page height changed")
                    try require(page.rotation == 0, "PDF must not rely on page rotation")
                    let scan = VectorScan.scan(cg.page(at: index + 1)!)
                    try require(scan.strokeCount > 0, "\(name) page \(index + 1): missing vector outlines")
                    try require(scan.imageCount == 0, "\(name) page \(index + 1): paper patterns were rasterized")
                    if index == 0 {
                        try require(scan.hasTenCMSquare,
                                    "\(name) \(format): missing physically accurate 10 cm vector calibration square; rectangles \(scan.rectangles)")
                    }
                    if format == .a4Tiled && index > 0 {
                        let tile = plan.tiles[index - 1]
                        let text = page.string ?? ""
                        try require(text.contains("第 \(tile.row + 1) 行") && text.contains("第 \(tile.column + 1) 列"),
                                    "\(name) tile \(tile.id): missing row/column assembly labels")
                        try require(text.contains("拼接页 \(tile.id) / \(plan.tiles.count)"),
                                    "\(name) tile \(tile.id): missing unambiguous tile number")
                        try require(text.contains("PDF 第 \(index + 1)") && text.contains("相邻拼接页"),
                                    "\(name) tile \(tile.id): missing footer or neighbor labels")
                    }
                }
                let text = pdf.string ?? ""
                try require(text.contains("不含缝份"), "\(name) \(format): missing no-seam-allowance warning")
                try require(text.contains("100%"), "\(name) \(format): missing actual-size printing instruction")
                try require(text.contains("1:1") || text.contains("原尺寸"), "Missing physical-scale information")
                checkedPages += pdf.pageCount
            }
            let after = try encoder.encode(document)
            try require(after == before, "PDF export mutated original pattern JSON")
        }

        let cleanData = try GarmentCodePDFExporter.data(document: square,
            options: .init(format: .fullSize, showSeams: false))
        let cleanPDF = try checkedDocument(cleanData)
        let cleanCG = CGPDFDocument(CGDataProvider(data: cleanData as CFData)!)!
        try require(VectorScan.scan(cleanCG.page(at: 1)!).strokeCount > 0,
                    "Hiding seam numbers must not remove the paper-pattern outlines")
        let cleanText = cleanPDF.string ?? ""
        try require(!cleanText.contains("缝1") && !cleanText.contains("缝 1"),
                    "Disabling seam annotations still emitted seam number 1")
        let exported = try GarmentCodePDFExporter.export(document: square,
            options: .init(format: .fullSize, showSeams: false))
        try require(exported.pathExtension.lowercased() == "pdf", "Export did not return a shareable PDF URL")
        _ = try checkedDocument(Data(contentsOf: exported))
        print("PASS: vector PDF export; \(checkedPages) pages across square, pants and pencil skirt; true-size MediaBoxes, 10 cm calibration, A4 assembly labels, no rasterized patterns, clean-outline option and unchanged JSON")
        print("PDF QA samples: \(output.path)")
    }

    static func checkedDocument(_ data: Data) throws -> PDFDocument {
        try require(data.starts(with: Array("%PDF-".utf8)), "Output is not a PDF")
        guard let document = PDFDocument(data: data), document.pageCount > 0,
              !document.isEncrypted else { throw Failure.check("Cannot reopen generated PDF") }
        return document
    }
}

/// Parses page content instead of trusting a screenshot or textual scale claim.
/// The calibration rectangle must measure exactly 10 cm after all `cm`
/// transformations, and paper outlines must remain stroked vectors.
private final class VectorScan {
    var transform = CGAffineTransform.identity
    var stack: [CGAffineTransform] = []
    var strokeCount = 0
    var imageCount = 0
    var hasTenCMSquare = false
    var rectangles: [CGSize] = []
    var subpath: [CGPoint] = []
    var resources: CGPDFDictionaryRef?

    static func scan(_ page: CGPDFPage) -> VectorScan {
        let result = VectorScan()
        _ = CGPDFDictionaryGetDictionary(page.dictionary!, "Resources", &result.resources)
        let table = CGPDFOperatorTableCreate()!
        func set(_ name: String, _ callback: @escaping CGPDFOperatorCallback) {
            CGPDFOperatorTableSetCallback(table, name, callback)
        }
        set("q") { _, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            state.stack.append(state.transform)
        }
        set("Q") { _, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            state.transform = state.stack.popLast() ?? .identity
        }
        set("cm") { scanner, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            var a = CGPDFReal(), b = CGPDFReal(), c = CGPDFReal()
            var d = CGPDFReal(), x = CGPDFReal(), y = CGPDFReal()
            guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x),
                  CGPDFScannerPopNumber(scanner, &d), CGPDFScannerPopNumber(scanner, &c),
                  CGPDFScannerPopNumber(scanner, &b), CGPDFScannerPopNumber(scanner, &a) else { return }
            state.transform = CGAffineTransform(a: a, b: b, c: c, d: d, tx: x, ty: y)
                .concatenating(state.transform)
        }
        set("re") { scanner, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            var x = CGPDFReal(), y = CGPDFReal(), width = CGPDFReal(), height = CGPDFReal()
            guard CGPDFScannerPopNumber(scanner, &height), CGPDFScannerPopNumber(scanner, &width),
                  CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
            let t = state.transform
            let actualWidth = abs(width) * hypot(t.a, t.b)
            let actualHeight = abs(height) * hypot(t.c, t.d)
            state.rectangles.append(CGSize(width: actualWidth, height: actualHeight))
            let tenCM = 10 * GarmentCodePrintPlan.pointsPerCM
            if abs(actualWidth - tenCM) < 0.005 && abs(actualHeight - tenCM) < 0.005 {
                state.hasTenCMSquare = true
            }
        }
        set("m") { scanner, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            var x = CGPDFReal(), y = CGPDFReal()
            guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
            state.subpath = [CGPoint(x: x, y: y).applying(state.transform)]
        }
        set("l") { scanner, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            var x = CGPDFReal(), y = CGPDFReal()
            guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
            state.subpath.append(CGPoint(x: x, y: y).applying(state.transform))
        }
        set("h") { _, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            // CoreGraphics may serialize stroke(CGRect) as m/l/l/l/h rather
            // than `re`, especially under its top-down drawing transform.
            guard state.subpath.count == 4 else { return }
            let p = state.subpath
            let widths = (0..<4).map { index in
                hypot(p[(index + 1) % 4].x - p[index].x, p[(index + 1) % 4].y - p[index].y)
            }
            let tenCM = 10 * GarmentCodePrintPlan.pointsPerCM
            let a = CGVector(dx: p[1].x - p[0].x, dy: p[1].y - p[0].y)
            let b = CGVector(dx: p[2].x - p[1].x, dy: p[2].y - p[1].y)
            if widths.allSatisfy({ abs($0 - tenCM) < 0.005 }), abs(a.dx * b.dx + a.dy * b.dy) < 0.01 {
                state.hasTenCMSquare = true
            }
        }
        for name in ["c", "v", "y"] {
            set(name) { _, info in
                Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue().subpath = []
            }
        }
        let stroke: CGPDFOperatorCallback = { _, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            state.strokeCount += 1
            state.subpath = []
        }
        for name in ["S", "s", "B", "B*", "b", "b*"] { set(name, stroke) }
        set("Do") { scanner, info in
            let state = Unmanaged<VectorScan>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name, let resources = state.resources else { return }
            var xobjects: CGPDFDictionaryRef?
            var stream: CGPDFStreamRef?
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects,
                  CGPDFDictionaryGetStream(xobjects, name, &stream), let stream else { return }
            var subtype: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(CGPDFStreamGetDictionary(stream)!, "Subtype", &subtype),
               let subtype, String(cString: subtype) == "Image" { state.imageCount += 1 }
        }
        let content = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(result).toOpaque())
        _ = CGPDFScannerScan(scanner)
        return result
    }
}
