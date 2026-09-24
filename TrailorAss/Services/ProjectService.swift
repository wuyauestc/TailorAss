import Foundation
import CloudKit
import UIKit

/// 项目追踪服务：操作私有数据库的 Project Record
final class ProjectService {
    private let db: CKDatabase
    private let recordType = "Project"

    init(container: CKContainer = CKContainer.default()) {
        self.db = container.privateCloudDatabase
    }

    // MARK: - 拉取全部项目（私有库）
    func fetchProjects() async throws -> [SewingProject] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: SewingProject.FieldKey.updatedAt, ascending: false)]
        let results = try await db.records(matching: query, resultsLimit: 500)
        return results.matchResults.compactMap { try? $0.1.get() }.map { SewingProject(record: $0) }
    }

    // MARK: - 新建项目
    func createProject(title: String, patternRecordName: String?, materials: [MaterialItem], notes: String, photos: [UIImage]) async throws -> SewingProject {
        let record = CKRecord(recordType: recordType)
        record[SewingProject.FieldKey.title] = title as CKRecordValue
        if let pn = patternRecordName {
            record[SewingProject.FieldKey.patternRecordName] = pn as CKRecordValue
        }
        record[SewingProject.FieldKey.status] = AppConstants.ProjectStatus.planning.rawValue as CKRecordValue
        record[SewingProject.FieldKey.materials] = materials.compactMap { $0.toJSONString() } as CKRecordValue
        record[SewingProject.FieldKey.notes] = notes as CKRecordValue
        record[SewingProject.FieldKey.updatedAt] = Date() as CKRecordValue
        record[SewingProject.FieldKey.photos] = try photos.compactMap { PatternService.makeImageAsset(image: $0, maxWidth: 1080) } as CKRecordValue

        let saved = try await db.save(record)
        return SewingProject(record: saved)
    }

    // MARK: - 更新项目（状态/材料/备注/照片）
    func updateProject(_ project: SewingProject, photos: [UIImage] = []) async throws -> SewingProject {
        let record = try await db.record(for: project.id)
        record[SewingProject.FieldKey.title] = project.title as CKRecordValue
        if let pn = project.patternRecordName {
            record[SewingProject.FieldKey.patternRecordName] = pn as CKRecordValue
        } else {
            record[SewingProject.FieldKey.patternRecordName] = nil
        }
        record[SewingProject.FieldKey.status] = project.status.rawValue as CKRecordValue
        record[SewingProject.FieldKey.materials] = project.materials.compactMap { $0.toJSONString() } as CKRecordValue
        record[SewingProject.FieldKey.notes] = project.notes as CKRecordValue
        record[SewingProject.FieldKey.updatedAt] = Date() as CKRecordValue
        if !photos.isEmpty {
            let photoAssets = photos.compactMap { PatternService.makeImageAsset(image: $0, maxWidth: 1080) }
            record[SewingProject.FieldKey.photos] = photoAssets as CKRecordValue
        }
        let saved = try await db.save(record)
        return SewingProject(record: saved)
    }

    // MARK: - 删除项目
    func deleteProject(_ project: SewingProject) async throws {
        _ = try await db.deleteRecord(withID: project.id)
    }
}
