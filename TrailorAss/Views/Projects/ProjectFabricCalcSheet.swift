import SwiftUI

// MARK: - 项目内调用布料计算器（计算后一键加入材料清单）
struct ProjectFabricCalcSheet: View {
    @EnvironmentObject var projectVM: ProjectDetailViewModel
    @StateObject private var calcVM = FabricCalcViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("输入参数") {
                    LabeledField(title: "衣片数 N", text: $calcVM.pieceCount, unit: "片")
                    LabeledField(title: "每片长 L", text: $calcVM.length, unit: "cm")
                    LabeledField(title: "每片宽 W", text: $calcVM.width, unit: "cm")
                    LabeledField(title: "布料幅宽 F", text: $calcVM.fabricWidth, unit: "cm")
                    LabeledField(title: "缩水率 r", text: $calcVM.shrinkage, unit: "%")
                }

                Button("计算") { calcVM.calculate() }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .listRowBackground(Color.appAccent)

                if let result = calcVM.result {
                    Section("计算结果") {
                        HStack {
                            Text("建议购布")
                            Spacer()
                            Text(String(format: "%.1f 米", result.meters))
                                .foregroundColor(.appAccent)
                                .font(.appHeadline)
                        }
                        Text("每行可排 \(result.piecesPerRow) 片，共 \(result.rows) 行")
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                        if result.needSplice {
                            Text("⚠️ 衣片宽度超过幅宽，需拼接").foregroundColor(.orange)
                        }
                    }

                    Section {
                        Button {
                            if let item = calcVM.asMaterialItem() {
                                projectVM.addFabricMaterial(item)
                                dismiss()
                            }
                        } label: {
                            Label("加入材料清单", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                if let err = calcVM.errorMessage {
                    Text(err).foregroundColor(.red)
                }
            }
            .navigationTitle("布料用量计算器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}
