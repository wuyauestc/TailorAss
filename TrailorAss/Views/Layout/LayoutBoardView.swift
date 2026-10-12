//
//  LayoutBoardView.swift
//  裁缝助手 —— M5a 布料排料画板（手绘/尺寸裁片 + 拖动碰撞 + 旋转 + 导出）
//

import SwiftUI

// MARK: - 主页面
struct LayoutBoardView: View {
    @StateObject private var vm = LayoutBoardViewModel()
    @State private var showFabricSizeSheet = false
    @State private var showPieceInputSheet = false
    @State private var exportImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            boardCanvas
            statsBar
            libraryBar
            toolbar
        }
        .appBackground()
        .navigationTitle("布料排料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFabricSizeSheet = true
                } label: {
                    Label("布料尺寸", systemImage: "ruler")
                        .foregroundColor(.appAccent)
                }
            }
        }
        .sheet(isPresented: $showFabricSizeSheet) {
            FabricSizeSheet(vm: vm)
        }
        .sheet(isPresented: $showPieceInputSheet) {
            PieceInputSheet { shape in
                vm.library.append(shape)
                _ = vm.autoPlace(shape: shape)
            }
            .presentationDetents([.large])
        }
        .alert("导出成功", isPresented: .constant(exportImage != nil)) {
            Button("好") { exportImage = nil }
        } message: {
            Text("排料图已保存到相册")
        }
    }

    // MARK: 画布
    private var boardCanvas: some View {
        LayoutCanvasView(vm: vm)
            .frame(maxHeight: .infinity)
            .clipped()
    }

    // MARK: 统计条
    private var statsBar: some View {
        HStack(spacing: 16) {
            Label("已排 \(vm.placedCount) 片", systemImage: "square.on.square")
            Label("用布 \(Int(vm.usedLength.rounded(.up))) cm", systemImage: "ruler")
            Spacer()
            Text("余料 \(vm.leftoverPercent)%")
                .foregroundColor(.appSubText)
        }
        .font(.appCaption)
        .foregroundColor(.appText)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: 裁片库
    private var libraryBar: some View {
        Group {
            if !vm.library.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.library) { shape in
                            Button {
                                _ = vm.autoPlace(shape: shape)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(shape.name)
                                        .font(.appCaption)
                                        .fontWeight(.medium)
                                    let box = shape.boundingBox
                                    Text("\(Int(box.width))×\(Int(box.height))cm")
                                        .font(.system(size: 10))
                                        .foregroundColor(.appSubText)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.appCard)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.appAccent, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: 工具条
    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                showPieceInputSheet = true
            } label: {
                Label("添加裁片", systemImage: "plus.circle.fill")
                    .font(.appBody)
                    .foregroundColor(.appAccent)
            }
            .buttonStyle(.borderedProminent)

            if vm.selectedPieceID != nil {
                Button {
                    _ = vm.rotateSelected(by: -15)
                } label: {
                    Image(systemName: "rotate.left")
                }
                Button {
                    _ = vm.rotateSelected(by: 15)
                } label: {
                    Image(systemName: "rotate.right")
                }
                Button {
                    vm.duplicateSelected()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    vm.deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
            }

            Spacer()

            Button {
                exportToPhotos()
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.appBody)
                    .foregroundColor(.appAccent)
            }
            .disabled(vm.placedPieces.isEmpty)
        }
        .buttonStyle(.bordered)
        .tint(.appAccent)
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: 导出 PNG 到相册
    private func exportToPhotos() {
        let scale: CGFloat = 4 // 4 px/cm
        let width = vm.fabricWidth * scale
        let height = vm.fabricLength * scale
        let renderer = ImageRenderer(content: FabricExportView(vm: vm))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        guard let ui = renderer.uiImage else { return }
        UIImageWriteToSavedPhotosAlbum(ui, nil, nil, nil)
        exportImage = ui
    }
}

// MARK: - 画布（缩放/平移/拖动裁片/碰撞提示）
struct LayoutCanvasView: View {
    @ObservedObject var vm: LayoutBoardViewModel

