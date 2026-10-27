import Foundation

/// Source-faithful native construction input for future cloth solvers. Each
/// original panel receives only its upstream rigid transform. This does not
/// certify collision freedom, sewing convergence, support or garment fit.
@MainActor
enum GarmentCodeNativeAssembly {
    typealias K=GarmentCodeCircleDrape
    typealias V=K.Vector3
    typealias S=GarmentCodeSewing
    typealias Builder=GarmentCodeAssemblyBuilder
    typealias Composition=GarmentCodeCompositionPlacement
    typealias Transform=GarmentCodePanelPlacement.Transform
    nonisolated struct Limits:Sendable {
        var maximumPanels=128
        var maximumVertices=20_000
        var maximumTriangles=40_000
        var maximumPanelVertices=6000
        var maximumPanelTriangles=16_000
        var maximumRefinementAttempts=5
    }
    nonisolated enum AssemblyError:LocalizedError,Sendable {
        case invalid(String),budget(String)
        var errorDescription:String?{switch self{case let .invalid(s):return "原生裁片装配无效："+s;case let .budget(s):return "原生裁片装配超过预算："+s}}
    }
    nonisolated enum Initialization:String,Codable,Sendable {
        /// Exact upstream construction, including any initial body crossings.
        case nativeConstruction
        /// Explicit conservative body-only clearance by rigid panel shifts.
        /// Mutual cloth clearance still needs independent inspection.
        case rigidBodyClearance
        /// Additional bounded rigid source-panel separation. Only actual
        /// proper/coplanar crossings are certified absent, not near contacts.
        case rigidBodyAndClothClearance
        /// Additional explicit positive sampled gap for self-barrier bootstrap.
        /// Keeps independent source IDs, including intended sewing interfaces.
        case rigidBodyAndClothPositiveClearance
    }
    nonisolated struct Preparation:Sendable {
        let preparedInput:GarmentCodeSewnDrape.PreparedInput
        let initialization:Initialization
        let bodyClearanceProof:GarmentCodeRigidBodyClearance.Proof?
        let clothClearanceProof:GarmentCodeRigidClothClearance.Proof?
    }
    /// Native authorization is captured once on MainActor. The private
    /// construction retains complete source bytes/geometry/stitches together
    /// with exact placement, intent, settings and the fitted body snapshot.
    nonisolated struct Recipe:Sendable {
        let source:GarmentCodeSewnDrape.SourceReceipt
        let hints:[S.StitchHint]
        let transforms:[String:Transform]
        let settings:K.Settings
        let limits:Limits
        let initialization:Initialization
        let body:Builder.BodyReceipt
        let garmentStyle:String
        fileprivate init(source:GarmentCodeSewnDrape.SourceReceipt,hints:[S.StitchHint],
            transforms:[String:Transform],settings:K.Settings,limits:Limits,
            initialization:Initialization,body:Builder.BodyReceipt,garmentStyle:String){
            self.source=source;self.hints=hints;self.transforms=transforms;self.settings=settings
            self.limits=limits;self.initialization=initialization;self.body=body;self.garmentStyle=garmentStyle
        }
    }
    static func prepare(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,settings:K.Settings,limits:Limits = .init(),
        initialization:Initialization = .nativeConstruction,
        isCancelled:@escaping @Sendable()->Bool={false})throws->GarmentCodeSewnDrape.PreparedInput {
        try prepareWithReport(document:document,body:body,design:design,settings:settings,limits:limits,
            initialization:initialization,isCancelled:isCancelled).preparedInput
    }
    static func prepareWithReport(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,settings:K.Settings,limits:Limits = .init(),
        initialization:Initialization = .nativeConstruction,
        isCancelled:@escaping @Sendable()->Bool={false})throws->Preparation {
        let recipe=try capture(document:document,body:body,design:design,settings:settings,
            limits:limits,initialization:initialization,isCancelled:isCancelled)
        return try build(recipe:recipe,isCancelled:isCancelled)
    }

