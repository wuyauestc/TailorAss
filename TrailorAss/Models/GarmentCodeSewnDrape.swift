import Foundation

/// Assembly helpers for separate, source-faithful panel degrees of freedom.
/// Existing welded-skirt controls continue to use their original solver path.
nonisolated enum GarmentCodeSewnDrape {
    typealias Kernel = GarmentCodeCircleDrape
    typealias Sewing = GarmentCodeSewing
    typealias Contact = GarmentCodeClothContact

    /// Optional numerical assembly before applying the full garment weight.
    /// It preserves source metrics, masses, pins and all final quality gates.
    /// Immediate loading remains the existing verified default.
    struct AssemblySchedule: Codable, Sendable {
        let staticFrames: Int
        let gravityRampFrames: Int
        static let immediate = AssemblySchedule(staticFrames: 0, gravityRampFrames: 0)
        func gravityFraction(step: Int) -> Double {
            if step < staticFrames { return 0 }
            if gravityRampFrames == 0 { return 1 }
            return min(1,Double(step-staticFrames+1)/Double(gravityRampFrames))
        }
    }

    /// Explicit numerical options for integrating the multi-component path.
    /// Defaults retain the existing waistband control. Options never alter
    /// source edges, masses, pins or final acceptance thresholds.
    struct CouplingOptions: Codable, Sendable {
        var timeStepSeconds: Double = 1.0/120
        var selfContactPaddingMeters: Double = 0.005
        var projectVirtualSewingPoints = false
        var useSourcePathBounds = false
        var sourceAwareContactRibbons = false
        var simultaneousFinalSewing = false
        var useContinuousBodyContact = false
    }

    /// Translate runtime seam provenance into boundary-only contact rules.
    /// Ordinary seams include their actual linear boundary intervals. Gathered
    /// and eased seams permit only the finite tacks supplied by the planner;
    /// their untacked fold nodes keep ordinary surface contact.
    static func contactTopology(vertexCount:Int,triangleIndices:[UInt32],plan:Sewing.Plan,
        referencePositions:[Kernel.Vector3]?=nil,
        isCancelled:@Sendable()->Bool={false}) throws -> Contact.Topology {
        if isCancelled() { throw CancellationError() }
        guard (3...20_000).contains(vertexCount),!triangleIndices.isEmpty,
              triangleIndices.count<=120_000,plan.contactNeighborhoods.count<=40_000,
              plan.ordinaryBoundaryIntervals.count<=40_000 else { throw Contact.ContactError.budgetExceeded }
        func point(_ attachment:Sewing.Attachment)->Contact.BoundaryPoint {
            .init(vertexIDs:attachment.vertexIDs,weights:attachment.weights)
        }
        var incident=Array(repeating:[Int](),count:vertexCount)
        guard triangleIndices.count%3==0 else { throw Contact.ContactError.invalid("缝合接触网格的三角面数组无效。") }
        for offset in stride(from:0,to:triangleIndices.count,by:3) {
            for j in 0..<3 {
                let vertex=Int(triangleIndices[offset+j])
                guard incident.indices.contains(vertex) else { throw Contact.ContactError.invalid("缝合接触三角面引用了无效顶点。") }
                incident[vertex].append(offset/3)
            }
        }
        func faces(_ location:Sewing.Location)throws->[Int] {
            guard location.attachment.vertexIDs.allSatisfy({incident.indices.contains($0)}) else {
                throw Contact.ContactError.invalid("缝合接触附着点引用了无效顶点。")
            }
            if location.attachment.vertexIDs.count==1 {
                return incident[location.attachment.vertexIDs[0]]
            }
            return Set(location.boundarySegments.map(\.adjacentTriangleID)).sorted()
        }
        var contacts:[Contact.SewnBoundaryContact]=[]
        for (index,neighborhood) in plan.contactNeighborhoods.enumerated() {
            if index%64 == 0 && isCancelled() { throw CancellationError() }
            // A shared dart corner already has one topological attachment;
            // there is no independent contact surface to exempt at that tack.
            if neighborhood.a.attachment==neighborhood.b.attachment { continue }
            let firstFaces=try faces(neighborhood.a),secondFaces=try faces(neighborhood.b)
            for first in firstFaces { for second in secondFaces {
                if first==second { continue }
                let a=point(neighborhood.a.attachment),b=point(neighborhood.b.attachment)
                contacts.append(.init(firstTriangle:first,secondTriangle:second,
                    firstStart:a,firstEnd:a,secondStart:b,secondEnd:b))
                guard contacts.count<=40_000 else { throw Contact.ContactError.budgetExceeded }
            } }
        }
        // Three or more panels can meet at one sewn source corner. Direct
        // stitch pairs alone omit the other pairs at that same physical
        // point, causing their contact padding to tear the junction apart.
        // Close only the graph of real endpoint-to-endpoint source stitches;
        // this does not weld particles or exempt any face-interior crossing.
        var parent=Array(0..<vertexCount),cornerVertices=Set<Int>(),directCornerPairs=Set<UInt64>()
        func root(_ vertex:Int)->Int {
            var cursor=vertex
            while parent[cursor] != cursor {cursor=parent[cursor]}
            return cursor
        }
        func cornerKey(_ a:Int,_ b:Int)->UInt64 {(UInt64(min(a,b))<<32)|UInt64(max(a,b))}
        for neighborhood in plan.contactNeighborhoods {
            let a=neighborhood.a,b=neighborhood.b
            guard a.attachment.vertexIDs.count==1,b.attachment.vertexIDs.count==1,
                  a.sourceArcFraction==0 || a.sourceArcFraction==1,
                  b.sourceArcFraction==0 || b.sourceArcFraction==1 else {continue}
            let first=a.attachment.vertexIDs[0],second=b.attachment.vertexIDs[0]
            guard first != second else {continue}
            parent[root(second)]=root(first)
            cornerVertices.insert(first);cornerVertices.insert(second)
            directCornerPairs.insert(cornerKey(first,second))
        }
        var junctions:[Int:[Int]]=[:]
        for vertex in cornerVertices.sorted() {junctions[root(vertex),default:[]].append(vertex)}
        for key in junctions.keys.sorted() {
            let vertices=junctions[key]!
            guard vertices.count>2 else {continue}
            for i in vertices.indices {
                if isCancelled() {throw CancellationError()}
                for j in vertices.indices where j>i {
                    let a=vertices[i],b=vertices[j]
                    if directCornerPairs.contains(cornerKey(a,b)) {continue}
                    let first=Contact.BoundaryPoint(vertexIDs:[a],weights:[1])
                    let second=Contact.BoundaryPoint(vertexIDs:[b],weights:[1])
                    for firstFace in incident[a] {for secondFace in incident[b] where firstFace != secondFace {
                        contacts.append(.init(firstTriangle:firstFace,secondTriangle:secondFace,
                            firstStart:first,firstEnd:first,secondStart:second,secondEnd:second))
                        guard contacts.count<=40_000 else {throw Contact.ContactError.budgetExceeded}
                    }}
                }
            }
        }
        for interval in plan.ordinaryBoundaryIntervals {
            if isCancelled() { throw CancellationError() }
            if interval.aSegment.adjacentTriangleID==interval.bSegment.adjacentTriangleID { continue }
            contacts.append(.init(firstTriangle:interval.aSegment.adjacentTriangleID,
                secondTriangle:interval.bSegment.adjacentTriangleID,
                firstStart:point(interval.aStart.attachment),firstEnd:point(interval.aEnd.attachment),
                secondStart:point(interval.bStart.attachment),secondEnd:point(interval.bEnd.attachment)))
            guard contacts.count<=40_000 else { throw Contact.ContactError.budgetExceeded }
        }
        return try Contact.Topology(vertexCount:vertexCount,triangleIndices:triangleIndices,
            sewnBoundaryContacts:contacts,referencePositions:referencePositions,isCancelled:isCancelled)
    }

    /// A separate assembly solve keeps every paper panel's reference metric
    /// and mass. Sewing closes attachments over a bounded ramp; it never
    /// merges particles, shortens the source edge or removes gather nodes.
    static func simulate(input prepared:PreparedInput,assemblyFrames:Int=240,
        schedule:AssemblySchedule = .immediate,
        coupling:CouplingOptions = .init(),
        physicalSewingCompliance:Double=1e-8,
        maximumSewingProjectionTravelPerFrameMeters:Double=0.2,
        maximumSewingSingleProjectionMeters:Double=0.02,
        isCancelled:@Sendable()->Bool={false},
        progress:@Sendable(Double)->Void={_ in}) throws -> Kernel.Output {
        if isCancelled() { throw CancellationError() }
        let input=prepared.cloth,plan=prepared.plan
        guard let body=input.standardBody,let bodyMesh=input.bodySurfaceMesh,
              input.settings.useSurfaceCollision,input.settings.useBodySurfaceCollision,
              (1...1200).contains(assemblyFrames),
              (0...1200).contains(schedule.staticFrames),(0...1200).contains(schedule.gravityRampFrames),
              schedule.staticFrames+schedule.gravityRampFrames<input.settings.maximumSteps,
              coupling.timeStepSeconds.isFinite,(0.0005...1.0/60).contains(coupling.timeStepSeconds),
              coupling.selfContactPaddingMeters.isFinite,(0.0001...0.02).contains(coupling.selfContactPaddingMeters),
              physicalSewingCompliance.isFinite,(0...0.001).contains(physicalSewingCompliance),
              maximumSewingProjectionTravelPerFrameMeters.isFinite,
              (0.000001...0.5).contains(maximumSewingProjectionTravelPerFrameMeters),
              maximumSewingSingleProjectionMeters.isFinite,
              (0.000001...0.1).contains(maximumSewingSingleProjectionMeters),
              input.positions.count==input.pinned.count,
              (3...20_000).contains(input.positions.count),
              input.inverseMasses.count==input.positions.count,
              input.positions.allSatisfy({$0.isFinite && $0.length<5}),
              input.inverseMasses.enumerated().allSatisfy({ index,weight in
                  weight.isFinite && (input.pinned[index] ? weight==0 : weight>0)
              }),
              input.meanParticleMassKg.isFinite,input.meanParticleMassKg>0,
              input.referencePositions.count==input.positions.count,
              input.referenceToSimulation==Array(input.positions.indices),
              (60...2400).contains(input.settings.maximumSteps),
              (4...32).contains(input.settings.solverIterations),
              (input.springs+input.bendingSprings).allSatisfy({ spring in
                  input.positions.indices.contains(spring.a) && input.positions.indices.contains(spring.b)
                    && spring.a != spring.b && spring.length.isFinite && spring.length>0
              }),
              !plan.constraints.isEmpty else {
            throw Kernel.DrapeError.invalid("多裁片缝合需要独立裁片顶点、完整质量和标准人体表面接触设置。")
        }
        let topology=try contactTopology(vertexCount:input.positions.count,
            triangleIndices:input.triangleIndices,plan:plan,
            referencePositions:coupling.sourceAwareContactRibbons ? input.referencePositions : nil,
            isCancelled:isCancelled)
        let started=Date(),dt=coupling.timeStepSeconds,thickness=0.0025
        let continuousBody=coupling.useContinuousBodyContact
            ? try GarmentCodeContinuousBodyContact.Prepared(bodyPositions:bodyMesh.positions,
                bodyTriangleIndices:bodyMesh.triangleIndices,isCancelled:isCancelled) : nil
        var positions=input.positions,previous=positions
        var velocities=Array(repeating:Kernel.Vector3.zero,count:positions.count)
        let weights=input.inverseMasses
        let virtualBodyContact=coupling.projectVirtualSewingPoints
            ? try GarmentCodeSewnBodyContact.Prepared(vertexCount:positions.count,
                constraints:plan.constraints,normalizedInverseMass:weights,isCancelled:isCancelled) : nil
        let sourceTethers=coupling.useSourcePathBounds
            ? try GarmentCodeSourceTethers.prepare(input:prepared,isCancelled:isCancelled) : nil
        let pointBlock=coupling.simultaneousFinalSewing
            ? try GarmentCodeSewnPointBlock.Prepared(vertexCount:positions.count,constraints:plan.constraints,
                normalizedInverseMass:weights,physicalCompliance:physicalSewingCompliance,
                meanParticleMassKg:input.meanParticleMassKg,timeStepSeconds:dt,isCancelled:isCancelled) : nil
        var pointBlockState=pointBlock?.makeFrameState()
        var pointBlockFrameTravel=Array(repeating:0.0,count:positions.count)
        var lastPointBlockLinearSolveConverged=true
        let sourceLimiter:Kernel.SourceStrainLimiter?
        if let limit=input.settings.sourceStrainLimit {
            guard (1...120).contains(input.settings.sourceStrainLimitPasses) else {
                throw Kernel.DrapeError.invalid("应变限制的迭代预算无效。")
            }
            sourceLimiter=try Kernel.SourceStrainLimiter(vertexCount:positions.count,springs:input.springs,
                normalizedInverseMass:weights,maximumAbsoluteStrain:limit)
        } else { sourceLimiter=nil }
        let material=input.settings.material?.parameters
        let stretchCompliance=(material?.stretchCompliance ?? 1e-10)*(material == nil ? 1 : input.meanParticleMassKg)
        let shearCompliance=(material?.shearCompliance ?? 1e-10)*(material == nil ? 1 : input.meanParticleMassKg)
        let bendCompliance=(material?.bendDistanceCompliance ?? 0.001)*(material == nil ? 1 : input.meanParticleMassKg)
        let retention=try material?.velocityRetention(timeStep:dt) ?? 0.5
        var stretchLambda=Array(repeating:0.0,count:input.springs.count)
        var bendLambda=Array(repeating:0.0,count:input.bendingSprings.count)
        var sewingState=try Sewing.State(constraintCount:plan.constraints.count,vertexCount:positions.count)
        func project(_ springs:[Kernel.Spring],lambda:inout[Double],compliance:Double,shear:Double?=nil) {
            for (index,spring) in springs.enumerated() {
                let alpha=(spring.isShear ? (shear ?? compliance) : compliance)/(dt*dt)
                let delta=positions[spring.a]-positions[spring.b],length=delta.length
                let weight=weights[spring.a]+weights[spring.b]
                guard length>1e-10,weight>0 else { continue }
                let change=(-(length-spring.length)-alpha*lambda[index])/(weight+alpha)
                lambda[index] += change
                let correction=delta*(change/length)
                positions[spring.a]=positions[spring.a]+correction*weights[spring.a]
                positions[spring.b]=positions[spring.b]-correction*weights[spring.b]
            }
        }
        func bodyProject() throws {
            for i in positions.indices where !input.pinned[i] {
                positions[i]=body.project(positions[i],thickness:thickness)
            }
            if let virtualBodyContact {
                _ = try virtualBodyContact.project(positions:&positions,
                    projectPoint:{body.project($0,thickness:thickness)},isCancelled:isCancelled)
            }
        }
        func sewProject(_ ramp:Double) throws {
            // At zero target distance the actual attachment constraints are
            // linear Cartesian point coincidences. Solve shared attachments
            // together without welding their original particles or masses.
            // The preceding distance ramp retains its established behavior.
            if let pointBlock,ramp==1,var state=pointBlockState {
                let quality=try GarmentCodeSewnPointBlock.project(positions:&positions,prepared:pointBlock,
                    state:&state,frameTravelMeters:&pointBlockFrameTravel,rampFraction:ramp,
                    maximumFrameTravelMeters:maximumSewingProjectionTravelPerFrameMeters,
                    maximumSingleProjectionMeters:maximumSewingSingleProjectionMeters,isCancelled:isCancelled)
                pointBlockState=state
                lastPointBlockLinearSolveConverged=quality.allLinearSystemsConverged
            } else {
                _ = try Sewing.project(positions:&positions,constraints:plan.constraints,
                    normalizedInverseMass:weights,state:&sewingState,timeStep:dt,
                    physicalCompliance:physicalSewingCompliance,meanParticleMassKg:input.meanParticleMassKg,
                    rampFraction:ramp,
                    maximumVertexCorrectionPerFrameMeters:maximumSewingProjectionTravelPerFrameMeters,
                    maximumSingleVertexCorrectionMeters:maximumSewingSingleProjectionMeters,
                    isCancelled:isCancelled)
            }
        }
        func sourcePathProject(_ ramp:Double) throws {
            if let sourceTethers {
                _ = try GarmentCodeSourceTethers.project(positions:&positions,plan:sourceTethers,
                    seamRampFraction:ramp,mode:.followSewingRamp,isCancelled:isCancelled)
            }
        }
        func lengthsReady()->Bool {
            input.springs.allSatisfy {abs((positions[$0.a]-positions[$0.b]).length/$0.length-1)<0.08}
        }
        var lastSpeed=Double.infinity,quietFrames=0,completedSteps=0
        var continuousBodyFrames=0,limitedBodyFrames=0,minimumSafeBodyTime=1.0,continuousBodySeconds=0.0
        var lastBodyMotionWasWhole=true
        progress(0)
        for step in 0..<input.settings.maximumSteps {
            if step%8==0 {
                if isCancelled() { throw CancellationError() }
                progress(Double(step)/Double(input.settings.maximumSteps))
            }
            let ramp=min(1,Double(step+1)/Double(assemblyFrames))
            let staticAssembly=step<schedule.staticFrames
            let gravityFraction=schedule.gravityFraction(step:step)
            previous=positions
            for i in positions.indices where !input.pinned[i] {
                if staticAssembly { velocities[i] = .zero }
                velocities[i].y -= 9.81*dt*gravityFraction
                positions[i]=positions[i]+velocities[i]*dt
            }
            stretchLambda=Array(repeating:0,count:stretchLambda.count)
            bendLambda=Array(repeating:0,count:bendLambda.count)
            sewingState.resetForFrame()
            if let pointBlock {
                pointBlockState=pointBlock.makeFrameState()
                pointBlockFrameTravel=Array(repeating:0,count:pointBlockFrameTravel.count)
            }
            for iteration in 0..<input.settings.solverIterations {
                project(input.springs,lambda:&stretchLambda,compliance:stretchCompliance,shear:shearCompliance)
                project(input.bendingSprings,lambda:&bendLambda,compliance:bendCompliance)
                try sewProject(ramp)
                try sourcePathProject(ramp)
                try bodyProject()
                if iteration==input.settings.solverIterations-1 {
                    _ = try Contact.project(positions:&positions,previousPositions:previous,
                        inverseMass:weights,topology:topology,thickness:coupling.selfContactPaddingMeters,isCancelled:isCancelled)
                    try bodyProject()
                }
                if (iteration+1)%8==0 || iteration==input.settings.solverIterations-1 {
                    _ = try GarmentCodeBodySurfaceContact.project(positions:&positions,inverseMass:weights,
                        topology:topology,body:bodyMesh,thickness:input.settings.bodySurfaceClearanceMeters,
                        previousPositions:previous,isCancelled:isCancelled)
                    try bodyProject()
                }
            }
            if let sourceLimiter {
                for pass in 0..<input.settings.sourceStrainLimitPasses {
                    _ = try sourceLimiter.project(positions:&positions,reverseOrder:pass%2 != 0,isCancelled:isCancelled)
                    try sewProject(ramp)
                    try sourcePathProject(ramp)
                    try bodyProject()
                    if (pass+1)%8==0 || pass==input.settings.sourceStrainLimitPasses-1 {
                        _ = try Contact.project(positions:&positions,previousPositions:previous,
                            inverseMass:weights,topology:topology,thickness:coupling.selfContactPaddingMeters,isCancelled:isCancelled)
                        try bodyProject()
                        _ = try GarmentCodeBodySurfaceContact.project(positions:&positions,inverseMass:weights,
                            topology:topology,body:bodyMesh,thickness:input.settings.bodySurfaceClearanceMeters,
                            previousPositions:previous,isCancelled:isCancelled)
                        try bodyProject()
                    }
                }
            }
            if let continuousBody {
                let motion=try continuousBody.guardMotion(previous:previous,candidate:positions,
                    clothTriangleIndices:input.triangleIndices,isCancelled:isCancelled)
                positions=motion.positions
                continuousBodyFrames += 1
                if !motion.permitsWholeCandidate {limitedBodyFrames += 1}
                lastBodyMotionWasWhole=motion.permitsWholeCandidate
                minimumSafeBodyTime=min(minimumSafeBodyTime,motion.metrics.safeTimeFraction)
                continuousBodySeconds += motion.metrics.computationSeconds
            }
            lastSpeed=0
            for i in positions.indices {
                if input.pinned[i] { positions[i]=input.positions[i];velocities[i] = .zero }
                else {
                    let velocity=(positions[i]-previous[i])/dt
                    guard velocity.isFinite,positions[i].isFinite,positions[i].length<5 else { throw Kernel.DrapeError.unstable }
                    // Initial constraint corrections are not physical launch
                    // velocities during an explicitly requested static stage.
                    velocities[i]=staticAssembly ? .zero : velocity*retention
                    lastSpeed=max(lastSpeed,velocity.length)
                }
            }
            completedSteps=step+1
            quietFrames=lastSpeed<0.025 && ramp==1 && gravityFraction==1 && lastBodyMotionWasWhole ? quietFrames+1 : 0
            if step>=max(240,assemblyFrames),quietFrames>=24,lengthsReady(),lastPointBlockLinearSolveConverged,
               positions.allSatisfy({body.penetration($0)<0.003}) {
                let sewing=try Sewing.inspect(positions:positions,constraints:plan.constraints,isCancelled:isCancelled)
                guard sewing.maximumGapMeters<0.0005 else { continue }
                let selfQuality=try Contact.inspect(positions:positions,topology:topology,thickness:0.005,isCancelled:isCancelled)
                guard selfQuality.intersectingTrianglePairs==0,selfQuality.degenerateTriangles==0 else { continue }
                let bodyQuality=try GarmentCodeBodySurfaceContact.inspect(positions:positions,topology:topology,
                    body:bodyMesh,thickness:input.settings.bodySurfaceClearanceMeters,isCancelled:isCancelled)
                if bodyQuality.intersectingTrianglePairs==0 && bodyQuality.degenerateClothTriangles==0 { break }
            }
        }
        if isCancelled() { throw CancellationError() }
        let strains=input.springs.map {abs((positions[$0.a]-positions[$0.b]).length/$0.length-1)}
        let maximumStrain=strains.max() ?? 0
        guard maximumStrain.isFinite,maximumStrain<0.40 else { throw Kernel.DrapeError.unstable }
        let penetration=positions.map {body.penetration($0)}.max() ?? 0
        let sewing=try Sewing.inspect(positions:positions,constraints:plan.constraints,isCancelled:isCancelled)
        let selfQuality=try Contact.inspect(positions:positions,topology:topology,thickness:0.005,isCancelled:isCancelled)
        let bodyQuality=try GarmentCodeBodySurfaceContact.inspect(positions:positions,topology:topology,body:bodyMesh,
            thickness:input.settings.bodySurfaceClearanceMeters,isCancelled:isCancelled)
        let fullGravityReached=completedSteps>=schedule.staticFrames+schedule.gravityRampFrames
        let converged=quietFrames>=24 && completedSteps>=assemblyFrames && fullGravityReached && maximumStrain<0.08 && penetration<0.003
            && lastPointBlockLinearSolveConverged
            && sewing.maximumGapMeters<0.0005 && selfQuality.intersectingTrianglePairs==0
            && selfQuality.degenerateTriangles==0 && bodyQuality.intersectingTrianglePairs==0
            && bodyQuality.degenerateClothTriangles==0
        var warnings=input.preparationWarnings+[
            "缝合保留各裁片独立顶点、原始边长和质量；接缝间隙测量实际附着点，没有通过合并顶点设为零。",
            "面料是实验数值预设，人体按围度有限拟合；末态离散接触检查不能证明连续运动无穿插或实物合体。"]
        if schedule.staticFrames>0 || schedule.gravityRampFrames>0 {
            warnings.append("先进行 \(schedule.staticFrames) 帧零重力静态装配，再用 \(schedule.gravityRampFrames) 帧加载重力；静态修正不注入速度。最终仍以完整重力和原质量门槛验收。")
        }
        if coupling.projectVirtualSewingPoints {
            warnings.append("缝合点与裁片顶点使用同一人体数值壳，虚拟附着点按原始质量权重修正，不合并裁片自由度。")
        }
        if coupling.sourceAwareContactRibbons {
            warnings.append("接缝附近的数值接触带按真实源裁片限制，并逐点核对对应位置；实际面内穿插检查继续执行。")
        }
        if coupling.simultaneousFinalSewing {
            warnings.append("完成收缝后，关联缝合点按原质量同时求解，保留独立裁片顶点与实际接缝测量；源边应变和全部接触门槛继续独立验收。")
            if !lastPointBlockLinearSolveConverged {
                warnings.append("最后一次接缝块线性求解未达到残差门槛，本次结果不判为收敛。")
            }
        }
        if coupling.useContinuousBodyContact {
            warnings.append("每步运动增加同一可见人体的连续三角接触检查；未确认的路径停止生成。它不代表布片之间也具备连续碰撞保证。")
            if !lastBodyMotionWasWhole {warnings.append("最后一步被连续人体接触限制，不能仅以低速度判断收敛。")}
        }
        if let sourceTethers {
            warnings.append("采用原结构边和真实缝点推导的路径上界加速，随真实收缝比例收紧；没有增加固定点。")
            if !sourceTethers.unreachableVertexIDs.isEmpty {
                warnings.append("\(sourceTethers.unreachableVertexIDs.count) 个源顶点没有通向既有支撑的源路径，未为它们添加人工固定点。")
            }
        }
        if plan.usesFiniteCoarseTacks {
            warnings.append("抽褶或吃势采用有限缝合点，点间保留原长和折叠节点；所示间隙只测缝合点，不能证明整条连续缝口闭合。")
        }
        if let sourceLimiter {
            warnings.append("使用 \(Int(sourceLimiter.maximumAbsoluteStrain*100))% 的实验性应变限制目标；实际源边应变仍独立检测，目标不是实测面料参数。")
        }
        if !converged { warnings.insert("本次未达到收敛门槛，结果仅供检查装配；请勿作为最终垂坠效果。",at:0) }
        var diagnostics=Kernel.Diagnostics(vertexCount:positions.count,triangleCount:input.triangleIndices.count/3,
            simulatedSeconds:Double(completedSteps)*dt,computationSeconds:Date().timeIntervalSince(started),
            maxEdgeStrain:maximumStrain,meanEdgeStrain:strains.reduce(0,+)/Double(max(1,strains.count)),
            maxSpeedMetersPerSecond:lastSpeed,maxBodyPenetrationMeters:penetration,maxSeamGapMeters:sewing.maximumGapMeters,
            waistCircumferenceMeters:input.waistCircumferenceMeters,hemCircumferenceMeters:input.hemCircumferenceMeters,
            radialLengthMeters:input.radialLengthMeters,referenceAreaSquareMeters:input.referenceAreaSquareMeters,
            converged:converged,warnings:warnings)
        diagnostics.bodyModel=body.profileName
        diagnostics.materialName=input.settings.material?.title ?? "原验证材料"
        diagnostics.totalFabricMassKg=input.totalFabricMassKg
        diagnostics.surfaceIntersectionCount=selfQuality.intersectingTrianglePairs
        diagnostics.closeSurfacePairCount=selfQuality.closeSurfacePairs
        diagnostics.garmentStyle=input.garmentStyle
        diagnostics.patternLengthLabel=input.patternLengthLabel
        diagnostics.patternLengthMeters=input.radialLengthMeters
        diagnostics.waistGatherRatio=input.waistGatherRatio
        diagnostics.supportWaistCircumferenceMeters=body.waistCircumferenceMeters
        diagnostics.bodySurfaceIntersectionCount=bodyQuality.intersectingTrianglePairs
        diagnostics.bodySurfaceCandidatePairCount=bodyQuality.candidateTrianglePairs
        diagnostics.maxBodySurfacePlaneOverlapMeters=bodyQuality.maximumPlaneOverlapMeters
        diagnostics.bodySurfaceClearanceMeters=input.settings.bodySurfaceClearanceMeters
        diagnostics.waistSupportClearanceMeters=0.005
        diagnostics.sewingConstraintCount=plan.constraints.count
        diagnostics.sewingRMSGapMeters=sewing.rmsGapMeters
        diagnostics.sewingUsesFiniteTacks=plan.usesFiniteCoarseTacks
        // This bounds the accumulated internal projection path, not the net
        // physical displacement between two displayed/simulated frames.
        diagnostics.sewingProjectionTravelBudgetMeters=maximumSewingProjectionTravelPerFrameMeters
        diagnostics.sewingSingleProjectionLimitMeters=maximumSewingSingleProjectionMeters
        if coupling.timeStepSeconds != 1.0/120 {diagnostics.sewnTimeStepSeconds=dt}
        if coupling.selfContactPaddingMeters != 0.005 {diagnostics.sewnContactPaddingMeters=coupling.selfContactPaddingMeters}
        if coupling.projectVirtualSewingPoints {diagnostics.usesVirtualSewingPointBodyContact=true}
        if coupling.useSourcePathBounds {diagnostics.usesSourcePathBounds=true}
        if coupling.sourceAwareContactRibbons {diagnostics.usesSourceAwareSewnContactRibbons=true}
        if coupling.simultaneousFinalSewing {
            diagnostics.usesSimultaneousFinalSewing=true
            diagnostics.sewingBlockLinearSystemsConverged=lastPointBlockLinearSolveConverged
        }
        if coupling.useContinuousBodyContact {
            diagnostics.usesContinuousBodyContact=true
            diagnostics.continuousBodyFrameCount=continuousBodyFrames
            diagnostics.continuousBodyLimitedFrameCount=limitedBodyFrames
            diagnostics.minimumContinuousBodyTimeFraction=minimumSafeBodyTime
            diagnostics.continuousBodyComputationSeconds=continuousBodySeconds
        }
        if schedule.staticFrames>0 {diagnostics.staticAssemblyFrameCount=schedule.staticFrames}
        if schedule.gravityRampFrames>0 {diagnostics.gravityRampFrameCount=schedule.gravityRampFrames}
        if let sourceLimiter {
            diagnostics.sourceStrainLimitFraction=sourceLimiter.maximumAbsoluteStrain
            diagnostics.sourceStrainLimitPassCount=input.settings.sourceStrainLimitPasses
        }
        progress(1)
        var output=Kernel.Output(positions:positions,triangleIndices:input.triangleIndices,mannequinPositions:input.mannequinPositions,
            mannequinTriangleIndices:input.mannequinTriangleIndices,seamPaths:input.seamPaths,
            seamVertexPairs:input.seamVertexPairs,diagnostics:diagnostics)
        output.panelGroups=prepared.panelBindings.map {
            .init(panelID:$0.mesh.panelID,vertexIDs:$0.vertexIDs,triangleIDs:$0.triangleIDs)
        }
        return output
    }
}
