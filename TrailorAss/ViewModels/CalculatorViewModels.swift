//
//  CalculatorViewModels.swift
//  裁缝助手 —— M1 计算器视图模型（MVVM 轻量分层）
//

import Foundation
import Combine

/// 字符串数字解析（容忍空格与中文逗号）
enum NumberParser {
    static func double(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "，", with: ".")
        return Double(trimmed)
    }

    static func int(_ text: String) -> Int? {
        guard let d = double(text) else { return nil }
        return Int(d.rounded())
    }
}

// MARK: - 5.1 布料用量计算器
final class FabricCalcViewModel: ObservableObject {
    @Published var pieceCount = ""
    @Published var length = ""
    @Published var width = ""
    @Published var fabricWidth = ""
    @Published var shrinkage = ""
    @Published var result: CalculationUtils.FabricResult?
    @Published var errorMessage: String?

    func calculate() {
        guard let n = NumberParser.int(pieceCount), n >= 1 else {
            fail("请输入有效的衣片数（≥1 的整数）"); return
        }
        guard let l = NumberParser.double(length), l > 0 else {
            fail("请输入有效的每片长 L（cm）"); return
        }
        guard let w = NumberParser.double(width), w > 0 else {
            fail("请输入有效的每片宽 W（cm）"); return
        }
        guard let f = NumberParser.double(fabricWidth), f > 0 else {
            fail("请输入有效的布料幅宽 F（cm）"); return
        }
        guard let r = NumberParser.double(shrinkage), r >= 0 else {
            fail("请输入有效的缩水率 r（%）"); return
        }
        errorMessage = nil
        result = CalculationUtils.calculateFabric(
            pieceCount: n, length: l, width: w, fabricWidth: f, shrinkage: r
        )
    }

    private func fail(_ message: String) {
        errorMessage = message
        result = nil
    }
}

// MARK: - 5.2 单位换算
final class UnitConvertViewModel: ObservableObject {
    @Published var input = ""
    @Published var fromUnit: CalculationUtils.LengthUnit = .yard {
        didSet { if fromUnit == toUnit { toUnit = oldValue } }
    }
    @Published var toUnit: CalculationUtils.LengthUnit = .meter {
        didSet { if toUnit == fromUnit { fromUnit = oldValue } }
    }

    /// 即时换算结果（保留 2 位小数）；输入无效时为 nil
    var output: Double? {
        guard let value = NumberParser.double(input) else { return nil }
        return CalculationUtils.convertLength(value: value, from: fromUnit, to: toUnit)
    }

    func swap() {
        let f = fromUnit
        fromUnit = toUnit
        toUnit = f
    }
}

// MARK: - 5.3 缩水率计算
final class ShrinkageViewModel: ObservableObject {
    @Published var finishedLength = ""
    @Published var shrinkage = ""

    /// 裁剪尺寸（保留 1 位小数）
    var cutLength: Double? {
        guard let l = NumberParser.double(finishedLength), l > 0,
              let r = NumberParser.double(shrinkage), r >= 0 else { return nil }
        return CalculationUtils.calculateShrinkage(finishedLength: l, shrinkage: r)
    }
}

// MARK: - 5.4 缝份换算
final class SeamAllowanceViewModel: ObservableObject {
    enum Direction: String, CaseIterable, Identifiable {
        case inchToCm = "英制 → 公制"
        case cmToInch = "公制 → 英制"
        var id: String { rawValue }
    }

    @Published var direction: Direction = .inchToCm
    @Published var input = ""

    var output: Double? {
        guard let value = NumberParser.double(input) else { return nil }
        switch direction {
        case .inchToCm: return CalculationUtils.inchToCm(value)
        case .cmToInch: return CalculationUtils.cmToInch(value)
        }
    }
}

// MARK: - 5.5 针距换算
final class StitchDensityViewModel: ObservableObject {
    enum Direction: String, CaseIterable, Identifiable {
        case inchToCm = "针/英寸 → 针/厘米"
        case cmToInch = "针/厘米 → 针/英寸"
        var id: String { rawValue }
    }

    @Published var direction: Direction = .inchToCm
    @Published var input = ""

    var output: Double? {
        guard let value = NumberParser.double(input) else { return nil }
        switch direction {
        case .inchToCm: return CalculationUtils.stitchesPerInchToCm(value)
        case .cmToInch: return CalculationUtils.stitchesPerCmToInch(value)
        }
    }
}
