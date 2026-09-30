//
//  CloudKitPatternStore.swift
//  裁缝助手 —— CloudKit 真实数据实现（M2 接通后替代 MockPatternStore）
//
//  启用前置条件：
//  1. 付费 Apple Developer Program 会员生效
//  2. Target 添加 iCloud → CloudKit 能力，容器 iCloud.com.trailorass.app
//  3. CloudKit Console（Development 环境）创建 Record Type：
//       Pattern: title/String, category/String, cover/Asset, pdf/Asset,
//                creatorName/String, favoritesCount/Int64
//       Favorite: patternRecordName/String, createdAt/Date
//     Indexes：Pattern.creationDate=Sortable、title=Queryable、category=Queryable；
//              Favorite.patternRecordName=Queryable
//     Pattern 安全角色：Authenticated User 允许 Create
//  4. StoreFactory.patternStore 改为 CloudKitPatternStore()
//

import CloudKit

final class CloudKitPatternStore: PatternStore {

    private let container: CKContainer
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    /// 列表分页游标（筛选/搜索条件变化时重置）
    private var listCursor: CKQueryOperation.Cursor?
    private var listKey = ""

    init(containerID: String = AppConstants.cloudKitContainerID) {
        self.container = CKContainer(identifier: containerID)
    }

    // MARK: iCloud 状态
    func accountState() async throws -> AccountState {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                switch status {
                case .available:            continuation.resume(returning: .available)
                case .noAccount:            continuation.resume(returning: .noAccount)
                case .couldNotDetermine,
                     .restricted,
                     .temporarilyUnavailable:
                    continuation.resume(returning: .unavailable)
                @unknown default:
                    continuation.resume(returning: .unavailable)
                }
            }
        }
    }

    private func ensureSignedIn() async throws {
        let state = try await accountState()
        if state != .available { throw StoreError.requiresICloud }
    }

    // MARK: 公共库 - 图纸列表
    func fetchPatterns(category: PatternCategory?,
                       searchText: String?,
                       page: Int) async throws -> [PatternItem] {
        // 条件变化或回到第一页：重建查询并清空游标
        let key = "\(category?.rawValue ?? "*")|\((searchText ?? "").trimmingCharacters(in: .whitespaces))"
        if page == 0 || key != listKey {
            listKey = key
            listCursor = nil
        }

        let results: [(CKRecord.ID, Result<CKRecord, Error>)]
        let cursor: CKQueryOperation.Cursor?

        let keyword = (searchText ?? "").trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            // CloudKit 全文检索对中文子串匹配不可靠（CJK 整段被视为一个词元），
            // 搜索时改为：服务端按分类拉取 + 本地按标题过滤。
            // 图纸库量级下够用，且中文子串匹配 100% 准确。
            return try await fetchByLocalTitleFilter(category: category, keyword: keyword)
        }

        if let listCursor {
            (results, cursor) = try await publicDB.records(continuingMatchFrom: listCursor,
                                                            resultsLimit: AppConstants.pageSize)
        } else {
            let predicate = makeListPredicate(category: category, searchText: searchText)
            let query = CKQuery(recordType: Schema.pattern, predicate: predicate)
            // creationDate 是 CKRecord 系统字段（对应 PRD 要求的 createdAt，不自建）
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            (results, cursor) = try await publicDB.records(matching: query,
                                                           resultsLimit: AppConstants.pageSize)
        }
        listCursor = cursor
        return try results.compactMap { try? $0.1.get() }.map(Self.makePattern(from:))
    }

    private func makeListPredicate(category: PatternCategory?, searchText: String?) -> NSPredicate {
        // 搜索词不再进服务端谓词（见 fetchPatterns 中的本地过滤分支）
        var subs: [NSPredicate] = []
        if let category {
            subs.append(NSPredicate(format: "category == %@", category.rawValue))
        }
        if subs.isEmpty { return NSPredicate(value: true) }
        if subs.count == 1 { return subs[0] }
        return NSCompoundPredicate(andPredicateWithSubpredicates: subs)
    }

    /// 搜索：服务端按分类分页拉取（最多 10 页防止极端情况），本地按标题子串过滤
    private func fetchByLocalTitleFilter(category: PatternCategory?,
                                         keyword: String) async throws -> [PatternItem] {
        let predicate = makeListPredicate(category: category, searchText: nil)
        let query = CKQuery(recordType: Schema.pattern, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var matched: [PatternItem] = []
        var cursor: CKQueryOperation.Cursor?
        let maxPages = 10
        for _ in 0..<maxPages {
            let fetched: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                          queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                fetched = try await publicDB.records(continuingMatchFrom: cursor,
                                                     resultsLimit: AppConstants.pageSize)
            } else {
                fetched = try await publicDB.records(matching: query,
                                                     resultsLimit: AppConstants.pageSize)
            }
            let batch = fetched.matchResults.compactMap { try? $0.1.get() }.map(Self.makePattern(from:))
            matched += batch.filter {
                $0.title.range(of: keyword, options: .caseInsensitive) != nil
            }
            cursor = fetched.queryCursor
            if cursor == nil { break }
        }
        return matched
    }

    // MARK: 收藏
    func favoriteRecordNames() async throws -> Set<String> {
        let query = CKQuery(recordType: Schema.favorite, predicate: NSPredicate(value: true))
        let (results, _) = try await privateDB.records(matching: query)
        return Set(try results.compactMap { try $0.1.get() }.compactMap { $0[Field.patternRecordName] as? String })
    }

    func setFavorite(pattern: PatternItem, isFavorite: Bool) async throws -> PatternItem {
        try await ensureSignedIn()

        // 1. 查私有库是否已有该收藏
        let existing = try await fetchFavoriteRecord(patternRecordName: pattern.recordName)

        if isFavorite {
            // 2a. 写私有库 Favorite
            if existing == nil {
                let record = CKRecord(recordType: Schema.favorite)
                record[Field.patternRecordName] = pattern.recordName
                record[Field.favoriteCreatedAt] = Date()
                _ = try await privateDB.save(record)
            }
            // 3a. 公共库收藏数 +1
            return try await updateCount(recordName: pattern.recordName, delta: existing == nil ? 1 : 0)
        } else {
            // 2b. 删私有库 Favorite
            if let existing {
                _ = try await privateDB.deleteRecord(withID: existing.recordID)
            }
            // 3b. 公共库收藏数 -1
            return try await updateCount(recordName: pattern.recordName, delta: existing != nil ? -1 : 0)
        }
    }

    func fetchFavoritePatterns() async throws -> [PatternItem] {
        try await ensureSignedIn()
        // 私有库收藏按时间倒序
        let query = CKQuery(recordType: Schema.favorite, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: Field.favoriteCreatedAt, ascending: false)]
        let (results, _) = try await privateDB.records(matching: query)
        let favorites = try results.compactMap { try $0.1.get() }

        guard !favorites.isEmpty else { return [] }
        let pairs: [(String, Date)] = favorites.compactMap {
            guard let name = $0[Field.patternRecordName] as? String else { return nil }
            return (name, $0[Field.favoriteCreatedAt] as? Date ?? Date())
        }
        // 批量取公共库 Pattern
        let ids = pairs.map { CKRecord.ID(recordName: $0.0) }
        let fetched = try await publicDB.records(for: ids)
        var byName: [String: PatternItem] = [:]
        for id in ids {
            if case .success(let record) = fetched[id] {
                byName[id.recordName] = Self.makePattern(from: record)
            }
        }
        return pairs.compactMap { byName[$0.0] }
    }

    // MARK: 上传
    func uploadPattern(title: String,
                       category: PatternCategory,
                       coverJPEGURL: URL,
                       pdfFileURL: URL) async throws -> PatternItem {
        try await ensureSignedIn()
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw StoreError.emptyTitle }
        guard MediaUtils.isPDFSizeValid(pdfFileURL) else { throw StoreError.invalidPDFSize }

        let record = CKRecord(recordType: Schema.pattern)
        record[Field.title] = trimmed
        record[Field.category] = category.rawValue
        record[Field.cover] = CKAsset(fileURL: coverJPEGURL)
        record[Field.pdf] = CKAsset(fileURL: pdfFileURL)
        record[Field.creatorName] = "裁缝用户"
        record[Field.favoritesCount] = 1          // 上传者默认收藏

        let saved = try await publicDB.save(record)

        // 私有库写一条收藏（禁止 CKReference，只存 recordName 字符串）
        let favorite = CKRecord(recordType: Schema.favorite)
        favorite[Field.patternRecordName] = saved.recordID.recordName
        favorite[Field.favoriteCreatedAt] = Date()
        _ = try? await privateDB.save(favorite)

        return Self.makePattern(from: saved)
    }

    // MARK: - 私有辅助
    private func fetchFavoriteRecord(patternRecordName: String) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "patternRecordName == %@", patternRecordName)
        let query = CKQuery(recordType: Schema.favorite, predicate: predicate)
        let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
        return results.first.flatMap { try? $0.1.get() }
    }

    /// 读取—改收藏数—保存（最佳努力的冗余计数维护）
    private func updateCount(recordName: String, delta: Int) async throws -> PatternItem {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await publicDB.record(for: recordID)
        if delta != 0 {
            let current = (record[Field.favoritesCount] as? Int64) ?? 0
            record[Field.favoritesCount] = max(0, current + Int64(delta))
            let saved = try await publicDB.save(record)
            return Self.makePattern(from: saved)
        }
        return Self.makePattern(from: record)
    }

    private static func makePattern(from record: CKRecord) -> PatternItem {
        PatternItem(
            recordName: record.recordID.recordName,
            title: record[Field.title] as? String ?? "未命名图纸",
            category: PatternCategory(rawValue: record[Field.category] as? String ?? "") ?? .top,
            creatorName: record[Field.creatorName] as? String ?? "裁缝用户",
            favoritesCount: Int((record[Field.favoritesCount] as? Int64) ?? 0),
            createdAt: record.creationDate ?? Date(),
            coverFileURL: (record[Field.cover] as? CKAsset)?.fileURL,
            pdfFileURL: (record[Field.pdf] as? CKAsset)?.fileURL
        )
    }

    private enum Schema {
        static let pattern = "Pattern"
        static let favorite = "Favorite"
    }

    private enum Field {
        static let title = "title"
        static let category = "category"
        static let cover = "cover"
        static let pdf = "pdf"
        static let creatorName = "creatorName"
        static let favoritesCount = "favoritesCount"
        static let patternRecordName = "patternRecordName"
        static let favoriteCreatedAt = "createdAt"
    }
}
