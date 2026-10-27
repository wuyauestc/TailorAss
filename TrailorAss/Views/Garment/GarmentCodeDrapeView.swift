import SwiftUI
import RealityKit
import UIKit
import simd

/// A bounded, pattern-driven draping experiment. The 2D document is immutable.
struct GarmentCodeDrapeView: View {
    let document: GarmentCodePatternFile
    @Environment(\.dismiss) private var dismiss
    @State private var input: GarmentCodeCircleDrape.Input?
    @State private var sewnInput: GarmentCodeSewnDrape.PreparedInput?
    @State private var output: GarmentCodeCircleDrape.Output?
    @State private var issue: String?
    @State private var sceneIssue: String?
    @State private var progress = 0.0
    @State private var running = false
    @State private var runID = UUID()
    @State private var worker: Task<GarmentCodeCircleDrape.Output, Error>?
    @State private var observer: Task<Void, Never>?
    @State private var exportURL: URL?
    @State private var yaw: Float = 0.35
    @State private var pitch: Float = -0.08
    @State private var cameraDistance: Float = 2.1
    @State private var showMannequin = true
    @State private var showSeams = true
    @State private var bodyMode: GarmentCodeCircleDrape.Settings.BodyMode = .standardMannequin
    @State private var material: GarmentCodeClothMaterial.Preset = .medium
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    private var isStandaloneWaistband:Bool {
        Set(document.pattern.panels.keys)==Set(["wb_front","wb_back"])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("离线 3D 垂坠试验")
                        .font(.headline)
                    Text(isStandaloneWaistband
                        ? "使用当前直条腰头或贴体弧形腰头的真实裁片与侧缝，独立查看腰头曲面。顶口使用数值支撑；尚未与裙身或裤身缝合。"
                        : "支持无腰头、无切口的圆裙和双片裙。标准人体使用自然腰位；双片裙的腰部抽褶采用实验性辅助支撑。计算使用当前真实裁片和接缝。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("人台", selection: $bodyMode) {
                            ForEach(isStandaloneWaistband ? [.standardMannequin] : GarmentCodeCircleDrape.Settings.BodyMode.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        Picker("面料实验预设", selection: $material) {
                            ForEach(GarmentCodeClothMaterial.Preset.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        Text("\(material.parameters.gramsPerSquareMeter, specifier: "%.0f") g/m² · 三档为数值预设，尚未用实物样布标定。更改后需重新计算。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(running)
                    if let output {
                        GarmentCodeDrapeScene(
                            output: output, meshID: runID, renderIssue: $sceneIssue,
                            yaw: yaw + Float(drag.width) * 0.008,
                            pitch: max(-0.8, min(0.8, pitch + Float(drag.height) * 0.005)),
                            distance: max(0.8, min(4, cameraDistance / Float(magnification))),
                            showMannequin: showMannequin, showSeams: showSeams)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                        .gesture(DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                yaw += Float(value.translation.width) * 0.008
                                pitch = max(-0.8, min(0.8, pitch + Float(value.translation.height) * 0.005))
                            })
                        .simultaneousGesture(MagnificationGesture()
                            .updating($magnification) { value, state, _ in state = value }
                            .onEnded { value in cameraDistance = max(0.8, min(4, cameraDistance / Float(value))) })
                        HStack {
                            Toggle("人台", isOn: $showMannequin)
                            Toggle("接缝", isOn: $showSeams)
                            Button("复位") { yaw = 0.35; pitch = -0.08; cameraDistance = 2.1 }
                        }
                        .font(.caption).tint(Color.appAccent)
                        Text(isStandaloneWaistband
                            ? "拖动旋转，双指缩放。侧视被手臂遮挡时可关闭人台；橙色线是原纸样侧缝。"
                            : "拖动旋转，双指缩放。橙色线是原纸样的配对侧缝。")
                            .font(.caption).foregroundStyle(.secondary)
                        qualitySummary(output)
                        if let exportURL {
                            ShareLink(item: exportURL, preview: SharePreview(isStandaloneWaistband ? "腰头 3D 试验网格" : "裙装 3D 试验网格")) {
                                Label("导出 3D 网格 OBJ", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.bordered)
                        }
                    } else if running {
                        VStack(spacing: 12) {
                            ProgressView(value: progress)
                            Text("正在本机计算垂坠… \(Int(progress * 100))%")
                                .font(.subheadline)
                            Button("取消计算", role: .cancel) { cancel() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ContentUnavailableView("尚未生成 3D", systemImage: "cube.transparent", description: Text("生成后可查看正面、背面和侧面；结果不会修改原始纸样或打印数据。"))
                            .frame(minHeight: 240)
                    }
                    if let issue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    if let sceneIssue {
                        Label(sceneIssue, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    if input != nil, !running {
                        Button(action: generate) {
                            Label(output == nil ? "生成离线 3D" : "重新计算", systemImage: "cube")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(Color.appAccent)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("试验范围").font(.subheadline.bold())
                        Text("标准人体按腰臀围和高度有限拟合，不是个人体型重建。标准人体模式分别检查末态布片自交和布片与人体的三角面交叉；参考圆台保留原对照方式。这些检查仍不能保证连续运动无穿插，面料也尚未实物标定。")
                        Text(isStandaloneWaistband
                            ? "顶口固定支撑用于观察腰头曲面，不包含裙身、拉链和扣合工艺；结果不能代替实际试衣。"
                            : "腰口固定支撑不代表已制作腰头或拉链。若需要其他款式，请继续使用现有 2D 纸样功能。")
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .background(Color.appBackground)
            .navigationTitle(isStandaloneWaistband ? "腰头 3D 试验" : "裙装 3D 试验")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回纸样") { cancel(); dismiss() }
                }
            }
        }
        .task { prepare() }
        .onChange(of: bodyMode) { _, _ in resetConfiguration() }
        .onChange(of: material) { _, _ in resetConfiguration() }
        .onDisappear { cancel() }
    }

    private func prepare() {
        do {
            guard case let .object(values)? = document.parameters?["body"] else {
                throw DrapeViewError.message("这份导入纸样没有完整量体来源。请在参数页核对人体尺寸，生成支持的款式后再打开 3D 试验。")
            }
            let body = GarmentCodeBodyParameters(values: values.compactMapValues(\.numberValue))
            var settings = GarmentCodeCircleDrape.Settings()
            settings.bodyMode = bodyMode
            settings.material = material
            settings.useSurfaceCollision = true
            settings.useBodySurfaceCollision = bodyMode == .standardMannequin
            if bodyMode == .standardMannequin { settings.solverIterations = 32 }
            if isStandaloneWaistband {
                let prepared=try GarmentCodeWaistbandAssembly.prepare(document:document,body:body,settings:settings)
                sewnInput=prepared
                input=prepared.cloth
            } else {
                sewnInput=nil
                input=try GarmentCodeSkirtDrape.prepare(document:document,body:body,settings:settings)
            }
            issue = nil
        } catch {
            input=nil;sewnInput=nil
            issue = error.localizedDescription
        }
    }

    private func resetConfiguration() {
        cancel()
        input = nil
        sewnInput = nil
        output = nil
        exportURL = nil
        issue = nil
        sceneIssue = nil
        prepare()
    }

    private func generate() {
        guard let input, !running else { return }
        cancel()
        let id = UUID()
        runID = id
        running = true
        progress = 0
        issue = nil
        sceneIssue = nil
        output = nil
        exportURL = nil
        let prepared=sewnInput
        let reportProgress:@Sendable(Double)->Void = { value in
            Task { @MainActor in
                guard runID == id,running else { return }
                progress=value
            }
        }
        let task = Task.detached(priority: .userInitiated) {
            if let prepared {
                return try GarmentCodeSewnDrape.simulate(input:prepared,
                    isCancelled:{Task.isCancelled},progress:reportProgress)
            }
            return try GarmentCodeCircleDrape.simulate(input:input,
                isCancelled:{Task.isCancelled},progress:reportProgress)
        }
        worker = task
        observer = Task { @MainActor in
            do {
                let result = try await task.value
                guard runID == id, !Task.isCancelled else { return }
                output = result
                running = false
                progress = 1
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("TailorAss-\(isStandaloneWaistband ? "waistband" : "skirt")-drape-\(id.uuidString).obj")
                do {
                    try result.objString.write(to: url, atomically: true, encoding: .utf8)
                    exportURL = url
                } catch {
                    issue = "3D 已生成，但导出文件创建失败：\(error.localizedDescription)"
                }
            } catch is CancellationError {
                guard runID == id else { return }
                running = false
            } catch {
                guard runID == id else { return }
                issue = error.localizedDescription
                running = false
            }
        }
    }

    private func cancel() {
        runID = UUID()
        worker?.cancel()
        observer?.cancel()
        worker = nil
        observer = nil
        running = false
    }

    private func qualitySummary(_ output: GarmentCodeCircleDrape.Output) -> some View {
        let diagnostics = output.diagnostics
        return VStack(alignment: .leading, spacing: 6) {
            Text("计算结果").font(.subheadline.bold())
            if let name = diagnostics.materialName { Text(name) }
            if let mass = diagnostics.totalFabricMassKg {
                Text("按参考裁片面积计算的布料质量 \(mass * 1000, specifier: "%.1f") g")
            }
            Text("\(output.positions.count) 个顶点 · \(output.triangleIndices.count / 3) 个三角形")
            Text("本次计算 \(diagnostics.computationSeconds, specifier: "%.1f") 秒 · \(diagnostics.converged ? "达到试验收敛条件" : "尚未达到试验收敛条件")")
            if diagnostics.sewingConstraintCount != nil {
                Text("最大网格边长变化 \(diagnostics.maxEdgeStrain * 100, specifier: "%.1f")% · 缝合点最大间隙 \(diagnostics.maxSeamGapMeters * 1000, specifier: "%.2f") mm")
            } else {
                Text("最大网格边长变化 \(diagnostics.maxEdgeStrain * 100, specifier: "%.1f")% · 共享接缝间隙 \(diagnostics.maxSeamGapMeters * 1000, specifier: "%.2f") mm")
            }
            Text("原纸样\(isStandaloneWaistband ? "上口" : "腰口")总长 \(diagnostics.waistCircumferenceMeters * 100, specifier: "%.1f") cm · \(diagnostics.patternLengthLabel ?? "径向裙长") \((diagnostics.patternLengthMeters ?? diagnostics.radialLengthMeters) * 100, specifier: "%.1f") cm")
            if let ratio = diagnostics.waistGatherRatio, ratio > 1.001,
               let support = diagnostics.supportWaistCircumferenceMeters {
                Text("腰部抽褶倍率 \(ratio, specifier: "%.2f") · 支撑腰围 \(support * 100, specifier: "%.1f") cm；原纸样尺寸没有缩小。")
            }
            ForEach(diagnostics.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.circle")
            }
            if let count = diagnostics.surfaceIntersectionCount {
                Text("末态布片自交检测：\(count) 组非相邻三角面交叉")
            }
            if let count = diagnostics.bodySurfaceIntersectionCount {
                Text("末态布片与人体相交检测：\(count) 组三角面交叉")
            }
            Text("末态检查不等于连续运动无穿插；原二维纸样与 PDF 保持不变。")
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private enum DrapeViewError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

private struct GarmentCodeDrapeScene: UIViewRepresentable {
    let output: GarmentCodeCircleDrape.Output
    let meshID: UUID
    @Binding var renderIssue: String?
    let yaw: Float
    let pitch: Float
    let distance: Float
    let showMannequin: Bool
    let showSeams: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = DrapeARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.onLayout = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.updateCamera(size: view.bounds.size)
        }
        view.environment.background = .color(UIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1))
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(context.coordinator.root)
        anchor.addChild(context.coordinator.camera)
        view.scene.addAnchor(anchor)
        let key = DirectionalLight()
        key.light.intensity = 2200
        key.look(at: [0, 0, 0], from: [1.5, 2.5, 2], relativeTo: nil)
        anchor.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 1300
        fill.look(at: [0, 0, 0], from: [-2, 1, -1.5], relativeTo: nil)
        anchor.addChild(fill)
        context.coordinator.camera.camera.fieldOfViewInDegrees = 44
        if #available(iOS 18.0, *) { context.coordinator.camera.camera.fieldOfViewOrientation = .vertical }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let coordinator = context.coordinator
        // A simulation produces one immutable output; camera changes don't rebuild geometry.
        if coordinator.meshIdentity != meshID, coordinator.failedIdentity != meshID {
            let positions = output.positions.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            let proxy = output.mannequinPositions.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            let all = positions + proxy
            let waistband=output.diagnostics.garmentStyle == "StraightWB" || output.diagnostics.garmentStyle == "FittedWB"
            let framing=waistband ? positions : all
            let low = framing.map(\.y).min() ?? 0, high = framing.map(\.y).max() ?? 1
            let center = SIMD3<Float>(0, (low + high) / 2, 0)
            coordinator.bodyOrbitRadius=proxy.reduce(0) {max($0,simd_length($1-center))}
            coordinator.halfHeight = max(waistband ? 0.18 : 0.1, (high-low)/2)
            coordinator.halfWidth = max(waistband ? 0.20 : 0.1, max((framing.map(\.x).max() ?? 0)-(framing.map(\.x).min() ?? 0),
                                                 (framing.map(\.z).max() ?? 0)-(framing.map(\.z).min() ?? 0))/2)
            let cloth: ModelEntity
            let mannequin: ModelEntity
            do {
                cloth = try model(positions: positions, indices: output.triangleIndices,
                                  color: UIColor(red: 0.14, green: 0.48, blue: 0.52, alpha: 1))
                mannequin = try model(positions: proxy, indices: output.mannequinTriangleIndices,
                                      color: UIColor(red: 0.70, green: 0.66, blue: 0.60, alpha: 1))
            } catch {
                coordinator.failedIdentity = meshID
                Task { @MainActor in renderIssue = "网格计算完成，但 3D 显示失败：\(error.localizedDescription)。可重新计算或导出网格检查。" }
                return
            }
            coordinator.root.children.removeAll()
            coordinator.content = Entity()
            coordinator.content.position = -center
            coordinator.root.addChild(coordinator.content)
            coordinator.content.addChild(cloth)
            coordinator.mannequin = mannequin
            coordinator.content.addChild(mannequin)
            coordinator.seams = Entity()
            let seamMaterial = UnlitMaterial(color: UIColor(red: 0.97, green: 0.48, blue: 0.13, alpha: 1))
            for path in output.seamPaths {
                for pair in zip(path, path.dropFirst()) where positions.indices.contains(pair.0) && positions.indices.contains(pair.1) {
                    let a = positions[pair.0], b = positions[pair.1]
                    let delta = b - a, length = simd_length(delta)
                    guard length > 0.00001 else { continue }
                    let segment = ModelEntity(mesh: .generateBox(size: [0.0028, length, 0.0028]), materials: [seamMaterial])
                    segment.position = (a + b) / 2
                    segment.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: delta / length)
                    coordinator.seams.addChild(segment)
                }
            }
            coordinator.content.addChild(coordinator.seams)
            coordinator.meshIdentity = meshID
            Task { @MainActor in renderIssue = nil }
        }
        coordinator.mannequin?.isEnabled = showMannequin
        coordinator.seams.isEnabled = showSeams
        coordinator.root.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
        let waistband=output.diagnostics.garmentStyle == "StraightWB" || output.diagnostics.garmentStyle == "FittedWB"
        if waistband,showMannequin {
            // A longer lens preserves the close waist framing while the
            // orbit stays outside the complete avatar at every rotation.
            coordinator.minimumCameraDistance=max(1.4,coordinator.bodyOrbitRadius+0.15)
        } else { coordinator.minimumCameraDistance=0 }
        coordinator.fieldOfViewDegrees=waistband ? 24 : 44
        coordinator.camera.camera.fieldOfViewInDegrees=coordinator.fieldOfViewDegrees
        coordinator.requestedDistance = distance
        coordinator.updateCamera(size: view.bounds.size)
    }

    private func model(positions: [SIMD3<Float>], indices: [UInt32], color: UIColor) throws -> ModelEntity {
        var normals = Array(repeating: SIMD3<Float>.zero, count: positions.count)
        for index in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[index]), b = Int(indices[index + 1]), c = Int(indices[index + 2])
            guard positions.indices.contains(a), positions.indices.contains(b), positions.indices.contains(c) else { continue }
            let normal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += normal; normals[b] += normal; normals[c] += normal
        }
        normals = normals.map { simd_length_squared($0) > 1e-12 ? simd_normalize($0) : [0, 1, 0] }
        var descriptor = MeshDescriptor(name: "Pattern-driven cloth")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.85
        material.faceCulling = .none
        return ModelEntity(mesh: try MeshResource.generate(from: [descriptor]), materials: [material])
    }

    final class Coordinator {
        let root = Entity()
        let camera = PerspectiveCamera()
        var content = Entity()
        var mannequin: ModelEntity?
        var seams = Entity()
        var meshIdentity: UUID?
        var failedIdentity: UUID?
        var halfHeight: Float = 0.6
        var halfWidth: Float = 0.3
        var requestedDistance: Float = 2.1
        var minimumCameraDistance: Float = 0
        var bodyOrbitRadius: Float = 1.2
        var fieldOfViewDegrees: Float = 44

        func updateCamera(size: CGSize) {
            guard size.width > 0, size.height > 0 else { return }
            let aspect = max(0.2, Float(size.width/size.height))
            let fitDistance = max(halfHeight, halfWidth/aspect)/tan(Float.pi*fieldOfViewDegrees/360)*1.12
            camera.look(at: [0, 0, 0], from: [0, 0.03, max(minimumCameraDistance,fitDistance*requestedDistance/2.1)], relativeTo: nil)
        }
    }
}

private final class DrapeARView: ARView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
