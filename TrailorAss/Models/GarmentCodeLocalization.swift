import Foundation

/// Presentation-only terminology. Official keys, values, ranges and JSON stay intact.
enum GarmentCodeChinese {
    struct Field {
        let title: String
        let detail: String
        let unit: String
        init(_ title: String, _ detail: String, _ unit: String = "") {
            self.title = title; self.detail = detail; self.unit = unit
        }
    }

    static let bodyOrder = ["height", "head_l", "neck_w", "shoulder_w", "shoulder_incl",
        "bust", "underbust", "back_width", "bust_points", "bust_line", "vert_bust_line",
        "waist", "waist_back_width", "waist_line", "waist_over_bust_line", "hips",
        "hip_back_width", "hips_line", "hip_inclination", "bum_points", "crotch_hip_diff",
        "leg_circ", "arm_length", "armscye_depth", "wrist", "arm_pose_angle"]

    static let body: [String: Field] = [
        "height": .init("身高", "赤足站立时，从地面到头顶的垂直高度。", "cm"),
        "head_l": .init("头顶至颈根高度", "用于从身高换算颈根基准高度。", "cm"),
        "neck_w": .init("颈根宽", "颈根左右两侧之间的宽度，不是颈围。", "cm"),
        "shoulder_w": .init("肩宽", "左右肩端之间的宽度。", "cm"),
        "shoulder_incl": .init("肩斜角", "肩线相对水平线向下倾斜的角度。", "°"),
        "bust": .init("胸围", "经过胸部最丰满处，水平围量一周。", "cm"),
        "underbust": .init("下胸围", "沿胸部下缘水平围量一周。", "cm"),
        "back_width": .init("后胸围弧长", "胸围线处，从一侧腋下经后背量至另一侧腋下的弧长；不是肩宽。", "cm"),
        "bust_points": .init("胸点间距", "左右胸部最高点之间的距离，用于定位前省道。", "cm"),
        "bust_line": .init("贴体胸高", "颈根基准至胸点的贴体测量长度，与垂直胸高分别填写。", "cm"),
        "vert_bust_line": .init("垂直胸高", "颈根基准至胸点所在水平线的垂直距离。", "cm"),
        "waist": .init("腰围", "沿自然腰线水平围量一周。", "cm"),
        "waist_back_width": .init("后腰围弧长", "腰线处，从一侧经后腰量至另一侧的弧长。", "cm"),
        "waist_line": .init("颈根至腰线垂直高度", "颈根基准到自然腰线的垂直距离，不是腰线离地高度。", "cm"),
        "waist_over_bust_line": .init("经胸前腰节长", "从颈根基准经胸点贴体量至自然腰线。", "cm"),
        "hips": .init("臀围", "经过臀部最丰满处，水平围量一周。", "cm"),
        "hip_back_width": .init("后臀围弧长", "臀围线处，从一侧经臀部后侧量至另一侧的弧长。", "cm"),
        "hips_line": .init("腰线至臀线高度", "自然腰线到臀围线的垂直距离。", "cm"),
        "hip_inclination": .init("侧臀倾角", "控制腰部至臀部的侧面倾斜，制版时按公式换算。", "°"),
        "bum_points": .init("臀峰间距", "左右臀部最高点之间的距离，用于定位后省道。", "cm"),
        "crotch_hip_diff": .init("臀线至裆底高度", "臀围线与裆底之间的垂直距离，不是前后裆弧总长。", "cm"),
        "leg_circ": .init("大腿围", "大腿根部的围度，用于确定裤腿基础宽度。", "cm"),
        "arm_length": .init("臂长", "肩端至腕部的测量长度，作为袖长的计算基准。", "cm"),
        "armscye_depth": .init("袖窿深", "肩部基准至腋下水平线的垂直深度；制版时自动加入袖窿余量。", "cm"),
        "wrist": .init("腕围", "手腕处围量一周，用于约束最小袖口宽度。", "cm"),
        "arm_pose_angle": .init("手臂外展角", "人体参考姿态中的手臂外展角；当前二维流程不显示三维姿态。", "°")
    ]

