//
//  CloudKitLayoutStore.swift
//  裁缝助手 —— CloudKit 私有库排料方案 CRUD（M5b）
//
//  启用前置条件（CloudKit Console Development 环境）：
//  1. 付费 Apple Developer Program 会员生效
//  2. Target 已添加 iCloud → CloudKit，容器 iCloud.com.trailorass.app
//  3. CloudKit Console 创建 Record Type：
//       Layout: title/String, projectRecordName/String(可空),
//               document/String(JSON), cover/Asset, updatedAt/Date
//     Indexes：recordName=Queryable + updatedAt=Sortable
//     （私有库无需配 Security Roles）
//  ⚠️ projectRecordName 字段需在 Console 标记为 Queryable，且若要按它查询
//     应改用 NSPredicate(value:true) 拉取后本地过滤（同 M2 图纸搜索本地过滤约定）
//

import CloudKit
import UIKit

final class CloudKitLayoutStore: LayoutStore {

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    init(containerID: String = AppConstants.cloudKitContainerID) {
        self.container = CKContainer(identifier: containerID)
    }

    // MARK: - Schema
    private enum Schema {
        static let layout = "Layout"
        static let title = "title"
        static let projectRecordName = "projectRecordName"
        static let document = "document"
        static let cover = "cover"
        static let updatedAt = "updatedAt"
    }

    // MARK: - iCloud 状态
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

    // MARK: - 拉取全部方案（按 updatedAt 倒序）
    func fetchLayouts() async throws -> [LayoutItem] {
        try await ensureSignedIn()

        let query = CKQuery(recordType: Schema.layout,
                            predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: Schema.updatedAt, ascending: false)]

        var items: [LayoutItem] = []
        var cursor: CKQueryOperation.Cursor?
        let pageSize = 100

        repeat {
            let fetched: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                          queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                fetched = try await privateDB.records(continuingMatchFrom: cursor,
                                                      resultsLimit: pageSize)
            } else {
                fetched = try await privateDB.records(matching: query,
                                                      resultsLimit: pageSize)
            }
            let batch = fetched.matchResults.compactMap { try? $0.1.get() }
            items.append(contentsOf: batch.map(Self.makeLayout(from:)))
            cursor = fetched.queryCursor
        } while cursor != nil

        return items
    }

    // MARK: - 拉取某项目关联的方案
    // 注：CloudKit 的 NSPredicate 对可选 String 字段做等值查询需该字段标 Queryable，
    // 私有库数据量小，统一用 NSPredicate(value:true) 拉取后本地过滤更稳（同 M2 搜索本地过滤约定）
    func fetchLayouts(forProject projectRecordName: String) async throws -> [LayoutItem] {
        let all = try await fetchLayouts()
        return all.filter { $0.projectRecordName == projectRecordName }
    }

    // MARK: - 创建方案
    func createLayout(title: String,
                      projectRecordName: String?,
                      document: LayoutDocument,
                      coverImage: UIImage?) async throws -> LayoutItem {
        try await ensureSignedIn()
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw StoreError.emptyTitle
        }

        let record = CKRecord(recordType: Schema.layout)
        record[Schema.title] = title
        record[Schema.projectRecordName] = projectRecordName
        record[Schema.document] = Self.encodeDocument(document)
        if let coverImage,
           let url = MediaUtils.saveUIImageToTemp(coverImage) {
            record[Schema.cover] = CKAsset(fileURL: url)
        }
        record[Schema.updatedAt] = Date()

        let saved = try await privateDB.save(record)
        return Self.makeLayout(from: saved)
    }

    // MARK: - 更新方案
    // coverImage=nil 不动 cover；document=nil 不动 document
    func updateLayout(_ layout: LayoutItem,
                      document: LayoutDocument?,
                      coverImage: UIImage?) async throws -> LayoutItem {
        try await ensureSignedIn()
        let record = try await mutateRecord(recordName: layout.recordName) { record in
            record[Schema.title] = layout.title
            record[Schema.projectRecordName] = layout.projectRecordName
            if let document {
                record[Schema.document] = Self.encodeDocument(document)
            }
            if let coverImage, let url = MediaUtils.saveUIImageToTemp(coverImage) {
                record[Schema.cover] = CKAsset(fileURL: url)
            }
            record[Schema.updatedAt] = Date()
        }
        return Self.makeLayout(from: record)
    }

    // MARK: - 删除方案
    func deleteLayout(recordName: String) async throws {
        try await ensureSignedIn()
        let recordID = CKRecord.ID(recordName: recordName)
        try await privateDB.deleteRecord(withID: recordID)
    }

    // MARK: - 冲突安全的"取回-修改-保存"（沿用 CloudKitProjectStore 模式）
    private func mutateRecord(recordName: String,
                              changes: (CKRecord) -> Void) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await privateDB.record(for: recordID)
        changes(record)
        do {
            return try await privateDB.save(record)
        } catch let e as CKError where e.code == .serverRecordChanged {
            guard let serverRecord = e.serverRecord else { throw e }
            changes(serverRecord)
            return try await privateDB.save(serverRecord)
        }
    }

    // MARK: - 工具方法
    static func encodeDocument(_ document: LayoutDocument) -> String {
        guard let data = try? JSONEncoder().encode(document),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    // MARK: - CKRecord → LayoutItem
    static func makeLayout(from record: CKRecord) -> LayoutItem {
        let coverURL = (record[Schema.cover] as? CKAsset)?.fileURL

        return LayoutItem(
            recordName: record.recordID.recordName,
            title: record[Schema.title] as? String ?? "",
            projectRecordName: record[Schema.projectRecordName] as? String,
            documentJSON: record[Schema.document] as? String ?? "",
            coverURL: coverURL,
            updatedAt: record[Schema.updatedAt] as? Date
                ?? record.creationDate ?? Date()
        )
    }
}
