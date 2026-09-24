import Foundation
import CloudKit
import UIKit

/// 图纸服务：操作公共数据库的 Pattern Record
final class PatternService {
    private let db: CKDatabase
    private let recordType = "Pattern"

    init(container: CKContainer = CKContainer.default()) {
        self.db = container.publicCloudDatabase
    }

    // MARK: - 拉取图纸列表（按 createdAt 倒序，分页 20 条）
    func fetchPatterns(category: String?, searchKeyword: String?, cursor: CKQueryOperation.Cursor?) async throws -> ([Pattern], CKQueryOperation.Cursor?) {
        var predicates: [NSPredicate] = [NSPredicate(value: true)]
        if let category = category, category != AppConstants.PatternCategory.all.rawValue, !category.isEmpty {
            predicates.append(NSPredicate(format: "category == %@", category))
        }
        if let keyword = searchKeyword, !keyword.isEmpty {
            predicates.append(NSPredicate(format: "title CONTAINS[c] %@", keyword))
        }
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let query = CKQuery(recordType: recordType, predicate: compound)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
        if let cursor = cursor {
            results = try await db.records(continuingMatchFrom: cursor)
        } else {
            results = try await db.records(matching: query, resultsLimit: AppConstants.pageSize)
        }

        let patterns = results.matchResults.compactMap { try? $0.1.get() }.map { Pattern(record: $0) }
        return (patterns, results.queryCursor)
    }

    // MARK: - 根据 recordName 列表批量拉取（用于"我的收藏"详情）
    func fetchPatterns(recordNames: [String]) async throws -> [Pattern] {
        guard !recordNames.isEmpty else { return [] }
        let recordIDs = recordNames.map { CKRecord.ID(recordName: $0) }
        let results = try await db.records(for: recordIDs)
        return results.values.compactMap { try? $0.get() }.map { Pattern(record: $0) }
    }

    // MARK: - 上传图纸
    /// 封面图先压缩至宽 ≤750px，PDF ≤20MB
    func uploadPattern(title: String, category: String, coverImage: UIImage, pdfData: Data, creatorName: String = "裁缝用户") async throws -> Pattern {
        let record = CKRecord(recordType: recordType)
        record[Pattern.FieldKey.title] = title as CKRecordValue
        record[Pattern.FieldKey.category] = category as CKRecordValue
        record[Pattern.FieldKey.creatorName] = creatorName as CKRecordValue
        record[Pattern.FieldKey.favoritesCount] = 0 as CKRecordValue

        // 封面：压缩至宽 ≤750px JPEG
        if let coverAsset = Self.makeImageAsset(image: coverImage, maxWidth: AppConstants.coverMaxWidth) {
            record[Pattern.FieldKey.cover] = coverAsset
        }

        // PDF：写临时文件再生成 CKAsset（PRD 约束 3）
        let pdfAsset = try Self.makeDataAsset(data: pdfData, fileExtension: "pdf")
        record[Pattern.FieldKey.pdf] = pdfAsset

        let saved = try await db.save(record)
        return Pattern(record: saved)
    }

    // MARK: - 收藏数 ±1
    func updateFavoritesCount(recordName: String, delta: Int64) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await db.record(for: recordID)
        let current = record[Pattern.FieldKey.favoritesCount] as? Int64 ?? 0
        record[Pattern.FieldKey.favoritesCount] = max(0, current + delta) as CKRecordValue
        _ = try await db.save(record)
    }

    // MARK: - CKAsset 工具
    static func makeImageAsset(image: UIImage, maxWidth: CGFloat) -> CKAsset? {
        let resized = image.resized(toWidth: maxWidth)
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return try? makeDataAsset(data: data, fileExtension: "jpg")
    }

    /// 把 Data 写入临时文件并生成 CKAsset（PRD 约束 3）
    static func makeDataAsset(data: Data, fileExtension: String) throws -> CKAsset {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: url)
        return CKAsset(fileURL: url)
    }
}

extension UIImage {
    /// 等比缩放至最大宽度
    func resized(toWidth width: CGFloat) -> UIImage {
        let ratio = width / size.width
        let newHeight = size.height * ratio
        let newSize = CGSize(width: width, height: newHeight)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
