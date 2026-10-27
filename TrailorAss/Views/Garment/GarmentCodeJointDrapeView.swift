import SwiftUI
import Combine

/// Experimental complete-source route. Only the full workflow validator can
/// supply this page's displayed/exported garment.
@MainActor struct GarmentCodeJointDrapeView:View {
    let document:GarmentCodePatternFile
    private let bodyResourceDirectory:URL?
    private let catalogURL:URL?
    private let configurationID:String
    private let signatureIssue:String?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model=GarmentCodeJointDrapeViewModel()
    @State private var camera=GarmentCodeDrapeFraming.Configuration()
    @State private var dragOrigin:(Double,Double)?
    @State private var zoomOrigin:Double?

    init(document:GarmentCodePatternFile,bodyResourceDirectory:URL?=nil,catalogURL:URL?=nil) {
        self.document=document;self.bodyResourceDirectory=bodyResourceDirectory;self.catalogURL=catalogURL
        do {
            configurationID=try GarmentCodeJointParameters.signature(document)+"|"+(bodyResourceDirectory?.absoluteString ?? "bundle")+"|"+(catalogURL?.absoluteString ?? "bundle")
            signatureIssue=nil
        } catch {
            configurationID="invalid-"+UUID().uuidString
            signatureIssue="纸样含有无法读取的来源数据，请重新生成纸样。"
        }
    }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    introduction
                    materialCard
                    bodyShapeCard
                    bodyPoseCard
                    if let shown=model.presented {
                        scene(shown)
                        metrics(shown.result)
                        exportCard
                    } else {generationCard}
                    if let issue=model.issue {notice(issue,systemImage:"exclamationmark.triangle")}
                    if let information=model.information {notice(information,systemImage:"info.circle")}
                }.padding()
            }
            .background(Color.appBackground)
            .navigationTitle("整衣 3D（实验）")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.appAccent)
            .toolbar {ToolbarItem(placement:.cancellationAction){Button("关闭"){model.close();dismiss()}}}
        }
        .task(id:configurationID) {model.configure(document:document,resourceDirectory:bodyResourceDirectory,catalogURL:catalogURL,signatureIssue:signatureIssue)}
        .onDisappear {model.close()}
    }
    private var introduction:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("从完整裁片生成整衣").font(.appTitle)
            Text("使用这份纸样的完整人体与设计参数计算缝合和重力下垂。部分款式仍在验证，可能无法完成；只有通过全部检查的结果才会显示并可导出。")
                .font(.appBody).foregroundStyle(.secondary)
            if model.sourceReady {
                Text("\(document.pattern.panels.count) 片原裁片 · \(document.pattern.stitches.count) 组配对接缝")
                    .font(.appCaption).foregroundStyle(.secondary)
            }
        }
    }
    private var materialCard:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("实验面料").font(.appHeadline)
            Picker("实验面料",selection:Binding(get:{model.material},set:{model.selectMaterial($0)})) {
                ForEach(GarmentCodeClothMaterial.Preset.allCases){item in Text(item.title).tag(item)}
            }.pickerStyle(.menu)
            Text("三档采用不同的单位面积质量、面内刚度与弯曲刚度，尚未用真实面料标定。切换后需重新计算。")
                .font(.appCaption).foregroundStyle(.secondary)
        }.cardStyle()
    }
    private var generationCard:some View {
        VStack(alignment:.leading,spacing:12) {
            if model.running {
                HStack {ProgressView();Text(model.phaseTitle).font(.appHeadline)}
                if let p=model.progress {
                    if p.phaseMaximumSteps>0 {
                        Text("本阶段已完成 \(p.phaseCompletedSteps) 步，最多 \(p.phaseMaximumSteps) 步")
                    }
                    if p.phase == .gravityRamp || p.phase == .settling || p.phase == .validating {
                        Text("连续稳定帧：\(p.consecutiveQuietSteps) / \(p.requiredQuietSteps)")
                    }
                }
                Text(model.cancelling ? "正在等待后台任务退出，结束后可重新计算。":"以上是实际完成的步骤计数；稳定时间取决于本次纸样。")
                    .font(.appCaption).foregroundStyle(.secondary)
                Button(model.cancelling ? "正在结束计算":"取消计算",role:.cancel){model.cancelGeneration()}
                    .buttonStyle(.bordered).disabled(model.cancelling)
            } else {
                Image(systemName:"tshirt").font(.system(size:36)).foregroundStyle(Color.appAccent)
                Text(model.sourceReady ? "准备好后开始计算" : (model.issue==nil ? "等待纸样参数":"无法读取原始参数")).font(.appHeadline)
                Text(!model.sourceReady && model.issue != nil ? "请返回纸样设计核对参数并重新生成，也可重新读取这份纸样的参数。":"后台计算可能需要等待。若未通过检查，会保留错误说明供重试。")
                    .font(.appBody).foregroundStyle(.secondary)
                Button(model.issue==nil ? "开始后台计算":"重新计算"){model.generate()}
                    .buttonStyle(.borderedProminent).disabled(!model.sourceReady)
                if !model.sourceReady {
                    Button("重新读取参数"){model.configure(document:document,resourceDirectory:bodyResourceDirectory,catalogURL:catalogURL,signatureIssue:signatureIssue)}
                }
            }
        }.font(.appBody).frame(maxWidth:.infinity,alignment:.leading).cardStyle()
    }
    private var bodyShapeCard:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("人台形状").font(.appHeadline)
            Picker("人台形状",selection:Binding(get:{model.bodyShapeSelection},set:{model.selectBodyShape($0)})) {
                Text("标准人台").tag(GarmentCodeCircleDrape.BodyShapeSelection.scaledTemplate)
                Text("按主要尺寸拟合（实验）").tag(GarmentCodeCircleDrape.BodyShapeSelection.surfaceMeasurements)
            }.pickerStyle(.menu)
            if model.bodyShapeSelection == .surfaceMeasurements {
                Text("按胸围、肩横宽、臂长和腕围四类参考尺寸调整人台，再按纸样参考角摆臂。其他尺寸仍采用模板比例，不是完整个人拟合。")
                    .font(.appCaption).foregroundStyle(.secondary)
                Text("拟合发生在参考姿势，摆臂后局部尺寸可能变化。此模式使用下面的纸样参考姿态。")
                    .font(.appCaption).foregroundStyle(.secondary)
            } else {
                Text("按身高、腰臀等比例缩放标准模板，肩宽、臂长等不会逐项拟合。切换人台形状后需重新计算。")
                    .font(.appCaption).foregroundStyle(.secondary)
            }
        }.cardStyle()
    }
    private var bodyPoseCard:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("人台姿态").font(.appHeadline)
            if model.bodyShapeSelection == .surfaceMeasurements {
                Text("按纸样参考角摆臂（此人台模式使用）").font(.appBody)
            } else {
                Picker("人台姿态",selection:Binding(get:{model.bodyPoseSelection},set:{model.selectBodyPose($0)})) {
                    Text("标准模板姿态").tag(GarmentCodeCircleDrape.BodyPoseSelection.legacyTemplate)
                    Text("按纸样参考角摆臂（实验）").tag(GarmentCodeCircleDrape.BodyPoseSelection.matchPatternReference)
                }.pickerStyle(.menu)
            }
            if model.bodyPoseSelection == .matchPatternReference {
                if let angle=model.referenceArmAngleDegrees {
                    Text("纸样参考角：\(angle,specifier:"%.2f")°，按水平向下计算。")
                        .font(.appCaption).foregroundStyle(.secondary)
                }
                Text("按纸样参考角调整手臂；不代表全部个人尺寸已拟合。")
                    .font(.appCaption).foregroundStyle(.secondary)
            } else {
                Text("沿用标准人台的原始姿态。切换姿态后需重新计算。")
                    .font(.appCaption).foregroundStyle(.secondary)
            }
        }.cardStyle()
    }
    private func scene(_ shown:GarmentCodeJointDrapeViewModel.Presented)->some View {
        let renderToken=model.sceneReloadID
        return VStack(alignment:.leading,spacing:12) {
            GarmentCodeGarmentScene(output:shown.result.validated.output,meshID:shown.id,configuration:camera,
                panelNames:shown.panelNames,seamGroupIDs:shown.result.validated.seamGroupIDs,renderIssue:Binding(get:{model.sceneIssue},set:{value in
                    guard model.presented?.id==shown.id,model.sceneReloadID==renderToken else{return}
                    model.sceneIssue=value
                }))
                .id(model.sceneReloadID)
                .frame(height:380).background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius:12))
                .simultaneousGesture(DragGesture().onChanged{value in
                    if dragOrigin==nil {dragOrigin=(camera.yaw,camera.pitch)}
                    if let start=dragOrigin {
                        camera.yaw=start.0+Double(value.translation.width)*0.009
                        camera.pitch=max(-1.3,min(1.3,start.1+Double(value.translation.height)*0.009))
                    }
                }.onEnded{_ in dragOrigin=nil})
                .simultaneousGesture(MagnifyGesture().onChanged{value in
                    if zoomOrigin==nil {zoomOrigin=camera.zoomScale}
                    camera.zoomScale=max(0.4,min(4,(zoomOrigin ?? 1)/Double(value.magnification)))
                }.onEnded{_ in zoomOrigin=nil})
                .accessibilityLabel("已验证整衣三维预览")
            Text("单指拖动旋转，双指缩放。").font(.appCaption).foregroundStyle(.secondary)
            HStack {
                Button{camera.zoomScale=max(0.4,camera.zoomScale/1.2)}label:{Label("放大",systemImage:"plus.magnifyingglass")}
                Button{camera.zoomScale=min(4,camera.zoomScale*1.2)}label:{Label("缩小",systemImage:"minus.magnifyingglass")}
                Spacer()
                Button("复位"){camera = .init();dragOrigin=nil;zoomOrigin=nil}
            }.buttonStyle(.bordered)
            Toggle("显示人台",isOn:$camera.showMannequin)
            Toggle("显示成对接缝",isOn:$camera.showSeams)
            if let issue=model.sceneIssue {
                Text("预览载入失败：\(issue)").foregroundStyle(.red)
                Button("重新载入预览"){model.sceneIssue=nil;model.sceneReloadID=UUID()}
            }
            Button("重新计算"){model.generate()}.buttonStyle(.bordered)
        }.font(.appBody).cardStyle()
    }
    private func metrics(_ result:GarmentCodeJointWorkflow.Result)->some View {
        let m=result.validated.metrics
        return VStack(alignment:.leading,spacing:8) {
            Text("本次结果").font(.appHeadline)
            Text("原裁片面积 \(m.sourceAreaSquareMeters,specifier:"%.4f") m² · 质量 \(m.totalFabricMassKg*1000,specifier:"%.1f") g")
            Text("\(m.panels.count) 片裁片 · \(m.vertices) 个顶点 · \(m.triangles) 个三角面")
            Text("\(m.sourceEdges) 条裁片网格边 · 最大原裁片边长变化 \(m.maximumSourceEdgeRelativeChange*100,specifier:"%.2f")%")
            Text("真实接缝最大间隙 \(m.maximumActualSeamGapMeters*1000,specifier:"%.3f") mm")
            Text("末态最大速度 \(m.maximumSpeedMetersPerSecond*1000,specifier:"%.2f") mm/s · 连续稳定 \(m.verifiedQuietFrames) 帧")
            Text("总用时 \(result.generationWallSeconds,specifier:"%.1f") 秒")
            Text("来源核对 \(result.sourceCaptureSeconds,specifier:"%.1f") 秒 · 准备 \(result.preparationSeconds,specifier:"%.1f") 秒 · 数值计算与验收 \(m.totalComputationSeconds,specifier:"%.1f") 秒")
                .font(.appCaption).foregroundStyle(.secondary)
            Text("本结果通过数值与几何检查，个人合体效果尚未验证。")
                .font(.appBody).foregroundStyle(.secondary)
        }.font(.appBody).cardStyle()
    }
    private var exportCard:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("导出三维模型").font(.appHeadline)
            Text("OBJ 包含完整裁片分组与人台，可供后续三维软件查看。")
                .font(.appCaption).foregroundStyle(.secondary)
            if model.exporting {
                HStack {ProgressView();Text("正在创建 OBJ 文件")}
                Button("取消导出",role:.cancel){model.cancelExport()}
            } else if let artifact=model.exportArtifact,artifact.resultID==model.presented?.id {
                ShareLink(item:artifact.url){Label("分享 OBJ 文件",systemImage:"square.and.arrow.up")}
                    .buttonStyle(.borderedProminent)
                Text("\(ByteCountFormatter.string(fromByteCount:Int64(artifact.byteCount),countStyle:.file))")
                    .font(.appCaption).foregroundStyle(.secondary)
                Button("重新导出"){model.export()}
            } else {
                Button(model.exportIssue==nil ? "创建 OBJ 文件":"重试导出"){model.export()}
                    .buttonStyle(.borderedProminent)
            }
            if let issue=model.exportIssue {Text(issue).foregroundStyle(.red)}
        }.font(.appBody).cardStyle()
    }
    private func notice(_ message:String,systemImage:String)->some View {
        Label(message,systemImage:systemImage).font(.appBody).foregroundStyle(.secondary).cardStyle()
    }
}

