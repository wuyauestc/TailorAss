import Foundation
import CryptoKit
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Opt-in fixed surface preparation. Requests may contain the legacy source,
/// but an issued surface never contains that Snapshot or its inverse SDF.
nonisolated enum GarmentCodeFittedBody {
    typealias V = GarmentCodeCircleDrape.Vector3
    typealias D = GarmentCodeFitDeformationReplay
    typealias M = GarmentCodeBodySurfaceMeasurements
    typealias F = GarmentCodeBodySurfaceFitter
    typealias B = GarmentCodeBodySurfaceContact
    typealias Q = GarmentCodeBodyMeshQueries
    typealias G = GarmentCodeBodySurfaceValidator
    static let goalToleranceMeters = 1e-5
    enum PosePolicy: Sendable, Equatable {
        case fittedReference
        case matchPatternReference(alphaDegrees: Double)
        var alphaDegrees: Double? { if case let .matchPatternReference(a) = self { return a }; return nil }
    }
    struct Limits: Sendable {
        var maximumCapturedResourceBytes = 24 * 1024 * 1024
        var maximumEstimatedWorkingBytes = 256 * 1024 * 1024
        var maximumVertices = 20_000
        var maximumTriangles = 40_000
        var surfaceValidation = G.Limits()
        var queries = Q.Limits()
        var queryVerification = Q.Options()
    }
    enum PreparationError: LocalizedError, Sendable {
        case invalid(String), budget(String), unsupportedRounding, workerRequired
        case goalsNotReached([F.Residual])
        case fittingRejected(F.Status, [F.Residual], Int)
        var errorDescription: String? { switch self {
        case let .invalid(s): return "拟合人体来源无效：" + s
        case let .budget(s): return "拟合人体准备超出预算：" + s
        case .unsupportedRounding: return "拟合人体准备要求最近舍入环境及可用的浮点环境桥。"
        case .workerRequired: return "拟合人体准备需要在后台工作线程执行。"
        case let .goalsNotReached(r): return "拟合后的六项表面尺寸尚未达到目标，最大差值 " + String(format: "%.4f mm", (r.map { abs($0.observedMinusRequestedMeters) }.max() ?? 0) * 1000) + "。"
        case let .fittingRejected(s, _, n): return "人体尺寸拟合未完成（" + s.rawValue + "，评估 " + String(n) + " 次）；未创建人体凭证。"
        }}
    }
    /// Owned, bounded copies of the four request resources. Hash validation is
    /// performed by the shared replay, rather than trusting claimed digests.
    struct Resources: Sendable {
        fileprivate let template: Data, rig: Data, contract: Data, auxiliary: Data
        var byteCount: Int { template.count + rig.count + contract.count + auxiliary.count }
        init(templateData: Data, rigData: Data, contractData: Data, auxiliaryWeightsData: Data,
             limits: Limits = .init(), isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
            let c = CancellationCheck(isCancelled); try c.checkpoint()
            try validateLimits(limits)
            let parts = [templateData, rigData, contractData, auxiliaryWeightsData]
            guard zip(parts, resourceByteCaps).allSatisfy({ $0.count <= $1 }), parts.reduce(0, { $0 + $1.count }) <= limits.maximumCapturedResourceBytes else { throw PreparationError.budget("四份来源资源大小") }
            // An explicit byte copy also breaks a caller-supplied mapped or
            // no-copy Data buffer before it crosses a worker boundary.
            template = Data([UInt8](templateData)); try c.checkpoint()
            rig = Data([UInt8](rigData)); try c.checkpoint()
            contract = Data([UInt8](contractData)); try c.checkpoint()
            auxiliary = Data([UInt8](auxiliaryWeightsData)); try c.checkpoint()
        }
    }
    struct Recipe: Sendable {
        fileprivate let referencePositions: [V], triangleIndices: [UInt32]
        let bodyValues: [String: Double], controls: [Double], posePolicy: PosePolicy
        fileprivate let resources: Resources
        fileprivate init(source: GarmentCodeStandardBody.Snapshot, bodyValues: [String: Double], controls: [Double], pose: PosePolicy, resources: Resources) {
            referencePositions = source.positions; triangleIndices = source.triangleIndices
            self.bodyValues = bodyValues; self.controls = controls; posePolicy = pose; self.resources = resources
        }
    }
    /// The source is retained only in this unvalidated worker request because
    /// the existing optimizer requires the immutable canonical Snapshot type.
    struct FittingRecipe: Sendable {
        fileprivate let source: GarmentCodeStandardBody.Snapshot
        let bodyValues: [String: Double], posePolicy: PosePolicy
        fileprivate let resources: Resources
        fileprivate init(source: GarmentCodeStandardBody.Snapshot, bodyValues: [String: Double], pose: PosePolicy, resources: Resources) {
            self.source = source; self.bodyValues = bodyValues; posePolicy = pose; self.resources = resources
        }
    }
    struct Bindings: Codable, Sendable {
        let version: String
        let templateResourceSHA256: String, rigResourceSHA256: String, contractSHA256: String, auxiliaryResourceSHA256: String
        let originalWeightsSHA256: String, sourceGeometrySHA256: String, sourceParameterSHA256: String
        let fitRecipeSHA256: String, fittedRestGeometrySHA256: String, poseRecipeSHA256: String, finalGeometrySHA256: String
        let sourceMappingSHA256: String, triangleIndicesSHA256: String
        let bodyValues: [String: Double], controls: [Double], alphaDegrees: Double?
        let goalToleranceMeters: Double, maximumRestGoalResidualMeters: Double
        let patternReferenceCompatible: Bool
    }
    struct FittingSummary: Codable, Sendable {
        let status: F.Status, iterations: Int, evaluations: Int, maximumResidualMeters: Double
    }
    /// No Decodable conformance and no public/memberwise initializer. This
    /// receipt is issued only after actual replay and complete mesh validation.
    struct SurfaceReceipt: Sendable {
        let mesh: B.BodyMesh
        let bindings: Bindings
        let posePolicy: PosePolicy
        let completeGeometryReport: G.Report
        private let certificate: G.Certificate
        private let originalRecipe: Recipe
        var geometrySHA256: String { bindings.finalGeometrySHA256 }
        var bodyValues: [String: Double] { bindings.bodyValues }
        var controls: [Double] { bindings.controls }
        var alphaDegrees: Double? { bindings.alphaDegrees }
        var matchesPatternReference: Bool { bindings.patternReferenceCompatible }
        var fitRecipeSHA256: String { bindings.fitRecipeSHA256 }
        var poseRecipeSHA256: String { bindings.poseRecipeSHA256 }
        var compatibleWithLegacyInverseSDF: Bool { false }
        var anatomicalFitCertified: Bool { false }
        private init(mesh: B.BodyMesh, bindings: Bindings, certificate: G.Certificate, originalRecipe: Recipe) {
            self.mesh = mesh; self.bindings = bindings; self.certificate = certificate; self.originalRecipe = originalRecipe
            posePolicy = originalRecipe.posePolicy; completeGeometryReport = certificate.report
        }
        fileprivate static func issue(mesh: B.BodyMesh, bindings: Bindings, certificate: G.Certificate, originalRecipe: Recipe) -> Self {
            .init(mesh: mesh, bindings: bindings, certificate: certificate, originalRecipe: originalRecipe)
        }
        func verify(positions: [V], triangleIndices: [UInt32], bodyValues: [String: Double], requirePatternReference: Bool = true,
                    isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
            let c = CancellationCheck(isCancelled); try c.checkpoint()
            guard sameValues(bodyValues, bindings.bodyValues), (!requirePatternReference || matchesPatternReference),
                  bindings.version == "tailorass-fitted-surface-v1", bindings.goalToleranceMeters.bitPattern == goalToleranceMeters.bitPattern,
                  bindings.maximumRestGoalResidualMeters <= goalToleranceMeters, certificate.report.completedAllPairs,
                  certificate.geometrySHA256 == geometrySHA256 else { throw PreparationError.invalid("人体参数、姿态角色或完整几何来源不同。") }
            guard triangleIndices == mesh.triangleIndices, positions.count == mesh.positions.count else { throw PreparationError.invalid("最终人体拓扑不同。") }
            try requireSame(positions, mesh.positions, c)
            try certificate.verify(positions: positions, triangleIndices: triangleIndices, isCancelled: { c.cancelled() })
            try verifyResources(originalRecipe.resources, bindings)
            try c.checkpoint()
        }
        func verify(recipe: Recipe, isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
            let c = CancellationCheck(isCancelled); try c.checkpoint()
            guard sameValues(recipe.bodyValues, bodyValues), sameScalars(recipe.controls, controls), samePose(recipe.posePolicy, posePolicy),
                  recipe.triangleIndices == originalRecipe.triangleIndices,
                  recipe.resources.template == originalRecipe.resources.template, recipe.resources.rig == originalRecipe.resources.rig,
                  recipe.resources.contract == originalRecipe.resources.contract, recipe.resources.auxiliary == originalRecipe.resources.auxiliary else { throw PreparationError.invalid("请求的参数、controls、pose或资源不同。") }
            try requireSame(recipe.referencePositions, originalRecipe.referencePositions, c)
            try verify(positions: mesh.positions, triangleIndices: mesh.triangleIndices, bodyValues: recipe.bodyValues,
                       requirePatternReference: false, isCancelled: { c.cancelled() })
            try c.checkpoint()
        }
    }
    struct Prepared: Sendable {
        let surface: SurfaceReceipt
        let exactQueries: Q.Prepared
        let restMeasurements: M.Report
        let restGeometryReport: G.Report
        let finalGeometryReport: G.Report
        let poseData: D.PoseData
        let fittingSummary: FittingSummary?
        var bodyModel: String { surface.matchesPatternReference ? "MakeHuman CC0 项目表面目标拟合／参考摆臂" : "MakeHuman CC0 项目表面目标拟合／参考姿势" }
        private init(surface: SurfaceReceipt, exactQueries: Q.Prepared, restMeasurements: M.Report, restGeometryReport: G.Report,
                     poseData: D.PoseData, fittingSummary: FittingSummary?) {
            self.surface = surface; self.exactQueries = exactQueries; self.restMeasurements = restMeasurements
            self.restGeometryReport = restGeometryReport; finalGeometryReport = surface.completeGeometryReport
            self.poseData = poseData; self.fittingSummary = fittingSummary
        }
        fileprivate static func make(_ recipe: Recipe, limits: Limits, fittingSummary: FittingSummary?, _ c: CancellationCheck) throws -> Self {
            try c.checkpoint(); try validateLimits(limits)
            guard !Thread.isMainThread else { throw PreparationError.workerRequired }
            try budget(recipe.resources, vertices: recipe.referencePositions.count, triangles: recipe.triangleIndices.count / 3, limits: limits)
            let r = recipe.resources
            let replay = try D.Prepared(templateData: r.template, rigData: r.rig, contractData: r.contract, auxiliaryWeightsData: r.auxiliary, isCancelled: { c.cancelled() })
            let context = try replay.context(sourcePositions: recipe.referencePositions, triangleIndices: recipe.triangleIndices,
                                             bodyValues: recipe.bodyValues, isCancelled: { c.cancelled() })
            let shape = try context.deform(controls: recipe.controls, isCancelled: { c.cancelled() })
            let measurements = try M.Prepared(contractData: r.contract, templateData: r.template, rigData: r.rig, isCancelled: { c.cancelled() })
            let rest = try measurements.measure(positions: shape.visiblePositions, triangleIndices: shape.triangleIndices,
                                                bodyValues: recipe.bodyValues, isCancelled: { c.cancelled() })
            let goals = residuals(rest)
            guard goals.count == 6, goals.allSatisfy({ abs($0.observedMinusRequestedMeters) <= goalToleranceMeters }) else { throw PreparationError.goalsNotReached(goals) }
            let pose: D.Pose
            switch recipe.posePolicy {
            case .fittedReference: pose = .identity
            case let .matchPatternReference(a):
                guard let expected = recipe.bodyValues["arm_pose_angle"], a.isFinite, a.bitPattern == expected.bitPattern else { throw PreparationError.invalid("摆臂请求必须逐位匹配同一33参数的 arm_pose_angle。") }
                pose = .arms(alphaDegrees: a)
            }
            let posed = try context.pose(shape, pose: pose, isCancelled: { c.cancelled() })
            let pattern: Bool
            switch recipe.posePolicy {
            case .fittedReference: pattern = false
            case .matchPatternReference:
                guard posed.matchesInputArmPoseAngle == true, let a = posed.alphaDegrees,
                      a.bitPattern == recipe.bodyValues["arm_pose_angle"]!.bitPattern else { throw PreparationError.invalid("最终摆臂来源不匹配裁片参考姿态。") }
                pattern = true
            }
            guard posed.bodyValues.count == 33, sameValues(posed.bodyValues, recipe.bodyValues),
                  rest.geometrySHA256 == shape.geometrySHA256, rest.parameterSHA256 == posed.sourceParameterSHA256,
                  shape.geometrySHA256 == posed.fittedRestGeometrySHA256, shape.triangleIndices == posed.triangleIndices else { throw PreparationError.invalid("拟合、测量和摆姿来源未逐项绑定。") }
            // Validate the fitted rest surface as well as the final surface.
            // Reuse is allowed only for an exactly identical actual mesh.
            let restCertificate = try G.validate(positions: shape.visiblePositions, triangleIndices: shape.triangleIndices,
                                                  limits: limits.surfaceValidation, isCancelled: { c.cancelled() })
            let finalCertificate: G.Certificate
            if samePositions(shape.visiblePositions, posed.visiblePositions) && shape.triangleIndices == posed.triangleIndices {
                try restCertificate.verify(positions: posed.visiblePositions, triangleIndices: posed.triangleIndices, isCancelled: { c.cancelled() })
                finalCertificate = restCertificate
            } else {
                finalCertificate = try G.validate(positions: posed.visiblePositions, triangleIndices: posed.triangleIndices,
                                                   limits: limits.surfaceValidation, isCancelled: { c.cancelled() })
            }
            try c.checkpoint()
            let mesh = try B.BodyMesh(positions: posed.visiblePositions, triangleIndices: posed.triangleIndices, signedDistance: nil)
            try c.checkpoint()
            let queries = try Q.Prepared(body: mesh, limits: limits.queries, isCancelled: { c.cancelled() })
            guard queries.geometrySHA256 == posed.geometrySHA256, finalCertificate.geometrySHA256 == posed.geometrySHA256,
                  restCertificate.geometrySHA256 == shape.geometrySHA256,
                  finalCertificate.report.completedAllPairs, restCertificate.report.completedAllPairs,
                  queries.triangleIndices == mesh.triangleIndices, samePositions(queries.positions, mesh.positions) else { throw PreparationError.invalid("显示表面、完整验证和实际Q索引的几何不同。") }
            let onSurface = queries.query(mesh.positions[0], options: limits.queryVerification, isCancelled: { c.cancelled() })
            guard onSurface.classification == .onSurface, onSurface.issue == nil, onSurface.signedDistanceMeters == 0 else { throw PreparationError.invalid("同一实际人体表面的Q校验未完成。") }
            let map = measurements.contract.visibleToSource
            let binding = Bindings(version: "tailorass-fitted-surface-v1", templateResourceSHA256: posed.templateResourceSHA256,
                rigResourceSHA256: posed.rigResourceSHA256, contractSHA256: posed.contractSHA256, auxiliaryResourceSHA256: posed.auxiliaryResourceSHA256,
                originalWeightsSHA256: "0f3641d651ae3d00ad6b4ccee43142edb109d3bd909d27d9e4139ef1beed8625",
                sourceGeometrySHA256: posed.sourceGeometrySHA256, sourceParameterSHA256: posed.sourceParameterSHA256,
                fitRecipeSHA256: posed.fitRecipeSHA256, fittedRestGeometrySHA256: posed.fittedRestGeometrySHA256,
                poseRecipeSHA256: posed.poseRecipeSHA256, finalGeometrySHA256: posed.geometrySHA256,
                sourceMappingSHA256: integerHash(map), triangleIndicesSHA256: indexHash(posed.triangleIndices), bodyValues: recipe.bodyValues,
                controls: recipe.controls, alphaDegrees: posed.alphaDegrees, goalToleranceMeters: goalToleranceMeters,
                maximumRestGoalResidualMeters: goals.map { abs($0.observedMinusRequestedMeters) }.max()!, patternReferenceCompatible: pattern)
            try verifyResources(r, binding); try c.checkpoint()
            let surface = SurfaceReceipt.issue(mesh: mesh, bindings: binding, certificate: finalCertificate, originalRecipe: recipe)
            try surface.verify(recipe: recipe, isCancelled: { c.cancelled() }); try c.checkpoint()
            return .init(surface: surface, exactQueries: queries, restMeasurements: rest, restGeometryReport: restCertificate.report,
                         poseData: posed, fittingSummary: fittingSummary)
        }
    }
    static func resources(resourceDirectory: URL, limits: Limits = .init(), isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> Resources {
        let c = CancellationCheck(isCancelled); try c.checkpoint(); try validateLimits(limits)
        var data: [Data] = []
        for (name, maximum) in zip(resourceNames, resourceByteCaps) {
            try c.checkpoint(); let url = resourceDirectory.appendingPathComponent(name)
            let remaining = limits.maximumCapturedResourceBytes - data.reduce(0, { $0 + $1.count })
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size >= 0, size <= min(maximum, remaining) else { throw PreparationError.budget("资源文件 " + name) }
            data.append(try readBounded(url, maximum: min(maximum, remaining), c))
        }
        return try Resources(templateData: data[0], rigData: data[1], contractData: data[2], auxiliaryWeightsData: data[3], limits: limits, isCancelled: { c.cancelled() })
    }
    static func recipe(source: GarmentCodeStandardBody.Snapshot, bodyValues: [String: Double], controls: [Double], pose: PosePolicy, resources: Resources) -> Recipe {
        .init(source: source, bodyValues: bodyValues, controls: controls, pose: pose, resources: resources)
    }
    static func capture(source: GarmentCodeStandardBody.Snapshot, bodyValues: [String: Double], controls: [Double], pose: PosePolicy,
                        resourceDirectory: URL, limits: Limits = .init(), isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> Recipe {
        recipe(source: source, bodyValues: bodyValues, controls: controls, pose: pose,
               resources: try resources(resourceDirectory: resourceDirectory, limits: limits, isCancelled: isCancelled))
    }
    static func captureFit(source: GarmentCodeStandardBody.Snapshot, bodyValues: [String: Double], pose: PosePolicy,
                           resourceDirectory: URL, limits: Limits = .init(), isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> FittingRecipe {
        .init(source: source, bodyValues: bodyValues, pose: pose, resources: try resources(resourceDirectory: resourceDirectory, limits: limits, isCancelled: isCancelled))
    }
    static func fittingRecipe(source: GarmentCodeStandardBody.Snapshot, bodyValues: [String: Double], pose: PosePolicy, resources: Resources) -> FittingRecipe {
        .init(source: source, bodyValues: bodyValues, pose: pose, resources: resources)
    }
    static func prepare(_ recipe: Recipe, limits: Limits = .init(), isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> Prepared {
        let c = CancellationCheck(isCancelled)
        do { return try Prepared.make(recipe, limits: limits, fittingSummary: nil, c) }
        catch { if c.roundingFailed { throw PreparationError.unsupportedRounding }; throw error }
    }
    static func fitAndPrepare(_ request: FittingRecipe, options: F.Options = .init(), limits: Limits = .init(),
                              isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> Prepared {
        let c = CancellationCheck(isCancelled)
        do {
            try c.checkpoint(); try validateLimits(limits)
            guard !Thread.isMainThread else { throw PreparationError.workerRequired }
            guard (1...64 * 1024 * 1024).contains(options.maximumWorkingBytes) else { throw PreparationError.invalid("优化工作区选项无效。") }
            try budget(request.resources, vertices: request.source.positions.count, triangles: request.source.triangleIndices.count / 3,
                       limits: limits, optimizerBytes: options.maximumWorkingBytes)
            let r = request.resources
            let fitter = try F.Prepared(contractData: r.contract, templateData: r.template, rigData: r.rig, auxiliaryWeightsData: r.auxiliary, isCancelled: { c.cancelled() })
            let attempt = fitter.fit(source: request.source, bodyValues: request.bodyValues, options: options, isCancelled: { c.cancelled() })
            try c.checkpoint()
            guard attempt.status == .draftSurfaceGoalsReached else { throw PreparationError.fittingRejected(attempt.status, attempt.residuals, attempt.evaluations) }
            // Only controls are consumed. Neither the decodable Attempt nor
            // its supplied positions/report is an authority for this factory.
            let raw = recipe(source: request.source, bodyValues: request.bodyValues, controls: attempt.controls, pose: request.posePolicy, resources: r)
            let stats = FittingSummary(status: attempt.status, iterations: max(0, attempt.iterations.count - 1), evaluations: attempt.evaluations,
                                       maximumResidualMeters: attempt.residuals.map { abs($0.observedMinusRequestedMeters) }.max()!)
            return try Prepared.make(raw, limits: limits, fittingSummary: stats, c)
        } catch { if c.roundingFailed { throw PreparationError.unsupportedRounding }; throw error }
    }
    private static let resourceNames = ["GarmentCodeStandardBody.json", "GarmentCodeStandardBodyRig/rig.json", "GarmentCodeBodySurfaceMeasurements.json", "GarmentCodeBodyFitAuxiliaryWeights.json"]
    private static let resourceByteCaps = [8_000_000, 8_000_000, 2_000_000, 1_000_000]
    private static func validateLimits(_ limits: Limits) throws {
        guard (1...32 * 1024 * 1024).contains(limits.maximumCapturedResourceBytes), (1...512 * 1024 * 1024).contains(limits.maximumEstimatedWorkingBytes),
              (4...100_000).contains(limits.maximumVertices), (4...200_000).contains(limits.maximumTriangles),
              (1...512 * 1024 * 1024).contains(limits.surfaceValidation.maximumEstimatedWorkingBytes),
              (4...100_000).contains(limits.queries.maximumVertices), (4...200_000).contains(limits.queries.maximumTriangles),
              (1...100_000).contains(limits.queries.maximumBVHNodes) else { throw PreparationError.invalid("资源或几何预算无效。") }
    }
    private static func budget(_ r: Resources, vertices: Int, triangles: Int, limits: Limits, optimizerBytes: Int = 0) throws {
        guard r.byteCount <= limits.maximumCapturedResourceBytes, vertices <= limits.maximumVertices, triangles <= limits.maximumTriangles,
              vertices <= limits.queries.maximumVertices, triangles <= limits.queries.maximumTriangles else { throw PreparationError.budget("来源点、面或资源数量") }
        let reservation = r.byteCount + 64 * 1024 * 1024 + limits.surfaceValidation.maximumEstimatedWorkingBytes + optimizerBytes
        guard reservation <= limits.maximumEstimatedWorkingBytes else { throw PreparationError.budget("几何/查询/重放及优化保守工作区预留") }
    }
    private static func residuals(_ report: M.Report) -> [F.Residual] {
        report.measurements.filter { $0.definition.targetUse == "projectFittingReference" }.map {
            .init(id: $0.definition.id, targetKey: $0.definition.targetKey, observedMeters: $0.observedMeters,
                  requestedMeters: $0.requestedMeters, observedMinusRequestedMeters: $0.observedMinusRequestedMeters)
        }
    }
    private static func verifyResources(_ resources: Resources, _ bindings: Bindings) throws {
        guard hash(resources.template) == bindings.templateResourceSHA256, hash(resources.rig) == bindings.rigResourceSHA256,
              hash(resources.contract) == bindings.contractSHA256, hash(resources.auxiliary) == bindings.auxiliaryResourceSHA256,
              bindings.contractSHA256 == M.approvedContractSHA256, bindings.auxiliaryResourceSHA256 == D.approvedAuxiliarySHA256 else { throw PreparationError.invalid("已捕获的来源资源字节不同。") }
    }
    private static func sameScalars(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { $0.bitPattern == $1.bitPattern } }
    private static func sameValues(_ a: [String: Double], _ b: [String: Double]) -> Bool { Set(a.keys) == Set(b.keys) && a.allSatisfy { b[$0.key]?.bitPattern == $0.value.bitPattern } }
    private static func samePose(_ a: PosePolicy, _ b: PosePolicy) -> Bool {
        switch (a, b) { case (.fittedReference, .fittedReference): return true
        case let (.matchPatternReference(x), .matchPatternReference(y)): return x.bitPattern == y.bitPattern
        default: return false }
    }
    private static func samePositions(_ a: [V], _ b: [V]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { $0.x.bitPattern == $1.x.bitPattern && $0.y.bitPattern == $1.y.bitPattern && $0.z.bitPattern == $1.z.bitPattern } }
    private static func requireSame(_ a: [V], _ b: [V], _ c: CancellationCheck) throws {
        guard a.count == b.count else { throw PreparationError.invalid("人体点数不同。") }
        for i in a.indices {
            if i % 128 == 0 { try c.checkpoint() }; let x = a[i], y = b[i]
            guard x.x.bitPattern == y.x.bitPattern, x.y.bitPattern == y.y.bitPattern, x.z.bitPattern == y.z.bitPattern else { throw PreparationError.invalid("实际人体坐标位不同。") }
        }
    }
    private static func readBounded(_ url: URL, maximum: Int, _ c: CancellationCheck) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var result = Data()
        while result.count <= maximum {
            try c.checkpoint()
            let bytes = try handle.read(upToCount: min(65_536, maximum + 1 - result.count)) ?? Data()
            if bytes.isEmpty { return result }; result.append(bytes)
        }
        throw PreparationError.budget("读取中的资源超过捕获上限")
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func integerHash(_ values: [Int]) -> String { var d = Data("fitted-visible-source-map-v1\0".utf8); for i in values { var x = UInt64(i).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }; return hash(d) }
    private static func indexHash(_ values: [UInt32]) -> String { var d = Data("fitted-source-triangles-v1\0".utf8); for i in values { var x = i.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }; return hash(d) }
    fileprivate final class CancellationCheck: @unchecked Sendable {
        private let callback: @Sendable () -> Bool, lock = NSLock()
        private var badRounding = false
        init(_ callback: @escaping @Sendable () -> Bool) { self.callback = callback }
        var roundingFailed: Bool { lock.lock(); defer { lock.unlock() }; return badRounding }
        private func mark() { lock.lock(); badRounding = true; lock.unlock() }
        func cancelled() -> Bool { if roundingFailed { return true }; guard nearest else { mark(); return true }; let value = callback(); guard nearest else { mark(); return true }; return value }
        func checkpoint() throws { if cancelled() { if roundingFailed { throw PreparationError.unsupportedRounding }; throw CancellationError() } }
        private var nearest: Bool {
            #if os(macOS)
            return fegetround() == FE_TONEAREST
            #elseif canImport(NativeClothCollision)
            return FloatingPointEnvironment.isNearestRounding
            #else
            return false
            #endif
        }
    }
}
