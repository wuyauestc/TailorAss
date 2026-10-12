//
//  MockProjectStore.swift
//  裁缝助手 —— M3 本地假数据（离线调试 UI，无需 iCloud）
//

import Foundation

final class MockProjectStore: ProjectStore {
    func accountState() async throws -> AccountState { .available }

    func fetchProjects() async throws -> [ProjectItem] { [] }

    func createProject(title: String, patternRecordName: String?,
                       materials: [MaterialItem]) async throws -> ProjectItem {
        ProjectItem(recordName: "mock-\(UUID().uuidString.prefix(8))",
                    title: title, patternRecordName: patternRecordName,
                    status: .planning, materials: materials, notes: "",
                    photoURLs: [], updatedAt: Date())
    }

    func updateProject(_ project: ProjectItem) async throws -> ProjectItem { project }
    func deleteProject(recordName: String) async throws {}
    func addPhotos(recordName: String, photoURLs: [URL]) async throws -> ProjectItem {
        ProjectItem(recordName: recordName, title: "", patternRecordName: nil,
                    status: .planning, materials: [], notes: "", photoURLs: photoURLs,
                    updatedAt: Date())
    }
}