@MainActor private final class GarmentCodeJointDrapeViewModel:ObservableObject {
    typealias W=GarmentCodeJointWorkflow
    typealias E=GarmentCodeMeshExport
    struct Presented {let id:UUID,result:W.Result,panelNames:[String:String]}
    @Published private(set) var material=GarmentCodeClothMaterial.Preset.medium
    @Published private(set) var bodyShapeSelection=GarmentCodeCircleDrape.BodyShapeSelection.scaledTemplate
    @Published private(set) var bodyPoseSelection=GarmentCodeCircleDrape.BodyPoseSelection.legacyTemplate
    @Published private(set) var sourceReady=false
    @Published private(set) var running=false
    @Published private(set) var cancelling=false
    @Published private(set) var progress:W.Progress?
    @Published private(set) var presented:Presented?
    @Published private(set) var issue:String?
    @Published private(set) var information:String?
    @Published var sceneIssue:String?
    @Published var sceneReloadID=UUID()
    @Published private(set) var exporting=false
    @Published private(set) var exportArtifact:E.Artifact?
    @Published private(set) var exportIssue:String?
    private var ownedArtifact:E.Artifact?
    private var document:GarmentCodePatternFile?
    private var restored:GarmentCodeJointParameters.Restored?
    private var resourceDirectory:URL?
    private var runID=UUID(),exportRunID=UUID()
    private var generationTask:Task<Void,Never>?,exportTask:Task<Void,Never>?
    private var generationTaskID:UUID?
    private enum GenerationOutcome {case completed(W.Result),cancelled,failed(String)}
    deinit {
        generationTask?.cancel();exportTask?.cancel()
        if let artifact=ownedArtifact {Task.detached(priority:.utility){try? E.remove(artifact)}}
    }
    var phaseTitle:String {
        if cancelling {return "正在结束上一次计算"}
        switch progress?.phase {
        case .capturing:return "核对原始纸样"
        case .preparing:return "准备完整裁片与人体"
        case .assembling:return "缝合裁片"
        case .gravityRamp:return "逐步施加重力"
        case .settling:return "等待衣服稳定"
        case .validating:return "检查最终成衣"
        case .completed:return "检查完成"
        case nil:return "开始计算"
        }
    }
    func configure(document:GarmentCodePatternFile,resourceDirectory:URL?,catalogURL:URL?,signatureIssue:String?) {
        resetResult();self.document=document;self.resourceDirectory=resourceDirectory;restored=nil;sourceReady=false
        do {
            if let signatureIssue {issue=signatureIssue;return}
            let url=catalogURL ?? Bundle.main.url(forResource:"GarmentCodeParameterCatalog",withExtension:"json")
            guard let url else {issue="参数目录未找到，请重新构建 App 后重试。";return}
            restored=try GarmentCodeJointParameters.restore(document:document,catalog:GarmentCodeParameterCatalog.load(from:url))
            sourceReady=true
        } catch {issue=error.localizedDescription}
    }
    func materialChanged(){resetResult()}
    // Picker writes invalidate the old publication synchronously, before a
    // queued completion can publish a result for the previous configuration.
    func selectMaterial(_ selection:GarmentCodeClothMaterial.Preset){
        guard material != selection else{return}
        material=selection;materialChanged()
    }
    func selectBodyShape(_ selection:GarmentCodeCircleDrape.BodyShapeSelection){
        guard bodyShapeSelection != selection else{return}
        bodyShapeSelection=selection;bodyShapeChanged()
    }
    func selectBodyPose(_ selection:GarmentCodeCircleDrape.BodyPoseSelection){
        guard bodyShapeSelection != .surfaceMeasurements || selection == .matchPatternReference,
              bodyPoseSelection != selection else{return}
        bodyPoseSelection=selection;bodyPoseChanged()
    }
    func bodyShapeChanged(){
        if bodyShapeSelection == .surfaceMeasurements {bodyPoseSelection = .matchPatternReference}
        resetResult()
    }
    func bodyPoseChanged(){resetResult()}
    var referenceArmAngleDegrees:Double? {restored?.body["arm_pose_angle"]}
    func generate() {
        guard let document,let restored,sourceReady,!running,generationTask==nil else {return}
        resetResult()
        guard bodyShapeSelection != .surfaceMeasurements || bodyPoseSelection == .matchPatternReference else {
            issue="按主要尺寸拟合需要采用纸样参考角摆臂，请重新选择人台形状。"
            return
        }
        let id=UUID();runID=id;generationTaskID=id;running=true;cancelling=false
        let selected=material,shape=bodyShapeSelection,pose=bodyPoseSelection,directory=resourceDirectory
        generationTask=Task { @MainActor [weak self] in
            do {
                let result=try await W.generate(document:document,body:restored.body,design:restored.design,material:selected,bodyPoseSelection:pose,bodyShapeSelection:shape,bodyResourceDirectory:directory,progress:{[weak self] value in
                    guard let self,self.runID==id,self.generationTaskID==id,self.running,!self.cancelling else{return}
                    self.progress=value
                })
                try Task.checkCancellation()
                self?.finishGeneration(id:id,outcome:.completed(result),panelNames:restored.panelNames)
            } catch is CancellationError {
                self?.finishGeneration(id:id,outcome:.cancelled,panelNames:restored.panelNames)
            } catch {
                self?.finishGeneration(id:id,outcome:.failed(error.localizedDescription),panelNames:restored.panelNames)
            }
        }
    }
    /// Cancel requests invalidate publication immediately, but keep the task
    /// handle/owner until Workflow has awaited both numerical workers' exit.
    /// Configuration changes can restore new parameters meanwhile; they cannot
    /// start another solver or let this old owner clear a later task.
    func cancelGeneration() {
        runID=UUID();progress=nil
        guard let generationTask else {running=false;cancelling=false;return}
        cancelling=true;running=true;information=nil
        generationTask.cancel()
    }
    private func finishGeneration(id:UUID,outcome:GenerationOutcome,panelNames:[String:String]) {
        guard generationTaskID==id else{return}
        let publish=runID==id && !cancelling
        generationTask=nil;generationTaskID=nil;running=false;cancelling=false
        guard publish else {
            if sourceReady {information="上一次计算已结束，可以重新开始。"}
            return
        }
        switch outcome {
        case let .completed(result):presented = .init(id:id,result:result,panelNames:panelNames)
        case .cancelled:progress=nil;information="已取消，可重新开始。"
        case let .failed(message):progress=nil;issue=message
        }
    }
    func export() {
        guard let shown=presented,!exporting else{return}
        cancelExport()
        let token=UUID();exportRunID=token;exporting=true;exportIssue=nil
        exportTask=Task { @MainActor [weak self] in
            do {
                let artifact=try await E.export(output:shown.result.validated.output,resultID:shown.id)
                guard !Task.isCancelled,let self,self.exportRunID==token,self.presented?.id==shown.id else {
                    try? E.remove(artifact);return
                }
                self.ownedArtifact=artifact;self.exportArtifact=artifact;self.exporting=false;self.exportTask=nil
            } catch is CancellationError {
                guard let self,self.exportRunID==token else{return}
                self.exporting=false;self.exportTask=nil
            } catch {
                guard let self,self.exportRunID==token,self.presented?.id==shown.id else{return}
                self.exporting=false;self.exportTask=nil;self.exportIssue="OBJ 创建失败："+error.localizedDescription
            }
        }
    }
    func cancelExport() {
        exportRunID=UUID();exportTask?.cancel();exportTask=nil;exporting=false;exportIssue=nil
        if let artifact=ownedArtifact {
            ownedArtifact=nil;exportArtifact=nil
            Task.detached(priority:.utility){try? E.remove(artifact)}
        }
    }
    func close(){resetResult();restored=nil;sourceReady=false;document=nil}
    private func resetResult() {
        cancelGeneration();cancelExport();presented=nil;issue=nil;information=nil;sceneIssue=nil;sceneReloadID=UUID()
    }
}

private extension View {
    func cardStyle()->some View {
        padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.appCard,in:RoundedRectangle(cornerRadius:16))
    }
}
