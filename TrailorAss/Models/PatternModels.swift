//
//  PatternModels.swift
//  裁缝助手 —— M2 图纸库数据模型（字段严格对应 PRD 第四节 CloudKit Record Types）
//

import Foundation

/// 图纸分类（PRD 5.8 锁定：上衣/裙装/裤装/童装/包袋/家居；"全部"仅用于筛选，不入库）
enum PatternCategory: String, CaseIterable, Identifiable, Codable {
    case top = "上衣"
    case skirt = "裙装"
    case pants = "裤装"
    case kids = "童装"
    case bag = "包袋"
    case home = "家居"

    var id: String { rawValue }

    /// 列表筛选项，"全部"在最前
    static let filterOptions: [PatternCategory?] = [nil] + allCases
}

/// 图纸（对应公共库 Record Type: Pattern）
struct PatternItem: Identifiable, Hashable {
    /// CKRecord.recordID.recordName；Mock 下为本地生成的唯一 ID
    let recordName: String
    var title: String
    var category: PatternCategory
    var creatorName: String
    var favoritesCount: Int
    /// 对应 CKRecord 系统字段 creationDate（勿自建上传时间字段）
    var createdAt: Date
    /// 封面图本地文件 URL（CloudKit 下为 CKAsset 解出的临时文件；宽 ≤750px JPEG）
    var coverFileURL: URL?
    /// PDF 图纸本地文件 URL（≤20MB）
    var pdfFileURL: URL?

    var id: String { recordName }
}

/// 收藏记录（对应私有库 Record Type: Favorite）
/// ⚠️ PRD 锁定：只存 Pattern 的 recordName 字符串，禁止跨库 CKReference
struct FavoriteItem: Identifiable, Hashable {
    let patternRecordName: String
    var createdAt: Date

    var id: String { patternRecordName }
}

/// iCloud 账号状态（映射 CKAccountStatus，Mock 恒为 available）
enum AccountState {
    case available          // 已登录，可收藏/上传
    case noAccount          // 未登录 iCloud：仅可浏览公共库
    case unavailable        // restricted / couldNotDetermine / temporarilyUnavailable
}

/// 数据层错误
enum StoreError: LocalizedError {
    case requiresICloud     // 需要登录 iCloud
    case invalidPDFSize     // PDF 超过 20MB
    case missingPDF
    case missingCover
    case emptyTitle
    case cloudKit(String)

    var errorDescription: String? {
        switch self {
        case .requiresICloud: return "请先在系统「设置」中登录 iCloud 后再操作"
        case .invalidPDFSize: return "PDF 文件不能超过 20MB"
        case .missingPDF:    return "请选择 PDF 图纸文件"
        case .missingCover:  return "请选择封面图"
        case .emptyTitle:    return "请输入图纸标题"
        case .cloudKit(let m): return m
        }
    }
}
