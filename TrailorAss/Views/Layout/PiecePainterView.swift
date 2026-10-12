//
//  PiecePainterView.swift
//  裁缝助手 —— M5 图形画板：铅笔/矩形/椭圆/扇形叠加绘制，自动合并轮廓生成裁片
//

import SwiftUI

/// 图形画板：在 200×200cm 画布上叠加绘制多个图形，
/// 完成时把所有图形栅格化合并，提取整体外轮廓作为一块裁片
struct PiecePainterView: View {
    enum Tool: String, CaseIterable, Identifiable {
        case pencil = "铅笔"
        case rect = "矩形"
        case ellipse = "椭圆"
        case sector = "扇形"
        var id: String { rawValue }
    }

    let onCreated: (PieceShape) -> Void

    /// 逻辑画布边长（cm）
    private let canvasCm: CGFloat = 200
    private let cellSize: CGFloat = 0.5

    @State private var tool: Tool = .pencil
    /// 已提交的图形（多边形顶点，cm，画布坐标）
    @State private var strokes: [[CGPoint]] = []
    /// 进行中的铅笔轨迹（cm）
    @State private var pencilPoints: [CGPoint] = []
    /// 矩形/椭圆拖拽起止点（cm）
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    /// 拖拽中的实时参数读数（显示在画布顶部）
    @State private var liveInfo: String?
    @State private var name = ""

    // 扇形参数
    @State private var sectorRadius: Double = 30
    @State private var sectorStart: Double = 0
    @State private var sectorSweep: Double = 90

