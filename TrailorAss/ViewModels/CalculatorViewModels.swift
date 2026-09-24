import Foundation

// MARK: - 5.1 布料用量计算器
final class FabricCalcViewModel: ObservableObject {
    @Published var pieceCount: String = "2"
    @Published var length: String = "60"       // cm
    @Published var width: String = "50"        // cm
    @Published var fabricWidth: String = "150" // cm
    @Published var shrinkage: String = "0"     // %

    @Published private(set) var result: CalculationUtils.FabricResult?
    @Published var errorMessage: String?

    func calculate() {
        errorMessage = nil
        guard let N = Int(pieceCount), N > 0,
              let L = Double(length), L > 0,
              let W = Double(width), W > 0,
              let F = Double(fabricWidth), F > 0,
              let r = Double(shrinkage), r >= 0 else {
            errorMessage = "请输入有效的数值"
            result = nil
            return
        }
        result = CalculationUtils.calculateFabric(pieceCount: N, length: L, width: W, fabricWidth: F, shrinkage: r)
    }

    /// 工具联动：把计算结果转为材料条目（名称"布料"、数量=结果、单位"米"）
    func asMaterialItem() -> MaterialItem? {
        guard let r = result else { return nil }
        return MaterialItem(name: "布料", qty: r.meters, unit: "米")
    }
}

// MARK: - 5.2 单位换算
final class UnitConvertViewModel: ObservableObject {
    @Published var inputValue: String = "1"
    @Published var fromUnit: CalculationUtils.LengthUnit = .yard
    @Published var toUnit: CalculationUtils.LengthUnit = .meter

    var convertedValue: Double {
        guard let v = Double(inputValue) else { return 0 }
        return CalculationUtils.convertLength(value: v, from: fromUnit, to: toUnit)
    }
}

// MARK: - 5.3 缩水率计算
final class ShrinkageViewModel: ObservableObject {
    @Published var finishedLength: String = "100" // cm
    @Published var shrinkage: String = "5"        // %

    var cutLength: Double {
        guard let L = Double(finishedLength), let r = Double(shrinkage) else { return 0 }
        return CalculationUtils.calculateShrinkage(finishedLength: L, shrinkage: r)
    }

    var hintText: String {
        "布料下水后缩水 \(shrinkage)%，裁剪需预留；建议先预缩再裁剪"
    }
}

// MARK: - 5.4 缝份换算
final class SeamAllowanceViewModel: ObservableObject {
    @Published var inchInput: String = ""
    @Published var cmInput: String = ""

    /// 英制→公制
    var cmFromInch: Double? {
        guard let v = Double(inchInput), !inchInput.isEmpty else { return nil }
        return CalculationUtils.inchToCm(v)
    }

    /// 公制→英制
    var inchFromCm: Double? {
        guard let v = Double(cmInput), !cmInput.isEmpty else { return nil }
        return CalculationUtils.cmToInch(v)
    }
}

// MARK: - 5.5 针距换算
final class StitchDensityViewModel: ObservableObject {
    @Published var spiInput: String = ""    // 针/英寸
    @Published var spcmInput: String = ""   // 针/厘米

    var spcmFromSpi: Double? {
        guard let v = Double(spiInput), !spiInput.isEmpty else { return nil }
        return CalculationUtils.stitchesPerInchToCm(v)
    }

    var spiFromSpcm: Double? {
        guard let v = Double(spcmInput), !spcmInput.isEmpty else { return nil }
        return CalculationUtils.stitchesPerCmToInch(v)
    }
}
