import SwiftUI

// MARK: - 5.4 缝份换算 + 推荐缝份表
struct SeamAllowanceView: View {
    @StateObject private var vm = SeamAllowanceViewModel()

    var body: some View {
        Form {
            Section("英制 → 公制（英寸 → 厘米）") {
                HStack {
                    TextField("英寸", text: $vm.inchInput)
                        .keyboardType(.decimalPad)
                    Text("英寸")
                }
                if let cm = vm.cmFromInch {
                    HStack {
                        Text("= \(String(format: "%.1f", cm)) cm")
                            .foregroundColor(.appAccent)
                            .font(.appHeadline)
                        Spacer()
                    }
                }
            }

            Section("公制 → 英制（厘米 → 英寸）") {
                HStack {
                    TextField("厘米", text: $vm.cmInput)
                        .keyboardType(.decimalPad)
                    Text("厘米")
                }
                if let inch = vm.inchFromCm {
                    HStack {
                        Text("= \(String(format: "%.2f", inch)) 英寸")
                            .foregroundColor(.appAccent)
                            .font(.appHeadline)
                        Spacer()
                    }
                }
            }

            Section("推荐缝份表") {
                ForEach(StaticTableData.seamAllowanceTable) { item in
                    HStack {
                        Text(item.seamType)
                        Spacer()
                        Text(item.allowance).foregroundColor(.appSubText)
                    }
                }
            }
        }
        .navigationTitle("缝份换算")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}

// MARK: - 5.5 针距换算
struct StitchDensityView: View {
    @StateObject private var vm = StitchDensityViewModel()

    var body: some View {
        Form {
            Section("针/英寸 → 针/厘米") {
                HStack {
                    TextField("针/英寸", text: $vm.spiInput)
                        .keyboardType(.decimalPad)
                    Text("针/英寸")
                }
                if let spcm = vm.spcmFromSpi {
                    HStack {
                        Text("= \(String(format: "%.1f", spcm)) 针/厘米")
                            .foregroundColor(.appAccent)
                            .font(.appHeadline)
                        Spacer()
                    }
                }
            }

            Section("针/厘米 → 针/英寸") {
                HStack {
                    TextField("针/厘米", text: $vm.spcmInput)
                        .keyboardType(.decimalPad)
                    Text("针/厘米")
                }
                if let spi = vm.spiFromSpcm {
                    HStack {
                        Text("= \(String(format: "%.1f", spi)) 针/英寸")
                            .foregroundColor(.appAccent)
                            .font(.appHeadline)
                        Spacer()
                    }
                }
            }

            Section("常见换算") {
                ForEach(StaticTableData.stitchConversionTable) { item in
                    HStack {
                        Text(item.spi)
                        Spacer()
                        Text(item.spcm).foregroundColor(.appSubText)
                    }
                }
            }
        }
        .navigationTitle("针距换算")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}
