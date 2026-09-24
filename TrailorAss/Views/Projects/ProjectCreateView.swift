import SwiftUI
import PhotosUI

// MARK: - 新建项目（Sheet 弹出）
struct ProjectCreateView: View {
    @StateObject private var vm = ProjectCreateViewModel()
    @Environment(\.dismiss) private var dismiss

    // 材料临时输入
    @State private var newMaterialName = ""
    @State private var newMaterialQty = ""
    @State private var newMaterialUnit = "米"

    // 关联图纸
    @State private var patterns: [Pattern] = []
    @State private var selectedPatternName: String?
    @State private var photoItems: [PhotosPickerItem] = []

    private let patternService = PatternService()

    var body: some View {
        NavigationStack {
            Form {
                Section("项目名称") {
                    TextField("例如：给女儿的小裙子", text: $vm.title)
                }

                Section("关联图纸（可选）") {
                    if patterns.isEmpty {
                        ProgressView().task { await loadPatterns() }
                    } else {
                        Picker("选择图纸", selection: $selectedPatternName) {
                            Text("不关联").tag(String?.none)
                            ForEach(patterns) { p in
                                Text(p.title).tag(String?.some(p.recordName))
                            }
                        }
                        .onChange(of: selectedPatternName) { _, newValue in
                            vm.patternRecordName = newValue
                        }
                    }
                }

                Section("材料清单") {
                    ForEach(vm.materials) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(String(format: "%.2f %@", item.qty, item.unit))
                                .foregroundColor(.appSubText)
                        }
                    }
                    .onDelete { vm.removeMaterial(at: $0) }

                    HStack {
                        TextField("名称", text: $newMaterialName)
                            .frame(maxWidth: .infinity)
                        TextField("数量", text: $newMaterialQty)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                        TextField("单位", text: $newMaterialUnit)
                            .frame(width: 50)
                        Button {
                            if let qty = Double(newMaterialQty), !newMaterialName.isEmpty {
                                vm.addMaterial(name: newMaterialName, qty: qty, unit: newMaterialUnit)
                                newMaterialName = ""; newMaterialQty = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.appAccent)
                        }
                    }
                }

                Section("备注") {
                    TextEditor(text: $vm.notes).frame(minHeight: 60)
                }

                Section("初始照片（可选）") {
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("选择照片", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: photoItems) { _, items in
                        Task {
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let img = UIImage(data: data) {
                                    await MainActor.run { vm.photos.append(img) }
                                }
                            }
                            photoItems = []
                        }
                    }
                    if !vm.photos.isEmpty {
                        Text("已选 \(vm.photos.count) 张照片").foregroundColor(.appSubText)
                    }
                }

                if let err = vm.errorMessage {
                    Text(err).foregroundColor(.red)
                }

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            if vm.isCreating { ProgressView() }
                            Text("创建项目")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!vm.canSubmit || vm.isCreating)
                }
            }
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onChange(of: vm.createSuccess) { _, success in
                if success { dismiss() }
            }
        }
    }

    private func loadPatterns() async {
        do {
            let (list, _) = try await patternService.fetchPatterns(category: nil, searchKeyword: nil, cursor: nil)
            await MainActor.run { patterns = list }
        } catch {
            // 静默失败，不关联图纸即可
        }
    }
}
