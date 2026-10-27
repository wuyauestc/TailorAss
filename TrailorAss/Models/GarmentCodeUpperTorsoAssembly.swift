import Foundation

/// Four source torso panels, with every real dart/centre/side/shoulder stitch.
/// This is a native layout seed and auxiliary support recipe, not an assertion
/// that a fixed template is a physical or personally fitted finished garment.
@MainActor
enum GarmentCodeUpperTorsoAssembly {
    typealias K = GarmentCodeCircleDrape
    typealias V = K.Vector3
    typealias S = GarmentCodeSewing
    typealias D = GarmentCodeSewnDrape
    typealias B = GarmentCodeAssemblyBuilder
    typealias Mesh = GarmentCodePanelMesher.Mesh

    private struct PanelRecipe {
        let name: String, source: GarmentCodePanelGeometry
        let translationY: Double
        let front: Bool
    }
    private struct Pin { let panel: String, edge: Int, atStart: Bool, point: V }
    private struct DepthCell: Hashable { let x: Int,y: Int }
    private struct DepthFace {
        let a: V,ux: Double,uy: Double,vx: Double,vy: Double,uz: Double,vz: Double,det: Double
    }
    /// A front/back ray envelope avoids the medial-axis ambiguity of a nearest
    /// SDF projection when an initial shoulder point is inside overlapping limb
    /// regions. Only the layout changes; runtime contact uses the same body.
    private struct DepthEnvelope {
        let bins: [DepthCell: [DepthFace]]
        private let spacing = 0.025
        init(body: GarmentCodeStandardBody.Snapshot, isCancelled: @Sendable () -> Bool) throws {
            var bins: [DepthCell: [DepthFace]] = [:]
            for t in stride(from: 0,to: body.triangleIndices.count,by: 3) {
                if t%1536 == 0 && isCancelled() { throw CancellationError() }
                let a=body.positions[Int(body.triangleIndices[t])],b=body.positions[Int(body.triangleIndices[t+1])],c=body.positions[Int(body.triangleIndices[t+2])]
                let u=b-a,v=c-a,det=u.x*v.y-u.y*v.x
                if abs(det)<1e-18 { continue }
                let packet=DepthFace(a: a,ux: u.x,uy: u.y,vx: v.x,vy: v.y,uz: u.z,vz: v.z,det: det)
                let loX=Int(floor(min(a.x,b.x,c.x)/spacing)),hiX=Int(floor(max(a.x,b.x,c.x)/spacing))
                let loY=Int(floor(min(a.y,b.y,c.y)/spacing)),hiY=Int(floor(max(a.y,b.y,c.y)/spacing))
                for x in loX...hiX { for y in loY...hiY { bins[.init(x: x,y: y),default: []].append(packet) } }
            }
            self.bins=bins
        }
        func outside(_ p: V, front: Bool) -> V {
            let key=DepthCell(x: Int(floor(p.x/spacing)),y: Int(floor(p.y/spacing)))
            var extent: Double?
            for f in bins[key] ?? [] {
                let x=p.x-f.a.x,y=p.y-f.a.y,b=(x*f.vy-y*f.vx)/f.det,c=(f.ux*y-f.uy*x)/f.det
                if b < -1e-10 || c < -1e-10 || b+c > 1+1e-10 { continue }
                let z=f.a.z+b*f.uz+c*f.vz
                extent=extent.map { front ? max($0,z) : min($0,z) } ?? z
            }
            guard let extent else { return p }
            return .init(x: p.x,y: p.y,z: front ? max(p.z,extent+0.005) : min(p.z,extent-0.005))
        }
    }

