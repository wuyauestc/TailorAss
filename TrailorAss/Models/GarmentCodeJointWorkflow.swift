import Foundation

/// App orchestration for the complete-source solver. Only source capture and
/// receipt binding run on MainActor; meshing, factors, stepping and final
/// validation have a serial detached owner. No intermediate mesh is returned.
nonisolated enum GarmentCodeJointWorkflow {
    typealias S = GarmentCodeJointSimulation
    typealias R = GarmentCodeJointResult
    typealias Fabric = GarmentCodeJointFabric

    enum Phase: String, Sendable {
        case capturing, preparing, assembling, gravityRamp, settling, validating, completed
    }
    struct Progress: Sendable {
        let phase: Phase
        let completedSteps: Int
        let maximumSteps: Int
        let phaseCompletedSteps: Int
        let phaseMaximumSteps: Int
        /// This is a completed-work counter, never an estimated completion
        /// percentage. Settling may terminate before the available step budget.
        let consecutiveQuietSteps: Int
        let requiredQuietSteps: Int
    }
    struct Result: Sendable {
        let validated: R.Validated
        let sourceCaptureSeconds: Double
        let preparationSeconds: Double
        let generationWallSeconds: Double
        fileprivate init(validated: R.Validated, sourceCaptureSeconds: Double,
                         preparationSeconds: Double, generationWallSeconds: Double) {
            self.validated = validated
            self.sourceCaptureSeconds = sourceCaptureSeconds
            self.preparationSeconds = preparationSeconds
            self.generationWallSeconds = generationWallSeconds
        }
    }
    enum WorkflowError: LocalizedError, Sendable {
        case rejected(step: Int, phase: Phase, reason: String)
        case stabilityBudget(completedSteps: Int)
        case gatheredSeamsUnavailable
        var errorDescription: String? {
            switch self {
            case let .rejected(step, phase, _):
                let name = phase == .assembling ? "裁片缝合" : "重力下垂"
                return "\(name)在第 \(step) 步未通过求解检查，本次没有生成完整成衣。"
            case let .stabilityBudget(steps):
                return "已计算 \(steps) 步，衣服尚未达到持续稳定条件。请保留当前参数用于复查。"
            case .gatheredSeamsUnavailable:
                return "这份纸样包含抽褶接缝，整衣3D的抽褶缝合仍在完善，暂时无法生成可验收结果。二维纸样可以正常使用。"
            }
        }
    }

    /// The caller owns one task per generation and cancels it on dismissal or
    /// configuration changes. Cancellation propagates to both detached stages.
    /// Only the final validator can produce the returned result capability.
    @MainActor static func generate(
        document: GarmentCodePatternFile,
        body: GarmentCodeBodyParameters,
        design: GarmentCodeDesignParameters,
        material: Fabric.Preset,
        bodyPoseSelection: S.K.BodyPoseSelection = .legacyTemplate,
        bodyShapeSelection: S.K.BodyShapeSelection = .scaledTemplate,
        bodyResourceDirectory: URL? = nil,
        settings: S.Settings = .init(),
        sourceLimits: GarmentCodeNativeAssembly.Limits = .init(),
        workerLimits: S.WorkerLimits = .init(),
        resultLimits: R.Limits = .init(),
        progress: @escaping @MainActor @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Result {
        try Task.checkCancellation()
        let clock = ContinuousClock(), began = clock.now
        let relay = ProgressRelay(callback: progress)
        defer { relay.finish() }
        relay.send(.init(phase: .capturing, completedSteps: 0, maximumSteps: settings.maximumSteps,
                         phaseCompletedSteps: 0, phaseMaximumSteps: 0, consecutiveQuietSteps: 0,
                         requiredQuietSteps: settings.requiredQuietSteps), sequence: 0)
        var sourceSettings = Fabric.sourceSettings(material, bodyResourceDirectory: bodyResourceDirectory)
        sourceSettings.bodyPoseSelection = bodyPoseSelection
        sourceSettings.bodyShapeSelection = bodyShapeSelection
        let recipe = try S.capture(document: document, body: body, design: design,
            sourceSettings: sourceSettings,
            materials: Fabric.materials(material), settings: settings, sourceLimits: sourceLimits,
            isCancelled: { Task.isCancelled })
        let captureSeconds = seconds(began.duration(to: clock.now)), preparing = clock.now
        try Task.checkCancellation()
        relay.send(.init(phase: .preparing, completedSteps: 0, maximumSteps: settings.maximumSteps,
                         phaseCompletedSteps: 0, phaseMaximumSteps: 0, consecutiveQuietSteps: 0,
                         requiredQuietSteps: settings.requiredQuietSteps), sequence: 1)
        let prepared = try await detached {
            let prepared = try S.prepare(recipe: recipe, isCancelled: { Task.isCancelled })
            // Check the real source-bound plan after complete preparation.
            // Do not spend the App's step budget on a seam the final validator
            // deliberately cannot certify yet. CLI S.prepare/solve stays intact.
            guard !prepared.input.source.plan.usesFiniteCoarseTacks else {
                throw WorkflowError.gatheredSeamsUnavailable
            }
            return prepared
        }
        try Task.checkCancellation()
        let receipt = try R.prepare(document: document, simulation: prepared,
                                    isCancelled: { Task.isCancelled })
        let preparationSeconds = seconds(preparing.duration(to: clock.now))
        relay.send(.init(phase: .assembling, completedSteps: 0, maximumSteps: settings.maximumSteps,
                         phaseCompletedSteps: 0, phaseMaximumSteps: settings.staticAssemblySteps,
                         consecutiveQuietSteps: 0, requiredQuietSteps: settings.requiredQuietSteps), sequence: 2)
        let report: @Sendable (Progress, Int) -> Void = { value, sequence in
            Task { @MainActor in relay.send(value, sequence: sequence) }
        }
        let validated = try await detached {
            try simulate(receipt, workerLimits: workerLimits, resultLimits: resultLimits, progress: report)
        }
        try Task.checkCancellation()
        // Finish on the calling actor before returning. Queued worker updates
        // cannot replace this event or arrive after cancellation/return.
        let completed = validated.metrics.completedSteps
        relay.send(.init(phase: .completed, completedSteps: completed, maximumSteps: settings.maximumSteps,
                         phaseCompletedSteps: settings.requiredQuietSteps, phaseMaximumSteps: settings.requiredQuietSteps,
                         consecutiveQuietSteps: settings.requiredQuietSteps, requiredQuietSteps: settings.requiredQuietSteps),
                   sequence: settings.maximumSteps + 4)
        return .init(validated: validated, sourceCaptureSeconds: captureSeconds,
                     preparationSeconds: preparationSeconds, generationWallSeconds: seconds(began.duration(to: clock.now)))
    }

    /// A cancelled parent must not leave unstructured CPU work running. The
    /// return-side cancellation check also covers a child completing at the
    /// same instant as its parent is cancelled.
    static func detached<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try operation()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            do {
                let value = try await task.value
                try Task.checkCancellation()
                return value
            } catch {
                // Cancellation wins even when the worker exits by throwing a
                // resource/solver error at the same time. Still await its exit.
                try Task.checkCancellation()
                throw error
            }
        } onCancel: { task.cancel() }
    }

    private static func simulate(_ receipt: R.Prepared, workerLimits: S.WorkerLimits, resultLimits: R.Limits,
                                 progress: @Sendable (Progress, Int) -> Void) throws -> R.Validated {
        try Task.checkCancellation()
        let prepared = receipt.simulation, settings = prepared.settings
        let session = try prepared.makeSession(limits: workerLimits, isCancelled: { Task.isCancelled })
        var computationSeconds = 0.0
        for step in 1...settings.maximumSteps {
            try Task.checkCancellation()
            let attempt = try session.advanceStep(isCancelled: { Task.isCancelled })
            try Task.checkCancellation()
            let report = attempt.report, phase: Phase
            switch report.phase {
            case .staticAssembly: phase = .assembling
            case .gravityRamp: phase = .gravityRamp
            case .settling: phase = .settling
            }
            guard report.accepted else {
                throw WorkflowError.rejected(step: step, phase: phase, reason: report.rejectionReason ?? "unknown")
            }
            computationSeconds += report.computationSeconds
            let offset = phase == .assembling ? 0 : (phase == .gravityRamp ? settings.staticAssemblySteps : settings.staticAssemblySteps + settings.gravityRampSteps)
            let budget = phase == .assembling ? settings.staticAssemblySteps : (phase == .gravityRamp ? settings.gravityRampSteps : settings.maximumAdditionalSteps)
            progress(.init(phase: phase, completedSteps: step, maximumSteps: settings.maximumSteps,
                           phaseCompletedSteps: step - offset, phaseMaximumSteps: budget,
                           consecutiveQuietSteps: report.consecutiveQuietSteps, requiredQuietSteps: settings.requiredQuietSteps), step + 2)
            if report.numericallyStableCandidate {
                progress(.init(phase: .validating, completedSteps: step, maximumSteps: settings.maximumSteps,
                               phaseCompletedSteps: 0, phaseMaximumSteps: 0,
                               consecutiveQuietSteps: report.consecutiveQuietSteps, requiredQuietSteps: settings.requiredQuietSteps), settings.maximumSteps + 3)
                return try receipt.validate(session: session, acceptedStepComputationSeconds: computationSeconds,
                                            limits: resultLimits, isCancelled: { Task.isCancelled })
            }
        }
        throw WorkflowError.stabilityBudget(completedSteps: session.state.completedSteps)
    }
    private static func seconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    /// MainActor ownership and monotone sequence numbers prevent detached
    /// notification ordering from regressing the progress UI.
    @MainActor final class ProgressRelay {
        private let callback: @MainActor @Sendable (Progress) -> Void
        private var lastSequence = -1
        private var active = true
        init(callback: @escaping @MainActor @Sendable (Progress) -> Void) { self.callback = callback }
        func send(_ progress: Progress, sequence: Int) {
            guard active, sequence > lastSequence else { return }
            lastSequence = sequence
            callback(progress)
        }
        func finish() { active = false }
    }
}
