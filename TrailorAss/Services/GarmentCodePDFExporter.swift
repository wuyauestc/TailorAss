import Foundation
import CoreGraphics
import CoreText

enum GarmentCodePDFFormat: String, CaseIterable, Identifiable {
    case fullSize, a4Tiled
    var id: String { rawValue }
    var title: String { self == .fullSize ? "整张原尺寸 PDF" : "A4 分页拼接 PDF" }
}

struct GarmentCodePDFOptions {
    var format: GarmentCodePDFFormat
    var showSeams: Bool = true
    var drafting: GarmentCodeDraftingSettings = .init()
}

/// Vector-only PDF drawing. Print coordinates are independent of the interactive
/// preview's zoom, pan and selection. One centimetre is always 72 / 2.54 points.
enum GarmentCodePDFExporter {
    private static let cm = GarmentCodePrintPlan.pointsPerCM
    private static let palette: [(Double, Double, Double)] = [
        (0, 0.45, 0.70), (0.80, 0.28, 0), (0, 0.49, 0.35), (0.53, 0.28, 0.65),
        (0.70, 0.09, 0.29), (0, 0.47, 0.55), (0.49, 0.35, 0), (0.22, 0.30, 0.63)
    ]

    enum ExportError: LocalizedError {
        case cannotCreatePDF
        var errorDescription: String? { "无法生成 PDF，请重试或减少款式组件。" }
    }

    static func annotationWarnings(plan: GarmentCodePrintPlan, showSeams: Bool,
                                   stitches: [GarmentCodeStitch]) -> [String] {
        let guide = GarmentCodeSeamGuide(stitches: stitches)
        let badges = showSeams ? seamBadges(plan: plan, guide: guide) : []
        let placed = manufactureTextLayout(plan, badges: badges).count
        let expected = plan.panels.reduce(0) { $0 + $1.markingLabelsCM.count }
        guard placed < expected else { return [] }
        return ["制作文字较密，有 \(expected - placed) 处辅助文字无法安全排入，PDF 将省略这些文字（配对定位文字成对省略），但定位短线仍保留。请按接缝编号复核；可尝试关闭接缝颜色与编号后重新生成。"]
    }

    static func export(document: GarmentCodePatternFile, options: GarmentCodePDFOptions) throws -> URL {
        let pdf = try data(document: document, options: options)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TailorAss-PDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = options.format == .fullSize ? "纸样-整张原尺寸1比1.pdf" : "纸样-A4分页拼接.pdf"
        let url = directory.appendingPathComponent(filename)
        try pdf.write(to: url, options: .atomic)
        return url
    }

