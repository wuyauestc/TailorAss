import Foundation
import NativeClothCollision

/// A PSD algorithmic approximation for the joint objective, never a replacement
/// for its actual energy/gradient/Hv or source/body/self acceptance checks.
nonisolated enum GarmentCodeJointPreconditioner {
    typealias J=GarmentCodeJointObjective
    typealias H=GarmentCodeHingeBending
    typealias V=GarmentCodeCircleDrape.Vector3
    enum PreconditionerError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded,staleFactor
        var errorDescription:String? {
            switch self {
            case let .invalid(s):return "布料预条件器无效："+s
            case .budgetExceeded:return "布料预条件器超出工作预算。"
            case .staleFactor:return "布料预条件器尚未成功更新到当前状态。"
            }
        }
    }
    struct Limits:Sendable {
        var linear=NativeSparseCholesky.Limits()
        var maximumSourceTriangles=40_000
        var maximumHinges=60_000
        var maximumScatterBytes=64*1_024*1_024
        var principalBarrier=J.M.BarrierPreconditionerLimits()
    }
    struct Scatter:Sendable {let a:Int,b:Int,offset:Int}
    struct Plan:Sendable {
        let prepared:J.Prepared,limits:Limits
        let dimension:Int,columnStarts:[Int64],rowIndices:[Int32]
        let sourceScatter:[[Scatter]],sewingScatter:[[Scatter]],hingeScatter:[[Scatter]],massOffsets:[Int]
        let scatterBytes:Int
        init(prepared:J.Prepared,limits:Limits=Limits(),isCancelled:@Sendable()->Bool={false})throws {
            if isCancelled(){throw CancellationError()}
            let n=prepared.massesKg.count
            guard n>0,n<=Int(Int32.max)/3,limits.maximumSourceTriangles>0,limits.maximumHinges>0,limits.maximumScatterBytes>0,
                  (1...40_000).contains(limits.principalBarrier.maximumBlocks),(1...128*1_024*1_024).contains(limits.principalBarrier.maximumStagedBytes),
                  prepared.membrane.vertexCount==n,prepared.massesKg.allSatisfy({$0.isFinite && $0>0}),
                  prepared.material.shearStiffnessNewtonPerMeter.isFinite,prepared.material.shearStiffnessNewtonPerMeter>0,
                  prepared.material.areaStiffnessNewtonPerMeter.isFinite,prepared.material.areaStiffnessNewtonPerMeter>=0,
                  prepared.sewingStiffnessNewtonPerMeter.isFinite,prepared.sewingStiffnessNewtonPerMeter>0,
                  prepared.bendingMaterial.bendingStiffnessNewtonMeter.isFinite,prepared.bendingMaterial.bendingStiffnessNewtonMeter>=0 else {
                throw PreconditionerError.invalid("需要同一源的正物理质量、材料与真实接缝。")
            }
            let dofs=3*n
            guard dofs<=limits.linear.maximumDegreesOfFreedom,prepared.membrane.triangles.count<=limits.maximumSourceTriangles else {throw PreconditionerError.budgetExceeded}
            let bendingEnabled=prepared.bendingMaterial.bendingStiffnessNewtonMeter>0
            if bendingEnabled {
                guard prepared.bending.vertexCount==n,prepared.bending.triangleCount==prepared.membrane.triangles.count else {
                    throw PreconditionerError.invalid("弯曲源顶点或三角面与膜源不一致。")
                }
                guard prepared.bending.hinges.count<=limits.maximumHinges else {throw PreconditionerError.budgetExceeded}
            }
            var keys=Set<Int64>()
            func insert(_ row:Int,_ column:Int)throws {
                if row>=column {keys.insert(Int64(row)*Int64(dofs)+Int64(column))}
                if keys.count>limits.linear.maximumLowerNonzeros {throw PreconditionerError.budgetExceeded}
            }
            for (index,t) in prepared.membrane.triangles.enumerated() {
                if index%64==0 && isCancelled(){throw CancellationError()}
                guard [t.a,t.b,t.c].allSatisfy({(0..<n).contains($0)}),t.referenceAreaSquareMeters.isFinite,t.referenceAreaSquareMeters>0,
                      [t.du[0],t.du[1],t.du[2],t.dv[0],t.dv[1],t.dv[2]].allSatisfy(\.isFinite) else {throw PreconditionerError.invalid("源三角面无效。")}
                let ids=[t.a,t.b,t.c]
                for a in 0..<9 {for b in 0..<9 {try insert(3*ids[a/3]+a%3,3*ids[b/3]+b%3)}}
            }
            for (index,row) in prepared.sewingRows.enumerated() {
                if index%64==0 && isCancelled(){throw CancellationError()}
                guard row.vertexIDs.count==row.coefficients.count,row.vertexIDs.count<=4,
                      row.vertexIDs.allSatisfy({(0..<n).contains($0)}),row.coefficients.allSatisfy(\.isFinite) else {throw PreconditionerError.invalid("接缝行无效。")}
                for a in row.vertexIDs {for b in row.vertexIDs {for i in 0..<3 {for j in 0..<3 {try insert(3*a+i,3*b+j)}}}}
            }
            if bendingEnabled {
                for (index,h) in prepared.bending.hinges.enumerated() {
                    if index%64==0 && isCancelled(){throw CancellationError()}
                    guard h.vertexIDs.count==4,Set(h.vertexIDs).count==4,h.vertexIDs.allSatisfy({(0..<n).contains($0)}),
                          h.sourceTriangleIDs.count==2,h.sourceTriangleIDs.allSatisfy({prepared.membrane.triangles.indices.contains($0)}),
                          h.sourceWeight.isFinite,h.sourceWeight>0 else {throw PreconditionerError.invalid("内部铰链源或权重无效。")}
                    // Both opposite vertices must couple. Source-face 9x9
                    // patterns alone omit this essential part of q q^T.
                    for a in h.vertexIDs {for b in h.vertexIDs {for i in 0..<3 {for j in 0..<3 {try insert(3*a+i,3*b+j)}}}}
                }
            }
            for dof in 0..<dofs {try insert(dof,dof)}
            let ordered=keys.sorted{a,b in a%Int64(dofs)==b%Int64(dofs) ? a/Int64(dofs)<b/Int64(dofs):a%Int64(dofs)<b%Int64(dofs)}
            var columns=Array(repeating:Int64(0),count:dofs+1),rows:[Int32]=[],lookup:[Int64:Int]=[:]
            rows.reserveCapacity(ordered.count);lookup.reserveCapacity(ordered.count)
            for (index,key) in ordered.enumerated(){columns[Int(key%Int64(dofs))+1]+=1;rows.append(Int32(key/Int64(dofs)));lookup[key]=index}
            for i in 0..<dofs {columns[i+1]+=columns[i]}
            var bytes=0
            func scatter(_ ids:[Int])throws->[Scatter] {
                var result:[Scatter]=[]
                for a in 0..<(3*ids.count){for b in 0..<(3*ids.count){
                    let r=3*ids[a/3]+a%3,c=3*ids[b/3]+b%3
                    if r>=c {guard let offset=lookup[Int64(r)*Int64(dofs)+Int64(c)] else {throw PreconditionerError.invalid("稀疏模式不完整。")};result.append(.init(a:a,b:b,offset:offset))}
                }}
                let (more,overflow)=result.count.multipliedReportingOverflow(by:MemoryLayout<Scatter>.stride)
                guard !overflow,bytes<=limits.maximumScatterBytes-more else {throw PreconditionerError.budgetExceeded};bytes+=more
                return result
            }
            var source:[[Scatter]]=[],sewing:[[Scatter]]=[],hinges:[[Scatter]]=[]
            for (index,t) in prepared.membrane.triangles.enumerated(){if index%64==0 && isCancelled(){throw CancellationError()};source.append(try scatter([t.a,t.b,t.c]))}
            for row in prepared.sewingRows {if isCancelled(){throw CancellationError()};sewing.append(try scatter(row.vertexIDs))}
            if bendingEnabled {for h in prepared.bending.hinges {if isCancelled(){throw CancellationError()};hinges.append(try scatter(h.vertexIDs))}}
            let mass=(0..<dofs).map{lookup[Int64($0)*Int64(dofs)+Int64($0)]!}
            self.prepared=prepared;self.limits=limits;dimension=dofs;columnStarts=columns;rowIndices=rows
            sourceScatter=source;sewingScatter=sewing;hingeScatter=hinges;massOffsets=mass;scatterBytes=bytes
            if isCancelled(){throw CancellationError()}
        }
        /// Exact comparison of the components used by P, not a probabilistic hash.
        /// Barrier parameters and active hinge GN must match their source.
        /// Body/self terms are added separately by the contact workspace.
        func matches(_ p:J.Prepared)->Bool {
            guard p.massesKg==prepared.massesKg,p.membrane.triangles.count==prepared.membrane.triangles.count,
                  p.sewingRows.count==prepared.sewingRows.count,p.sewingStiffnessNewtonPerMeter==prepared.sewingStiffnessNewtonPerMeter,
                  p.material.shearStiffnessNewtonPerMeter==prepared.material.shearStiffnessNewtonPerMeter,
                  p.material.areaStiffnessNewtonPerMeter==prepared.material.areaStiffnessNewtonPerMeter,
                  p.bendingMaterial.bendingStiffnessNewtonMeter==prepared.bendingMaterial.bendingStiffnessNewtonMeter,
                  p.strainBarrier.lowerLimit==prepared.strainBarrier.lowerLimit,p.strainBarrier.lowerActivation==prepared.strainBarrier.lowerActivation,
                  p.strainBarrier.upperActivation==prepared.strainBarrier.upperActivation,p.strainBarrier.upperLimit==prepared.strainBarrier.upperLimit,
                  p.strainBarrier.stiffnessNewtonPerMeter==prepared.strainBarrier.stiffnessNewtonPerMeter else{return false}
            for (a,b) in zip(p.membrane.triangles,prepared.membrane.triangles) {
                if a.a != b.a || a.b != b.b || a.c != b.c || a.du != b.du || a.dv != b.dv || a.referenceAreaSquareMeters != b.referenceAreaSquareMeters {return false}
            }
            for (a,b) in zip(p.sewingRows,prepared.sewingRows) {if a.vertexIDs != b.vertexIDs || a.coefficients != b.coefficients || a.initialGapMeters != b.initialGapMeters{return false}}
            if prepared.bendingMaterial.bendingStiffnessNewtonMeter>0 {
                let a=p.bending,b=prepared.bending
                guard a.vertexCount==b.vertexCount,a.triangleCount==b.triangleCount,a.boundaryEdgeCount==b.boundaryEdgeCount,
                      a.panelHingeCounts==b.panelHingeCounts,a.hinges.count==b.hinges.count else{return false}
                for (x,y) in zip(a.hinges,b.hinges) {
                    if x.vertexIDs != y.vertexIDs || x.panelID != y.panelID || x.sourceTriangleIDs != y.sourceTriangleIDs ||
                        x.sourceEdgeLengthMeters != y.sourceEdgeLengthMeters || x.sourceFirstCrossNormSquareMeters != y.sourceFirstCrossNormSquareMeters ||
                        x.sourceSecondCrossNormSquareMeters != y.sourceSecondCrossNormSquareMeters ||
                        x.sourceAdjacentAreaSquareMeters != y.sourceAdjacentAreaSquareMeters || x.sourceWeight != y.sourceWeight {return false}
                }
            }
            return true
        }
        func makeWorkspace(isCancelled:@Sendable()->Bool={false})throws->Workspace {try Workspace(plan:self,isCancelled:isCancelled)}
    }
    struct UpdateReport:Sendable {
        let linear:NativeSparseCholesky.Diagnostics
        let assemblySeconds:Double,refactorSeconds:Double,maximumPolarOrthogonalityError:Double
        let minimumTrueSewingTransverseStiffness:Double?,maximumTrueSewingTransverseStiffness:Double?
        let negativeTransverseRowsClippedOnlyInPreconditioner:Int
        let hingeGaussNewtonCount:Int,hingeAssemblySeconds:Double
        let principalBarrierTriangles:Int,principalBarrierAssemblySeconds:Double,principalBarrierStagedBytes:Int
        let omittedTerms:[String]
    }
    struct SolveReport:Sendable {
        let vector:[V],linear:NativeSparseCholesky.Diagnostics,applySeconds:Double
    }
    /// Mutable numeric data remains serial in one worker; no Sendable assertion.
    final class Workspace {
        let plan:Plan
        private let linear:NativeSparseCholesky
        private(set) var lowerValues:[Double]=[]
        private(set) var latest:UpdateReport?
        init(plan:Plan,isCancelled:@Sendable()->Bool={false})throws {
            self.plan=plan
            linear=try NativeSparseCholesky(dimension:plan.dimension,columnStarts:plan.columnStarts,rowIndices:plan.rowIndices,limits:plan.limits.linear,isCancelled:isCancelled)
        }
        @discardableResult func update(frame:J.Frame,positions x:[V],isCancelled:@Sendable()->Bool={false})throws->UpdateReport {
            linear.invalidate();latest=nil;lowerValues=[]
            if isCancelled(){throw CancellationError()}
            guard plan.matches(frame.prepared),x.count==plan.prepared.massesKg.count,x.allSatisfy({$0.isFinite && $0.length<100}),
                  frame.timeStepSeconds.isFinite,(1e-5...1).contains(frame.timeStepSeconds),frame.sewingRamp.isFinite,(0...1).contains(frame.sewingRamp) else {
                throw PreconditionerError.invalid("必须使用同一源和当前Frame的有限位置、时间步长与收紧比例。")
            }
            let stamp=Date(),p=plan.prepared,mu=p.material.shearStiffnessNewtonPerMeter,lambda=p.material.areaStiffnessNewtonPerMeter
            let inverseTimeSquared=1/(frame.timeStepSeconds*frame.timeStepSeconds)
            var values=Array(repeating:0.0,count:plan.rowIndices.count),maximumOrthogonality=0.0
            for i in x.indices {let weight=p.massesKg[i]*inverseTimeSquared;guard weight.isFinite && weight>0 else {throw PreconditionerError.invalid("物理惯性无效。")};for axis in 0..<3 {values[plan.massOffsets[3*i+axis]]=weight}}
            for (id,t) in p.membrane.triangles.enumerated() {
                if id%64==0 && isCancelled(){throw CancellationError()}
                let u=(x[t.b]-x[t.a])*t.du[1]+(x[t.c]-x[t.a])*t.du[2],v=(x[t.b]-x[t.a])*t.dv[1]+(x[t.c]-x[t.a])*t.dv[2]
                let a=dot(u,u),b=dot(u,v),c=dot(v,v),j=cross(u,v).length,denominator=j*sqrt(a+c+2*j)
                guard j>1e-10,denominator.isFinite,denominator>0 else {throw PreconditionerError.invalid("源三角面已退化。")}
                let ru=(u*(c+j)-v*b)/denominator,rv=(v*(a+j)-u*b)/denominator
                maximumOrthogonality=max(maximumOrthogonality,abs(dot(ru,ru)-1),abs(dot(rv,rv)-1),abs(dot(ru,rv)))
                let uu=[ru.x,ru.y,ru.z],vv=[rv.x,rv.y,rv.z];var B=Array(repeating:0.0,count:27)
                for i in 0..<3 {for axis in 0..<3 {B[3*i+axis]=t.du[i]*uu[axis];B[9+3*i+axis]=t.dv[i]*vv[axis];B[18+3*i+axis]=t.dv[i]*uu[axis]+t.du[i]*vv[axis]}}
                for e in plan.sourceScatter[id] {
                    let i=e.a,k=e.b
                    values[e.offset]+=t.referenceAreaSquareMeters*(((lambda+2*mu)*B[i]+lambda*B[9+i])*B[k]+(lambda*B[i]+(lambda+2*mu)*B[9+i])*B[9+k]+mu*B[18+i]*B[18+k])
                }
            }
            let barrierStamp=Date()
            let barrier=try p.membrane.principalBarrierPreconditioner(positions:x,barrier:p.strainBarrier,limits:plan.limits.principalBarrier,isCancelled:isCancelled)
            for block in barrier.blocks {
                if isCancelled(){throw CancellationError()}
                for e in plan.sourceScatter[block.triangleID] {values[e.offset]+=block.hessian[9*e.a+e.b]}
            }
            let barrierSeconds=Date().timeIntervalSince(barrierStamp)
            var minimum:Double?,maximum:Double?,clipped=0
            let k=frame.sewingStiffnessNewtonPerMeter
            for (index,row) in p.sewingRows.enumerated() {
                if index%64==0 && isCancelled(){throw CancellationError()}
                if row.vertexIDs.isEmpty {continue}
                let target=frame.sewingTargetMeters(row)
                let delta=zip(row.vertexIDs,row.coefficients).reduce(V.zero){$0+x[$1.0]*$1.1},length=delta.length
                var normal=[0.0,0,0],tau=1.0
                if target != 0 {
                    guard length>0 && length.isFinite else {throw PreconditionerError.invalid("非零目标接缝的两端已重合。")}
                    let signed=1-target/length;minimum=min(minimum ?? signed*k,signed*k);maximum=max(maximum ?? signed*k,signed*k)
                    if signed<0 {clipped+=1};tau=max(0,signed);normal=[delta.x/length,delta.y/length,delta.z/length]
                } else {minimum=min(minimum ?? k,k);maximum=max(maximum ?? k,k)}
                for e in plan.sewingScatter[index] {
                    let a=e.a%3,b=e.b%3,coefficient=row.coefficients[e.a/3]*row.coefficients[e.b/3]
                    values[e.offset]+=coefficient*k*((a==b ? tau:0)+(1-tau)*normal[a]*normal[b])
                }
            }
            let hingeStamp=Date(),kb=p.bendingMaterial.bendingStiffnessNewtonMeter
            if kb>0 {
                // Use the public, source-domain checked angle derivative. Do
                // not replace true objective Hv with this PSD approximation.
                for (index,h) in p.bending.hinges.enumerated() {
                    if index%64==0 && isCancelled(){throw CancellationError()}
                    let angle=try frame.prepared.bending.angle(positions:x,hingeID:index,isCancelled:isCancelled)
                    let coefficient=2*kb*h.sourceWeight,q=angle.gradientPerMeter.flatMap{[$0.x,$0.y,$0.z]}
                    guard q.count==12,q.allSatisfy(\.isFinite),coefficient.isFinite,coefficient>0 else {
                        throw PreconditionerError.invalid("内部铰链 GN 导数或系数无效。")
                    }
                    for e in plan.hingeScatter[index] {values[e.offset]+=coefficient*q[e.a]*q[e.b]}
                }
            }
            let hingeSeconds=kb>0 ? Date().timeIntervalSince(hingeStamp):0
            guard values.allSatisfy(\.isFinite),maximumOrthogonality.isFinite else {throw PreconditionerError.invalid("预条件矩阵溢出。")}
            if isCancelled(){throw CancellationError()}
            let assemblySeconds=Date().timeIntervalSince(stamp),factorStamp=Date()
            let diagnostics=try linear.refactor(values:values,isCancelled:isCancelled)
            let result=UpdateReport(linear:diagnostics,assemblySeconds:assemblySeconds,refactorSeconds:Date().timeIntervalSince(factorStamp),maximumPolarOrthogonalityError:maximumOrthogonality,
                minimumTrueSewingTransverseStiffness:minimum,maximumTrueSewingTransverseStiffness:maximum,negativeTransverseRowsClippedOnlyInPreconditioner:clipped,
                hingeGaussNewtonCount:kb>0 ? p.bending.hinges.count:0,hingeAssemblySeconds:hingeSeconds,
                principalBarrierTriangles:barrier.blocks.count,principalBarrierAssemblySeconds:barrierSeconds,principalBarrierStagedBytes:barrier.chargedStagedBytes,
                omittedTerms:kb>0 ? ["exact hinge curvature beyond Gauss-Newton","body/self contact","friction"]:["hinge bending","body/self contact","friction"])
            lowerValues=values;latest=result;return result
        }
        func solve(rhs:[V],generation:UInt64,isCancelled:@Sendable()->Bool={false})throws->SolveReport {
            guard latest?.linear.generation==generation else {throw PreconditionerError.staleFactor}
            let stamp=Date()
            do {
                let solution=try linear.solve(rhs:rhs.flatMap{[$0.x,$0.y,$0.z]},generation:generation,isCancelled:isCancelled)
                let vector=stride(from:0,to:solution.values.count,by:3).map{V(x:solution.values[$0],y:solution.values[$0+1],z:solution.values[$0+2])}
                return .init(vector:vector,linear:solution.diagnostics,applySeconds:Date().timeIntervalSince(stamp))
            } catch {latest=nil;lowerValues=[];throw error}
        }
        /// Diagnostic multiplication by the current represented P, not true Hv.
        func product(_ vector:[V])throws->[V] {
            guard latest != nil,vector.count*3==plan.dimension,lowerValues.count==plan.rowIndices.count else {throw PreconditionerError.staleFactor}
            let x=vector.flatMap{[$0.x,$0.y,$0.z]};var y=Array(repeating:0.0,count:plan.dimension)
            for col in 0..<plan.dimension {for t in Int(plan.columnStarts[col])..<Int(plan.columnStarts[col+1]) {let row=Int(plan.rowIndices[t]),v=lowerValues[t];y[row]+=v*x[col];if row != col {y[col]+=v*x[row]}}}
            return stride(from:0,to:y.count,by:3).map{V(x:y[$0],y:y[$0+1],z:y[$0+2])}
        }
    }
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func cross(_ a:V,_ b:V)->V {V(x:a.y*b.z-a.z*b.y,y:a.z*b.x-a.x*b.z,z:a.x*b.y-a.y*b.x)}
}
