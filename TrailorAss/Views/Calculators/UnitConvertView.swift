//
//  UnitConvertView.swift
//  裁缝助手 —— 5.2 单位换算（码↔米、英尺↔米、英寸↔厘米，即时出结果）
//

import SwiftUI

struct UnitConvertView: View {
    @StateObject private var vm = UnitConvertViewModel()

    var body: some View {
        Form {
            Section("从单位 → 到单位") {
                Picker("从", selection: $vm.fromUnit) {
                    ForEach(CalculationUtils.LengthUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        vm.swap()
                    } label: {
                        Label("交换", systemImage: "arrow.up.arrow.down")
                            .font(.appCaption)
                    }
                    .buttonStyle(.borderless)
                }
                Picker("到", selection: $vm.toUnit) {
                    ForEach(CalculationUtils.LengthUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
            }

            Section("输入数值") {
                LabeledField(title: vm.fromUnit.rawValue, text: $vm.input, unit: vm.fromUnit.rawValue)
            }

            Section("换算结果") {
                HStack {
                    Text("结果")
                        .font(.appBody)
                    Spacer()
                    if let output = vm.output {
                        Text(String(format: "%.2f %@", output, vm.toUnit.rawValue))
                            .font(.appHeadline)
                            .foregroundColor(.appAccent)
                    } else {
                        Text("请输入数值")
                            .font(.appBody)
                            .foregroundColor(.appSubText)
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle("单位换算")
        .navigationBarTitleDisplayMode(.inline)
    }
}