    var body: some View {
        VStack(spacing: 12) {
            TextField("裁片名称（如：圆摆裙片）", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Picker("工具", selection: $tool) {
                ForEach(Tool.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if tool == .sector { sectorParamBar }

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let scale = side / canvasCm
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.96, green: 0.92, blue: 0.85))
                    Canvas { ctx, _ in
                        drawGrid(ctx: ctx, scale: scale)
                        drawStrokes(ctx: ctx, scale: scale)
                        drawPreview(ctx: ctx, scale: scale)
                    }
                    if strokes.isEmpty && pencilPoints.isEmpty {
                        Text(hintText)
                            .font(.appBody)
                            .foregroundColor(.appSubText)
                            .multilineTextAlignment(.center)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .top) {
                    if let liveInfo {
                        Text(liveInfo)
                            .font(.appCaption)
                            .foregroundColor(.appText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { dragChanged($0, scale: scale) }
                        .onEnded { dragEnded($0, scale: scale) }
                )
                .onTapGesture { loc in
                    if tool == .sector {
                        placeSector(at: CGPoint(x: loc.x / scale, y: loc.y / scale))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)

            Text(summaryText)
                .font(.appCaption)
                .foregroundColor(.appSubText)

            HStack(spacing: 16) {
                Button("撤销") { _ = strokes.popLast() }
                    .buttonStyle(.bordered)
                    .disabled(strokes.isEmpty)
                Button("清空") { strokes = [] }
                    .buttonStyle(.bordered)
                    .disabled(strokes.isEmpty)
                Button("完成") {
                    guard let shape = buildShape() else { return }
                    onCreated(shape)
                }
                .buttonStyle(.borderedProminent)
                .disabled(strokes.isEmpty)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - 扇形参数条
    private var sectorParamBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                paramField(title: "半径", value: $sectorRadius, unit: "cm")
                paramField(title: "起始角", value: $sectorStart, unit: "°")
                paramField(title: "角度", value: $sectorSweep, unit: "°")
            }
            Text("点按画布放置扇形圆心（0°=向右，顺时针增大）")
                .font(.appCaption)
                .foregroundColor(.appSubText)
        }
        .padding(.horizontal)
    }

    private func paramField(title: String, value: Binding<Double>, unit: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.appCaption)
                .foregroundColor(.appText)
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
            Text(unit)
                .font(.appCaption)
                .foregroundColor(.appSubText)
        }
    }

    private var hintText: String {
        switch tool {
        case .pencil: return "用手指画出闭合轮廓\n（松手自动填充，可继续叠加其他图形）"
        case .rect: return "按住拖出矩形\n（可继续叠加其他图形）"
        case .ellipse: return "按住拖出椭圆/正圆\n（可继续叠加其他图形）"
        case .sector: return "设好半径和角度后\n点按画布放置扇形"
        }
    }

    private var summaryText: String {
        guard !strokes.isEmpty else { return "画布 200 × 200 cm，未绘制" }
        let all = strokes.flatMap { $0 }
        let xs = all.map(\.x), ys = all.map(\.y)
        let w = (xs.max()! - xs.min()!).rounded()
        let h = (ys.max()! - ys.min()!).rounded()
        return "\(strokes.count) 个图形 · 整体约 \(Int(w)) × \(Int(h)) cm"
    }

    // MARK: - 手势处理
    private func clamped(_ cm: CGPoint) -> CGPoint {
        CGPoint(x: min(max(cm.x, 0), canvasCm), y: min(max(cm.y, 0), canvasCm))
    }

    private func dragChanged(_ value: DragGesture.Value, scale: CGFloat) {
        let cm = clamped(CGPoint(x: value.location.x / scale, y: value.location.y / scale))
        switch tool {
        case .pencil:
            pencilPoints.append(cm)
            if pencilPoints.count > 1 {
                let r = bboxRect(pencilPoints)
                liveInfo = String(format: "轨迹约 %.1f × %.1f cm", r.width, r.height)
            }
        case .rect, .ellipse:
            if dragStart == nil {
                dragStart = clamped(CGPoint(x: value.startLocation.x / scale,
                                            y: value.startLocation.y / scale))
            }
            dragCurrent = cm
            if let s = dragStart {
                let r = normalizedRect(s, cm)
                if tool == .rect {
                    liveInfo = String(format: "宽 %.1f × 高 %.1f cm", r.width, r.height)
                } else {
                    liveInfo = String(format: "横向直径 %.1f × 纵向直径 %.1f cm", r.width, r.height)
                }
            }
        case .sector:
            break
        }
    }

    private func dragEnded(_ value: DragGesture.Value, scale: CGFloat) {
        liveInfo = nil
        switch tool {
        case .pencil:
            defer { pencilPoints = [] }
            guard pencilPoints.count >= 8 else { return }
            let simplified = PolylineSimplifier.ramerDouglasPeucker(pencilPoints, epsilon: 0.8)
            guard simplified.count >= 3, bboxArea(simplified) >= 1 else { return }
            strokes.append(simplified)
        case .rect:
            defer { dragStart = nil; dragCurrent = nil }
            guard let s = dragStart, let e = dragCurrent else { return }
            let r = normalizedRect(s, e)
            guard r.width >= 1, r.height >= 1 else { return }
            strokes.append([
                CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)
            ])
        case .ellipse:
            defer { dragStart = nil; dragCurrent = nil }
            guard let s = dragStart, let e = dragCurrent else { return }
            let r = normalizedRect(s, e)
            guard r.width >= 1, r.height >= 1 else { return }
            strokes.append(ellipsePolygon(in: r))
        case .sector:
            break
        }
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func bboxRect(_ pts: [CGPoint]) -> CGRect {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private func bboxArea(_ pts: [CGPoint]) -> CGFloat {
        let r = bboxRect(pts)
        return r.width * r.height
    }

    /// 椭圆 → 48 边形近似
    private func ellipsePolygon(in r: CGRect) -> [CGPoint] {
        (0..<48).map { i in
            let t = 2 * CGFloat.pi * CGFloat(i) / 48
            return CGPoint(x: r.midX + r.width / 2 * cos(t),
                           y: r.midY + r.height / 2 * sin(t))
        }
    }

    /// 扇形 → 多边形（每 3° 一个弧点，不满 360° 时带圆心）
    private func placeSector(at center: CGPoint) {
        let radius = CGFloat(sectorRadius)
        let sweep = min(sectorSweep, 360)
        guard radius >= 1, sweep > 0 else { return }
        var pts: [CGPoint] = []
        if sweep < 360 { pts.append(center) }
        var a: Double = 0
        while a <= sweep {
            let rad = (sectorStart + a) * .pi / 180
            pts.append(CGPoint(x: center.x + radius * cos(rad),
                               y: center.y + radius * sin(rad)))
            a += 3
        }
        strokes.append(pts.map { clamped($0) })
    }

    // MARK: - 画布绘制
    private func drawGrid(ctx: GraphicsContext, scale: CGFloat) {
        var grid = Path()
        var major = Path()
        var cm: CGFloat = 0
        while cm <= canvasCm {
            let p = cm * scale
            let target: Path = (cm.truncatingRemainder(dividingBy: 50) == 0) ? major : grid
            var t = target
            t.move(to: CGPoint(x: p, y: 0)); t.addLine(to: CGPoint(x: p, y: canvasCm * scale))
            t.move(to: CGPoint(x: 0, y: p)); t.addLine(to: CGPoint(x: canvasCm * scale, y: p))
            if cm.truncatingRemainder(dividingBy: 50) == 0 { major = t } else { grid = t }
            cm += 10
        }
        ctx.stroke(grid, with: .color(.gray.opacity(0.12)), lineWidth: 0.5)
        ctx.stroke(major, with: .color(.gray.opacity(0.3)), lineWidth: 0.8)
    }

    private func polygonPath(_ poly: [CGPoint], scale: CGFloat) -> Path {
        var p = Path()
        guard let first = poly.first else { return p }
        p.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
        for pt in poly.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * scale, y: pt.y * scale))
        }
        p.closeSubpath()
        return p
    }

