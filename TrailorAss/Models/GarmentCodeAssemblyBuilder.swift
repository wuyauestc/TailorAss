import Foundation

/// Shared assembly mechanics for every garment family. A layout supplies
/// placements and explicit sewing intent; this layer preserves each paper
/// panel and delegates acceptance to the complete-source validation factory.
@MainActor
enum GarmentCodeAssemblyBuilder {
    typealias Kernel = GarmentCodeCircleDrape
    typealias Sewing = GarmentCodeSewing
    typealias Sewn = GarmentCodeSewnDrape
    typealias Vector3 = Kernel.Vector3

    nonisolated struct Panel: Sendable {
        let mesh: GarmentCodePanelMesher.Mesh
        let positions: [Vector3]
        let fixedVertexIDs: Set<Int>
        init(mesh: GarmentCodePanelMesher.Mesh, positions: [Vector3],
             fixedVertexIDs: Set<Int> = []) {
            self.mesh = mesh
            self.positions = positions
            self.fixedVertexIDs = fixedVertexIDs
        }
    }

    nonisolated struct Metrics: Sendable {
        let garmentStyle: String
        let lengthLabel: String
        let sourceWaistMeters: Double
        let sourceHemMeters: Double
        let sourceLengthMeters: Double
        var gatherRatio: Double = 1
        var warnings: [String] = []
    }

    nonisolated private struct Edge: Hashable {
        let a: Int
        let b: Int
        init(_ a: Int, _ b: Int) { self.a = min(a,b); self.b = max(a,b) }
    }

    /// Exact standard body and compatibility proxy captured together. The
    /// resource cache and body-parameter access stay on MainActor.
    nonisolated struct BodyReceipt: Sendable {
        fileprivate enum Source: Sendable {
            case legacy(GarmentCodeStandardBody.Snapshot)
            case posed(GarmentCodeFixedBody.Recipe)
            case fitted(GarmentCodeFittedBody.FittingRecipe)
        }
        fileprivate let source: Source
        let proxy: Kernel.ProxyBody
        fileprivate init(source: Source, proxy: Kernel.ProxyBody) {
            self.source=source;self.proxy=proxy
        }
    }

    static func captureBody(body: GarmentCodeBodyParameters,
                            settings: Kernel.Settings) throws -> BodyReceipt {
        let standard = try GarmentCodeStandardBody.load(body: body,
                                                       resourceDirectory: settings.bodyResourceDirectory)
        let waist = standard.waistCircumferenceMeters, hips = standard.hipsCircumferenceMeters
        guard let hipLineCM = body["hips_line"], hipLineCM.isFinite, hipLineCM > 0 else {
            throw Kernel.DrapeError.invalid("装配需要有效的腰臀高。")
        }
        let hipLine = hipLineCM/100
        let bust=body["bust"].map { $0/100 } ?? waist*1.2
        let proxy = Kernel.ProxyBody(levels: [0.3,0.14,0,-hipLine,-hipLine-0.14,-hipLine-0.8],
            circumferences: [max(waist*1.15,bust),
                             waist*1.08,waist,hips,hips*0.83,hips*0.48])
        if settings.bodyShapeSelection == .surfaceMeasurements {
            guard settings.bodyPoseSelection == .matchPatternReference,
                  let alpha=body["arm_pose_angle"],alpha.isFinite,
                  let directory=settings.bodyResourceDirectory ?? Bundle.main.resourceURL else {
                throw Kernel.DrapeError.invalid("拟合人体需要同一纸样的参考摆臂角和完整人体资源。")
            }
            let recipe=try GarmentCodeFittedBody.captureFit(source:standard,bodyValues:body.values,
                pose:.matchPatternReference(alphaDegrees:alpha),resourceDirectory:directory)
            return .init(source:.fitted(recipe),proxy:proxy)
        }
        if settings.bodyPoseSelection == .matchPatternReference {
            guard let directory=settings.bodyResourceDirectory ?? Bundle.main.resourceURL else {throw Kernel.DrapeError.invalid("参考摆臂资源目录缺失。")}
            let recipe=GarmentCodeFixedBody.recipe(source:standard,bodyValues:body.values,resourceDirectory:directory)
            return .init(source:.posed(recipe),proxy:proxy)
        }
        return .init(source:.legacy(standard),proxy:proxy)
    }

