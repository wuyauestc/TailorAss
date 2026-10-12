//
//  RasterCollision.swift
//  裁缝助手 —— M5 排料栅格碰撞引擎（0.5cm 网格，异形 + 任意角度统一处理）
//

import Foundation
import CoreGraphics

/// 栅格占位板：布料按 cellSize 划分网格，cells[i] = 0 空闲，>0 为占位标记
struct RasterBoard {
    let cellSize: CGFloat          // cm / cell（0.5）
    let cols: Int
    let rows: Int
    var cells: [UInt8]

    init(fabricWidth: Double, fabricLength: Double, cellSize: CGFloat = 0.5) {
        self.cellSize = cellSize
        self.cols = Int(ceil(CGFloat(fabricWidth) / cellSize))
        self.rows = Int(ceil(CGFloat(fabricLength) / cellSize))
        self.cells = [UInt8](repeating: 0, count: self.cols * self.rows)
    }

    func isFree(col: Int, row: Int) -> Bool {
        col >= 0 && col < cols && row >= 0 && row < rows && cells[row * cols + col] == 0
    }

    mutating func set(col: Int, row: Int, _ value: UInt8) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        cells[row * cols + col] = value
    }
}

/// 裁片的栅格蒙版：相对锚点（旋转后包围盒左上角）的占位 cell 偏移集合
struct PieceStamp {
    let cols: Int                  // 蒙版宽度（cell 数）
    let rows: Int
    let offsets: [ CGPoint ]       // 占位 cell 的 (col, row) 偏移
    let area: Int                  // 占位 cell 总数

    /// 对多边形（cm，局部坐标原点=锚点）按 cellSize 栅格化
    init(shape: PieceShape, cellSize: CGFloat) {
        let box = shape.boundingBox
        let cols = max(1, Int(ceil(box.width / cellSize)))
        let rows = max(1, Int(ceil(box.height / cellSize)))
        var pts: [CGPoint] = []
        var count = 0
        for r in 0..<rows {
            for c in 0..<cols {
                let px = (CGFloat(c) + 0.5) * cellSize
                let py = (CGFloat(r) + 0.5) * cellSize
                if PieceStamp.contains(point: CGPoint(x: px, y: py), polygon: shape.points) {
                    pts.append(CGPoint(x: CGFloat(c), y: CGFloat(r)))
                    count += 1
                }
            }
        }
        self.cols = cols
        self.rows = rows
        self.offsets = pts
        self.area = count
    }

    /// 射线法点在多边形内判定
    static func contains(point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let xCross = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// 蒙版在锚点 (col,row) 处是否与布料板完全兼容（界内且不重叠）
    func fits(atCol col: Int, atRow row: Int, board: RasterBoard) -> Bool {
        for o in offsets {
            if !board.isFree(col: col + Int(o.x), row: row + Int(o.y)) {
                return false
            }
        }
        return true
    }

    /// 把蒙版盖到板上（占位标记 stampValue）
    func stamp(atCol col: Int, atRow row: Int, board: inout RasterBoard, value: UInt8) {
        for o in offsets {
            board.set(col: col + Int(o.x), row: row + Int(o.y), value)
        }
    }
}

/// 轮廓描边：把栅格填充区域的外边界提取为有序多边形
/// 原理：沿"有料/无料"的 cell 交界生成有向边（保持填充区在右手侧），再首尾接龙成闭合环
enum ContourTracer {

    /// 返回所有闭合轮廓（单位 = cell，顶点落在网格线上；多个分离区域会得到多个环）
    static func trace(cells: [UInt8], cols: Int, rows: Int) -> [[CGPoint]] {
        struct Edge: Hashable {
            let x1: Int, y1: Int, x2: Int, y2: Int
        }
        let vStride = cols + 1
        func vKey(_ x: Int, _ y: Int) -> Int { y * vStride + x }
        func filled(_ c: Int, _ r: Int) -> Bool {
            c >= 0 && c < cols && r >= 0 && r < rows && cells[r * cols + c] != 0
        }

        // 生成所有边界有向边（屏幕坐标 y 向下，行走时填充 cell 保持在右手侧）
        var outgoing: [Int: [Edge]] = [:]
        for r in 0..<rows {
            for c in 0..<cols where filled(c, r) {
                if !filled(c, r - 1) { // 上邻为空：边 (c,r)→(c+1,r)
                    let e = Edge(x1: c, y1: r, x2: c + 1, y2: r)
                    outgoing[vKey(e.x1, e.y1), default: []].append(e)
                }
                if !filled(c + 1, r) { // 右邻为空
                    let e = Edge(x1: c + 1, y1: r, x2: c + 1, y2: r + 1)
                    outgoing[vKey(e.x1, e.y1), default: []].append(e)
                }
                if !filled(c, r + 1) { // 下邻为空
                    let e = Edge(x1: c + 1, y1: r + 1, x2: c, y2: r + 1)
                    outgoing[vKey(e.x1, e.y1), default: []].append(e)
                }
                if !filled(c - 1, r) { // 左邻为空
                    let e = Edge(x1: c, y1: r + 1, x2: c, y2: r)
                    outgoing[vKey(e.x1, e.y1), default: []].append(e)
                }
            }
        }

        // 接龙成环：每个顶点优先右转（y 向下坐标系），保证鞍点正确分离
        var used = Set<Edge>()
        var loops: [[CGPoint]] = []
        for r in 0...rows {
            for c in 0...cols {
                guard let starts = outgoing[vKey(c, r)] else { continue }
                for start in starts where !used.contains(start) {
                    var loop: [CGPoint] = []
                    var edge = start
                    while !used.contains(edge) {
                        used.insert(edge)
                        loop.append(CGPoint(x: edge.x1, y: edge.y1))
                        let dx = edge.x2 - edge.x1, dy = edge.y2 - edge.y1
                        let candidates = (outgoing[vKey(edge.x2, edge.y2)] ?? []).filter { !used.contains($0) }
                        guard !candidates.isEmpty else { break }
                        // 优先级：右转 > 直行 > 左转（y 向下时右方向 = (-dy, dx)）
                        edge = candidates.max { a, b in
                            func score(_ e: Edge) -> Int {
                                let nx = e.x2 - e.x1, ny = e.y2 - e.y1
                                if nx == -dy && ny == dx { return 3 }   // 右转
                                if nx == dx && ny == dy { return 2 }    // 直行
                                return 1
                            }
                            return score(a) < score(b)
                        }!
                    }
                    if loop.count >= 4 { loops.append(loop) }
                }
            }
        }
        return loops
    }

    /// 鞋带公式面积（带符号，配合 trace 可区分外轮廓与孔洞）
    static func signedArea(_ loop: [CGPoint]) -> CGFloat {
        guard loop.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<loop.count {
            let a = loop[i], b = loop[(i + 1) % loop.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }
}
