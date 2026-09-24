import Foundation
import CloudKit
import UIKit

// MARK: - 项目列表（按状态分组）
final class ProjectsViewModel: ObservableObject {
    @Published var projects: [SewingProject] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = ProjectService()

    /// 按状态分组
    var groupedByStatus: [(status: AppConstants.ProjectStatus, items: [SewingProject])] {
        AppConstants.ProjectStatus.allCases.map { status in
            (status, projects.filter { $0.status == status })
        }.filter { !$0.items.isEmpty }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await service.fetchProjects()
            await MainActor.run { self.projects = list }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
    }
}

// MARK: - 项目详情
final class ProjectDetailViewModel: ObservableObject {
    @Published var project: SewingProject
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let service = ProjectService()

    init(project: SewingProject) {
        self.project = project
    }

    // MARK: 状态流转：仅相邻状态可切换，finished 可重新打开为 sewing
    func transition(to next: AppConstants.ProjectStatus) {
        guard project.status.canTransition(to: next) else { return }
        project.status = next
        Task { await save() }
    }

    // MARK: 材料增删
    func addMaterial(_ item: MaterialItem) {
        project.materials.append(item)
        Task { await save() }
    }

    func removeMaterial(at offsets: IndexSet) {
        project.materials.remove(atOffsets: offsets)
        Task { await save() }
    }

    // MARK: 备注
    func updateNotes(_ notes: String) {
        project.notes = notes
    }

    // MARK: 工具联动：把布料计算器结果加入材料清单
    func addFabricMaterial(_ item: MaterialItem) {
        project.materials.append(item)
        Task { await save() }
    }

    // MARK: 保存
    func save() async {
        isSaving = true
        do {
            let updated = try await service.updateProject(project)
            await MainActor.run { self.project = updated }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isSaving = false }
    }

    // MARK: 上传照片
    func uploadPhotos(_ images: [UIImage]) async {
        isSaving = true
        do {
            let updated = try await service.updateProject(project, photos: images)
            await MainActor.run { self.project = updated }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isSaving = false }
    }
}

// MARK: - 新建项目
final class ProjectCreateViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var patternRecordName: String?
    @Published var materials: [MaterialItem] = []
    @Published var notes: String = ""
    @Published var photos: [UIImage] = []
    @Published var isCreating = false
    @Published var errorMessage: String?
    @Published var createSuccess = false

    private let service = ProjectService()

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func addMaterial(name: String, qty: Double, unit: String) {
        materials.append(MaterialItem(name: name, qty: qty, unit: unit))
    }

    func removeMaterial(at offsets: IndexSet) {
        materials.remove(atOffsets: offsets)
    }

    func submit() async {
        guard canSubmit else { return }
        isCreating = true
        do {
            _ = try await service.createProject(
                title: title,
                patternRecordName: patternRecordName,
                materials: materials,
                notes: notes,
                photos: photos
            )
            await MainActor.run { createSuccess = true }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isCreating = false }
    }
}