    private static let fields: [String: Field] = [
        "meta.upper": .init("上衣款式", "选择上衣版型，或选择不添加上衣。"),
        "meta.wb": .init("腰头款式", "腰头是连接腰部的带状裁片，可与上衣、裙装或裤装组合。"),
        "meta.bottom": .init("下装款式", "选择裙装或裤装，也可只生成上衣或腰头。"),
        "waistband.waist": .init("腰头围度倍率", "放大腰头计算所用的腰围和臀围；1 为人体原始围度。", "倍"),
        "waistband.width": .init("腰头高度比例", "腰头的竖直高度相对于腰线至臀线高度的比例，不是厘米数。"),
        "shirt.strapless": .init("无肩带款式", "用于合体上衣，去除肩部结构；宽松上衣不使用此设置。"),
        "shirt.length": .init("衣长倍率", "用于宽松上衣：以颈根至腰线高度为基准，结合肩斜计算衣长；合体款按人体尺寸制版。", "倍"),
        "shirt.width": .init("衣身宽松倍率", "用于宽松上衣：以人体胸围增加衣身宽度；1 为基准。合体款不使用此项。", "倍"),
        "shirt.flare": .init("衣摆宽度倍率", "用于宽松上衣：大于 1 外扩，小于 1 收窄。合体款不使用此项。", "倍"),
        "collar.f_collar": .init("前领口形状", "选择前身裁片的领口轮廓。"),
        "collar.b_collar": .init("后领口形状", "选择后身裁片的领口轮廓；部分领部组件会自动调整它。"),
        "collar.width": .init("领口开宽调节", "0 对应颈根宽，正值向肩部加宽；负值使领口比颈根宽更窄。"),
        "collar.fc_depth": .init("前领深比例", "以胸高为基准计算前领口深度，并受肩线和衣身长度限制。"),
        "collar.bc_depth": .init("后领深比例", "以胸高为基准计算后领口深度，并受肩线和衣身长度限制。"),
        "collar.fc_angle": .init("前领口造型角", "用于梯形领的侧边角度或圆弧领的圆心角。", "°"),
        "collar.bc_angle": .init("后领口造型角", "用于梯形领的侧边角度或圆弧领的圆心角。", "°"),
        "collar.f_bezier_x": .init("前领曲线横向控制", "用于可调曲线领，控制点沿领口两端连线的位置比例。"),
        "collar.f_bezier_y": .init("前领曲线弯曲控制", "用于可调曲线领，控制点偏离领口两端连线的程度。"),
        "collar.b_bezier_x": .init("后领曲线横向控制", "用于可调曲线领，控制点沿领口两端连线的位置比例。"),
        "collar.b_bezier_y": .init("后领曲线弯曲控制", "用于可调曲线领，控制点偏离领口两端连线的程度。"),
        "collar.f_flip_curve": .init("反向弯曲前领线", "反转波形、圆弧或可调曲线前领口的弯曲方向。"),
        "collar.b_flip_curve": .init("反向弯曲后领线", "反转波形、圆弧或可调曲线后领口的弯曲方向。"),
        "collar.component.style": .init("领部组件", "选择额外的领片或帽片；不添加时仅生成衣身上的领口。"),
        "collar.component.depth": .init("领片高度／翻折宽度", "控制立领高度或翻领裁片的宽度；不用于帽领。", "cm"),
        "collar.component.lapel_standing": .init("翻领后片立起", "用于翻领：开启后采用立起的后领片结构。"),
        "collar.component.hood_depth": .init("帽深倍率", "以半领口宽为基准确定帽片前后方向的深度。", "倍"),
        "collar.component.hood_length": .init("帽高倍率", "以头顶至颈根高度为基准，另加入领口宽度补偿。", "倍"),
        "sleeve.sleeveless": .init("无袖", "开启后只生成袖窿，不生成袖片和袖口组件。"),
        "sleeve.armhole_shape": .init("袖窿形状", "方形和折角袖窿用于无袖款；带袖款采用弧形袖窿。"),
        "sleeve.length": .init("袖长比例", "以臂长扣除袖山展开长度后的余量为基准；添加袖口时还会扣除组件长度。"),
        "sleeve.connecting_width": .init("袖窿加深系数", "以人体袖窿深加制版余量为基准增加深度，并受衣身长度限制。"),
        "sleeve.end_width": .init("袖口宽度倍率", "以袖窿展开高度为基准计算袖口宽度，并受腕围的最小宽度约束。", "倍"),
        "sleeve.sleeve_angle": .init("袖片下倾角", "控制袖片倾斜；计算值不小于人体肩斜角。", "°"),
        "sleeve.opening_dir_mix": .init("袖窿下端切线调节", "调整袖窿下端的曲线方向，影响袖山展开形状，不是袖口方向。"),
        "sleeve.standing_shoulder": .init("立肩造型", "当袖片下倾角大于肩斜角并满足制版条件时，加入立肩结构。"),
        "sleeve.standing_shoulder_len": .init("立肩延伸长度", "仅在启用立肩造型时使用。", "cm"),
        "sleeve.connect_ruffle": .init("袖山抽褶倍率", "袖山与衣身连接处的抽褶量；1 表示不额外抽褶。", "倍"),
        "sleeve.smoothing_coeff": .init("袖窿曲线平顺系数", "调节弧形袖窿的控制点位置及转折平顺程度。"),
        "left.enable_asym": .init("启用左右不对称", "单独设置左侧衣身、领口和袖子；领深沿用主设置，独立领片和帽片自动取消。"),
        "skirt.length": .init("裙长调节比例", "按腿长比例计算裙长，腰位同时影响从腰口到下摆的总长度。"),
        "skirt.rise": .init("裙腰位置比例", "1 为自然腰线；数值减小，腰口向臀线下移。"),
        "skirt.ruffle": .init("腰口抽褶倍率", "裙片腰口长度相对于连接腰围的倍率；1 表示不抽褶。", "倍"),
        "skirt.bottom_cut": .init("侧缝开衩系数", "控制侧缝下端的切口大小，随裙长参数换算；0 表示不开衩。"),
        "skirt.flare": .init("单侧下摆扩展量", "每片裙片的两侧各增加此宽度；这是实际厘米数。", "cm"),
        "flare-skirt.length": .init("裙长调节比例", "按腿长比例计算，腰位同时影响裙片的径向长度。"),
        "flare-skirt.rise": .init("裙腰位置比例", "1 为自然腰线；数值减小，腰口向臀线下移。"),
        "flare-skirt.suns": .init("圆裙圆周倍数", "1 表示整圆裙（360°），0.5 表示半圆裙（180°）。", "倍"),
        "flare-skirt.skirt-many-panels.n_panels": .init("拼接裙片数", "将裙身分成此数量的拼接裁片。", "片"),
        "flare-skirt.skirt-many-panels.panel_curve": .init("裙片下摆弧线系数", "0 为直线下摆；正负值控制弯曲方向，绝对值控制弯曲程度。"),
        "flare-skirt.asymm.front_length": .init("前裙长比例", "用于不对称圆裙，控制前部相对于后部的长度。"),
        "flare-skirt.cut.add": .init("添加下摆开衩", "在圆裙下摆切出开衩轮廓。"),
        "flare-skirt.cut.depth": .init("开衩深度比例", "以裙长为基准确定开衩向上的深度。"),
        "flare-skirt.cut.width": .init("开衩宽度比例", "以裙长为基准，计算开衩在下摆处的宽度。"),
        "flare-skirt.cut.place": .init("开衩位置", "正值选前裙片，零及负值选后裙片；绝对值控制沿下摆的位置。"),
        "godet-skirt.base": .init("插片裙基础裙型", "选择插入三角形裙片的基础裙身。"),
        "godet-skirt.insert_w": .init("插片底边宽", "三角形插片在下摆处的宽度。", "cm"),
        "godet-skirt.insert_depth": .init("插片高度", "三角形插片从底边到顶点的高度。", "cm"),
        "godet-skirt.num_inserts": .init("三角插片总数", "插片分配到裙身前后片。", "片"),
        "godet-skirt.cuts_distance": .init("相邻插片间距", "沿基础裙片下摆预留的相邻切口间距，空间不足时自动调整。", "cm"),
        "pencil-skirt.length": .init("裙长调节比例", "按腿长比例计算，并结合腰线至臀线高度确定总裙长。"),
        "pencil-skirt.rise": .init("裙腰位置比例", "1 为自然腰线；数值减小，腰口向臀线下移。"),
        "pencil-skirt.flare": .init("下摆宽度倍率", "以臀围为基准调节下摆：1 为基准，大于 1 外扩，小于 1 收窄。", "倍"),
        "pencil-skirt.low_angle": .init("下摆倾斜角", "控制裙片下摆的倾斜方向与角度。", "°"),
        "pencil-skirt.front_slit": .init("前中开衩比例", "从前中下摆向上开衩；0 表示不开衩。"),
        "pencil-skirt.back_slit": .init("后中开衩比例", "从后中下摆向上开衩；0 表示不开衩。"),
        "pencil-skirt.left_slit": .init("左侧开衩比例", "从左侧下摆向上开衩；0 表示不开衩。"),
        "pencil-skirt.right_slit": .init("右侧开衩比例", "从右侧下摆向上开衩；0 表示不开衩。"),
        "pencil-skirt.style_side_cut": .init("侧缝装饰切口", "选择太阳形或标志形的装饰切口。"),
        "levels-skirt.base": .init("基裙款式", "选择最上方、连接腰部的基础裙型。"),
        "levels-skirt.level": .init("接层裙型", "选择接在基裙下方的裙层款式。"),
        "levels-skirt.num_levels": .init("追加裙层数", "接在基裙下方的层数，不包含基裙本身。", "层"),
        "levels-skirt.level_ruffle": .init("层间抽褶倍率", "新裙层上口相对于上一层下摆的长度倍率。", "倍"),
        "levels-skirt.length": .init("总裙长比例", "以腿长为基准设置基裙与接层的总长度。"),
        "levels-skirt.rise": .init("裙腰位置比例", "1 为自然腰线；数值减小，腰口向臀线下移。"),
        "levels-skirt.base_length_frac": .init("基裙长度占比", "基裙占可分配裙长的比例，其余长度由追加裙层均分。"),
        "pants.length": .init("裤长比例", "以人体派生腿长为基准；添加裤口组件时会扣除相应长度。"),
        "pants.width": .init("裤身宽松倍率", "以人体围度为基准增加裤身宽度。", "倍"),
        "pants.flare": .init("裤脚扩缩系数", "1 为基准裤脚宽度，小于 1 收窄，大于 1 外扩。"),
        "pants.rise": .init("裤腰位置比例", "1 为自然腰线；数值减小，裤腰向臀线下移。")
    ]

