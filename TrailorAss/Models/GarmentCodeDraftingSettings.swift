import Foundation

/// Manufacture annotations are separate from the official pattern JSON and
/// never change the source garment's geometry or stitch references.
struct GarmentCodeDraftingSettings: Codable, Equatable {
    enum EdgeKind: String, Codable, CaseIterable, Identifiable {
        case seam, hem, fold, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .seam: "普通接缝"
            case .hem: "下摆折边"
            case .fold: "对折边（不加缝份）"
            case .none: "不加缝份"
            }
        }
    }

    struct EdgeTreatment: Codable, Equatable {
        var kind: EdgeKind = .seam
        /// Nil follows the corresponding global width, including later edits.
        var customWidthCM: Double?
    }

    struct Grainline: Codable, Equatable {
        /// Degrees counter-clockwise from the original panel's local x axis.
        var angleDegrees: Double = 90
        var centerXRatio: Double = 0.5
        var centerYRatio: Double = 0.5
        var lengthRatio: Double = 0.6
    }

    struct PanelSettings: Codable, Equatable {
        var edges: [Int: EdgeTreatment] = [:]
        var grainline: Grainline?
        var cutQuantity: Int = 1
    }

    var addSeamAllowance = false
    var standardAllowanceCM: Double = 1
    var hemAllowanceCM: Double = 3
    var showNotches = false
    var panels: [String: PanelSettings] = [:]

    func panelSettings(_ name: String) -> PanelSettings { panels[name] ?? .init() }

    func treatment(panel: String, edge: Int, stitches: [GarmentCodeStitch]) -> EdgeTreatment {
        if let treatment = panels[panel]?.edges[edge] { return treatment }
        // Never silently treat the inner legs of a dart like an ordinary
        // outside seam: widening them can erase the dart opening.
        let isDart = stitches.contains { stitch in
            stitch.sides.count == 2 && stitch.sides.allSatisfy { $0.panel == panel } &&
                stitch.sides.contains { $0.edge == edge }
        }
        return .init(kind: isDart ? .none : .seam)
    }

    func widthCM(for treatment: EdgeTreatment) -> Double {
        switch treatment.kind {
        case .fold, .none: 0
        case .seam: treatment.customWidthCM ?? standardAllowanceCM
        case .hem: treatment.customWidthCM ?? hemAllowanceCM
        }
    }

    mutating func setTreatment(_ treatment: EdgeTreatment, panel: String, edge: Int) {
        var value = panelSettings(panel)
        value.edges[edge] = treatment
        panels[panel] = value
    }

    func validate(document: GarmentCodePatternFile) throws {
        func reject(_ message: String) throws { throw ValidationError.invalid(message) }
        guard standardAllowanceCM.isFinite, hemAllowanceCM.isFinite,
              (0...5).contains(standardAllowanceCM), (0...5).contains(hemAllowanceCM) else {
            return try reject("缝份与折边宽度必须在 0～5 cm 之间。")
        }
        for (name, settings) in panels {
            guard let panel = document.pattern.panels[name] else {
                return try reject("制作设置引用了不存在的裁片，请恢复设置后重试。")
            }
            guard (1...20).contains(settings.cutQuantity) else {
                return try reject("每个裁片的裁剪数量必须在 1～20 片之间。")
            }
            for (index, treatment) in settings.edges {
                guard panel.edges.indices.contains(index) else {
                    return try reject("制作设置引用了不存在的边，请恢复该片设置。")
                }
                let width = widthCM(for: treatment)
                guard width.isFinite, (0...5).contains(width) else {
                    return try reject("逐边缝份宽度必须在 0～5 cm 之间。")
                }
                if treatment.kind == .fold, document.edgeIsStitched(panel: name, edge: index) {
                    return try reject("已配对缝合的边不能设为对折边，请先确认原纸样结构。")
                }
            }
            if let grain = settings.grainline {
                guard [grain.angleDegrees, grain.centerXRatio, grain.centerYRatio, grain.lengthRatio].allSatisfy(\.isFinite),
                      (-180...180).contains(grain.angleDegrees),
                      (0...1).contains(grain.centerXRatio), (0...1).contains(grain.centerYRatio),
                      (0.1...0.9).contains(grain.lengthRatio) else {
                    return try reject("布纹线角度须为 -180～180°，位置须在裁片范围内，长度比例须为 0.1～0.9。")
                }
            }
        }
    }

    enum ValidationError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { switch self { case let .invalid(message): message } }
    }
}
