import Foundation
import CloudKit

/// 收藏服务：操作私有数据库的 Favorite Record
/// 收藏里存图案的 recordName（字符串），不建跨库 CKReference（PRD 约束 1）
final class FavoriteService {
    private let db: CKDatabase
    private let recordType = "Favorite"

    init(container: CKContainer = CKContainer.default()) {
        self.db = container.privateCloudDatabase
    }

    // MARK: - 获取我的全部收藏的 patternRecordName 列表
    func fetchFavorites() async throws -> [Favorite] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let results = try await db.records(matching: query, resultsLimit: 500)
        return results.matchResults.compactMap { try? $0.1.get() }.map { Favorite(record: $0) }
    }

    // MARK: - 是否已收藏
    func isFavorited(patternRecordName: String) async throws -> Bool {
        let predicate = NSPredicate(format: "\(Favorite.FieldKey.patternRecordName) == %@", patternRecordName)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        let results = try await db.records(matching: query, resultsLimit: 1)
        return !results.matchResults.isEmpty
    }

    // MARK: - 收藏
    func addFavorite(patternRecordName: String) async throws {
        let record = CKRecord(recordType: recordType)
        record[Favorite.FieldKey.patternRecordName] = patternRecordName as CKRecordValue
        _ = try await db.save(record)
    }

    // MARK: - 取消收藏
    func removeFavorite(patternRecordName: String) async throws {
        let predicate = NSPredicate(format: "\(Favorite.FieldKey.patternRecordName) == %@", patternRecordName)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        let results = try await db.records(matching: query, resultsLimit: 1)
        guard let first = results.matchResults.first,
              let record = try? first.1.get() else { return }
        _ = try await db.deleteRecord(withID: record.recordID)
    }
}
