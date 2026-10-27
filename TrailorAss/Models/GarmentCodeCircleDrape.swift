import Foundation

/// A deliberately bounded, offline cloth experiment. The two circular panels
/// supply the rest lengths; neither a stock garment mesh nor a scaled template
/// is used. This is not an industrial fabric/fit simulator.
enum GarmentCodeCircleDrape {
    nonisolated struct Vector3: Codable, Hashable, Sendable {
        var x: Double
        var y: Double
        var z: Double

        static let zero = Self(x: 0, y: 0, z: 0)
        static func + (a: Self, b: Self) -> Self { .init(x: a.x+b.x, y: a.y+b.y, z: a.z+b.z) }
        static func - (a: Self, b: Self) -> Self { .init(x: a.x-b.x, y: a.y-b.y, z: a.z-b.z) }
        static func * (a: Self, b: Double) -> Self { .init(x: a.x*b, y: a.y*b, z: a.z*b) }
        static func / (a: Self, b: Double) -> Self { a * (1/b) }
        var lengthSquared: Double { x*x+y*y+z*z }
        var length: Double { sqrt(lengthSquared) }
        var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
        func cross(_ b: Self) -> Self { .init(x: y*b.z-z*b.y, y: z*b.x-x*b.z, z: x*b.y-y*b.x) }
    }

    nonisolated enum BodyPoseSelection:String,Sendable {case legacyTemplate,matchPatternReference}
    nonisolated enum BodyShapeSelection:String,Sendable {case scaledTemplate,surfaceMeasurements}
    nonisolated struct Settings: Sendable {
        nonisolated enum BodyMode: String, CaseIterable, Identifiable, Sendable {
            case referenceCylinder, standardMannequin
            var id: String { rawValue }
            var title: String { self == .standardMannequin ? "标准人体（实验）" : "参考圆台（对照）" }
        }
        var targetEdgeMeters = 0.035
        var maximumSteps = 2400
        var solverIterations = 24
        // Defaults reproduce the original controlled experiment. The App
        // explicitly selects the new anatomical/surface-contact configuration.
        var bodyMode: BodyMode = .referenceCylinder
        var bodyPoseSelection:BodyPoseSelection = .legacyTemplate
        var bodyShapeSelection:BodyShapeSelection = .scaledTemplate
        var material: GarmentCodeClothMaterial.Preset? = nil
        var useSurfaceCollision = false
        var useBodySurfaceCollision = false
        // Exact mesh contact needs less padding than the coarse SDF samples.
        // This is a numerical clearance, not calibrated fabric thickness.
        var bodySurfaceClearanceMeters = 0.0005
        // Optional numerical strain limiting; legacy skirt controls leave it
        // off. It projects actual positions and never changes source lengths.
        var sourceStrainLimit: Double? = nil
        var sourceStrainLimitPasses = 40
        var bodyResourceDirectory: URL? = nil
    }

    nonisolated struct Diagnostics: Codable, Sendable {
        let vertexCount: Int
        let triangleCount: Int
        let simulatedSeconds: Double
        let computationSeconds: Double
        let maxEdgeStrain: Double
        let meanEdgeStrain: Double
        let maxSpeedMetersPerSecond: Double
        let maxBodyPenetrationMeters: Double
        let maxSeamGapMeters: Double
        let waistCircumferenceMeters: Double
        let hemCircumferenceMeters: Double
        let radialLengthMeters: Double
        let referenceAreaSquareMeters: Double
        let converged: Bool
        let warnings: [String]
        var bodyModel: String? = nil
        var materialName: String? = nil
        var totalFabricMassKg: Double? = nil
        var surfaceIntersectionCount: Int? = nil
        var closeSurfacePairCount: Int? = nil
        var garmentStyle: String? = nil
        var patternLengthLabel: String? = nil
        var patternLengthMeters: Double? = nil
        var waistGatherRatio: Double? = nil
        var supportWaistCircumferenceMeters: Double? = nil
        var bodySurfaceIntersectionCount: Int? = nil
        var bodySurfaceCandidatePairCount: Int? = nil
        var maxBodySurfacePlaneOverlapMeters: Double? = nil
        var bodySurfaceClearanceMeters: Double? = nil
        var waistSupportClearanceMeters: Double? = nil
        var sewingConstraintCount: Int? = nil
        var sewingRMSGapMeters: Double? = nil
        var sewingUsesFiniteTacks: Bool? = nil
        var sewingProjectionTravelBudgetMeters: Double? = nil
        var sewingSingleProjectionLimitMeters: Double? = nil
        var sourceStrainLimitFraction: Double? = nil
        var sourceStrainLimitPassCount: Int? = nil
        var sewnTimeStepSeconds: Double? = nil
        var sewnContactPaddingMeters: Double? = nil
        var usesVirtualSewingPointBodyContact: Bool? = nil
        var usesSourcePathBounds: Bool? = nil
        var usesSimultaneousFinalSewing: Bool? = nil
        var sewingBlockLinearSystemsConverged: Bool? = nil
        var usesContinuousBodyContact: Bool? = nil
        var continuousBodyFrameCount: Int? = nil
        var continuousBodyLimitedFrameCount: Int? = nil
        var minimumContinuousBodyTimeFraction: Double? = nil
        var continuousBodyComputationSeconds: Double? = nil
        var usesSourceAwareSewnContactRibbons: Bool? = nil
        var staticAssemblyFrameCount: Int? = nil
        var gravityRampFrameCount: Int? = nil
    }

    nonisolated struct PanelGroup: Codable, Sendable {
        let panelID: String
        let vertexIDs: [Int]
        let triangleIDs: [Int]
    }

