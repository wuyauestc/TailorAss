import Foundation

/// The original27 source-mesh case definitions, shared verbatim by its flat
/// meshing check and the complete-paper input exporter. No pattern geometry.
@MainActor enum SourceMeshCaseDefinitions {
    struct Case {
        let id: String
        let upper: String?
        let waistband: String?
        let bottom: String?
        var changes: [([String],JSONValue)] = []
    }
    static func cases()->[Case] {
        var specs:[Case]=[]
        for upper in ["Shirt","FittedShirt"] {specs.append(.init(id:upper,upper:upper,waistband:nil,bottom:nil))}
        for band in ["StraightWB","FittedWB"] {specs.append(.init(id:band,upper:nil,waistband:band,bottom:nil))}
        for bottom in ["SkirtCircle","AsymmSkirtCircle","GodetSkirt","Pants","Skirt2","SkirtManyPanels","PencilSkirt","SkirtLevels"] {
            specs.append(.init(id:bottom,upper:nil,waistband:nil,bottom:bottom))
        }
        for collar in ["Turtle","SimpleLapel","Hood2Panels"] {
            specs.append(.init(id:"Shirt-"+collar,upper:"Shirt",waistband:nil,bottom:nil,
                changes:[(["collar","component","style"],.string(collar))]))
        }
        for armhole in ["ArmholeSquare","ArmholeAngle","ArmholeCurve"] {
            specs.append(.init(id:"Shirt-sleeve-"+armhole,upper:"Shirt",waistband:nil,bottom:nil,
                changes:[(["sleeve","sleeveless"],.bool(false)),(["sleeve","armhole_shape"],.string(armhole))]))
        }
        for cuff in ["CuffBand","CuffSkirt","CuffBandSkirt"] {
            specs.append(.init(id:"Shirt-"+cuff,upper:"Shirt",waistband:nil,bottom:nil,
                changes:[(["sleeve","sleeveless"],.bool(false)),(["sleeve","cuff","type"],.string(cuff))]))
            specs.append(.init(id:"Pants-"+cuff,upper:nil,waistband:nil,bottom:"Pants",
                changes:[(["pants","cuff","type"],.string(cuff))]))
        }
        specs.append(.init(id:"Circle-suns-1.95",upper:nil,waistband:nil,bottom:"SkirtCircle",
            changes:[(["flare-skirt","suns"],.number(1.95))]))
        specs.append(.init(id:"Shirt-StraightWB-Pants",upper:"Shirt",waistband:"StraightWB",bottom:"Pants"))
        specs.append(.init(id:"FittedShirt-FittedWB-SkirtLevels",upper:"FittedShirt",waistband:"FittedWB",bottom:"SkirtLevels"))
        return specs
    }
}