    static func prepare(document: GarmentCodePatternFile, body: GarmentCodeBodyParameters,
                        settings: K.Settings,
                        isCancelled: @Sendable () -> Bool = { false }) throws -> D.PreparedInput {
        if isCancelled() { throw CancellationError() }
        let sourceHash = try D.canonicalSourceSHA256(document: document)
        let names = ["right_ftorso", "right_btorso", "left_ftorso", "left_btorso"]
        let geometry = try document.geometryPanels()
        guard Set(geometry.keys) == Set(names) else {
            throw K.DrapeError.unsupported("衣身装配当前需要完整四片衣身；不能删除袖片、领片、腰头或下装后冒充完整成衣。")
        }
        let design = try nativeDesign(document: document, body: body, sourceHash: sourceHash)
        let fitted = design.value(at: ["meta", "upper"]) == .string("FittedShirt")
        let values = body.values
        func value(_ key: String) throws -> Double {
            guard let n = values[key], n.isFinite else { throw K.DrapeError.invalid("衣身装配缺少有效人体尺寸 \(key)。") }
            return n
        }
        let height = try value("height"), head = try value("head_l"), waistLevel = try value("_waist_level")
        let bust = try value("bust"), backWidth = try value("back_width"), shoulder = try value("shoulder_w")
        let waistLine = try value("waist_line"), frontWaistLine = try value("waist_over_bust_line")
        let tangent = tan(try value("_shoulder_incl") * Double.pi / 180)
        let top = height-head, f = (bust-backWidth)/2, b = backWidth/2, shoulderHalf = shoulder/2
        guard f > 0, b > 0, shoulderHalf > 0, tangent.isFinite else { throw K.DrapeError.invalid("衣身宽度或肩斜无效。") }
        func number(_ path: [String]) throws -> Double {
            guard let n = design.value(at: path)?.numberValue, n.isFinite else { throw K.DrapeError.invalid("衣身参数缺失：\(path.joined(separator: "."))。") }
            return n
        }
        var recipes: [PanelRecipe] = []
        for name in names {
            let front = name.contains("ftorso"), left = name.hasPrefix("left_")
            let asymmetric = design.value(at: ["left", "enable_asym"]) == .bool(true)
            let width = try number(left && asymmetric ? ["left", "shirt", "width"] : ["shirt", "width"])
            let ty: Double
            if fitted {
                let lf = frontWaistLine-tangent*(f-shoulderHalf), lb = waistLine-tangent*(b-shoulderHalf)
                ty = front ? top-lf-tangent*f : top-lb-tangent*b+tangent*b/4
            } else {
                let lb = try number(["shirt", "length"])*waistLine, lf = lb-tangent*(f-b)
                ty = front ? top-lf-tangent*width*f : top-lb-tangent*width*b
            }
            recipes.append(.init(name: name, source: geometry[name]!, translationY: (ty-waistLevel)/100, front: front))
        }
        let standard = try GarmentCodeStandardBody.load(body: body, resourceDirectory: settings.bodyResourceDirectory)
        let depthEnvelope = try DepthEnvelope(body: standard, isCancelled: isCancelled)
        let headlessShoulderY = (top-waistLevel)/100
        var pins: [Pin] = []
        for stitch in document.pattern.stitches {
            if isCancelled() { throw CancellationError() }
            guard stitch.sides.count == 2, !stitch.rightWrong else {
                throw K.DrapeError.unsupported("四片衣身需要已知正反面配对；不能猜测反缝或扭转。")
            }
            let first = stitch.sides[0], second = stitch.sides[1]
            if first.panel == second.panel { continue } // Keep real source darts free.
            guard let a = shoulderEndpoint(panel: geometry[first.panel]!, edge: first.edge),
                  let c = shoulderEndpoint(panel: geometry[second.panel]!, edge: second.edge),
                  first.panel.hasPrefix("left_") == second.panel.hasPrefix("left_"),
                  first.panel.contains("ftorso") != second.panel.contains("ftorso") else { continue }
            let x = (a.point.x+c.point.x)/200
            let anchor = try shoulderAnchor(body: standard, x: x, isCancelled: isCancelled)
            pins += [.init(panel: first.panel, edge: first.edge, atStart: a.atStart, point: anchor),
                     .init(panel: second.panel, edge: second.edge, atStart: c.atStart, point: anchor)]
        }
        var hints: [S.StitchHint] = []
        // Native unruffled torso interfaces carry sub-millimetre drafting
        // residuals (default Shirt side: 0.446 mm). They remain continuous
        // ordinary stitching, with both actual source metrics preserved.
        let ordinaryTolerance=0.0005
        for (index, stitch) in document.pattern.stitches.enumerated() {
            let a = stitch.sides[0], b = stitch.sides[1]
            let la = geometry[a.panel]!.edges[a.edge].length()/100, lb = geometry[b.panel]!.edges[b.edge].length()/100
            let intent: S.Intent = abs(la-lb) <= ordinaryTolerance ? .ordinary : .eased(longerSide: la > lb ? .a : .b, maximumLengthRatio: max(la,lb)/min(la,lb)+1e-8)
            hints.append(.init(stitchIndex: index, seamID: "torso-source-\(index)",
                a: .init(panelID: a.panel, edgeIndex: a.edge), b: .init(panelID: b.panel, edgeIndex: b.edge),
                aDirection: .forward, bDirection: .reverse, rightWrong: stitch.rightWrong, intent: intent,
                maximumTackSpacingMeters: 0.06, minimumFreeBoundaryNodes: 1,ordinaryLengthToleranceMeters: ordinaryTolerance))
        }
        var overrides: [String: [Int: Double]] = [:]
        for attempt in 0..<5 {
            var panels: [B.Panel] = []
            for recipe in recipes {
                if isCancelled() { throw CancellationError() }
                let mesh = try GarmentCodePanelMesher.prepare(panel: recipe.source, targetEdgeMeters: settings.targetEdgeMeters,
                    maximumVertices: 6000, maximumTriangles: 16000, maximumBoundarySpacingMeters: overrides[recipe.name] ?? [:], isCancelled: isCancelled)
                var fixed = Set<Int>(), explicit: [Int: V] = [:]
                for pin in pins where pin.panel == recipe.name {
                    let boundary = mesh.boundaries[pin.edge]
                    let id = pin.atStart ? boundary.vertexIDs[0] : boundary.vertexIDs.last!
                    fixed.insert(id); explicit[id] = pin.point
                }
                let sidePins = pins.filter { $0.panel.hasPrefix(recipe.name.hasPrefix("left_") ? "left_" : "right_") }
                let side=recipe.name.hasPrefix("left_") ? 1.0 : -1.0
                let c=1/sqrt(1+tangent*tangent),s=tangent*c
                let along=V(x: side*c,y: -s,z: 0),downNormal=V(x: side*s,y: c,z: 0)
                let support=sidePins.first?.point ?? V(x: side*shoulderHalf/100,y: headlessShoulderY-tangent*shoulderHalf/100+0.005,z: 0)
                let origin=V(x: 0,y: support.y+tangent*abs(support.x),z: support.z)
                let shoulderEdges=recipe.source.edges.indices.filter { shoulderEndpoint(panel: recipe.source,edge: $0) != nil }
                let sourceShoulderY=shoulderEdges.first.map { i in
                    let edge=recipe.source.edges[i]
                    return (edge.start.y+edge.end.y)/200+recipe.translationY+tangent*(abs(edge.start.x)+abs(edge.end.x))/200
                } ?? headlessShoulderY
                // A cylindrical bend around the actual source shoulder line
                // is isometric in its orthonormal paper coordinates. It begins
                // as a loose sheet over the body; sewing/gravity must produce
                // the final garment. No source width is squeezed onto a body
                // circumference and no nearest-SDF branch is chosen here.
                let bendRadius=0.30
                let placed = try mesh.flatPositions.enumerated().map { i,p -> V in
                    if i%128 == 0 && isCancelled() { throw CancellationError() }
                    if let q = explicit[i] { return q }
                    let paper=V(x: p.x,y: p.y+recipe.translationY-sourceShoulderY,z: 0)
                    let u=paper.x*along.x+paper.y*along.y,d = -(paper.x*downNormal.x+paper.y*downNormal.y)
                    let depth: Double,z: Double
                    if d<0 { depth=d;z=0 }
                    else if d<=Double.pi*bendRadius/2 { depth=bendRadius*(1-cos(d/bendRadius));z=bendRadius*sin(d/bendRadius) }
                    else { depth=bendRadius+d-Double.pi*bendRadius/2;z=bendRadius }
                    let world=origin+along*u-downNormal*depth+V(x: 0,y: 0,z: (recipe.front ? 1 : -1)*z)
                    return depthEnvelope.outside(world,front: recipe.front)
                }
                // Strapless has no invented shoulder seam. Its real upper
                // boundary gets a small, disclosed set of auxiliary supports.
                var positions = placed
                if sidePins.isEmpty && recipe.front {
                    for boundary in mesh.boundaries where recipe.source.edges[boundary.edgeIndex].label == "strapless_top" {
                        let candidates = [boundary.vertexIDs[0],boundary.vertexIDs.last!].filter { abs(mesh.flatPositions[$0].x)<1e-8 }
                        for id in candidates {
                            // Mirrored source halves have distinct source IDs,
                            // but their common front-centre support is one
                            // physical point, not two separated bent sheets.
                            fixed.insert(id)
                            positions[id] = depthEnvelope.outside(.init(x: 0,y: positions[id].y,z: 0),front: true)
                        }
                    }
                }
                panels.append(.init(mesh: mesh, positions: positions, fixedVertexIDs: fixed))
            }
            guard panels.contains(where: { !$0.fixedVertexIDs.isEmpty }) else { throw K.DrapeError.unsupported("衣身没有可识别的真实肩缝或抹胸上缘辅助支撑。") }
            let used = Set(document.pattern.stitches.flatMap { $0.sides.map { "\($0.panel):\($0.edge)" } })
            let hem = recipes.reduce(0.0) { sum, recipe in sum+recipe.source.edges.enumerated().filter {
                !used.contains("\(recipe.name):\($0.offset)") && $0.element.label == nil
            }.reduce(0.0) { $0+$1.element.length()/100 } }
            let backCenter = document.pattern.stitches.filter { $0.sides.count == 2 && Set($0.sides.map(\.panel)) == Set(["left_btorso","right_btorso"]) }.reduce(0.0) { sum, stitch in
                sum+geometry[stitch.sides[0].panel]!.edges[stitch.sides[0].edge].length()/100
            }
            var metrics = B.Metrics(garmentStyle: fitted ? "FittedShirt" : "Shirt", lengthLabel: "后中接缝纸样边长",
                sourceWaistMeters: hem, sourceHemMeters: hem, sourceLengthMeters: backCenter)
            metrics.warnings = ["四片真实衣身保留全部省道和接缝；仅使用少量肩点或真实抹胸上缘辅助固定支撑，不代表肩带、松紧带或实际穿着工艺。",
                "初始包体位置只用于启动缝合；人体当前仍为按腰臀围和高度有限拟合的实验人台，尚非胸肩颈臂的个人尺寸重建。",
                "已核对原生来源的普通衣身接口允许不超过 0.5 mm 的源边差，并保留各自真实长度；更大的差量明确采用有限吃势点，不会缩短纸样。"]
            do { return try B.prepare(document: document, body: body, settings: settings, panels: panels, hints: hints, metrics: metrics, isCancelled: isCancelled) }
            catch S.SewingError.refinementNeeded(let requests) {
                guard attempt < 4 else { throw S.SewingError.refinementNeeded(requests) }
                for r in requests {
                    guard r.requiredMaximumBoundarySpacingMeters >= 0.0005 else { throw S.SewingError.refinementNeeded(requests) }
                    overrides[r.edge.panelID,default: [:]][r.edge.edgeIndex] = min(overrides[r.edge.panelID]?[r.edge.edgeIndex] ?? .infinity,r.requiredMaximumBoundarySpacingMeters)
                }
            }
        }
        throw K.DrapeError.invalid("衣身局部接缝细分未能在预算内完成。")
    }