    nonisolated struct ResolvedBodyReceipt:Sendable {
        fileprivate enum Source: Sendable {
            case legacy(GarmentCodeStandardBody.Snapshot)
            case posed(GarmentCodeFixedBody.Prepared)
            case fitted(GarmentCodeFittedBody.Prepared)
        }
        fileprivate let source: Source
        let proxy:Kernel.ProxyBody
        var legacy:GarmentCodeStandardBody.Snapshot? {
            if case let .legacy(body)=source{return body};return nil
        }
        var posed:GarmentCodeFixedBody.Prepared? {
            if case let .posed(body)=source{return body};return nil
        }
        var fitted:GarmentCodeFittedBody.Prepared? {
            if case let .fitted(body)=source{return body};return nil
        }
        var positions:[Vector3] {
            switch source {
            case let .legacy(body):return body.positions
            case let .posed(body):return body.surface.mesh.positions
            case let .fitted(body):return body.surface.mesh.positions
            }
        }
        var triangleIndices:[UInt32] {
            switch source {
            case let .legacy(body):return body.triangleIndices
            case let .posed(body):return body.surface.mesh.triangleIndices
            case let .fitted(body):return body.surface.mesh.triangleIndices
            }
        }
        fileprivate init(source:Source,proxy:Kernel.ProxyBody) {
            self.source=source;self.proxy=proxy
        }
    }
    nonisolated static func prepareBody(_ recipe:BodyReceipt,isCancelled:@Sendable()->Bool={false})throws->ResolvedBodyReceipt {
        if isCancelled(){throw CancellationError()}
        switch recipe.source {
        case let .legacy(body):return .init(source:.legacy(body),proxy:recipe.proxy)
        case let .posed(pose):
            return .init(source:.posed(try GarmentCodeFixedBody.prepare(pose,isCancelled:isCancelled)),proxy:recipe.proxy)
        case let .fitted(fit):
            return try withoutActuallyEscaping(isCancelled) { cancelled in
                .init(source:.fitted(try GarmentCodeFittedBody.fitAndPrepare(fit,isCancelled:cancelled)),proxy:recipe.proxy)
            }
        }
    }

    static func prepare(document: GarmentCodePatternFile,
                        body: GarmentCodeBodyParameters,
                        settings: Kernel.Settings,
                        panels: [Panel], hints: [Sewing.StitchHint],
                        metrics: Metrics,
                        isCancelled: @Sendable () -> Bool = { false }) throws -> Sewn.PreparedInput {
        if isCancelled() { throw CancellationError() }
        guard settings.bodyMode == .standardMannequin,
              settings.useSurfaceCollision, settings.useBodySurfaceCollision,
              let material = settings.material else {
            throw Kernel.DrapeError.unsupported("多裁片装配需要标准人体、实验面料和两类表面接触。")
        }
        try material.parameters.validate()
        let source=try Sewn.captureSource(document:document)
        let bodyReceipt=try captureBody(body:body,settings:settings)
        return try prepare(source:source,body:bodyReceipt,settings:settings,panels:panels,
                           hints:hints,metrics:metrics,isCancelled:isCancelled)
    }

    /// All mesh, sewing, mass, topology, exact-body and full-source validation
    /// is performed here on the caller's worker, using immutable receipts.
    nonisolated static func prepare(source: Sewn.SourceReceipt,
                        body: BodyReceipt,
                        settings: Kernel.Settings,
                        panels: [Panel], hints: [Sewing.StitchHint],
                        metrics: Metrics,
                        isCancelled: @Sendable () -> Bool = { false }) throws -> Sewn.PreparedInput {
        try prepare(source:source,body:prepareBody(body,isCancelled:isCancelled),settings:settings,
                    panels:panels,hints:hints,metrics:metrics,isCancelled:isCancelled)
    }

