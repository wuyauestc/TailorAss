import Foundation

/// Discrete Shells bending on internal edges of the unchanged source paper.
/// E = kb * sum(3 L0²/(A01+A02) * theta²), with flat rest angle zero.
/// kb is explicitly experimental, in N·m; it is not a calibrated fabric value.
/// This energy component adds no pins, sewing edges, mass changes or dynamics.
nonisolated enum GarmentCodeHingeBending {
    typealias V=GarmentCodeCircleDrape.Vector3
    typealias PanelGroup=GarmentCodeCircleDrape.PanelGroup

    enum HingeError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded,degenerateCurrentHinge(Int),principalAngleCut(Int)
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "裁片弯曲能量无效："+s
            case .budgetExceeded:return "裁片弯曲能量超出顶点、三角面或铰链预算。"
            case let .degenerateCurrentHinge(id):return "裁片内部铰链 \(id) 已退化，不能计算弯曲导数。"
            case let .principalAngleCut(id):return "裁片内部铰链 \(id) 接近正负 π 分支，不能计算连续弯曲导数。"
            }
        }
    }
    struct Limits:Sendable {
        var maximumVertices=20_000
        var maximumTriangles=40_000
        var maximumHinges=60_000
        /// An explicit invalid-domain band, never an angle/force clamp.
        var principalBranchMarginRadians=1e-6
        /// Current edge length and face cross-product norm relative to source.
        var minimumCurrentRatio=1e-8
    }
    struct Material:Sendable {
        /// N·m in the declared energy convention, which has no factor 1/2.
        let bendingStiffnessNewtonMeter:Double
        init(bendingStiffnessNewtonMeter:Double)throws {
            guard bendingStiffnessNewtonMeter.isFinite,(0...1e12).contains(bendingStiffnessNewtonMeter) else {
                throw HingeError.invalid("实验弯曲系数必须是有限且非负的 N·m 数值。")
            }
            self.bendingStiffnessNewtonMeter=bendingStiffnessNewtonMeter
        }
    }
    struct Hinge:Sendable {
        /// The shared oriented edge is [0,1]; opposite vertices are [2,3].
        /// The reference faces have orders [0,1,2] and [1,0,3].
        let vertexIDs:[Int]
        let panelID:String
        let sourceTriangleIDs:[Int]
        let sourceEdgeLengthMeters:Double
        let sourceFirstCrossNormSquareMeters:Double
        let sourceSecondCrossNormSquareMeters:Double
        let sourceAdjacentAreaSquareMeters:Double
        let sourceWeight:Double
    }
    struct AngleEvaluation:Sendable {
        let angleRadians:Double
        /// d(theta)/dx in 1/m, in this hinge's four vertexIDs order.
        let gradientPerMeter:[V]
    }
    struct EnergyEvaluation:Sendable {
        let energyJoules:Double
        /// dE/dx in N; the internal bending force is its negative.
        let gradientNewton:[V]
        let maximumAbsoluteAngleRadians:Double
    }
    enum HessianMode:Sendable {
        /// Includes theta * D(gradient(theta)); may be indefinite at a fold.
        case exact
        /// PSD outer-product approximation, equal to exact only at theta=0.
        case gaussNewtonPSD
    }
    struct Prepared:Sendable {
        let vertexCount:Int
        let triangleCount:Int
        let boundaryEdgeCount:Int
        let hinges:[Hinge]
        let panelHingeCounts:[String:Int]
        private let limits:Limits

        /// Groups must come from the caller's already verified source bindings,
        /// e.g. PreparedInput.panelBindings.map { PanelGroup(panelID:$0.mesh.panelID,
        /// vertexIDs:$0.vertexIDs,triangleIDs:$0.triangleIDs) }.
        /// This constructor checks complete disjoint topology membership again.
        /// It cannot certify source provenance and never guesses panel identity
        /// from connected components, spatial proximity or a sewing plan.
        init(referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[PanelGroup],
             limits:Limits=Limits(),isCancelled:@Sendable()->Bool={false})throws {
            try checkCancellation(isCancelled)
            guard (1...20_000).contains(limits.maximumVertices),(1...40_000).contains(limits.maximumTriangles),
                  (1...60_000).contains(limits.maximumHinges),limits.principalBranchMarginRadians.isFinite,
                  (1e-8..<0.01).contains(limits.principalBranchMarginRadians),limits.minimumCurrentRatio.isFinite,
                  (1e-8..<0.01).contains(limits.minimumCurrentRatio) else {throw HingeError.invalid("数值域或工作预算无效。")}
            let n=referencePositions.count,tCount=referenceTriangles.count/3
            guard n<=limits.maximumVertices,tCount<=limits.maximumTriangles else {throw HingeError.budgetExceeded}
            guard n>=3,!referenceTriangles.isEmpty,referenceTriangles.count%3==0,
                  !panelGroups.isEmpty,panelGroups.count<=128 else {throw HingeError.invalid("需要完整参考三角网格和显式裁片分组。")}
            var vertexOwner=Array(repeating:-1,count:n),faceOwner=Array(repeating:-1,count:tCount),names=Set<String>()
            var membershipVisits=0
            for (groupID,group) in panelGroups.enumerated() {
                try checkCancellation(isCancelled)
                guard !group.panelID.isEmpty,group.panelID.utf8.count<=256,names.insert(group.panelID).inserted,
                      !group.vertexIDs.isEmpty,group.vertexIDs.count<=n,
                      !group.triangleIDs.isEmpty,group.triangleIDs.count<=tCount else {throw HingeError.invalid("裁片名称或分组规模无效。")}
                for id in group.vertexIDs {
                    if membershipVisits%128==0 {try checkCancellation(isCancelled)};membershipVisits+=1
                    guard referencePositions.indices.contains(id),vertexOwner[id] == -1 else {throw HingeError.invalid("参考顶点的裁片归属重复或越界。")}
                    vertexOwner[id]=groupID
                }
                for id in group.triangleIDs {
                    if membershipVisits%128==0 {try checkCancellation(isCancelled)};membershipVisits+=1
                    guard (0..<tCount).contains(id),faceOwner[id] == -1 else {throw HingeError.invalid("参考三角面的裁片归属重复或越界。")}
                    faceOwner[id]=groupID
                }
            }
            guard !vertexOwner.contains(-1),!faceOwner.contains(-1) else {throw HingeError.invalid("显式裁片分组必须完整覆盖所有源顶点和三角面。")}
            for i in referencePositions.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                guard referencePositions[i].isFinite,referencePositions[i].length<100 else {throw HingeError.invalid("原纸样坐标必须是有限的米制坐标。")}
            }
            var edges:[Edge:[HalfEdge]]=[:],seen=Set<TriangleKey>(),used=Array(repeating:false,count:n)
            for ti in 0..<tCount {
                if ti%128==0 {try checkCancellation(isCancelled)}
                let ids=(0..<3).map{Int(referenceTriangles[3*ti+$0])}
                guard Set(ids).count==3,ids.allSatisfy({referencePositions.indices.contains($0)}) else {throw HingeError.invalid("源三角面索引无效。")}
                guard ids.allSatisfy({vertexOwner[$0]==faceOwner[ti]}) else {throw HingeError.invalid("源三角面与其裁片顶点归属不一致。")}
                guard seen.insert(TriangleKey(ids)).inserted else {throw HingeError.invalid("源三角面重复。")}
                let a=referencePositions[ids[1]]-referencePositions[ids[0]],b=referencePositions[ids[2]]-referencePositions[ids[0]],c=referencePositions[ids[2]]-referencePositions[ids[1]]
                let scale=max(a.lengthSquared,max(b.lengthSquared,c.lengthSquared)),cross=a.cross(b).length
                guard scale.isFinite,scale>0,cross.isFinite,cross>scale*1e-12 else {throw HingeError.invalid("源三角面退化。")}
                for id in ids {used[id]=true}
                for j in 0..<3 {
                    let half=HalfEdge(a:ids[j],b:ids[(j+1)%3],opposite:ids[(j+2)%3],triangle:ti)
                    let key=Edge(half.a,half.b)
                    edges[key,default:[]].append(half)
                    guard edges[key]!.count<=2 else {throw HingeError.invalid("源内部边不是二流形。")}
                }
            }
            guard used.allSatisfy({$0}) else {throw HingeError.invalid("分组中的源顶点必须属于真实三角面。")}
            var result:[Hinge]=[],counts:[String:Int]=[:],boundary=0,visits=0
            for key in edges.keys.sorted(by:{$0.lo == $1.lo ? $0.hi<$1.hi:$0.lo<$1.lo}) {
                if visits%128==0 {try checkCancellation(isCancelled)};visits+=1
                let faces=edges[key]!
                if faces.count==1 {boundary+=1;continue}
                let a=faces[0],b=faces[1]
                guard a.a==b.b,a.b==b.a,a.opposite != b.opposite,
                      faceOwner[a.triangle]==faceOwner[b.triangle] else {throw HingeError.invalid("源内部边方向或裁片归属不一致。")}
                let ids=[a.a,a.b,a.opposite,b.opposite],panel=panelGroups[faceOwner[a.triangle]].panelID
                let e=referencePositions[ids[1]]-referencePositions[ids[0]],v=referencePositions[ids[2]]-referencePositions[ids[0]],w=referencePositions[ids[3]]-referencePositions[ids[0]],length=e.length
                let n1=e.cross(v).length,n2=w.cross(e).length,sumArea=(n1+n2)/2,weight=3*length*length/sumArea
                guard weight.isFinite,weight>0 else {throw HingeError.invalid("源铰链权重不可分辨。")}
                let hinge=Hinge(vertexIDs:ids,panelID:panel,sourceTriangleIDs:[a.triangle,b.triangle],sourceEdgeLengthMeters:length,
                    sourceFirstCrossNormSquareMeters:n1,sourceSecondCrossNormSquareMeters:n2,sourceAdjacentAreaSquareMeters:sumArea,sourceWeight:weight)
                let state=try angleState(hinge,positions:referencePositions,limits:limits,hingeID:result.count)
                guard abs(state.theta)<=1e-8 else {throw HingeError.invalid("源纸样铰链必须具有零弯曲角。")}
                result.append(hinge);counts[panel,default:0]+=1
                guard result.count<=limits.maximumHinges else {throw HingeError.budgetExceeded}
            }
            try checkCancellation(isCancelled)
            vertexCount=n;triangleCount=tCount;boundaryEdgeCount=boundary;hinges=result;panelHingeCounts=counts;self.limits=limits
        }
        private func validate(_ positions:[V],_ isCancelled:@Sendable()->Bool)throws {
            try checkCancellation(isCancelled)
            guard positions.count==vertexCount else {throw HingeError.invalid("实际坐标数量与参考网格不一致。")}
            for i in positions.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                guard positions[i].isFinite,positions[i].length<100 else {throw HingeError.invalid("实际坐标必须是有限的米制坐标。")}
            }
        }
        func angle(positions:[V],hingeID:Int,isCancelled:@Sendable()->Bool={false})throws->AngleEvaluation {
            try validate(positions,isCancelled)
            guard hinges.indices.contains(hingeID) else {throw HingeError.invalid("内部铰链编号越界。")}
            let s=try angleState(hinges[hingeID],positions:positions,limits:limits,hingeID:hingeID)
            try checkCancellation(isCancelled)
            return .init(angleRadians:s.theta,gradientPerMeter:s.q)
        }
        func evaluate(positions:[V],material:Material,isCancelled:@Sendable()->Bool={false})throws->EnergyEvaluation {
            try validate(positions,isCancelled)
            var energy=0.0,maximum=0.0,g=Array(repeating:V.zero,count:vertexCount)
            let kb=material.bendingStiffnessNewtonMeter
            for (id,h) in hinges.enumerated() {
                if id%128==0 {try checkCancellation(isCancelled)}
                let s=try angleState(h,positions:positions,limits:limits,hingeID:id),c=2*kb*h.sourceWeight
                energy += kb*h.sourceWeight*s.theta*s.theta;maximum=max(maximum,abs(s.theta))
                for j in 0..<4 {g[h.vertexIDs[j]]=g[h.vertexIDs[j]]+s.q[j]*(c*s.theta)}
            }
            guard energy.isFinite,g.allSatisfy(\.isFinite) else {throw HingeError.invalid("弯曲能量或梯度溢出。")}
            try checkCancellation(isCancelled)
            return .init(energyJoules:energy,gradientNewton:g,maximumAbsoluteAngleRadians:maximum)
        }
        /// Exact and PSD GN are intentionally distinct. No assembled Hessian,
        /// material damping, projection, source repair or dynamics is applied.
        func hessianProduct(positions:[V],direction:[V],material:Material,mode:HessianMode,
                            isCancelled:@Sendable()->Bool={false})throws->[V] {
            try validate(positions,isCancelled)
            guard direction.count==vertexCount else {throw HingeError.invalid("弯曲方向向量数量无效。")}
            for i in direction.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                guard direction[i].isFinite else {throw HingeError.invalid("弯曲方向向量含非有限数值。")}
            }
            var out=Array(repeating:V.zero,count:vertexCount)
            for (id,h) in hinges.enumerated() {
                if id%128==0 {try checkCancellation(isCancelled)}
                let s=try angleState(h,positions:positions,limits:limits,hingeID:id),d=h.vertexIDs.map{direction[$0]},c=2*material.bendingStiffnessNewtonMeter*h.sourceWeight
                let dt=(0..<4).reduce(0.0){$0+dot(s.q[$1],d[$1])}
                let dq=mode == .exact ? angleGradientDifferential(s,direction:d):Array(repeating:V.zero,count:4)
                for j in 0..<4 {out[h.vertexIDs[j]]=out[h.vertexIDs[j]]+(s.q[j]*dt+dq[j]*s.theta)*c}
            }
            guard out.allSatisfy(\.isFinite) else {throw HingeError.invalid("弯曲 Hessian 方向积溢出。")}
            try checkCancellation(isCancelled);return out
        }
    }
    private struct Edge:Hashable {let lo:Int,hi:Int;init(_ a:Int,_ b:Int){lo=min(a,b);hi=max(a,b)}}
    private struct HalfEdge {let a:Int,b:Int,opposite:Int,triangle:Int}
    private struct TriangleKey:Hashable {let a:Int,b:Int,c:Int;init(_ ids:[Int]){let s=ids.sorted();a=s[0];b=s[1];c=s[2]}}
    private struct AngleState {let theta:Double,q:[V],e:V,v:V,w:V,length:Double,n1:V,n2:V,a:Double,b:Double}
    private static func checkCancellation(_ isCancelled:@Sendable()->Bool)throws {if isCancelled(){throw CancellationError()}}
    private static func dot(_ a:V,_ b:V)->Double{a.x*b.x+a.y*b.y+a.z*b.z}
    private static func angleState(_ h:Hinge,positions:[V],limits:Limits,hingeID:Int)throws->AngleState {
        let p=h.vertexIDs.map{positions[$0]},e=p[1]-p[0],v=p[2]-p[0],w=p[3]-p[0],length=e.length,n1=e.cross(v),n2=w.cross(e),s1=n1.length,s2=n2.length
        guard length.isFinite,length>h.sourceEdgeLengthMeters*limits.minimumCurrentRatio,
              s1.isFinite,s2.isFinite,s1>h.sourceFirstCrossNormSquareMeters*limits.minimumCurrentRatio,
              s2>h.sourceSecondCrossNormSquareMeters*limits.minimumCurrentRatio else {throw HingeError.degenerateCurrentHinge(hingeID)}
        let theta=atan2(dot(e/length,(n1/s1).cross(n2/s2)),dot(n1/s1,n2/s2))
        guard theta.isFinite,Double.pi-abs(theta)>limits.principalBranchMarginRadians else {throw HingeError.principalAngleCut(hingeID)}
        let q3=n1*(-length/(s1*s1)),q4=n2*(-length/(s2*s2)),a=dot(e,v)/(length*length),b=dot(e,w)/(length*length)
        let q=[q3*(-(1-a))+q4*(-(1-b)),q3*(-a)+q4*(-b),q3,q4]
        guard q.allSatisfy(\.isFinite) else {throw HingeError.invalid("弯曲角梯度溢出。")}
        return .init(theta:theta,q:q,e:e,v:v,w:w,length:length,n1:n1,n2:n2,a:a,b:b)
    }
    private static func angleGradientDifferential(_ s:AngleState,direction d:[V])->[V] {
        let de=d[1]-d[0],dv=d[2]-d[0],dw=d[3]-d[0],dL=dot(s.e,de)/s.length
        let dn1=de.cross(s.v)+s.e.cross(dv),dn2=dw.cross(s.e)+s.w.cross(de),s1=s.n1.lengthSquared,s2=s.n2.lengthSquared
        let dq3=(s.n1*dL+dn1*s.length)*(-1/s1)+s.n1*(s.length*2*dot(s.n1,dn1)/(s1*s1))
        let dq4=(s.n2*dL+dn2*s.length)*(-1/s2)+s.n2*(s.length*2*dot(s.n2,dn2)/(s2*s2))
        let common=2*dot(s.e,de)/(s.length*s.length)
        let da=(dot(de,s.v)+dot(s.e,dv))/(s.length*s.length)-s.a*common
        let db=(dot(de,s.w)+dot(s.e,dw))/(s.length*s.length)-s.b*common
        return [s.q[2]*da-dq3*(1-s.a)+s.q[3]*db-dq4*(1-s.b),
                s.q[2]*(-da)-dq3*s.a+s.q[3]*(-db)-dq4*s.b,dq3,dq4]
    }
}