    private static func nativeDesign(document: GarmentCodePatternFile, body: GarmentCodeBodyParameters, sourceHash: String) throws -> GarmentCodeDesignParameters {
        guard case let .object(values)? = document.parameters?["design"] else { throw K.DrapeError.unsupported("衣身装配需要完整的原生设计参数来源，不能猜测未知导入纸样。") }
        let nodes = try JSONDecoder().decode([String: GarmentCodeParameterNode].self,from: JSONEncoder().encode(JSONValue.object(values)))
        let design = GarmentCodeDesignParameters(catalog: .init(design: nodes, body: body.values, bodyDerivedFormulas: nil))
        let upper = design.value(at: ["meta","upper"])
        guard (upper == .string("Shirt") || upper == .string("FittedShirt")),
              (design.value(at: ["meta","bottom"]) == nil || design.value(at: ["meta","bottom"]) == .null),
              (design.value(at: ["meta","wb"]) == nil || design.value(at: ["meta","wb"]) == .null) else {
            throw K.DrapeError.unsupported("当前衣身工厂不允许省略组合款式中的腰头或下装。")
        }
        let regenerated = try GarmentCodeNativeGenerator.generate(body: body, design: design)
        guard try D.canonicalSourceSHA256(document: regenerated) == sourceHash else { throw K.DrapeError.unsupported("当前四片衣身与完整原生参数重生成结果不同，不能猜测摆放或缝合意图。") }
        return design
    }

