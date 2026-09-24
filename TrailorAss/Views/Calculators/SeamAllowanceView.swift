//
//  SeamAllowanceView.swift
//  裁缝助手 —— 5.4 缝份换算 + 推荐缝份表
//

import SwiftUI

struct SeamAllowanceView: View {
    @StateObject private var vm = SeamAllowanceViewModel()

    private var resultUnit: String {
        vm.direction == .inchToCm ? "cm" : "英寸"
    }
    private var resultFractionDigits: Int {
        vm.direction == .inchToCm ? 1 : 2
    }

    var body: some View {
        Form {
            Section("换算方向") {
                Picker("方向", selection: $vm.direction) {
                    ForEach(SeamAllowanceViewModel.Direction.allCases) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("输入数值") {
                LabeledField(
                    title: vm.direction == .inchToCm ? "英寸" : "厘米",
                    text: $vm.input,
                    unit: vm.direction == .inchToCm ? "英寸" : "cm"
                )
            }

            Section("换算结果") {
                HStack {
                    Text("结果")
                        .font(.appBody)
                    Spacer()
                    if let output = vm.output {
                        Text(String(format: "%.\(resultFractionDigits)f %@", output, resultUnit))
                            .font(.appHeadline)
                            .foregroundColor(.appAccent)
                    } else {
                        Text("请输入数值")
                            .font(.appBody)
                            .foregroundColor(.appSubText)
                    }
                }
            }

            Section("推荐缝份表") {
                ForEach(StaticTableData.seamAllowanceTable) { item in
                    HStack {
                        Text(item.seamType)
                            .font(.appBody)
                            .foregroundColor(.appText)
                        Spacer()
                        Text(item.allowance)
                            .font(.appBody)
                            .foregroundColor(.appSubText)
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle("缝份换算")
        .navigationBarTitleDisplayMode(.inline)
    }
}
