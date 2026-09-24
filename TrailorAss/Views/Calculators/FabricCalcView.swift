//
//  FabricCalcView.swift
//  裁缝助手 —— 5.1 布料用量计算器
//

import SwiftUI

struct FabricCalcView: View {
    @StateObject private var vm = FabricCalcViewModel()

    var body: some View {
        Form {
            Section("输入参数") {
                LabeledField(title: "衣片数 N", text: $vm.pieceCount, unit: "片")
                LabeledField(title: "每片长 L", text: $vm.length, unit: "cm")
                LabeledField(title: "每片宽 W", text: $vm.width, unit: "cm")
                LabeledField(title: "布料幅宽 F", text: $vm.fabricWidth, unit: "cm")
                LabeledField(title: "缩水率 r", text: $vm.shrinkage, unit: "%")
            }

            Section {
                Button {
                    vm.calculate()
                } label: {
                    Text("计算")
                        .font(.appHeadline)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.appAccent)
                .foregroundColor(.white)
            }

            if let result = vm.result {
                Section("计算结果") {
                    ResultRow(title: "建议购布",
                              value: String(format: "%.1f 米", result.meters),
                              highlight: true)
                    ResultRow(title: "每行可排片数", value: "\(result.piecesPerRow) 片")
                    ResultRow(title: "所需行数", value: "\(result.rows) 行")
                    if result.needSplice {
                        Label("衣片宽度超过幅宽，需拼接", systemImage: "exclamationmark.triangle.fill")
                            .font(.appBody)
                            .foregroundColor(.orange)
                    }
                }
            }

            if let error = vm.errorMessage {
                Section {
                    Label(error, systemImage: "xmark.circle.fill")
                        .font(.appBody)
                        .foregroundColor(.red)
                }
            }
        }
        .appBackground()
        .navigationTitle("布料用量计算器")
        .navigationBarTitleDisplayMode(.inline)
    }
}
