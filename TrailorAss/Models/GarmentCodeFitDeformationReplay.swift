import Foundation
import CryptoKit
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Source-bound finite-point replay, not a fitted-body or collision capability.
/// The SAME four fitting stages act on all visible and CC0 helper source points.
/// A fitted reference or its pose must never use StandardBody's inverse SDF.
nonisolated enum GarmentCodeFitDeformationReplay {
    typealias M=GarmentCodeBodySurfaceMeasurements
    typealias V=M.V
    static let approvedAuxiliarySHA256="47b71fabd69b9578cf2800ac2e0a7cd05a7fe6b009323d9a49dcfedb5b3aa6f4"
    enum ReplayError:LocalizedError,Sendable {
        case invalid(String)
        var errorDescription:String? {if case let .invalid(s)=self{return "可选拟合场重放无效："+s};return nil}
    }
    enum Pose:Sendable {case identity,arms(alphaDegrees:Double)}
    fileprivate struct Source:Decodable,Sendable {let baseline:[String:Double],positions:[[Double]],triangleIndices:[UInt32]}
    fileprivate struct Rig:Decodable,Sendable {
        struct Point:Decodable,Sendable {let sourceVertexID:Int,templatePositionMeters:[Double],visibleVertexID:Int?}
        struct Joint:Decodable,Sendable {let sourceVertexTableIndices:[Int]}
        struct Bone:Decodable,Sendable {let name:String,parent:Int?,head:Int,tail:Int}
        struct Weights:Decodable,Sendable {let vertexOffsets:[Int],boneIndices:[Int],rawValues:[Double],normalizedValues:[Double],sourcePairOffsets:[Int],rawVertexSums:[Double]}
        let jointSourceVertexTable:[Point],joints:[Joint],bones:[Bone],boneEvaluationOrder:[Int],weights:Weights
    }
    fileprivate struct Auxiliary:Decodable,Sendable {
        let format:String,license:String,sourceCommit:String,weightsSourceSHA256:String,rigResourceSHA256:String,templateResourceSHA256:String
        let sourceVertexCount:Int,jointSourceVertexIDs:[Int],visibleVertexIDs:[Int?],boneNames:[String]
        let vertexOffsets:[Int],boneIndices:[Int],rawValues:[Double],normalizedValues:[Double],sourcePairOffsets:[Int],rawVertexSums:[Double],normalizationOrigins:[String]
    }
    fileprivate struct Point:Sendable {
        let ids:[Int],weights:[Double]
        func value(_ p:[V])->V {zip(ids,weights).reduce(V.zero){$0+p[$1.0]*$1.1}}
    }
    fileprivate struct Metric:Sendable {let definition:M.Definition,points:[Point]}
    struct ShapeData:Encodable,Sendable {
        let sourceGeometrySHA256:String,sourceParameterSHA256:String,templateResourceSHA256:String,rigResourceSHA256:String
        let contractSHA256:String,auxiliaryResourceSHA256:String,fitRecipeSHA256:String,geometrySHA256:String
        let bodyValues:[String:Double],controls:[Double],visiblePositions:[V],helperPositions:[V],restJointAnchors:[V],triangleIndices:[UInt32]
        let bodyCapabilityIssued=false,compatibleWithLegacyInverseSDF=false
        fileprivate let contextIdentity:UUID
        fileprivate init(context:Context,controls:[Double],all:[V]) {
            sourceGeometrySHA256=context.sourceGeometrySHA256;sourceParameterSHA256=context.sourceParameterSHA256
            templateResourceSHA256=context.templateSHA;rigResourceSHA256=context.rigSHA;contractSHA256=M.approvedContractSHA256
            auxiliaryResourceSHA256=approvedAuxiliarySHA256;bodyValues=context.bodyValues;self.controls=controls
            let visible=Array(all[..<context.visibleCount]),helper=Array(all[context.visibleCount...])
            visiblePositions=visible;helperPositions=helper;triangleIndices=context.triangles
            restJointAnchors=context.rig.joints.map{j in mean(j.sourceVertexTableIndices.map{helper[$0]})}
            geometrySHA256=geometryHash(visiblePositions,triangleIndices);contextIdentity=context.identity
            fitRecipeSHA256=recipeHash(source:sourceGeometrySHA256,parameters:sourceParameterSHA256,controls:controls)
        }
    }
    struct PoseData:Encodable,Sendable {
        let sourceGeometrySHA256:String,sourceParameterSHA256:String,fitRecipeSHA256:String
        let bodyValues:[String:Double],templateResourceSHA256:String,contractSHA256:String,poseRecipeSHA256:String
        let matchesInputArmPoseAngle:Bool?
        let fittedRestGeometrySHA256:String,geometrySHA256:String,rigResourceSHA256:String,auxiliaryResourceSHA256:String
        let alphaDegrees:Double?,visiblePositions:[V],helperPositions:[V],triangleIndices:[UInt32]
        /// Rest joints are means of individually fitted source helpers. Posed
        /// bone-frame proxies use their owning bone transform, as the original
        /// rig contract does; they are not means of LBS-skinned helper points.
        let restJointAnchors:[V],posedBoneJointAnchors:[V],boneRotationZRadians:[Double],bonePivots:[V]
        let bodyCapabilityIssued=false,compatibleWithLegacyInverseSDF=false,anatomicalFitCertified=false
    }
    struct Prepared:Sendable {
        private let source:Source,rig:Rig,aux:Auxiliary,measurements:M.Prepared
        private let armMasks:[[Double]],landmarks:[String:Point],metrics:[Metric]
        private let templateSHA:String,rigSHA:String
        init(templateData:Data,rigData:Data,contractData:Data,auxiliaryWeightsData:Data,isCancelled:@Sendable()->Bool={false})throws {
            try checkCancellation(isCancelled)
            guard auxiliaryWeightsData.count<=1_000_000,hash(auxiliaryWeightsData)==approvedAuxiliarySHA256 else {throw ReplayError.invalid("辅助权重不是固定CC0来源。")}
            let m=try M.Prepared(contractData:contractData,templateData:templateData,rigData:rigData,isCancelled:isCancelled)
            let r=try JSONDecoder().decode(Rig.self,from:rigData),a=try JSONDecoder().decode(Auxiliary.self,from:auxiliaryWeightsData)
            let t=try JSONDecoder().decode(Source.self,from:templateData),n=m.contract.visibleVertexCount
            guard a.format=="tailorass-fit-auxiliary-skin-weights-v1",a.license=="CC0-1.0",a.sourceCommit==m.contract.sourceCommit,
                  a.weightsSourceSHA256=="0f3641d651ae3d00ad6b4ccee43142edb109d3bd909d27d9e4139ef1beed8625",
                  a.rigResourceSHA256==hash(rigData),a.templateResourceSHA256==hash(templateData),a.sourceVertexCount==m.contract.sourceVertexCount,
                  a.jointSourceVertexIDs==r.jointSourceVertexTable.map(\.sourceVertexID),a.jointSourceVertexIDs.count==1117,
                  a.visibleVertexIDs==r.jointSourceVertexTable.map(\.visibleVertexID),a.boneNames==r.bones.map(\.name),
                  a.vertexOffsets.count==1118,a.vertexOffsets.first==0,a.vertexOffsets.last==a.boneIndices.count,
                  a.rawValues.count==a.boneIndices.count,a.normalizedValues.count==a.boneIndices.count,a.sourcePairOffsets.count==a.boneIndices.count,
                  a.rawVertexSums.count==1117,a.normalizationOrigins.count==1117,
                  r.weights.vertexOffsets.count==n+1,r.boneEvaluationOrder.sorted()==Array(r.bones.indices),r.joints.count==2*r.bones.count else {throw ReplayError.invalid("辅助点／原骨权重／模板绑定不同。")}
            var overlap=0
            for i in a.jointSourceVertexIDs.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                let l=a.vertexOffsets[i],h=a.vertexOffsets[i+1]
                guard l>=0,h>l,h<=a.boneIndices.count,h-l<=64,
                      a.boneIndices[l..<h].allSatisfy({r.bones.indices.contains($0)}),
                      a.rawValues[l..<h].allSatisfy({$0.isFinite && $0>=0}),a.normalizedValues[l..<h].allSatisfy({$0.isFinite && $0>=0}) else {throw ReplayError.invalid("辅助权重CSR无效。")}
                if let v=a.visibleVertexIDs[i] {
                    let x=r.weights.vertexOffsets[v],y=r.weights.vertexOffsets[v+1]
                    guard a.normalizationOrigins[i]=="pinnedVisibleRig",Array(a.boneIndices[l..<h])==Array(r.weights.boneIndices[x..<y]),
                          Array(a.sourcePairOffsets[l..<h])==Array(r.weights.sourcePairOffsets[x..<y]),
                          sameScalars(Array(a.rawValues[l..<h]),Array(r.weights.rawValues[x..<y])),
                          sameScalars(Array(a.normalizedValues[l..<h]),Array(r.weights.normalizedValues[x..<y])),
                          a.rawVertexSums[i].bitPattern==r.weights.rawVertexSums[v].bitPattern else {throw ReplayError.invalid("重合源点不能重新归一化或丢权重。")}
                    overlap+=1
                } else {
                    let sum=a.rawValues[l..<h].reduce(0,+)
                    guard a.normalizationOrigins[i]=="sequentialAscendingBoneRawNormalization",sum>0,sum.bitPattern==a.rawVertexSums[i].bitPattern,
                          zip(a.rawValues[l..<h],a.normalizedValues[l..<h]).allSatisfy({($0/sum).bitPattern==$1.bitPattern}) else {throw ReplayError.invalid("不可见辅助源权重不符合明确归一化顺序。")}
                }
            }
            guard overlap==135 else {throw ReplayError.invalid("可见与辅助的重合点数不符。")}
            let prefixes=["clavicle.","shoulder01.","upperarm","lowerarm","wrist.","metacarpal","finger"]
            var masks:[[Double]]=[]
            for side in ["L","R"] {
                let selected=Set(r.bones.indices.filter{i in r.bones[i].name.hasSuffix("."+side) && prefixes.contains{r.bones[i].name.hasPrefix($0)}})
                var values:[Double]=[]
                for i in 0..<(n+1117) {
                    if i%128==0 {try checkCancellation(isCancelled)}
                    let offsets=i<n ? r.weights.vertexOffsets:a.vertexOffsets,ids=i<n ? r.weights.boneIndices:a.boneIndices,w=i<n ? r.weights.normalizedValues:a.normalizedValues,j=i<n ? i:i-n
                    let value=(offsets[j]..<offsets[j+1]).reduce(0.0){$0+(selected.contains(ids[$1]) ? w[$1]:0)}
                    guard value.isFinite,value>=0,value<=1+1e-14 else {throw ReplayError.invalid("源局部权重超过有限域。")}
                    values.append(min(1,value))
                }
                masks.append(values)
            }
            var inverse=Array(repeating:-1,count:m.contract.sourceVertexCount)
            for (i,id) in m.contract.visibleToSource.enumerated(){inverse[id]=i}
            func point(_ a:M.Attachment)->Point {.init(ids:a.sourceVertexIDs.map{inverse[$0]},weights:a.weights)}
            self.source=t;rig=r;aux=a;measurements=m;armMasks=masks;landmarks=m.contract.landmarks.mapValues(point)
            metrics=m.contract.measurements.filter{$0.targetUse=="projectFittingReference"}.map{.init(definition:$0,points:$0.samples.map(point))}
            templateSHA=hash(templateData);rigSHA=hash(rigData)
        }
        func context(sourcePositions:[V],triangleIndices:[UInt32],bodyValues:[String:Double],isCancelled:@Sendable()->Bool={false})throws->Context {
            try checkCancellation(isCancelled)
            let report=try measurements.measure(positions:sourcePositions,triangleIndices:triangleIndices,bodyValues:bodyValues,isCancelled:isCancelled)
            let field=try CanonicalField(baseline:source.baseline,values:bodyValues)
            guard triangleIndices==source.triangleIndices,sourcePositions.count==source.positions.count else {throw ReplayError.invalid("原始源拓扑不同。")}
            for i in sourcePositions.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                let q=source.positions[i]
                guard same(sourcePositions[i],field.apply(.init(x:q[0],y:q[1],z:q[2]))) else {throw ReplayError.invalid("拟合起点必须是同参数五尺度原网格，不能重复warp或传入摆姿。")}
            }
            let helper=rig.jointSourceVertexTable.map{q in field.apply(.init(x:q.templatePositionMeters[0],y:q.templatePositionMeters[1],z:q.templatePositionMeters[2]))}
            return try Context(base:sourcePositions+helper,triangles:triangleIndices,rig:rig,aux:aux,armMasks:armMasks,landmarks:landmarks,metrics:metrics,
                sourceGeometrySHA256:report.geometrySHA256,sourceParameterSHA256:report.parameterSHA256,bodyValues:bodyValues,templateSHA:templateSHA,rigSHA:rigSHA,isCancelled:isCancelled)
        }
    }
    struct Context:Sendable {
        fileprivate let base:[V],triangles:[UInt32],rig:Rig,aux:Auxiliary,armMasks:[[Double]],landmarks:[String:Point],metrics:[Metric]
        fileprivate let visibleCount:Int,sourceGeometrySHA256:String,sourceParameterSHA256:String,templateSHA:String,rigSHA:String,identity:UUID
        fileprivate let bodyValues:[String:Double]
        private let chestMask:[Double],wristMasks:[[Double]]
        fileprivate init(base:[V],triangles:[UInt32],rig:Rig,aux:Auxiliary,armMasks:[[Double]],landmarks:[String:Point],metrics:[Metric],
            sourceGeometrySHA256:String,sourceParameterSHA256:String,bodyValues:[String:Double],templateSHA:String,rigSHA:String,isCancelled:@Sendable()->Bool)throws {
            self.base=base;self.triangles=triangles;self.rig=rig;self.aux=aux;self.armMasks=armMasks;self.landmarks=landmarks;self.metrics=metrics
            visibleCount=rig.weights.vertexOffsets.count-1;self.sourceGeometrySHA256=sourceGeometrySHA256;self.sourceParameterSHA256=sourceParameterSHA256;self.bodyValues=bodyValues;self.templateSHA=templateSHA;self.rigSHA=rigSHA;identity=UUID()
            let chestY=(landmarks["chestSurfaceReference.L"]!.value(base).y+landmarks["chestSurfaceReference.R"]!.value(base).y)/2
            chestMask=base.indices.map{max(0,min(1,1-armMasks[0][$0]-armMasks[1][$0]))*window(base[$0].y-chestY,0.030,0.105)}
            var wrist:[[Double]]=[]
            for (side,label) in ["L","R"].enumerated() {
                let points=metrics.first{$0.definition.id=="wristSurfaceLoop."+label}!.points.map{$0.value(base)},center=mean(points),normal=try planeNormal(points,center)
                wrist.append(base.indices.map{armMasks[side][$0]*window(dot(base[$0]-center,normal),0.015,0.070)})
            }
            wristMasks=wrist
            try checkCancellation(isCancelled)
        }
        func deform(controls:[Double],isCancelled:@Sendable()->Bool={false})throws->ShapeData {
            try checkCancellation(isCancelled)
            guard controls.count==4,zip(controls,zip(lower,upper)).allSatisfy({$0.isFinite && $0>=$1.0 && $0<=$1.1}) else {throw ReplayError.invalid("四局部参数超出原有限拟合域。")}
            var p=base
            for i in p.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                let scale=exp(controls[0]*chestMask[i]);p[i].x *= scale;p[i].z *= scale
                p[i].x += controls[1]*0.05*(armMasks[0][i]-armMasks[1][i])
            }
            for (side,label) in ["L","R"].enumerated() {
                let center=landmarks["shoulderSurfaceReference."+label]!.value(p)
                for i in p.indices {if i%128==0 {try checkCancellation(isCancelled)};p[i]=p[i]+(p[i]-center)*expm1(controls[2]*armMasks[side][i])}
            }
            for (side,label) in ["L","R"].enumerated() {
                let q=metrics.first{$0.definition.id=="wristSurfaceLoop."+label}!.points.map{$0.value(p)},center=mean(q),elbow=landmarks["outerElbowSurfaceReference."+label]!.value(p),direction=center-elbow
                guard direction.isFinite,direction.length>1e-9 else {throw ReplayError.invalid("腕环／肘参考轴无效。")}
                let axis=direction/direction.length
                for i in p.indices {if i%128==0 {try checkCancellation(isCancelled)};let delta=p[i]-center,radial=delta-axis*dot(delta,axis);p[i]=p[i]+radial*expm1(controls[3]*wristMasks[side][i])}
            }
            guard p.allSatisfy({$0.isFinite && $0.length<100}) else {throw ReplayError.invalid("拟合场产生非有限或超域坐标。")}
            try overlaps(p,isCancelled)
            try checkCancellation(isCancelled)
            return .init(context:self,controls:controls,all:p)
        }
        func pose(_ shape:ShapeData,pose:Pose,isCancelled:@Sendable()->Bool={false})throws->PoseData {
            try checkCancellation(isCancelled)
            guard shape.contextIdentity==identity,shape.sourceGeometrySHA256==sourceGeometrySHA256,shape.sourceParameterSHA256==sourceParameterSHA256,
                  shape.geometrySHA256==geometryHash(shape.visiblePositions,triangles) else {throw ReplayError.invalid("拟合结果不属于同一源参数实例。")}
            var angles=Array(repeating:0.0,count:rig.bones.count),pivots=Array(repeating:V.zero,count:rig.bones.count),alpha:Double?
            switch pose {
            case .identity:alpha=nil
            case let .arms(degrees):
                guard degrees.isFinite,(0...90).contains(degrees) else {throw ReplayError.invalid("参考摆臂角超出0...90度。")};alpha=degrees
                for side in ["L","R"] {
                    let root=rig.bones.firstIndex{$0.name=="upperarm01."+side}!,elbow=rig.bones.firstIndex{$0.name=="upperarm02."+side}!,pivot=shape.restJointAnchors[rig.bones[root].head],axis=shape.restJointAnchors[rig.bones[elbow].tail]-pivot
                    guard abs(axis.x)>1e-9,axis.y<0 else {throw ReplayError.invalid("拟合后的骨代理不符合当前摆臂约定。")}
                    let rest=atan2(-axis.y,abs(axis.x)),delta=(rest-degrees*Double.pi/180)*(side=="L" ? 1:-1);var affected=Set<Int>()
                    for id in rig.boneEvaluationOrder {let b=rig.bones[id];if id==root || (b.parent != nil && affected.contains(b.parent!)){affected.insert(id);angles[id]=delta;pivots[id]=pivot}}
                }
            }
            func apply(_ point:V,_ bone:Int)->V {
                if angles[bone]==0{return .zero};let q=point-pivots[bone],c=cos(angles[bone])-1,s=sin(angles[bone])
                return .init(x:c*q.x-s*q.y,y:s*q.x+c*q.y,z:0)
            }
            var points=shape.visiblePositions+shape.helperPositions
            for i in points.indices {
                if i%128==0 {try checkCancellation(isCancelled)}
                let original=points[i],w=i<visibleCount ? rig.weights.normalizedValues:aux.normalizedValues,ids=i<visibleCount ? rig.weights.boneIndices:aux.boneIndices,offsets=i<visibleCount ? rig.weights.vertexOffsets:aux.vertexOffsets,j=i<visibleCount ? i:i-visibleCount
                var delta=V.zero
                for k in offsets[j]..<offsets[j+1]{delta=delta+apply(original,ids[k])*w[k]}
                if delta.x != 0 || delta.y != 0 || delta.z != 0 {points[i]=original+delta}
            }
            try overlaps(points,isCancelled)
            var joints=shape.restJointAnchors
            for id in rig.bones.indices {let b=rig.bones[id];for j in [b.head,b.tail]{let delta=apply(joints[j],id);if delta.x != 0 || delta.y != 0 || delta.z != 0 {joints[j]=joints[j]+delta}}}
            guard points.allSatisfy({$0.isFinite && $0.length<100})else{throw ReplayError.invalid("摆臂产生非有限坐标。")}
            try checkCancellation(isCancelled)
            let visible=Array(points[..<visibleCount])
            return .init(sourceGeometrySHA256:sourceGeometrySHA256,sourceParameterSHA256:sourceParameterSHA256,fitRecipeSHA256:shape.fitRecipeSHA256,
                bodyValues:bodyValues,templateResourceSHA256:templateSHA,contractSHA256:M.approvedContractSHA256,poseRecipeSHA256:poseHash(shape.fitRecipeSHA256,alpha),matchesInputArmPoseAngle:alpha.map{bodyValues["arm_pose_angle"]==$0},
                fittedRestGeometrySHA256:shape.geometrySHA256,geometrySHA256:geometryHash(visible,triangles),rigResourceSHA256:rigSHA,auxiliaryResourceSHA256:approvedAuxiliarySHA256,
                alphaDegrees:alpha,visiblePositions:visible,helperPositions:Array(points[visibleCount...]),triangleIndices:triangles,restJointAnchors:shape.restJointAnchors,
                posedBoneJointAnchors:joints,boneRotationZRadians:angles,bonePivots:pivots)
        }
        private func overlaps(_ p:[V],_ cancel:@Sendable()->Bool)throws {
            for i in aux.visibleVertexIDs.indices {
                if i%128==0 {try checkCancellation(cancel)}
                if let v=aux.visibleVertexIDs[i] {guard same(p[v],p[visibleCount+i]) else {throw ReplayError.invalid("135重合源点没有逐位共享同一拟合／摆姿变形。")}}
            }
        }
    }
    private struct CanonicalField {
        let ws:Double,hs:Double,hy:Double,ly:Double,uy:Double,bl:Double
        init(baseline b:[String:Double],values v:[String:Double])throws {
            guard let h=v["height"],let w=v["waist"],let p=v["hips"],let l=v["hips_line"],let y=v["_waist_level"],let bh=b["height"],let bw=b["waist"],let bp=b["hips"],let bl=b["hipLine"],let by=b["waistLevel"] else {throw ReplayError.invalid("原始五尺度参数缺失。")}
            ws=w/100/bw;hs=p/100/bp;hy=l/100/bl;ly=(y-l)/100/(by-bl);uy=(h-y)/100/(bh-by);self.bl=bl
            guard [ws,hs,hy,ly,uy].allSatisfy({$0.isFinite && (0.5...1.8).contains($0)})else{throw ReplayError.invalid("原始五尺度超出旧有限域。")}
        }
        func apply(_ q:V)->V {let y=q.y,t=max(0,min(1,(y+bl)/bl)),blend=t*t*(3-2*t),h=hs+(ws-hs)*blend;let yy=y>=0 ? y*uy:(y >= -bl ? y*hy:-bl*hy+(y+bl)*ly);return .init(x:q.x*h,y:yy,z:q.z*h)}
    }
    private static func checkCancellation(_ cancelled:@Sendable()->Bool)throws {
        if cancelled(){throw CancellationError()}
        #if os(macOS)
        let nearest=Darwin.fegetround()==FE_TONEAREST
        #elseif canImport(NativeClothCollision)
        let nearest=FloatingPointEnvironment.isNearestRounding
        #else
        let nearest=false
        #endif
        guard nearest else {throw ReplayError.invalid("不支持当前浮点舍入环境。")}
    }
    private static func poseHash(_ shapeRecipe:String,_ alpha:Double?)->String {
        var d=Data(("body-fit-original-rig-pose-v1\0"+shapeRecipe+"\0").utf8)
        if let alpha {d.append(1);var bits=alpha.bitPattern.littleEndian;withUnsafeBytes(of:&bits){d.append(contentsOf:$0)}}else{d.append(0)}
        return hash(d)
    }
    private static let lower=[log(0.75),-1.4,log(0.65),log(0.7)],upper=[log(1.3),1.4,log(1.2),log(1.4)]
    private static func window(_ x:Double,_ inner:Double,_ outer:Double)->Double {let t=max(0,min(1,(abs(x)-inner)/(outer-inner)));return 1-t*t*(3-2*t)}
    private static func dot(_ a:V,_ b:V)->Double{a.x*b.x+a.y*b.y+a.z*b.z}
    private static func mean(_ p:[V])->V{p.reduce(V.zero,+)/Double(p.count)}
    private static func same(_ a:V,_ b:V)->Bool{a.x.bitPattern==b.x.bitPattern && a.y.bitPattern==b.y.bitPattern && a.z.bitPattern==b.z.bitPattern}
    private static func sameScalars(_ a:[Double],_ b:[Double])->Bool{a.count==b.count && zip(a,b).allSatisfy{$0.bitPattern==$1.bitPattern}}
    private static func hash(_ d:Data)->String {SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
    private static func geometryHash(_ p:[V],_ t:[UInt32])->String {var d=Data("rigid-clearance-visible-body-v1\0".utf8);func add<T:FixedWidthInteger>(_ x:T){var q=x.littleEndian;withUnsafeBytes(of:&q){d.append(contentsOf:$0)}};add(UInt64(p.count));add(UInt64(t.count));for q in p{add(q.x.bitPattern);add(q.y.bitPattern);add(q.z.bitPattern)};for x in t{add(x)};return hash(d)}
    private static func recipeHash(source:String,parameters:String,controls:[Double])->String {var d=Data(("body-fit-four-field-replay-v1\0"+source+"\0"+parameters+"\0"+M.approvedContractSHA256+"\0"+approvedAuxiliarySHA256).utf8);for x in controls{var q=x.bitPattern.littleEndian;withUnsafeBytes(of:&q){d.append(contentsOf:$0)}};return hash(d)}
    private static func planeNormal(_ p: [V], _ center: V) throws -> V {
        var a = Array(repeating: [Double](repeating: 0, count: 3), count: 3)
        for point in p { let q = point - center, d = [q.x, q.y, q.z]; for i in 0..<3 { for j in 0..<3 { a[i][j] += d[i] * d[j] } } }
        var v = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
        for _ in 0..<32 {
            let pair = [(0, 1), (0, 2), (1, 2)].max { abs(a[$0.0][$0.1]) < abs(a[$1.0][$1.1]) }!, i = pair.0, j = pair.1
            if abs(a[i][j]) < 1e-20 { break }
            let tau = (a[j][j] - a[i][i]) / (2 * a[i][j]), t = (tau >= 0 ? 1.0 : -1.0) / (abs(tau) + sqrt(1 + tau * tau))
            let c = 1 / sqrt(1 + t * t), s = t * c, off = a[i][j]
            a[i][i] -= t * off; a[j][j] += t * off; a[i][j] = 0; a[j][i] = 0
            for k in 0..<3 where k != i && k != j { let x = a[k][i], y = a[k][j]; a[k][i] = c * x - s * y; a[i][k] = a[k][i]; a[k][j] = s * x + c * y; a[j][k] = a[k][j] }
            for k in 0..<3 { let x = v[k][i], y = v[k][j]; v[k][i] = c * x - s * y; v[k][j] = s * x + c * y }
        }
        let k = (0..<3).min { a[$0][$0] < a[$1][$1] }!, result = V(x: v[0][k], y: v[1][k], z: v[2][k])
        guard result.isFinite, result.length > 0 else { throw ReplayError.invalid("固定腕环没有可靠的参考法向。") }
        return result / result.length
    }
}
