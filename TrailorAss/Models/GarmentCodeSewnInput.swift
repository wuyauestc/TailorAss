import Foundation
import CryptoKit

extension GarmentCodeSewnDrape {
    /// Only this factory can create a solver input carrying verified paper,
    /// assembly, mass and collision-body provenance. Validation does not certify
    /// that the chosen placement will settle or that a garment physically fits.
    nonisolated struct PreparedInput: Sendable {
        let cloth: Kernel.Input
        let plan: Sewing.Plan
        let sourceSHA256: String
        /// The exact source meshes and disjoint IDs accepted by this factory.
        /// Component layouts may reuse these as seeds, but a composed document
        /// still needs its own complete source hash, stitching plan and check.
        let panelBindings: [Sewing.PanelBinding]
        fileprivate init(cloth: Kernel.Input, plan: Sewing.Plan, sourceSHA256: String,
                         panelBindings: [Sewing.PanelBinding]) {
            self.cloth=cloth;self.plan=plan;self.sourceSHA256=sourceSHA256
            self.panelBindings=panelBindings
        }
    }

    /// Immutable complete paper source captured on MainActor. Its private
    /// constructor prevents a hash-only or partial-geometry worker receipt.
    nonisolated struct SourceReceipt: Sendable {
        let canonicalData: Data
        let sourceSHA256: String
        let geometry: [String: GarmentCodePanelGeometry]
        let stitches: [Sewing.SourceStitch]
        let bodyValues: [String: Double]?
        fileprivate init(canonicalData: Data, sourceSHA256: String,
                         geometry: [String: GarmentCodePanelGeometry], stitches: [Sewing.SourceStitch], bodyValues: [String: Double]?) {
            self.canonicalData=canonicalData;self.sourceSHA256=sourceSHA256
            self.geometry=geometry;self.stitches=stitches;self.bodyValues=bodyValues
        }
        /// Rehash actual retained canonical bytes; a caller's SHA string is
        /// never substituted for the independent geometric/rest validation.
        func verifiedSHA256() throws -> String {
            let hash=SHA256.hash(data:canonicalData).map {String(format:"%02x",$0)}.joined()
            guard hash==sourceSHA256 else {throw inputInvalid("源纸样回执的规范化数据与 SHA-256 不一致。")}
            return hash
        }
    }

    @MainActor
    private static func canonicalSourceData(document: GarmentCodePatternFile) throws -> Data {
        try boundedSource(document)
        try document.validateForPreview()
        let encoder=JSONEncoder()
        encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let bytes=try encoder.encode(document)
        guard bytes.count<=32*1024*1024 else { throw inputBudget("规范化源纸样超过 32 MiB。") }
        return bytes
    }

    @MainActor
    static func canonicalSourceSHA256(document: GarmentCodePatternFile) throws -> String {
        let bytes=try canonicalSourceData(document:document)
        return SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
    }

    @MainActor
    static func captureSource(document: GarmentCodePatternFile) throws -> SourceReceipt {
        let bytes=try canonicalSourceData(document:document)
        let hash=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        let geometry=try document.geometryPanels()
        let stitches=try document.pattern.stitches.map { stitch -> Sewing.SourceStitch in
            guard stitch.sides.count==2 else {throw inputInvalid("每组源接缝必须明确引用两条边。")}
            return .init(a:.init(panelID:stitch.sides[0].panel,edgeIndex:stitch.sides[0].edge),
                         b:.init(panelID:stitch.sides[1].panel,edgeIndex:stitch.sides[1].edge),rightWrong:stitch.rightWrong)
        }
        let originalBody=document.parameters?["body"]?.objectValue
        let numericBody=originalBody?.compactMapValues { $0.numberValue }
        let bodyValues=numericBody?.count==originalBody?.count ? numericBody:nil
        return .init(canonicalData:bytes,sourceSHA256:hash,geometry:geometry,stitches:stitches,bodyValues:bodyValues)
    }

    /// The separate-panel solver accepts this value, never an unchecked raw
    /// Kernel.Input/Plan pair. No source coordinates, rest metrics, body mesh,
    /// sewing metadata or quality thresholds are repaired during validation.
    @MainActor
    static func prepare(input: Kernel.Input, plan: Sewing.Plan,
                        document: GarmentCodePatternFile,
                        bindings: [Sewing.PanelBinding],
                        isCancelled: @Sendable () -> Bool = {false}) throws -> PreparedInput {
        if isCancelled() { throw CancellationError() }
        return try prepare(input:input,plan:plan,source:captureSource(document:document),
                           bindings:bindings,isCancelled:isCancelled)
    }

