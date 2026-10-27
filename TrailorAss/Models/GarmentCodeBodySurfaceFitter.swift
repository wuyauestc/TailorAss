import Foundation
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Explicit opt-in draft fitting for four project surface measurement types.
/// This creates no collision/pose capability and never uses the legacy SDF.
nonisolated enum GarmentCodeBodySurfaceFitter {
    typealias M = GarmentCodeBodySurfaceMeasurements
    typealias D = GarmentCodeFitDeformationReplay
    typealias V = M.V
    struct Options: Sendable {
        var maximumIterations = 24
        var maximumEvaluations = 512
        var maximumWorkingBytes = 32 * 1024 * 1024
        var absoluteGoalToleranceMeters = 1e-5
        var finiteDifferenceStep = 1e-5
    }
    enum Status: String, Codable, Sendable {
        case draftSurfaceGoalsReached, iterationBudget, evaluationBudget, memoryBudget
        case cancelled, invalidInput, invalidOptions, noProgress, geometryRejected
    }
    struct Residual: Codable, Sendable {
        let id: String, targetKey: String
        let observedMeters: Double, requestedMeters: Double, observedMinusRequestedMeters: Double
    }
    struct Quality: Codable, Sendable {
        let minimumTriangleAreaSquareMeters: Double, minimumReferenceNormalCosine: Double
    }
    struct Iteration: Codable, Sendable {
        let index: Int, evaluations: Int
        let controls: [Double], costSquareMeters: Double, maximumAbsoluteResidualMeters: Double
    }
    struct Attempt: Codable, Sendable {
        let status: Status, reason: String?
        let sourceGeometrySHA256: String?, sourceParameterSHA256: String?
        let contractSHA256: String, rigResourceSHA256: String
        let diagnosticPositions: [V], triangleIndices: [UInt32]
        let residuals: [Residual], controls: [Double], quality: Quality?
        let iterations: [Iteration], evaluations: Int, rejectedGeometryTrials: Int
        let diagnosticMeasurement: M.Report?
        let bodyCapabilityIssued: Bool, requiresCompleteIntersectionAudit: Bool
        let compatibleWithLegacyInverseSDF: Bool, all26BodyFieldsIndependentlyFitted: Bool
    }
    enum FittingError: LocalizedError, Sendable {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(s) = self { return "局部人体拟合无效：" + s }; return nil }
    }
    private struct Source: Decodable, Sendable { let baseline: [String: Double], positions: [[Double]], triangleIndices: [UInt32] }
    private struct Point: Sendable {
        let ids: [Int], weights: [Double]
        func value(_ p: [V]) -> V { zip(ids, weights).reduce(V.zero) { $0 + p[$1.0] * $1.1 } }
    }
    private struct Metric: Sendable { let definition: M.Definition, points: [Point] }
    private enum Stop: Error { case cancelled, evaluationBudget, geometry }
    // A callback may alter the thread's floating-point environment. Latch the
    // first violation and stop before another callback can hide it by restoring
    // rounding. This lock protects only a flag; it never guards user code.
    private final class CancellationCheck: @unchecked Sendable {
        private let lock = NSLock()
        private let callback: @Sendable () -> Bool
        private var failedRounding = false
        init(_ callback: @escaping @Sendable () -> Bool) { self.callback = callback }
        var roundingFailed: Bool { lock.lock(); defer { lock.unlock() }; return failedRounding }
        private func mark() { lock.lock(); failedRounding = true; lock.unlock() }
        func call() -> Bool {
            if roundingFailed { return true }
            guard nearestRounding else { mark(); return true }
            let cancelled = callback()
            guard nearestRounding else { mark(); return true }
            return cancelled
        }
    }
    struct Prepared: Sendable {
        private let measurements: M.Prepared, source: Source
        private let deformation: D.Prepared, metrics: [Metric]
        init(contractData: Data, templateData: Data, rigData: Data, auxiliaryWeightsData: Data,
             isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
            let check = CancellationCheck(isCancelled)
            let checkedCancel: @Sendable () -> Bool = { check.call() }
            do {
                if checkedCancel() { throw CancellationError() }
                let m = try M.Prepared(contractData: contractData, templateData: templateData, rigData: rigData, isCancelled: checkedCancel)
                let shared = try D.Prepared(templateData: templateData, rigData: rigData, contractData: contractData, auxiliaryWeightsData: auxiliaryWeightsData, isCancelled: checkedCancel)
                var inverse = Array(repeating: -1, count: m.contract.sourceVertexCount)
                for (i, id) in m.contract.visibleToSource.enumerated() { inverse[id] = i }
                func attachment(_ a: M.Attachment) -> Point { .init(ids: a.sourceVertexIDs.map { inverse[$0] }, weights: a.weights) }
                measurements = m; source = try JSONDecoder().decode(Source.self, from: templateData); deformation = shared
                metrics = m.contract.measurements.filter { $0.targetUse == "projectFittingReference" }.map { .init(definition: $0, points: $0.samples.map(attachment)) }
                guard metrics.count == 6 else { throw FittingError.invalid("需要胸、肩横宽、双臂和双腕六个固定表面目标。") }
                if checkedCancel() { throw CancellationError() }
            } catch is CancellationError {
                if check.roundingFailed { throw FittingError.invalid("不支持当前浮点舍入环境。") }
                throw CancellationError()
            }
        }
        /// Snapshot is the existing immutable canonical source. Replay binds
        /// it to all input values before a diagnostic draft can be optimized.
        func fit(source snapshot: GarmentCodeStandardBody.Snapshot, bodyValues: [String: Double], options: Options = .init(),
                 isCancelled: @escaping @Sendable () -> Bool = { false }) -> Attempt {
            let check = CancellationCheck(isCancelled)
            let checkedCancel: @Sendable () -> Bool = { check.call() }
            var initial: M.Report?, current: Evaluation?, kernel: Kernel?
            var controls = [0.0, 0, 0, 0], history: [Iteration] = [], evaluations = 0, rejected = 0
            func finish(_ status: Status, _ reason: String? = nil) -> Attempt {
                var finalStatus = status, finalReason = reason
                let p = current?.positions ?? initial?.positions ?? []
                let residuals: [Residual]
                if let k = kernel, let q = current { residuals = k.metrics.indices.map { .init(id: k.metrics[$0].definition.id, targetKey: k.metrics[$0].definition.targetKey, observedMeters: q.values[$0], requestedMeters: k.targets[$0], observedMinusRequestedMeters: q.residuals[$0]) } }
                else { residuals = initial?.measurements.filter { $0.definition.targetUse == "projectFittingReference" }.map { .init(id: $0.definition.id, targetKey: $0.definition.targetKey, observedMeters: $0.observedMeters, requestedMeters: $0.requestedMeters, observedMinusRequestedMeters: $0.observedMinusRequestedMeters) } ?? [] }
                var report: M.Report?
                if status != .cancelled, !check.roundingFailed, !p.isEmpty {
                    do { report = try measurements.measure(positions: p, triangleIndices: snapshot.triangleIndices, bodyValues: bodyValues, isCancelled: checkedCancel) }
                    catch is CancellationError { finalStatus = .cancelled }
                    catch { if status == .draftSurfaceGoalsReached { finalStatus = .geometryRejected }; finalReason = error.localizedDescription }
                }
                if checkedCancel() { finalStatus = .cancelled; report = nil }
                if check.roundingFailed { finalStatus = .invalidInput; finalReason = "不支持当前浮点舍入环境。"; report = nil }
                return .init(status: finalStatus, reason: finalReason, sourceGeometrySHA256: initial?.geometrySHA256, sourceParameterSHA256: initial?.parameterSHA256,
                    contractSHA256: M.approvedContractSHA256, rigResourceSHA256: measurements.contract.rigResourceSHA256,
                    diagnosticPositions: p, triangleIndices: p.isEmpty ? [] : snapshot.triangleIndices, residuals: residuals,
                    controls: controls, quality: current?.quality, iterations: history, evaluations: evaluations, rejectedGeometryTrials: rejected,
                    diagnosticMeasurement: report, bodyCapabilityIssued: false, requiresCompleteIntersectionAudit: true,
                    compatibleWithLegacyInverseSDF: false, all26BodyFieldsIndependentlyFitted: false)
            }
            do {
                if checkedCancel() { return finish(.cancelled) }
                initial = try measurements.measure(positions: snapshot.positions, triangleIndices: snapshot.triangleIndices, bodyValues: bodyValues, isCancelled: checkedCancel)
                guard (0...64).contains(options.maximumIterations), (1...2048).contains(options.maximumEvaluations),
                      (1...64 * 1024 * 1024).contains(options.maximumWorkingBytes),
                      options.absoluteGoalToleranceMeters.isFinite, (1e-9...1e-2).contains(options.absoluteGoalToleranceMeters),
                      options.finiteDifferenceStep.isFinite, (1e-7...1e-3).contains(options.finiteDifferenceStep) else { return finish(.invalidOptions) }
                guard options.maximumWorkingBytes >= 32 * 1024 * 1024 else { return finish(.memoryBudget, "需要预留32MiB有界临时工作区。") }
                try replay(snapshot.positions, snapshot.triangleIndices, bodyValues, checkedCancel)
                let context = try deformation.context(sourcePositions: snapshot.positions, triangleIndices: snapshot.triangleIndices, bodyValues: bodyValues, isCancelled: checkedCancel)
                kernel = try Kernel(base: snapshot.positions, triangles: snapshot.triangleIndices, metrics: metrics, deformationContext: context,
                                    values: bodyValues, isCancelled: checkedCancel)
                let k = kernel!
                func evaluate(_ a: [Double]) throws -> Evaluation {
                    if checkedCancel() { throw Stop.cancelled }
                    guard evaluations < options.maximumEvaluations else { throw Stop.evaluationBudget }
                    evaluations += 1
                    return try k.evaluate(a, checkedCancel)
                }
                current = try evaluate(controls)
                func record() { history.append(.init(index: history.count, evaluations: evaluations, controls: controls,
                    costSquareMeters: current!.cost, maximumAbsoluteResidualMeters: current!.maximumResidual)) }
                record()
                var damping = 1e-6
                for _ in 0..<options.maximumIterations {
                    if checkedCancel() { throw Stop.cancelled }
                    if current!.maximumResidual <= options.absoluteGoalToleranceMeters { return finish(.draftSurfaceGoalsReached) }
                    var jacobian = Array(repeating: [Double](repeating: 0, count: 4), count: 6)
                    for j in 0..<4 {
                        let h = options.finiteDifferenceStep * max(1, abs(controls[j]))
                        var plus = controls, minus = controls; plus[j] = min(upper[j], plus[j] + h); minus[j] = max(lower[j], minus[j] - h)
                        let a = try evaluate(plus), b = try evaluate(minus), width = plus[j] - minus[j]
                        guard width > 0 else { return finish(.noProgress, "参数已在有限域边界。") }
                        for i in 0..<6 { jacobian[i][j] = (a.residuals[i] - b.residuals[i]) / width }
                    }
                    var hessian = Array(repeating: [Double](repeating: 0, count: 4), count: 4), gradient = [Double](repeating: 0, count: 4)
                    for i in 0..<6 { for j in 0..<4 {
                        gradient[j] += jacobian[i][j] * current!.residuals[i]
                        for l in 0..<4 { hessian[j][l] += jacobian[i][j] * jacobian[i][l] }
                    }}
                    var accepted = false
                    for _ in 0..<12 {
                        var system = hessian
                        for j in 0..<4 { system[j][j] += damping * max(hessian[j][j], 1e-12) }
                        guard let step = solve(system, gradient.map { -$0 }) else { return finish(.noProgress, "局部线性系统不能可靠求解。") }
                        let trial = (0..<4).map { max(lower[$0], min(upper[$0], controls[$0] + step[$0])) }
                        guard trial != controls else { return finish(.noProgress, "有限域内没有可表示的新参数。") }
                        do {
                            let candidate = try evaluate(trial)
                            if candidate.cost < current!.cost {
                                controls = trial; current = candidate; damping = max(1e-12, damping / 5); accepted = true; record(); break
                            }
                        } catch Stop.geometry { rejected += 1 }
                        damping *= 10
                    }
                    if !accepted { return finish(.noProgress, "有界尝试没有降低实际固定表面残差。") }
                }
                return finish(current!.maximumResidual <= options.absoluteGoalToleranceMeters ? .draftSurfaceGoalsReached : .iterationBudget)
            } catch is CancellationError { return finish(.cancelled) }
              catch Stop.cancelled { return finish(.cancelled) }
              catch Stop.evaluationBudget { return finish(.evaluationBudget) }
              catch Stop.geometry { return finish(.geometryRejected, "当前有限差分或候选包含退化/反向面。") }
              catch { return finish(.invalidInput, error.localizedDescription) }
        }
        private func replay(_ p: [V], _ triangles: [UInt32], _ v: [String: Double], _ cancel: @Sendable () -> Bool) throws {
            guard triangles == source.triangleIndices, p.count == source.positions.count,
                  let height = v["height"], let waist = v["waist"], let hips = v["hips"], let hipLine = v["hips_line"], let waistLevel = v["_waist_level"],
                  let bh = source.baseline["height"], let bw = source.baseline["waist"], let bp = source.baseline["hips"], let bl = source.baseline["hipLine"], let by = source.baseline["waistLevel"] else { throw FittingError.invalid("原人体或五尺度参数不完整。") }
            let ws = waist / 100 / bw, hs = hips / 100 / bp, hy = hipLine / 100 / bl, ly = (waistLevel - hipLine) / 100 / (by - bl), uy = (height - waistLevel) / 100 / (bh - by)
            guard [ws, hs, hy, ly, uy].allSatisfy({ $0.isFinite && (0.5...1.8).contains($0) }) else { throw FittingError.invalid("原人体不在旧五尺度有限域。") }
            for i in p.indices {
                if i % 128 == 0, cancel() { throw Stop.cancelled }
                let q = source.positions[i], y = q[1], t = max(0, min(1, (y + bl) / bl)), blend = t * t * (3 - 2 * t), h = hs + (ws - hs) * blend
                let yy = y >= 0 ? y * uy : (y >= -bl ? y * hy : -bl * hy + (y + bl) * ly)
                let expected = V(x: q[0] * h, y: yy, z: q[2] * h)
                guard p[i].x.bitPattern == expected.x.bitPattern, p[i].y.bitPattern == expected.y.bitPattern, p[i].z.bitPattern == expected.z.bitPattern else { throw FittingError.invalid("需要同一参数生成的原始参考姿态；不能直接传入摆臂或任意替换网格。") }
            }
        }
    }
    private struct Evaluation {
        let positions: [V], values: [Double], residuals: [Double], quality: Quality
        var cost: Double { residuals.reduce(0) { $0 + $1 * $1 } / 2 }
        var maximumResidual: Double { residuals.map(abs).max()! }
    }
    private struct Kernel {
        let base: [V], triangles: [UInt32], metrics: [Metric]
        let deformationContext: D.Context, targets: [Double], normals: [V]
        init(base: [V], triangles: [UInt32], metrics: [Metric], deformationContext: D.Context,
             values: [String: Double], isCancelled: @Sendable () -> Bool) throws {
            self.base = base; self.triangles = triangles; self.metrics = metrics; self.deformationContext = deformationContext
            targets = metrics.map { values[$0.definition.targetKey]! / 100 }
            var result: [V] = []
            for face in 0..<(triangles.count / 3) {
                if face % 128 == 0, isCancelled() { throw Stop.cancelled }
                result.append((base[Int(triangles[face * 3 + 1])] - base[Int(triangles[face * 3])]).cross(base[Int(triangles[face * 3 + 2])] - base[Int(triangles[face * 3])]))
            }
            normals = result
        }
        func evaluate(_ controls: [Double], _ cancel: @Sendable () -> Bool) throws -> Evaluation {
            let p = try deformationContext.deform(controls: controls, isCancelled: cancel).visiblePositions
            var minimumArea = Double.infinity, minimumCosine = Double.infinity
            guard p.allSatisfy({ $0.isFinite && $0.length < 100 }) else { throw Stop.geometry }
            for face in normals.indices {
                if face % 128 == 0, cancel() { throw Stop.cancelled }
                let a = p[Int(triangles[face * 3])], b = p[Int(triangles[face * 3 + 1])], c = p[Int(triangles[face * 3 + 2])]
                let n = (b - a).cross(c - a), length = n.length, referenceLength = normals[face].length
                guard length.isFinite, length > 0, referenceLength > 0 else { throw Stop.geometry }
                let cosine = dot(n, normals[face]) / (length * referenceLength)
                guard cosine.isFinite, cosine > 0 else { throw Stop.geometry }
                minimumArea = min(minimumArea, length / 2); minimumCosine = min(minimumCosine, cosine)
            }
            let values = metrics.map { m -> Double in
                let q = m.points.map { $0.value(p) }
                if m.definition.kind == "axisDistanceX" { return abs(q[1].x - q[0].x) }
                if m.definition.kind == "pointDistance" { return (q[1] - q[0]).length }
                var sum = 0.0; for j in 1..<q.count { sum += (q[j] - q[j - 1]).length }
                if m.definition.closed == true { sum += (q[0] - q[q.count - 1]).length }; return sum
            }
            guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw Stop.geometry }
            return .init(positions: p, values: values, residuals: zip(values, targets).map(-),
                         quality: .init(minimumTriangleAreaSquareMeters: minimumArea, minimumReferenceNormalCosine: minimumCosine))
        }
    }
    private static var nearestRounding: Bool {
        #if os(macOS)
        return Darwin.fegetround() == FE_TONEAREST
        #elseif canImport(NativeClothCollision)
        return FloatingPointEnvironment.isNearestRounding
        #else
        return false
        #endif
    }
    private static let lower = [log(0.75), -1.4, log(0.65), log(0.7)]
    private static let upper = [log(1.3), 1.4, log(1.2), log(1.4)]
    private static func dot(_ a: V, _ b: V) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
    private static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = (0..<4).map { matrix[$0] + [rhs[$0]] }
        for k in 0..<4 {
            let pivot = (k..<4).max { abs(a[$0][k]) < abs(a[$1][k]) }!
            guard a[pivot][k].isFinite, abs(a[pivot][k]) > 1e-18 else { return nil }
            a.swapAt(k, pivot); let value = a[k][k]; for j in k...4 { a[k][j] /= value }
            for i in 0..<4 where i != k { let scale = a[i][k]; for j in k...4 { a[i][j] -= scale * a[k][j] } }
        }
        let result = a.map { $0[4] }; return result.allSatisfy(\.isFinite) ? result : nil
    }
}
