import Foundation

/// Build a true two-panel sewing input while preserving the existing welded
/// waistband preview as a separate control. Source paper particles, triangle
/// metrics and area masses remain independent on the two sides of each seam.
@MainActor
enum GarmentCodeWaistbandAssembly {
    typealias Kernel=GarmentCodeCircleDrape
    typealias Sewing=GarmentCodeSewing
    typealias Sewn=GarmentCodeSewnDrape

    private struct Edge:Hashable {
        let a:Int
        let b:Int
        init(_ a:Int,_ b:Int) {self.a=min(a,b);self.b=max(a,b)}
    }

    static func prepare(document:GarmentCodePatternFile,body:GarmentCodeBodyParameters,
                        settings:Kernel.Settings,
                        isCancelled:@Sendable()->Bool={false}) throws ->Sewn.PreparedInput {
        if isCancelled() {throw CancellationError()}
        guard settings.bodyMode == .standardMannequin,
              settings.useSurfaceCollision,settings.useBodySurfaceCollision,
              let material=settings.material else {
            throw Kernel.DrapeError.unsupported("独立裁片缝合需要标准人体、实验面料、自接触和真实人体表面接触。")
        }
        try material.parameters.validate()
        let sourceHash=try Sewn.canonicalSourceSHA256(document:document)
        let assembly=try GarmentCodeWaistbandDrape.prepareAssembly(document:document,body:body,
            settings:settings,isCancelled:isCancelled)
        let old=assembly.input,flat=old.referencePositions,n=flat.count
        guard (3...8000).contains(n),old.referenceToSimulation.count==n,
              old.positions.count==old.pinned.count,
              old.referenceToSimulation.allSatisfy({old.positions.indices.contains($0)}),
              old.referenceTriangles.count%3==0,!old.referenceTriangles.isEmpty,
              old.referenceTriangles.count<=120_000,
              old.referenceTriangles.allSatisfy({Int($0)<n}),
              Set(assembly.sourcePanelBindings.map(\.panelID))==Set(["wb_front","wb_back"]),
              assembly.sourcePanelBindings.count==2,
              old.garmentStyle=="StraightWB" || old.garmentStyle=="FittedWB",
              document.pattern.stitches.count==2 else {
            throw Kernel.DrapeError.invalid("腰头装配缺少完整独立裁片的参考绑定。")
        }
        let positions=flat.indices.map {old.positions[old.referenceToSimulation[$0]]}
        let pinned=flat.indices.map {old.pinned[old.referenceToSimulation[$0]]}
        var triangles=Array(repeating:UInt32(0),count:old.referenceTriangles.count)
        var bindings:[Sewing.PanelBinding]=[],sourcePaths:[Sewing.EdgeKey:[Int]]=[:]
        var structural:[Edge:Kernel.Spring]=[:],bendCandidates=Set<Edge>()
        var seenVertices=Set<Int>(),seenTriangleSlots=Set<Int>()
        for source in assembly.sourcePanelBindings {
            if isCancelled() {throw CancellationError()}
            let mesh=source.mesh,offset=source.referenceVertexOffset,triangleOffset=source.triangleIndexOffset
            guard mesh.panelID==source.panelID,offset>=0,offset<=n-mesh.flatPositions.count,
                  triangleOffset>=0,triangleOffset%3==0,
                  triangleOffset<=triangles.count-mesh.triangleIndices.count else {
                throw Kernel.DrapeError.invalid("腰头源裁片的顶点或三角面偏移无效。")
            }
            let binding=try Sewing.PanelBinding(mesh:mesh,vertexOffset:offset,triangleOffset:triangleOffset/3)
            for (local,global) in binding.vertexIDs.enumerated() {
                guard seenVertices.insert(global).inserted,flat[global]==mesh.flatPositions[local] else {
                    throw Kernel.DrapeError.invalid("腰头源裁片的独立顶点缺失、重复或被修改。")
                }
            }
            bindings.append(binding)
            var adjacent:[Edge:[Int]]=[:]
            for t in stride(from:0,to:mesh.triangleIndices.count,by:3) {
                if t%384==0 && isCancelled() {throw CancellationError()}
                let local=(0..<3).map {Int(mesh.triangleIndices[t+$0])}
                guard local.allSatisfy({mesh.flatPositions.indices.contains($0)}),Set(local).count==3,
                      seenTriangleSlots.insert((triangleOffset+t)/3).inserted else {
                    throw Kernel.DrapeError.invalid("腰头源裁片的三角面索引无效或重复。")
                }
                let global=local.map {offset+$0}
                guard (0..<3).allSatisfy({old.referenceTriangles[triangleOffset+t+$0]==UInt32(global[$0])}) else {
                    throw Kernel.DrapeError.invalid("腰头参考三角面没有保持源网格的顺序和 CCW 方向。")
                }
                var face=global
                if mesh.sourceClockwise {face.swapAt(1,2)}
                for j in 0..<3 {triangles[triangleOffset+t+j]=UInt32(face[j])}
                for (a,b,opposite) in [(global[0],global[1],global[2]),
                                        (global[1],global[2],global[0]),
                                        (global[2],global[0],global[1])] {
                    let key=Edge(a,b),length=(flat[a]-flat[b]).length
                    guard length.isFinite,length>1e-10 else {
                        throw Kernel.DrapeError.invalid("腰头原始结构边退化。")
                    }
                    if let prior=structural[key],prior.length != length {
                        throw Kernel.DrapeError.invalid("腰头同一源结构边具有不同参考长度。")
                    }
                    structural[key] = .init(a:key.a,b:key.b,length:length)
                    adjacent[key,default:[]].append(opposite)
                }
            }
            guard adjacent.values.allSatisfy({(1...2).contains($0.count)}) else {
                throw Kernel.DrapeError.invalid("腰头参考网格包含非流形结构边。")
            }
            for opposite in adjacent.values where opposite.count==2 {
                let edge=Edge(opposite[0],opposite[1])
                if edge.a != edge.b {bendCandidates.insert(edge)}
            }
            for boundary in mesh.boundaries {
                let key=Sewing.EdgeKey(panelID:source.panelID,edgeIndex:boundary.edgeIndex)
                guard boundary.vertexIDs.allSatisfy({mesh.flatPositions.indices.contains($0)}),
                      sourcePaths[key]==nil else {
                    throw Kernel.DrapeError.invalid("腰头源边界顶点或边 ID 无效。")
                }
                sourcePaths[key]=boundary.vertexIDs.map {offset+$0}
            }
        }
        guard seenVertices.count==n,seenTriangleSlots.count==triangles.count/3 else {
            throw Kernel.DrapeError.invalid("真实腰头装配不能遗漏源裁片自由度或三角面。")
        }
        func order(_ a:Kernel.Spring,_ b:Kernel.Spring)->Bool {a.a==b.a ? a.b<b.b : a.a<b.a}
        let springs=structural.values.sorted(by:order)
        let bends=try bendCandidates.filter {structural[$0]==nil}.map {edge in
            let length=(flat[edge.a]-flat[edge.b]).length
            guard length.isFinite,length>1e-10 else {throw Kernel.DrapeError.invalid("腰头源二跳弯曲边退化。")}
            return Kernel.Spring(a:edge.a,b:edge.b,length:length)
        }.sorted(by:order)

        // These are known waistband side roles, not inferred gathered seams.
        // Preserve the document's A/B order and explicit right/wrong metadata.
        let expected:[Int:Int]=old.garmentStyle=="StraightWB" ? [3:0,1:2] : [0:3,2:1]
        var usedFront=Set<Int>(),sourceStitches:[Sewing.SourceStitch]=[],hints:[Sewing.StitchHint]=[]
        var seamPaths:[[Int]]=[]
        for (index,stitch) in document.pattern.stitches.enumerated() {
            if isCancelled() {throw CancellationError()}
            guard stitch.sides.count==2,!stitch.rightWrong,
                  let front=stitch.sides.first(where:{$0.panel=="wb_front"}),
                  let back=stitch.sides.first(where:{$0.panel=="wb_back"}),
                  expected[front.edge]==back.edge,usedFront.insert(front.edge).inserted else {
                throw Kernel.DrapeError.unsupported("腰头仅支持已知前后片侧边的普通等长缝合；不能猜测反缝、抽褶或附加接口。")
            }
            let a=Sewing.EdgeKey(panelID:stitch.sides[0].panel,edgeIndex:stitch.sides[0].edge)
            let b=Sewing.EdgeKey(panelID:stitch.sides[1].panel,edgeIndex:stitch.sides[1].edge)
            guard let aPath=sourcePaths[a],let bPath=sourcePaths[b] else {
                throw Kernel.DrapeError.invalid("腰头源接缝没有完整边界路径。")
            }
            sourceStitches.append(.init(a:a,b:b,rightWrong:stitch.rightWrong))
            hints.append(.init(stitchIndex:index,seamID:"waistband-side-\(index)",a:a,b:b,
                aDirection:.forward,bDirection:.reverse,rightWrong:stitch.rightWrong,intent:.ordinary))
            seamPaths += [aPath,bPath]
        }
        let plan=try Sewing.build(bindings:bindings,positions:positions,sourceStitches:sourceStitches,
            actualSourceSHA256:sourceHash,assembly:.init(sourceSHA256:sourceHash,hints:hints),isCancelled:isCancelled)
        let masses=try GarmentCodeClothMaterial.lumpedMasses(
            referencePositions:flat.map {SIMD3<Double>($0.x,$0.y,$0.z)},triangleIndices:old.referenceTriangles,
            arealDensity:material.parameters.arealDensityKgPerSquareMeter)
        guard abs(masses.totalAreaSquareMeters-old.referenceAreaSquareMeters)<=max(1e-12,masses.totalAreaSquareMeters*1e-10) else {
            throw Kernel.DrapeError.invalid("腰头独立顶点恢复后没有保留全部原始裁片面积。")
        }
        var input=Kernel.Input(positions:positions,triangleIndices:triangles,referencePositions:flat,
            referenceTriangles:old.referenceTriangles,referenceToSimulation:Array(flat.indices),
            panelColumns:0,radialSegments:0,seamPaths:seamPaths,seamVertexPairs:[],pinned:pinned,
            springs:springs,bendingSprings:bends,body:old.body,mannequinPositions:old.mannequinPositions,
            mannequinTriangleIndices:old.mannequinTriangleIndices,waistCircumferenceMeters:old.waistCircumferenceMeters,
            hemCircumferenceMeters:old.hemCircumferenceMeters,radialLengthMeters:old.radialLengthMeters,
            referenceAreaSquareMeters:old.referenceAreaSquareMeters,settings:old.settings)
        input.standardBody=old.standardBody;input.bodySurfaceMesh=old.bodySurfaceMesh
        input.inverseMasses=masses.normalizedInverseMasses.enumerated().map {pinned[$0.offset] ? 0 : $0.element}
        input.meanParticleMassKg=masses.meanMassKg;input.totalFabricMassKg=masses.totalMassKg
        input.garmentStyle=old.garmentStyle;input.patternLengthLabel=old.patternLengthLabel
        input.waistGatherRatio=old.waistGatherRatio
        input.preparationWarnings=["当前为独立腰头缝合预览，上缘使用距标准人体约 5 mm 的辅助固定支撑；前后片保留独立源顶点和质量，侧缝通过实际缝合约束闭合，尚未包含裙身或完整成衣。"]
        input.surfaceTopology=try Sewn.contactTopology(vertexCount:n,triangleIndices:triangles,plan:plan,isCancelled:isCancelled)
        if isCancelled() {throw CancellationError()}
        return try Sewn.prepare(input:input,plan:plan,document:document,bindings:bindings,isCancelled:isCancelled)
    }
}