    private static func shoulderEndpoint(panel: GarmentCodePanelGeometry, edge: Int) -> (point: GarmentCodePoint, atStart: Bool)? {
        let n = panel.edges.count, before = panel.edges[(edge+n-1)%n], after = panel.edges[(edge+1)%n]
        if before.label?.contains("armhole") == true && after.label?.contains("collar") == true { return (panel.edges[edge].start,true) }
        if after.label?.contains("armhole") == true && before.label?.contains("collar") == true { return (panel.edges[edge].end,false) }
        return nil
    }
    private static func shoulderAnchor(body: GarmentCodeStandardBody.Snapshot, x: Double, isCancelled: @Sendable () -> Bool) throws -> V {
        var top: V?
        for t in stride(from: 0,to: body.triangleIndices.count,by: 3) {
            if t%1536 == 0 && isCancelled() { throw CancellationError() }
            let p = (0..<3).map { body.positions[Int(body.triangleIndices[t+$0])] }
            for i in 0..<3 {
                let a=p[i],b=p[(i+1)%3],d=b.x-a.x
                guard abs(d)>1e-12 else { continue }
                let u=(x-a.x)/d
                if (0...1).contains(u) { let q=a+(b-a)*u;if top == nil || q.y>top!.y { top=q } }
            }
        }
        guard let top,top.y>0.1,top.y<0.5 else { throw K.DrapeError.unsupported("当前肩宽无法在标准人台定位可靠的肩部辅助支撑。") }
        return body.project(top+V(x: 0,y: 0.005,z: 0),thickness: 0.005)
    }
}