    private func drawStrokes(ctx: GraphicsContext, scale: CGFloat) {
        for poly in strokes {
            let p = polygonPath(poly, scale: scale)
            ctx.fill(p, with: .color(.appAccent.opacity(0.3)))
            ctx.stroke(p, with: .color(.appAccent), lineWidth: 1.5)
        }
    }

    private func drawPreview(ctx: GraphicsContext, scale: CGFloat) {
        // 铅笔进行中：实时轨迹
        if pencilPoints.count > 1 {
            var p = Path()
            p.move(to: CGPoint(x: pencilPoints[0].x * scale, y: pencilPoints[0].y * scale))
            for pt in pencilPoints.dropFirst() {
                p.addLine(to: CGPoint(x: pt.x * scale, y: pt.y * scale))
            }
            ctx.stroke(p, with: .color(.appAccent), lineWidth: 2.5)
        }
        // 矩形/椭圆拖拽中：虚线预览
        if let s = dragStart, let e = dragCurrent {
            let r = normalizedRect(s, e)
            let px = CGRect(x: r.minX * scale, y: r.minY * scale,
                            width: r.width * scale, height: r.height * scale)
            let style = StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            if tool == .rect {
                ctx.stroke(Path(px), with: .color(.appAccent), style: style)
            } else if tool == .ellipse {
                ctx.stroke(Path(ellipseIn: px), with: .color(.appAccent), style: style)
            }
        }
    }

    // MARK: - 生成裁片：栅格化合并 → 提取外轮廓
    private func buildShape() -> PieceShape? {
        guard !strokes.isEmpty else { return nil }
        var board = RasterBoard(fabricWidth: Double(canvasCm),
                                fabricLength: Double(canvasCm), cellSize: cellSize)
        for poly in strokes {
            let shape = PieceShape(name: "", points: poly)
            let box = shape.boundingBox
            let local = PieceShape(name: "", points: poly.map {
                CGPoint(x: $0.x - box.minX, y: $0.y - box.minY)
            })
            PieceStamp(shape: local, cellSize: cellSize)
                .stamp(atCol: Int(box.minX / cellSize), atRow: Int(box.minY / cellSize),
                       board: &board, value: 1)
        }
        let loops = ContourTracer.trace(cells: board.cells, cols: board.cols, rows: board.rows)
        guard let largest = loops.max(by: {
            abs(ContourTracer.signedArea($0)) < abs(ContourTracer.signedArea($1))
        }) else { return nil }
        var cmPts = largest.map { CGPoint(x: $0.x * cellSize, y: $0.y * cellSize) }
        cmPts = PolylineSimplifier.ramerDouglasPeucker(cmPts, epsilon: 0.7)
        guard cmPts.count >= 3 else { return nil }
        let xs = cmPts.map(\.x), ys = cmPts.map(\.y)
        let minX = xs.min()!, minY = ys.min()!
        let normalized = cmPts.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
        return PieceShape(name: name.isEmpty ? "裁片" : name, points: normalized)
    }
}

/// 折线简化（RDP 算法）：把手绘抖动压缩成少量顶点
enum PolylineSimplifier {
    static func ramerDouglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplifyRange(points, first: 0, last: points.count - 1,
                      epsilon: epsilon, keep: &keep)
        return points.enumerated().filter { keep[$0.offset] }.map(\.element)
    }

    private static func simplifyRange(_ points: [CGPoint], first: Int, last: Int,
                                      epsilon: CGFloat, keep: inout [Bool]) {
        guard last > first + 1 else { return }
        var maxDist: CGFloat = 0
        var index = first
        for i in (first + 1)..<last {
            let d = pointToSegmentDistance(points[i], points[first], points[last])
            if d > maxDist {
                maxDist = d
                index = i
            }
        }
        if maxDist > epsilon {
            keep[index] = true
            simplifyRange(points, first: first, last: index, epsilon: epsilon, keep: &keep)
            simplifyRange(points, first: index, last: last, epsilon: epsilon, keep: &keep)
        }
    }

    private static func pointToSegmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx, projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }
}
