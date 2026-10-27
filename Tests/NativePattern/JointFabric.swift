import Foundation
import NativeClothCollision

@main @MainActor struct JointFabricRegression {
    typealias F=GarmentCodeJointFabric
    typealias M=GarmentCodeMembrane
    typealias H=GarmentCodeHingeBending
    typealias V=M.V
    struct Source:Decodable {let referencePositions:[V],referenceTriangles:[UInt32],panelGroups:[H.PanelGroup],sourceSHA256:String}
    enum Failure:Error {case check(String)}
    static func require(_ x:Bool,_ label:String)throws{if !x{throw Failure.check(label)}}
    static func bits(_ x:Double,_ y:Double,_ label:String)throws{try require(x.bitPattern==y.bitPattern,label)}
    static func dot(_ a:[V],_ b:[V])->Double{zip(a,b).reduce(0){$0+$1.0.x*$1.1.x+$1.0.y*$1.1.y+$1.0.z*$1.1.z}}
    static func scalarClose(_ x:Double,_ y:Double,_ label:String)throws{try require(abs(x-y)<1e-11*max(1,abs(y)),label+" \(x) vs \(y)")}
    static func materialValues(_ m:F.S.Materials)->[Double]{
        [m.membrane.shearStiffnessNewtonPerMeter,m.membrane.areaStiffnessNewtonPerMeter,
         m.strainBarrier.lowerLimit,m.strainBarrier.lowerActivation,m.strainBarrier.upperActivation,m.strainBarrier.upperLimit,m.strainBarrier.stiffnessNewtonPerMeter,
         m.bending.bendingStiffnessNewtonMeter,m.sewingComplianceMetersPerNewton,
         m.bodyContact.stiffnessPascals,m.bodyContact.minimumDistanceMeters,m.bodyContact.activationGapMeters,
         m.selfContact.stiffnessPascals,m.selfContact.minimumDistanceMeters,m.selfContact.activationGapMeters]
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        let baseline=try baselineJointMaterials(),medium=try F.materials(.medium)
        try require(materialValues(baseline).count==materialValues(medium).count,"baseline field coverage")
        for (i,pair) in zip(materialValues(baseline),materialValues(medium)).enumerated(){try bits(pair.0,pair.1,"medium baseline field \(i)")}
        try require(baseline.bodyContact.hessianMode.rawValue==medium.bodyContact.hessianMode.rawValue && baseline.selfContact.hessianMode.rawValue==medium.selfContact.hessianMode.rawValue,"raw physical contact Hessian mode")
        let reference=[V(x:0,y:0,z:0),V(x:1,y:0,z:0),V(x:1,y:0.5,z:0),V(x:0,y:0.5,z:0)],triangles:[UInt32]=[0,1,2,0,2,3]
        let area=0.5,membrane=try M.Prepared(referencePositions:reference,triangleIndices:triangles)
        let hinge=try H.Prepared(referencePositions:reference,referenceTriangles:triangles,panelGroups:[.init(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0,1])])
        try require(hinge.hinges.count==1,"one actual shared-edge hinge")
        let gamma=0.02,shear=reference.map{V(x:$0.x+gamma*$0.y,y:$0.y,z:0)},shearDirection=reference.map{V(x:$0.y,y:0,z:0)}
        let stretch=reference.map{V(x:1.02*$0.x,y:$0.y,z:0)},barrierProbe=reference.map{V(x:1.05*$0.x,y:$0.y,z:0)}
        let theta=0.35,edge=reference[2]-reference[0],axis=edge/edge.length,q=reference[3]-reference[0]
        let d=axis.x*q.x+axis.y*q.y+axis.z*q.z
        var folded=reference;folded[3]=reference[0]+q*cos(theta)+axis.cross(q)*sin(theta)+axis*(d*(1-cos(theta)))
        let source=try JSONDecoder().decode(Source.self,from:Data(contentsOf:root.appendingPathComponent("native-source-topology.json")))
        let sourceArea=source.referenceTriangles.indices.filter{$0%3==0}.reduce(0.0){sum,k in
            let a=source.referencePositions[Int(source.referenceTriangles[k])],b=source.referencePositions[Int(source.referenceTriangles[k+1])],c=source.referencePositions[Int(source.referenceTriangles[k+2])]
            return sum+((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/2
        }
        try require(source.referencePositions.count==2000 && source.referenceTriangles.count==3472*3 && abs(sourceArea-0.7687490142067)<1e-13,"full unchanged real source fixture")
        let realM=try M.Prepared(referencePositions:source.referencePositions,triangleIndices:source.referenceTriangles)
        let realH=try H.Prepared(referencePositions:source.referencePositions,referenceTriangles:source.referenceTriangles,panelGroups:source.panelGroups)
        let realShear=source.referencePositions.map{V(x:$0.x+gamma*$0.y,y:$0.y,z:0)}
        let realCurve=source.referencePositions.map{V(x:$0.x,y:$0.y,z:0.012*sin(5*$0.x)*cos(4*$0.y)+0.009*$0.x*$0.y)}
        let groups=[H.PanelGroup(panelID:"paper",vertexIDs:[0,1,2,3],triangleIDs:[0,1])]
        let scaledReference=reference.map{$0*10},scaledShear=shear.map{$0*10},scaledFold=folded.map{$0*10}
        let scaledM=try M.Prepared(referencePositions:scaledReference,triangleIndices:triangles)
        let scaledH=try H.Prepared(referencePositions:scaledReference,referenceTriangles:triangles,panelGroups:groups)
        let bodyDirectory=output.appendingPathComponent("unchanged-body-resources")
        let sourceBaseline=baselineJointSourceSettings(bodyResourceDirectory:bodyDirectory)
        var rows:[[String:Any]]=[],barriers:[M.EnergyEvaluation]=[],shearE:[Double]=[],foldE:[Double]=[]
        for preset in F.Preset.allCases {
            let p=F.parameters(preset),m=try F.materials(preset),settings=F.sourceSettings(preset,bodyResourceDirectory:bodyDirectory)
            try require([p.arealDensityKgPerSquareMeter,p.shearStiffnessNewtonPerMeter,p.areaStiffnessNewtonPerMeter,p.bendingStiffnessNewtonMeter,p.sewingComplianceMetersPerNewton].allSatisfy{$0.isFinite && $0>0},"finite positive SI coefficients")
            try bits(p.arealDensityKgPerSquareMeter,preset.parameters.arealDensityKgPerSquareMeter,"density preset binding")
            try require(settings.material==preset && settings.bodyMode == .standardMannequin && settings.useSurfaceCollision && settings.useBodySurfaceCollision && settings.bodyResourceDirectory==bodyDirectory,"source body/contact/preset settings")
            try bits(settings.targetEdgeMeters,sourceBaseline.targetEdgeMeters,"default source grid edge matches actual current simulation baseline")
            try require(settings.bodyMode==sourceBaseline.bodyMode && settings.useSurfaceCollision==sourceBaseline.useSurfaceCollision && settings.useBodySurfaceCollision==sourceBaseline.useBodySurfaceCollision,"source baseline choices")
            let custom=F.sourceSettings(preset,bodyResourceDirectory:bodyDirectory,targetEdgeMeters:0.025)
            try bits(custom.targetEdgeMeters,0.025,"explicit source grid edge forwarding")
            try require(settings.sourceStrainLimit==nil && m.bodyContact.hessianMode == .exact && m.selfContact.hessianMode == .exact,"no hidden legacy strain clamp/PSD physical Hessian")
            let se=try membrane.neoHookean(positions:shear,material:m.membrane),sv=try membrane.neoHookeanHessianProduct(positions:shear,direction:shearDirection,material:m.membrane)
            let expectedShear=area*p.shearStiffnessNewtonPerMeter*gamma*gamma/2
            try scalarClose(se.energyJoules,expectedShear,"analytic SI shear energy")
            try scalarClose(dot(se.gradientNewton,shearDirection),area*p.shearStiffnessNewtonPerMeter*gamma,"analytic shear energy derivative")
            try scalarClose(dot(shearDirection,sv),area*p.shearStiffnessNewtonPerMeter,"analytic shear directional Hessian")
            let eps=1e-6,plus=zip(shear,shearDirection).map{$0+$1*eps},minus=zip(shear,shearDirection).map{$0-$1*eps}
            let fd=(try membrane.neoHookean(positions:plus,material:m.membrane).energyJoules-membrane.neoHookean(positions:minus,material:m.membrane).energyJoules)/(2*eps)
            try require(abs(fd-dot(se.gradientNewton,shearDirection))<1e-7,"finite-difference material response")
            let stretchE=try membrane.neoHookean(positions:stretch,material:m.membrane).energyJoules,logJ=log(1.02)
            let stretchOracle=area*(p.shearStiffnessNewtonPerMeter*0.5*(1.02*1.02+1-2)-p.shearStiffnessNewtonPerMeter*logJ+0.5*p.areaStiffnessNewtonPerMeter*logJ*logJ)
            try scalarClose(stretchE,stretchOracle,"independent area/shear SI constitutive response")
            let be=try hinge.evaluate(positions:folded,material:m.bending),angle=try hinge.angle(positions:folded,hingeID:0)
            let bendOracle=p.bendingStiffnessNewtonMeter*7.5*theta*theta
            try scalarClose(be.energyJoules,bendOracle,"actual dihedral oracle N m")
            try require(abs(abs(angle.angleRadians)-theta)<1e-14,"geometric fold angle")
            let hdir=[V(x:0.1,y:0.2,z:0.3),V(x:-0.2,y:0.1,z:0.1),V(x:0.1,y:-0.1,z:0.2),V(x:-0.1,y:0.2,z:-0.3)]
            let bg=dot(be.gradientNewton,hdir),bp=zip(folded,hdir).map{$0+$1*eps},bm=zip(folded,hdir).map{$0-$1*eps}
            let bfd=(try hinge.evaluate(positions:bp,material:m.bending).energyJoules-hinge.evaluate(positions:bm,material:m.bending).energyJoules)/(2*eps)
            try require(abs(bg-bfd)<1e-10,"actual bending derivative finite-difference")
            let b=try membrane.principalBarrier(positions:barrierProbe,barrier:m.strainBarrier);barriers.append(b)
            let mass=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:reference.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:triangles,arealDensity:settings.material!.parameters.arealDensityKgPerSquareMeter)
            try scalarClose(mass.totalMassKg,area*p.arealDensityKgPerSquareMeter,"analytic area-mass SI binding")
            let scaledMass=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:scaledReference.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:triangles,arealDensity:p.arealDensityKgPerSquareMeter)
            let scaledElastic=try scaledM.neoHookean(positions:scaledShear,material:m.membrane)
            let scaledBend=try scaledH.evaluate(positions:scaledFold,material:m.bending)
            try scalarClose(scaledMass.totalMassKg,100*mass.totalMassKg,"metre geometry scale yields square-metre mass scale")
            try scalarClose(scaledElastic.energyJoules,100*se.energyJoules,"membrane SI area covariance")
            try scalarClose(scaledBend.energyJoules,be.energyJoules,"hinge SI scale invariance for same fold angle")
            try require(zip(scaledBend.gradientNewton,be.gradientNewton).allSatisfy{($0*10-$1).length<1e-12},"bending force has inverse-length scale")
            let objective=try GarmentCodeJointObjective.Prepared(referencePositions:reference,referenceTriangles:triangles,panelGroups:groups,massesKg:mass.massesKg,stitches:[],material:m.membrane,strainBarrier:m.strainBarrier,bendingMaterial:m.bending,sewingComplianceMetersPerNewton:m.sewingComplianceMetersPerNewton)
            let dt=F.S.Settings().timeStepSeconds,translation=V(x:0,y:0,z:0.001)
            let frame=try objective.frame(predictor:reference,timeStepSeconds:dt,sewingRamp:1)
            let inertial=try frame.evaluate(positions:reference.map{$0+translation})
            try scalarClose(inertial.inertiaJoules,0.5*mass.totalMassKg*translation.lengthSquared/(dt*dt),"actual Joint inertia uses preset SI masses")
            for i in reference.indices {try scalarClose(inertial.gradientNewton[i].z,mass.massesKg[i]*translation.z/(dt*dt),"actual per-vertex inertial force uses original mass")}

            let realMass=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:source.referencePositions.map{SIMD3($0.x,$0.y,$0.z)},triangleIndices:source.referenceTriangles,arealDensity:settings.material!.parameters.arealDensityKgPerSquareMeter)
            try scalarClose(realMass.totalMassKg,sourceArea*p.arealDensityKgPerSquareMeter,"real source mass binding")
            let realElastic=try realM.neoHookean(positions:realShear,material:m.membrane)
            try scalarClose(realElastic.energyJoules,sourceArea*p.shearStiffnessNewtonPerMeter*gamma*gamma/2,"full source affine shear oracle")
            let realBending=try realH.evaluate(positions:realCurve,material:m.bending)
            try require(realBending.energyJoules>0 && realBending.gradientNewton.contains{$0.length>1e-8},"real source constitutive bending response")
            rows.append(["preset":preset.rawValue,"densityKgPerSquareMeter":p.arealDensityKgPerSquareMeter,"shearEnergyJoules":se.energyJoules,"shearDirectionalDerivativeJoules":dot(se.gradientNewton,shearDirection),"shearDirectionalHessianJoules":dot(shearDirection,sv),"stretchEnergyJoules":stretchE,"foldEnergyJoules":be.energyJoules,"foldDirectionalDerivativeJoules":bg,"activeNumericalBarrierJoules":b.energyJoules,"sampleMassKg":mass.totalMassKg,"actualJointInertiaJoules":inertial.inertiaJoules,"metreScaleMassRatio":scaledMass.totalMassKg/mass.totalMassKg,"metreScaleMembraneEnergyRatio":scaledElastic.energyJoules/se.energyJoules,"metreScaleHingeEnergyRatio":scaledBend.energyJoules/be.energyJoules,"realSourceMassKg":realMass.totalMassKg,"realSourceShearEnergyJoules":realElastic.energyJoules,"realSourceBendingEnergyJoules":realBending.energyJoules])
            shearE.append(se.energyJoules);foldE.append(be.energyJoules)
        }
        try require(shearE[0]<shearE[1] && shearE[1]<shearE[2] && foldE[0]<foldE[1] && foldE[1]<foldE[2],"actual preset response ordering")
        try scalarClose(shearE[1]/shearE[0],2,"membrane response ratio soft->medium")
        try scalarClose(shearE[2]/shearE[1],2,"membrane response ratio medium->firm")
        try scalarClose(foldE[1]/foldE[0],4,"bending response ratio soft->medium")
        try scalarClose(foldE[2]/foldE[1],4,"bending response ratio medium->firm")
        for b in barriers.dropFirst() {
            try bits(b.energyJoules,barriers[0].energyJoules,"numerical feasibility barrier must not change with material preset")
            try require(zip(b.gradientNewton,barriers[0].gradientNewton).allSatisfy{$0.x.bitPattern==$1.x.bitPattern && $0.y.bitPattern==$1.y.bitPattern && $0.z.bitPattern==$1.z.bitPattern},"barrier gradient material-independent")
        }
        let summary:[String:Any]=["passed":true,"mediumMatchesCurrentSimulationMaterialsBitwise":true,"mediumComparedSIScalars":materialValues(medium).count,"sourceSettingsMatchActualSimulationBaseline":true,"sourceSHA256":source.sourceSHA256,"realSourceVertices":2000,"realSourceTriangles":3472,"realSourceHinges":realH.hinges.count,"realSourceAreaSquareMeters":sourceArea,"rows":rows,"numericalBarrierBitwiseIndependentOfPreset":true,"sourceScaleAndActualJointInertiaBindingVerified":true,"noPhysicalSimulationRun":true,"calibratedFabric":false,"finalGarmentSensitivityVerified":false,"scope":"SI factory, immutable area-mass binding and isolated actual constitutive response; no calibrated material or final garment/drape claim." ]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("joint-fabric-summary.json"))
        print("PASS: medium bitwise baseline, 3 SI density/mesh/contact presets, analytic+FD membrane/hinge responses and complete original2000V/3472T area-mass binding")
    }
}
