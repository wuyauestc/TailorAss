//
//  CalculationUtils.swift
//  裁缝助手 —— 计算规则锁定工具（公式来自 PRD 第五节，禁止修改）
//

import Foundation

enum CalculationUtils {

    // MARK: - 5.1 布料用量计算器
    /// 输入：衣片数 N、每片长 L(cm)、每片宽 W(cm)、布料幅宽 F(cm)、缩水率 r(%)
    struct FabricResult: Equatable {
        let meters: Double         // 建议购布米数（向上取整到 0.1 米）
        let piecesPerRow: Int      // 每行可排片数
        let rows: Int              // 所需行数
        let needSplice: Bool       // 是否需要拼接（衣片宽度超过幅宽）
    }

    static func calculateFabric(
        pieceCount N: Int,
        length L: Double,
        width W: Double,
        fabricWidth F: Double,
        shrinkage r: Double
    ) -> FabricResult {
        // 1. 单衣片面积 A = L × W
        _ = L * W
        // 2. 沿幅宽方向每行可排片数 = floor(F ÷ W)，若 <1 则取 1 并提示拼接
        var piecesPerRow = Int((F / W).rounded(.down))
        let needSplice = piecesPerRow < 1
        if piecesPerRow < 1 { piecesPerRow = 1 }
        // 3. 所需行数 = ceil(N ÷ 每行片数)
        let rows = Int(ceil(Double(N) / Double(piecesPerRow)))
        // 4. 用布长度(cm) = 行数 × L
        let fabricLengthCM = Double(rows) * L
        // 5. 考虑缩水：最终长度 = 用布长度 ÷ (1 − r/100)
        let shrinkFactor = 1.0 - (r / 100.0)
        let finalLengthCM = shrinkFactor > 0 ? fabricLengthCM / shrinkFactor : fabricLengthCM
        // 6. 转米并向上取整到 0.1 米
        let meters = ceil((finalLengthCM / 100.0) * 10) / 10
        return FabricResult(meters: meters, piecesPerRow: piecesPerRow, rows: rows, needSplice: needSplice)
    }

    // MARK: - 5.2 单位换算
    /// 码↔米、英尺↔米、英寸↔厘米（统一经厘米换算），保留 2 位小数
    enum LengthUnit: String, CaseIterable, Identifiable {
        case yard = "码"
        case meter = "米"
        case foot = "英尺"
        case inch = "英寸"
        case cm = "厘米"

        var id: String { rawValue }

        /// 转换为厘米的系数
        var toCmFactor: Double {
            switch self {
            case .yard:  return 91.44   // 1 码 = 0.9144 米
            case .meter: return 100
            case .foot:  return 30.48   // 1 英尺 = 0.3048 米
            case .inch:  return 2.54    // 1 英寸 = 2.54 厘米
            case .cm:    return 1
            }
        }
    }

    static func convertLength(value: Double, from: LengthUnit, to: LengthUnit) -> Double {
        let cmValue = value * from.toCmFactor
        let result = cmValue / to.toCmFactor
        return (result * 100).rounded() / 100   // 保留 2 位小数
    }

    // MARK: - 5.3 缩水率计算
    /// 成品尺寸 L(cm)、缩水率 r(%) → 裁剪尺寸 = L ÷ (1 − r/100)，保留 1 位小数
    static func calculateShrinkage(finishedLength L: Double, shrinkage r: Double) -> Double {
        let factor = 1.0 - (r / 100.0)
        let cutLength = factor > 0 ? L / factor : L
        return (cutLength * 10).rounded() / 10
    }

    // MARK: - 5.4 缝份换算
    /// 英制→公制：英寸 × 2.54（保留 1 位小数）
    static func inchToCm(_ inch: Double) -> Double {
        (inch * 2.54 * 10).rounded() / 10
    }

    /// 公制→英制：厘米 ÷ 2.54（保留 2 位小数）
    static func cmToInch(_ cm: Double) -> Double {
        (cm / 2.54 * 100).rounded() / 100
    }

    // MARK: - 5.5 针距换算
    /// 针/英寸 → 针/厘米 = 值 ÷ 2.54（保留 1 位小数）
    static func stitchesPerInchToCm(_ spi: Double) -> Double {
        (spi / 2.54 * 10).rounded() / 10
    }

    /// 针/厘米 → 针/英寸 = 值 × 2.54
    static func stitchesPerCmToInch(_ spcm: Double) -> Double {
        (spcm * 2.54 * 10).rounded() / 10
    }
}

// MARK: - 静态表数据（PRD 5.4 / 5.5 / 5.6 / 5.7，纯本地数据，禁止网络请求）
enum StaticTableData {

    /// 5.4 推荐缝份表
    struct SeamAllowanceItem: Identifiable {
        let id = UUID()
        let seamType: String
        let allowance: String
    }

    static let seamAllowanceTable: [SeamAllowanceItem] = [
        .init(seamType: "平缝", allowance: "1.0 cm"),
        .init(seamType: "包缝（锁边）", allowance: "0.7 cm"),
        .init(seamType: "折边（底摆）", allowance: "2.5 cm"),
        .init(seamType: "弧线部位", allowance: "0.6 cm")
    ]

    /// 5.5 常见针距换算表
    struct StitchConversionItem: Identifiable {
        let id = UUID()
        let spi: String
        let spcm: String
    }

    static let stitchConversionTable: [StitchConversionItem] = [
        .init(spi: "10 针/英寸", spcm: "≈ 3.9 针/厘米"),
        .init(spi: "12 针/英寸", spcm: "≈ 4.7 针/厘米"),
        .init(spi: "14 针/英寸", spcm: "≈ 5.5 针/厘米")
    ]

    /// 5.6 针线搭配表
    struct NeedleThreadItem: Identifiable {
        let id = UUID()
        let fabricType: String
        let needle: String
        let thread: String
    }

    static let needleThreadTable: [NeedleThreadItem] = [
        .init(fabricType: "薄料（雪纺、真丝、薄棉）", needle: "9 号", thread: "细线（60S）"),
        .init(fabricType: "普通面料（棉麻、涤棉）", needle: "11 号", thread: "通用线（50S）"),
        .init(fabricType: "厚料（牛仔、帆布、毛呢）", needle: "14 号", thread: "粗线（40S/30S）"),
        .init(fabricType: "弹性面料（针织、莱卡）", needle: "弹力针（蓝针 11 号）", thread: "弹力线或通用线")
    ]

    /// 5.7 熨烫温度表
    struct IroningTempItem: Identifiable {
        let id = UUID()
        let fabricType: String
        let temperature: String
        let remark: String
    }

    static let ironingTempTable: [IroningTempItem] = [
        .init(fabricType: "棉", temperature: "180℃", remark: "可喷蒸汽"),
        .init(fabricType: "麻", temperature: "200℃", remark: "可喷蒸汽"),
        .init(fabricType: "真丝", temperature: "150℃", remark: "垫布熨烫、禁喷蒸汽"),
        .init(fabricType: "羊毛", temperature: "160℃", remark: "垫布熨烫"),
        .init(fabricType: "化纤（涤纶）", temperature: "120℃", remark: "低温、禁高温")
    ]
}
