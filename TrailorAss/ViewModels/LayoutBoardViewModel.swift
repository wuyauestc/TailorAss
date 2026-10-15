//
//  LayoutBoardViewModel.swift
//  裁缝助手 —— M5 排料画板 VM（放置/拖动/旋转/删除/复制/统计）
//

import SwiftUI
import Combine

@MainActor
final class LayoutBoardViewModel: ObservableObject {
    // MARK: - 布料
    @Published var fabricWidth: Double = 150   // 幅宽 cm
    @Published var fabricLength: Double = 200  // 长度 cm

    // MARK: - 内容
    @Published var placedPieces: [PlacedPiece] = []
    /// 裁片库：可重复放置的形状
    @Published var library: [PieceShape] = []

    // MARK: - 交互状态
    @Published var selectedPieceID: UUID?
    /// 拖动中的候选位置（cm）；nil 表示当前未在拖动
    @Published var dragCandidate: (id: UUID, anchor: CGPoint)?
    /// 拖动候选是否合法（合法=焦糖色，非法=红色）
    @Published var dragCandidateValid = true

    let cellSize: CGFloat = 0.5

    // MARK: - 板状态
    private var board: RasterBoard

    init() {
        board = RasterBoard(fabricWidth: 150, fabricLength: 200)
    }

    // MARK: 重建整板（尺寸变更/撤销状态时）
    func rebuildBoard() {
        board = RasterBoard(fabricWidth: fabricWidth, fabricLength: fabricLength,
                            cellSize: cellSize)
        for (idx, piece) in placedPieces.enumerated() {
            pieceStamp(piece).stamp(atCol: col(of: piece.anchor.x),
                                    atRow: row(of: piece.anchor.y),
                                    board: &board,
                                    value: UInt8(min(idx + 1, 255)))
        }
    }

    // MARK: - 坐标换算
    private func col(of cmX: CGFloat) -> Int { Int(floor(cmX / cellSize)) }
    private func row(of cmY: CGFloat) -> Int { Int(floor(cmY / cellSize)) }

    func stamp(for shape: PieceShape, rotation: Double) -> PieceStamp {
        PieceStamp(shape: shape.rotated(by: rotation), cellSize: cellSize)
    }

    func pieceStamp(_ piece: PlacedPiece) -> PieceStamp {
        stamp(for: piece.shape, rotation: piece.rotation)
    }

    // MARK: - 放置与移动
    /// 尝试把形状放到指定锚点；合法返回并盖章，非法返回 false
    @discardableResult
    func place(shape: PieceShape, rotation: Double = 0, anchor: CGPoint) -> Bool {
        let st = stamp(for: shape, rotation: rotation)
        let c = col(of: anchor.x), r = row(of: anchor.y)
        guard st.fits(atCol: c, atRow: r, board: board) else { return false }
        let piece = PlacedPiece(shape: shape, rotation: rotation, anchor: anchor)
        placedPieces.append(piece)
        st.stamp(atCol: c, atRow: r, board: &board,
                 value: UInt8(min(placedPieces.count, 255)))
        selectedPieceID = piece.id
        return true
    }

    /// 找第一个能放下的位置（从左上角扫描，优先 0°，其次 90°），成功返回 true
    @discardableResult
    func autoPlace(shape: PieceShape) -> Bool {
        for rotation in [0.0, 90.0, 15.0, 75.0, 105.0, 165.0] {
            let st = stamp(for: shape, rotation: rotation)
            var r = 0
            while r < board.rows {
                var c = 0
                while c < board.cols {
                    if st.fits(atCol: c, atRow: r, board: board) {
                        let piece = PlacedPiece(shape: shape, rotation: rotation,
                                                anchor: CGPoint(x: CGFloat(c) * cellSize,
                                                                y: CGFloat(r) * cellSize))
                        placedPieces.append(piece)
                        st.stamp(atCol: c, atRow: r, board: &board,
                                 value: UInt8(min(placedPieces.count, 255)))
                        selectedPieceID = piece.id
                        return true
                    }
                    c += 1
                }
                r += 1
            }
        }
        return false // 布料放不下
    }

    /// 一键重排：清空 → 按面积降序 → 每片 0/15/30/.../165 共 12 角度全板扫描选最靠左上合法落点放下
    /// - Returns: 放不下的裁片数量
    @discardableResult
    func autoArrangeAll() -> Int {
        // 收集当前所有裁片实例的 shape（保留每个独立实例）
        let shapes = placedPieces.map(\.shape)
        // 清空整板
        placedPieces.removeAll()
        rebuildBoard()
        // 按面积降序（大面积先放）
        let sorted = shapes.sorted { $0.area > $1.area }
        let angles: [Double] = (0..<12).map { Double($0) * 15 }  // 0,15,...,165

        var failed = 0
        for shape in sorted {
            if !autoArrangePlace(shape: shape, angles: angles) {
                failed += 1
            }
        }
        selectedPieceID = nil
        return failed
    }