    /// Worker entry point retains every source/rest/area/facing/mass/sewing
    /// check below; captureSource only transfers actor-owned paper data.
    nonisolated static func prepare(input: Kernel.Input, plan: Sewing.Plan,
                        source receipt: SourceReceipt,
                        bindings: [Sewing.PanelBinding],
                        isCancelled: @Sendable () -> Bool = {false}) throws -> PreparedInput {
        if isCancelled() { throw CancellationError() }
        let hash=try receipt.verifiedSHA256()
        guard hash==plan.sourceSHA256 else { throw inputInvalid("缝合计划与当前规范化源纸样的 SHA-256 不一致。") }
        let n=input.positions.count,faceCount=input.triangleIndices.count/3
        guard (3...20_000).contains(n),!input.triangleIndices.isEmpty,
              input.triangleIndices.count%3==0,input.triangleIndices.count<=120_000,
              input.referencePositions.count==n,input.referenceToSimulation==Array(0..<n),
              input.referenceTriangles.count==input.triangleIndices.count,
              input.pinned.count==n,input.inverseMasses.count==n,
              input.positions.allSatisfy({$0.isFinite && $0.length<5}),
              input.referencePositions.allSatisfy({$0.isFinite && $0.length<100 && abs($0.z)<1e-12}),
              input.settings.bodyMode == .standardMannequin,
              input.settings.useSurfaceCollision,input.settings.useBodySurfaceCollision,
              input.settings.targetEdgeMeters.isFinite,(0.005...0.10).contains(input.settings.targetEdgeMeters),
              (60...2400).contains(input.settings.maximumSteps),(4...32).contains(input.settings.solverIterations),
              input.settings.bodySurfaceClearanceMeters.isFinite,
              (0.0001...0.005).contains(input.settings.bodySurfaceClearanceMeters),
              [input.waistCircumferenceMeters,input.hemCircumferenceMeters,input.radialLengthMeters]
                .allSatisfy({$0.isFinite && (0...100).contains($0)}),
              input.waistGatherRatio.isFinite,(0.01...10).contains(input.waistGatherRatio),
              !input.garmentStyle.isEmpty,input.garmentStyle.utf8.count<=256,
              !input.patternLengthLabel.isEmpty,input.patternLengthLabel.utf8.count<=256,
              input.preparationWarnings.count<=128,input.preparationWarnings.allSatisfy({$0.utf8.count<=4096}),
              let preset=input.settings.material,let bodyMesh=input.bodySurfaceMesh,
              input.springs.count<=120_000,input.bendingSprings.count<=120_000,
              !plan.constraints.isEmpty,plan.constraints.count<=4096,plan.anchors.count<=8192,
              plan.allBoundaryPaths.count<=8192,plan.contactNeighborhoods.count<=8192,
              plan.ordinaryBoundaryIntervals.count<=40_000,plan.foldIntervals.count<=40_000,
              plan.constraints.allSatisfy({$0.origins.count<=8192}),
              plan.constraints.reduce(0,{$0+$1.origins.count})<=8192,
              plan.contactNeighborhoods.allSatisfy({$0.adjacentTrianglePairs.count<=4}),
              input.seamPaths.count<=8192,input.seamPaths.allSatisfy({$0.count<=100_000}),
              input.seamPaths.reduce(0,{$0+$1.count})<=100_000,input.seamVertexPairs.count<=100_000,
              input.seamPaths.allSatisfy({$0.allSatisfy({(0..<n).contains($0)})}),
              input.seamVertexPairs.allSatisfy({(0..<n).contains($0.a) && (0..<n).contains($0.b)}) else {
            throw inputInvalid("缝合输入需要有界的独立裁片、恒等参考映射、实验面料及标准人体表面接触。")
        }
        guard bodyMesh.positions==input.mannequinPositions,bodyMesh.triangleIndices==input.mannequinTriangleIndices else {
            throw inputInvalid("可见人体与面接触人体必须来自同一份顶点和三角面。")
        }
        if let fitted=input.fittedBodySurface {
            guard input.standardBody==nil,input.fixedBodySurface==nil,
                  input.settings.bodyShapeSelection == .surfaceMeasurements,
                  input.settings.bodyPoseSelection == .matchPatternReference,
                  let bodyValues=receipt.bodyValues else {throw inputInvalid("拟合人体必须绑定同一纸样的完整人体参数，不能携带旧人体或逆SDF。")}
            try withoutActuallyEscaping(isCancelled) { cancelled in
                try fitted.verify(positions:input.mannequinPositions,triangleIndices:input.mannequinTriangleIndices,
                                  bodyValues:bodyValues,requirePatternReference:true,isCancelled:cancelled)
            }
        }else if let fixed=input.fixedBodySurface {
            guard input.standardBody==nil,input.settings.bodyShapeSelection == .scaledTemplate,
                  input.settings.bodyPoseSelection == .matchPatternReference else {throw inputInvalid("摆姿人体不能挂接旧逆SDF或冒充拟合人体。")}
            try fixed.verify(positions:input.mannequinPositions,triangleIndices:input.mannequinTriangleIndices)
        }else{
            guard input.settings.bodyShapeSelection == .scaledTemplate,
                  input.settings.bodyPoseSelection == .legacyTemplate,let body=input.standardBody,
                  body.positions==input.mannequinPositions,body.triangleIndices==input.mannequinTriangleIndices else {
                throw inputInvalid("旧SDF人体必须与可见人体、面接触人体逐值一致；摆姿必须有同源回执。")
            }
        }
        if let limit=input.settings.sourceStrainLimit {
            guard limit.isFinite,(0...0.4).contains(limit),(1...120).contains(input.settings.sourceStrainLimitPasses) else {
                throw inputInvalid("可选源边应变投影的比例或迭代预算无效。")
            }
        }
        try preset.parameters.validate()
        let source=receipt.geometry
        guard !bindings.isEmpty,bindings.count==source.count,bindings.count<=128,
              Set(bindings.map { $0.mesh.panelID })==Set(source.keys) else {
            throw inputInvalid("必须显式绑定源纸样中的全部裁片，不能遗漏或重复裁片。")
        }
        var seenVertices=Set<Int>(),seenTriangles=Set<Int>()
        var vertexPanel=Array(repeating:-1,count:n)
        var expectedEdges:[InputEdge:Double]=[:],neighbors=Array(repeating:Set<Int>(),count:n)
        var expectedPaths:[Sewing.EdgeKey:Sewing.BoundaryPath]=[:]
        var totalArea=0.0,boundarySamples=0,integrationVisits=0
        for (panelIndex,binding) in bindings.enumerated() {
            if isCancelled() { throw CancellationError() }
            let mesh=binding.mesh,paper=source[mesh.panelID]!
            let count=mesh.flatPositions.count,localFaces=mesh.triangleIndices.count/3
            guard (3...20_000).contains(count),binding.vertexIDs.count==count,
                  !mesh.triangleIndices.isEmpty,mesh.triangleIndices.count%3==0,
                  binding.triangleIDs.count==localFaces,
                  Set(binding.vertexIDs).count==count,Set(binding.triangleIDs).count==localFaces,
                  binding.vertexIDs.allSatisfy({(0..<n).contains($0)}),
                  binding.triangleIDs.allSatisfy({(0..<faceCount).contains($0)}),
                  mesh.boundaries.count==paper.edges.count,
                  Set(mesh.boundaries.map(\.edgeIndex))==Set(paper.edges.indices),
                  mesh.maximumBoundaryDeviationMeters.isFinite,(0...0.001).contains(mesh.maximumBoundaryDeviationMeters),
                  mesh.arcLengthIntegrationToleranceMeters.isFinite,
                  (0...1e-8).contains(mesh.arcLengthIntegrationToleranceMeters) else {
                throw inputInvalid("裁片绑定的顶点、三角面、边界或误差声明无效。")
            }
            for (local,global) in binding.vertexIDs.enumerated() {
                guard seenVertices.insert(global).inserted,mesh.flatPositions[local]==input.referencePositions[global] else {
                    throw inputInvalid("裁片顶点已被合并、重复或偏离原参考纸样。")
                }
                vertexPanel[global]=panelIndex
            }
            var adjacency:[InputEdge:[(face:Int,a:Int,b:Int)]]=[:]
            var meshArea=0.0
            for t in 0..<localFaces {
                if t%128==0 && isCancelled() { throw CancellationError() }
                let local=(0..<3).map {Int(mesh.triangleIndices[t*3+$0])}
                guard Set(local).count==3,local.allSatisfy({(0..<count).contains($0)}),
                      seenTriangles.insert(binding.triangleIDs[t]).inserted else {
                    throw inputInvalid("裁片三角面含重复 ID 或无效顶点。")
                }
                let global=local.map {binding.vertexIDs[$0]},slot=binding.triangleIDs[t]*3
                var sourceFacing=global
                if mesh.sourceClockwise {sourceFacing.swapAt(1,2)}
                // A vertex set alone also accepts a single flipped face. Rest
                // faces retain the mesher's CCW convention; simulation faces
                // restore the original paper-panel normal. Only cyclic index
                // rotation preserves each of these directed orientations.
                guard sameCyclicFace(input.referenceTriangles[slot..<slot+3].map(Int.init),global),
                      sameCyclicFace(input.triangleIndices[slot..<slot+3].map(Int.init),sourceFacing) else {
                    throw inputInvalid("参考面必须保持源网格 CCW 方向，模拟面必须保留源裁片法向；不能翻转单个面。")
                }
                let p=local.map {mesh.flatPositions[$0]}
                let twice=(p[1]-p[0]).cross(p[2]-p[0]).z
                guard twice.isFinite,twice>1e-14 else { throw inputInvalid("参考裁片存在翻转或退化三角面。") }
                meshArea += twice/2
                for (a,b) in [(local[0],local[1]),(local[1],local[2]),(local[2],local[0])] {
                    adjacency[.init(a,b),default:[]].append((binding.triangleIDs[t],a,b))
                    let x=binding.vertexIDs[a],y=binding.vertexIDs[b],key=InputEdge(x,y)
                    let length=(mesh.flatPositions[a]-mesh.flatPositions[b]).length
                    guard length.isFinite,length>1e-10 else { throw inputInvalid("源结构边退化。") }
                    if let old=expectedEdges[key],abs(old-length)>1e-12 { throw inputInvalid("同一源边有不同参考长度。") }
                    expectedEdges[key]=length;neighbors[x].insert(y);neighbors[y].insert(x)
                }
            }
            guard adjacency.values.allSatisfy({ uses in
                uses.count==1 || (uses.count==2 && uses[0].a==uses[1].b && uses[0].b==uses[1].a)
            }),count-adjacency.count+localFaces==1 else {
                throw inputInvalid("参考裁片不是一致定向的单连通三角网格。")
            }
            var boundaryKeys=Set<InputEdge>(),priorLast:Int?,firstID:Int?
            var analyticSignedArea=0.0,sourcePerimeter=0.0
            for boundary in mesh.boundaries.sorted(by:{$0.edgeIndex<$1.edgeIndex}) {
                if isCancelled() { throw CancellationError() }
                guard boundary.vertexIDs.count<=100_000 else {throw inputBudget("单条源边界样本过多。")}
                boundarySamples += boundary.vertexIDs.count
                guard boundarySamples<=100_000 else { throw inputBudget("源边界样本过多。") }
                let edge=paper.edges[boundary.edgeIndex],curve=try InputCurve(edge)
                let m=boundary.vertexIDs.count,length=edge.length(tolerance:1e-9)/100
                guard m>=2,boundary.sourceParameters.count==m,boundary.arcFractions.count==m,
                      boundary.edgeID==edge.id,boundary.vertexIDs.allSatisfy({(0..<count).contains($0)}),
                      boundary.sourceParameters.allSatisfy({$0.isFinite && (0...1).contains($0)}),
                      boundary.arcFractions.allSatisfy({$0.isFinite && (0...1).contains($0)}),
                      boundary.sourceParameters.first==0,boundary.sourceParameters.last==1,
                      boundary.arcFractions.first==0,boundary.arcFractions.last==1,
                      zip(boundary.sourceParameters,boundary.sourceParameters.dropFirst()).allSatisfy({$0.0<$0.1}),
                      zip(boundary.arcFractions,boundary.arcFractions.dropFirst()).allSatisfy({$0.0<$0.1}),
                      length.isFinite,length>1e-9,abs(boundary.sourceLengthMeters-length)<=1e-9 else {
                    throw inputInvalid("边界 ID、方向、原弧长或参数采样与源纸样不一致。")
                }
                if let last=priorLast,last != boundary.vertexIDs[0] { throw inputInvalid("原始相邻边没有共享其裁片角点。") }
                if firstID==nil {firstID=boundary.vertexIDs[0]};priorLast=boundary.vertexIDs.last
                var cumulative=0.0,segments:[Sewing.BoundarySegment]=[]
                let key=Sewing.EdgeKey(panelID:mesh.panelID,edgeIndex:boundary.edgeIndex)
                for i in 0..<m {
                    let t=boundary.sourceParameters[i],id=boundary.vertexIDs[i]
                    guard (mesh.flatPositions[id]-curve.point(t)).length<=1e-9 else {
                        throw inputInvalid("边界顶点不是其声明参数处的真实源曲线点。")
                    }
                    if i>0 {
                        let a=boundary.vertexIDs[i-1],b=id,pair=InputEdge(a,b)
                        guard boundaryKeys.insert(pair).inserted,let use=adjacency[pair],use.count==1 else {
                            throw inputInvalid("源边界线段缺少唯一相邻面或被重复使用。")
                        }
                        let lo=boundary.sourceParameters[i-1],hi=t
                        let bound=curve.secondBound(lo,hi)*(hi-lo)*(hi-lo)/8
                        guard bound<=mesh.maximumBoundaryDeviationMeters+1e-11 else {
                            throw inputInvalid("源曲线的离散误差超过网格声明。")
                        }
                        cumulative += try curve.length(lo,hi,total:length,visits:&integrationVisits,isCancelled:isCancelled)
                        let actualFraction=cumulative/length
                        guard abs(boundary.arcFractions[i]-actualFraction)<=2e-8 else {
                            throw inputInvalid("边界弧长比例与原始曲线积分不同。")
                        }
                        segments.append(.init(edge:key,edgeID:edge.id,segmentIndex:i-1,
                            vertexIDs:[binding.vertexIDs[a],binding.vertexIDs[b]],adjacentTriangleID:use[0].face,
                            sourceArcRange:boundary.arcFractions[i-1]...boundary.arcFractions[i]))
                    }
                }
                expectedPaths[key] = .init(edge:key,edgeID:edge.id,
                    vertexIDs:boundary.vertexIDs.map {binding.vertexIDs[$0]},sourceParameters:boundary.sourceParameters,
                    sourceArcFractions:boundary.arcFractions,sourceLengthMeters:boundary.sourceLengthMeters,segments:segments)
                analyticSignedArea += curve.green(origin:mesh.flatPositions[0]);sourcePerimeter += length
            }
            guard priorLast==firstID,
                  boundaryKeys==Set(adjacency.compactMap {$0.value.count==1 ? $0.key : nil}),
                  analyticSignedArea.isFinite,abs(analyticSignedArea)>1e-12,
                  mesh.sourceClockwise == (analyticSignedArea<0),
                  abs(mesh.sourceSignedAreaSquareMeters-analyticSignedArea)<=1e-10,
                  abs(mesh.flattenedAreaSquareMeters-meshArea)<=1e-10,
                  abs(meshArea-abs(analyticSignedArea))<=sourcePerimeter*mesh.maximumBoundaryDeviationMeters+1e-9 else {
                throw inputInvalid("裁片边界、解析面积、离散面积或原始方向不一致。")
            }
            totalArea += meshArea
        }
        guard seenVertices.count==n,seenTriangles.count==faceCount,
              input.referenceAreaSquareMeters.isFinite,abs(input.referenceAreaSquareMeters-totalArea)<=max(1e-12,totalArea*1e-10),
              input.springs.count==expectedEdges.count else {
            throw inputInvalid("源顶点、三角面、面积或全部结构边没有被完整保留。")
        }
        var springKeys=Set<InputEdge>()
        for (index,spring) in input.springs.enumerated() {
            if index%128==0 && isCancelled() { throw CancellationError() }
            let key=InputEdge(spring.a,spring.b)
            guard springKeys.insert(key).inserted,let rest=expectedEdges[key],spring.length.isFinite,
                  abs(spring.length-rest)<=max(1e-12,rest*1e-10) else {
                throw inputInvalid("结构边缺失、重复、跨片、被平均或改变了原始参考长度。")
            }
        }
        var bendKeys=Set<InputEdge>()
        for spring in input.bendingSprings {
            if isCancelled() { throw CancellationError() }
            let a=spring.a,b=spring.b,key=InputEdge(a,b)
            guard (0..<n).contains(a),(0..<n).contains(b),a != b,vertexPanel[a]==vertexPanel[b],
                  bendKeys.insert(key).inserted,!springKeys.contains(key),
                  !neighbors[a].isDisjoint(with:neighbors[b]),spring.length.isFinite,spring.length>1e-10,
                  abs(spring.length-(input.referencePositions[a]-input.referencePositions[b]).length)<=max(1e-12,spring.length*1e-10) else {
                throw inputInvalid("弯曲近似必须是同一裁片内唯一的源长度二跳距离，不能额外缝合或硬撑裁片。")
            }
        }
        let masses=try GarmentCodeClothMaterial.lumpedMasses(
            referencePositions:input.referencePositions.map {SIMD3<Double>($0.x,$0.y,$0.z)},
            triangleIndices:input.referenceTriangles,referenceToSimulation:input.referenceToSimulation,
            simulationVertexCount:n,arealDensity:preset.parameters.arealDensityKgPerSquareMeter)
        guard let totalMass=input.totalFabricMassKg,totalMass.isFinite,
              abs(totalMass-masses.totalMassKg)<=max(1e-12,masses.totalMassKg*1e-10),
              input.meanParticleMassKg.isFinite,
              abs(input.meanParticleMassKg-masses.meanMassKg)<=max(1e-14,masses.meanMassKg*1e-10) else {
            throw inputInvalid("面料总质量或归一化质量尺度与原始裁片三角面积不一致。")
        }
        for (id,expected) in masses.normalizedInverseMasses.enumerated() {
            let actual=input.inverseMasses[id],wanted=input.pinned[id] ? 0 : expected
            guard actual.isFinite,abs(actual-wanted)<=max(1e-12,abs(wanted)*1e-10) else {
                throw inputInvalid("顶点归一化逆质量或固定点掩码与源面积质量不一致。")
            }
        }
        try validatePlan(plan,paths:expectedPaths,stitches:receipt.stitches,positions:input.positions,
                         pinned:input.pinned,isCancelled:isCancelled)
        // Recreate the topology from verified source-local contact metadata;
        // this also checks that every advertised segment is an actual boundary.
        _ = try contactTopology(vertexCount:n,triangleIndices:input.triangleIndices,plan:plan,isCancelled:isCancelled)
        if isCancelled() { throw CancellationError() }
        return PreparedInput(cloth:input,plan:plan,sourceSHA256:hash,panelBindings:bindings)
    }

