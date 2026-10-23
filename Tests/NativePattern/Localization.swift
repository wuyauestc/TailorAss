import Foundation

@main
struct PatternLocalizationCoverage {
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repo = root.deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try GarmentCodeParameterCatalog.load(from: repo.appendingPathComponent(
            "TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        var count = 0
        func visit(_ node: GarmentCodeParameterNode, path: [String]) {
            if node.hasValueKey, node.type != nil {
                guard let field = GarmentCodeChinese.parameter(path) else {
                    preconditionFailure("Missing Chinese parameter: \(path.joined(separator: "."))")
                }
                precondition(!field.title.isEmpty && !field.detail.isEmpty)
                for value in node.range ?? [] {
                    if case let .string(option) = value {
                        precondition(GarmentCodeChinese.options[option] != nil, "Missing option: \(option)")
                    }
                }
                count += 1
            }
            for (key, child) in node.children { visit(child, path: path + [key]) }
        }
        for (key, node) in catalog.design { visit(node, path: [key]) }
        precondition(Set(catalog.body.keys) == Set(GarmentCodeChinese.body.keys))
        precondition(Set(GarmentCodeChinese.bodyOrder) == Set(catalog.body.keys))
        precondition(GarmentCodeChinese.bodyOrder.count == catalog.body.count)
        // Same English leaf key has different meanings and units in context.
        precondition(GarmentCodeChinese.parameter(["waistband", "width"])?.title == "腰头高度比例")
        precondition(GarmentCodeChinese.parameter(["shirt", "width"])?.title == "衣身宽松倍率")
        precondition(GarmentCodeChinese.parameter(["skirt", "flare"])?.unit == "cm")
        precondition(GarmentCodeChinese.parameter(["shirt", "flare"])?.unit == "倍")
        precondition(GarmentCodeChinese.parameter(["left", "sleeve", "length"])?.title.hasPrefix("左侧·") == true)
        var design = GarmentCodeDesignParameters(catalog: catalog)
        _ = design.setValue(.number(100), at: ["shirt", "width"])
        let errors = design.validationMessages { GarmentCodeChinese.parameter($0)!.title }
        precondition(errors.contains { $0.contains("衣身宽松倍率") })
        precondition(!errors.contains { $0.contains("shirt.width") })
        var panels: Set<String> = []
        func collect(_ object: Any) {
            if let dictionary = object as? [String: Any] {
                if let pattern = dictionary["pattern"] as? [String: Any], let p = pattern["panels"] as? [String: Any] {
                    panels.formUnion(p.keys)
                }
                dictionary.values.forEach(collect)
            } else if let array = object as? [Any] { array.forEach(collect) }
        }
        for url in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Fixtures"),
                                                               includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            collect(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
        }
        for name in panels {
            precondition(GarmentCodeChinese.panel(name) != name, "Missing Chinese panel: \(name)")
        }
        precondition(GarmentCodeChinese.panel("用户命名的裁片") == "用户命名的裁片")
        print("PASS: Chinese coverage for \(count) design parameters, \(catalog.body.count) body measurements, all string options and \(panels.count) official panel names; contextual units and validation labels")
    }
}
