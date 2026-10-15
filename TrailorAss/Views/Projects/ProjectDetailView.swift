//
//  ProjectDetailView.swift
//  裁缝助手 —— M3 项目详情（状态流转/材料/备注/照片/工具联动）
//

import SwiftUI
import PhotosUI

struct ProjectDetailView: View {
    @StateObject private var vm: ProjectDetailViewModel
    @Environment(\.dismiss) private var dismiss

    let onUpdated: (ProjectItem) -> Void
    let onDelete: () -> Void

    @State private var newMaterialName = ""
    @State private var newMaterialQty = ""
    @State private var newMaterialUnit = "米"
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showDeleteConfirm = false

    init(project: ProjectItem,
         onUpdated: @escaping (ProjectItem) -> Void,
         onDelete: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: ProjectDetailViewModel(project: project))
        self.onUpdated = onUpdated
        self.onDelete = onDelete
    }

    var body: some View {
        Form {
            // MARK: 状态流转
            Section("状态") {
                HStack(spacing: 8) {
                    ForEach(ProjectStatus.allCases) { status in
                        let canGo = vm.project.status.canTransition(to: status)
                        let isCurrent = vm.project.status == status
                        Button {
                            Task { await vm.transitionTo(status) }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: status.iconName)
                                    .font(.system(size: 18))
                                Text(status.rawValue)
                                    .font(.appCaption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                isCurrent ? Color.appAccent.opacity(0.15)
                                          : Color.gray.opacity(0.06)
                            )
                            .cornerRadius(8)
                        }
                        .foregroundColor(isCurrent ? .appAccent : .appSubText)
                        .disabled(!canGo && !isCurrent)
                    }
                }
            }

            // MARK: 材料清单
            Section("材料清单") {
                ForEach(vm.project.materials) { m in
                    HStack {
                        Text(m.name).foregroundColor(.appText)
                        Spacer()
                        Text("\(m.quantity) \(m.unit)")
                            .foregroundColor(.appSubText)
                    }
                }
                .onDelete { idx in vm.removeMaterial(at: idx) }

                HStack {
                    TextField("材料名", text: $newMaterialName)
                        .frame(maxWidth: 100)
                    TextField("数量", text: $newMaterialQty)
                        .frame(maxWidth: 60)
                    Picker("", selection: $newMaterialUnit) {
                        ForEach(["米", "厘米", "码", "个", "条", "片"], id: \.self) {
                            Text($0).font(.caption)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 80)
                    Button {
                        guard !newMaterialName.trimmingCharacters(in: .whitespaces).isEmpty,
                              !newMaterialQty.trimmingCharacters(in: .whitespaces).isEmpty
                        else { return }
                        vm.addMaterial(MaterialItem(name: newMaterialName,
                                                     quantity: newMaterialQty,
                                                     unit: newMaterialUnit))
                        newMaterialName = ""
                        newMaterialQty = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                }

                // PRD 5.9 工具联动：布料计算器入口
                NavigationLink {
                    FabricCalcViewForProject { meters in
                        vm.addFabricResult(meters: meters)
                    }
                } label: {
                    Label("用布料计算器", systemImage: "ruler")
                        .foregroundColor(.appAccent)
                }
            }

            // MARK: 备注
            Section("备注") {
                TextEditor(text: $vm.project.notes)
                    .frame(minHeight: 80)
                    .onChange(of: vm.project.notes) { _, _ in
                        vm.notesChanged()
                    }
            }

            // MARK: 照片
            Section("成品/过程照片") {
                if !vm.project.photoURLs.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()),
                                        GridItem(.flexible())],
                              spacing: 8) {
                        ForEach(vm.project.photoURLs, id: \.self) { url in
                            if let img = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 120)
                                    .clipped()
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10,
                             matching: .images) {
                    Label("添加照片", systemImage: "photo.badge.plus")
                        .foregroundColor(.appAccent)
                }
                .onChange(of: photoItems) { _, items in
                    Task { await vm.addPhotos(items) }
                }
            }

            // MARK: 排料方案（M5b）
            Section("排料方案") {
                if vm.layouts.isEmpty {
                    NavigationLink {
                        LayoutBoardView(editingLayout: nil,
                                        projectRecordName: vm.project.recordName) {
                            Task { await vm.loadLayouts() }
                        }
                    } label: {
                        Label("新建排料方案", systemImage: "plus.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                } else {
                    ForEach(vm.layouts) { layout in
                        NavigationLink {
                            LayoutBoardView(editingLayout: layout,
                                            projectRecordName: nil) {
                                Task { await vm.loadLayouts() }
                            }
                        } label: {
                            LayoutRow(layout: layout)
                        }
                    }
                    .onDelete { idx in
                        Task {
                            for index in idx {
                                let layout = vm.layouts[index]
                                try? await LayoutStoreFactory.layoutStore
                                    .deleteLayout(recordName: layout.recordName)
                            }
                            await vm.loadLayouts()
                        }
                    }
                    NavigationLink {
                        LayoutBoardView(editingLayout: nil,
                                        projectRecordName: vm.project.recordName) {
                            Task { await vm.loadLayouts() }
                        }
                    } label: {
                        Label("新建排料方案", systemImage: "plus.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                }
            }

            // MARK: 删除
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("删除项目")
                }
            }
        }
        .appBackground()
        .navigationTitle(vm.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("删除后无法恢复")
        }
        .alert("出错了", isPresented: .constant(vm.errorMessage != nil)) {
            Button("好") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .onChange(of: vm.project) { _, newProject in
            onUpdated(newProject)
        }
        // M5b 进入详情页时拉取关联的排料方案
        .task { await vm.loadLayouts() }
        // 从画板返回时刷新方案列表
        .onAppear { Task { await vm.loadLayouts() } }
    }
}

// MARK: - 布料计算器（项目内嵌版，计算完回调加入材料）
struct FabricCalcViewForProject: View {
    @StateObject private var calcVM = FabricCalcViewModel()
    let onResult: (Double) -> Void

    var body: some View {
        Form {
            Section("输入参数") {
                LabeledField(title: "衣片数 N", text: $calcVM.pieceCount, unit: "片")
                LabeledField(title: "每片长 L", text: $calcVM.length, unit: "cm")
                LabeledField(title: "每片宽 W", text: $calcVM.width, unit: "cm")
                LabeledField(title: "布料幅宽 F", text: $calcVM.fabricWidth, unit: "cm")
                LabeledField(title: "缩水率 r", text: $calcVM.shrinkage, unit: "%")
            }
            Section {
                Button("计算") { calcVM.calculate() }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.appAccent)
                    .foregroundColor(.white)
            }
            if let result = calcVM.result {
                Section("计算结果") {
                    ResultRow(title: "建议购布",
                              value: String(format: "%.1f 米", result.meters),
                              highlight: true)
                    ResultRow(title: "每行可排片数", value: "\(result.piecesPerRow) 片")
                    ResultRow(title: "所需行数", value: "\(result.rows) 行")
                    Button {
                        onResult(result.meters)
                    } label: {
                        Label("加入项目材料", systemImage: "plus.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                }
            }
            if let error = calcVM.errorMessage {
                Section {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .appBackground()
        .navigationTitle("布料计算器")
        .navigationBarTitleDisplayMode(.inline)
    }
}