    // 视口状态
    @State private var scale: CGFloat = 1.0      // 基础适配后的缩放
    @State private var baseScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    // 拖动状态
    @State private var panLast: CGPoint?
    @State private var draggingPieceID: UUID?
    @State private var dragStartAnchor: CGPoint?
    @State private var dragStartLocation: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let s = fitScale * scale
            Canvas { ctx, _ in
                drawFabric(ctx: &ctx, scale: s)
                drawPieces(ctx: &ctx, scale: s)
            }
            .overlay(alignment: .top) {
                if let candidate = vm.dragCandidate {
                    Text(String(format: "距左边 %.1f cm · 距上边 %.1f cm",
                                candidate.anchor.x, candidate.anchor.y))
                        .font(.appCaption)
                        .foregroundColor(vm.dragCandidateValid ? .appText : .red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(scale: s))
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(baseScale * value, 0.5), 6)
                    }
                    .onEnded { _ in baseScale = scale }
            )
            .onAppear {
                viewSize = geo.size
                resetView()
            }
            .onChange(of: geo.size) { _, newSize in
                viewSize = newSize
                resetView()
            }
            .onChange(of: vm.fabricWidth) { _, _ in resetView() }
            .onChange(of: vm.fabricLength) { _, _ in resetView() }
        }
    }

    private var fitScale: CGFloat {
        let sw = viewSize.width == 0 ? 1 : viewSize.width / CGFloat(vm.fabricWidth + 20)
        let sh = viewSize.height == 0 ? 1 : viewSize.height / CGFloat(vm.fabricLength + 20)
        return min(sw, sh)
    }

    private func resetView() {
        baseScale = 1
        scale = 1
        offset = .zero
    }

    /// 布料左上角在画布中的位置（居中 + 平移）
    private func origin(scale s: CGFloat) -> CGPoint {
        let w = CGFloat(vm.fabricWidth) * s
        let h = CGFloat(vm.fabricLength) * s
        return CGPoint(x: (viewSize.width - w) / 2 + offset.width,
                       y: (viewSize.height - h) / 2 + offset.height)
    }

    private func screenToCm(_ point: CGPoint, scale s: CGFloat) -> CGPoint {
        let o = origin(scale: s)
        return CGPoint(x: (point.x - o.x) / s, y: (point.y - o.y) / s)
    }

    // MARK: 绘制
    private func drawFabric(ctx: inout GraphicsContext, scale s: CGFloat) {
        let w = CGFloat(vm.fabricWidth) * s
        let h = CGFloat(vm.fabricLength) * s
        let rect = CGRect(origin: origin(scale: s), size: CGSize(width: w, height: h))
        ctx.fill(Path(rect), with: .color(Color(red: 0.96, green: 0.92, blue: 0.85)))
        ctx.stroke(Path(rect), with: .color(.appAccent.opacity(0.5)), lineWidth: 1)
        // 布边虚线
        var dashes = Path()
        dashes.move(to: CGPoint(x: rect.minX + 3 * s, y: rect.minY))
        dashes.addLine(to: CGPoint(x: rect.minX + 3 * s, y: rect.maxY))
        dashes.move(to: CGPoint(x: rect.maxX - 3 * s, y: rect.minY))
        dashes.addLine(to: CGPoint(x: rect.maxX - 3 * s, y: rect.maxY))
        ctx.stroke(dashes, with: .color(.gray.opacity(0.4)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func drawPieces(ctx: inout GraphicsContext, scale s: CGFloat) {
        let o = origin(scale: s)
        for piece in vm.placedPieces {
            let shape = piece.effectiveShape
            let isSelected = piece.id == vm.selectedPieceID
            let isDraggingCandidate = vm.dragCandidate?.id == piece.id
            // 拖动中：跟随候选位置绘制，否则画在实际锚点
            let drawAnchor = isDraggingCandidate ? (vm.dragCandidate?.anchor ?? piece.anchor) : piece.anchor

            // 拖动中在原位画虚线残影，方便对比
            if isDraggingCandidate {
                var ghost = Path()
                let gpts = shape.points.map { p -> CGPoint in
                    CGPoint(x: o.x + (piece.anchor.x + p.x) * s,
                            y: o.y + (piece.anchor.y + p.y) * s)
                }
                if let first = gpts.first {
                    ghost.move(to: first)
                    for p in gpts.dropFirst() { ghost.addLine(to: p) }
                    ghost.closeSubpath()
                    ctx.stroke(ghost, with: .color(.brown.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            }

            var path = Path()
            let pts = shape.points.map { p -> CGPoint in
                CGPoint(x: o.x + (drawAnchor.x + p.x) * s,
                        y: o.y + (drawAnchor.y + p.y) * s)
            }
            guard let first = pts.first else { continue }
            path.move(to: first)
            for p in pts.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()

            let fill: Color
            if isDraggingCandidate {
                fill = vm.dragCandidateValid ? .appAccent.opacity(0.35) : .red.opacity(0.35)
            } else {
                fill = Color(red: 0.72, green: 0.54, blue: 0.35).opacity(0.28)
            }
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path,
                       with: .color(isSelected || isDraggingCandidate ? .appAccent : .brown.opacity(0.6)),
                       lineWidth: isSelected ? 2 : 1)

            // 标签：名称 + 尺寸（画在包围盒中心）
            let box = shape.boundingBox
            let cx = o.x + (drawAnchor.x + box.midX) * s
            let cy = o.y + (drawAnchor.y + box.midY) * s
            let label = Text("\(shape.name)\n\(Int(box.width))×\(Int(box.height))")
                .font(.system(size: 9))
                .foregroundColor(.appText)
            ctx.draw(label, at: CGPoint(x: cx, y: cy))
        }
    }

    // MARK: 手势
    private func dragGesture(scale s: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if panLast == nil && draggingPieceID == nil {
                    // 第一次回调：判定是拖裁片还是平移画布
                    let cm = screenToCm(value.startLocation, scale: s)
                    if let hit = vm.hitTest(cmPoint: cm) {
                        draggingPieceID = hit
                        dragStartAnchor = vm.placedPieces.first { $0.id == hit }?.anchor
                        dragStartLocation = value.startLocation
                        vm.selectedPieceID = hit
                    } else {
                        panLast = value.startLocation
                    }
                }

                if let id = draggingPieceID,
                   let startAnchor = dragStartAnchor,
                   let startLoc = dragStartLocation {
                    let dx = (value.location.x - startLoc.x) / s
                    let dy = (value.location.y - startLoc.y) / s
                    let candidate = CGPoint(x: startAnchor.x + dx, y: startAnchor.y + dy)
                    vm.dragCandidate = (id, candidate)
                    vm.dragCandidateValid = vm.isValidMove(pieceID: id, to: candidate)
                } else if let last = panLast {
                    offset = CGSize(width: offset.width + (value.location.x - last.x),
                                    height: offset.height + (value.location.y - last.y))
                    panLast = value.location
                }
            }
            .onEnded { _ in
                if let id = draggingPieceID,
                   let candidate = vm.dragCandidate?.anchor,
                   vm.dragCandidateValid {
                    vm.commitMove(pieceID: id, to: candidate)
                }
                draggingPieceID = nil
                dragStartAnchor = nil
                dragStartLocation = nil
                panLast = nil
                vm.dragCandidate = nil
            }
    }
}

// MARK: - 布料尺寸设置 Sheet
struct FabricSizeSheet: View {
    @ObservedObject var vm: LayoutBoardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var widthText: String = ""
    @State private var lengthText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("布料尺寸（cm）") {
                    HStack {
                        Text("幅宽")
                        Spacer()
                        TextField("150", text: $widthText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("长度")
                        Spacer()
                        TextField("200", text: $lengthText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                Section {
                    Text("幅宽是布料横向的固定宽度；长度是这次买/裁的布有多长。排料会按这个比例 1:1 显示。")
                        .font(.appCaption)
                        .foregroundColor(.appSubText)
                }
            }
            .navigationTitle("布料尺寸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确定") {
                        let w = Double(widthText), l = Double(lengthText)
                        if let w, let l, w > 0, l > 0 {
                            vm.fabricWidth = min(w, 500)
                            vm.fabricLength = min(l, 1000)
                            vm.rebuildBoard()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                widthText = Int(vm.fabricWidth) == Int(vm.fabricWidth)
                    ? String(Int(vm.fabricWidth)) : String(vm.fabricWidth)
                lengthText = Int(vm.fabricLength) == Int(vm.fabricLength)
                    ? String(Int(vm.fabricLength)) : String(vm.fabricLength)
            }
        }
    }
}

// MARK: - 添加裁片 Sheet（手绘 / 尺寸两个 Tab）
struct PieceInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    let onCreated: (PieceShape) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("方式", selection: $mode) {
                    Text("图形画板").tag(0)
                    Text("输入尺寸").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if mode == 0 {
                    PiecePainterView { shape in
                        onCreated(shape)
                        dismiss()
                    }
                } else {
                    RectPieceInputView { shape in
                        onCreated(shape)
                        dismiss()
                    }
                }
            }
            .navigationTitle("添加裁片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 尺寸输入（矩形裁片）
struct RectPieceInputView: View {
    @State private var name = ""
    @State private var widthText = ""
    @State private var lengthText = ""
    let onCreated: (PieceShape) -> Void

    var canCreate: Bool {
        guard let w = Double(widthText), let l = Double(lengthText),
              w > 0, l > 0 else { return false }
        return true
    }

    var body: some View {
        Form {
            Section("裁片信息") {
                TextField("名称（如：前片）", text: $name)
                HStack {
                    Text("宽（幅向）")
                    Spacer()
                    TextField("60", text: $widthText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("cm").foregroundColor(.appSubText)
                }
                HStack {
                    Text("长（经向）")
                    Spacer()
                    TextField("70", text: $lengthText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("cm").foregroundColor(.appSubText)
                }
            }
            Section {
                Button {
                    let w = Double(widthText) ?? 0
                    let l = Double(lengthText) ?? 0
                    guard w > 0, l > 0 else { return }
                    let finalName = name.isEmpty ? "裁片" : name
                    onCreated(.rectangle(name: finalName, width: w, length: l))
                } label: {
                    Text("添加到排料板")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canCreate)
            }
        }
    }
}

// MARK: - 导出用纯布料视图（ImageRenderer 截取）
struct FabricExportView: View {
    @ObservedObject var vm: LayoutBoardViewModel

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.85)
            Canvas { ctx, size in
                let s = size.width / CGFloat(vm.fabricWidth)
                // 布边
                var dashes = Path()
                dashes.move(to: CGPoint(x: 3 * s, y: 0))
                dashes.addLine(to: CGPoint(x: 3 * s, y: size.height))
                dashes.move(to: CGPoint(x: size.width - 3 * s, y: 0))
                dashes.addLine(to: CGPoint(x: size.width - 3 * s, y: size.height))
                ctx.stroke(dashes, with: .color(.gray.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                // 裁片
                for piece in vm.placedPieces {
                    let shape = piece.effectiveShape
                    var path = Path()
                    let pts = shape.points.map { p -> CGPoint in
                        CGPoint(x: (piece.anchor.x + p.x) * s, y: (piece.anchor.y + p.y) * s)
                    }
                    guard let first = pts.first else { continue }
                    path.move(to: first)
                    for p in pts.dropFirst() { path.addLine(to: p) }
                    path.closeSubpath()
                    ctx.fill(path, with: .color(Color(red: 0.72, green: 0.54, blue: 0.35).opacity(0.4)))
                    ctx.stroke(path, with: .color(.brown), lineWidth: 1)
                }
                // 标题水印
                let title = Text("裁缝助手 · \(Int(vm.fabricWidth))×\(Int(vm.fabricLength))cm · 已排\(vm.placedCount)片")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                ctx.draw(title, at: CGPoint(x: size.width / 2, y: 14))
            }
        }
        .aspectRatio(CGFloat(vm.fabricWidth / vm.fabricLength), contentMode: .fit)
    }
}
