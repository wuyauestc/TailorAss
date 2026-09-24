//
//  StitchDensityView.swift
//  裁缝助手 —— 5.5 针距换算 + 常见换算表
//

import SwiftUI

struct StitchDensityView: View {
    @StateObject private var vm = StitchDensityViewModel()

    private var inputUnit: String {
        vm.direction == .inchToCm ? "针/英寸" : "针/厘米"
    }
    private var resultUnit: String {
        vm.direction == .inchToCm ? "针/厘米" : "针/英寸"
    }

    var body: some View {
        Form {
            Section("换算方向") {
                Picker("方向", selection: $vm.direction) {
                    ForEach(StitchDensityViewModel.Direction.allCases) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("输入数值") {
                LabeledField(title: "针距密度", text: $vm.input, unit: inputUnit)
            }

            Section("换算结果") {
                HStack {
                    Text("结果")
                        .font(.appBody)
                    Spacer()
                    if let output = vm.output {
                        Text(String(format: "%.1f %@", output, resultUnit))
                            .font(.appHeadline)
                            .foregroundColor(.appAccent)
                    } else {
                        Text("请输入数值")
                            .font(.appBody)
                            .foregroundColor(.appSubText)
                    }
                }
            }

            Section("常见换算表") {
                ForEach(StaticTableData.stitchConversionTable) { item in
                    HStack {
                        Text(item.spi)
                            .font(.appBody)
                            .foregroundColor(.appText)
                        Spacer()
                        Text(item.spcm)
                            .font(.appBody)
                            .foregroundColor(.appSubText)
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle("针距换算")
        .navigationBarTitleDisplayMode(.inline)
    }
}
