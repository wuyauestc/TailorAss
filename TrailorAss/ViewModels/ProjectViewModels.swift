//
//  ProjectViewModels.swift
//  裁缝助手 —— M3 项目追踪视图模型
//

import SwiftUI
import Combine
import CloudKit
import PhotosUI

// MARK: - 项目列表 VM
@MainActor
final class ProjectListViewModel: ObservableObject {
    @Published var projects: [ProjectItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = ProjectStoreFactory.projectStore

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            projects = try await store.fetchProjects()
        } catch is CancellationError {
        } catch let e as CKError where e.code == .operationCancelled {
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    /// 按状态分组（PRD 5.9：规划中/裁剪中/车缝中/已完成）
    var groupedProjects: [(ProjectStatus, [ProjectItem])] {
        ProjectStatus.allCases.map { status in
            (status, projects.filter { $0.status == status })
        }.filter { !$1.isEmpty }
    }

    func delete(_ project: ProjectItem) async {
        do {
            try await store.deleteProject(recordName: project.recordName)
            projects.removeAll { $0.recordName == project.recordName }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 项目详情 VM
@MainActor
final class ProjectDetailViewModel: ObservableObject {
    @Published var project: ProjectItem
    @Published var isUpdating = false
    @Published var errorMessage: String?
    @Published var showFabricCalc = false

    private let store = ProjectStoreFactory.projectStore
    /// 保存串行队列：所有修改按顺序逐个保存，避免 CloudKit 并发冲突
    private var saveChain: Task<Void, Never>?
    /// 备注防抖任务
    private var notesDebounce: Task<Void, Never>?

    init(project: ProjectItem) {
        self.project = project
    }

    /// 状态流转（PRD 5.9：仅相邻可切换，finished 可重开为 sewing）
    func transitionTo(_ next: ProjectStatus) async {
        guard project.status.canTransition(to: next) else { return }
        project.status = next
        save()
    }

    /// 入队一次保存（与之前的保存串行执行，始终保存最新状态）
    func save() {
        let prev = saveChain
        saveChain = Task { [weak self] in
            guard let self else { return }
            _ = await prev?.value
            await self.performSave()
        }
    }

    /// 备注防抖：停止输入 500ms 后才入队保存
    func notesChanged() {
        notesDebounce?.cancel()
        notesDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func performSave() async {
        isUpdating = true
        do {
            project = try await store.updateProject(project)
        } catch is CancellationError {
        } catch let e as CKError where e.code == .operationCancelled {
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
        isUpdating = false
    }

    /// 添加材料
    func addMaterial(_ item: MaterialItem) {
        project.materials.append(item)
        save()
    }

    /// 删除材料
    func removeMaterial(at indexSet: IndexSet) {
        project.materials.remove(atOffsets: indexSet)
        save()
    }

    /// 从布料计算器结果添加材料（PRD 5.9 工具联动）
    func addFabricResult(meters: Double) {
        let item = MaterialItem(name: "布料",
                                quantity: String(format: "%.1f", meters),
                                unit: "米")
        project.materials.append(item)
        save()
    }

    /// 上传照片
    func addPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var urls: [URL] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let url = MediaUtils.saveJPEGToTemp(data: data, maxWidth: 1024) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }
        do {
            project = try await store.addPhotos(recordName: project.recordName,
                                                  photoURLs: urls)
        } catch {
            errorMessage = "照片上传失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 新建项目 VM
@MainActor
final class ProjectCreateViewModel: ObservableObject {
    @Published var title = ""
    @Published var materials: [MaterialItem] = []
    @Published var patternRecordName: String?
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let store = ProjectStoreFactory.projectStore

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        do {
            let created = try await store.createProject(
                title: title,
                patternRecordName: patternRecordName,
                materials: materials
            )
            _ = created
            isSubmitting = false
            return true
        } catch {
            errorMessage = "创建失败：\(error.localizedDescription)"
            isSubmitting = false
            return false
        }
    }
}
