import CNativeClothCollision

/// Conservative CCD primitives only. Elasticity, sewing, broadphase and contact filtering are separate.
public enum NativeClothCollision {
    public enum Status: Int32, Sendable { case invalid = 0, noHit = 1, conservativeHit = 2, uncertain = 3 }
    public enum Detail: Int32, Sendable {
        case none = 0, invalidArgument = 1, unsupportedScale = 2, uncertainGeometry = 3
        case precisionOrBudget = 4, roundingMode = 5, internalFailure = 6, cancelled = 7
    }
    public struct Options: Sendable {
        public var minimumSeparation: Double
        public var maximumTime: Double
        public var distanceTolerance: Double
        public var maximumIterations: Int64
        public init(minimumSeparation: Double = 0, maximumTime: Double = 1,
                    distanceTolerance: Double = 1e-8, maximumIterations: Int64 = 10_000) {
            self.minimumSeparation = minimumSeparation
            self.maximumTime = maximumTime
            self.distanceTolerance = distanceTolerance
            self.maximumIterations = maximumIterations
        }
    }
    public struct Result: Sendable {
        public let status: Status
        public let detail: Detail
        /// Infinity only for noHit; uncertain results cannot authorize advancement.
        public let conservativeTimeOfImpact: Double
        public let achievedDistanceTolerance: Double
        public let configuredIterationBudget: Int64
        /// Only this status certifies absence of contact during the requested time interval.
        public var permitsWholeInterval: Bool { status == .noHit }
    }
    public static var upstreamRevision: String { String(cString: ncc_upstream_revision()) }

    /// Four xyz rows per endpoint: vertex/triangle0/triangle1/triangle2.
    public static func vertexFace(start: [Double], end: [Double], options: Options = .init(),
                                  isCancelled: (() -> Bool)? = nil) -> Result {
        evaluate(start: start, end: end, options: options, vertexFace: true, isCancelled: isCancelled)
    }
    /// Four xyz rows per endpoint: edgeA0/edgeA1/edgeB0/edgeB1.
    public static func edgeEdge(start: [Double], end: [Double], options: Options = .init(),
                                isCancelled: (() -> Bool)? = nil) -> Result {
        evaluate(start: start, end: end, options: options, vertexFace: false, isCancelled: isCancelled)
    }
    private static func evaluate(start: [Double], end: [Double], options: Options,
                                 vertexFace: Bool, isCancelled: (() -> Bool)?) -> Result {
        func cancelled() -> Result {
            Result(status: .uncertain, detail: .cancelled, conservativeTimeOfImpact: 0,
                   achievedDistanceTolerance: .infinity, configuredIterationBudget: options.maximumIterations)
        }
        if isCancelled?() == true { return cancelled() }
        let o = NCCOptions(minimum_separation: options.minimumSeparation, maximum_time: options.maximumTime,
                           distance_tolerance: options.distanceTolerance, maximum_iterations: options.maximumIterations)
        let r = start.withUnsafeBufferPointer { a in
            end.withUnsafeBufferPointer { b in
                vertexFace ? ncc_vertex_face(a.baseAddress, a.count, b.baseAddress, b.count, o)
                           : ncc_edge_edge(a.baseAddress, a.count, b.baseAddress, b.count, o)
            }
        }
        if isCancelled?() == true { return cancelled() }
        return Result(status: Status(rawValue: r.status) ?? .uncertain,
                      detail: Detail(rawValue: r.detail) ?? .internalFailure,
                      conservativeTimeOfImpact: r.conservative_time_of_impact,
                      achievedDistanceTolerance: r.achieved_distance_tolerance,
                      configuredIterationBudget: r.configured_iteration_budget)
    }
}