    /// Actor-owned native regeneration, parameters, constructor transforms and
    /// resource loading only. No meshing or complete-source mesh validation.
    static func capture(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,settings:K.Settings,limits:Limits = .init(),
        initialization:Initialization = .nativeConstruction,
        isCancelled:@escaping @Sendable()->Bool={false})throws->Recipe {
        if isCancelled(){throw CancellationError()}
        guard (1...128).contains(limits.maximumPanels),(3...20_000).contains(limits.maximumVertices),
              (1...40_000).contains(limits.maximumTriangles),(3...6000).contains(limits.maximumPanelVertices),
              (1...16_000).contains(limits.maximumPanelTriangles),(1...8).contains(limits.maximumRefinementAttempts),
              settings.targetEdgeMeters.isFinite,(0.005...0.10).contains(settings.targetEdgeMeters),
              settings.bodyMode == .standardMannequin,settings.useSurfaceCollision,settings.useBodySurfaceCollision,settings.material != nil else {
            throw AssemblyError.invalid("需要有界源网格、标准人体、实验面料及两类接触配置。")
        }
        let source=try GarmentCodeSewnDrape.captureSource(document:document)
        let hash=source.sourceSHA256
        let regenerated=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        guard document.parameters?["design"]==design.jsonValue,
              document.parameters?["body"] == .object(body.values.mapValues(JSONValue.number)),
              try GarmentCodeSewnDrape.canonicalSourceSHA256(document:regenerated)==hash else {
            throw AssemblyError.invalid("完整原生参数重生成与源 SHA-256 不符；未知导入不能按边长猜缝合意图。")
        }
        let geometry=source.geometry
        guard geometry.count<=limits.maximumPanels else {throw AssemblyError.budget("完整裁片数超限，不能省略组件。")}
        let placement=try construction(document:document,body:body,design:design,isCancelled:isCancelled)
        guard placement.sourceSHA256==hash,Set(placement.transforms.keys)==Set(geometry.keys) else {throw AssemblyError.invalid("完整源裁片或构造矩阵缺失。")}
        let hints=try stitchHints(document:document,geometry:geometry,design:design)
        let bodyReceipt=try Builder.captureBody(body:body,settings:settings)
        if isCancelled(){throw CancellationError()}
        return .init(source:source,hints:hints,transforms:placement.transforms,settings:settings,
            limits:limits,initialization:initialization,body:bodyReceipt,
            garmentStyle:[option(design,"upper"),option(design,"wb"),option(design,"bottom")].compactMap{$0}.joined(separator:"+"))
    }