    static func data(document: GarmentCodePatternFile, options: GarmentCodePDFOptions) throws -> Data {
        let plan = try GarmentCodePrintPlan(document: document, drafting: options.drafting)
        let size = options.format == .fullSize ? plan.boardSizeCM : GarmentCodePrintPlan.a4SizeCM
        var box = CGRect(origin: .zero, size: CGSize(width: size.width * cm, height: size.height * cm))
        guard let buffer = CFDataCreateMutable(nil, 0), let consumer = CGDataConsumer(data: buffer),
              let context = CGContext(consumer: consumer, mediaBox: &box, [
                kCGPDFContextTitle: plan.includesSeamAllowance ? "TailorAss 原尺寸纸样 - 逐边缝份" : "TailorAss 原尺寸纸样 - 不含缝份",
                kCGPDFContextCreator: "TailorAss"
              ] as CFDictionary) else { throw ExportError.cannotCreatePDF }
        let guide = GarmentCodeSeamGuide(stitches: document.pattern.stitches)
        // A single global annotation layout must be reused by every tile;
        // page-local collision avoidance could move labels in overlap bands.
        let badges = options.showSeams ? seamBadges(plan: plan, guide: guide) : []
        let markTexts = manufactureTextLayout(plan, badges: badges)
        func page(_ draw: () -> Void) {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)
            draw()
            context.restoreGState()
            context.endPDFPage()
        }
        switch options.format {
        case .fullSize:
            page { drawBoard(plan, guide: guide, showSeams: options.showSeams, badges: badges, markTexts: markTexts, context: context) }
        case .a4Tiled:
            page { drawCover(plan, context: context) }
            let marks = registrationMarks(plan)
            for tile in plan.tiles {
                page {
                    drawTile(tile, plan: plan, guide: guide, showSeams: options.showSeams,
                             badges: badges, markTexts: markTexts, marks: marks, context: context)
                }
            }
        }
        context.closePDF()
        let result = buffer as Data
        guard !result.isEmpty else { throw ExportError.cannotCreatePDF }
        return result
    }

    private static func color(_ id: Int) -> CGColor {
        let rgb = palette[id % palette.count]
        return CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    private static func scaled(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * cm, y: rect.minY * cm, width: rect.width * cm, height: rect.height * cm)
    }

    private static func text(_ value: String, in rect: CGRect, size: CGFloat = 9,
                             color: CGColor = CGColor(gray: 0.12, alpha: 1),
                             context: CGContext) {
        // CoreText's cascade supplies Chinese glyphs on both iOS and macOS.
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
        let attributed = NSAttributedString(string: value, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil), nil)
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func drawBoard(_ plan: GarmentCodePrintPlan, guide: GarmentCodeSeamGuide,
                                  showSeams: Bool, badges: [SeamBadge], markTexts: [PrintedMark],
                                  visibleCM: CGRect? = nil, context: CGContext) {
        text("TailorAss · 原尺寸纸样 1:1", in: CGRect(x: cm, y: 0.4 * cm, width: 50 * cm, height: 23),
             size: 16, context: context)
        text("\(boundaryDescription(plan)) · \(plan.panels.count) 个裁片 · 100% 实际大小打印",
             in: CGRect(x: cm, y: 1.25 * cm, width: (plan.boardSizeCM.width - 2) * cm, height: 22), context: context)
        drawCalibration(at: CGPoint(x: plan.calibrationOriginCM.x * cm,
                                    y: plan.calibrationOriginCM.y * cm), note: manufactureNote(plan), context: context)
        for panel in plan.panels {
            if let visibleCM, !panel.boundsCM.union(panel.labelRectCM).insetBy(dx: -1, dy: -1).intersects(visibleCM) { continue }
            context.saveGState()
            context.scaleBy(x: cm, y: cm)
            context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
            context.setLineWidth(0.55 / cm)
            context.setLineDash(phase: 0, lengths: panel.cutPathCM == nil ? [] : [4 / cm, 3 / cm])
            context.addPath(panel.pathCM)
            context.strokePath()
            if showSeams {
                for (index, path) in panel.edgePathsCM.enumerated() {
                    let groups = guide.groups(for: .init(panel: panel.name, edge: index))
                    for (offset, group) in groups.enumerated() {
                        context.setStrokeColor(color(group.id))
                        context.setLineWidth(0.9 / cm)
                        context.setLineDash(phase: CGFloat(offset) * 6 / cm,
                            lengths: groups.count > 1 ? [6 / cm, CGFloat(groups.count - 1) * 6 / cm]
                                : panel.cutPathCM == nil ? [] : [4 / cm, 3 / cm])
                        context.addPath(path)
                        context.strokePath()
                    }
                }
            }
            context.setLineDash(phase: 0, lengths: [])
            context.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
            if let cut = panel.cutPathCM {
                context.setLineWidth(0.85 / cm)
                context.addPath(cut)
                context.strokePath()
            }
            context.setLineWidth(0.6 / cm)
            for mark in panel.markingPathsCM { context.addPath(mark); context.strokePath() }
            context.restoreGState()
            text("\(GarmentCodeChinese.panel(panel.name))\n裁 \(panel.cutQuantity) 片 · \(panel.allowanceSummary)",
                 in: scaled(panel.labelRectCM), size: 10, context: context)
        }
        let visible = visibleCM.map { scaled($0) }
        for mark in markTexts where visible == nil || visible!.intersects(mark.rect) {
            text(mark.text, in: mark.rect, size: 7, context: context)
        }
        for badge in badges where visible == nil || visible!.intersects(badge.rect) {
            drawSeamBadge(badge, context: context)
        }
    }

    private struct SeamBadge { let group: GarmentCodeSeamGuide.Group; let rect: CGRect }
    private struct PrintedMark { let text: String; let rect: CGRect }

    private static func cutLineRegions(_ plan: GarmentCodePrintPlan) -> [CGPath] {
        plan.panels.compactMap { panel in
            var transform = CGAffineTransform(scaleX: cm, y: cm)
            return panel.cutPathCM?.copy(using: &transform)?.copy(
                strokingWithWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 4)
        }
    }

    private static func clearsCutLine(_ rect: CGRect, regions: [CGPath]) -> Bool {
        let box = CGPath(rect: rect.insetBy(dx: -1, dy: -1), transform: nil)
        return !regions.contains { $0.intersects(box, using: .winding) }
    }

    private static func manufactureTextLayout(_ plan: GarmentCodePrintPlan, badges: [SeamBadge]) -> [PrintedMark] {
        // This is global as well: crop the same label on neighboring pages,
        // never recompute its placement relative to a page's visible pieces.
        var occupied = plan.panels.map { scaled($0.labelRectCM) } + badges.map(\.rect)
        occupied.append(scaled(CGRect(origin: plan.calibrationOriginCM, size: CGSize(width: 10, height: 10))))
        let board = scaled(CGRect(origin: .zero, size: plan.boardSizeCM))
        let cutRegions = cutLineRegions(plan)
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 7, nil)
        var output: [PrintedMark] = []
        for panel in plan.panels {
            for label in panel.markingLabelsCM {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: label.text,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                let width = min(160, ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 4)
                let p = CGPoint(x: label.point.x * cm, y: label.point.y * cm)
                let offsets: [CGPoint] = [.zero, .init(x: 0, y: 13), .init(x: 0, y: -13),
                                          .init(x: 12, y: 0), .init(x: -12, y: 0),
                                          .init(x: 0, y: 26), .init(x: 0, y: -26),
                                          // Facing edges share the packing gap;
                                          // allow a nearby label inside its panel
                                          // instead of silently losing one side.
                                          .init(x: 36, y: 0), .init(x: -36, y: 0),
                                          .init(x: 52, y: 0), .init(x: -52, y: 0),
                                          .init(x: 36, y: 13), .init(x: -36, y: 13),
                                          .init(x: 36, y: -13), .init(x: -36, y: -13),
                                          .init(x: 0, y: 39), .init(x: 0, y: -39)]
                let candidates = offsets.map {
                    CGRect(x: p.x - width / 2 + $0.x, y: p.y - 8 + $0.y, width: width, height: 16)
                }
                if let rect = candidates.first(where: { candidate in
                    let centerCM = CGPoint(x: candidate.midX / cm, y: candidate.midY / cm)
                    return board.contains(candidate) && clearsCutLine(candidate, regions: cutRegions) &&
                        !plan.panels.contains(where: { other in
                            other.name != panel.name && (other.cutPathCM ?? other.pathCM).contains(centerCM)
                        }) &&
                        !occupied.contains(where: { $0.intersects(candidate.insetBy(dx: -1, dy: -1)) })
                }) {
                    occupied.append(rect)
                    output.append(.init(text: label.text, rect: rect))
                }
            }
        }
        let pairedTextCounts = Dictionary(grouping: output.filter {
            $0.text.hasPrefix("缝") && ($0.text.hasSuffix("·单") || $0.text.hasSuffix("·双"))
        }, by: \.text).mapValues(\.count)
        // Crowding must not leave an apparently unmatched notch label.
        return output.filter { pairedTextCounts[$0.text].map { $0 == 2 } ?? true }
    }

    private static func seamBadges(plan: GarmentCodePrintPlan, guide: GarmentCodeSeamGuide) -> [SeamBadge] {
        var occupied = plan.panels.map { scaled($0.labelRectCM) }
        occupied.append(scaled(CGRect(origin: plan.calibrationOriginCM, size: CGSize(width: 10, height: 10))))
        let bounds = scaled(CGRect(origin: .zero, size: plan.boardSizeCM))
        let cutRegions = cutLineRegions(plan)
        var badges: [SeamBadge] = []
        for panel in plan.panels {
            for (index, pointCM) in panel.edgeMidpointsCM.enumerated() {
                for group in guide.groups(for: .init(panel: panel.name, edge: index)) {
                    let point = CGPoint(x: pointCM.x * cm, y: pointCM.y * cm)
                    guard let rect = seamBadgeRect(group, at: point, bounds: bounds,
                                                  occupied: occupied, cutRegions: cutRegions) else { continue }
                    occupied.append(rect)
                    badges.append(SeamBadge(group: group, rect: rect))
                }
            }
        }
        return badges
    }

    private static func seamBadgeRect(_ group: GarmentCodeSeamGuide.Group, at point: CGPoint,
                                      bounds: CGRect, occupied: [CGRect], cutRegions: [CGPath]) -> CGRect? {
        let width = CGFloat(group.label.count) * 7 + 6
        let offsets: [CGPoint] = [.init(x: 4, y: -15), .init(x: -width - 4, y: 3),
                                  .init(x: 4, y: 6), .init(x: -width - 4, y: -18),
                                  .init(x: 4, y: -31), .init(x: 4, y: 22)]
        let candidates = offsets.map { CGRect(x: point.x + $0.x, y: point.y + $0.y, width: width, height: 13) }
        return candidates.first(where: { candidate in
            bounds.contains(candidate) && clearsCutLine(candidate, regions: cutRegions) &&
                !occupied.contains(where: { $0.intersects(candidate.insetBy(dx: -1, dy: -1)) })
        })
    }

    private static func drawSeamBadge(_ badge: SeamBadge, context: CGContext) {
        let rect = badge.rect, group = badge.group
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.setStrokeColor(color(group.id))
        context.setLineWidth(0.4)
        context.stroke(rect)
        text(group.label, in: rect.insetBy(dx: 3, dy: 1), size: 7, color: color(group.id), context: context)
    }

    private static func boundaryDescription(_ plan: GarmentCodePrintPlan) -> String {
        plan.includesSeamAllowance
            ? "实线裁剪线 / 虚线原始制版线 · 缝份按边设置（含 0 cm 边）"
            : "不含缝份 · 轮廓为原始制版线，需自行加缝份后裁剪"
    }

    private static func manufactureNote(_ plan: GarmentCodePrintPlan) -> String? {
        guard plan.includesSeamAllowance || plan.includesNotches || plan.panels.contains(where: { !$0.markingPathsCM.isEmpty }) else { return nil }
        return (plan.includesSeamAllowance
            ? "实线为裁剪线，虚线为原始制版线。逐边缝份可能不同，0 cm 边与对折边两线重合。"
            : "未加缝份：轮廓为原始制版线，裁布前需自行补足缝份。") +
            "\n布纹方向由用户手动设置；裁剪数量见片名标注，不自动复制或镜像。" +
            "\n短线仅为定位记号，不改变裁剪边界。请勿剪入原始制版线；未标记或不等长接缝须人工核对。" +
            "\n省道与折边转角须复核，本版未做折省省帽及折边折叠后的修形。先做试样。" +
            "\n密集区域可能省略辅助文字，定位短线保留，请按接缝编号核对。"
    }

    private static func drawCalibration(at origin: CGPoint, note: String? = nil, context: CGContext) {
        let square = CGRect(x: origin.x, y: origin.y, width: 10 * cm, height: 10 * cm)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(0.5)
        context.stroke(square)
        for fraction in [0.0, 0.5, 1.0] {
            let x = square.minX + square.width * fraction, y = square.minY + square.height * fraction
            context.move(to: CGPoint(x: x, y: square.minY - 3))
            context.addLine(to: CGPoint(x: x, y: square.minY + 3))
            context.move(to: CGPoint(x: square.minX - 3, y: y))
            context.addLine(to: CGPoint(x: square.minX + 3, y: y))
        }
        context.strokePath()
        let content = "10 cm × 10 cm\n打印校准框（不属于裁片）\n测量方框边线中心之间的距离" + (note.map { "\n\n" + $0 } ?? "")
        text(content, in: CGRect(x: square.minX + 18, y: note == nil ? square.midY - 30 : square.minY + 18,
                                width: square.width - 36, height: note == nil ? 70 : square.height - 36),
             size: note == nil ? 10 : 8, context: context)
        text("先核对校准框，再裁剪；打印时选择 100% / 实际大小。",
             in: CGRect(x: origin.x - 0.5 * cm, y: square.maxY + 0.2 * cm, width: 11 * cm, height: 26),
             size: 8, context: context)
    }

    private static func drawCover(_ plan: GarmentCodePrintPlan, context: CGContext) {
        let x = cm, w = 19 * cm
        text("A4 拼接纸样 · 打印说明", in: CGRect(x: x, y: 0.7 * cm, width: w, height: 28), size: 18, context: context)
        text("\(plan.rows) 行 × \(plan.columns) 列，共 \(plan.tiles.count) 张拼接页；另含本说明页，共 \(plan.tiles.count + 1) 页。",
             in: CGRect(x: x, y: 1.9 * cm, width: w, height: 18), size: 10, context: context)
        text("选择 A4 纵向、100% / 实际大小，关闭“适合页面”或自动缩放。",
             in: CGRect(x: x, y: 2.6 * cm, width: w, height: 18), size: 10, context: context)
        text(plan.includesSeamAllowance
             ? "实线裁剪线 / 虚线原始制版线。缝份按边设置；省道与折边转角未按折叠状态修形，请先复核试样。"
             : "不含缝份：轮廓是原始制版线，不是已加缝份的裁剪线。请先试样并自行加缝份。",
             in: CGRect(x: x, y: 3.3 * cm, width: w, height: 24), size: 9, context: context)
        text("拼接总览（缩略图，不能直接用于裁剪）", in: CGRect(x: x, y: 4.2 * cm, width: w, height: 20), size: 10, context: context)
        let overview = CGRect(x: x, y: 5 * cm, width: w, height: 10.2 * cm)
        context.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
        context.setLineWidth(0.4)
        context.stroke(overview)
        let factor = min((overview.width - 16) / plan.boardSizeCM.width,
                         (overview.height - 16) / plan.boardSizeCM.height)
        let origin = CGPoint(x: overview.midX - plan.boardSizeCM.width * factor / 2,
                             y: overview.midY - plan.boardSizeCM.height * factor / 2)
        context.saveGState()
        context.clip(to: overview)
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: factor, y: factor)
        context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        context.setLineWidth(0.5 / factor)
        for panel in plan.panels { context.addPath(panel.cutPathCM ?? panel.pathCM); context.strokePath() }
        context.setStrokeColor(CGColor(gray: 0.65, alpha: 1))
        context.stroke(CGRect(origin: plan.calibrationOriginCM, size: CGSize(width: 10, height: 10)))
        for tile in plan.tiles {
            context.setStrokeColor(CGColor(gray: 0.65, alpha: 1))
            context.setLineWidth(0.35 / factor)
            context.setLineDash(phase: 0, lengths: [2 / factor, 2 / factor])
            context.stroke(tile.boardRectCM)
        }
        context.restoreGState()
        for tile in plan.tiles {
            let position = CGPoint(x: origin.x + (tile.boardRectCM.minX + 0.5) * factor,
                                   y: origin.y + (tile.boardRectCM.minY + 0.5) * factor)
            text("\(tile.row + 1)-\(tile.column + 1)", in: CGRect(x: position.x, y: position.y, width: 30, height: 10),
                 size: 6, context: context)
        }
        drawCalibration(at: CGPoint(x: cm, y: 16.8 * cm), note: manufactureNote(plan), context: context)
        text("拼接方法\n\n1. 沿每页的实线边框裁去页边空白。\n2. 按行从左到右，再从上到下排列。\n3. 相邻页重叠 1 cm，对齐同号 G 十字标记与纸样线后粘贴。\n4. 虚线表示重叠带边界，不是裁片线。\n\n先打印本页，核对校准框两边均为 10 cm；尺寸不符时请检查打印缩放设置。",
             in: CGRect(x: 12 * cm, y: 17 * cm, width: 8 * cm, height: 10 * cm), size: 10, context: context)
        text("TailorAss · 打印说明 · 第 1 / \(plan.tiles.count + 1) 页 · 后续拼接页均为原尺寸 1:1",
             in: CGRect(x: cm, y: 28.6 * cm, width: w, height: 18), size: 8, context: context)
    }

    private struct RegistrationMark { let id: Int; let pointCM: CGPoint }

    private static func registrationMarks(_ plan: GarmentCodePrintPlan) -> [RegistrationMark] {
        var points: [CGPoint] = []
        if plan.columns > 1 {
            for row in 0..<plan.rows {
                for column in 1..<plan.columns {
                    for fraction in [0.25, 0.75] {
                        points.append(CGPoint(x: Double(column) * GarmentCodePrintPlan.tileStepCM.width + 0.5,
                                              y: Double(row) * GarmentCodePrintPlan.tileStepCM.height + 26.7 * fraction))
                    }
                }
            }
        }
        if plan.rows > 1 {
            for row in 1..<plan.rows {
                for column in 0..<plan.columns {
                    for fraction in [0.25, 0.75] {
                        points.append(CGPoint(x: Double(column) * GarmentCodePrintPlan.tileStepCM.width + 19 * fraction,
                                              y: Double(row) * GarmentCodePrintPlan.tileStepCM.height + 0.5))
                    }
                }
            }
        }
        return points.enumerated().map { RegistrationMark(id: $0.offset + 1, pointCM: $0.element) }
    }

    private static func drawTile(_ tile: GarmentCodePrintPlan.Tile, plan: GarmentCodePrintPlan,
                                 guide: GarmentCodeSeamGuide, showSeams: Bool,
                                 badges: [SeamBadge], markTexts: [PrintedMark],
                                 marks: [RegistrationMark], context: CGContext) {
        let content = scaled(CGRect(origin: GarmentCodePrintPlan.tilePageOriginCM,
                                    size: GarmentCodePrintPlan.tileWindowSizeCM))
        text("A4 · 拼接页 \(tile.id) / \(plan.tiles.count) · 第 \(tile.row + 1) 行 / 第 \(tile.column + 1) 列",
             in: CGRect(x: cm, y: 0.5 * cm, width: 19 * cm, height: 18), size: 9, context: context)
        text("原尺寸 1:1 · \(plan.includesSeamAllowance ? "实线裁剪 / 虚线制版" : "不含缝份") · 100% 实际大小打印 · 重叠 1 cm",
             in: CGRect(x: cm, y: 1.02 * cm, width: 19 * cm, height: 16), size: 8, context: context)
        context.saveGState()
        context.clip(to: content)
        context.translateBy(x: content.minX - tile.boardRectCM.minX * cm,
                            y: content.minY - tile.boardRectCM.minY * cm)
        drawBoard(plan, guide: guide, showSeams: showSeams, badges: badges, markTexts: markTexts,
                  visibleCM: tile.boardRectCM, context: context)
        for mark in marks where tile.boardRectCM.contains(mark.pointCM) {
            let p = CGPoint(x: mark.pointCM.x * cm, y: mark.pointCM.y * cm)
            context.setStrokeColor(CGColor(gray: 0.3, alpha: 1))
            context.setLineWidth(0.45)
            context.move(to: CGPoint(x: p.x - 5, y: p.y)); context.addLine(to: CGPoint(x: p.x + 5, y: p.y))
            context.move(to: CGPoint(x: p.x, y: p.y - 5)); context.addLine(to: CGPoint(x: p.x, y: p.y + 5))
            context.strokePath()
            text("G\(mark.id)", in: CGRect(x: p.x - 10, y: p.y + 5, width: 24, height: 9), size: 6, context: context)
        }
        context.restoreGState()
        drawTileFrame(tile, plan: plan, content: content, context: context)
        var neighbors: [String] = []
        if tile.column > 0 { neighbors.append("左 \(tile.id - 1)") }
        if tile.column + 1 < plan.columns { neighbors.append("右 \(tile.id + 1)") }
        if tile.row > 0 { neighbors.append("上 \(tile.id - plan.columns)") }
        if tile.row + 1 < plan.rows { neighbors.append("下 \(tile.id + plan.columns)") }
        text("相邻拼接页：\(neighbors.joined(separator: " / "))",
             in: CGRect(x: cm, y: 28.4 * cm, width: 19 * cm, height: 16), size: 8, context: context)
        text("TailorAss · PDF 第 \(tile.id + 1) / \(plan.tiles.count + 1) 页 · 沿实线框去白边，再对齐重叠带",
             in: CGRect(x: cm, y: 28.85 * cm, width: 19 * cm, height: 15), size: 7, context: context)
    }

    private static func drawTileFrame(_ tile: GarmentCodePrintPlan.Tile, plan: GarmentCodePrintPlan,
                                      content: CGRect, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
        context.setLineWidth(0.4)
        context.stroke(content)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
        func vertical(_ x: CGFloat) {
            context.move(to: CGPoint(x: x, y: content.minY)); context.addLine(to: CGPoint(x: x, y: content.maxY))
        }
        func horizontal(_ y: CGFloat) {
            context.move(to: CGPoint(x: content.minX, y: y)); context.addLine(to: CGPoint(x: content.maxX, y: y))
        }
        if tile.column > 0 { vertical(content.minX + cm) }
        if tile.column + 1 < plan.columns { vertical(content.maxX - cm) }
        if tile.row > 0 { horizontal(content.minY + cm) }
        if tile.row + 1 < plan.rows { horizontal(content.maxY - cm) }
        context.strokePath()
        context.restoreGState()
    }
}