    @MainActor
    private static func boundedSource(_ document:GarmentCodePatternFile)throws {
        guard (1...128).contains(document.pattern.panels.count),document.pattern.stitches.count<=2048,
              document.pattern.panels.allSatisfy({name,panel in
                  !name.isEmpty && name.utf8.count<=256 && (2...512).contains(panel.edges.count)
                    && (2...20_000).contains(panel.vertices.count)
              }),document.pattern.panels.values.reduce(0,{$0+$1.vertices.count})<=100_000,
              document.pattern.panels.values.reduce(0,{$0+$1.edges.count})<=8192 else {
            throw inputBudget("源裁片、顶点、边或接缝数量超过本轮输入预算。")
        }
    }
    nonisolated private static func inputInvalid(_ message:String)->Kernel.DrapeError {.invalid(message)}
    nonisolated private static func inputBudget(_ message:String)->Sewing.SewingError {.budgetExceeded(message)}
    nonisolated private struct InputEdge:Hashable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int){self.a=min(a,b);self.b=max(a,b)}
    }
    nonisolated private static func sameCyclicFace(_ actual:[Int],_ expected:[Int])->Bool {
        guard actual.count==3,expected.count==3 else {return false}
        return (0..<3).contains {shift in (0..<3).allSatisfy {actual[$0]==expected[($0+shift)%3]}}
    }

    /// Independent source-primitive measurements, in metres. No triangulation
    /// is rerun and no source point is snapped to a nearby meshed location.
    nonisolated private struct InputCurve {
        let edge:GarmentCodeGeometryEdge
        let coefficients:[Kernel.Vector3]
        let arc:(center:Kernel.Vector3,radius:Double,theta:Double,delta:Double)?
        init(_ edge:GarmentCodeGeometryEdge)throws {
            self.edge=edge
            let a=Kernel.Vector3(x:edge.start.x/100,y:edge.start.y/100,z:0)
            let b=Kernel.Vector3(x:edge.end.x/100,y:edge.end.y/100,z:0),chord=b-a
            var p=[a]
            if let controls=edge.curvature?.params {
                let left=Kernel.Vector3(x:-chord.y,y:chord.x,z:0)
                p += controls.map {a+chord*$0[0]+left*$0[1]}
            }
            p.append(b)
            guard p.allSatisfy({$0.isFinite && $0.length<100}) else {throw inputInvalid("源曲线控制点无效。")}
            switch p.count {
            case 2:coefficients=[a,b-a]
            case 3:coefficients=[a,(p[1]-a)*2,a-p[1]*2+b]
            case 4:coefficients=[a,(p[1]-a)*3,(a-p[1]*2+p[2])*3,b-p[2]*3+p[1]*3-a]
            default:throw inputInvalid("源曲线阶数无效。")
            }
            if let circle=edge.curvature?.circle {
                let d=chord.length,r=max(circle.radius/100,d/2)
                guard d>1e-14 else {throw inputInvalid("源圆弧端点重合。")}
                let h=sqrt(max(0,r*r-d*d/4)),sign=circle.largeArc == circle.right ? -1.0 : 1.0
                let c=(a+b)/2+Kernel.Vector3(x:-chord.y/d,y:chord.x/d,z:0)*(h*sign)
                let first=atan2(a.y-c.y,a.x-c.x),last=atan2(b.y-c.y,b.x-c.x)
                var delta=last-first
                if circle.right {while delta<0 {delta += 2*Double.pi};while delta>=2*Double.pi {delta -= 2*Double.pi}}
                else {while delta>0 {delta -= 2*Double.pi};while delta <= -2*Double.pi {delta += 2*Double.pi}}
                if abs(delta) != Double.pi && (abs(delta)>Double.pi) != circle.largeArc {delta += circle.right ? -2*Double.pi : 2*Double.pi}
                arc=(c,r,first,delta)
            } else {arc=nil}
        }
        func point(_ t:Double)->Kernel.Vector3 {let p=edge.point(at:t);return .init(x:p.x/100,y:p.y/100,z:0)}
        func derivative(_ t:Double)->Kernel.Vector3 {
            if let arc {let a=arc.theta+arc.delta*t;return .init(x:-sin(a)*arc.radius*arc.delta,y:cos(a)*arc.radius*arc.delta,z:0)}
            return (1..<coefficients.count).reduce(.zero) {$0+coefficients[$1]*(Double($1)*pow(t,Double($1-1)))}
        }
        func secondBound(_ a:Double,_ b:Double)->Double {
            if let arc {return arc.radius*arc.delta*arc.delta}
            func second(_ t:Double)->Kernel.Vector3 {
                (2..<coefficients.count).reduce(.zero) {$0+coefficients[$1]*(Double($1*($1-1))*pow(t,Double($1-2)))}
            }
            return max(second(a).length,second(b).length)
        }
        func green(origin:Kernel.Vector3)->Double {
            if let arc {let a=point(0),b=point(1),c=arc.center-origin;return (c.x*(b.y-a.y)-c.y*(b.x-a.x)+arc.radius*arc.radius*arc.delta)/2}
            var c=coefficients;c[0]=c[0]-origin
            var result=0.0
            for i in c.indices {for j in 1..<c.count {result += Double(j)*(c[i].x*c[j].y-c[i].y*c[j].x)/Double(i+j)}}
            return result/2
        }
        func length(_ a:Double,_ b:Double,total:Double,visits:inout Int,
                    isCancelled:@Sendable()->Bool)throws->Double {
            if arc != nil || edge.curvature==nil {return total*(b-a)}
            func visit(_ a:Double,_ b:Double,_ fa:Double,_ fm:Double,_ fb:Double,_ whole:Double,_ epsilon:Double,_ depth:Int)throws->Double {
                visits += 1
                if visits%128==0 && isCancelled() {throw CancellationError()}
                guard visits<=2_000_000 else {throw inputBudget("源曲线弧长复核超过积分预算。")}
                let m=(a+b)/2,l=derivative((a+m)/2).length,r=derivative((m+b)/2).length
                let left=(m-a)*(fa+4*l+fm)/6,right=(b-m)*(fm+4*r+fb)/6,delta=left+right-whole
                if abs(delta)<=15*epsilon {return left+right+delta/15}
                guard depth<24 else {throw inputInvalid("源曲线弧长复核未收敛。")}
                return try visit(a,m,fa,l,fm,left,epsilon/2,depth+1)+visit(m,b,fm,r,fb,right,epsilon/2,depth+1)
            }
            let fa=derivative(a).length,fm=derivative((a+b)/2).length,fb=derivative(b).length
            return try visit(a,b,fa,fm,fb,(b-a)*(fa+4*fm+fb)/6,1e-11,0)
        }
    }

    nonisolated private static func pathLocation(_ path:Sewing.BoundaryPath,_ f:Double)throws->Sewing.Location {
        guard f.isFinite,(0...1).contains(f) else {throw inputInvalid("缝合位置弧长比例无效。")}
        let fractions=path.sourceArcFractions,last=fractions.count-1
        var lo=0,hi=last
        while hi-lo>1 {let mid=(lo+hi)/2;if fractions[mid]<f {lo=mid}else{hi=mid}}
        let vertex:Int?=abs(f-fractions[lo])<=1e-12 ? lo : (abs(f-fractions[hi])<=1e-12 ? hi : nil)
        let attachment:Sewing.Attachment,segments:[Sewing.BoundarySegment],actual:Double
        if let vertex {
            attachment=try .init(vertexID:path.vertexIDs[vertex]);actual=fractions[vertex]
            var ids:[Int]=[];if vertex>0 {ids.append(vertex-1)};if vertex<last {ids.append(vertex)}
            segments=ids.map {path.segments[$0]}
        } else {
            let w=(f-fractions[lo])/(fractions[hi]-fractions[lo])
            attachment=try .init(vertexIDs:[path.vertexIDs[lo],path.vertexIDs[hi]],weights:[1-w,w])
            segments=[path.segments[lo]];actual=f
        }
        let first=segments.map(\.segmentIndex).min()!,end=segments.map(\.segmentIndex).max()!+1
        return .init(edge:path.edge,edgeID:path.edgeID,sourceArcFraction:actual,sourceLengthMeters:path.sourceLengthMeters,
            sourceParameterRange:path.sourceParameters[first]...path.sourceParameters[end],attachment:attachment,boundarySegments:segments)
    }

    nonisolated private static func validatePlan(_ plan:Sewing.Plan,paths:[Sewing.EdgeKey:Sewing.BoundaryPath],
        stitches:[Sewing.SourceStitch],positions:[Kernel.Vector3],pinned:[Bool],
        isCancelled:@Sendable()->Bool)throws {
        guard plan.allBoundaryPaths.count==paths.count else {throw inputInvalid("缝合计划未保留所有源边界。")}
        var seen=Set<Sewing.EdgeKey>()
        for p in plan.allBoundaryPaths {
            guard seen.insert(p.edge).inserted,let expected=paths[p.edge],p.edgeID==expected.edgeID,
                  p.vertexIDs==expected.vertexIDs,p.sourceParameters==expected.sourceParameters,
                  p.sourceArcFractions==expected.sourceArcFractions,p.sourceLengthMeters==expected.sourceLengthMeters,
                  p.segments==expected.segments else {throw inputInvalid("缝合计划的源边界与绑定网格不同。")}
        }
        func check(_ location:Sewing.Location)throws {
            guard let p=paths[location.edge],try pathLocation(p,location.sourceArcFraction)==location else {
                throw inputInvalid("缝合附着点、边界区间或相邻面不是其声明的源弧长位置。")
            }
        }
        var grouped:[Int:[Int]]=[:],usedConstraintOrigins=Array(repeating:Set<Sewing.Origin>(),count:plan.constraints.count)
        var attached=Set<Int>(),shared=0
        for (id,a) in plan.anchors.enumerated() {
            if id%64==0 && isCancelled() {throw CancellationError()}
            guard stitches.indices.contains(a.stitchIndex),a.normalizedSeamFraction.isFinite,
                  (0...1).contains(a.normalizedSeamFraction),!a.seamID.isEmpty,a.seamID.utf8.count<=256 else {
                throw inputInvalid("缝合锚点的源接缝索引或归一化位置无效。")
            }
            let stitch=stitches[a.stitchIndex]
            guard a.a.edge == stitch.a,
                  a.b.edge == stitch.b else {
                throw inputInvalid("缝合锚点没有对应同一条源接缝的两侧。")
            }
            try check(a.a);try check(a.b)
            attached.formUnion(a.a.attachment.vertexIDs);attached.formUnion(a.b.attachment.vertexIDs)
            if let c=a.constraintIndex {
                guard plan.constraints.indices.contains(c),a.a.attachment != a.b.attachment else {throw inputInvalid("缝合约束索引或共享角点处理无效。")}
                let constraint=plan.constraints[c]
                guard (constraint.a==a.a.attachment && constraint.b==a.b.attachment)
                    || (constraint.b==a.a.attachment && constraint.a==a.b.attachment) else {throw inputInvalid("锚点与其实际约束附着点不同。")}
            } else {
                guard a.a.attachment==a.b.attachment else {throw inputInvalid("独立附着点不能省略缝合约束。")};shared += 1
            }
            grouped[a.stitchIndex,default:[]].append(id)
        }
        guard Set(grouped.keys)==Set(stitches.indices),plan.sharedTopologicalCornerAnchors==shared,
              plan.deduplicatedCornerConstraints==plan.anchors.count-shared-plan.constraints.count else {
            throw inputInvalid("源接缝覆盖或角点约束去重计数不一致。")
        }
        var intents:[Int:Sewing.Intent]=[:],seamNames=Set<String>(),usedEdges=Set<Sewing.EdgeKey>()
        for index in stitches.indices {
            if isCancelled() {throw CancellationError()}
            let ids=grouped[index]!.sorted {plan.anchors[$0].normalizedSeamFraction<plan.anchors[$1].normalizedSeamFraction}
            let anchors=ids.map {plan.anchors[$0]},first=anchors[0],last=anchors.last!
            guard (2...513).contains(anchors.count),first.normalizedSeamFraction==0,last.normalizedSeamFraction==1,
                  seamNames.insert(first.seamID).inserted,anchors.allSatisfy({$0.seamID==first.seamID}),
                  zip(anchors,anchors.dropFirst()).allSatisfy({$0.0.normalizedSeamFraction<$0.1.normalizedSeamFraction}),
                  usedEdges.insert(first.a.edge).inserted,usedEdges.insert(first.b.edge).inserted else {
                throw inputInvalid("源接缝必须有唯一、完整且不重复使用边界的缝合路径。")
            }
            let aDirection:Sewing.Direction=first.a.sourceArcFraction==0 ? .forward : .reverse
            let bDirection:Sewing.Direction=first.b.sourceArcFraction==0 ? .forward : .reverse
            let origins=anchors.compactMap {anchor in anchor.constraintIndex.flatMap {c in
                plan.constraints[c].origins.first {$0.stitchIndex==index && $0.a==anchor.a && $0.b==anchor.b}
            }}
            guard let intent=origins.first?.intent,origins.allSatisfy({$0.intent==intent}) else {
                throw inputInvalid("接缝缺少一致、明确的普通／吃势／抽褶意图来源。")
            }
            intents[index]=intent
            let aLength=paths[first.a.edge]!.sourceLengthMeters,bLength=paths[first.b.edge]!.sourceLengthMeters
            switch intent {
            case .ordinary:
                guard abs(aLength-bLength)<=0.001 else {throw inputInvalid("不等长源边不能假定为普通等长接缝。")}
            case let .eased(side,ratio),let .gathered(side,ratio):
                let long=side == .a ? aLength : bLength,short=side == .a ? bLength : aLength
                guard ratio.isFinite,(1...10).contains(ratio),long+1e-10>=short,long/short<=ratio+1e-9 else {throw inputInvalid("吃势／抽褶来源与真实长边和倍率不符。")}
                if case .gathered=intent,long<=short+max(1e-9,short*1e-6) {throw inputInvalid("抽褶来源没有实际多余源长度。")}
            }
            for anchor in anchors {
                let f=anchor.normalizedSeamFraction
                guard abs(anchor.a.sourceArcFraction-(aDirection == .forward ? f : 1-f))<1e-11,
                      abs(anchor.b.sourceArcFraction-(bDirection == .forward ? f : 1-f))<1e-11 else {
                    throw inputInvalid("原始边路径方向与接缝归一化位置不一致。")
                }
                if let c=anchor.constraintIndex {
                    usedConstraintOrigins[c].insert(.init(seamID:anchor.seamID,stitchIndex:index,a:anchor.a,b:anchor.b,
                        aDirection:aDirection,bDirection:bDirection,intent:intent,rightWrong:stitches[index].rightWrong,
                        reversedRelativeToConstraint:plan.constraints[c].a != anchor.a.attachment))
                }
            }
        }
        for (id,c) in plan.constraints.enumerated() {
            if id%64==0 && isCancelled() {throw CancellationError()}
            let a=try Sewing.Attachment(vertexIDs:c.a.vertexIDs,weights:c.a.weights)
            let b=try Sewing.Attachment(vertexIDs:c.b.vertexIDs,weights:c.b.weights)
            let delta=try a.point(in:positions)-b.point(in:positions),gap=delta.length
            guard a==c.a,b==c.b,a != b,c.finalGapMeters==0,c.initialGapMeters.isFinite,
                  abs(c.initialGapMeters-gap)<=1e-10,c.initialDirection.isFinite,
                  (gap>1e-12 ? (c.initialDirection-delta/gap).length<1e-8 : c.initialDirection.length<1e-8),
                  !usedConstraintOrigins[id].isEmpty,Set(c.origins)==usedConstraintOrigins[id],c.origins.count==usedConstraintOrigins[id].count else {
                throw inputInvalid("缝合约束来源、初始间距或方向与当前独立裁片放置不同。")
            }
        }
        guard plan.contactNeighborhoods.count==plan.anchors.count else {throw inputInvalid("每个缝合锚点都需要准确的局部接触来源。")}
        var seenNeighborhoods=Set<Int>(),pairCount=0
        for c in plan.contactNeighborhoods {
            if isCancelled() {throw CancellationError()}
            guard plan.anchors.indices.contains(c.anchorIndex),seenNeighborhoods.insert(c.anchorIndex).inserted else {throw inputInvalid("局部缝合接触锚点重复或无效。")}
            let a=plan.anchors[c.anchorIndex]
            var pairs=Set<Sewing.TrianglePair>()
            for x in a.a.boundarySegments {for y in a.b.boundarySegments where x.adjacentTriangleID != y.adjacentTriangleID {pairs.insert(.init(a:x.adjacentTriangleID,b:y.adjacentTriangleID))}}
            pairCount += pairs.count
            guard pairCount<=40_000,c.constraintIndex==a.constraintIndex,c.a==a.a,c.b==a.b,
                  c.rightWrong==stitches[a.stitchIndex].rightWrong,
                  Set(c.adjacentTrianglePairs)==pairs,c.adjacentTrianglePairs.count==pairs.count else {
                throw inputInvalid("局部接触不能扩大为非源接缝面片的碰撞豁免。")
            }
        }
        func isContinuous(_ intent:Sewing.Intent?)->Bool {
            switch intent {case .ordinary?,.eased?:return true;default:return false}
        }
        var intervalKeys=Set<String>()
        for c in plan.ordinaryBoundaryIntervals {
            if isCancelled() {throw CancellationError()}
            guard isContinuous(intents[c.stitchIndex]),plan.anchors.indices.contains(c.startAnchorIndex),
                  plan.anchors.indices.contains(c.endAnchorIndex) else {throw inputInvalid("仅普通／吃势接缝允许连续的匹配边界接触区间。")}
            let a=plan.anchors[c.startAnchorIndex],b=plan.anchors[c.endAnchorIndex]
            guard a.stitchIndex==c.stitchIndex,b.stitchIndex==c.stitchIndex,a.seamID==c.seamID,b.seamID==c.seamID,
                  c.aStart==a.a,c.aEnd==b.a,c.bStart==a.b,c.bEnd==b.b,
                  a.normalizedSeamFraction<b.normalizedSeamFraction,
                  c.normalizedSeamRange==(a.normalizedSeamFraction...b.normalizedSeamFraction),
                  c.rightWrong==stitches[c.stitchIndex].rightWrong,
                  paths[a.a.edge]!.segments.contains(c.aSegment),paths[a.b.edge]!.segments.contains(c.bSegment),
                  covers(c.aSegment,a.a,b.a),covers(c.bSegment,a.b,b.b),
                  intervalKeys.insert("\(c.stitchIndex):\(c.startAnchorIndex):\(c.endAnchorIndex)").inserted else {
                throw inputInvalid("连续接触区间超出实际相邻源边界段。")
            }
        }
        for (index,ids) in grouped {
            if isCancelled() {throw CancellationError()}
            let sorted=ids.sorted {plan.anchors[$0].normalizedSeamFraction<plan.anchors[$1].normalizedSeamFraction}
            if isContinuous(intents[index]) {
                if case .eased?=intents[index] {
                    // Every actual eased source knot is explicitly retained;
                    // no sparse tack plan may gain continuous contact rights.
                    let first=plan.anchors[sorted[0]],firstA=first.a.sourceArcFraction==0,firstB=first.b.sourceArcFraction==0
                    let anchorFractions=Set(sorted.map{plan.anchors[$0].normalizedSeamFraction})
                    for (path,forward) in [(paths[first.a.edge]!,firstA),(paths[first.b.edge]!,firstB)] {
                        for (k,f) in path.sourceArcFractions.enumerated() {
                            if k%64==0 && isCancelled(){throw CancellationError()}
                            guard anchorFractions.contains(forward ? f:1-f) else {throw inputInvalid("连续吃势缝遗漏了真实源边界节点。")}
                        }
                    }
                }
                for i in 0..<sorted.count-1 {
                    guard intervalKeys.remove("\(index):\(sorted[i]):\(sorted[i+1])") != nil else {throw inputInvalid("普通接缝遗漏了实际源折线区间。")}
                }
            } else {
                guard plan.usesFiniteCoarseTacks else {throw inputInvalid("吃势／抽褶必须保留有限缝合点声明。")}
                let side:Sewing.Side
                switch intents[index]! {case let .gathered(s,_):side=s;default:throw inputInvalid("只有抽褶可声明未钉折叠自由度。")}
                let relevant=plan.foldIntervals.filter {$0.seamID==plan.anchors[sorted[0]].seamID}
                guard relevant.count==sorted.count-1 else {throw inputInvalid("吃势／抽褶折叠自由度区间不完整。")}
                var ranges=Set<ClosedRange<Double>>()
                for i in 0..<sorted.count-1 {
                    if isCancelled() {throw CancellationError()}
                    let a=plan.anchors[sorted[i]],b=plan.anchors[sorted[i+1]]
                    let start=side == .a ? a.a : a.b,end=side == .a ? b.a : b.b
                    let range=min(start.sourceArcFraction,end.sourceArcFraction)...max(start.sourceArcFraction,end.sourceArcFraction)
                    guard let fold=relevant.first(where:{$0.sourceArcRange==range}),ranges.insert(range).inserted,
                          fold.intent==intents[index],fold.longerEdge==start.edge,(1...16).contains(fold.minimumFreeBoundaryNodes),
                          let p=paths[fold.longerEdge],
                          abs(fold.sourceIntervalLengthMeters-p.sourceLengthMeters*(range.upperBound-range.lowerBound))<1e-10 else {throw inputInvalid("较长源边折叠区间来源无效。")}
                    let free=p.vertexIDs.indices.filter {p.sourceArcFractions[$0]>range.lowerBound+1e-12 && p.sourceArcFractions[$0]<range.upperBound-1e-12}.map {p.vertexIDs[$0]}.filter {!attached.contains($0)}
                    guard free==fold.untackedBoundaryVertexIDs,free.count>=fold.minimumFreeBoundaryNodes,
                          free.allSatisfy({!pinned[$0]}) else {throw inputInvalid("有限缝合点之间的原长折叠节点已被附着、固定或省略。")}
                }
            }
        }
        let gatheredNames=Set(grouped.compactMap {index,ids -> String? in
            if case .gathered?=intents[index] {return plan.anchors[ids[0]].seamID};return nil
        })
        guard intervalKeys.isEmpty,plan.foldIntervals.allSatisfy({gatheredNames.contains($0.seamID)}),
              plan.usesFiniteCoarseTacks == !gatheredNames.isEmpty else {
            throw inputInvalid("计划的粗缝合点标记、折叠区间或连续接触豁免与源接缝意图不一致。")
        }
    }
    nonisolated private static func covers(_ segment:Sewing.BoundarySegment,_ a:Sewing.Location,_ b:Sewing.Location)->Bool {
        let lo=min(a.sourceArcFraction,b.sourceArcFraction),hi=max(a.sourceArcFraction,b.sourceArcFraction)
        return segment.edge==a.edge && segment.edge==b.edge && segment.sourceArcRange.lowerBound<=lo+1e-12 && segment.sourceArcRange.upperBound>=hi-1e-12
    }
}
