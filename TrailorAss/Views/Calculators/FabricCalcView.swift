import SwiftUI

// MARK: - 5.1 布料用量计算器
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

            Button("计算") {
                vm.calculate()
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .listRowBackground(Color.appAccent)

            if let result = vm.result {
                Section("计算结果") {
                    HStack {
                        Text("建议购布")
                        Spacer()
                        Text(String(format: "%.1f 米", result.meters))
                            .foregroundColor(.appAccent)
                            .font(.appHeadline)
                    }
                    HStack {
                        Text("每行可排片数")
                        Spacer()
                        Text("\(result.piecesPerRow) 片")
                    }
                    HStack {
                        Text("所需行数")
                        Spacer()
                        Text("\(result.rows) 行")
                    }
                    if result.needSplice {
                        Text("⚠️ 衣片宽度超过幅宽，需拼接")
                            .foregroundColor(.orange)
                    }
                }
            }

            if let err = vm.errorMessage {
                Text(err).foregroundColor(.red)
            }
        }
        .navigationTitle("布料用量计算器")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}

struct LabeledField: View {
    let title: String
    @Binding var text: String
    let unit: String
    var body: some View {
        HStack {
            Text(title)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundColor(.appSubText)
        }
    }
}