    nonisolated static func prepare(source: Sewn.SourceReceipt,
                        body: ResolvedBodyReceipt,
                        settings: Kernel.Settings,
                        panels: [Panel], hints: [Sewing.StitchHint],
                        metrics: Metrics,
                        isCancelled: @Sendable () -> Bool = { false }) throws -> Sewn.PreparedInput {
        if isCancelled() { throw CancellationError() }
        guard settings.bodyMode == .standardMannequin,
              settings.useSurfaceCollision, settings.useBodySurfaceCollision,
              let material = settings.material else {
            throw Kernel.DrapeError.unsupported("多裁片装配需要标准人体、实验面料和两类表面接触。")
        }
        try material.parameters.validate()
        let sourceSHA = try source.verifiedSHA256()
        let sourceIDs = Set(source.geometry.keys)
        guard !panels.isEmpty, panels.count <= 128, panels.count == sourceIDs.count,
              Set(panels.map { $0.mesh.panelID }) == sourceIDs,
              panels.reduce(0, { $0 + $1.positions.count }) <= 20_000,
              panels.reduce(0, { $0 + $1.mesh.triangleIndices.count }) <= 120_000 else {
            throw Kernel.DrapeError.invalid("装配必须包含全部原始裁片，且不能重复、遗漏或超过网格预算。")
        }

        var flat: [Vector3] = [], positions: [Vector3] = [], fixed: [Bool] = []
        var referenceTriangles: [UInt32] = [], triangles: [UInt32] = []
        var bindings: [Sewing.PanelBinding] = []
        var structural: [Edge: Kernel.Spring] = [:], bendEdges = Set<Edge>()
        for panel in panels {
            if isCancelled() { throw CancellationError() }
            let mesh = panel.mesh, offset = flat.count
            guard mesh.flatPositions.count == panel.positions.count,
                  !panel.positions.isEmpty,
                  panel.positions.allSatisfy({ $0.isFinite && $0.length < 5 }),
                  panel.fixedVertexIDs.allSatisfy({ panel.positions.indices.contains($0) }),
                  !mesh.triangleIndices.isEmpty, mesh.triangleIndices.count % 3 == 0 else {
                throw Kernel.DrapeError.invalid("裁片的源网格、初始位置或固定点无效。")
            }
            bindings.append(try .init(mesh: mesh, vertexOffset: offset,
                                      triangleOffset: triangles.count / 3))
            flat += mesh.flatPositions
            positions += panel.positions
            fixed += panel.positions.indices.map { panel.fixedVertexIDs.contains($0) }
            var opposite: [Edge: [Int]] = [:]
            for t in stride(from: 0, to: mesh.triangleIndices.count, by: 3) {
                if t % 384 == 0 && isCancelled() { throw CancellationError() }
                let local = (0..<3).map { Int(mesh.triangleIndices[t+$0]) }
                guard Set(local).count == 3,
                      local.allSatisfy({ mesh.flatPositions.indices.contains($0) }) else {
                    throw Kernel.DrapeError.invalid("源裁片包含无效三角面引用。")
                }
                let ids = local.map { offset+$0 }
                referenceTriangles += ids.map(UInt32.init)
                var facing = ids
                if mesh.sourceClockwise { facing.swapAt(1,2) }
                triangles += facing.map(UInt32.init)
                for (a,b,c) in [(ids[0],ids[1],ids[2]), (ids[1],ids[2],ids[0]), (ids[2],ids[0],ids[1])] {
                    let edge = Edge(a,b), length = (flat[a]-flat[b]).length
                    guard length.isFinite, length > 1e-10 else {
                        throw Kernel.DrapeError.invalid("装配中的源结构边退化。")
                    }
                    structural[edge] = .init(a: edge.a, b: edge.b, length: length)
                    opposite[edge, default: []].append(c)
                }
            }
            guard opposite.values.allSatisfy({ (1...2).contains($0.count) }) else {
                throw Kernel.DrapeError.invalid("装配中的源裁片包含非流形边。")
            }
            for vertices in opposite.values where vertices.count == 2 {
                let edge = Edge(vertices[0],vertices[1])
                if edge.a != edge.b { bendEdges.insert(edge) }
            }
        }
        func order(_ a: Kernel.Spring, _ b: Kernel.Spring) -> Bool {
            a.a == b.a ? a.b < b.b : a.a < b.a
        }
        let springs = structural.values.sorted(by: order)
        let bends = bendEdges.filter { structural[$0] == nil }.map {
            Kernel.Spring(a: $0.a, b: $0.b, length: (flat[$0.a]-flat[$0.b]).length)
        }.sorted(by: order)
        let sourceStitches = source.stitches
        let plan = try Sewing.build(bindings: bindings, positions: positions,
            sourceStitches: sourceStitches, actualSourceSHA256: sourceSHA,
            assembly: .init(sourceSHA256: sourceSHA, hints: hints), isCancelled: isCancelled)
        let paths = Dictionary(uniqueKeysWithValues: plan.allBoundaryPaths.map { ($0.edge,$0.vertexIDs) })
        let seamPaths = try sourceStitches.flatMap { stitch -> [[Int]] in
            guard let a = paths[stitch.a], let b = paths[stitch.b] else {
                throw Kernel.DrapeError.invalid("装配缺少源接缝的完整边界。")
            }
            return [a,b]
        }
        let masses = try GarmentCodeClothMaterial.lumpedMasses(
            referencePositions: flat.map { SIMD3<Double>($0.x,$0.y,$0.z) },
            triangleIndices: referenceTriangles,
            arealDensity: material.parameters.arealDensityKgPerSquareMeter)
        let standard=body.legacy
        // The proxy is retained for output compatibility. All numerical contact
        // in this path uses the exact standard surface and its same-source SDF.
        let proxy=body.proxy
        var input = Kernel.Input(positions: positions, triangleIndices: triangles,
            referencePositions: flat, referenceTriangles: referenceTriangles,
            referenceToSimulation: Array(flat.indices), panelColumns: 0, radialSegments: 0,
            seamPaths: seamPaths, seamVertexPairs: [], pinned: fixed, springs: springs,
            bendingSprings: bends, body: proxy, mannequinPositions: body.positions,
            mannequinTriangleIndices: body.triangleIndices,
            waistCircumferenceMeters: metrics.sourceWaistMeters,
            hemCircumferenceMeters: metrics.sourceHemMeters,
            radialLengthMeters: metrics.sourceLengthMeters,
            referenceAreaSquareMeters: masses.totalAreaSquareMeters, settings: settings)
        input.standardBody = standard
        input.fixedBodySurface = body.posed?.surface
        input.fittedBodySurface = body.fitted?.surface
        input.inverseMasses = masses.normalizedInverseMasses.enumerated().map { fixed[$0.offset] ? 0 : $0.element }
        input.meanParticleMassKg = masses.meanMassKg
        input.totalFabricMassKg = masses.totalMassKg
        input.garmentStyle = metrics.garmentStyle
        input.patternLengthLabel = metrics.lengthLabel
        input.waistGatherRatio = metrics.gatherRatio
        input.preparationWarnings = metrics.warnings
        input.surfaceTopology = try Sewn.contactTopology(vertexCount: positions.count,
            triangleIndices: triangles, plan: plan, isCancelled: isCancelled)
        try Kernel.attachBodySurfaceContact(to: &input)
        return try Sewn.prepare(input: input, plan: plan, source: source,
                                bindings: bindings, isCancelled: isCancelled)
    }
}
