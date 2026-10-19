//
//  ProjectStore.swift
//  裁缝助手 —— M3 项目追踪数据访问抽象（私有库 CRUD）
//

import Foundation

protocol ProjectStore {
    // MARK: iCloud 状态
    func accountState() async throws -> AccountState

    // MARK: 私有库 - 项目 CRUD
    /// 拉取全部项目（按 updatedAt 倒序）
    func fetchProjects() async throws -> [ProjectItem]

    /// 创建项目
    func createProject(title: String,
                       patternRecordName: String?,
                       materials: [MaterialItem]) async throws -> ProjectItem

    /// 更新项目（状态流转、材料增删、备注、照片等）
    func updateProject(_ project: ProjectItem) async throws -> ProjectItem

    /// 删除项目
    func deleteProject(recordName: String) async throws

    /// 上传成品/过程照片（单张 ≤5MB JPEG），返回更新后的项目
    func addPhotos(recordName: String, photoURLs: [URL]) async throws -> ProjectItem
}

/// 数据层切换入口
enum ProjectStoreFactory {
    /// Simulator 构建不具备真机签名后的 CloudKit entitlement，使用本地实现便于 UI / Unity 联调。
    /// 真机继续使用 CloudKit 私有库。
#if targetEnvironment(simulator)
    static let projectStore: any ProjectStore = MockProjectStore()
#else
    static let projectStore: any ProjectStore = CloudKitProjectStore()
#endif
}
