//
//  ProjectsTabView.swift
//  裁缝助手 —— M3 项目列表（按状态分组展示）
//

import SwiftUI

struct ProjectsTabView: View {
    @StateObject private var vm = ProjectListViewModel()
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.projects.isEmpty {
                    ProgressView().frame(maxHeight: .infinity)
                } else if vm.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .appBackground()
            .navigationTitle("项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.appAccent)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                ProjectCreateView { newProject in
                    vm.projects.insert(newProject, at: 0)
                }
            }
            .alert("出错了", isPresented: .constant(vm.errorMessage != nil)) {
                Button("好") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .task { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.appAccent)
            Text("还没有项目")
                .font(.appTitle)
                .foregroundColor(.appText)
            Text("点右上角 ＋ 创建第一个缝纫项目吧～")
                .font(.appBody)
                .foregroundColor(.appSubText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectList: some View {
        List {
            ForEach(vm.groupedProjects, id: \.0) { status, items in
                Section {
                    ForEach(items) { project in
                        NavigationLink {
                            ProjectDetailView(project: project) { updated in
                                if let idx = vm.projects.firstIndex(where: {
                                    $0.recordName == updated.recordName
                                }) {
                                    vm.projects[idx] = updated
                                }
                            } onDelete: {
                                Task { await vm.delete(project) }
                            }
                        } label: {
                            ProjectRow(project: project)
                        }
                    }
                } header: {
                    Label(status.rawValue, systemImage: status.iconName)
                        .font(.appHeadline)
                        .foregroundColor(.appAccent)
                }
            }
        }
    }
}

// MARK: - 项目行
struct ProjectRow: View {
    let project: ProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title)
                .font(.appHeadline)
                .foregroundColor(.appText)
            HStack(spacing: 8) {
                Image(systemName: project.status.iconName)
                    .font(.caption)
                    .foregroundColor(.appAccent)
                Text(project.status.rawValue)
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
                if !project.materials.isEmpty {
                    Text("· \(project.materials.count) 件材料")
                        .font(.appCaption)
                        .foregroundColor(.appSubText)
                }
            }
            if !project.notes.isEmpty {
                Text(project.notes)
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