    static func parameter(_ path: [String]) -> Field? {
        var path = path
        let left = path.first == "left" && path.count > 1 && path[1] != "enable_asym"
        if left { path.removeFirst() }
        let field: Field?
        if path.count == 3, path[1] == "cuff", ["sleeve", "pants"].contains(path[0]) {
            let prefix = path[0] == "pants" ? "裤口" : "袖口"
            switch path[2] {
            case "type": field = .init(prefix + "组件", "选择直条、荷叶边或两者组合的口边裁片。")
            case "top_ruffle": field = .init(prefix + "连接抽褶倍率", "衣袖或裤脚与口边组件连接时的抽褶倍率；1 表示不抽褶。", "倍")
            case "cuff_len": field = .init(prefix + "长度比例", path[0] == "pants"
                ? "以派生腿长为基准计算裤口组件长度，并受裤长限制。"
                : "以臂长为基准计算袖口组件长度，最多占设定袖长的 70%。")
            case "skirt_fraction": field = .init(prefix + "荷叶边长度占比", "用于组合口边：荷叶边占口边组件总长度的比例。")
            case "skirt_flare": field = .init(prefix + "荷叶边展开倍率", "调节荷叶边下口相对于上口的宽度。", "倍")
            case "skirt_ruffle": field = .init(prefix + "荷叶边抽褶倍率", "调节荷叶边与直条口边连接处的抽褶量。", "倍")
            default: field = nil
            }
        } else { field = fields[path.joined(separator: ".")] }
        guard let field else { return nil }
        return left ? .init("左侧·" + field.title, field.detail, field.unit) : field
    }

