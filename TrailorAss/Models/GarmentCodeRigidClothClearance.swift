import Foundation
import CryptoKit

/// Opt-in initialization of independently rigid source panels. The default
/// policy preserves crossing-only behavior; positiveGap additionally separates
/// sampled primitives for a contact-potential bootstrap. Neither is sewing or drape.
nonisolated enum GarmentCodeRigidClothClearance {
    typealias V=GarmentCodeCircleDrape.Vector3
    typealias Body=GarmentCodeRigidBodyClearance
    enum Policy:Codable,Sendable {
        /// Preserves the original crossing-only initialization exactly.
        case crossingOnly
        /// A sampled-mesh bootstrap gap, not fabric thickness or a sewn result.
        case positiveGap
    }
    static let positiveGapTargetMeters=0.00005
    struct Limits:Codable,Sendable {
        var maximumPanels=128,maximumVertices=20_000,maximumTriangles=40_000
        var maximumTrianglePanelTests=10_240_000,maximumTrianglePairTests=10_240_000
        var maximumReportedTrianglePairs=150_000,maximumMoves=127
        var maximumExtraShiftPerPanelMeters=0.05,maximumTotalExtraShiftMeters=0.15
    }
    struct TriangleReference:Codable,Hashable,Sendable {let panelID:String,triangleIndex:Int}
    struct Conflict:Codable,Sendable {
        let first:TriangleReference,second:TriangleReference
        let coplanar:Bool
        var distanceMeters:Double?=nil
    }
    struct Inspection:Codable,Sendable {
        let properTrianglePairs:Int,coplanarTrianglePairs:Int
        let conflicts:[Conflict]
        /// Additional distance-only conflicts; proper/coplanar counts remain separate.
        var nearTrianglePairs:Int?=nil
    }
    struct Support:Codable,Sendable {
        let panelID:String,origin:V,u:V,v:V,normal:V,chosenNormalSign:Double
        let currentPlaneCoordinateMeters:Double,uvBounds:Body.Bounds2,projectionPaddingMeters:Double
        let boundaryDeviationMeters:Double,maximumOtherBoundaryDeviationMeters:Double
        let candidateTriangles:[TriangleReference]
        let minimumOtherNormalCoordinateMeters:Double?,maximumOtherNormalCoordinateMeters:Double?
        let planeDeviationMeters:Double,requiredExtraTranslationMeters:Double
        var projectionMethod:String?=nil
        var fullTriangleBroadCandidates:Int?=nil
    }
    struct Step:Codable,Sendable {
        let selectedPanelID:String,supportOptions:[Support],appliedTranslation:V
        let actualInspectionAfter:Inspection
    }
    struct SupportRefinement:Codable,Sendable {
        let stepIndex:Int
        let refusedRectangleOptions:[Support]
    }
    struct Proof:Codable,Sendable {
        let limits:Limits
        let algorithm:String,bodyGeometrySHA256:String,inputGeometrySHA256:String,outputGeometrySHA256:String
        let requestedClothShellMeters:Double,numericalSeparationReserveMeters:Double
        let maximumExtraShiftPerPanelMeters:Double,maximumTotalExtraShiftMeters:Double
        let initialInspection:Inspection,finalInspection:Inspection,steps:[Step]
        let translationsByPanel:[String:V],totalExtraTranslationMeters:Double
        let trianglePanelTests:Int,trianglePairTests:Int
        let maximumRelativeSourceEdgeLengthChange:Double,maximumRigidTranslationErrorMeters:Double
        let sampledTriangleInitializationOnly:Bool,nearContactsNotCertifiedAbsent:Bool
        var positiveGapTargetMeters:Double?=nil
        var samePanelNonAdjacentPrimitivePairsTested:Int?=nil
        var samePanelZeroDistanceToleranceMeters:Double?=nil
        var supportRefinements:[SupportRefinement]?=nil
        var projectionClipTests:Int?=nil
        var projectionBVHVisits:Int?=nil
        var broadPhaseBuildVisits:Int?=nil
        var broadPhaseSortComparisons:Int?=nil
        var broadPhaseNodeVisits:Int?=nil
        var broadPhaseLeafPairTests:Int?=nil
        var broadPhaseAdditionalBytesUpperBound:Int?=nil
    }
    struct Result:Sendable {let positionsByPanel:[String:[V]],proof:Proof}
    enum ClearanceError:LocalizedError,Sendable {
        case invalid(String),budget(String)
        var errorDescription:String?{switch self{case let .invalid(s):return "刚体布片间隙初始化无效："+s;case let .budget(s):return "刚体布片间隙初始化超过预算："+s}}
    }
    private struct Panel {
        let id:String,indices:[UInt32],frame:Body.PanelProof
    }
    private struct Face {
        let p:[V],normal:V,low:V,high:V
        init(_ p:[V]) {
            self.p=p;let n=(p[1]-p[0]).cross(p[2]-p[0]);normal=n/n.length
            low = .init(x:p.map(\.x).min()!,y:p.map(\.y).min()!,z:p.map(\.z).min()!)
            high = .init(x:p.map(\.x).max()!,y:p.map(\.y).max()!,z:p.map(\.z).max()!)
        }
        func overlaps(_ b:Face)->Bool{low.x<=b.high.x && b.low.x<=high.x && low.y<=b.high.y && b.low.y<=high.y && low.z<=b.high.z && b.low.z<=high.z}
        func distanceLowerBoundSquared(_ b:Face)->Double{boxDistanceSquared(low,high,b.low,b.high)}
    }
    private struct Box {
        let low:V,high:V
        init(_ p:[V]){low = .init(x:p.map(\.x).min()!,y:p.map(\.y).min()!,z:p.map(\.z).min()!);high = .init(x:p.map(\.x).max()!,y:p.map(\.y).max()!,z:p.map(\.z).max()!)}
        func overlaps(_ b:Box)->Bool{low.x<=b.high.x && b.low.x<=high.x && low.y<=b.high.y && b.low.y<=high.y && low.z<=b.high.z && b.low.z<=high.z}
        func distanceLowerBoundSquared(_ b:Box)->Double{boxDistanceSquared(low,high,b.low,b.high)}
    }
    private struct Counts {
        var panel=0,pair=0,clip=0,bvh=0,projectionBVH=0
        var broadBuild=0,broadSort=0,broadNodes=0,broadLeaf=0,broadBytes=0
    }
    private struct FaceNode {let low:V,high:V,left:Int,right:Int,begin:Int,end:Int}
    private struct FaceTree {let nodes:[FaceNode],order:[Int]}
    /// Additional index/query containers only; source Face storage retains the
    /// existing 40,000-triangle limit. This is conservative accounting, not RSS.
    private static let maximumBroadPhaseAdditionalBytes=32*1_024*1_024
    private enum BroadWork {case build,sort,node}
    private static let shell=0.005,reserve=1e-9
    private static func dot(_ a:V,_ b:V)->Double{a.x*b.x+a.y*b.y+a.z*b.z}
    private static func valid(_ p:V)->Bool{p.isFinite && max(abs(p.x),abs(p.y),abs(p.z))<=100}
    /// `bodyCleared` must be the complete preceding body-only result. Frames,
    /// IDs, original UV bounds and final support planes are checked here; the
    /// native factory separately proves canonical paper, mass and source DOFs.
    static func prepare(bodyCleared:Body.Result,trianglesByPanel:[String:[UInt32]],
        policy:Policy = .crossingOnly,limits:Limits = .init(),isCancelled:@Sendable()->Bool={false})throws->Result {
        if isCancelled(){throw CancellationError()}
        guard (1...128).contains(limits.maximumPanels),(3...20_000).contains(limits.maximumVertices),
              (1...40_000).contains(limits.maximumTriangles),(1...10_240_000).contains(limits.maximumTrianglePanelTests),
              (1...10_240_000).contains(limits.maximumTrianglePairTests),(1...150_000).contains(limits.maximumReportedTrianglePairs),
              (0...127).contains(limits.maximumMoves),limits.maximumExtraShiftPerPanelMeters.isFinite,
              limits.maximumTotalExtraShiftMeters.isFinite,(0...0.05).contains(limits.maximumExtraShiftPerPanelMeters),
              (0...0.15).contains(limits.maximumTotalExtraShiftMeters) else{throw ClearanceError.invalid("资源或额外位移上限无效，不能放宽固定上限。")}
        let original=bodyCleared.positionsByPanel,ids=original.keys.sorted(),bodyProof=bodyCleared.proof
        guard !ids.isEmpty,ids.count<=limits.maximumPanels,Set(ids)==Set(trianglesByPanel.keys),
              Set(ids)==Set(bodyProof.panels.map(\.panelID)),bodyProof.panels.count==ids.count,
              bodyProof.bodyOnlyInitializationProof else{throw ClearanceError.invalid("需要完整且未重复的原人体间隙裁片与三角面。")}
        guard original.values.reduce(0,{$0+$1.count})<=limits.maximumVertices,
              trianglesByPanel.values.reduce(0,{$0+$1.count/3})<=limits.maximumTriangles else{throw ClearanceError.budget("完整源网格超限，不能丢片或删面。")}
        var panels:[Panel]=[]
        for id in ids {
            if isCancelled(){throw CancellationError()}
            let p=original[id]!,indices=trianglesByPanel[id]!,f=bodyProof.panels.first{$0.panelID==id}!
            guard p.count>=3,p.allSatisfy(valid),!indices.isEmpty,indices.count%3==0,
                  indices.allSatisfy({Int($0)<p.count}),f.chosenNormalSign==1 || f.chosenNormalSign == -1,
                  f.boundaryDeviationMeters.isFinite,(0...0.001).contains(f.boundaryDeviationMeters),
                  abs(f.u.length-1)<1e-10,abs(f.v.length-1)<1e-10,abs(f.normal.length-1)<1e-10,
                  abs(dot(f.u,f.v))<1e-10,abs(dot(f.u,f.normal))<1e-10,abs(dot(f.v,f.normal))<1e-10 else{throw ClearanceError.invalid("布片顶点、三角索引、既定法向或源边界误差无效。")}
            let origin=p[0],uv=p.map{(dot($0-origin,f.u),dot($0-origin,f.v))},bounds=f.clothBounds
            guard abs(dot(origin,f.normal)-f.finalPlaneCoordinateMeters)<1e-10,
                  p.allSatisfy({abs(dot($0-origin,f.normal))<1e-10}),
                  abs(uv.map(\.0).min()!-bounds.minimumU)<1e-10,abs(uv.map(\.0).max()!-bounds.maximumU)<1e-10,
                  abs(uv.map(\.1).min()!-bounds.minimumV)<1e-10,abs(uv.map(\.1).max()!-bounds.maximumV)<1e-10 else{throw ClearanceError.invalid("输入不是该人体 proof 的完整刚体结果。")}
            var seen=Set<[UInt32]>()
            for offset in stride(from:0,to:indices.count,by:3){
                if offset%768==0 && isCancelled(){throw CancellationError()}
                let t=Array(indices[offset..<offset+3]),a=p[Int(t[0])],b=p[Int(t[1])],c=p[Int(t[2])]
                guard Set(t).count==3,seen.insert(t.sorted()).inserted,(b-a).cross(c-a).length>1e-16 else{throw ClearanceError.invalid("真实源三角面退化或重复。")}
            }
            panels.append(.init(id:id,indices:indices,frame:f))
        }
        var positions=original,counts=Counts(),translations=Dictionary(uniqueKeysWithValues:ids.map{($0,V.zero)})
        let samePanelTests=policy == .positiveGap
            ? try inspectSamePanel(panels,positions,counts:&counts,limits:limits,isCancelled:isCancelled):nil
        var inspection=try inspect(panels,positions,policy:policy,counts:&counts,limits:limits,isCancelled:isCancelled)
        let initial=inspection;var steps:[Step]=[],moved=Set<String>(),total=0.0,refinements:[SupportRefinement]=[]
        while !inspection.conflicts.isEmpty {
            if isCancelled(){throw CancellationError()}
            guard steps.count<min(ids.count-1,limits.maximumMoves) else{throw ClearanceError.budget("已达到 N−1 次刚体移动或调用者更小上限，真实冲突仍存在。")}
            let badIDs=Set(inspection.conflicts.flatMap{[$0.first.panelID,$0.second.panelID]}).sorted()
            var options:[Support]=[]
            for id in badIDs{options.append(try support(panels.first{$0.id==id}!,panels,positions,policy:policy,counts:&counts,limits:limits,isCancelled:isCancelled))}
            var selected=options.min{a,b in a.requiredExtraTranslationMeters==b.requiredExtraTranslationMeters ? a.panelID<b.panelID:a.requiredExtraTranslationMeters<b.requiredExtraTranslationMeters}!
            if policy == .positiveGap && (selected.requiredExtraTranslationMeters>limits.maximumExtraShiftPerPanelMeters+1e-12 || total+selected.requiredExtraTranslationMeters>limits.maximumTotalExtraShiftMeters+1e-12) {
                // No refused translation has been applied. The UV rectangle
                // can cover a source neck opening: refine this support bound
                // against the FULL union of expanded actual source triangles.
                refinements.append(.init(stepIndex:steps.count,refusedRectangleOptions:options))
                options=[]
                for id in badIDs{options.append(try support(panels.first{$0.id==id}!,panels,positions,policy:policy,refineFootprint:true,counts:&counts,limits:limits,isCancelled:isCancelled))}
                selected=options.min{a,b in a.requiredExtraTranslationMeters==b.requiredExtraTranslationMeters ? a.panelID<b.panelID:a.requiredExtraTranslationMeters<b.requiredExtraTranslationMeters}!
            }
            let amount=selected.requiredExtraTranslationMeters
            guard amount>0,amount.isFinite,!moved.contains(selected.panelID) else{throw ClearanceError.invalid("冲突片所需位移为零，或已清除的片重新进入冲突集合。")}
            guard amount<=limits.maximumExtraShiftPerPanelMeters+1e-12,total+amount<=limits.maximumTotalExtraShiftMeters+1e-12 else{
                throw ClearanceError.budget("\(selected.panelID) 最小全布片支持位移 \(amount)m，单片上限 \(limits.maximumExtraShiftPerPanelMeters)m，累计已有 \(total)m；未应用该位移。")
            }
            let delta=selected.normal*(selected.chosenNormalSign*amount),oldPairs=Set(inspection.conflicts.map{pairKey($0.first.panelID,$0.second.panelID)})
            positions[selected.panelID]=positions[selected.panelID]!.map{$0+delta}
            guard positions[selected.panelID]!.allSatisfy(valid) else{throw ClearanceError.invalid("额外刚体平移坐标溢出。")}
            translations[selected.panelID]=delta;total += amount;moved.insert(selected.panelID)
            inspection=try inspect(panels,positions,policy:policy,counts:&counts,limits:limits,isCancelled:isCancelled)
            let newPairs=Set(inspection.conflicts.map{pairKey($0.first.panelID,$0.second.panelID)})
            guard newPairs.isSubset(of:oldPairs),newPairs.count<oldPairs.count,
                  !inspection.conflicts.contains(where:{$0.first.panelID==selected.panelID || $0.second.panelID==selected.panelID}) else{
                throw ClearanceError.invalid("全支持平移未能严格减少冲突，不能隐藏剩余交叉。")
            }
            steps.append(.init(selectedPanelID:selected.panelID,supportOptions:options,appliedTranslation:delta,actualInspectionAfter:inspection))
        }
        var edgeChange=0.0,rigidError=0.0
        for panel in panels {
            if isCancelled(){throw CancellationError()}
            let a=original[panel.id]!,b=positions[panel.id]!,delta=translations[panel.id]!
            for i in a.indices{rigidError=max(rigidError,(b[i]-a[i]-delta).length)}
            for offset in stride(from:0,to:panel.indices.count,by:3){for k in 0..<3{
                let i=Int(panel.indices[offset+k]),j=Int(panel.indices[offset+(k+1)%3]),before=(a[i]-a[j]).length
                edgeChange=max(edgeChange,abs((b[i]-b[j]).length/before-1))
            }}
        }
        guard edgeChange<1e-10,rigidError<1e-10 else{throw ClearanceError.invalid("最终结果改变源长度或不再是逐片刚体平移。")}
        if isCancelled(){throw CancellationError()}
        return .init(positionsByPanel:positions,proof:.init(limits:limits,algorithm:policy == .crossingOnly ? "Actual inter-panel proper/coplanar conflicts; all-other-triangle conservative UV support; fixed body-outward sign; monotonically decreasing bad pairs; no near-contact/physical certification":"Actual inter-panel proper/coplanar or distance-bound conflicts; complete six VF/nine EE triangle distance; all-other conservative UV support; fixed body-outward sign; monotone bad pairs; positive sampled bootstrap only",
            bodyGeometrySHA256:bodyProof.bodyGeometrySHA256,inputGeometrySHA256:geometryHash(panels,original),outputGeometrySHA256:geometryHash(panels,positions),
            requestedClothShellMeters:policy == .crossingOnly ? shell:positiveGapTargetMeters,numericalSeparationReserveMeters:reserve,maximumExtraShiftPerPanelMeters:limits.maximumExtraShiftPerPanelMeters,maximumTotalExtraShiftMeters:limits.maximumTotalExtraShiftMeters,
            initialInspection:initial,finalInspection:inspection,steps:steps,translationsByPanel:translations,totalExtraTranslationMeters:total,trianglePanelTests:counts.panel+counts.bvh,trianglePairTests:counts.pair+counts.clip,
            maximumRelativeSourceEdgeLengthChange:edgeChange,maximumRigidTranslationErrorMeters:rigidError,sampledTriangleInitializationOnly:true,nearContactsNotCertifiedAbsent:policy == .crossingOnly,
            positiveGapTargetMeters:policy == .positiveGap ? positiveGapTargetMeters:nil,
            samePanelNonAdjacentPrimitivePairsTested:samePanelTests,samePanelZeroDistanceToleranceMeters:policy == .positiveGap ? 1e-8:nil,
            supportRefinements:refinements.isEmpty ? nil:refinements,projectionClipTests:refinements.isEmpty ? nil:counts.clip,projectionBVHVisits:refinements.isEmpty ? nil:counts.projectionBVH,
            broadPhaseBuildVisits:counts.broadBuild,broadPhaseSortComparisons:counts.broadSort,broadPhaseNodeVisits:counts.broadNodes,
            broadPhaseLeafPairTests:counts.broadLeaf,broadPhaseAdditionalBytesUpperBound:counts.broadBytes))
    }
    private static func pairKey(_ a:String,_ b:String)->String{a<b ? a+"\0"+b:b+"\0"+a}
    private struct UV {let u:Double,v:Double}
    private struct FootprintFace {let uv:[UV],bounds:Body.Bounds2}
    private struct FootprintNode {let bounds:Body.Bounds2,left:Int,right:Int,begin:Int,end:Int}
    private struct Footprint {let faces:[FootprintFace],order:[Int],nodes:[FootprintNode]}
    private static func projectionVisit(_ counts:inout Counts,_ limits:Limits,_ isCancelled:@Sendable()->Bool)throws {
        counts.bvh += 1
        counts.projectionBVH += 1
        guard counts.panel+counts.bvh<=limits.maximumTrianglePanelTests else{throw ClearanceError.budget("源足迹构造／查询与全部三角面支持超过原总预算。")}
        if counts.bvh%128==0 && isCancelled(){throw CancellationError()}
    }
    private static func broadVisit(_ work:BroadWork,_ counts:inout Counts,_ limits:Limits,_ isCancelled:@Sendable()->Bool)throws {
        counts.bvh += 1
        switch work {case .build:counts.broadBuild += 1;case .sort:counts.broadSort += 1;case .node:counts.broadNodes += 1}
        guard counts.panel+counts.bvh<=limits.maximumTrianglePanelTests else {
            throw ClearanceError.budget("完整布片空间索引构建、排序与查询超过原三角面支持总预算。")
        }
        if counts.bvh%128==0 && isCancelled(){throw CancellationError()}
    }
    /// Every operation rounds the nonnegative bound downward. Monotonicity
    /// also makes this no greater than the original Float64 Face-box bound
    /// for any descendant, including a threshold tie. Unknown stays a candidate.
    private static func broadDistanceLowerSquared(_ low:V,_ high:V,_ otherLow:V,_ otherHigh:V)->Double {
        func axis(_ a:Double,_ b:Double,_ c:Double,_ d:Double)->Double {
            max(0,max((a-d).nextDown,(c-b).nextDown))
        }
        func square(_ x:Double)->Double {max(0,(x*x).nextDown)}
        let x=square(axis(low.x,high.x,otherLow.x,otherHigh.x)),y=square(axis(low.y,high.y,otherLow.y,otherHigh.y)),z=square(axis(low.z,high.z,otherLow.z,otherHigh.z))
        return max(0,(max(0,(x+y).nextDown)+z).nextDown)
    }
    private static func buildFaceTree(_ faces:[Face],counts:inout Counts,limits:Limits,isCancelled:@Sendable()->Bool)throws->FaceTree {
        var order=Array(faces.indices),nodes:[FaceNode]=[]
        nodes.reserveCapacity(2*faces.count)
        func build(_ begin:Int,_ end:Int)throws->Int {
            try broadVisit(.build,&counts,limits,isCancelled)
            var low=V(x:.infinity,y:.infinity,z:.infinity),high=V(x:-Double.infinity,y:-Double.infinity,z:-Double.infinity)
            for i in begin..<end {
                try broadVisit(.build,&counts,limits,isCancelled)
                let f=faces[order[i]]
                low = .init(x:min(low.x,f.low.x),y:min(low.y,f.low.y),z:min(low.z,f.low.z))
                high = .init(x:max(high.x,f.high.x),y:max(high.y,f.high.y),z:max(high.z,f.high.z))
            }
            let index=nodes.count
            guard index<2*faces.count else{throw ClearanceError.budget("完整布片空间索引节点超过源三角面有界数量。")}
            nodes.append(.init(low:low,high:high,left:-1,right:-1,begin:begin,end:end))
            if end-begin<=8{return index}
            let extent=high-low,axis=extent.x>=extent.y ? (extent.x>=extent.z ? 0:2):(extent.y>=extent.z ? 1:2)
            func center(_ id:Int)->Double {
                let f=faces[id]
                return axis==0 ? f.low.x+f.high.x:(axis==1 ? f.low.y+f.high.y:f.low.z+f.high.z)
            }
            try order[begin..<end].sort { a,b in
                try broadVisit(.sort,&counts,limits,isCancelled)
                let x=center(a),y=center(b);return x==y ? a<b:x<y
            }
            let middle=(begin+end)/2,left=try build(begin,middle),right=try build(middle,end)
            nodes[index] = .init(low:low,high:high,left:left,right:right,begin:begin,end:end)
            return index
        }
        _=try build(0,order.count)
        return .init(nodes:nodes,order:order)
    }
    private static func faceCandidates(_ face:Face,_ tree:FaceTree,positive:Bool,counts:inout Counts,limits:Limits,isCancelled:@Sendable()->Bool)throws->[Int] {
        var stack=[0],result:[Int]=[]
        result.reserveCapacity(tree.order.count)
        let threshold=positiveGapTargetMeters*positiveGapTargetMeters
        while let index=stack.popLast() {
            try broadVisit(.node,&counts,limits,isCancelled)
            let node=tree.nodes[index]
            if positive {
                if broadDistanceLowerSquared(face.low,face.high,node.low,node.high)>threshold{continue}
            } else if face.low.x>node.high.x || node.low.x>face.high.x || face.low.y>node.high.y || node.low.y>face.high.y || face.low.z>node.high.z || node.low.z>face.high.z {continue}
            if node.left<0 {
                for i in node.begin..<node.end {result.append(tree.order[i])}
            } else {stack.append(node.right);stack.append(node.left)}
            guard stack.count<=tree.nodes.count,result.count<=tree.order.count else{throw ClearanceError.budget("布片空间索引查询栈或临时候选超过完整源数量。")}
        }
        // The old i,j ordering determines conflict and source-move receipts.
        // Sorting is itself charged and cancellable; no full Cartesian list.
        try result.sort { a,b in try broadVisit(.sort,&counts,limits,isCancelled);return a<b }
        return result
    }
    private static func buildFootprint(_ selected:Panel,_ p:[V],_ origin:V,_ u:V,_ v:V,
        counts:inout Counts,limits:Limits,isCancelled:@Sendable()->Bool)throws->Footprint {
        var faces:[FootprintFace]=[]
        for offset in stride(from:0,to:selected.indices.count,by:3){
            try projectionVisit(&counts,limits,isCancelled)
            let uv=(0..<3).map{let d=p[Int(selected.indices[offset+$0])]-origin;return UV(u:dot(d,u),v:dot(d,v))}
            let area=(uv[1].u-uv[0].u)*(uv[2].v-uv[0].v)-(uv[1].v-uv[0].v)*(uv[2].u-uv[0].u)
            guard area.isFinite,abs(area)>1e-20 else{throw ClearanceError.invalid("源足迹投影退化或不明，不能裁剪支持界。")}
            faces.append(.init(uv:uv,bounds:.init(minimumU:uv.map(\.u).min()!,maximumU:uv.map(\.u).max()!,minimumV:uv.map(\.v).min()!,maximumV:uv.map(\.v).max()!)))
        }
        var order=Array(faces.indices),nodes:[FootprintNode]=[]
        func build(_ begin:Int,_ end:Int)throws->Int {
            try projectionVisit(&counts,limits,isCancelled)
            var loU=Double.infinity,hiU = -Double.infinity,loV=Double.infinity,hiV = -Double.infinity
            for i in begin..<end {
                try projectionVisit(&counts,limits,isCancelled)
                let b=faces[order[i]].bounds;loU=min(loU,b.minimumU);hiU=max(hiU,b.maximumU);loV=min(loV,b.minimumV);hiV=max(hiV,b.maximumV)
            }
            let bounds=Body.Bounds2(minimumU:loU,maximumU:hiU,minimumV:loV,maximumV:hiV),id=nodes.count
            guard nodes.count<2*limits.maximumTriangles else{throw ClearanceError.budget("完整源足迹树节点超限。")}
            nodes.append(.init(bounds:bounds,left:-1,right:-1,begin:begin,end:end))
            if end-begin<=8{return id}
            let axisU=hiU-loU>=hiV-loV
            order[begin..<end].sort { a,b in
                let x=faces[a].bounds,y=faces[b].bounds,xc=axisU ? x.minimumU+x.maximumU:x.minimumV+x.maximumV,yc=axisU ? y.minimumU+y.maximumU:y.minimumV+y.maximumV
                return xc==yc ? a<b:xc<yc
            }
            let mid=(begin+end)/2,left=try build(begin,mid),right=try build(mid,end)
            nodes[id] = .init(bounds:bounds,left:left,right:right,begin:begin,end:end)
            return id
        }
        _=try build(0,order.count)
        return .init(faces:faces,order:order,nodes:nodes)
    }
    private static func footprintCandidates(_ tree:Footprint,_ box:Body.Bounds2,_ padding:Double,
        counts:inout Counts,limits:Limits,isCancelled:@Sendable()->Bool)throws->[Int] {
        func overlaps(_ b:Body.Bounds2)->Bool {
            b.minimumU<=box.maximumU+padding && box.minimumU<=b.maximumU+padding && b.minimumV<=box.maximumV+padding && box.minimumV<=b.maximumV+padding
        }
        var stack=[0],result:[Int]=[]
        while let index=stack.popLast() {
            try projectionVisit(&counts,limits,isCancelled)
            let node=tree.nodes[index]
            if !overlaps(node.bounds){continue}
            if node.left<0 {
                for i in node.begin..<node.end {
                    try projectionVisit(&counts,limits,isCancelled)
                    let face=tree.order[i]
                    if overlaps(tree.faces[face].bounds){result.append(face)}
                }
            }else{stack.append(node.right);stack.append(node.left)}
        }
        return result.sorted()
    }
    /// Clip the ENTIRE other 3D triangle against all three vertical halfplanes
    /// of an outward-expanded source footprint. Projection can be a line/point;
    /// no projected-vertex sampling or original full-triangle extrema shortcut.
    private static func clip(_ triangle:[V],to source:[UV],origin:V,u:V,v:V,padding:Double)throws->[V] {
        let area=(source[1].u-source[0].u)*(source[2].v-source[0].v)-(source[1].v-source[0].v)*(source[2].u-source[0].u)
        guard area.isFinite,abs(area)>1e-20,padding.isFinite,padding>0 else{throw ClearanceError.invalid("源足迹半平面无效。")}
        let sign=area>0 ? 1.0:-1.0
        var polygon=triangle
        for i in 0..<3 {
            let a=source[i],b=source[(i+1)%3],eu=b.u-a.u,ev=b.v-a.v,length=hypot(eu,ev)
            guard length.isFinite,length>0 else{throw ClearanceError.invalid("源足迹边退化。")}
            func value(_ point:V)->Double {
                let d=point-origin,pu=dot(d,u),pv=dot(d,v)
                return sign*(eu*(pv-a.v)-ev*(pu-a.u))+padding*length
            }
            let old=polygon;polygon=[]
            if old.isEmpty{return []}
            for j in old.indices {
                let x=old[j],y=old[(j+1)%old.count],dx=value(x),dy=value(y)
                guard dx.isFinite,dy.isFinite else{throw ClearanceError.invalid("三维支持裁剪计算失败。")}
                if dx>=0{polygon.append(x)}
                if (dx>=0) != (dy>=0) {
                    let denominator=dx-dy,t=dx/denominator
                    guard denominator.isFinite,denominator != 0,t.isFinite,t>=0,t<=1 else{throw ClearanceError.invalid("三维支持交点不明，未丢弃片段。")}
                    let q=x+(y-x)*t
                    guard valid(q) else{throw ClearanceError.invalid("三维支持交点溢出。")}
                    polygon.append(q)
                }
            }
            guard polygon.count<=12 else{throw ClearanceError.budget("三角面／半平面裁剪顶点超出完整凸多边形预算。")}
        }
        return polygon
    }
    private static func support(_ selected:Panel,_ panels:[Panel],_ positions:[String:[V]],policy:Policy,refineFootprint:Bool=false,counts:inout Counts,limits:Limits,isCancelled:@Sendable()->Bool)throws->Support {
        let f=selected.frame,p=positions[selected.id]!,origin=p[0],n=f.normal,u=f.u,v=f.v,plane=dot(n,origin)
        let uv=p.map{(dot($0-origin,u),dot($0-origin,v))},bounds=Body.Bounds2(minimumU:uv.map(\.0).min()!,maximumU:uv.map(\.0).max()!,minimumV:uv.map(\.1).min()!,maximumV:uv.map(\.1).max()!)
        let separation=policy == .crossingOnly ? shell:positiveGapTargetMeters
        let error=panels.filter{$0.id != selected.id}.map{$0.frame.boundaryDeviationMeters}.max() ?? 0,padding=separation+reserve+f.boundaryDeviationMeters+error
        let deviation=p.map{abs(dot($0-origin,n))}.max() ?? 0
        let footprint=refineFootprint ? try buildFootprint(selected,p,origin,u,v,counts:&counts,limits:limits,isCancelled:isCancelled):nil
        var low=Double.infinity,high = -Double.infinity,candidates:[TriangleReference]=[]
        var broadCandidates=0
        for other in panels where other.id != selected.id {
            let points=positions[other.id]!,e=other.frame.boundaryDeviationMeters
            for offset in stride(from:0,to:other.indices.count,by:3){
                counts.panel += 1
                guard counts.panel+counts.bvh<=limits.maximumTrianglePanelTests else{throw ClearanceError.budget("完整其他三角面与投影树支持测试超限，未省略候选。")}
                if counts.panel%128==0 && isCancelled(){throw CancellationError()}
                let q=(0..<3).map{points[Int(other.indices[offset+$0])]},us=q.map{dot($0-origin,u)},vs=q.map{dot($0-origin,v)}
                if us.max()!<bounds.minimumU-padding || us.min()!>bounds.maximumU+padding || vs.max()!<bounds.minimumV-padding || vs.min()!>bounds.maximumV+padding {continue}
                broadCandidates += 1
                let supportedPoints:[V]
                if let footprint {
                    let box=Body.Bounds2(minimumU:us.min()!,maximumU:us.max()!,minimumV:vs.min()!,maximumV:vs.max()!)
                    let hits=try footprintCandidates(footprint,box,padding,counts:&counts,limits:limits,isCancelled:isCancelled)
                    var clipped:[V]=[]
                    for hit in hits {
                        counts.clip += 1
                        guard counts.pair+counts.clip<=limits.maximumTrianglePairTests else{throw ClearanceError.budget("完整源足迹裁剪与三角面对检查超过原总预算。")}
                        if counts.clip%128==0 && isCancelled(){throw CancellationError()}
                        clipped += try clip(q,to:footprint.faces[hit].uv,origin:origin,u:u,v:v,padding:padding)
                    }
                    if clipped.isEmpty{continue}
                    supportedPoints=clipped
                }else{supportedPoints=q}
                candidates.append(.init(panelID:other.id,triangleIndex:offset/3))
                for point in supportedPoints{let d=dot(point,n);low=min(low,d-e);high=max(high,d+e)}
            }
        }
        let amount:Double
        if candidates.isEmpty{amount=0}
        else if f.chosenNormalSign>0{amount=max(0,high+separation+reserve+deviation-plane)}
        else{amount=max(0,plane-(low-separation-reserve-deviation))}
        return .init(panelID:selected.id,origin:origin,u:u,v:v,normal:n,chosenNormalSign:f.chosenNormalSign,currentPlaneCoordinateMeters:plane,
            uvBounds:bounds,projectionPaddingMeters:padding,boundaryDeviationMeters:f.boundaryDeviationMeters,maximumOtherBoundaryDeviationMeters:error,candidateTriangles:candidates,
            minimumOtherNormalCoordinateMeters:candidates.isEmpty ? nil:low,maximumOtherNormalCoordinateMeters:candidates.isEmpty ? nil:high,planeDeviationMeters:deviation,requiredExtraTranslationMeters:amount,
            projectionMethod:refineFootprint ? "all-source-triangle-expanded-halfplanes":nil,fullTriangleBroadCandidates:refineFootprint ? broadCandidates:nil)
    }
    private static func inspect(_ panels:[Panel],_ positions:[String:[V]],policy:Policy,counts:inout Counts,limits:Limits,isCancelled:@Sendable()->Bool)throws->Inspection {
        let faceCount=panels.reduce(0){$0+$1.indices.count/3},maximumPanelFaces=panels.map{$0.indices.count/3}.max() ?? 0
        // Reserve node capacity, order arrays, both sorting scratch buffers,
        // current candidates/query stack, container headers and recursion.
        // A factor of two covers allocator capacity rounding. No global cache.
        let additionalBytes=2*(2*faceCount*MemoryLayout<FaceNode>.stride+3*faceCount*MemoryLayout<Int>.stride+2*maximumPanelFaces*MemoryLayout<Int>.stride+panels.count*4_096+131_072)
        guard additionalBytes<=maximumBroadPhaseAdditionalBytes else{throw ClearanceError.budget("完整布片空间索引与临时排序／查询内存超过固定 32 MiB 上限。")}
        counts.broadBytes=max(counts.broadBytes,additionalBytes)
        var faces:[[Face]]=[],boxes:[Box]=[]
        for panel in panels{
            let p=positions[panel.id]!,f=stride(from:0,to:panel.indices.count,by:3).map{offset in Face((0..<3).map{p[Int(panel.indices[offset+$0])]})}
            faces.append(f)
            boxes.append(Box(p))
        }
        var trees:[FaceTree]=[];trees.reserveCapacity(panels.count)
        for f in faces{trees.append(try buildFaceTree(f,counts:&counts,limits:limits,isCancelled:isCancelled))}
        var conflicts:[Conflict]=[],proper=0,coplanar=0,near=0
        let positive=policy == .positiveGap,thresholdSquared=positiveGapTargetMeters*positiveGapTargetMeters
        for a in panels.indices{for b in panels.indices where b>a{
            if isCancelled(){throw CancellationError()}
            if positive ? boxes[a].distanceLowerBoundSquared(boxes[b])>thresholdSquared:!boxes[a].overlaps(boxes[b]){continue}
            for (i,x) in faces[a].enumerated(){
                let candidates=try faceCandidates(x,trees[b],positive:positive,counts:&counts,limits:limits,isCancelled:isCancelled)
                for j in candidates {
                let y=faces[b][j]
                counts.pair += 1
                counts.broadLeaf += 1
                guard counts.pair+counts.clip<=limits.maximumTrianglePairTests else{throw ClearanceError.budget("完整三角面对与源足迹裁剪测试超限，未隐藏剩余冲突。")}
                if counts.pair%128==0 && isCancelled(){throw CancellationError()}
                if positive ? x.distanceLowerBoundSquared(y)>thresholdSquared:!x.overlaps(y){continue}
                let planar=coplanarOverlap(x,y)
                let properHit=planar ? false:properCross(x,y)
                let distanceSquared=positive ? triangleDistanceSquared(x,y):nil
                if let distanceSquared {
                    guard distanceSquared.isFinite,distanceSquared>=0 else{throw ClearanceError.invalid("真实三角面距离计算失败，未视为无接触。")}
                }
                let nearHit=distanceSquared.map{$0<=thresholdSquared} ?? false
                if planar || properHit || nearHit{
                    guard conflicts.count<limits.maximumReportedTrianglePairs else{throw ClearanceError.budget("完整冲突记录超限，不能截断。")}
                    if planar{coplanar += 1}else if properHit{proper += 1}else{near += 1}
                    conflicts.append(.init(first:.init(panelID:panels[a].id,triangleIndex:i),second:.init(panelID:panels[b].id,triangleIndex:j),coplanar:planar,distanceMeters:distanceSquared.map(sqrt)))
                }
            }}
        }}
        return .init(properTrianglePairs:proper,coplanarTrianglePairs:coplanar,conflicts:conflicts,nearTrianglePairs:positive ? near:nil)
    }
    private static func boxDistanceSquared(_ low:V,_ high:V,_ otherLow:V,_ otherHigh:V)->Double {
        let x=max(0,max(low.x-otherHigh.x,otherLow.x-high.x))
        let y=max(0,max(low.y-otherHigh.y,otherLow.y-high.y))
        let z=max(0,max(low.z-otherHigh.z,otherLow.z-high.z))
        return x*x+y*y+z*z
    }
    private static func pointTriangleDistanceSquared(_ p:V,_ a:V,_ b:V,_ c:V)->Double {
        let ab=b-a,ac=c-a,ap=p-a,d1=dot(ab,ap),d2=dot(ac,ap)
        if d1<=0 && d2<=0{return dot(ap,ap)}
        let bp=p-b,d3=dot(ab,bp),d4=dot(ac,bp)
        if d3>=0 && d4<=d3{return dot(bp,bp)}
        let vc=d1*d4-d3*d2
        if vc<=0 && d1>=0 && d3<=0{let q=p-(a+ab*(d1/(d1-d3)));return dot(q,q)}
        let cp=p-c,d5=dot(ab,cp),d6=dot(ac,cp)
        if d6>=0 && d5<=d6{return dot(cp,cp)}
        let vb=d5*d2-d1*d6
        if vb<=0 && d2>=0 && d6<=0{let q=p-(a+ac*(d2/(d2-d6)));return dot(q,q)}
        let va=d3*d6-d5*d4
        if va<=0 && d4-d3>=0 && d5-d6>=0{let q=p-(b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6))));return dot(q,q)}
        let denominator=va+vb+vc,q=p-(a+ab*(vb/denominator)+ac*(vc/denominator))
        return dot(q,q)
    }
    private static func edgeDistanceSquared(_ a:V,_ b:V,_ c:V,_ d:V)->Double {
        let u=b-a,v=d-c,r=a-c,aa=dot(u,u),ee=dot(v,v),f=dot(v,r)
        guard aa>0,ee>0 else{return .nan}
        let cc=dot(u,r),bb=dot(u,v),denominator=aa*ee-bb*bb
        var s=denominator>0 ? min(1,max(0,(bb*f-cc*ee)/denominator)):0.0
        var t=(bb*s+f)/ee
        if t<0{t=0;s=min(1,max(0,-cc/aa))}
        else if t>1{t=1;s=min(1,max(0,(bb-cc)/aa))}
        let q=(a+u*s)-(c+v*t);return dot(q,q)
    }
    /// All six VF and nine EE features are needed: two long edges can meet
    /// while no vertex projects into the other face. No source seam mask.
    private static func triangleDistanceSquared(_ a:Face,_ b:Face)->Double {
        var result=Double.infinity
        for i in 0..<3{
            result=min(result,pointTriangleDistanceSquared(a.p[i],b.p[0],b.p[1],b.p[2]))
            result=min(result,pointTriangleDistanceSquared(b.p[i],a.p[0],a.p[1],a.p[2]))
            for j in 0..<3{result=min(result,edgeDistanceSquared(a.p[i],a.p[(i+1)%3],b.p[j],b.p[(j+1)%3]))}
        }
        return result
    }
    /// A rigid shift cannot repair zero-distance source topology within one
    /// panel. Exclude only actual shared primitive IDs; reject distinct IDs.
    private static func inspectSamePanel(_ panels:[Panel],_ positions:[String:[V]],counts:inout Counts,limits:Limits,
        isCancelled:@Sendable()->Bool)throws->Int {
        let toleranceSquared=1e-16
        var primitiveTests=0
        for panel in panels {
            if isCancelled(){throw CancellationError()}
            let p=positions[panel.id]!,ids=stride(from:0,to:panel.indices.count,by:3).map{Array(panel.indices[$0..<$0+3])}
            let faces=ids.map{Face($0.map{p[Int($0)]})},order=faces.indices.sorted{faces[$0].low.x==faces[$1].low.x ? $0<$1:faces[$0].low.x<faces[$1].low.x}
            for ii in order.indices {
                let i=order[ii],a=faces[i],ai=ids[i]
                var jj=ii+1
                while jj<order.count {
                    let j=order[jj],b=faces[j],bi=ids[j];jj += 1
                    if b.low.x>a.high.x+1e-8{break}
                    if a.distanceLowerBoundSquared(b)>toleranceSquared{continue}
                    counts.pair += 1
                    guard counts.pair+counts.clip<=limits.maximumTrianglePairTests else{throw ClearanceError.budget("同片非邻接原语与源足迹裁剪超过原三角面对预算，未跳过源拓扑。")}
                    if counts.pair%128==0 && isCancelled(){throw CancellationError()}
                    for k in 0..<3 {
                        if !bi.contains(ai[k]) {
                            primitiveTests += 1
                            let d=pointTriangleDistanceSquared(a.p[k],b.p[0],b.p[1],b.p[2])
                            guard d.isFinite,d>toleranceSquared else{throw ClearanceError.invalid("\(panel.id) 同片独立顶点/三角面距离为零或小于数值容差，不能用刚体平移或接缝豁免隐藏。")}
                        }
                        if !ai.contains(bi[k]) {
                            primitiveTests += 1
                            let d=pointTriangleDistanceSquared(b.p[k],a.p[0],a.p[1],a.p[2])
                            guard d.isFinite,d>toleranceSquared else{throw ClearanceError.invalid("\(panel.id) 同片独立顶点/三角面距离为零或小于数值容差，不能用刚体平移或接缝豁免隐藏。")}
                        }
                        for l in 0..<3 {
                            let ae=[ai[k],ai[(k+1)%3]],be=[bi[l],bi[(l+1)%3]]
                            if ae.contains(where:be.contains){continue}
                            primitiveTests += 1
                            let d=edgeDistanceSquared(a.p[k],a.p[(k+1)%3],b.p[l],b.p[(l+1)%3])
                            guard d.isFinite,d>toleranceSquared else{throw ClearanceError.invalid("\(panel.id) 同片无共享源 ID 的边间距离为零或小于数值容差。")}
                        }
                    }
                }
            }
        }
        return primitiveTests
    }
    private static func properCross(_ a:Face,_ b:Face)->Bool {
        let line=a.normal.cross(b.normal),length=line.length
        if length<1e-12{return false}
        let axis=line/length,da=a.p.map{dot($0-b.p[0],b.normal)},db=b.p.map{dot($0-a.p[0],a.normal)},epsilon=1e-9
        guard da.min()! < -epsilon,da.max()!>epsilon,db.min()! < -epsilon,db.max()!>epsilon else{return false}
        func interval(_ p:[V],_ d:[Double])->(Double,Double)?{
            var values:[Double]=[]
            for i in 0..<3{let j=(i+1)%3;if abs(d[i])<=epsilon{values.append(dot(p[i],axis))};if d[i]*d[j]<0{values.append(dot(p[i]+(p[j]-p[i])*(d[i]/(d[i]-d[j])),axis))}}
            guard let low=values.min(),let high=values.max() else{return nil};return(low,high)
        }
        guard let x=interval(a.p,da),let y=interval(b.p,db) else{return false}
        return min(x.1,y.1)-max(x.0,y.0)>1e-7
    }
    private static func coplanarOverlap(_ a:Face,_ b:Face)->Bool {
        guard a.normal.cross(b.normal).length<=1e-10,abs(dot(b.p[0]-a.p[0],a.normal))<=1e-9 else{return false}
        let n=a.normal,axis=abs(n.x)>abs(n.y) ? (abs(n.x)>abs(n.z) ? 0:2):(abs(n.y)>abs(n.z) ? 1:2)
        func p(_ v:V)->(Double,Double){axis==0 ? (v.y,v.z):(axis==1 ? (v.x,v.z):(v.x,v.y))}
        func cross(_ a:(Double,Double),_ b:(Double,Double),_ c:(Double,Double))->Double{(b.0-a.0)*(c.1-a.1)-(b.1-a.1)*(c.0-a.0)}
        let target=b.p.map(p),sign=cross(target[0],target[1],target[2])>0 ? 1.0:-1.0
        var polygon=a.p.map(p)
        for i in 0..<3{
            let old=polygon;polygon=[];if old.isEmpty{return false}
            for j in old.indices{let u=old[j],v=old[(j+1)%old.count],du=sign*cross(target[i],target[(i+1)%3],u),dv=sign*cross(target[i],target[(i+1)%3],v)
                if du>=0{polygon.append(u)};if (du>=0) != (dv>=0){let t=du/(du-dv);polygon.append((u.0+t*(v.0-u.0),u.1+t*(v.1-u.1)))}
            }
        }
        guard polygon.count>=3 else{return false}
        var area=0.0;for i in 1..<(polygon.count-1){area += cross(polygon[0],polygon[i],polygon[i+1])}
        return abs(area)/2>1e-14
    }
    private static func geometryHash(_ panels:[Panel],_ positions:[String:[V]])->String {
        var bytes=Data("rigid-cloth-support-input-v1\0".utf8)
        for p in panels{bytes.append(Data(p.id.utf8));bytes.append(0);bytes.append(Data(Body.geometrySHA256(positions:positions[p.id]!,indices:p.indices).utf8))}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
}
