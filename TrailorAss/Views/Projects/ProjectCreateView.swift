//
//  ProjectCreateView.swift
//  裁缝助手 —— M3 新建项目（Sheet 弹出）
//

import SwiftUI

struct ProjectCreateView: View {
    @StateObject private var vm = ProjectCreateViewModel()
    @Environment(\.dismiss) private var dismiss

    let onCreated: (ProjectItem) -> Void

    @State private var newMaterialName = ""
    @State private var newMaterialQty = ""
    @State private var newMaterialUnit = "米"

    var body: some View {
        NavigationStack {
            Form {
                Section("项目信息") {
                    TextField("项目名称（如：给女儿的小裙子）", text: $vm.title)
                }

                Section("材料清单（可选）") {
                    ForEach(vm.materials) { m in
                        HStack {
                            Text(m.name).foregroundColor(.appText)
                            Spacer()
                            Text("\(m.quantity) \(m.unit)")
                                .foregroundColor(.appSubText)
                        }
                    }
                    .onDelete { idx in vm.materials.remove(atOffsets: idx) }

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
                            addMaterial()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.appAccent)
                        }
                    }
                }
            }
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("创建") {
                        Task {
                            if await vm.submit() {
                                // 由于 CloudKit 是异步的，这里通知父视图刷新
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.canSubmit || vm.isSubmitting)
                }
            }
            .alert("出错了", isPresented: .constant(vm.errorMessage != nil)) {
                Button("好") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private func addMaterial() {
        guard !newMaterialName.trimmingCharacters(in: .whitespaces).isEmpty,
              !newMaterialQty.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vm.materials.append(MaterialItem(name: newMaterialName,
                                           quantity: newMaterialQty,
                                           unit: newMaterialUnit))
        newMaterialName = ""
        newMaterialQty = ""
    }
}
