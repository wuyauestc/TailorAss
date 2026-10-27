import Foundation
import CoreGraphics

/// A physical-centimetre, read-only print layout. No preview zoom, 3D placement,
/// fabric packing or garment calculation enters this model. Optional manufacture
/// paths are derived separately; original curves and stitch IDs stay intact.
struct GarmentCodePrintPlan {
    static let pointsPerCM: Double = 72 / 2.54
    static let a4SizeCM = CGSize(width: 21, height: 29.7)
    static let tileWindowSizeCM = CGSize(width: 19, height: 26.7)
    static let tilePageOriginCM = CGPoint(x: 1, y: 1.5)
    static let tileOverlapCM: Double = 1
    static let tileStepCM = CGSize(width: 18, height: 25.7)

    struct Panel {
        let name: String
        /// Board coordinates, with positive y downwards. Units are centimetres.
        let pathCM: CGPath
        let edgePathsCM: [CGPath]
        let edgeMidpointsCM: [CGPoint]
        let boundsCM: CGRect
        let labelRectCM: CGRect
        let cutPathCM: CGPath?
        let markingPathsCM: [CGPath]
        let markingLabelsCM: [GarmentCodeManufacturingMarks.Label]
        let cutQuantity: Int
        let allowanceSummary: String
    }

    struct Tile: Identifiable {
        let id: Int
        let row: Int
        let column: Int
        let boardRectCM: CGRect
    }

    let boardSizeCM: CGSize
    let panels: [Panel]
    let calibrationOriginCM: CGPoint
    let columns: Int
    let rows: Int
    let tiles: [Tile]
    let warnings: [String]
    let includesSeamAllowance: Bool
    let includesNotches: Bool

    enum PrintError: LocalizedError {
        case invalidGeometry
        case tooLarge
        case tooManyPages

        var errorDescription: String? {
            switch self {
            case .invalidGeometry: "裁片轮廓或尺寸无效，无法生成打印纸样。"
            case .tooLarge: "纸样排版尺寸过大（单边最多 500 cm），请减少裁片或调整尺寸。"
            case .tooManyPages: "A4 拼接超过 200 页，请减少裁片或调整尺寸后导出。"
            }
        }
    }

