import Foundation

/// A native, constrained triangulation of one simple paper-panel loop.
/// The copied source geometry and every numerical value are Sendable. Each
/// invocation owns its mesh/refinement buffers; no UI actor or cache is used.
nonisolated enum GarmentCodePanelMesher {
    typealias Vector3 = GarmentCodeCircleDrape.Vector3

    nonisolated struct Boundary: Codable, Sendable {
        let edgeIndex: Int
        let edgeID: String
        let vertexIDs: [Int]
        let sourceParameters: [Double]
        let arcFractions: [Double]
        let sourceLengthMeters: Double
    }
    nonisolated struct Quality: Codable, Sendable {
        let minimumAngleDegrees: Double
        let maximumEdgeMeters: Double
        let triangleCount: Int
        let vertexCount: Int
    }
    /// Only recovered meshes disclose this deterministic extra work. Timing
    /// belongs in a caller's diagnostic report, not canonical mesh bytes.
    nonisolated struct BoundaryRecovery: Codable, Sendable {
        let attempts: Int
        let originalRefinementRounds: Int
        let recoveryRefinementRounds: Int
        let originalRoundChecks: Int
        let recoveryRoundChecks: Int
        let maximumBoundarySpacingMeters: Double
    }
    nonisolated struct Mesh: Codable, Sendable {
        let panelID: String
        let flatPositions: [Vector3]
        let triangleIndices: [UInt32]
        let boundaries: [Boundary]
        let sourceClockwise: Bool
        /// Green's integral: analytic for the supported line/circle/Bezier
        /// primitives, rather than the panel's display-sampling area.
        let sourceSignedAreaSquareMeters: Double
        let flattenedAreaSquareMeters: Double
        /// Analytic interpolation-error bound over all boundary segments.
        let maximumBoundaryDeviationMeters: Double
        /// Target absolute tolerance of adaptive analytic-speed quadrature.
        let arcLengthIntegrationToleranceMeters: Double
        let quality: Quality
        var boundaryRecovery: BoundaryRecovery? = nil
    }
    nonisolated enum MesherError: LocalizedError, Sendable {
        case invalid(String)
        case budgetExceeded(String)
        var errorDescription: String? {
            switch self {
            case let .invalid(reason): return "裁片网格无法生成：\(reason)"
            case let .budgetExceeded(reason): return "裁片网格超出本轮预算：\(reason)"
            }
        }
    }
    private struct Triangle {
        let a: Int, b: Int, c: Int
        var vertices: [Int] { [a,b,c] }
    }
    private struct Sample { let t: Double; let point: Vector3; let error: Double }
    private struct Curve {
        let edge: GarmentCodeGeometryEdge
        let controls: [Vector3]
        let coefficients: [Vector3]
        let circle: (center: Vector3, radius: Double, theta: Double, delta: Double)?
        init(_ edge: GarmentCodeGeometryEdge) throws {
            self.edge=edge
            let a=Vector3(x:edge.start.x/100,y:edge.start.y/100,z:0)
            let b=Vector3(x:edge.end.x/100,y:edge.end.y/100,z:0)
            guard a.isFinite,b.isFinite,a.length<100,b.length<100 else {throw MesherError.invalid("边界坐标无效。")}
            if let curvature=edge.curvature, !curvature.isValidForPreview {throw MesherError.invalid("曲线参数无效。")}
            var points=[a]
            if let params=edge.curvature?.params {
                let chord=b-a,left=Vector3(x:-chord.y,y:chord.x,z:0)
                points += params.map {a+chord*$0[0]+left*$0[1]}
            }
            points.append(b)
            guard points.allSatisfy({$0.isFinite && $0.length<100}) else {throw MesherError.invalid("曲线控制点超出有效范围。")}
            controls=points
            switch points.count {
            case 2: coefficients=[a,b-a]
            case 3: coefficients=[a,(points[1]-a)*2,a-points[1]*2+b]
            case 4: coefficients=[a,(points[1]-a)*3,(a-points[1]*2+points[2])*3,b-points[2]*3+points[1]*3-a]
            default: throw MesherError.invalid("不支持该曲线阶数。")
            }
            if let spec=edge.curvature?.circle {
                let chord=b-a,d=chord.length
                guard d>1e-14 else {throw MesherError.invalid("圆弧端点重合。")}
                let radius=max(spec.radius/100,d/2),height=sqrt(max(0,radius*radius-d*d/4))
                let sign = spec.largeArc == spec.right ? -1.0 : 1.0
                let center=(a+b)/2+Vector3(x:-chord.y/d,y:chord.x/d,z:0)*(height*sign)
                let theta=atan2(a.y-center.y,a.x-center.x),last=atan2(b.y-center.y,b.x-center.x)
                var delta=last-theta
                if spec.right {while delta<0 {delta += 2*Double.pi};while delta>=2*Double.pi {delta -= 2*Double.pi}}
                else {while delta>0 {delta -= 2*Double.pi};while delta <= -2*Double.pi {delta += 2*Double.pi}}
                if abs(delta) != Double.pi && (abs(delta)>Double.pi) != spec.largeArc {delta += spec.right ? -2*Double.pi : 2*Double.pi}
                circle=(center,radius,theta,delta)
            } else {circle=nil}
        }
        func point(_ t:Double)->Vector3 {
            let p=edge.point(at:t)
            return .init(x:p.x/100,y:p.y/100,z:0)
        }
        func derivative(_ t:Double)->Vector3 {
            if let circle {
                let angle=circle.theta+circle.delta*t
                return .init(x:-sin(angle)*circle.radius*circle.delta,y:cos(angle)*circle.radius*circle.delta,z:0)
            }
            var value=Vector3.zero
            for i in 1..<coefficients.count {value=value+coefficients[i]*(Double(i)*pow(t,Double(i-1)))}
            return value
        }
        func secondDerivative(_ t:Double)->Vector3 {
            var value=Vector3.zero
            for i in 2..<coefficients.count {value=value+coefficients[i]*(Double(i*(i-1))*pow(t,Double(i-2)))}
            return value
        }
        func secondBound(_ a:Double,_ b:Double)->Double {
            if let circle {return circle.radius*circle.delta*circle.delta}
            return max(secondDerivative(a).length,secondDerivative(b).length)
        }
        func monotoneProjection(_ a:Double,_ b:Double,_ chord:Vector3)->Bool {
            if let circle {return abs(circle.delta*(b-a))<Double.pi}
            var values=[dot(derivative(a),chord),dot(derivative(b),chord)]
            if coefficients.count==4 {
                let q1=2*dot(coefficients[2],chord),q2=3*dot(coefficients[3],chord)
                if abs(q2)>1e-24 {let t = -q1/(2*q2);if t>a && t<b {values.append(dot(derivative(t),chord))}}
            }
            return values.min()! >= -1e-14*max(1e-12,chord.length*derivative((a+b)/2).length)
        }
        func green(origin:Vector3)->Double {
            if let circle {
                let a=point(0),b=point(1),center=circle.center-origin
                return (center.x*(b.y-a.y)-center.y*(b.x-a.x)+circle.radius*circle.radius*circle.delta)/2
            }
            var coefficients=coefficients;coefficients[0]=coefficients[0]-origin
            var integral=0.0
            for i in coefficients.indices {for j in 1..<coefficients.count {
                integral += Double(j)*(coefficients[i].x*coefficients[j].y-coefficients[i].y*coefficients[j].x)/Double(i+j)
            }}
            return integral/2
        }
    }

    static func prepare(panel:GarmentCodePanelGeometry,targetEdgeMeters:Double=0.03,
                        flatnessMeters:Double=0.00005,maximumVertices:Int=8000,
                        maximumTriangles:Int=24000,
                        maximumBoundarySpacingMeters:[Int:Double]=[:],
                        isCancelled:@Sendable()->Bool={false}) throws -> Mesh {
        try prepare(panel:panel,targetEdgeMeters:targetEdgeMeters,flatnessMeters:flatnessMeters,
                    maximumVertices:maximumVertices,maximumTriangles:maximumTriangles,
                    maximumBoundarySpacingMeters:maximumBoundarySpacingMeters,
                    allowsBoundaryRecovery:true,refinementRoundObserver:nil,isCancelled:isCancelled)
    }

    private static func prepare(panel:GarmentCodePanelGeometry,targetEdgeMeters:Double,
                        flatnessMeters:Double,maximumVertices:Int,maximumTriangles:Int,
                        maximumBoundarySpacingMeters:[Int:Double],allowsBoundaryRecovery:Bool,
                        refinementRoundObserver:((Int)->Void)?,
                        isCancelled:@Sendable()->Bool) throws -> Mesh {
        if isCancelled() {throw CancellationError()}
        guard targetEdgeMeters.isFinite,(0.005...0.10).contains(targetEdgeMeters),
              flatnessMeters.isFinite,(0.000001...0.001).contains(flatnessMeters),
              (3...20000).contains(maximumVertices),(1...60000).contains(maximumTriangles) else {
            throw MesherError.invalid("网格间距、误差或资源上限无效。")
        }
        guard panel.edges.count>=2,panel.edges.count<=512 else {throw MesherError.invalid("需要一个有限的闭合边界。")}
        // A sewing refinement request can add fold freedom only along a
        // particular source edge. Empty overrides preserve the original mesh.
        guard maximumBoundarySpacingMeters.allSatisfy({edge,spacing in
            panel.edges.indices.contains(edge) && spacing.isFinite && (0.0005...0.10).contains(spacing)
        }) else {throw MesherError.invalid("局部接缝边界间距或源边索引无效。")}
        let curves=try panel.edges.map { try Curve($0) }
        for i in curves.indices {
            guard (curves[i].point(1)-curves[(i+1)%curves.count].point(0)).length<=1e-9 else {
                throw MesherError.invalid("相邻原始边没有闭合，不能自动移动纸样端点。")
            }
        }
        var points:[Vector3]=[],boundaries:[Boundary]=[],boundaryKeys=Set<UInt64>(),deviations:[UInt64:Double]=[:]
        var maximumDeviation=0.0,subdivisionVisits=0
        let lengthTolerance=1e-10
        for (edgeIndex,curve) in curves.enumerated() {
            if isCancelled() {throw CancellationError()}
            let sourceLength=curve.edge.length(tolerance:1e-9)/100
            guard sourceLength.isFinite,sourceLength>1e-9,sourceLength<100 else {throw MesherError.invalid("原始边长为零或超出有效范围。")}
            let edgeSpacing=min(targetEdgeMeters,maximumBoundarySpacingMeters[edgeIndex] ?? targetEdgeMeters)
            var samples=[Sample(t:0,point:curve.point(0),error:0)]
            func flatten(_ a:Double,_ b:Double,_ pa:Vector3,_ pb:Vector3,_ depth:Int)throws {
                subdivisionVisits += 1
                if subdivisionVisits%128==0 && isCancelled() {throw CancellationError()}
                guard subdivisionVisits<=maximumVertices*64 else {throw MesherError.budgetExceeded("曲线细分次数过多。")}
                let h=b-a,m=(a+b)/2,k=curve.secondBound(a,b),bound=k*h*h/8
                let measured=[a+h/4,m,a+3*h/4].map {distanceToSegment(curve.point($0),pa,pb)}.max()!
                let arcBound=(curve.derivative(m).length+k*h/2)*h
                if bound<=flatnessMeters && measured<=flatnessMeters && arcBound<=edgeSpacing*(1+1e-12) && curve.monotoneProjection(a,b,pb-pa) {
                    guard samples.count<maximumVertices else {throw MesherError.budgetExceeded("曲线边界顶点过多。")}
                    guard (pb-pa).length>1e-10 else {throw MesherError.invalid("边界出现重合或无法分辨的曲线点。")}
                    samples.append(.init(t:b,point:pb,error:max(bound,measured)))
                } else {
                    guard depth<30 else {throw MesherError.budgetExceeded("曲线在指定精度下无法可靠细分。")}
                    let pm=curve.point(m)
                    try flatten(a,m,pa,pm,depth+1);try flatten(m,b,pm,pb,depth+1)
                }
            }
            try flatten(0,1,curve.point(0),curve.point(1),0)
            var lengths=[0.0]
            for i in 1..<samples.count {
                let a=samples[i-1].t,b=samples[i].t
                let segment:Double
                if curve.circle != nil || curve.edge.curvature == nil {segment=sourceLength*(b-a)}
                else {segment=try integrateSpeed(curve,a,b,tolerance:lengthTolerance/Double(samples.count-1),depth:0)}
                lengths.append(lengths.last!+segment)
            }
            let integrated=lengths.last!
            guard integrated>0,abs(integrated-sourceLength)<=max(1e-9,sourceLength*1e-8) else {
                throw MesherError.invalid("原始曲线弧长积分未能一致收敛。")
            }
            var ids:[Int]=[]
            for i in samples.indices {
                let id:Int
                if i==0 {
                    if edgeIndex==0 {points.append(samples[i].point);id=0}
                    else {id=boundaries.last!.vertexIDs.last!}
                } else if edgeIndex==curves.count-1 && i==samples.count-1 {id=0}
                else {
                    guard points.count<maximumVertices else {throw MesherError.budgetExceeded("边界顶点超过上限。")}
                    id=points.count;points.append(samples[i].point)
                }
                if let previous=ids.last {
                    let key=edgeKey(previous,id)
                    guard previous != id,boundaryKeys.insert(key).inserted else {throw MesherError.invalid("边界重复经过同一条线段。")}
                    deviations[key]=samples[i].error;maximumDeviation=max(maximumDeviation,samples[i].error)
                }
                ids.append(id)
            }
            var fractions=lengths.map {$0/integrated};fractions[fractions.count-1]=1
            boundaries.append(.init(edgeIndex:edgeIndex,edgeID:curve.edge.id,vertexIDs:ids,
                                    sourceParameters:samples.map(\.t),arcFractions:fractions,sourceLengthMeters:sourceLength))
        }
        guard points.count>=3 else {throw MesherError.invalid("边界没有形成有效面积。")}
        try validateLoop(points,deviations:deviations,isCancelled:isCancelled)
        let origin=points[0]
        let signed=points.indices.reduce(0.0) {sum,i in sum+cross(points[i]-origin,points[(i+1)%points.count]-origin)}/2
        let sourceArea=curves.reduce(0.0) {$0+$1.green(origin:origin)}
        guard signed.isFinite,sourceArea.isFinite,abs(signed)>1e-12,sourceArea*signed>0 else {throw MesherError.invalid("裁片面积为零或曲线方向不一致。")}
        let boundaryCount=points.count
        // Small input angles cannot be removed by any conforming mesher.
        // Protect their immediate neighbourhood from quality-only refinement;
        // the maximum-edge condition and every original sample still apply.
        // Otherwise an S-curve nearly tangent to its neighbouring source edge
        // attracts an endless chain of smaller interior triangles.
        var acuteCorners:[Vector3]=[]
        for i in curves.indices {
            let previous=curves[(i+curves.count-1)%curves.count],current=curves[i]
            var incoming=previous.derivative(1),outgoing=current.derivative(0)
            if incoming.length<1e-12 {incoming=previous.point(1)-previous.point(0.9999)}
            if outgoing.length<1e-12 {outgoing=current.point(0.0001)-current.point(0)}
            let interior=atan2(abs(cross(incoming*(-1),outgoing)),dot(incoming*(-1),outgoing))*180/Double.pi
            if cross(incoming,outgoing)*(signed>0 ? 1 : -1)>0 && interior<20 {
                acuteCorners.append(points[boundaries[i].vertexIDs[0]])
            }
        }
        var active=signed>0 ? Array(points.indices) : Array(points.indices.reversed())
        var triangles:[Triangle]=[],earChecks=0
        let span=max(points.map(\.x).max()!-points.map(\.x).min()!,points.map(\.y).max()!-points.map(\.y).min()!)
        let epsilon=max(1e-18,span*span*1e-14)
        while active.count>3 {
            if isCancelled() {throw CancellationError()}
            var found=false
            for i in active.indices {
                let a=active[(i+active.count-1)%active.count],b=active[i],c=active[(i+1)%active.count]
                guard orientation(points[a],points[b],points[c])>epsilon else {continue}
                var occupied=false
                for p in active where p != a && p != b && p != c {
                    earChecks += 1
                    guard earChecks<=max(1_000_000,maximumVertices*maximumVertices*2) else {throw MesherError.budgetExceeded("凹多边形三角剖分次数过多。")}
                    if inside(points[p],points[a],points[b],points[c],epsilon:epsilon) {occupied=true;break}
                }
                if !occupied {
                    triangles.append(.init(a:a,b:b,c:c));active.remove(at:i);found=true;break
                }
            }
            guard found else {throw MesherError.invalid("无法剖分边界，可能存在重复、相切或过窄的轮廓。")}
        }
        guard orientation(points[active[0]],points[active[1]],points[active[2]])>epsilon else {throw MesherError.invalid("最后一个三角面退化。")}
        triangles.append(.init(a:active[0],b:active[1],c:active[2]))
        guard triangles.count<=maximumTriangles else {throw MesherError.budgetExceeded("边界初始三角面超过上限。")}
        try improve(&triangles,points:points,boundary:boundaryKeys,epsilon:epsilon,isCancelled:isCancelled)
        let targetSquared=targetEdgeMeters*targetEdgeMeters*(1+1e-10),shapeFloor=max(0.002,targetEdgeMeters*0.2)
        for round in 0..<80 {
            refinementRoundObserver?(round)
            if isCancelled() {throw CancellationError()}
            let adjacency=try edgeMap(triangles)
            var requested=Set(adjacency.keys.filter {key in let (a,b)=edgeVertices(key);return (points[a]-points[b]).lengthSquared>targetSquared})
            // Constrained Delaunay gives the best angles for the current
            // vertices. Add local detail where a short curved boundary would
            // otherwise meet a long fan. Intrinsically acute source corners
            // are retained; this is not a false minimum-angle certificate.
            for triangle in triangles where minimumAngle(triangle,points:points)<10 {
                if acuteCorners.contains(where:{corner in triangle.vertices.contains(where:{(points[$0]-corner).lengthSquared<4*targetEdgeMeters*targetEdgeMeters})}) {continue}
                // Splitting a shorter interior edge opposite a longer FIXED
                // boundary cannot improve that sliver; it merely drives its
                // midpoint repeatedly onto the boundary. Only bisect the real
                // longest edge here. Interior smoothing handles the former.
                if let longest=triangleEdges(triangle).max(by:{edgeLengthSquared($0,points:points)<edgeLengthSquared($1,points:points)}),
                   !boundaryKeys.contains(longest),
                   edgeLengthSquared(longest,points:points)>shapeFloor*shapeFloor {requested.insert(longest)}
            }
            if requested.isEmpty {break}
            if round==79 {
                let originalReason="内部网格细化未能收敛。"
                guard allowsBoundaryRecovery else {throw MesherError.budgetExceeded(originalReason)}
                // A short curved boundary beside a long fixed source segment
                // can repeatedly encroach that segment's diametral circle.
                // Rebuild once with more source samples; do not relax quality,
                // flatness, target edge length or final V/T resource limits.
                let spacing=targetEdgeMeters/4
                let tighter=Dictionary(uniqueKeysWithValues:panel.edges.indices.map {
                    ($0,min(maximumBoundarySpacingMeters[$0] ?? targetEdgeMeters,spacing))
                })
                if isCancelled() {throw CancellationError()}
                var recoveryRounds=0
                do {
                    var mesh=try prepare(panel:panel,targetEdgeMeters:targetEdgeMeters,flatnessMeters:flatnessMeters,
                        maximumVertices:maximumVertices,maximumTriangles:maximumTriangles,
                        maximumBoundarySpacingMeters:tighter,allowsBoundaryRecovery:false,
                        refinementRoundObserver:{recoveryRounds=$0},isCancelled:isCancelled)
                    mesh.boundaryRecovery = .init(attempts:2,originalRefinementRounds:round,
                        recoveryRefinementRounds:recoveryRounds,originalRoundChecks:round+1,
                        recoveryRoundChecks:recoveryRounds+1,maximumBoundarySpacingMeters:spacing)
                    return mesh
                } catch is CancellationError {throw CancellationError()}
                catch {throw MesherError.budgetExceeded("\(originalReason)同源边界加密后仍失败：\(error.localizedDescription)")}
            }
            let sorted=requested.sorted {a,b in let x=edgeLengthSquared(a,points:points),y=edgeLengthSquared(b,points:points);return x==y ? a<b : x>y}
            var touched=Set<Int>(),selected:[(UInt64,[Int])]=[]
            for key in sorted {
                guard !boundaryKeys.contains(key) else {throw MesherError.invalid("原始曲线边界没有达到指定网格间距。")}
                let owners=adjacency[key]!
                guard owners.count==2 else {throw MesherError.invalid("内部边没有两个相邻三角面。")}
                if owners.allSatisfy({!touched.contains($0)}) {selected.append((key,owners));touched.formUnion(owners)}
            }
            guard !selected.isEmpty else {throw MesherError.invalid("内部网格无法继续保持一致细化。")}
            guard points.count+selected.count<=maximumVertices,triangles.count+2*selected.count<=maximumTriangles else {
                throw MesherError.budgetExceeded("所需顶点或三角面超过上限，请增大网格间距。")
            }
            for (key,owners) in selected {
                let (a,b)=edgeVertices(key),mid=points.count
                points.append((points[a]+points[b])/2)
                for owner in owners {
                    let third=triangles[owner].vertices.first {$0 != a && $0 != b}!
                    triangles[owner]=try ccw(a,mid,third,points:points,epsilon:epsilon)
                    triangles.append(try ccw(mid,b,third,points:points,epsilon:epsilon))
                }
            }
            try improve(&triangles,points:points,boundary:boundaryKeys,epsilon:epsilon,isCancelled:isCancelled)
            try relax(&points,triangles:triangles,fixedCount:boundaryCount,epsilon:epsilon,isCancelled:isCancelled)
            try improve(&triangles,points:points,boundary:boundaryKeys,epsilon:epsilon,isCancelled:isCancelled)
        }
        let adjacency=try edgeMap(triangles)
        guard points.count-adjacency.count+triangles.count==1,
              adjacency.allSatisfy({boundaryKeys.contains($0.key) ? $0.value.count==1 : $0.value.count==2}),
              boundaryKeys.allSatisfy({adjacency[$0]?.count==1}),points.prefix(boundaryCount).allSatisfy(\.isFinite) else {
            throw MesherError.invalid("结果没有保持原始单片边界拓扑。")
        }
        let area=triangles.reduce(0.0) {$0+orientation(points[$1.a],points[$1.b],points[$1.c])/2}
        guard abs(area-abs(signed))<=max(1e-12,abs(signed)*1e-10) else {throw MesherError.invalid("内部细化改变了原始平面面积。")}
        let maximumEdge=sqrt(adjacency.keys.map {edgeLengthSquared($0,points:points)}.max() ?? 0)
        guard maximumEdge<=targetEdgeMeters*(1+1e-8) else {throw MesherError.invalid("内部边长没有达到指定上限。")}
        let indices=triangles.flatMap {$0.vertices.map(UInt32.init)}
        return .init(panelID:panel.id,flatPositions:points,triangleIndices:indices,boundaries:boundaries,
                     sourceClockwise:signed<0,sourceSignedAreaSquareMeters:sourceArea,flattenedAreaSquareMeters:abs(signed),
                     maximumBoundaryDeviationMeters:maximumDeviation,arcLengthIntegrationToleranceMeters:lengthTolerance,
                     quality:.init(minimumAngleDegrees:triangles.map {minimumAngle($0,points:points)}.min() ?? 0,
                                   maximumEdgeMeters:maximumEdge,triangleCount:triangles.count,vertexCount:points.count))
    }

    private static func integrateSpeed(_ curve:Curve,_ a:Double,_ b:Double,tolerance:Double,depth:Int)throws->Double {
        let m=(a+b)/2,fa=curve.derivative(a).length,fm=curve.derivative(m).length,fb=curve.derivative(b).length
        let whole=(b-a)*(fa+4*fm+fb)/6
        func visit(_ a:Double,_ b:Double,_ fa:Double,_ fm:Double,_ fb:Double,_ whole:Double,_ eps:Double,_ depth:Int)throws->Double {
            let m=(a+b)/2,lm=curve.derivative((a+m)/2).length,rm=curve.derivative((m+b)/2).length
            let left=(m-a)*(fa+4*lm+fm)/6,right=(b-m)*(fm+4*rm+fb)/6,delta=left+right-whole
            if abs(delta)<=15*eps {return left+right+delta/15}
            guard depth<24 else {throw MesherError.budgetExceeded("曲线弧长积分未在误差范围内收敛。")}
            return try visit(a,m,fa,lm,fm,left,eps/2,depth+1)+visit(m,b,fm,rm,fb,right,eps/2,depth+1)
        }
        return try visit(a,b,fa,fm,fb,whole,tolerance,depth)
    }
    private static func edgeKey(_ a:Int,_ b:Int)->UInt64 {(UInt64(min(a,b))<<32)|UInt64(max(a,b))}
    private static func edgeVertices(_ key:UInt64)->(Int,Int) {(Int(key>>32),Int(key&0xffffffff))}
    private static func triangleEdges(_ t:Triangle)->[UInt64] {[edgeKey(t.a,t.b),edgeKey(t.b,t.c),edgeKey(t.c,t.a)]}
    private static func dot(_ a:Vector3,_ b:Vector3)->Double {a.x*b.x+a.y*b.y}
    private static func cross(_ a:Vector3,_ b:Vector3)->Double {a.x*b.y-a.y*b.x}
    private static func orientation(_ a:Vector3,_ b:Vector3,_ c:Vector3)->Double {cross(b-a,c-a)}
    private static func edgeLengthSquared(_ key:UInt64,points:[Vector3])->Double {let (a,b)=edgeVertices(key);return (points[a]-points[b]).lengthSquared}
    private static func distanceToSegment(_ p:Vector3,_ a:Vector3,_ b:Vector3)->Double {
        let e=b-a,t=e.lengthSquared>1e-30 ? max(0,min(1,dot(p-a,e)/e.lengthSquared)) : 0
        return (p-a-e*t).length
    }
    private static func inside(_ p:Vector3,_ a:Vector3,_ b:Vector3,_ c:Vector3,epsilon:Double)->Bool {
        orientation(a,b,p)>=(-epsilon) && orientation(b,c,p)>=(-epsilon) && orientation(c,a,p)>=(-epsilon)
    }
    private static func validateLoop(_ points:[Vector3],deviations:[UInt64:Double],isCancelled:@Sendable()->Bool)throws {
        let n=points.count,tolerance=1e-10
        for i in 0..<n {
            if i%32==0 && isCancelled() {throw CancellationError()}
            let a=points[i],b=points[(i+1)%n],before=points[(i+n-1)%n]
            guard (b-a).length>tolerance else {throw MesherError.invalid("轮廓含重复顶点。")}
            if abs(orientation(before,a,b))<=1e-16 && dot(before-a,b-a)>0 {throw MesherError.invalid("轮廓相邻边重叠或折返。")}
            for j in (i+1)..<n where j != (i+1)%n && i != (j+1)%n {
                let c=points[j],d=points[(j+1)%n],margin=(deviations[edgeKey(i,(i+1)%n)] ?? 0)+(deviations[edgeKey(j,(j+1)%n)] ?? 0)+tolerance
                if max(a.x,b.x)+margin<min(c.x,d.x) || max(c.x,d.x)+margin<min(a.x,b.x) || max(a.y,b.y)+margin<min(c.y,d.y) || max(c.y,d.y)+margin<min(a.y,b.y) {continue}
                let o1=orientation(a,b,c),o2=orientation(a,b,d),o3=orientation(c,d,a),o4=orientation(c,d,b)
                if o1*o2<0 && o3*o4<0 {throw MesherError.invalid("轮廓自相交。")}
                let distance=min(distanceToSegment(a,c,d),distanceToSegment(b,c,d),distanceToSegment(c,a,b),distanceToSegment(d,a,b))
                if distance<=margin {throw MesherError.invalid("轮廓接触或在当前曲线误差内无法可靠分离。")}
            }
        }
    }
    private static func edgeMap(_ triangles:[Triangle])throws->[UInt64:[Int]] {
        var map:[UInt64:[Int]]=[:]
        for (i,t) in triangles.enumerated() {for edge in triangleEdges(t) {map[edge,default:[]].append(i)}}
        guard map.values.allSatisfy({$0.count<=2}) else {throw MesherError.invalid("三角面之间出现非流形内部边。")}
        return map
    }
    private static func ccw(_ a:Int,_ b:Int,_ c:Int,points:[Vector3],epsilon:Double)throws->Triangle {
        let area=orientation(points[a],points[b],points[c])
        guard abs(area)>epsilon else {throw MesherError.invalid("细化产生退化三角面，无法保持原始轮廓。")}
        return area>0 ? .init(a:a,b:b,c:c) : .init(a:a,b:c,c:b)
    }
    private static func minimumAngle(_ t:Triangle,points:[Vector3])->Double {
        let p=t.vertices.map {points[$0]}
        return (0..<3).map {i in
            let a=p[(i+1)%3]-p[i],b=p[(i+2)%3]-p[i]
            return atan2(abs(cross(a,b)),dot(a,b))*180/Double.pi
        }.min()!
    }
    /// Move only interior samples within the kernel of their incident face
    /// star. Every trial retains strict CCW faces and does not reduce its
    /// minimum angle. Original curve samples and source parameter chains are
    /// untouched, so the paper region and its total area remain unchanged.
    private static func relax(_ points:inout[Vector3],triangles:[Triangle],fixedCount:Int,
                              epsilon:Double,isCancelled:@Sendable()->Bool)throws {
        guard points.count>fixedCount else {return}
        var neighbors=Array(repeating:Set<Int>(),count:points.count),incident=Array(repeating:[Int](),count:points.count)
        for (i,t) in triangles.enumerated() {
            for v in t.vertices {incident[v].append(i);neighbors[v].formUnion(t.vertices.filter {$0 != v})}
        }
        let ordered=neighbors.map {$0.sorted()}
        for _ in 0..<4 {
            var moved=false
            for i in fixedCount..<points.count {
                if i%64==0 && isCancelled() {throw CancellationError()}
                guard !ordered[i].isEmpty else {continue}
                let original=points[i]
                let average=ordered[i].reduce(Vector3.zero) {$0+points[$1]}/Double(ordered[i].count)
                let delta=average-original
                guard delta.length>1e-12 else {continue}
                let oldMinimum=incident[i].map {minimumAngle(triangles[$0],points:points)}.min()!
                var scale=0.5,accepted=false
                for _ in 0..<12 {
                    points[i]=original+delta*scale
                    let positive=incident[i].allSatisfy {j in let t=triangles[j];return orientation(points[t.a],points[t.b],points[t.c])>epsilon}
                    let newMinimum=positive ? incident[i].map {minimumAngle(triangles[$0],points:points)}.min()! : -1
                    if positive && newMinimum>=oldMinimum-1e-8 {accepted=true;moved=true;break}
                    scale *= 0.5
                }
                if !accepted {points[i]=original}
            }
            if !moved {break}
        }
    }
    private static func improve(_ triangles:inout[Triangle],points:[Vector3],boundary:Set<UInt64>,
                                epsilon:Double,isCancelled:@Sendable()->Bool)throws {
        for pass in 0..<256 {
            if isCancelled() {throw CancellationError()}
            let adjacency=try edgeMap(triangles)
            var touched=Set<Int>(),flips=0
            for key in adjacency.keys.sorted() where !boundary.contains(key) {
                guard let owners=adjacency[key],owners.count==2,!touched.contains(owners[0]),!touched.contains(owners[1]) else {continue}
                let (u,v)=edgeVertices(key)
                guard triangles[owners[0]].vertices.contains(u),triangles[owners[0]].vertices.contains(v),
                      triangles[owners[1]].vertices.contains(u),triangles[owners[1]].vertices.contains(v),
                      let a=triangles[owners[0]].vertices.first(where:{$0 != u && $0 != v}),
                      let b=triangles[owners[1]].vertices.first(where:{$0 != u && $0 != v}),a != b else {continue}
                let replacement=edgeKey(a,b)
                let sideU=orientation(points[a],points[b],points[u]),sideV=orientation(points[a],points[b],points[v])
                // A product-only convexity test admits one almost-collinear
                // replacement face when the other face is large. Such a flip
                // must be skipped, rather than rejecting a valid input panel.
                guard adjacency[replacement]==nil,
                      (sideU>epsilon && sideV < -epsilon) || (sideU < -epsilon && sideV>epsilon) else {continue}
                let triangle=try ccw(u,v,a,points:points,epsilon:epsilon)
                let aa=points[triangle.a]-points[b],bb=points[triangle.b]-points[b],cc=points[triangle.c]-points[b]
                let determinant=aa.lengthSquared*cross(bb,cc)-bb.lengthSquared*cross(aa,cc)+cc.lengthSquared*cross(aa,bb)
                let scale=max(aa.lengthSquared,bb.lengthSquared,cc.lengthSquared)
                let tolerance=max(1e-30,scale*scale*1e-12)
                if determinant>tolerance || (abs(determinant)<=tolerance && replacement<key) {
                    triangles[owners[0]]=try ccw(a,b,u,points:points,epsilon:epsilon)
                    triangles[owners[1]]=try ccw(b,a,v,points:points,epsilon:epsilon)
                    touched.insert(owners[0]);touched.insert(owners[1]);flips += 1
                }
            }
            if flips==0 {return}
            guard pass<255 else {throw MesherError.budgetExceeded("内部 Delaunay 边翻转未能收敛。")}
        }
    }
}