    /// 给 autoArrangeAll 用的放置：按角度顺序尝试，每个角度全板扫描最靠左上合法落点
    private func autoArrangePlace(shape: PieceShape, angles: [Double]) -> Bool {
        for rotation in angles {
            let st = stamp(for: shape, rotation: rotation)
            for r in 0..<board.rows {
                for c in 0..<board.cols {
                    if st.fits(atCol: c, atRow: r, board: board) {
                        let piece = PlacedPiece(shape: shape, rotation: rotation,
                                                anchor: CGPoint(x: CGFloat(c) * cellSize,
                                                                y: CGFloat(r) * cellSize))
                        placedPieces.append(piece)
                        st.stamp(atCol: c, atRow: r, board: &board,
                                 value: UInt8(min(placedPieces.count, 255)))
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - M5b 存档载入/导出
    /// 从排料文档载入（打开已存方案时调用）
    func loadDocument(_ document: LayoutDocument) {
        fabricWidth = document.fabricWidth
        fabricLength = document.fabricLength
        placedPieces = document.pieces
        rebuildBoard()
        selectedPieceID = nil
    }

    /// 导出当前画板为排料文档（保存到 CloudKit 时用）
    func toDocument() -> LayoutDocument {
        LayoutDocument(fabricWidth: fabricWidth,
                       fabricLength: fabricLength,
                       pieces: placedPieces)
    }

    /// 清空所有裁片
    func clearAll() {
        placedPieces.removeAll()
        rebuildBoard()
        selectedPieceID = nil
    }

    /// 拖动预览：返回该位置是否合法（不落章）
    func isValidMove(pieceID: UUID, to newAnchor: CGPoint) -> Bool {
        guard let idx = placedPieces.firstIndex(where: { $0.id == pieceID }) else { return false }
        let piece = placedPieces[idx]
        let st = pieceStamp(piece)
        let c0 = col(of: piece.anchor.x), r0 = row(of: piece.anchor.y)
        // 临时清空自身占位再检测（只遍历蒙版 offsets，O(k)）
        st.stamp(atCol: c0, atRow: r0, board: &board, value: 0)
        let ok = st.fits(atCol: col(of: newAnchor.x), atRow: row(of: newAnchor.y), board: board)
        // 恢复自身占位
        st.stamp(atCol: c0, atRow: r0, board: &board, value: UInt8(min(idx + 1, 255)))
        return ok
    }

    /// 提交移动
    func commitMove(pieceID: UUID, to newAnchor: CGPoint) {
        guard let idx = placedPieces.firstIndex(where: { $0.id == pieceID }) else { return }
        let st = pieceStamp(placedPieces[idx])
        // 清除旧占位（只遍历蒙版 offsets，O(k)）
        st.stamp(atCol: col(of: placedPieces[idx].anchor.x),
                 atRow: row(of: placedPieces[idx].anchor.y), board: &board, value: 0)
        placedPieces[idx].anchor = newAnchor
        st.stamp(atCol: col(of: newAnchor.x), atRow: row(of: newAnchor.y),
                 board: &board, value: UInt8(min(idx + 1, 255)))
    }

    /// 旋转选中的裁片（任意角度），失败（放不下）返回 false 并保持原状
    func rotateSelected(by delta: Double) -> Bool {
        guard let id = selectedPieceID,
              let idx = placedPieces.firstIndex(where: { $0.id == id }) else { return false }
        let piece = placedPieces[idx]
        let newRotation = (piece.rotation + delta).truncatingRemainder(dividingBy: 360)
        let newShape = piece.shape.rotated(by: newRotation)
        let st = PieceStamp(shape: newShape, cellSize: cellSize)
        let value = UInt8(min(idx + 1, 255))
        let c0 = col(of: piece.anchor.x), r0 = row(of: piece.anchor.y)
        // 清除自身占位（只遍历蒙版 offsets，O(k)）
        pieceStamp(piece).stamp(atCol: c0, atRow: r0, board: &board, value: 0)
        if st.fits(atCol: c0, atRow: r0, board: board) {
            placedPieces[idx].rotation = newRotation
            st.stamp(atCol: c0, atRow: r0, board: &board, value: value)
            return true
        } else {
            // 放不下：恢复原占位
            pieceStamp(piece).stamp(atCol: c0, atRow: r0, board: &board, value: value)
            return false
        }
    }

    /// 删除选中裁片
    func deleteSelected() {
        guard let id = selectedPieceID,
              let idx = placedPieces.firstIndex(where: { $0.id == id }) else { return }
        placedPieces.remove(at: idx)
        selectedPieceID = nil
        rebuildBoard() // 整板重建（占位标记重新编号）
    }

    /// 复制选中裁片（同形状自动找位）
    func duplicateSelected() {
        guard let id = selectedPieceID,
              let piece = placedPieces.first(where: { $0.id == id }) else { return }
        _ = autoPlace(shape: piece.shape)
    }

    /// 命中检测：屏幕点（cm 坐标）找到最上层裁片
    func hitTest(cmPoint: CGPoint) -> UUID? {
        for piece in placedPieces.reversed() {
            let local = CGPoint(x: cmPoint.x - piece.anchor.x, y: cmPoint.y - piece.anchor.y)
            if PieceStamp.contains(point: local, polygon: piece.effectiveShape.points) {
                return piece.id
            }
        }
        return nil
    }

    // MARK: - 统计
    var placedCount: Int { placedPieces.count }

    /// 已用布长（cm）：最下沿 cell 的 y + 1 行
    var usedLength: Double {
        guard !placedPieces.isEmpty else { return 0 }
        let maxRow = placedPieces.map { p -> Int in
            let st = pieceStamp(p)
            return row(of: p.anchor.y) + st.rows
        }.max() ?? 0
        return Double(maxRow) * cellSize
    }

    /// 占用面积 cm²（蒙版 cell 数 × 单元面积）
    var occupiedArea: Double {
        Double(placedPieces.reduce(0) { $0 + pieceStamp($1).area }) * cellSize * cellSize
    }

    /// 余料面积百分比（相对已用布长区域）
    var leftoverPercent: Int {
        let used = usedLength
        guard used > 0 else { return 100 }
        let total = used * fabricWidth
        guard total > 0 else { return 100 }
        return max(0, Int(round((1 - occupiedArea / total) * 100)))
    }
}