    static let options = [
        "Shirt": "宽松上衣", "FittedShirt": "合体上衣", "StraightWB": "直条腰头", "FittedWB": "贴体弧形腰头",
        "SkirtCircle": "圆裙", "AsymmSkirtCircle": "不对称圆裙", "Skirt2": "双片裙", "SkirtManyPanels": "多片拼接裙",
        "PencilSkirt": "铅笔裙", "GodetSkirt": "三角插片裙", "SkirtLevels": "层叠裙", "Pants": "裤装",
        "CircleNeckHalf": "圆领", "CurvyNeckHalf": "波形曲线领", "VNeckHalf": "V 领", "SquareNeckHalf": "方领",
        "TrapezoidNeckHalf": "梯形领", "CircleArcNeckHalf": "可调圆弧领", "Bezier2NeckHalf": "可调曲线领",
        "Turtle": "立领", "SimpleLapel": "翻领", "Hood2Panels": "两片式帽领", "ArmholeSquare": "方形袖窿",
        "ArmholeAngle": "折角袖窿", "ArmholeCurve": "弧形袖窿", "CuffBand": "直条口边",
        "CuffSkirt": "荷叶边口边", "CuffBandSkirt": "直条与荷叶边组合", "Sun": "太阳形切口", "SIGGRAPH_logo": "SIGGRAPH 标志切口"
    ]