    nonisolated struct Output: Codable, Sendable {
        let positions: [Vector3]
        let triangleIndices: [UInt32]
        let mannequinPositions: [Vector3]
        let mannequinTriangleIndices: [UInt32]
        let seamPaths: [[Int]]
        let seamVertexPairs: [SeamPair]
        let diagnostics: Diagnostics
        /// Separate source-panel membership for composed garments. Legacy
        /// welded control outputs leave this nil and keep their export bytes.
        var panelGroups: [PanelGroup]? = nil

        /// Output JSON can outlive a solver run. Invalid optional membership
        /// must not omit cloth faces or index outside the immutable topology.
        var validatedPanelGroups: [PanelGroup]? {
            guard let groups=panelGroups,!groups.isEmpty,triangleIndices.count%3==0 else { return nil }
            let faceCount=triangleIndices.count/3
            var vertices=Set<Int>(),faces=Set<Int>(),names=Set<String>()
            for group in groups {
                guard !group.panelID.isEmpty,names.insert(group.panelID).inserted,
                      !group.vertexIDs.isEmpty,!group.triangleIDs.isEmpty else { return nil }
                var local=Set<Int>()
                for id in group.vertexIDs {
                    guard positions.indices.contains(id),local.insert(id).inserted,vertices.insert(id).inserted else { return nil }
                }
                for face in group.triangleIDs {
                    guard (0..<faceCount).contains(face),faces.insert(face).inserted,
                          (0..<3).allSatisfy({local.contains(Int(triangleIndices[face*3+$0]))}) else { return nil }
                }
            }
            return vertices.count==positions.count && faces.count==faceCount ? groups : nil
        }

        /// The export is in metres, +Y up. Pattern JSON remains untouched.
        var objString: String {
            let band=diagnostics.garmentStyle == "StraightWB" || diagnostics.garmentStyle == "FittedWB"
            let objectName:String
            switch diagnostics.garmentStyle {
            case "StraightWB": objectName="straight_waistband"
            case "FittedWB": objectName="fitted_waistband"
            case "Skirt2": objectName="two_panel_skirt"
            case nil, "SkirtCircle": objectName="circle_skirt"
            default: objectName="sewn_garment"
            }
            let kind=band ? "waistband" : (objectName=="sewn_garment" ? "garment" : "skirt")
            var lines = ["# TailorAss experimental pattern-driven \(kind) drape; metres; +Y up",
                         "# Numerical material; standard mannequin or reference proxy; not validated personal fit",
                         "o \(objectName)"]
            lines += positions.map { "v \($0.x) \($0.y) \($0.z)" }
            let groups=validatedPanelGroups
            if panelGroups != nil && groups == nil {
                lines.append("# Invalid optional panel membership; exporting every original cloth face without groups")
            }
            if let groups {
                for (index,panel) in groups.enumerated() {
                    let safe=panel.panelID.unicodeScalars.map { scalar -> String in
                        let n=scalar.value
                        return (48...57).contains(n) || (65...90).contains(n) || (97...122).contains(n) || n==95 ? String(scalar) : "_"
                    }.joined()
                    lines.append("g panel_\(index)_\(safe)")
                    for face in panel.triangleIDs {
                        let t=face*3
                        lines.append("f \(triangleIndices[t]+1) \(triangleIndices[t+1]+1) \(triangleIndices[t+2]+1)")
                    }
                }
            } else {
                for t in stride(from: 0, to: triangleIndices.count, by: 3) {
                    lines.append("f \(triangleIndices[t]+1) \(triangleIndices[t+1]+1) \(triangleIndices[t+2]+1)")
                }
            }
            lines.append("o \(diagnostics.bodyModel?.hasPrefix("MakeHuman") == true ? "standard_mannequin" : "analytic_collision_proxy")")
            if groups != nil { lines.append("g mannequin") }
            lines += mannequinPositions.map { "v \($0.x) \($0.y) \($0.z)" }
            let offset = UInt32(positions.count)+1
            for t in stride(from: 0, to: mannequinTriangleIndices.count, by: 3) {
                lines.append("f \(mannequinTriangleIndices[t]+offset) \(mannequinTriangleIndices[t+1]+offset) \(mannequinTriangleIndices[t+2]+offset)")
            }
            return lines.joined(separator: "\n")+"\n"
        }
    }

    nonisolated struct Input: Sendable {
        let positions: [Vector3]
        let triangleIndices: [UInt32]
        let referencePositions: [Vector3]
        let referenceTriangles: [UInt32]
        let referenceToSimulation: [Int]
        let panelColumns: Int
        let radialSegments: Int
        let seamPaths: [[Int]]
        let seamVertexPairs: [SeamPair]
        let pinned: [Bool]
        let springs: [Spring]
        let bendingSprings: [Spring]
        let body: ProxyBody
        let mannequinPositions: [Vector3]
        let mannequinTriangleIndices: [UInt32]
        let waistCircumferenceMeters: Double
        let hemCircumferenceMeters: Double
        let radialLengthMeters: Double
        let referenceAreaSquareMeters: Double
        let settings: Settings
        var standardBody: GarmentCodeStandardBody.Snapshot? = nil
        var fixedBodySurface:GarmentCodeBodySurfaceContact.FixedSurfaceReceipt? = nil
        var fittedBodySurface:GarmentCodeFittedBody.SurfaceReceipt? = nil
        var surfaceTopology: GarmentCodeClothContact.Topology? = nil
        var bodySurfaceMesh: GarmentCodeBodySurfaceContact.BodyMesh? = nil
        var inverseMasses: [Double] = []
        var meanParticleMassKg: Double = 1
        var totalFabricMassKg: Double? = nil
        var garmentStyle = "SkirtCircle"
        var patternLengthLabel = "径向裙长"
        var preparationWarnings: [String] = []
        var waistGatherRatio = 1.0
    }

    nonisolated struct Spring: Sendable {
        let a: Int
        let b: Int
        let length: Double
        var isShear = false
    }

