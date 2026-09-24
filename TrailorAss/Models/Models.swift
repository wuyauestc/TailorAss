import Foundation
import CloudKit

// MARK: - 材料清单条目
/// 项目材料清单条目，对应 Project.materials 数组中的 JSON 字符串
struct MaterialItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String    // 如 "棉麻布"
    var qty: Double     // 数量
    var unit: String    // 单位，如 "米"

    init(name: String, qty: Double, unit: String) {
        self.name = name
        self.qty = qty
        self.unit = unit
    }

    // MARK: - JSON <-> String（PRD 约束 2：materials 用 [String] 数组存 JSON 字符串）
    func toJSONString() -> String? {
        let dict: [String: Any] = ["name": name, "qty": qty, "unit": unit]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSONString(_ string: String) -> MaterialItem? {
        guard let data = string.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["name"] as? String,
              let qty = dict["qty"] as? Double,
              let unit = dict["unit"] as? String else { return nil }
        return MaterialItem(name: name, qty: qty, unit: unit)
    }
}

// MARK: - Pattern（公共库图纸）
struct Pattern: Identifiable, Hashable {
    let id: CKRecord.ID
    let recordName: String
    var title: String
    var category: String
    var coverURL: URL?           // CKAsset 本地 URL
    var pdfURL: URL?
    var creatorName: String
    var favoritesCount: Int64
    var createdAt: Date

    // 字段键
    enum FieldKey {
        static let title = "title"
        static let category = "category"
        static let cover = "cover"
        static let pdf = "pdf"
        static let creatorName = "creatorName"
        static let favoritesCount = "favoritesCount"
    }

    init(record: CKRecord) {
        self.id = record.recordID
        self.recordName = record.recordID.recordName
        self.title = record[FieldKey.title] as? String ?? ""
        self.category = record[FieldKey.category] as? String ?? ""
        self.coverURL = (record[FieldKey.cover] as? CKAsset)?.fileURL
        self.pdfURL = (record[FieldKey.pdf] as? CKAsset)?.fileURL
        self.creatorName = record[FieldKey.creatorName] as? String ?? "裁缝用户"
        self.favoritesCount = record[FieldKey.favoritesCount] as? Int64 ?? 0
        self.createdAt = record.creationDate ?? Date()
    }
}

// MARK: - Favorite（私有库收藏）
/// 收藏里存图案的 recordName（字符串），不建跨库 CKReference（PRD 约束 1）
struct Favorite: Identifiable, Hashable {
    let id: CKRecord.ID
    let patternRecordName: String
    let createdAt: Date

    enum FieldKey {
        static let patternRecordName = "patternRecordName"
    }

    init(record: CKRecord) {
        self.id = record.recordID
        self.patternRecordName = record[FieldKey.patternRecordName] as? String ?? ""
        self.createdAt = record.creationDate ?? Date()
    }
}

// MARK: - Project（私有库项目追踪）
struct SewingProject: Identifiable, Hashable {
    let id: CKRecord.ID
    var title: String
    var patternRecordName: String?   // 关联图纸 recordName（字符串，可空）
    var status: AppConstants.ProjectStatus
    var materials: [MaterialItem]
    var notes: String
    var photoURLs: [URL]             // CKAsset fileURL 数组
    var updatedAt: Date

    enum FieldKey {
        static let title = "title"
        static let patternRecordName = "patternRecordName"
        static let status = "status"
        static let materials = "materials"
        static let notes = "notes"
        static let photos = "photos"
        static let updatedAt = "updatedAt"
    }

    init(record: CKRecord) {
        self.id = record.recordID
        self.title = record[FieldKey.title] as? String ?? ""
        self.patternRecordName = record[FieldKey.patternRecordName] as? String
        let statusRaw = record[FieldKey.status] as? String ?? AppConstants.ProjectStatus.planning.rawValue
        self.status = AppConstants.ProjectStatus(rawValue: statusRaw) ?? .planning

        // materials: [String] -> [MaterialItem]
        let materialStrings = record[FieldKey.materials] as? [String] ?? []
        self.materials = materialStrings.compactMap { MaterialItem.fromJSONString($0) }

        self.notes = record[FieldKey.notes] as? String ?? ""

        // photos: [CKAsset] -> [URL]
        let photoAssets = record[FieldKey.photos] as? [CKAsset] ?? []
        self.photoURLs = photoAssets.compactMap { $0.fileURL }

        self.updatedAt = record[FieldKey.updatedAt] as? Date ?? record.modificationDate ?? Date()
    }
}