    init(document: GarmentCodePatternFile, drafting: GarmentCodeDraftingSettings = .init()) throws {
        try document.validateForPreview()
        try drafting.validate(document: document)
        let geometry = try document.geometryPanels()
        guard !geometry.isEmpty else { throw PrintError.invalidGeometry }
        var seen: Set<String> = []
        let names = ((document.pattern.panelOrder ?? []) + geometry.keys.sorted())
            .filter { geometry[$0] != nil && seen.insert($0).inserted }

        var collectedWarnings: [String] = []
        var rawPanels = try names.map { name -> RawPanel in
            guard let source = geometry[name], let anchor = source.edges.first?.start else {
                throw PrintError.invalidGeometry
            }
            // Rebase before CoreGraphics evaluation to avoid large, irrelevant
            // source translations degrading a small pattern's local precision.
            let edges = source.edges.map { $0.translated(by: anchor * -1) }
            let outline = CGMutablePath()
            var paths: [CGPath] = []
            var midpoints: [CGPoint] = []
            for (index, edge) in edges.enumerated() {
                if index == 0 { outline.move(to: try Self.cgPoint(edge.start)) }
                try Self.append(edge, to: outline)
                let path = CGMutablePath()
                path.move(to: try Self.cgPoint(edge.start))
                try Self.append(edge, to: path)
                paths.append(path)
                midpoints.append(try Self.cgPoint(edge.point(at: 0.5)))
            }
            outline.closeSubpath()
            let bounds = outline.boundingBoxOfPath
            guard Self.valid(bounds), bounds.width > 0, bounds.height > 0 else {
                throw PrintError.invalidGeometry
            }
            guard bounds.width <= 500, bounds.height <= 500 else { throw PrintError.tooLarge }
            let treatments = edges.indices.map { drafting.treatment(panel: name, edge: $0, stitches: document.pattern.stitches) }
            let widths = treatments.map { drafting.addSeamAllowance ? drafting.widthCM(for: $0) : 0 }
            let folds = Set(treatments.indices.filter { treatments[$0].kind == .fold })
            let cut: CGPath?
            do {
                if drafting.addSeamAllowance || !folds.isEmpty {
                    let result = try GarmentCodeSeamAllowance.build(seamPath: outline, edgePaths: paths,
                                                                  widthsCM: widths, foldEdges: folds)
                    cut = drafting.addSeamAllowance ? result.cutPath : nil
                    collectedWarnings += result.warnings.map { "\(GarmentCodeChinese.panel(name))：\($0)" }
                } else { cut = nil }
                let localPanel = GarmentCodePanelGeometry(id: name, label: source.label, edges: edges)
                let marks: GarmentCodeManufacturingMarks.Result
                if drafting.showNotches || drafting.panelSettings(name).grainline != nil || !folds.isEmpty {
                    marks = try GarmentCodeManufacturingMarks.build(panelName: name, panel: localPanel,
                        seamPath: outline, cutPath: cut, settings: drafting, geometry: geometry,
                        stitches: document.pattern.stitches)
                } else {
                    marks = .init(paths: [], labels: [], warnings: [])
                }
                collectedWarnings += marks.warnings.map { "\(GarmentCodeChinese.panel(name))：\($0)" }
                let combined = cut.map { bounds.union($0.boundingBoxOfPath) } ?? bounds
                guard Self.valid(combined), combined.width <= 500, combined.height <= 500 else { throw PrintError.tooLarge }
                let uniqueWidths = Set(widths).sorted()
                let summary = drafting.addSeamAllowance
                    ? "缝份 \(uniqueWidths.map { $0.formatted(.number.precision(.fractionLength(0...2))) }.joined(separator: "/")) cm（按边）"
                    : "不含缝份"
                return RawPanel(name: name, path: outline, edges: paths,
                    midpoints: midpoints, bounds: combined, cutPath: cut, markingPaths: marks.paths,
                    markingLabels: marks.labels, cutQuantity: drafting.panelSettings(name).cutQuantity,
                    allowanceSummary: summary)
            } catch {
                throw GarmentCodeDraftingSettings.ValidationError.invalid("“\(GarmentCodeChinese.panel(name))”：\(error.localizedDescription)")
            }
        }

        // A matching guide is useful only when it exists on both physical
        // sides. Never leave a one-sided automatic notch after local clipping.
        func isNotchLabel(_ label: String) -> Bool {
            label.hasPrefix("缝") && (label.hasSuffix("·单") || label.hasSuffix("·双"))
        }
        var matchingPanels: [String: Set<String>] = [:]
        for panel in rawPanels {
            guard panel.markingPaths.count == panel.markingLabels.count else { throw PrintError.invalidGeometry }
            for label in panel.markingLabels where isNotchLabel(label.text) {
                matchingPanels[label.text, default: []].insert(panel.name)
            }
        }
        for index in rawPanels.indices {
            let pairs = zip(rawPanels[index].markingPaths, rawPanels[index].markingLabels).filter { _, label in
                !isNotchLabel(label.text) || matchingPanels[label.text]?.count == 2
            }
            rawPanels[index].markingPaths = pairs.map { $0.0 }
            rawPanels[index].markingLabels = pairs.map { $0.1 }
        }
        for key in matchingPanels.keys.sorted() where matchingPanels[key]?.count != 2 {
            collectedWarnings.append("\(key) 未能在两侧可靠生成，已同时省略，请人工核对定位。")
        }

        if drafting.addSeamAllowance, document.pattern.stitches.contains(where: {
            $0.sides.count == 2 && $0.sides[0].panel == $0.sides[1].panel
        }) {
            collectedWarnings.append("同片省道边默认不加缝份；本版不做折省后的省帽修形，正式裁布前须复核并试样。")
        }

        // A 12 x 14 cm calibration/legend slot is the first shelf item. Unlike
        // a full-width calibration header, this does not waste an entire row.
        calibrationOriginCM = CGPoint(x: 2, y: 4)
        let outerMargin: CGFloat = 1
        let gap: CGFloat = 2
        let labelHeight: CGFloat = 2.2
        let labelGap: CGFloat = 0.35
        let layoutWidth = max(80, (rawPanels.map { max(12, $0.bounds.width) }.max() ?? 0) + 2 * outerMargin)
        var cursor = CGPoint(x: outerMargin + 12 + gap, y: 3)
        var shelfHeight: CGFloat = 14
        var right: CGFloat = outerMargin + 12
        var bottom: CGFloat = 17
        var placed: [Panel] = []

        for raw in rawPanels {
            let slotWidth = max(12, raw.bounds.width)
            let slotHeight = raw.bounds.height + labelGap + labelHeight
            if cursor.x + slotWidth > layoutWidth - outerMargin + 1e-9,
               cursor.x > outerMargin {
                cursor.x = outerMargin
                cursor.y += shelfHeight + gap
                shelfHeight = 0
            }
            let pieceX = cursor.x + (slotWidth - raw.bounds.width) / 2
            var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                              tx: pieceX - raw.bounds.minX,
                                              ty: cursor.y + raw.bounds.maxY)
            guard let path = raw.path.copy(using: &transform) else { throw PrintError.invalidGeometry }
            let edgePaths = try raw.edges.map { edge -> CGPath in
                guard let result = edge.copy(using: &transform) else { throw PrintError.invalidGeometry }
                return result
            }
            let cut = raw.cutPath?.copy(using: &transform)
            let marks = try raw.markingPaths.map { mark -> CGPath in
                guard let result = mark.copy(using: &transform) else { throw PrintError.invalidGeometry }
                return result
            }
            let bounds = raw.bounds.applying(transform)
            let label = CGRect(x: cursor.x, y: cursor.y + raw.bounds.height + labelGap,
                               width: slotWidth, height: labelHeight)
            guard Self.valid(bounds), Self.valid(label) else { throw PrintError.invalidGeometry }
            placed.append(Panel(name: raw.name, pathCM: path, edgePathsCM: edgePaths,
                                edgeMidpointsCM: raw.midpoints.map { $0.applying(transform) },
                                boundsCM: bounds, labelRectCM: label, cutPathCM: cut,
                                markingPathsCM: marks,
                                markingLabelsCM: raw.markingLabels.map {
                                    .init(text: $0.text, point: $0.point.applying(transform))
                                }, cutQuantity: raw.cutQuantity, allowanceSummary: raw.allowanceSummary))
            right = max(right, cursor.x + slotWidth)
            bottom = max(bottom, cursor.y + slotHeight)
            shelfHeight = max(shelfHeight, slotHeight)
            cursor.x += slotWidth + gap
        }
        let size = CGSize(width: right + outerMargin, height: bottom + outerMargin)
        guard size.width.isFinite, size.height.isFinite, size.width <= 500, size.height <= 500 else {
            throw PrintError.tooLarge
        }
        let columns = Self.tileCount(length: size.width, window: Self.tileWindowSizeCM.width,
                                     step: Self.tileStepCM.width)
        let rows = Self.tileCount(length: size.height, window: Self.tileWindowSizeCM.height,
                                  step: Self.tileStepCM.height)
        guard columns <= 200, rows <= 200, columns * rows <= 200 else { throw PrintError.tooManyPages }
        boardSizeCM = size
        panels = placed
        self.columns = columns
        self.rows = rows
        tiles = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                Tile(id: row * columns + column + 1, row: row, column: column,
                     boardRectCM: CGRect(origin: CGPoint(x: CGFloat(column) * Self.tileStepCM.width,
                                                         y: CGFloat(row) * Self.tileStepCM.height),
                                         size: Self.tileWindowSizeCM))
            }
        }
        warnings = Array(NSOrderedSet(array: collectedWarnings)) as? [String] ?? collectedWarnings
        includesSeamAllowance = drafting.addSeamAllowance
        includesNotches = drafting.showNotches
    }

    private struct RawPanel {
        let name: String
        let path: CGPath
        let edges: [CGPath]
        let midpoints: [CGPoint]
        let bounds: CGRect
        let cutPath: CGPath?
        var markingPaths: [CGPath]
        var markingLabels: [GarmentCodeManufacturingMarks.Label]
        let cutQuantity: Int
        let allowanceSummary: String
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite &&
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
    }

    private static func cgPoint(_ point: GarmentCodePoint) throws -> CGPoint {
        guard point.x.isFinite, point.y.isFinite else { throw PrintError.invalidGeometry }
        return CGPoint(x: point.x, y: point.y)
    }

    /// A tiny numerical overshoot at an exact tile boundary must not add a
    /// mostly blank page. The tolerance is under a nanometre in model units.
    private static func tileCount(length: CGFloat, window: CGFloat, step: CGFloat) -> Int {
        max(1, Int(ceil(max(0, length - window) / step - 1e-10)) + 1)
    }

    private static func append(_ edge: GarmentCodeGeometryEdge, to path: CGMutablePath) throws {
        let end = try cgPoint(edge.end)
        guard let curve = edge.curvature else { path.addLine(to: end); return }
        let chord = edge.end - edge.start
        func control(_ value: [Double]) throws -> CGPoint {
            guard value.count == 2 else { throw PrintError.invalidGeometry }
            return try cgPoint(edge.start + chord * value[0] + chord.leftNormal * value[1])
        }
        switch curve.type {
        case "quadratic":
            guard let first = curve.params?.first else { throw PrintError.invalidGeometry }
            path.addQuadCurve(to: end, control: try control(first))
        case "cubic":
            guard let values = curve.params, values.count == 2 else { throw PrintError.invalidGeometry }
            path.addCurve(to: end, control1: try control(values[0]), control2: try control(values[1]))
        case "circle":
            guard let circle = curve.circle else { throw PrintError.invalidGeometry }
            let distance = chord.length
            let radius = max(circle.radius, distance / 2)
            guard distance.isFinite, distance > 1e-12, radius.isFinite, radius > 0 else {
                throw PrintError.invalidGeometry
            }
            let squaredHeight = radius * radius - distance * distance / 4
            guard squaredHeight.isFinite else { throw PrintError.invalidGeometry }
            let height = sqrt(max(0, squaredHeight))
            let sign = circle.largeArc == circle.right ? -1.0 : 1.0
            let center = (edge.start + edge.end) * 0.5 + chord.normalized.leftNormal * (height * sign)
            let startAngle = atan2(edge.start.y - center.y, edge.start.x - center.x)
            let endAngle = atan2(edge.end.y - center.y, edge.end.x - center.x)
            var delta = endAngle - startAngle
            if circle.right {
                while delta < 0 { delta += 2 * .pi }
                while delta >= 2 * .pi { delta -= 2 * .pi }
            } else {
                while delta > 0 { delta -= 2 * .pi }
                while delta <= -2 * .pi { delta += 2 * .pi }
            }
            if abs(delta) != .pi && (abs(delta) > .pi) != circle.largeArc {
                delta += circle.right ? -2 * .pi : 2 * .pi
            }
            path.addArc(center: try cgPoint(center), radius: radius,
                        startAngle: startAngle, endAngle: startAngle + delta,
                        clockwise: delta < 0)
        default:
            throw PrintError.invalidGeometry
        }
    }
}
