import SwiftUI

// MARK: - 5.2 单位换算
struct UnitConvertView: View {
    @StateObject private var vm = UnitConvertViewModel()

    var body: some View {
        Form {
            Section("输入数值") {
                HStack {
                    TextField("输入数值", text: $vm.inputValue)
                        .keyboardType(.decimalPad)
                    Picker("从", selection: $vm.fromUnit) {
                        ForEach(CalculationUtils.LengthUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("换算结果") {
                HStack {
                    Text(String(format: "%.2f", vm.convertedValue))
                        .foregroundColor(.appAccent)
                        .font(.appHeadline)
                    Spacer()
                    Picker("到", selection: $vm.toUnit) {
                        ForEach(CalculationUtils.LengthUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .navigationTitle("单位换算")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}

// MARK: - 5.3 缩水率计算
struct ShrinkageView: View {
    @StateObject private var vm = ShrinkageViewModel()

    var body: some View {
        Form {
            Section("输入") {
                LabeledField(title: "成品尺寸 L", text: $vm.finishedLength, unit: "cm")
                LabeledField(title: "缩水率 r", text: $vm.shrinkage, unit: "%")
            }
            Section("裁剪尺寸") {
                HStack {
                    Text(String(format: "%.1f cm", vm.cutLength))
                        .foregroundColor(.appAccent)
                        .font(.appHeadline)
                    Spacer()
                }
            }
            Section {
                Text(vm.hintText)
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
            }
        }
        .navigationTitle("缩水率计算")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}
