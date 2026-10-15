//
//  LayoutModels.swift
//  裁缝助手 —— M5 布料排料数据模型（多边形裁片 + 排料文档）
//

import Foundation
import CoreGraphics

/// 裁片形状：多边形顶点（单位 cm，局部坐标系，原点在包围盒左上角）
struct PieceShape: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    /// 多边形顶点（cm，顺时针或逆时针均可，自动闭合）
    var points: [CGPoint]

    init(id: UUID = UUID(), name: String, points: [CGPoint]) {
        self.id = id
        self.name = name
        self.points = points
    }

    /// 包围盒（cm）
    var boundingBox: CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, minY = ys.min()!
        return CGRect(x: minX, y: minY,
                      width: xs.max()! - minX, height: ys.max()! - minY)
    }

    /// 鞋带公式面积（cm²）
    var area: Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += Double(a.x * b.y - b.x * a.y)
        }
        return abs(sum) / 2
    }

    /// 生成矩形裁片
    static func rectangle(name: String, width: Double, length: Double) -> PieceShape {
        PieceShape(name: name, points: [
            CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0),
            CGPoint(x: width, y: length), CGPoint(x: 0, y: length)
        ])
    }

    /// 绕包围盒中心旋转角度（度），返回旋转后重新对齐到左上角的新形状
    func rotated(by degrees: Double) -> PieceShape {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return self }
        let rad = degrees * .pi / 180
        let cos = CGFloat(cos(rad)), sin = CGFloat(sin(rad))
        let box = boundingBox
        let cx = box.midX, cy = box.midY
        let rotated = points.map { p -> CGPoint in
            let dx = p.x - cx, dy = p.y - cy
            return CGPoint(x: dx * cos - dy * sin, y: dx * sin + dy * cos)
        }
        let newBox = PieceShape(name: name, points: rotated).boundingBox
        let offsetX = -newBox.minX, offsetY = -newBox.minY
        return PieceShape(name: name,
                          points: rotated.map { CGPoint(x: $0.x + offsetX, y: $0.y + offsetY) })
    }
}

/// 已放置在布料上的裁片实例
struct PlacedPiece: Identifiable, Hashable, Codable {
    var id: UUID
    var shape: PieceShape          // 未旋转的原始形状
    var rotation: Double           // 旋转角度（度，任意角）
    /// 放置锚点：旋转后包围盒左上角在布料上的坐标（cm）
    var anchor: CGPoint

    init(id: UUID = UUID(), shape: PieceShape, rotation: Double = 0, anchor: CGPoint = .zero) {
        self.id = id
        self.shape = shape
        self.rotation = rotation
        self.anchor = anchor
    }

    /// 当前旋转状态下的实际形状（局部坐标，原点即 anchor）
    var effectiveShape: PieceShape { shape.rotated(by: rotation) }
}

/// 排料文档：布料尺寸 + 已排裁片（M5b 存 CloudKit Layout.document 字段，JSON 字符串）
struct LayoutDocument: Codable {
    var fabricWidth: Double    // 幅宽 cm
    var fabricLength: Double   // 长度 cm
    var pieces: [PlacedPiece]
}

/// 排料方案（M5b，对应 CloudKit 私有库 Record Type: Layout）
/// 字段：title/projectRecordName(可空，禁用 CKReference，字符串)/document(JSON)/cover(Asset 缩略图)/updatedAt
/// 索引：recordName(Queryable) + updatedAt(Sortable)
struct LayoutItem: Identifiable, Hashable {
    let recordName: String
    var title: String
    /// 关联项目记录名（可空，跨记录用字符串非 CKReference，同 M3/M2 约定）
    var projectRecordName: String?
    /// LayoutDocument 序列化后的 JSON 字符串（CloudKit 存 String）
    var documentJSON: String
    /// 缩略图本地临时 URL（CloudKit 下为 CKAsset 解出的临时文件 URL；nil 表示无缩略图）
    var coverURL: URL?
    var updatedAt: Date

    var id: String { recordName }

    /// 从 documentJSON 反序列化出排料文档；解析失败返回空文档
    var document: LayoutDocument {
        guard let data = documentJSON.data(using: .utf8),
              let doc = try? JSONDecoder().decode(LayoutDocument.self, from: data) else {
            return LayoutDocument(fabricWidth: 150, fabricLength: 200, pieces: [])
        }
        return doc
    }

    /// 缩略图标题预览（无 cover 时用裁片数）
    var previewText: String {
        let doc = document
        return "\(Int(doc.fabricWidth))×\(Int(doc.fabricLength))cm · \(doc.pieces.count)片"
    }
}