    /// A prepared source-edge strain inequality. It changes real particle
    /// positions; the original rest lengths and material springs stay intact.
    /// This is a numerical stabilization primitive, not fabric calibration.
    nonisolated struct SourceStrainLimiter: Sendable {
        nonisolated struct Statistics: Sendable {
            var examinedConstraints = 0
            var projectedConstraints = 0
            var unresolvedPinnedConstraints = 0
            var collapsedConstraints = 0
            var cappedCorrections = 0
            /// Largest displacement from one edge projection. It is not a
            /// whole-pass or time-step displacement bound.
            var maximumSingleVertexCorrectionMeters = 0.0
        }

        nonisolated enum LimiterError: LocalizedError, Sendable {
            case invalid(String)
            case budgetExceeded(String)
            var errorDescription: String? {
                switch self {
                case let .invalid(message), let .budgetExceeded(message): return message
                }
            }
        }

        private nonisolated struct Constraint: Sendable {
            let a: Int
            let b: Int
            let minimumLength: Double
            let maximumLength: Double
            let weightA: Double
            let weightB: Double
            let weightSum: Double
        }

        let vertexCount: Int
        let maximumAbsoluteStrain: Double
        let maximumSingleVertexCorrectionMeters: Double
        let maximumPositionMagnitudeMeters: Double
        private let constraints: [Constraint]

        init(vertexCount: Int, springs: [Spring], normalizedInverseMass: [Double],
             maximumAbsoluteStrain: Double = 0.05,
             maximumSingleVertexCorrectionMeters: Double = 0.02,
             maximumVertices: Int = 100_000, maximumConstraints: Int = 300_000,
             maximumPositionMagnitudeMeters: Double = 5) throws {
            guard (1...100_000).contains(maximumVertices),
                  (1...300_000).contains(maximumConstraints),
                  maximumAbsoluteStrain.isFinite, (0...0.4).contains(maximumAbsoluteStrain),
                  maximumPositionMagnitudeMeters.isFinite,
                  maximumPositionMagnitudeMeters > 0, maximumPositionMagnitudeMeters <= 100,
                  maximumSingleVertexCorrectionMeters.isFinite,
                  maximumSingleVertexCorrectionMeters > 0,
                  maximumSingleVertexCorrectionMeters <= 2*maximumPositionMagnitudeMeters else {
                throw LimiterError.invalid("纸样应变约束的限值、坐标范围或预算无效。")
            }
            guard vertexCount > 0, !springs.isEmpty else {
                throw LimiterError.invalid("纸样应变约束需要非空的原始结构边图。")
            }
            guard vertexCount <= maximumVertices, springs.count <= maximumConstraints else {
                throw LimiterError.budgetExceeded("纸样应变约束超过顶点或结构边预算。")
            }
            // These are normalized, dimensionless solver weights. The upper
            // bound also keeps all length*weight sums finite during a pass.
            guard normalizedInverseMass.count == vertexCount,
                  normalizedInverseMass.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1e12 }) else {
                throw LimiterError.invalid("纸样应变约束收到无效的归一化逆质量。")
            }
            var seen = Set<UInt64>(), prepared: [Constraint] = []
            prepared.reserveCapacity(springs.count)
            for spring in springs {
                guard (0..<vertexCount).contains(spring.a), (0..<vertexCount).contains(spring.b),
                      spring.a != spring.b, spring.length.isFinite, spring.length > 1e-12,
                      spring.length <= 2*maximumPositionMagnitudeMeters else {
                    throw LimiterError.invalid("纸样应变约束含越界、退化或非有限的原始结构边。")
                }
                let key=(UInt64(min(spring.a,spring.b))<<32)|UInt64(max(spring.a,spring.b))
                guard seen.insert(key).inserted else {
                    throw LimiterError.invalid("纸样应变约束不能重复同一条原始结构边。")
                }
                let a=normalizedInverseMass[spring.a], b=normalizedInverseMass[spring.b]
                prepared.append(.init(a:spring.a,b:spring.b,
                    minimumLength:spring.length*(1-maximumAbsoluteStrain),
                    maximumLength:spring.length*(1+maximumAbsoluteStrain),
                    weightA:a,weightB:b,weightSum:a+b))
            }
            self.vertexCount=vertexCount
            self.maximumAbsoluteStrain=maximumAbsoluteStrain
            self.maximumSingleVertexCorrectionMeters=maximumSingleVertexCorrectionMeters
            self.maximumPositionMagnitudeMeters=maximumPositionMagnitudeMeters
            constraints=prepared
        }

        /// A pass is transactional on cancellation or invalid coordinates.
        /// Collapsed edges have no trustworthy direction and remain explicit
        /// unresolved constraints; fixed particles never move.
        func project(positions: inout [Vector3], reverseOrder: Bool = false,
                     isCancelled: @Sendable () -> Bool = { false }) throws -> Statistics {
            if isCancelled() { throw CancellationError() }
            func valid(_ values: [Vector3]) -> Bool {
                values.count == vertexCount && values.allSatisfy {
                    $0.isFinite && $0.length <= maximumPositionMagnitudeMeters
                }
            }
            guard valid(positions) else {
                throw LimiterError.invalid("纸样应变投影的坐标数量、有限性或范围无效。")
            }
            var result=positions, statistics=Statistics()
            for ordinal in constraints.indices {
                if ordinal%64 == 0 && isCancelled() { throw CancellationError() }
                let index=reverseOrder ? constraints.count-1-ordinal : ordinal
                let edge=constraints[index], delta=result[edge.a]-result[edge.b], length=delta.length
                statistics.examinedConstraints += 1
                if length <= 1e-12 {
                    statistics.collapsedConstraints += 1
                    if edge.weightSum == 0 { statistics.unresolvedPinnedConstraints += 1 }
                    continue
                }
                let target=max(edge.minimumLength,min(edge.maximumLength,length))
                guard target != length else { continue }
                guard edge.weightSum > 0 else {
                    statistics.unresolvedPinnedConstraints += 1
                    continue
                }
                // The cap applies to the largest actual vertex displacement,
                // preserving the inverse-mass correction ratio even near pins.
                let largest=abs(target-length)*(max(edge.weightA,edge.weightB)/edge.weightSum)
                let scale: Double
                if largest > maximumSingleVertexCorrectionMeters {
                    scale=maximumSingleVertexCorrectionMeters/largest
                    statistics.cappedCorrections += 1
                } else { scale=1 }
                let amount=(target-length)/(length*edge.weightSum)
                let a:Vector3, b:Vector3
                if amount.isFinite {
                    let correction=delta*amount*scale
                    a=correction*edge.weightA; b=correction*edge.weightB
                } else {
                    // Extremely small but finite normalized weights must not
                    // turn an otherwise bounded correction into infinity.
                    let correction=delta*((target-length)/length)*scale
                    a=correction*(edge.weightA/edge.weightSum)
                    b=correction*(edge.weightB/edge.weightSum)
                }
                result[edge.a]=result[edge.a]+a
                result[edge.b]=result[edge.b]-b
                statistics.projectedConstraints += 1
                statistics.maximumSingleVertexCorrectionMeters=max(statistics.maximumSingleVertexCorrectionMeters,max(a.length,b.length))
            }
            if isCancelled() { throw CancellationError() }
            guard valid(result) else {
                throw LimiterError.invalid("纸样应变投影产生超出范围或非有限的坐标。")
            }
            positions=result
            return statistics
        }
    }

    nonisolated struct SeamPair: Codable, Sendable {
        let a: Int
        let b: Int
    }

    nonisolated struct ProxyBody: Sendable {
        /// Descending Y / circumference profile of a circular collision tube.
        /// Circular sections are a controlled test fixture, not body shape
        /// inferred from a handful of measurements.
        let levels: [Double]
        let circumferences: [Double]
        static let aspect = 1.0

        static func axes(circumference: Double) -> (Double, Double) {
            let a = aspect, b = 1.0
            let h = pow((a-b)/(a+b), 2)
            let unitPerimeter = Double.pi*(a+b)*(1+3*h/(10+sqrt(4-3*h)))
            return (a*circumference/unitPerimeter, b*circumference/unitPerimeter)
        }

        func axes(at y: Double) -> (Double, Double)? {
            guard y <= levels[0], y >= levels[levels.count-1] else { return nil }
            for i in 0..<(levels.count-1) where y <= levels[i] && y >= levels[i+1] {
                let t = (levels[i]-y)/(levels[i]-levels[i+1])
                return Self.axes(circumference: circumferences[i]*(1-t)+circumferences[i+1]*t)
            }
            return nil
        }

        func penetration(_ p: Vector3) -> Double {
            guard let (a,b) = axes(at: p.y) else { return 0 }
            let radius = hypot(p.x/a, p.z/b)
            return max(0, (1-radius)*min(a,b))
        }

        func project(_ p: Vector3, thickness: Double) -> Vector3 {
            guard let (a,b) = axes(at: p.y) else { return p }
            let aa = a+thickness, bb = b+thickness
            let radius = hypot(p.x/aa, p.z/bb)
            guard radius < 1 else { return p }
            if radius < 1e-10 { return .init(x: aa, y: p.y, z: 0) }
            return .init(x: p.x/radius, y: p.y, z: p.z/radius)
        }
    }

    nonisolated enum DrapeError: LocalizedError, Sendable {
        case unsupported(String)
        case invalid(String)
        case unstable

        var errorDescription: String? {
            switch self {
            case let .unsupported(message): return message
            case let .invalid(message): return message
            case .unstable: return "布料计算未能保持稳定，请调整裙装参数后重试；没有生成可信的成衣结果。"
            }
        }
    }

    /// Extract all actor-isolated existing model data before moving the
    /// numerical work to a background task.
    static func prepare(document: GarmentCodePatternFile,
                        body: GarmentCodeBodyParameters,
                        settings: Settings = .init()) throws -> Input {
        try document.validateForPreview()
        let panels = try document.geometryPanels()
        guard Set(panels.keys) == Set(["skirt_front", "skirt_back"]),
              document.pattern.stitches.count == 2 else {
            throw DrapeError.unsupported("本轮 3D 实验仅支持无腰头、无开衩的双片对称圆裙。请选择圆裙，并关闭其他上衣、腰头及切口组件。")
        }
        guard settings.targetEdgeMeters.isFinite,
              (0.025...0.06).contains(settings.targetEdgeMeters),
              (60...2400).contains(settings.maximumSteps),
              (4...32).contains(settings.solverIterations) else {
            throw DrapeError.invalid("3D 网格或求解预算超出实验范围。")
        }
        guard let waistCm = body["waist"], let hipsCm = body["hips"],
              let hipLineCm = body["hips_line"], let heightCm = body["height"],
              body.values.values.allSatisfy(\.isFinite),
              [waistCm, hipsCm, hipLineCm, heightCm].allSatisfy({ $0.isFinite && $0 > 0 }),
              (30...200).contains(waistCm), (40...220).contains(hipsCm),
              hipsCm >= waistCm, (5...45).contains(hipLineCm), (100...240).contains(heightCm) else {
            throw DrapeError.invalid("3D 实验需要有效的腰围、臀围、腰臀高和身高；当前简化人台要求臀围不小于腰围。")
        }

        struct Sector {
            let name: String
            let panel: GarmentCodePanelGeometry
            let topIndex: Int
            let hemIndex: Int
            let top: GarmentCodeGeometryEdge
            let hem: GarmentCodeGeometryEdge
            let reverseHem: Bool
            let angle: Double
            let length: Double
        }
        func sector(_ name: String) throws -> Sector {
            guard let panel = panels[name], panel.edges.count == 4 else {
                throw DrapeError.unsupported("3D 实验暂不支持圆裙开衩、切口或附加裁片。")
            }
            let arcs = panel.edges.indices.filter { panel.edges[$0].curvature?.circle != nil }
            let lines = panel.edges.indices.filter { panel.edges[$0].curvature == nil }
            guard arcs.count == 2, lines.count == 2,
                  let topI = arcs.min(by: { panel.edges[$0].curvature!.circle!.radius < panel.edges[$1].curvature!.circle!.radius }),
                  let hemI = arcs.first(where: { $0 != topI }) else {
                throw DrapeError.unsupported("3D 实验需要两条同心圆弧和两条径向直线构成的标准圆裙裁片。")
            }
            let top = panel.edges[topI], hem = panel.edges[hemI]
            let topR = top.curvature!.circle!.radius, hemR = hem.curvature!.circle!.radius
            let length = hemR-topR
            let angle = top.length()/topR
            let reverseHem = top.start.distance(to: hem.end) < top.start.distance(to: hem.start)
            guard length >= 5, length <= 150, topR > 0,
                  angle.isFinite, angle >= 0.1*Double.pi-1e-6, angle <= Double.pi+1e-6,
                  abs(hem.length()/hemR-angle) < 1e-5,
                  lines.allSatisfy({ abs(panel.edges[$0].length()-length) < 0.001 }) else {
                throw DrapeError.unsupported("该圆裙超出当前 3D 实验范围。裙长需为 5～150 cm，圆裙圆周倍数暂支持 0.1～1；超过一整圆的褶量尚未验证。")
            }
            for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
                guard abs(top.point(at: t).distance(to: hem.point(at: reverseHem ? 1-t : t))-length) < 0.001 else {
                    throw DrapeError.unsupported("内外圆弧不是可对应的同心圆裙边界，不能可靠生成 3D 网格。")
                }
            }
            return .init(name: name, panel: panel, topIndex: topI, hemIndex: hemI,
                         top: top, hem: hem, reverseHem: reverseHem, angle: angle, length: length)
        }
        let sectors = try [sector("skirt_front"), sector("skirt_back")]
        guard abs(sectors[0].top.length()-sectors[1].top.length()) < 0.001,
              abs(sectors[0].hem.length()-sectors[1].hem.length()) < 0.001,
              abs(sectors[0].length-sectors[1].length) < 0.001 else {
            throw DrapeError.unsupported("当前 3D 实验只支持前后片相同的对称圆裙。")
        }
        let waist = sectors.reduce(0) { $0+$1.top.length()/100 }
        let hem = sectors.reduce(0) { $0+$1.hem.length()/100 }
        let length = sectors[0].length/100
        let waistBody = waistCm/100, hipsBody = hipsCm/100, hipLine = hipLineCm/100
        guard waist >= waistBody-0.002, waist <= hipsBody+0.002 else {
            throw DrapeError.invalid("纸样腰口与当前量体数据不匹配。请用当前人体尺寸重新生成圆裙，再打开 3D 实验。")
        }
        let n = min(100, max(24, Int(ceil((hem/2)/settings.targetEdgeMeters))))
        let rows = min(45, max(5, Int(ceil(length/settings.targetEdgeMeters))))
        guard 2*(n+1)*(rows+1) <= 8000 else { throw DrapeError.invalid("圆裙网格超过本轮离线实验预算。") }
        let panelStride = (n+1)*(rows+1)
        var flat: [Vector3] = []
        var edgeVertices: [String: [Int]] = [:]
        var unmergedTriangles: [UInt32] = []
        var structural: [(Int,Int,Double,Bool)] = []
        var bend: [(Int,Int,Double)] = []
        for (panelIndex, sector) in sectors.enumerated() {
            let offset = panelIndex*panelStride
            func index(_ r: Int, _ c: Int) -> Int { offset+r*(n+1)+c }
            for r in 0...rows {
                let v = Double(r)/Double(rows)
                for c in 0...n {
                    let u = Double(c)/Double(n)
                    let a = sector.top.point(at: u)
                    let b = sector.hem.point(at: sector.reverseHem ? 1-u : u)
                    let p = a*(1-v)+b*v
                    flat.append(.init(x: p.x/100, y: p.y/100, z: 0))
                }
            }
            for r in 0..<rows {
                for c in 0..<n {
                    let a=index(r,c), b=index(r,c+1), cc=index(r+1,c), d=index(r+1,c+1)
                    unmergedTriangles += [UInt32(a),UInt32(b),UInt32(cc),UInt32(b),UInt32(d),UInt32(cc)]
                }
            }
            for r in 0...rows {
                for c in 0...n {
                    let a=index(r,c)
                    for (rr,cc) in [(r+1,c),(r,c+1),(r+1,c+1),(r+1,c-1)] where rr <= rows && cc >= 0 && cc <= n {
                        // In surface-contact mode, each real triangle edge
                        // carries the metric and its diagonal remains a hinge.
                        // Retain the older cross-braced graph only for controls.
                        if settings.useBodySurfaceCollision && rr == r+1 && cc == c+1 { continue }
                        let b=index(rr,cc)
                        structural.append((a,b,(flat[a]-flat[b]).length,rr != r && cc != c))
                    }
                    for (rr,cc) in [(r+2,c),(r,c+2)] where rr <= rows && cc <= n {
                        let b=index(rr,cc)
                        bend.append((a,b,(flat[a]-flat[b]).length))
                    }
                }
            }
            for e in sector.panel.edges.indices {
                let edge = sector.panel.edges[e]
                let candidates: [[Int]] = [
                    (0...n).map { index(0,$0) }, (0...n).map { index(rows,$0) },
                    (0...rows).map { index($0,0) }, (0...rows).map { index($0,n) }
                ]
                let start = Vector3(x: edge.start.x/100,y: edge.start.y/100,z:0)
                let end = Vector3(x: edge.end.x/100,y: edge.end.y/100,z:0)
                guard let match = candidates.first(where: { path in
                    let a=flat[path[0]], b=flat[path[path.count-1]]
                    return ((a-start).length < 1e-5 && (b-end).length < 1e-5) ||
                        ((a-end).length < 1e-5 && (b-start).length < 1e-5)
                }) else { throw DrapeError.invalid("裁片边到 3D 网格的映射失败。") }
                edgeVertices["\(sector.name):\(e)"] = (flat[match[0]]-start).length < 1e-5 ? match : match.reversed()
            }
        }
        // Union seam particles, retaining all panel-local spring rest lengths.
        // Welding the flat reference coordinates themselves would corrupt the
        // pattern metric; referencePositions intentionally remain duplicated.
        var parent = Array(flat.indices)
        func find(_ i: Int) -> Int {
            var a=i
            while parent[a] != a { a=parent[a] }
            return a
        }
        var originalSeams: [[Int]] = [], originalPairs: [(Int,Int)] = []
        var referenced = Set<String>()
        for stitch in document.pattern.stitches {
            guard stitch.sides.count == 2, !stitch.rightWrong else {
                throw DrapeError.unsupported("当前 3D 实验只支持普通双边侧缝。")
            }
            let keys = stitch.sides.map { "\($0.panel):\($0.edge)" }
            guard keys[0] != keys[1], keys.allSatisfy({ referenced.insert($0).inserted }),
                  let a=edgeVertices[keys[0]], let bb=edgeVertices[keys[1]],
                  a.count == rows+1, bb.count == a.count,
                  stitch.sides[0].panel != stitch.sides[1].panel else {
                throw DrapeError.unsupported("侧缝关系与双片圆裙不一致，不能可靠缝合。")
            }
            let b=Array(bb.reversed())
            for (i,j) in zip(a,b) {
                parent[find(j)] = find(i)
                originalPairs.append((i,j))
            }
            originalSeams.append(a)
        }
        var roots: [Int:Int] = [:], mapping: [Int] = []
        for i in flat.indices {
            let root=find(i)
            if roots[root] == nil { roots[root]=roots.count }
            mapping.append(roots[root]!)
        }
        guard roots.count == 2*n*(rows+1),
              Set((0...n).map { mapping[$0] }).intersection(Set((0...n).map { mapping[panelStride+$0] })).count == 2 else {
            throw DrapeError.invalid("接缝没有形成一致的圆裙环状拓扑。")
        }
        let backForward = mapping[n] == mapping[panelStride]
        // Reject a twisted seam instead of quietly choosing a convenient
        // placement that ignores the imported stitching relationship.
        for r in 0...rows {
            guard mapping[r*(n+1)] == mapping[panelStride+r*(n+1)+(backForward ? n : 0)],
                  mapping[r*(n+1)+n] == mapping[panelStride+r*(n+1)+(backForward ? 0 : n)] else {
                throw DrapeError.invalid("侧缝把腰口与下摆交叉连接，当前实验拒绝扭转装配。")
            }
        }
        func springs(_ records: [(Int,Int,Double,Bool)]) throws -> [Spring] {
            var unique: [String:Spring] = [:]
            for (i,j,rest,isShear) in records {
                let a=min(mapping[i],mapping[j]), b=max(mapping[i],mapping[j])
                guard a != b, rest.isFinite, rest > 1e-8 else { throw DrapeError.invalid("3D 网格存在退化约束。") }
                let key="\(a):\(b)"
                if let previous=unique[key], abs(previous.length-rest) > 0.00002 {
                    throw DrapeError.invalid("配对侧缝的参考长度不同，当前实验不支持吃势或抽褶。")
                }
                unique[key] = .init(a:a,b:b,length:rest,isShear:isShear)
            }
            return unique.values.sorted { $0.a == $1.a ? $0.b < $1.b : $0.a < $1.a }
        }
        let topBelowWaist = hipsBody-waistBody > 1e-5
            ? hipLine*min(1,max(0,(waist-waistBody)/(hipsBody-waistBody))) : 0
        let proxy = ProxyBody(
            levels:[topBelowWaist+0.30,topBelowWaist+0.14,topBelowWaist,
                    topBelowWaist-hipLine,topBelowWaist-hipLine-0.14,topBelowWaist-hipLine-0.80],
            circumferences:[min(1.5, max(waistBody*1.15,(body["bust"] ?? waistCm*1.2)/100)),
                            waistBody*1.08,waistBody,hipsBody,hipsBody*0.83,hipsBody*0.48])
        let standard: GarmentCodeStandardBody.Snapshot?
        if settings.bodyMode == .standardMannequin {
            guard abs(waist-waistBody) < 0.002 else {
                throw DrapeError.unsupported("标准人体试验目前仅支持自然腰位圆裙，请在高级参数中将圆裙腰位比例设为 1；其他腰位可使用参考圆台对照。")
            }
            standard = try GarmentCodeStandardBody.load(body: body, resourceDirectory: settings.bodyResourceDirectory)
        } else { standard = nil }
        let supportPoints: [Vector3]
        var supportArcLengths = [0.0]
        if let standard, settings.useBodySurfaceCollision {
            supportPoints = (0..<1024).map {
                standard.project(standard.waistPoint(arcFraction:Double($0)/1024), thickness:0.005)
            }
            for i in supportPoints.indices {
                supportArcLengths.append(supportArcLengths.last! +
                    (supportPoints[(i+1)%supportPoints.count]-supportPoints[i]).length)
            }
        } else { supportPoints = [] }
        func supportedWaistPoint(_ fraction: Double, body: GarmentCodeStandardBody.Snapshot) -> Vector3 {
            guard !supportPoints.isEmpty else { return body.waistPoint(arcFraction:fraction) }
            // Reparameterize the offset contour itself. Equal arc samples of
            // the skin cease to be equal arc samples after normal projection.
            let target=(fraction-floor(fraction))*supportArcLengths.last!
            var low=0,high=supportPoints.count
            while high-low>1 {
                let mid=(low+high)/2
                if supportArcLengths[mid]<target {low=mid} else {high=mid}
            }
            let t=(target-supportArcLengths[low])/max(1e-12,supportArcLengths[low+1]-supportArcLengths[low])
            return supportPoints[low]*(1-t)+supportPoints[(low+1)%supportPoints.count]*t
        }
        let (waistA,waistB)=ProxyBody.axes(circumference:waist)
        // Invert an ellipse arc-length table, so equal source waist intervals
        // are not stretched merely by the elliptical mannequin convention.
        let tableCount=2048
        var arcTable=[0.0]
        var last=Vector3(x:waistA,y:0,z:0)
        for k in 1...tableCount {
            let theta=2*Double.pi*Double(k)/Double(tableCount)
            let p=Vector3(x:waistA*cos(theta),y:0,z:waistB*sin(theta))
            arcTable.append(arcTable.last!+(p-last).length)
            last=p
        }
        func ellipseAngle(_ fraction: Double) -> Double {
            let distance=fraction*arcTable.last!
            var lo=0, hi=tableCount
            while hi-lo > 1 {
                let mid=(lo+hi)/2
                if arcTable[mid] < distance { lo=mid } else { hi=mid }
            }
            let f=(distance-arcTable[lo])/max(1e-12,arcTable[hi]-arcTable[lo])
            return 2*Double.pi*(Double(lo)+f)/Double(tableCount)
        }
        let suns=sectors[0].angle/Double.pi
        var initial=Array(repeating:Vector3.zero,count:roots.count)
        var pinned=Array(repeating:false,count:roots.count)
        for panelIndex in 0..<2 {
            for r in 0...rows {
                let s=length*Double(r)/Double(rows)
                for c in 0...n {
                    let fraction: Double
                    if panelIndex == 0 { fraction=0.5*Double(c)/Double(n) }
                    else { fraction=backForward ? 0.5+0.5*Double(c)/Double(n) : 1-0.5*Double(c)/Double(n) }
                    let theta=ellipseAngle(fraction)
                    let index=mapping[panelIndex*panelStride+r*(n+1)+c]
                    // Circular sections admit an isometric cone (a horizontal
                    // annulus at one sun). A tiny deterministic perturbation
                    // breaks perfect rotational symmetry for the gravity solve.
                    let slope=min(1,suns)
                    let radial=s*slope
                    let seed=s*0.012*sin(8*theta)
                    initial[index] = .init(x:(waistA+radial)*cos(theta),
                                         y:-s*sqrt(max(0,1-slope*slope))+seed,
                                         z:(waistB+radial)*sin(theta))
                    if let standard {
                        let anchor = supportedWaistPoint(fraction, body: standard)
                        let radialDirection = Vector3(x: cos(theta), y: 0, z: sin(theta))
                        initial[index] = anchor + radialDirection*radial + Vector3(x: 0, y: -s*sqrt(max(0,1-slope*slope))+seed, z: 0)
                        if r > 0 { initial[index] = standard.project(initial[index], thickness: 0.0025) }
                    }
                    // The controlled experiment uses a full waist support hoop.
                    // Suns > 1 cannot fit this hoop isometrically and are
                    // rejected above rather than silently adding gathers.
                    if r == 0 { pinned[index]=true }
                }
            }
        }
        var triangles: [UInt32] = []
        for (t,offset) in stride(from:0,to:unmergedTriangles.count,by:3).enumerated() {
            var ids=[mapping[Int(unmergedTriangles[offset])],mapping[Int(unmergedTriangles[offset+1])],mapping[Int(unmergedTriangles[offset+2])]]
            let panelIndex=t/(2*n*rows)
            if panelIndex == 1 && !backForward { ids.swapAt(1,2) }
            triangles += ids.map(UInt32.init)
        }
        var area=0.0
        for t in stride(from:0,to:unmergedTriangles.count,by:3) {
            let a=flat[Int(unmergedTriangles[t])], b=flat[Int(unmergedTriangles[t+1])], c=flat[Int(unmergedTriangles[t+2])]
            area += (b-a).cross(c-a).length/2
        }
        let mannequin = standard.map { ($0.positions, $0.triangleIndices) } ?? proxyMesh(proxy)
        var result = Input(positions:initial,triangleIndices:triangles,referencePositions:flat,
                     referenceTriangles:unmergedTriangles,referenceToSimulation:mapping,
                     panelColumns:n,radialSegments:rows,
                     seamPaths:originalSeams.map { $0.map { mapping[$0] } },
                     seamVertexPairs:originalPairs.map { .init(a:mapping[$0.0],b:mapping[$0.1]) },pinned:pinned,
                     springs:try springs(structural),bendingSprings:try springs(bend.map { ($0.0,$0.1,$0.2,false) }),body:proxy,
                     mannequinPositions:mannequin.0,mannequinTriangleIndices:mannequin.1,
                     waistCircumferenceMeters:waist,hemCircumferenceMeters:hem,
                     radialLengthMeters:length,referenceAreaSquareMeters:area,settings:settings)
        result.standardBody = standard
        if settings.useSurfaceCollision {
            result.surfaceTopology = try GarmentCodeClothContact.Topology(vertexCount: initial.count, triangleIndices: triangles)
        }
        if let material = settings.material {
            let parameters = material.parameters
            try parameters.validate()
            let masses = try GarmentCodeClothMaterial.lumpedMasses(
                referencePositions: flat.map { SIMD3<Double>($0.x,$0.y,$0.z) }, triangleIndices: unmergedTriangles,
                referenceToSimulation: mapping, simulationVertexCount: initial.count,
                arealDensity: parameters.arealDensityKgPerSquareMeter)
            result.inverseMasses = masses.normalizedInverseMasses.enumerated().map { pinned[$0.offset] ? 0 : $0.element }
            result.meanParticleMassKg = masses.meanMassKg
            result.totalFabricMassKg = masses.totalMassKg
        }
        try attachBodySurfaceContact(to: &result)
        return result
    }

    nonisolated static func attachBodySurfaceContact(to input: inout Input) throws {
        guard input.settings.useBodySurfaceCollision else { return }
        guard input.settings.bodySurfaceClearanceMeters.isFinite,
              (0.0001...0.005).contains(input.settings.bodySurfaceClearanceMeters) else {
            throw DrapeError.invalid("人体面接触间距超出数值试验范围。")
        }
        if let fitted=input.fittedBodySurface {
            guard input.standardBody==nil,input.fixedBodySurface==nil,
                  input.settings.bodyShapeSelection == .surfaceMeasurements,
                  input.settings.bodyPoseSelection == .matchPatternReference else {throw DrapeError.invalid("拟合人体必须使用独立的同源表面，不能携带旧人体或逆SDF。")}
            try fitted.verify(positions:input.mannequinPositions,triangleIndices:input.mannequinTriangleIndices,
                              bodyValues:fitted.bodyValues,requirePatternReference:true)
            input.bodySurfaceMesh=fitted.mesh
            return
        }
        guard input.settings.bodyShapeSelection == .scaledTemplate else {throw DrapeError.invalid("拟合人体缺少完整表面验证回执。")}
        if let fixed=input.fixedBodySurface {
            guard input.standardBody==nil,input.settings.bodyPoseSelection == .matchPatternReference else {throw DrapeError.invalid("摆姿人体不能携带旧逆SDF。")}
            try fixed.verify(positions:input.mannequinPositions,triangleIndices:input.mannequinTriangleIndices)
            input.bodySurfaceMesh=fixed.mesh
            return
        }
        guard let body = input.standardBody else {
            throw DrapeError.unsupported("人体面接触目前需要标准人体，请选择标准人体模式。")
        }
        input.bodySurfaceMesh = try GarmentCodeBodySurfaceContact.BodyMesh(
            positions: body.positions, triangleIndices: body.triangleIndices,
            signedDistance: { body.signedDistance($0) })
    }

    nonisolated private static func proxyMesh(_ body: ProxyBody) -> ([Vector3],[UInt32]) {
        let columns=64, rows=48
        var vertices:[Vector3]=[], triangles:[UInt32]=[]
        for r in 0...rows {
            let y=body.levels[0]+(body.levels.last!-body.levels[0])*Double(r)/Double(rows)
            let (a,b)=body.axes(at:y) ?? ProxyBody.axes(circumference:body.circumferences.last!)
            for c in 0..<columns {
                let theta=2*Double.pi*Double(c)/Double(columns)
                vertices.append(.init(x:a*cos(theta),y:y,z:b*sin(theta)))
            }
        }
        for r in 0..<rows {
            for c in 0..<columns {
                let a=UInt32(r*columns+c), b=UInt32(r*columns+(c+1)%columns)
                let cc=a+UInt32(columns), d=b+UInt32(columns)
                triangles += [a,b,cc,b,d,cc]
            }
        }
        return (vertices,triangles)
    }

    /// XPBD-style distance projection with normalized particle masses. Material
    /// constants are numerical defaults, not measurements of a real fabric.
    /// Two-hop distances approximate bend resistance. Vertex self-collision
    /// cannot prevent every edge/triangle intersection and is disclosed below.
    nonisolated static func simulate(input: Input,
                                      isCancelled: @Sendable () -> Bool = { false },
                                      progress: @Sendable (Double) -> Void = { _ in }) throws -> Output {
        if isCancelled() { throw CancellationError() }
        guard input.fixedBodySurface==nil,input.fittedBodySurface==nil,
              input.settings.bodyPoseSelection == .legacyTemplate,input.settings.bodyShapeSelection == .scaledTemplate else {throw DrapeError.unsupported("摆臂或拟合人体只支持联合求解器；旧投影器不能使用旧SDF或参考圆台代替。")}
        let started=Date()
        let dt=1.0/120, thickness=0.0025
        var positions=input.positions, previous=positions
        var velocities=Array(repeating:Vector3.zero,count:positions.count)
        let weights = input.inverseMasses.isEmpty ? input.pinned.map { $0 ? 0.0 : 1.0 } : input.inverseMasses
        let sourceLimiter: SourceStrainLimiter?
        if let limit=input.settings.sourceStrainLimit {
            guard (1...120).contains(input.settings.sourceStrainLimitPasses) else {
                throw DrapeError.invalid("应变限制的迭代预算无效。")
            }
            sourceLimiter=try SourceStrainLimiter(vertexCount:positions.count,springs:input.springs,
                normalizedInverseMass:weights,maximumAbsoluteStrain:limit)
        } else { sourceLimiter=nil }
        let bodyContactTopology: GarmentCodeClothContact.Topology?
        if input.bodySurfaceMesh != nil {
            bodyContactTopology = try input.surfaceTopology ?? GarmentCodeClothContact.Topology(
                vertexCount: positions.count, triangleIndices: input.triangleIndices)
        } else { bodyContactTopology = nil }
        let material = input.settings.material?.parameters
        let stretchCompliance = (material?.stretchCompliance ?? 1e-10) * (material == nil ? 1 : input.meanParticleMassKg)
        let shearCompliance = (material?.shearCompliance ?? 1e-10) * (material == nil ? 1 : input.meanParticleMassKg)
        let bendCompliance = (material?.bendDistanceCompliance ?? 0.001) * (material == nil ? 1 : input.meanParticleMassKg)
        let retention = try material?.velocityRetention(timeStep: dt) ?? 0.5
        func bodyProject(_ p: Vector3) -> Vector3 {
            if let body = input.standardBody { return body.project(p, thickness: thickness) }
            return input.body.project(p, thickness: thickness)
        }
        var stretchLambda=Array(repeating:0.0,count:input.springs.count)
        var bendLambda=Array(repeating:0.0,count:input.bendingSprings.count)
        var excluded=Array(repeating:Set<Int>(),count:positions.count)
        for spring in input.springs+input.bendingSprings {
            excluded[spring.a].insert(spring.b)
            excluded[spring.b].insert(spring.a)
        }
        func project(_ springs: [Spring], lambda: inout [Double], compliance: Double, shear: Double? = nil) {
            for (i,s) in springs.enumerated() {
                let alpha = (s.isShear ? (shear ?? compliance) : compliance)/(dt*dt)
                let difference=positions[s.a]-positions[s.b], length=difference.length
                let w=weights[s.a]+weights[s.b]
                guard length > 1e-10, w > 0 else { continue }
                let change=(-(length-s.length)-alpha*lambda[i])/(w+alpha)
                lambda[i] += change
                let direction=difference*(change/length)
                positions[s.a]=positions[s.a]+direction*weights[s.a]
                positions[s.b]=positions[s.b]-direction*weights[s.b]
            }
        }
        struct Cell: Hashable { let x:Int; let y:Int; let z:Int }
        func selfCollide() throws {
            let separation=0.005
            var cells:[Cell:[Int]]=[:]
            for i in positions.indices {
                let p=positions[i]
                // Validate before the Double -> Int hash conversion; a failed
                // numerical step must return an error rather than trap.
                guard p.isFinite, p.length < 5 else { throw DrapeError.unstable }
                let key=Cell(x:Int(floor(p.x/separation)),y:Int(floor(p.y/separation)),z:Int(floor(p.z/separation)))
                for x in -1...1 {
                    for y in -1...1 {
                        for z in -1...1 {
                            guard let neighbors=cells[.init(x:key.x+x,y:key.y+y,z:key.z+z)] else { continue }
                            for j in neighbors where !excluded[i].contains(j) {
                                let delta=positions[i]-positions[j], distance=delta.length
                                let w=weights[i]+weights[j]
                                guard distance < separation, distance > 1e-9, w > 0 else { continue }
                                let correction=delta*((separation-distance)/(distance*w))
                                positions[i]=positions[i]+correction*weights[i]
                                positions[j]=positions[j]-correction*weights[j]
                            }
                        }
                    }
                }
                cells[key,default:[]].append(i)
            }
        }
        var lastSpeed=Double.infinity, consecutiveQuiet=0, completedSteps=0
        progress(0)
        for step in 0..<input.settings.maximumSteps {
            if step%8 == 0 {
                if isCancelled() { throw CancellationError() }
                progress(Double(step)/Double(input.settings.maximumSteps))
            }
            previous=positions
            for i in positions.indices where !input.pinned[i] {
                velocities[i].y -= 9.81*dt
                positions[i]=positions[i]+velocities[i]*dt
            }
            stretchLambda=Array(repeating:0,count:stretchLambda.count)
            bendLambda=Array(repeating:0,count:bendLambda.count)
            for iteration in 0..<input.settings.solverIterations {
                project(input.springs,lambda:&stretchLambda,compliance:stretchCompliance,shear:shearCompliance)
                project(input.bendingSprings,lambda:&bendLambda,compliance:bendCompliance)
                for i in positions.indices where !input.pinned[i] {
                    positions[i]=bodyProject(positions[i])
                }
                if iteration == input.settings.solverIterations-1 {
                    // The contact set must be solved every step. Alternating
                    // self-collision on/off produced a persistent period-two
                    // oscillation around the body surface.
                    if let topology = input.surfaceTopology {
                        _ = try GarmentCodeClothContact.project(positions: &positions, previousPositions: previous,
                            inverseMass: weights, topology: topology, thickness: 0.005, isCancelled: isCancelled)
                    } else { try selfCollide() }
                    for i in positions.indices where !input.pinned[i] {
                        positions[i]=bodyProject(positions[i])
                    }
                }
                // Resolve metric and body-face constraints together. A single
                // post-solve body correction can otherwise reintroduce the
                // same large edge error at the end of every time step.
                if (iteration+1)%8 == 0 || iteration == input.settings.solverIterations-1,
                   let body = input.bodySurfaceMesh, let topology = bodyContactTopology {
                    _ = try GarmentCodeBodySurfaceContact.project(positions: &positions,
                        inverseMass: weights, topology: topology, body: body,
                        thickness: input.settings.bodySurfaceClearanceMeters,
                        previousPositions: previous, isCancelled: isCancelled)
                    for i in positions.indices where !input.pinned[i] {
                        positions[i]=bodyProject(positions[i])
                    }
                }
            }
            if let sourceLimiter {
                // Bound source strain jointly with contact. A hard rest-length
                // solve alone can concentrate an incompatible body correction
                // in one edge even when nearby edges have available strain.
                for pass in 0..<input.settings.sourceStrainLimitPasses {
                    _ = try sourceLimiter.project(positions:&positions,reverseOrder:pass%2 != 0,isCancelled:isCancelled)
                    for i in positions.indices where !input.pinned[i] { positions[i]=bodyProject(positions[i]) }
                    if (pass+1)%8==0 || pass==input.settings.sourceStrainLimitPasses-1 {
                        if let topology=input.surfaceTopology {
                            _ = try GarmentCodeClothContact.project(positions:&positions,previousPositions:previous,
                                inverseMass:weights,topology:topology,thickness:0.005,isCancelled:isCancelled)
                        } else { try selfCollide() }
                        for i in positions.indices where !input.pinned[i] { positions[i]=bodyProject(positions[i]) }
                        if let body=input.bodySurfaceMesh,let topology=bodyContactTopology {
                            _ = try GarmentCodeBodySurfaceContact.project(positions:&positions,inverseMass:weights,
                                topology:topology,body:body,thickness:input.settings.bodySurfaceClearanceMeters,
                                previousPositions:previous,isCancelled:isCancelled)
                            for i in positions.indices where !input.pinned[i] { positions[i]=bodyProject(positions[i]) }
                        }
                    }
                }
            }
            lastSpeed=0
            for i in positions.indices {
                if input.pinned[i] { positions[i]=input.positions[i]; velocities[i] = .zero }
                else {
                    let displacementVelocity=(positions[i]-previous[i])/dt
                    let velocity=displacementVelocity*retention
                    guard velocity.isFinite, positions[i].isFinite, positions[i].length < 5 else { throw DrapeError.unstable }
                    velocities[i]=velocity
                    // Measure actual position changes, not the damped velocity
                    // used to advance the next step.
                    lastSpeed=max(lastSpeed,displacementVelocity.length)
                }
            }
            completedSteps=step+1
            consecutiveQuiet=lastSpeed < 0.025 ? consecutiveQuiet+1 : 0
            if step >= 240 && consecutiveQuiet >= 24 {
                // Quiet motion alone can leave a skirt resting against the
                // hips with unresolved strain. Use the final quality gates
                // here too, so those cases can use the remaining solve budget.
                let lengthsReady = input.springs.allSatisfy {
                    abs((positions[$0.a]-positions[$0.b]).length/$0.length-1) < 0.08
                }
                let bodyReady = lengthsReady && positions.allSatisfy {
                    (input.standardBody?.penetration($0) ?? input.body.penetration($0)) < 0.003
                }
                if bodyReady {
                    var bodyFacesReady = true
                    if let body = input.bodySurfaceMesh, let topology = bodyContactTopology {
                        let quality = try GarmentCodeBodySurfaceContact.inspect(positions: positions,
                            topology: topology, body: body,
                            thickness: input.settings.bodySurfaceClearanceMeters, isCancelled: isCancelled)
                        bodyFacesReady = quality.intersectingTrianglePairs == 0 && quality.degenerateClothTriangles == 0
                    }
                    guard bodyFacesReady else { continue }
                    if let topology = input.surfaceTopology {
                        let quality = try GarmentCodeClothContact.inspect(positions: positions, topology: topology, thickness: 0.005)
                        if quality.intersectingTrianglePairs == 0 && quality.degenerateTriangles == 0 { break }
                    } else { break }
                }
            }
        }
        if isCancelled() { throw CancellationError() }
        let strains=input.springs.map { abs((positions[$0.a]-positions[$0.b]).length/$0.length-1) }
        let maxStrain=strains.max() ?? 0
        guard maxStrain.isFinite, maxStrain < 0.40 else { throw DrapeError.unstable }
        let penetration=positions.map { input.standardBody?.penetration($0) ?? input.body.penetration($0) }.max() ?? 0
        // Both sides are the same simulation DOF after union, so this is an
        // exact topological guarantee, not an estimated geometric tolerance.
        let seamGap=input.seamVertexPairs.map { (positions[$0.a]-positions[$0.b]).length }.max() ?? 0
        let surfaceQuality: GarmentCodeClothContact.Quality?
        if let topology = input.surfaceTopology {
            surfaceQuality = try GarmentCodeClothContact.inspect(positions: positions, topology: topology, thickness: 0.005)
        } else { surfaceQuality = nil }
        let bodySurfaceQuality: GarmentCodeBodySurfaceContact.Quality?
        if let body = input.bodySurfaceMesh, let topology = bodyContactTopology {
            bodySurfaceQuality = try GarmentCodeBodySurfaceContact.inspect(positions: positions,
                topology: topology, body: body,
                thickness: input.settings.bodySurfaceClearanceMeters, isCancelled: isCancelled)
        } else { bodySurfaceQuality = nil }
        let converged=consecutiveQuiet >= 24 && maxStrain < 0.08 && penetration < 0.003
            && (surfaceQuality?.intersectingTrianglePairs ?? 0) == 0
            && (surfaceQuality?.degenerateTriangles ?? 0) == 0
            && (bodySurfaceQuality?.intersectingTrianglePairs ?? 0) == 0
            && (bodySurfaceQuality?.degenerateClothTriangles ?? 0) == 0
        var warnings=["面料是数值实验预设，尚无样布拉伸、弯曲或摩擦实测标定；不能用于判断个人合体度。",
                      input.standardBody == nil
                        ? "人台是圆形截面参考碰撞体，腰口用支撑环固定。"
                        : "人台来自标准人体网格并按围度近似缩放，保留腰腹臀腿轮廓；不是个人体型还原。",
                      input.surfaceTopology == nil
                        ? "参考模式只处理顶点自碰撞，不保证消除边或三角面穿插。"
                        : "表面碰撞检查顶点与三角面、边与边及末态三角面交叉；尚不是连续碰撞保证。",
                      input.bodySurfaceMesh == nil
                        ? "弯曲仍用二阶距离近似；人体接触的质量指标仅检查布片顶点，不能证明所有面片完全没有穿体。"
                        : "弯曲仍用二阶距离近似；人体接触另检查布片与可见人体的三角面交叉，仍非连续碰撞或实物合体验证。"]
        if input.bodySurfaceMesh != nil {
            if input.garmentStyle == "StraightWB" || input.garmentStyle == "FittedWB" {
                warnings.append("腰头顶口采用数值固定支撑，支撑间距不代表纸样新增松量；尚未与裙身、裤身或扣合部件缝合。")
            } else {
                warnings.append("腰口保留数值辅助支撑间距；它不代表原纸样增加了腰部松量，也不是已缝制腰头的效果。")
            }
        }
        if !converged { warnings.insert("本次未达到收敛门槛，结果仅供检查装配；请勿作为最终垂坠效果。",at:0) }
        warnings += input.preparationWarnings
        if let sourceLimiter {
            warnings.append("使用 \(Int(sourceLimiter.maximumAbsoluteStrain*100))% 的实验性应变限制目标；接触修正后仍按实际边长独立检查，目标不是实测面料拉伸上限。")
        }
        var diagnostics=Diagnostics(vertexCount:positions.count,triangleCount:input.triangleIndices.count/3,
                                    simulatedSeconds:Double(completedSteps)*dt,computationSeconds:Date().timeIntervalSince(started),
                                    maxEdgeStrain:maxStrain,meanEdgeStrain:strains.reduce(0,+)/Double(max(1,strains.count)),
                                    maxSpeedMetersPerSecond:lastSpeed,maxBodyPenetrationMeters:penetration,
                                    maxSeamGapMeters:seamGap,waistCircumferenceMeters:input.waistCircumferenceMeters,
                                    hemCircumferenceMeters:input.hemCircumferenceMeters,radialLengthMeters:input.radialLengthMeters,
                                    referenceAreaSquareMeters:input.referenceAreaSquareMeters,converged:converged,warnings:warnings)
        diagnostics.bodyModel = input.standardBody?.profileName ?? "参考圆台"
        diagnostics.materialName = input.settings.material?.title ?? "原验证材料"
        diagnostics.totalFabricMassKg = input.totalFabricMassKg
        diagnostics.surfaceIntersectionCount = surfaceQuality?.intersectingTrianglePairs
        diagnostics.closeSurfacePairCount = surfaceQuality?.closeSurfacePairs
        diagnostics.garmentStyle = input.garmentStyle
        diagnostics.patternLengthLabel = input.patternLengthLabel
        diagnostics.patternLengthMeters = input.radialLengthMeters
        diagnostics.waistGatherRatio = input.waistGatherRatio
        diagnostics.supportWaistCircumferenceMeters = input.standardBody?.waistCircumferenceMeters
            ?? input.waistCircumferenceMeters / max(1,input.waistGatherRatio)
        diagnostics.bodySurfaceIntersectionCount = bodySurfaceQuality?.intersectingTrianglePairs
        diagnostics.bodySurfaceCandidatePairCount = bodySurfaceQuality?.candidateTrianglePairs
        diagnostics.maxBodySurfacePlaneOverlapMeters = bodySurfaceQuality?.maximumPlaneOverlapMeters
        if input.bodySurfaceMesh != nil {
            diagnostics.bodySurfaceClearanceMeters = input.settings.bodySurfaceClearanceMeters
            diagnostics.waistSupportClearanceMeters = 0.005
        }
        if let sourceLimiter {
            diagnostics.sourceStrainLimitFraction=sourceLimiter.maximumAbsoluteStrain
            diagnostics.sourceStrainLimitPassCount=input.settings.sourceStrainLimitPasses
        }
        progress(1)
        return .init(positions:positions,triangleIndices:input.triangleIndices,
                     mannequinPositions:input.mannequinPositions,mannequinTriangleIndices:input.mannequinTriangleIndices,
                     seamPaths:input.seamPaths,seamVertexPairs:input.seamVertexPairs,diagnostics:diagnostics)
    }
}
