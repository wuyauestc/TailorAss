//
//  CloudKitProjectStore.swift
//  裁缝助手 —— CloudKit 私有库项目 CRUD（M3）
//
//  启用前置条件：
//  1. 付费 Apple Developer Program 会员生效
//  2. Target 已添加 iCloud → CloudKit，容器 iCloud.com.trailorass.app
//  3. CloudKit Console（Development 环境）创建 Record Type：
//       Project: title/String, patternRecordName/String, status/String,
//                materials/String[], notes/String, photos/[Asset], updatedAt/Date
//     Indexes：updatedAt=Sortable, status=Queryable, recordName=Queryable
//     （私有库无需配置 Security Roles，用户天然拥有自己数据的全部权限）
//

import CloudKit
import UIKit

final class CloudKitProjectStore: ProjectStore {

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    init(containerID: String = AppConstants.cloudKitContainerID) {
        self.container = CKContainer(identifier: containerID)
    }

    // MARK: - Schema
    private enum Schema {
        static let project = "Project"
        static let title = "title"
        static let patternRecordName = "patternRecordName"
        static let status = "status"
        static let materials = "materials"
        static let notes = "notes"
        static let photos = "photos"
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

    // MARK: - 拉取全部项目（按 updatedAt 倒序）
    func fetchProjects() async throws -> [ProjectItem] {
        try await ensureSignedIn()

        let query = CKQuery(recordType: Schema.project,
                            predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: Schema.updatedAt, ascending: false)]

        var items: [ProjectItem] = []
        var cursor: CKQueryOperation.Cursor?

        // 分页拉取（每页 100，私有库数据量小）
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
            items.append(contentsOf: batch.map(Self.makeProject(from:)))
            cursor = fetched.queryCursor
        } while cursor != nil

        return items
    }

    // MARK: - 创建项目
    func createProject(title: String,
                       patternRecordName: String?,
                       materials: [MaterialItem]) async throws -> ProjectItem {
        try await ensureSignedIn()
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw StoreError.emptyTitle
        }

        let record = CKRecord(recordType: Schema.project)
        record[Schema.title] = title
        record[Schema.patternRecordName] = patternRecordName
        record[Schema.status] = ProjectStatus.planning.rawValue
        record[Schema.materials] = materials.map { encodeMaterial($0) }
        record[Schema.notes] = ""
        record[Schema.updatedAt] = Date()

        let saved = try await privateDB.save(record)
        return Self.makeProject(from: saved)
    }

    // MARK: - 更新项目
    func updateProject(_ project: ProjectItem) async throws -> ProjectItem {
        try await ensureSignedIn()
        let record = try await mutateRecord(recordName: project.recordName) { record in
            record[Schema.title] = project.title
            record[Schema.patternRecordName] = project.patternRecordName
            record[Schema.status] = project.status.rawValue
            record[Schema.materials] = project.materials.map { encodeMaterial($0) }
            record[Schema.notes] = project.notes
            record[Schema.updatedAt] = Date()
            // photos 不动，保留服务器上的 Asset 列表
        }
        return Self.makeProject(from: record)
    }

    // MARK: - 删除项目
    func deleteProject(recordName: String) async throws {
        try await ensureSignedIn()
        let recordID = CKRecord.ID(recordName: recordName)
        try await privateDB.deleteRecord(withID: recordID)
    }

    // MARK: - 上传照片
    func addPhotos(recordName: String, photoURLs: [URL]) async throws -> ProjectItem {
        try await ensureSignedIn()
        let record = try await mutateRecord(recordName: recordName) { record in
            var assets = (record[Schema.photos] as? [CKAsset]) ?? []
            for url in photoURLs {
                assets.append(CKAsset(fileURL: url))
            }
            record[Schema.photos] = assets
            record[Schema.updatedAt] = Date()
        }
        return Self.makeProject(from: record)
    }

    // MARK: - 冲突安全的"取回-修改-保存"
    /// 多处并发保存时以服务器最新版本为准合并重试，避免 client oplock error
    private func mutateRecord(recordName: String,
                              changes: (CKRecord) -> Void) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await privateDB.record(for: recordID)
        changes(record)
        do {
            return try await privateDB.save(record)
        } catch let e as CKError where e.code == .serverRecordChanged {
            // 本地版本过期：把同样的修改叠加到服务器最新记录上重试一次
            guard let serverRecord = e.serverRecord else { throw e }
            changes(serverRecord)
            return try await privateDB.save(serverRecord)
        }
    }

    // MARK: - 工具方法
    private func encodeMaterial(_ item: MaterialItem) -> String {
        guard let data = try? JSONEncoder().encode(item),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    private func decodeMaterial(_ json: String) -> MaterialItem? {
        guard let data = json.data(using: .utf8),
              let item = try? JSONDecoder().decode(MaterialItem.self, from: data) else { return nil }
        return item
    }

    // MARK: - CKRecord → ProjectItem
    static func makeProject(from record: CKRecord) -> ProjectItem {
        let materials: [MaterialItem] = (record[Schema.materials] as? [String])?
            .compactMap { decodeMaterialStatic($0) } ?? []

        let photoURLs: [URL] = (record[Schema.photos] as? [CKAsset])?
            .compactMap { $0.fileURL } ?? []

        return ProjectItem(
            recordName: record.recordID.recordName,
            title: record[Schema.title] as? String ?? "",
            patternRecordName: record[Schema.patternRecordName] as? String,
            status: ProjectStatus(rawValue: record[Schema.status] as? String ?? "")
                ?? .planning,
            materials: materials,
            notes: record[Schema.notes] as? String ?? "",
            photoURLs: photoURLs,
            updatedAt: record[Schema.updatedAt] as? Date
                ?? record.creationDate ?? Date()
        )
    }

    private static func decodeMaterialStatic(_ json: String) -> MaterialItem? {
        guard let data = json.data(using: .utf8),
              let item = try? JSONDecoder().decode(MaterialItem.self, from: data) else { return nil }
        return item
    }
}