    static func option(_ value: JSONValue, path: [String]) -> String {
        switch value {
        case let .string(value): return options[value] ?? value
        case .null:
            return path.first == "meta" ? "不添加" : "无"
        case let .number(value):
            if path.last == "panel_curve", value == 0 { return "直线下摆" }
            return value.formatted(.number.precision(.fractionLength(0...3)))
        case let .bool(value): return value ? "是" : "否"
        default: return "—"
        }
    }

    static func panel(_ name: String) -> String {
        let direct = ["left_btorso": "左后身片", "left_ftorso": "左前身片", "right_btorso": "右后身片", "right_ftorso": "右前身片",
            "left_hood": "左帽片", "right_hood": "右帽片", "wb_front": "腰头前片", "wb_back": "腰头后片",
            "skirt_front": "裙前片", "skirt_back": "裙后片", "pant_b_l": "左裤后片", "pant_b_r": "右裤后片",
            "pant_f_l": "左裤前片", "pant_f_r": "右裤前片"]
        if let title = direct[name] { return title }
        for (prefix, title) in [("ins_skirt_back_", "裙后片三角插片"), ("ins_skirt_front_", "裙前片三角插片"),
            ("skirt_panel_", "拼接裙片"), ("skirt_front_", "接层裙前片"), ("skirt_back_", "接层裙后片")] {
            if name.hasPrefix(prefix), let n = Int(name.dropFirst(prefix.count)) { return "\(title) \(n + 1)" }
        }
        for (prefix, side) in [("left_", "左"), ("right_", "右")] where name.hasPrefix(prefix) {
            let rest = String(name.dropFirst(prefix.count))
            let labels = ["sleeve_f": "袖前片", "sleeve_b": "袖后片", "collar_front": "前领片", "collar_back": "后领片"]
            if let label = labels[rest] { return side + label }
        }
        for (prefix, title) in [("sl_left_cuff_", "左袖口"), ("sl_right_cuff_", "右袖口"),
                                ("pant_l_cuff_", "左裤口"), ("pant_r_cuff_", "右裤口")] where name.hasPrefix(prefix) {
            let rest = String(name.dropFirst(prefix.count))
            let labels = ["f": "前片", "b": "后片", "skirt_f": "荷叶边前片", "skirt_b": "荷叶边后片"]
            if let label = labels[rest] { return title + label }
        }
        return name // User-defined names in imported files remain identifiable.
    }
}
