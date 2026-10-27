import Foundation
import CryptoKit

/// Optional fixed-body pose preparation. No existing body/SDF or App route is
/// replaced. Bone proxies are not anthropometric surface measurements.
nonisolated enum GarmentCodeBodyRig {
    typealias V = GarmentCodeCircleDrape.Vector3
    typealias C = GarmentCodeClothContact
    struct Limits: Sendable {
        var maximumResourceBytes = 8_000_000
        var maximumVertices = 40_000
        var maximumTriangles = 80_000
        var maximumBones = 512
        var maximumJointReferences = 10_000
        var maximumWeightPairs = 200_000
        var maximumCandidatePairs = 300_000
    }
    enum Pose: Sendable { case identity, arms(alphaDegrees: Double) }
    enum RigError: LocalizedError, Sendable {
        case invalid(String), budgetExceeded
        var errorDescription: String? {
            switch self {case let .invalid(s): return "可选人体姿态无效："+s
            case .budgetExceeded: return "可选人体姿态超出本轮资源或检查预算。"}
        }
    }
    struct BoneTransform: Codable, Sendable {
        let name: String
        let rotationZRadians: Double
        let pivot: V
        func apply(_ p: V) -> V {
            if rotationZRadians == 0 { return p }
            return p+displacement(p)
        }
        func displacement(_ p:V)->V {
            if rotationZRadians == 0 {return .zero}
            let q=p-pivot,c=cos(rotationZRadians)-1,s=sin(rotationZRadians)
            return .init(x:c*q.x-s*q.y,y:s*q.x+c*q.y,z:0)
        }
    }
    struct Statistics: Codable, Sendable {
        let vertexCount: Int, triangleCount: Int, boneCount: Int, jointCount: Int
        let retainedWeightPairs: Int, maximumInfluencesPerVertex: Int
        let minimumTriangleCrossSquaredMeters4: Double
        let minimumReferenceNormalDot: Double
        let signedVolumeCubicMeters: Double
        let selfInspection: C.Quality
    }
    struct ValidatedBody: Sendable {
        let positions: [V]
        let triangleIndices: [UInt32]
        let geometrySHA256: String
        let jointAnchors: [V]
        let boneTransforms: [BoneTransform]
        let statistics: Statistics
        /// This capability is for fixed-body preparation, not animated body
        /// replacement or proof of personal measurements.
        let compatibleWithLegacyInverseSDF: Bool
        fileprivate init(positions:[V],triangleIndices:[UInt32],geometrySHA256:String,
                         jointAnchors:[V],boneTransforms:[BoneTransform],statistics:Statistics,identity:Bool) {
            self.positions=positions;self.triangleIndices=triangleIndices;self.geometrySHA256=geometrySHA256
            self.jointAnchors=jointAnchors;self.boneTransforms=boneTransforms;self.statistics=statistics
            compatibleWithLegacyInverseSDF=identity
        }
    }
    struct Attempt: Sendable {
        let validatedBody: ValidatedBody?
        let diagnosticPositions: [V]
        let diagnosticJointAnchors: [V]
        let statistics: Statistics
        let rejectionReasons: [String]
        let geometrySHA256: String
        let independentSurfaceFittingImplemented = false
        let boundedWarpInputFields = ["height","waist","hips","hips_line","_waist_level"]
        let notIndependentlyFittedBodyFields = ["arm_length","arm_pose_angle","armscye_depth","back_width","bum_points","bust","bust_line","bust_points","crotch_hip_diff","head_l","height","hip_back_width","hip_inclination","hips","hips_line","leg_circ","neck_w","shoulder_incl","shoulder_w","underbust","vert_bust_line","waist","waist_back_width","waist_line","waist_over_bust_line","wrist"]
        let selfInspectionExcludesTrianglesSharingAnyVertex = true
        var fixedBodyPreparationAllowed: Bool { validatedBody != nil }
    }
    private struct Template: Decodable, Sendable {
        let format: String, baseline: [String:Double], positions: [[Double]], triangleIndices: [UInt32]
    }
    private struct JointPoint: Decodable, Sendable {
        let sourceVertexID: Int, sourcePosition: [Double], templatePositionMeters: [Double], visibleVertexID: Int?
    }
    private struct Joint: Decodable, Sendable {
        let name: String, sourceVertexIDs: [Int], sourceVertexTableIndices: [Int], templatePositionMeters: [Double]
    }
    private struct Bone: Decodable, Sendable {
        let name: String, parent: Int?, head: Int, tail: Int, rotationPlaneJointIndices: [Int]
    }
    private struct Weights: Decodable, Sendable {
        let vertexOffsets: [Int], boneIndices: [Int], rawValues: [Double], normalizedValues: [Double]
        let sourcePairOffsets: [Int], rawVertexSums: [Double]
    }
    private struct Rig: Decodable, Sendable {
        let format: String, license: String, sourceCommit: String
        let templateResourceSHA256: String, templateGeometrySHA256: String
        let templateVertexCount: Int, sourceVertexCount: Int
        let visibleToSource: [Int], sourceToVisible: [Int], jointSourceVertexTable: [JointPoint]
        let joints: [Joint], bones: [Bone], boneEvaluationOrder: [Int], weights: Weights
        let runtimeEnabled: Bool, fitterImplemented: Bool, surfaceMeasurementContractImplemented: Bool
    }
    private struct Provenance: Decodable {
        struct Asset: Decodable {let filename: String, sha256: String, license: String}
        let format: String, sourceCommit: String, rigResourceSHA256: String
        let templateResourceSHA256: String, templateGeometrySHA256: String, assets: [Asset]
    }
    private struct ShapeField {
        let ws:Double,hs:Double,hy:Double,ly:Double,uy:Double,baseHipLine:Double
        init(baseline:[String:Double],values:[String:Double])throws {
            guard let height=values["height"],let waist=values["waist"],let hips=values["hips"],
                  let hipLine=values["hips_line"],let waistLevel=values["_waist_level"],
                  [height,waist,hips,hipLine,waistLevel].allSatisfy({$0.isFinite && $0>0}),
                  waistLevel>hipLine,height>waistLevel,
                  let bh=baseline["height"],let bw=baseline["waist"],let bp=baseline["hips"],
                  let bl=baseline["hipLine"],let blevel=baseline["waistLevel"],
                  [bh,bw,bp,bl,blevel].allSatisfy({$0.isFinite && $0>0}),blevel>bl,bh>blevel else {
                throw RigError.invalid("人体五尺度或基准不完整。")
            }
            ws=waist/100/bw;hs=hips/100/bp;hy=hipLine/100/bl
            ly=(waistLevel-hipLine)/100/(blevel-bl);uy=(height-waistLevel)/100/(bh-blevel);baseHipLine=bl
            guard [ws,hs,hy,ly,uy].allSatisfy({(0.5...1.8).contains($0)}) else {throw RigError.invalid("人体五尺度超出旧有限拟合域。")}
        }
        func apply(_ p:V)->V {
            // Preserve the existing StandardBody scalar operation order.
            let y=p.y,t=max(0,min(1,(y+baseHipLine)/baseHipLine)),blend=t*t*(3-2*t)
            let h=hs+(ws-hs)*blend
            let yy=y>=0 ? y*uy:(y>=(-baseHipLine) ? y*hy:-baseHipLine*hy+(y+baseHipLine)*ly)
            return .init(x:p.x*h,y:yy,z:p.z*h)
        }
    }
    struct Prepared: Sendable {
        private let template:Template,rig:Rig,limits:Limits,topology:C.Topology
        let templateGeometrySHA256:String,rigResourceSHA256:String
        let visibleToSource:[Int]
        init(templateData:Data,rigData:Data,provenanceData:Data,limits:Limits = .init(),
             isCancelled:@Sendable ()->Bool = {false})throws {
            if isCancelled(){throw CancellationError()}
            guard (4096...32_000_000).contains(limits.maximumResourceBytes),
                  (4...100_000).contains(limits.maximumVertices),(4...200_000).contains(limits.maximumTriangles),
                  (2...2048).contains(limits.maximumBones),(1...100_000).contains(limits.maximumJointReferences),
                  (4...1_000_000).contains(limits.maximumWeightPairs),(1...1_000_000).contains(limits.maximumCandidatePairs) else {throw RigError.invalid("预算无效。")}
            guard [templateData,rigData,provenanceData].allSatisfy({$0.count<=limits.maximumResourceBytes}) else {throw RigError.budgetExceeded}
            let t=try JSONDecoder().decode(Template.self,from:templateData),r=try JSONDecoder().decode(Rig.self,from:rigData)
            let p=try JSONDecoder().decode(Provenance.self,from:provenanceData)
            let commit="a8bc2d54ff0ac92e78ff71431b1023eda42bf482"
            guard t.format=="tailorass-standard-body-v1",r.format=="tailorass-optional-body-rig-v1",r.license=="CC0-1.0",
                  p.format=="tailorass-optional-body-rig-provenance-v1",r.sourceCommit==commit,p.sourceCommit==commit,
                  !r.fitterImplemented,!r.surfaceMeasurementContractImplemented,!r.runtimeEnabled,
                  p.rigResourceSHA256==hash(rigData),p.templateResourceSHA256==hash(templateData),
                  r.templateResourceSHA256==p.templateResourceSHA256,
                  p.assets.count==4,p.assets.allSatisfy({$0.license=="CC0-1.0" && $0.sha256.count==64}),
                  Set(p.assets.map(\.filename))==Set(["base.obj","default.mhskel","default_weights.mhw","LICENSE.ASSETS.md"]) else {throw RigError.invalid("CC0资源来源或SHA绑定无效。")}
            guard t.positions.count<=limits.maximumVertices,t.triangleIndices.count/3<=limits.maximumTriangles,
                  r.bones.count<=limits.maximumBones,r.jointSourceVertexTable.count<=limits.maximumJointReferences,
                  r.weights.boneIndices.count<=limits.maximumWeightPairs else {throw RigError.budgetExceeded}
            guard t.positions.count==r.templateVertexCount,t.positions.count==13380,r.sourceVertexCount==19158,
                  t.triangleIndices.count==26756*3,r.bones.count==163,r.joints.count==326,
                  r.jointSourceVertexTable.count==1117,r.weights.boneIndices.count==40156,
                  r.visibleToSource.count==t.positions.count,r.sourceToVisible.count==r.sourceVertexCount,
                  Set(r.visibleToSource).count==t.positions.count,
                  r.visibleToSource.allSatisfy({r.sourceToVisible.indices.contains($0)}),
                  r.visibleToSource.enumerated().allSatisfy({r.sourceToVisible[$0.element]==$0.offset}),
                  r.sourceToVisible.filter({$0>=0}).count==t.positions.count,
                  r.sourceToVisible.allSatisfy({$0 == -1 || t.positions.indices.contains($0)}),
                  t.positions.allSatisfy({$0.count==3 && $0.allSatisfy(\.isFinite)}) else {throw RigError.invalid("可见源顶点映射无效。")}
            let positions=t.positions.map{V(x:$0[0],y:$0[1],z:$0[2])}
            guard geometryHash(positions,t.triangleIndices)==r.templateGeometrySHA256,
                  p.templateGeometrySHA256==r.templateGeometrySHA256 else {throw RigError.invalid("可见模板几何SHA不匹配。")}
            try validateClosed(positions,t.triangleIndices,isCancelled:isCancelled)
            guard !r.bones.isEmpty,r.joints.count==2*r.bones.count,
                  Set(r.bones.map(\.name)).count==r.bones.count,
                  Set(r.bones.flatMap{[$0.head,$0.tail]}).count==r.joints.count,
                  r.boneEvaluationOrder.sorted()==Array(r.bones.indices) else {throw RigError.invalid("骨架名称、锚点或顺序无效。")}
            var done=Set<Int>()
            for id in r.boneEvaluationOrder {
                let b=r.bones[id]
                guard (b.parent == nil || done.contains(b.parent!)),r.joints.indices.contains(b.head),r.joints.indices.contains(b.tail),
                      b.rotationPlaneJointIndices.allSatisfy({r.joints.indices.contains($0)}) else {throw RigError.invalid("骨架父子链或引用无效。")}
                done.insert(id)
            }
            var sourceIDs=Set<Int>()
            for (i,v) in r.jointSourceVertexTable.enumerated() {
                if i%128==0,isCancelled(){throw CancellationError()}
                guard sourceIDs.insert(v.sourceVertexID).inserted,r.sourceToVisible.indices.contains(v.sourceVertexID),
                      v.templatePositionMeters.count==3,v.templatePositionMeters.allSatisfy(\.isFinite),
                      v.sourcePosition.count==3,v.sourcePosition.allSatisfy(\.isFinite),
                      v.visibleVertexID==(r.sourceToVisible[v.sourceVertexID]>=0 ? r.sourceToVisible[v.sourceVertexID]:nil) else {throw RigError.invalid("辅助骨锚源映射无效。")}
                if let id=v.visibleVertexID {guard v.templatePositionMeters==t.positions[id] else {throw RigError.invalid("可见辅助源点不一致。")}}
            }
            for j in r.joints {
                guard !j.sourceVertexTableIndices.isEmpty,j.sourceVertexTableIndices.count<=64,
                      j.sourceVertexIDs.count==j.sourceVertexTableIndices.count,j.templatePositionMeters.count==3,
                      j.sourceVertexTableIndices.allSatisfy({r.jointSourceVertexTable.indices.contains($0)}),
                      j.sourceVertexTableIndices.map({r.jointSourceVertexTable[$0].sourceVertexID})==j.sourceVertexIDs else {throw RigError.invalid("辅助骨锚引用无效。")}
                let q=mean(j.sourceVertexTableIndices.map{i in let p=r.jointSourceVertexTable[i].templatePositionMeters;return V(x:p[0],y:p[1],z:p[2])})
                guard same(q,V(x:j.templatePositionMeters[0],y:j.templatePositionMeters[1],z:j.templatePositionMeters[2])) else {throw RigError.invalid("辅助骨锚不是逐源点变换后的均值。")}
            }
            let w=r.weights,n=w.boneIndices.count
            guard w.vertexOffsets.count==positions.count+1,w.vertexOffsets.first==0,w.vertexOffsets.last==n,
                  w.rawValues.count==n,w.normalizedValues.count==n,w.sourcePairOffsets.count==n,w.rawVertexSums.count==positions.count else {throw RigError.invalid("完整蒙皮权重CSR无效。")}
            var sourcePairs=Set<UInt64>()
            for i in positions.indices {
                if i%128==0,isCancelled(){throw CancellationError()}
                let a=w.vertexOffsets[i],b=w.vertexOffsets[i+1]
                guard a>=0,b>a,b<=n,b-a<=64 else {throw RigError.invalid("顶点缺少完整权重。")}
                let ids=Array(w.boneIndices[a..<b]),raw=Array(w.rawValues[a..<b]),norm=Array(w.normalizedValues[a..<b]),total=raw.reduce(0,+)
                guard Set(ids).count==ids.count,ids.allSatisfy({r.bones.indices.contains($0)}),
                      raw.allSatisfy({$0.isFinite && $0>=0}),norm.allSatisfy({$0.isFinite && $0>=0}),total>0,
                      total==w.rawVertexSums[i],zip(raw,norm).allSatisfy({$0/total==$1}),abs(norm.reduce(0,+)-1)<1e-12,
                      w.sourcePairOffsets[a..<b].allSatisfy({(0..<r.sourceVertexCount).contains($0)}) else {throw RigError.invalid("蒙皮权重或比例无效。")}
                for j in a..<b {
                    let key=(UInt64(w.boneIndices[j])<<32)|UInt64(w.sourcePairOffsets[j])
                    guard sourcePairs.insert(key).inserted else {throw RigError.invalid("原始骨权重来源引用重复。")}
                }
            }
            for side in ["L","R"] {guard ["upperarm01.","upperarm02.","wrist."].allSatisfy({prefix in r.bones.contains{$0.name==prefix+side}}) else {throw RigError.invalid("双臂代理骨链缺失。")}}
            let topology=try C.Topology(vertexCount:positions.count,triangleIndices:t.triangleIndices,isCancelled:isCancelled)
            if isCancelled(){throw CancellationError()}
            template=t;rig=r;self.limits=limits;self.topology=topology
            templateGeometrySHA256=r.templateGeometrySHA256;rigResourceSHA256=p.rigResourceSHA256;visibleToSource=r.visibleToSource
        }
        func pose(visiblePositions:[V],triangleIndices:[UInt32],bodyValues:[String:Double],pose:Pose = .identity,
                  isCancelled:@Sendable ()->Bool = {false})throws->Attempt {
            if isCancelled(){throw CancellationError()}
            guard triangleIndices==template.triangleIndices,visiblePositions.count==template.positions.count else {throw RigError.invalid("输入可见人体拓扑不匹配。")}
            let field=try ShapeField(baseline:template.baseline,values:bodyValues)
            for i in visiblePositions.indices {
                if i%128==0,isCancelled(){throw CancellationError()}
                let p=template.positions[i],expected=field.apply(V(x:p[0],y:p[1],z:p[2]))
                guard same(visiblePositions[i],expected) else {throw RigError.invalid("输入可见人体与同一五尺度变形场逐位不一致。")}
            }
            let helper=rig.jointSourceVertexTable.map{p in field.apply(V(x:p.templatePositionMeters[0],y:p.templatePositionMeters[1],z:p.templatePositionMeters[2]))}
            var joints=rig.joints.map{j in mean(j.sourceVertexTableIndices.map{helper[$0]})}
            var transforms=rig.bones.map{BoneTransform(name:$0.name,rotationZRadians:0,pivot:.zero)}
            let identity:Bool
            switch pose {
            case .identity: identity=true
            case let .arms(alpha):
                identity=false
                guard alpha.isFinite,(0...90).contains(alpha) else {throw RigError.invalid("摆臂角须为相对水平线向下的0…90度。")}
                for side in ["L","R"] {
                    let root=rig.bones.firstIndex{$0.name=="upperarm01."+side}!,elbow=rig.bones.firstIndex{$0.name=="upperarm02."+side}!
                    let pivot=joints[rig.bones[root].head],axis=joints[rig.bones[elbow].tail]-pivot
                    guard abs(axis.x)>1e-9,axis.y<0 else {throw RigError.invalid("双臂代理方向不适合当前摆臂契约。")}
                    let rest=atan2(-axis.y,abs(axis.x)),delta=(rest-alpha*Double.pi/180)*(side=="L" ? 1:-1)
                    var affected=Set<Int>()
                    for id in rig.boneEvaluationOrder {
                        let b=rig.bones[id]
                        if id==root || (b.parent != nil && affected.contains(b.parent!)) {
                            affected.insert(id)
                            transforms[id] = .init(name:b.name,rotationZRadians:delta,pivot:pivot)
                        }
                    }
                }
                // A joint belongs to exactly one head/tail bone pair in this
                // pinned schema; auxiliary rotation planes remain references.
                for id in rig.bones.indices {
                    let b=rig.bones[id],t=transforms[id]
                    joints[b.head]=t.apply(joints[b.head]);joints[b.tail]=t.apply(joints[b.tail])
                }
            }
            var positions=visiblePositions
            if !identity {
                let w=rig.weights
                for i in positions.indices {
                    if i%128==0,isCancelled(){throw CancellationError()}
                    let p=visiblePositions[i];var delta=V.zero
                    for j in w.vertexOffsets[i]..<w.vertexOffsets[i+1] {
                        delta=delta+transforms[w.boneIndices[j]].displacement(p)*w.normalizedValues[j]
                    }
                    // All original influences retained. Delta form preserves
                    // unchanged vertices exactly; no four-influence pruning.
                    if delta.x != 0 || delta.y != 0 || delta.z != 0 {positions[i]=p+delta}
                }
            }
            var minCross=Double.infinity,minDot=1.0,volume=0.0
            for offset in stride(from:0,to:triangleIndices.count,by:3) {
                if offset%384==0,isCancelled(){throw CancellationError()}
                let a=Int(triangleIndices[offset]),b=Int(triangleIndices[offset+1]),c=Int(triangleIndices[offset+2])
                let q=(positions[b]-positions[a]).cross(positions[c]-positions[a])
                let r=(visiblePositions[b]-visiblePositions[a]).cross(visiblePositions[c]-visiblePositions[a])
                minCross=min(minCross,q.lengthSquared)
                minDot=min(minDot,dot(q,r)/max(1e-300,q.length*r.length))
                volume+=dot(positions[a],positions[b].cross(positions[c]))/6
            }
            let quality=try C.inspect(positions:positions,topology:topology,thickness:0.0001,
                                      maximumCandidatePairs:limits.maximumCandidatePairs,isCancelled:isCancelled)
            let stats=Statistics(vertexCount:positions.count,triangleCount:triangleIndices.count/3,boneCount:rig.bones.count,jointCount:rig.joints.count,
                                 retainedWeightPairs:rig.weights.boneIndices.count,
                                 maximumInfluencesPerVertex:positions.indices.map{rig.weights.vertexOffsets[$0+1]-rig.weights.vertexOffsets[$0]}.max()!,
                                 minimumTriangleCrossSquaredMeters4:minCross,minimumReferenceNormalDot:minDot,signedVolumeCubicMeters:volume,selfInspection:quality)
            var reasons:[String]=[]
            if !positions.allSatisfy(\.isFinite) || !(minCross>1e-22){reasons.append("degenerateOrNonfiniteSurface")}
            if !(minDot>0){reasons.append("referenceTriangleOrientationReversed")}
            if !(volume>1e-12){reasons.append("invalidOrReversedClosedVolume")}
            if quality.intersectingTrianglePairs>0 || quality.degenerateTriangles>0 {reasons.append("nonadjacentSurfaceIntersection")}
            if isCancelled(){throw CancellationError()}
            let sha=geometryHash(positions,triangleIndices)
            let body=reasons.isEmpty ? ValidatedBody(positions:positions,triangleIndices:triangleIndices,geometrySHA256:sha,
                                                     jointAnchors:joints,boneTransforms:transforms,statistics:stats,identity:identity):nil
            return Attempt(validatedBody:body,diagnosticPositions:positions,diagnosticJointAnchors:joints,statistics:stats,rejectionReasons:reasons,geometrySHA256:sha)
        }
    }
    static func load(resourceDirectory:URL,limits:Limits = .init(),isCancelled:@Sendable ()->Bool = {false})throws->Prepared {
        if isCancelled(){throw CancellationError()}
        let rig=resourceDirectory.appendingPathComponent("GarmentCodeStandardBodyRig")
        func read(_ url:URL)throws->Data {
            if isCancelled(){throw CancellationError()}
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize
            guard let size,size<=limits.maximumResourceBytes else {throw RigError.budgetExceeded}
            return try Data(contentsOf:url,options:.mappedIfSafe)
        }
        return try Prepared(templateData:read(resourceDirectory.appendingPathComponent("GarmentCodeStandardBody.json")),
                            rigData:read(rig.appendingPathComponent("rig.json")),
                            provenanceData:read(rig.appendingPathComponent("provenance.json")),limits:limits,isCancelled:isCancelled)
    }
    private static func mean(_ points:[V])->V {
        let sum=points.reduce(V.zero,+),n=Double(points.count)
        // Direct division matches the declared JSON mean operation, rather
        // than Vector3 division's reciprocal multiplication.
        return .init(x:sum.x/n,y:sum.y/n,z:sum.z/n)
    }
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func same(_ a:V,_ b:V)->Bool {a.x.bitPattern==b.x.bitPattern && a.y.bitPattern==b.y.bitPattern && a.z.bitPattern==b.z.bitPattern}
    private static func hash(_ d:Data)->String {SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
    static func geometryHash(_ positions:[V],_ indices:[UInt32])->String {
        var d=Data("rigid-clearance-visible-body-v1\0".utf8)
        func add<T:FixedWidthInteger>(_ x:T){var y=x.littleEndian;withUnsafeBytes(of:&y){d.append(contentsOf:$0)}}
        add(UInt64(positions.count));add(UInt64(indices.count))
        for p in positions {add(p.x.bitPattern);add(p.y.bitPattern);add(p.z.bitPattern)}
        for i in indices {add(i)}
        return hash(d)
    }
    private static func validateClosed(_ positions:[V],_ indices:[UInt32],isCancelled:@Sendable ()->Bool)throws {
        guard positions.count>=4,!indices.isEmpty,indices.count%3==0,positions.allSatisfy({$0.isFinite && $0.length<100}) else {throw RigError.invalid("人体表面数量或坐标无效。")}
        var edges:[UInt64:(Int,Int)]=[:],volumes:[Int:Double]=[:],parents=Array(positions.indices),used=Set<Int>()
        func root(_ i:Int)->Int {var k=i;while parents[k] != k {k=parents[k]};return k}
        for k in stride(from:0,to:indices.count,by:3) {
            if k%384==0,isCancelled(){throw CancellationError()}
            let a=Int(indices[k]),b=Int(indices[k+1]),c=Int(indices[k+2])
            guard a<positions.count,b<positions.count,c<positions.count,a != b,b != c,c != a,
                  (positions[b]-positions[a]).cross(positions[c]-positions[a]).lengthSquared>1e-22 else {throw RigError.invalid("模板人体含无效三角面。")}
            parents[root(b)]=root(a);parents[root(c)]=root(a);used.formUnion([a,b,c])
            for (i,j) in [(a,b),(b,c),(c,a)] {
                let key=(UInt64(min(i,j))<<32)|UInt64(max(i,j)),v=edges[key] ?? (0,0)
                edges[key]=(v.0+1,v.1+(i<j ? 1:-1))
            }
        }
        for k in stride(from:0,to:indices.count,by:3) {
            if k%384==0,isCancelled(){throw CancellationError()}
            let a=Int(indices[k]),b=Int(indices[k+1]),c=Int(indices[k+2])
            volumes[root(a),default:0]+=dot(positions[a],positions[b].cross(positions[c]))/6
        }
        guard used.count==positions.count,edges.values.allSatisfy({$0.0==2 && $0.1==0}),
              volumes.values.allSatisfy({$0.isFinite && $0>1e-12}) else {throw RigError.invalid("模板人体不是全部逐组件正向闭合表面。")}
    }
}