    /// Request-local meshing/refinement, rigid clearance, sewing, mass/contact
    /// assembly and independent full source validation. Safe for concurrent
    /// workers using the same immutable recipe; no global mutable cache.
    nonisolated static func build(recipe:Recipe,
        isCancelled:@escaping @Sendable()->Bool={false})throws->Preparation {
        if isCancelled(){throw CancellationError()}
        _ = try recipe.source.verifiedSHA256()
        let geometry=recipe.source.geometry,hints=recipe.hints,settings=recipe.settings
        let limits=recipe.limits,initialization=recipe.initialization
        let resolvedBody=try Builder.prepareBody(recipe.body,isCancelled:isCancelled)
        let clearanceBody=initialization != .nativeConstruction ? resolvedBody:nil
        var spacing:[String:[Int:Double]]=[:],meshes:[String:GarmentCodePanelMesher.Mesh]=[:]
        for attempt in 0..<limits.maximumRefinementAttempts {
            if isCancelled(){throw CancellationError()}
            var panels:[Builder.Panel]=[],clearancePanels:[GarmentCodeRigidBodyClearance.Panel]=[],vertices=0,triangles=0
            for id in geometry.keys.sorted(){
                if isCancelled(){throw CancellationError()}
                let mesh:GarmentCodePanelMesher.Mesh
                if let cached=meshes[id]{mesh=cached}
                else{
                    do{
                        mesh=try GarmentCodePanelMesher.prepare(panel:geometry[id]!,targetEdgeMeters:settings.targetEdgeMeters,
                            maximumVertices:limits.maximumPanelVertices,maximumTriangles:limits.maximumPanelTriangles,
                            maximumBoundarySpacingMeters:spacing[id] ?? [:],isCancelled:isCancelled)
                    }catch is CancellationError{throw CancellationError()}
                    catch{throw AssemblyError.invalid("完整源裁片 \(id) 无法建立真实网格：\(error)")}
                    meshes[id]=mesh
                }
                vertices += mesh.flatPositions.count;triangles += mesh.triangleIndices.count/3
                guard vertices<=limits.maximumVertices,triangles<=limits.maximumTriangles else {throw AssemblyError.budget("完整原始网格超限，不能丢片、焊点或缩短源边。")}
                let transform=recipe.transforms[id]!
                let positions=try mesh.flatPositions.map{try transform.point($0)}
                // No skin projection, torso wrap, cone shaping, seam averaging
                // or artificial supports: all source degrees of freedom stay.
                panels.append(.init(mesh:mesh,positions:positions))
                if initialization != .nativeConstruction {
                    clearancePanels.append(.init(panelID:id,positions:positions,
                        u:try transform.direction(.init(x:1,y:0,z:0)),v:try transform.direction(.init(x:0,y:1,z:0)),
                        normal:try transform.direction(.init(x:0,y:0,z:1)),maximumBoundaryDeviationMeters:mesh.maximumBoundaryDeviationMeters))
                }
            }
            var clearanceProof:GarmentCodeRigidBodyClearance.Proof?
            var clothClearanceProof:GarmentCodeRigidClothClearance.Proof?
            if let clearanceBody {
                let cleared=try GarmentCodeRigidBodyClearance.prepare(panels:clearancePanels,bodyPositions:clearanceBody.positions,
                    bodyTriangleIndices:clearanceBody.triangleIndices,shellMeters:0.0025,isCancelled:isCancelled)
                let clothCleared=try initialization == .rigidBodyAndClothClearance || initialization == .rigidBodyAndClothPositiveClearance
                    ? GarmentCodeRigidClothClearance.prepare(bodyCleared:cleared,
                        trianglesByPanel:Dictionary(uniqueKeysWithValues:panels.map{($0.mesh.panelID,$0.mesh.triangleIndices)}),
                        policy:initialization == .rigidBodyAndClothPositiveClearance ? .positiveGap:.crossingOnly,
                        isCancelled:isCancelled):nil
                panels=try panels.map { panel in
                    guard let positions=(clothCleared?.positionsByPanel ?? cleared.positionsByPanel)[panel.mesh.panelID] else {throw AssemblyError.invalid("刚体间隙初始化遗漏源裁片。")}
                    return .init(mesh:panel.mesh,positions:positions,fixedVertexIDs:panel.fixedVertexIDs)
                }
                clearanceProof=cleared.proof
                clothClearanceProof=clothCleared?.proof
            }
            var metrics=Builder.Metrics(garmentStyle:recipe.garmentStyle,
                lengthLabel:"原生独立裁片构造",sourceWaistMeters:0,sourceHemMeters:0,sourceLengthMeters:0)
            metrics.warnings=["采用固定上游原生刚体构造矩阵，所有源裁片和原长独立保留；默认不设置人工固定点。",
                "这是未来 CCD／布料求解的准备输入，尚未证明无穿插、缝合收敛、成衣合体或实机性能。",
                "已知原生接口的不等长保留为明确吃势或参数抽褶；普通与吃势接缝覆盖完整源边界，参数抽褶保留未附着节点，不缩短源边或猜测未知导入的意图。"]
            if resolvedBody.fitted != nil {
                metrics.warnings.append("人体已按项目定义的胸围、肩横宽、双臂长和腕围拟合，并匹配当前纸样的摆臂角；尚未独立拟合全部人体尺寸，不能代替个体试样。")
            }
            if let clearanceProof {
                metrics.warnings[0]="采用固定上游原生构造矩阵后，显式沿各片平面法向作同幅刚体平移 \(clearanceProof.commonTranslationMagnitudeMeters)m；保留全部源原长、质量与独立自由度，零人工固定点。"
                metrics.warnings.append("刚体支撑平面仅证明距同源可见人体至少 2.5 mm；尚未证明布片互不穿插、可缝合或成为成衣。完整偏移与人体 SHA-256 另有初始化 proof。")
            }
            if let clothClearanceProof {
                if let target=clothClearanceProof.positiveGapTargetMeters {
                    metrics.warnings.append("显式逐片全支持刚体展开共移动 \(clothClearanceProof.steps.count) 片，额外法向位移累计 \(clothClearanceProof.totalExtraTranslationMeters)m；独立裁片采样三角面保留至少 \(target)m 初始间隙，仅用于接触势初始化，尚未缝合或形成成衣。")
                } else {
                    metrics.warnings.append("显式逐片全支持刚体展开共移动 \(clothClearanceProof.steps.count) 片，额外法向位移累计 \(clothClearanceProof.totalExtraTranslationMeters)m；仅证明采样三角面没有 proper／正面积共面交叉，仍可能存在近接触，尚未缝合或形成成衣。")
                }
            }
            for hint in hints{
                let a=geometry[hint.a.panelID]!.edges[hint.a.edgeIndex].length(tolerance:1e-9)/100
                let b=geometry[hint.b.panelID]!.edges[hint.b.edgeIndex].length(tolerance:1e-9)/100
                if abs(a-b)>1e-10{
                    let label:String
                    switch hint.intent{case .ordinary:label="普通接口源误差（仅源长比较容差 0.5 mm，不是最终接缝间距）";case .eased:label="已知原生接口吃势／拟合残差，非参数抽褶";case .gathered:label="原生 constructor 明确 ruffle 参数接口"}
                    metrics.warnings.append("源接缝 \(hint.stitchIndex) \(hint.a.panelID):\(hint.a.edgeIndex) \(a)m ↔ \(hint.b.panelID):\(hint.b.edgeIndex) \(b)m：\(label)；完整原长与独立自由度保留。")
                }
            }
            guard metrics.warnings.count<=128 else {throw AssemblyError.budget("逐条原生接缝来源警告超过验证预算，未丢弃记录。")}
            do{
                let input=try Builder.prepare(source:recipe.source,body:resolvedBody,settings:settings,panels:panels,hints:hints,metrics:metrics,isCancelled:isCancelled)
                if let clearanceProof {
                    guard GarmentCodeRigidBodyClearance.geometrySHA256(positions:input.cloth.mannequinPositions,indices:input.cloth.mannequinTriangleIndices)==clearanceProof.bodyGeometrySHA256 else {
                        throw AssemblyError.invalid("刚体间隙证明与最终完整装配未使用同一可见人体。")
                    }
                }
                // Builder receives these FINAL positions, so all actual
                // attachment initialGap/ramp targets and directions are newly
                // assembled, never copied from the preceding body-only plan.
                return .init(preparedInput:input,initialization:initialization,bodyClearanceProof:clearanceProof,clothClearanceProof:clothClearanceProof)
            }
            catch S.SewingError.refinementNeeded(let requests){
                guard attempt+1<limits.maximumRefinementAttempts,!requests.isEmpty else {throw S.SewingError.refinementNeeded(requests)}
                for request in requests{
                    let value=request.requiredMaximumBoundarySpacingMeters
                    guard value.isFinite,value>=0.0005 else {throw S.SewingError.refinementNeeded(requests)}
                    let previous=spacing[request.edge.panelID]?[request.edge.edgeIndex] ?? .infinity
                    spacing[request.edge.panelID,default:[:]][request.edge.edgeIndex]=min(previous,value)
                    meshes.removeValue(forKey:request.edge.panelID)
                }
            }
        }
        throw AssemblyError.invalid("真实接缝细分未完成。")
    }
    private static func option(_ d:GarmentCodeDesignParameters,_ key:String)->String?{
        if case let .string(s)?=d.value(at:["meta",key]),!s.isEmpty{return s};return nil
    }
    private static func lowerSection(_ lower:String?,_ d:GarmentCodeDesignParameters)->String{
        switch lower{case "Pants":return "pants";case "PencilSkirt":return "pencil-skirt";case "Skirt2":return "skirt";case "SkirtLevels":return "levels-skirt"
        case "GodetSkirt":return d.value(at:["godet-skirt","base"]) == .string("PencilSkirt") ? "pencil-skirt":"skirt"
        default:return "flare-skirt"}
    }
    private static func construction(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
        design:GarmentCodeDesignParameters,isCancelled:@escaping @Sendable()->Bool)throws->Composition.Placement{
        var components:[Composition.Component]=[]
        let upper=option(design,"upper"),lower=option(design,"bottom"),band=option(design,"wb"),fitted=upper=="FittedShirt"
        if upper != nil{
            var d=design;_=d.setValue(.null,at:["meta","wb"]);_=d.setValue(.null,at:["meta","bottom"])
            let file=try GarmentCodeNativeGenerator.generate(body:body,design:d)
            let map=try GarmentCodeUpperPlacement.sourceMap(document:file,body:body,design:d,isCancelled:isCancelled)
            components.append(.init(kind:.upper,transforms:map.panels.mapValues(\.transform)))
        }
        var lowerMap:GarmentCodeLowerPlacement.ComponentMap?
        let section=lowerSection(lower,design)
        if lower != nil{
            var d=design;_=d.setValue(.null,at:["meta","upper"]);_=d.setValue(.null,at:["meta","wb"])
            if fitted,lower != "SkirtLevels"{_=d.setValue(.number(1),at:[section,"rise"])}
            lowerMap=try GarmentCodeLowerPlacement.componentMap(body:body,design:d,requestedRise:fitted && lower=="SkirtLevels" ? 1:nil,isCancelled:isCancelled)
        }
        if let band{
            let rise=lower==nil ? 1:(fitted ? 1:design.value(at:[section,"rise"])?.numberValue)
            let source=try GarmentCodePrograms.waistband(body:body,design:design,rise:rise)
            components.append(.init(kind:.waistband,transforms:try bandTransforms(source:source,style:band,body:body)))
        }
        if let lowerMap{components.append(.init(kind:.lower,transforms:lowerMap.transforms))}
        return try Composition.prepare(document:document,body:body,design:design,components:components,isCancelled:isCancelled)
    }
    /// Same native band construction as LowerPlacement's established recipe;
    /// component source is unsplit, before complete interfaces are subdivided.
    private static func bandTransforms(source:GarmentCodePatternFile,style:String,body:GarmentCodeBodyParameters)throws->[String:Transform]{
        guard ["StraightWB","FittedWB"].contains(style),let natural=body["_waist_level"],natural.isFinite else {throw AssemblyError.invalid("原生腰头或腰位不受支持。")}
        var result:[String:Transform]=[:]
        for(id,g) in try source.geometryPanels(){
            let front=id=="wb_front",anchor:V
            if style=="FittedWB"{
                let e=front ? g.edges.last!:g.edges.first!
                guard e.curvature?.type=="circle" else {throw AssemblyError.invalid("贴体腰头真实上口弧缺失。")}
                anchor = .init(x:-abs(e.end.x-e.start.x)/2,y:natural,z:front ? 20:-15)
            }else{
                let xs=g.edges.map{$0.start.x},ys=g.edges.map{$0.start.y}
                anchor = .init(x:-(xs.max()!-xs.min()!)/2,y:natural-Double(Int(ys.max()!-ys.min()!)),z:front ? 20:-15)
            }
            result[id]=try Transform(rotationDegrees:[0,0,0],translation:[anchor.x,anchor.y,anchor.z],unitsInMeter:100,waistLevelCentimeters:natural)
        }
        return result
    }
    private static func stitchHints(document:GarmentCodePatternFile,geometry:[String:GarmentCodePanelGeometry],design:GarmentCodeDesignParameters)throws->[S.StitchHint]{
        try document.pattern.stitches.enumerated().map{i,stitch in
            guard stitch.sides.count==2 else {throw AssemblyError.invalid("源接缝必须完整引用两侧。")}
            let a=stitch.sides[0],b=stitch.sides[1]
            guard let pa=geometry[a.panel],let pb=geometry[b.panel],pa.edges.indices.contains(a.edge),pb.edges.indices.contains(b.edge) else {throw AssemblyError.invalid("源接缝边不存在。")}
            let la=pa.edges[a.edge].length(tolerance:1e-9)/100,lb=pb.edges[b.edge].length(tolerance:1e-9)/100
            let intent:S.Intent
            if abs(la-lb)<=0.0005{intent = .ordinary}
            else{
                let longer:S.Side=la>=lb ? .a:.b,ratio=max(la,lb)/min(la,lb)
                guard ratio<=10 else {throw AssemblyError.invalid("已知原生接口倍率超出明确吃势／抽褶范围。")}
                // Native identity was verified for the entire source before
                // this recipe. Length chooses the declared longer side only;
                // it cannot grant an imported file native sewing semantics.
                if gatheredInterface(a.panel,b.panel,design:design){intent = .gathered(longerSide:longer,maximumLengthRatio:ratio+1e-8)}
                else{intent = .eased(longerSide:longer,maximumLengthRatio:ratio+1e-8)}
            }
            return .init(stitchIndex:i,seamID:"native-\(i)",a:.init(panelID:a.panel,edgeIndex:a.edge),b:.init(panelID:b.panel,edgeIndex:b.edge),
                aDirection:stitch.rightWrong ? .forward:.reverse,bDirection:.forward,rightWrong:stitch.rightWrong,intent:intent,
                maximumTackSpacingMeters:0.06,minimumFreeBoundaryNodes:1,ordinaryLengthToleranceMeters:0.0005)
        }
    }
    /// Explicit constructor parameter families, never a ratio-derived ruffle.
    /// Non-ruffled native fitted interfaces remain ease, not gathered fabric.
    private static func gatheredInterface(_ a:String,_ b:String,design d:GarmentCodeDesignParameters)->Bool{
        func number(_ path:[String],left:Bool=false)->Double{
            let asymmetric=d.value(at:["left","enable_asym"]) == .bool(true)
            return d.value(at:(left && asymmetric ? ["left"]:[])+path)?.numberValue ?? 1
        }
        let left=a.contains("left") || b.contains("left"),sleeveA=a.contains("_sleeve_"),sleeveB=b.contains("_sleeve_")
        if (sleeveA && b.hasSuffix("torso")) || (sleeveB && a.hasSuffix("torso")){return abs(number(["sleeve","connect_ruffle"],left:left)-1)>1e-9}
        let cuffA=a.contains("_cuff"),cuffB=b.contains("_cuff")
        if cuffA != cuffB{
            let section=(a.hasPrefix("pant_") || b.hasPrefix("pant_")) ? "pants":"sleeve"
            let cuffType=d.value(at:(section=="sleeve" && left && d.value(at:["left","enable_asym"]) == .bool(true) ? ["left"]:[])+[section,"cuff","type"])
            return abs(number([section,"cuff","top_ruffle"],left:section=="sleeve" && left)-1)>1e-9 ||
                (cuffType == .string("CuffSkirt") && abs(number([section,"cuff","skirt_ruffle"],left:section=="sleeve" && left)-1)>1e-9)
        }
        if cuffA && cuffB && a.contains("cuff_skirt") != b.contains("cuff_skirt"){
            let section=a.hasPrefix("sl_") || b.hasPrefix("sl_") ? "sleeve":"pants"
            return abs(number([section,"cuff","skirt_ruffle"],left:section=="sleeve" && left)-1)>1e-9
        }
        if option(d,"bottom")=="SkirtLevels",a.hasPrefix("skirt_"),b.hasPrefix("skirt_"),
           a.split(separator:"_").last != b.split(separator:"_").last{return abs(number(["levels-skirt","level_ruffle"])-1)>1e-9}
        let bottom=option(d,"bottom")
        let hasTwoPanelRoot=bottom=="Skirt2" || (bottom=="GodetSkirt" && d.value(at:["godet-skirt","base"]) == .string("Skirt2")) || (bottom=="SkirtLevels" && d.value(at:["levels-skirt","base"]) == .string("Skirt2"))
        if hasTwoPanelRoot,(a.hasPrefix("skirt_") && !b.hasPrefix("skirt_")) || (b.hasPrefix("skirt_") && !a.hasPrefix("skirt_")){
            return abs(number(["skirt","ruffle"])-1)>1e-9
        }
        return false
    }
}
