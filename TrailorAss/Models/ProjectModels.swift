//
//  ProjectModels.swift
//  裁缝助手 —— M3 项目追踪数据模型（字段严格对应 PRD 第四节 Project Record Type）
//

import Foundation

/// 项目状态（PRD 5.9 锁定四态：planning → cutting → sewing → finished）
enum ProjectStatus: String, CaseIterable, Identifiable, Codable {
    case planning = "规划中"
    case cutting = "裁剪中"
    case sewing = "车缝中"
    case finished = "已完成"

    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .planning: return "rectangle.dashed"
        case .cutting:  return "scissors"
        case .sewing:   return "needle"
        case .finished: return "checkmark.seal.fill"
        }
    }
    /// PRD 锁定：仅相邻状态可切换；finished 后可重新打开为 sewing
    func canTransition(to next: ProjectStatus) -> Bool {
        switch self {
        case .planning: return next == .cutting
        case .cutting:  return next == .sewing
        case .sewing:   return next == .finished
        case .finished: return next == .sewing  // 重新打开
        }
    }
}

/// 材料清单条目（编码为 JSON 字符串存入 CloudKit materials 字段）
struct MaterialItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var quantity: String
    var unit: String

    init(id: UUID = UUID(), name: String, quantity: String, unit: String) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }

    /// 显示文本：布料 1.5 米
    var displayText: String { "\(name) \(quantity) \(unit)" }
}

/// 项目（对应私有库 Record Type: Project）
struct ProjectItem: Identifiable, Hashable {
    let recordName: String
    var title: String
    var patternRecordName: String?  // 关联图纸（可空，字符串非 CKReference）
    var status: ProjectStatus
    var materials: [MaterialItem]   // 存入 CloudKit 时编码为 JSON 字符串数组
    var notes: String
    var photoURLs: [URL]            // CloudKit 下为 CKAsset 解出的临时文件 URL
    var updatedAt: Date

    var id: String { recordName }
}
