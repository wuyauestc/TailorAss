import Foundation
import CryptoKit

/// Acceptance of the verified source-to-solver boundary, independent of whether
/// a proposed 3D placement can physically settle. No unchecked solver is called.
#if !SEWN_INPUT_INTEGRATION
@main
#endif
@MainActor
struct SewnInputRegression {
    typealias K=GarmentCodeCircleDrape
    typealias S=GarmentCodeSewing
    typealias D=GarmentCodeSewnDrape
    typealias V=K.Vector3
    enum Failure:Error {case check(String)}
    struct Fixture {let document:GarmentCodePatternFile;let input:K.Input;let bindings:[S.PanelBinding];let plan:S.Plan}
    struct Changes {
        var positions:[V]?,triangles:[UInt32]?,flat:[V]?,referenceTriangles:[UInt32]?,mapping:[Int]?,pinned:[Bool]?
        var springs:[K.Spring]?,bends:[K.Spring]?,visibleBody:[V]?,visibleTriangles:[UInt32]?
        var area:Double?,settings:K.Settings?
    }
    nonisolated final class CancelCounter:@unchecked Sendable {
        private let lock=NSLock();private var visits=0
        func cancel()->Bool {lock.lock();defer{lock.unlock()};visits += 1;return visits>=4}
    }
    static var rejected:[String]=[],acceptedInvalid:[String]=[]
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func require(_ condition:@autoclosure()throws->Bool,_ message:String)throws {if try !condition(){throw Failure.check(message)}}
    static func encode<T:Encodable>(_ value:T)throws->Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(value)}
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func log(_ text:String){FileHandle.standardError.write(Data((text+"\n").utf8))}
    static func copy(_ a:K.Input,_ c:Changes = .init())->K.Input {
        var b=K.Input(positions:c.positions ?? a.positions,triangleIndices:c.triangles ?? a.triangleIndices,
            referencePositions:c.flat ?? a.referencePositions,referenceTriangles:c.referenceTriangles ?? a.referenceTriangles,
            referenceToSimulation:c.mapping ?? a.referenceToSimulation,panelColumns:a.panelColumns,radialSegments:a.radialSegments,
            seamPaths:a.seamPaths,seamVertexPairs:a.seamVertexPairs,pinned:c.pinned ?? a.pinned,
            springs:c.springs ?? a.springs,bendingSprings:c.bends ?? a.bendingSprings,body:a.body,
            mannequinPositions:c.visibleBody ?? a.mannequinPositions,mannequinTriangleIndices:c.visibleTriangles ?? a.mannequinTriangleIndices,
            waistCircumferenceMeters:a.waistCircumferenceMeters,hemCircumferenceMeters:a.hemCircumferenceMeters,
            radialLengthMeters:a.radialLengthMeters,referenceAreaSquareMeters:c.area ?? a.referenceAreaSquareMeters,settings:c.settings ?? a.settings)
        b.standardBody=a.standardBody;b.surfaceTopology=a.surfaceTopology;b.bodySurfaceMesh=a.bodySurfaceMesh
        b.inverseMasses=a.inverseMasses;b.meanParticleMassKg=a.meanParticleMassKg;b.totalFabricMassKg=a.totalFabricMassKg
        b.garmentStyle=a.garmentStyle;b.patternLengthLabel=a.patternLengthLabel;b.preparationWarnings=a.preparationWarnings;b.waistGatherRatio=a.waistGatherRatio
        return b
    }
    static func validate(_ f:Fixture,input:K.Input?=nil,document:GarmentCodePatternFile?=nil,bindings:[S.PanelBinding]?=nil,plan:S.Plan?=nil)throws->D.PreparedInput {
        try D.prepare(input:input ?? f.input,plan:plan ?? f.plan,document:document ?? f.document,bindings:bindings ?? f.bindings)
    }
    static func expectInvalid(_ name:String,_ operation:()throws->Void) {
        do {try operation();acceptedInvalid.append(name);log("FAIL accepted invalid: \(name)")}
        catch {rejected.append(name);log("PASS reject \(name): \(error)")}
    }
    static func mutate<T:Codable>(_ value:T,_ block:(inout [String:Any])->Void)throws->T {
        var obj=try JSONSerialization.jsonObject(with:encode(value)) as! [String:Any]
        block(&obj);return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:obj))
    }
    static func sourceStitches(_ document:GarmentCodePatternFile)->[S.SourceStitch] {
        document.pattern.stitches.map{.init(a:.init(panelID:$0.sides[0].panel,edgeIndex:$0.sides[0].edge),b:.init(panelID:$0.sides[1].panel,edgeIndex:$0.sides[1].edge),rightWrong:$0.rightWrong)}
    }
    static func sourceSprings(_ flat:[V],_ triangles:[UInt32])->[K.Spring] {
        var keys=Set<String>(),springs:[K.Spring]=[]
        for i in stride(from:0,to:triangles.count,by:3) {
            let f=(0..<3).map{Int(triangles[i+$0])}
            for (x,y) in [(f[0],f[1]),(f[1],f[2]),(f[2],f[0])] {
                let a=min(x,y),b=max(x,y)
                if keys.insert("\(a):\(b)").inserted {springs.append(.init(a:a,b:b,length:(flat[a]-flat[b]).length))}
            }
        }
        return springs.sorted{$0.a == $1.a ? $0.b<$1.b : $0.a<$1.a}
    }
    static func withMass(_ input:K.Input)throws->K.Input {
        var a=input
        let mass=try GarmentCodeClothMaterial.lumpedMasses(referencePositions:a.referencePositions.map{SIMD3<Double>($0.x,$0.y,$0.z)},triangleIndices:a.referenceTriangles,arealDensity:a.settings.material!.parameters.arealDensityKgPerSquareMeter)
        a.inverseMasses=mass.normalizedInverseMasses.enumerated().map{a.pinned[$0.offset] ? 0 : $0.element}
        a.meanParticleMassKg=mass.meanMassKg;a.totalFabricMassKg=mass.totalMassKg
        return a
    }
    static func waistband(_ style:String,catalog:GarmentCodeParameterCatalog,body:GarmentCodeBodyParameters)throws->Fixture {
        var design=GarmentCodeDesignParameters(catalog:catalog)
        _=design.setValue(.null,at:["meta","upper"]);_=design.setValue(.null,at:["meta","bottom"]);_=design.setValue(.string(style),at:["meta","wb"])
        let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        var settings=K.Settings();settings.bodyMode = .standardMannequin;settings.material = .medium
        settings.useSurfaceCollision=true;settings.useBodySurfaceCollision=true;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
        let assembly=try GarmentCodeWaistbandDrape.prepareAssembly(document:document,body:body,settings:settings),old=assembly.input
        let bindings=try assembly.sourcePanelBindings.map{try S.PanelBinding(mesh:$0.mesh,vertexOffset:$0.referenceVertexOffset,triangleOffset:$0.triangleIndexOffset/3)}
        let flat=old.referencePositions,points=flat.indices.map{old.positions[old.referenceToSimulation[$0]]},pins=flat.indices.map{old.pinned[old.referenceToSimulation[$0]]}
        var triangles:[UInt32]=[]
        for binding in bindings {for i in stride(from:0,to:binding.mesh.triangleIndices.count,by:3) {
            var ids=(0..<3).map{UInt32(binding.vertexIDs[Int(binding.mesh.triangleIndices[i+$0])])}
            if binding.mesh.sourceClockwise {ids.swapAt(1,2)};triangles += ids
        }}
        var input=K.Input(positions:points,triangleIndices:triangles,referencePositions:flat,referenceTriangles:old.referenceTriangles,
            referenceToSimulation:Array(flat.indices),panelColumns:0,radialSegments:0,seamPaths:[],seamVertexPairs:[],pinned:pins,
            springs:sourceSprings(flat,old.referenceTriangles),bendingSprings:[],body:old.body,mannequinPositions:old.mannequinPositions,
            mannequinTriangleIndices:old.mannequinTriangleIndices,waistCircumferenceMeters:old.waistCircumferenceMeters,
            hemCircumferenceMeters:old.hemCircumferenceMeters,radialLengthMeters:old.radialLengthMeters,referenceAreaSquareMeters:old.referenceAreaSquareMeters,settings:old.settings)
        input.standardBody=old.standardBody;input.bodySurfaceMesh=old.bodySurfaceMesh
        input.garmentStyle=style;input.patternLengthLabel=old.patternLengthLabel;input.preparationWarnings=old.preparationWarnings;input.waistGatherRatio=old.waistGatherRatio
        input=try withMass(input)
        let sha=try D.canonicalSourceSHA256(document:document),stitches=sourceStitches(document)
        let hints=stitches.enumerated().map{S.StitchHint(stitchIndex:$0.offset,seamID:"side\($0.offset)",a:$0.element.a,b:$0.element.b,aDirection:.forward,bDirection:.reverse,rightWrong:$0.element.rightWrong,intent:.ordinary)}
        let plan=try S.build(bindings:bindings,positions:points,sourceStitches:stitches,actualSourceSHA256:sha,assembly:.init(sourceSHA256:sha,hints:hints))
        return Fixture(document:document,input:input,bindings:bindings,plan:plan)
    }
    static func positive(_ f:Fixture,_ name:String)throws {
        let before=try encode(f.document),planBefore=try encode(f.plan),verified=try validate(f)
        try require(verified.sourceSHA256==hash(before),"Canonical SHA differs from an independent sorted source encoding")
        try require(verified.cloth.positions==f.input.positions && verified.cloth.referencePositions==f.input.referencePositions && verified.cloth.referenceTriangles==f.input.referenceTriangles && verified.cloth.triangleIndices==f.input.triangleIndices,"Factory changed source or simulation geometry")
        try require(verified.cloth.referenceToSimulation==Array(f.input.positions.indices),"Separate panel particles were merged")
        try require(try encode(verified.plan)==planBefore,"Factory repaired the runtime plan")
        try require(try encode(f.document)==before,"Factory mutated canonical source")
        var analyticArea=0.0
        for i in stride(from:0,to:f.input.referenceTriangles.count,by:3) {let ids=(0..<3).map{Int(f.input.referenceTriangles[i+$0])};let p=ids.map{f.input.referencePositions[$0]};analyticArea += (p[1]-p[0]).cross(p[2]-p[0]).length/2}
        try require(abs(analyticArea-f.input.referenceAreaSquareMeters)<1e-12,"Fixture area is not actual source triangle area")
        try require(abs(f.input.totalFabricMassKg!-analyticArea*f.input.settings.material!.parameters.arealDensityKgPerSquareMeter)<1e-12,"Fixture mass is not measured source area times density")
        log("PASS \(name): independent source SHA, separate DOFs, all source metrics/mass/body/plan retained")
    }
    static func malformedChecks(_ f:Fixture)throws {
        var c=Changes();c.springs=Array(f.input.springs.dropLast());expectInvalid("missing actual source edge"){_=try validate(f,input:copy(f.input,c))}
        var springs=f.input.springs;let s=springs[0];springs[0] = .init(a:s.a,b:s.b,length:s.length*0.9)
        c=Changes();c.springs=springs;expectInvalid("shortened rest length"){_=try validate(f,input:copy(f.input,c))}
        springs=f.input.springs;springs[1]=springs[0];c=Changes();c.springs=springs;expectInvalid("duplicated edge replacing another"){_=try validate(f,input:copy(f.input,c))}
        let x=f.bindings[0].vertexIDs[0],y=f.bindings[1].vertexIDs[0]
        c=Changes();c.bends=[.init(a:x,b:y,length:(f.input.referencePositions[x]-f.input.referencePositions[y]).length)];expectInvalid("cross-panel bending brace"){_=try validate(f,input:copy(f.input,c))}
        var flat=f.input.referencePositions;flat[0].x += 0.0001;c=Changes();c.flat=flat;expectInvalid("altered source vertex"){_=try validate(f,input:copy(f.input,c))}
        var mapping=f.input.referenceToSimulation;mapping[y]=x;c=Changes();c.mapping=mapping;expectInvalid("pre-welded reference map"){_=try validate(f,input:copy(f.input,c))}
        c=Changes();c.area=f.input.referenceAreaSquareMeters*1.01;expectInvalid("false total source area"){_=try validate(f,input:copy(f.input,c))}
        c=Changes();c.area=Double.nan;expectInvalid("nonfinite source area"){_=try validate(f,input:copy(f.input,c))}
        var bad=copy(f.input);bad.totalFabricMassKg=nil;expectInvalid("missing physical mass"){_=try validate(f,input:bad)}
        bad=copy(f.input);bad.totalFabricMassKg! *= 1.01;expectInvalid("false physical mass"){_=try validate(f,input:bad)}
        bad=copy(f.input);bad.meanParticleMassKg *= 1.01;expectInvalid("false mass normalization scale"){_=try validate(f,input:bad)}
        bad=copy(f.input);bad.inverseMasses[0] += 0.01;expectInvalid("incorrect normalized inverse mass"){_=try validate(f,input:bad)}
        var pins=f.input.pinned;let free=pins.firstIndex(of:false)!;pins[free]=true;c=Changes();c.pinned=pins;expectInvalid("pin mask without corresponding zero inverse mass"){_=try validate(f,input:copy(f.input,c))}
        var points=f.input.positions;points[0].x=Double.nan;c=Changes();c.positions=points;expectInvalid("nonfinite placement"){_=try validate(f,input:copy(f.input,c))}
        var visible=f.input.mannequinPositions;visible[0].x += 0.001;c=Changes();c.visibleBody=visible;expectInvalid("rendered body differs from collider and SDF"){_=try validate(f,input:copy(f.input,c))}
        bad=copy(f.input);bad.bodySurfaceMesh=nil;expectInvalid("missing actual mesh collider"){_=try validate(f,input:bad)}
        bad=copy(f.input)
        bad.bodySurfaceMesh=try GarmentCodeBodySurfaceContact.BodyMesh(positions:f.input.mannequinPositions.map{$0+V(x:0.001,y:0,z:0)},triangleIndices:f.input.mannequinTriangleIndices)
        expectInvalid("actual body collider differs from rendered body"){_=try validate(f,input:bad)}
        bad=copy(f.input);bad.standardBody=nil;expectInvalid("missing source SDF body"){_=try validate(f,input:bad)}
        expectInvalid("omitted source panel binding"){_=try validate(f,bindings:Array(f.bindings.dropLast()))}
        expectInvalid("duplicate source panel binding"){_=try validate(f,bindings:[f.bindings[0],f.bindings[0]])}
        var settings=f.input.settings;settings.material=nil;c=Changes();c.settings=settings;expectInvalid("missing explicit physical preset"){_=try validate(f,input:copy(f.input,c))}
        settings=f.input.settings;settings.sourceStrainLimit=Double.nan;c=Changes();c.settings=settings;expectInvalid("nonfinite optional source limiter"){_=try validate(f,input:copy(f.input,c))}
        settings=f.input.settings;settings.sourceStrainLimit=0.05;settings.sourceStrainLimitPasses=0;c=Changes();c.settings=settings;expectInvalid("zero optional limiter budget"){_=try validate(f,input:copy(f.input,c))}
        let stale=try mutate(f.document){o in var pattern=o["pattern"] as! [String:Any];var panels=pattern["panels"] as! [String:Any];let key=panels.keys.sorted()[0];var panel=panels[key] as! [String:Any];var vertices=panel["vertices"] as! [[Double]];vertices[0][0] += 0.01;panel["vertices"]=vertices;panels[key]=panel;pattern["panels"]=panels;o["pattern"]=pattern}
        expectInvalid("stale canonical source dimensions"){_=try validate(f,document:stale)}
        let badHash=try mutate(f.plan){$0["sourceSHA256"]=String(repeating:"a",count:64)}
        expectInvalid("stale plan source hash"){_=try validate(f,plan:badHash)}
        let badPath=try mutate(f.plan){o in var paths=o["allBoundaryPaths"] as! [[String:Any]];paths[0]["sourceLengthMeters"]=(paths[0]["sourceLengthMeters"] as! Double)+0.001;o["allBoundaryPaths"]=paths}
        expectInvalid("stale claimed boundary metric"){_=try validate(f,plan:badPath)}
        let badGap=try mutate(f.plan){o in var constraints=o["constraints"] as! [[String:Any]];constraints[0]["initialGapMeters"]=(constraints[0]["initialGapMeters"] as! Double)+0.001;o["constraints"]=constraints}
        expectInvalid("stale initial sewing anchor gap"){_=try validate(f,plan:badGap)}
        let missingContacts=try mutate(f.plan){$0["contactNeighborhoods"]=[]}
        expectInvalid("omitted seam-local contact provenance"){_=try validate(f,plan:missingContacts)}
        let missingIntervals=try mutate(f.plan){$0["ordinaryBoundaryIntervals"]=[]}
        expectInvalid("omitted ordinary seam boundary interval"){_=try validate(f,plan:missingIntervals)}
        let wrongFacing=try mutate(f.plan){o in var neighborhoods=o["contactNeighborhoods"] as! [[String:Any]];neighborhoods[0]["rightWrong"] = !(neighborhoods[0]["rightWrong"] as! Bool);o["contactNeighborhoods"]=neighborhoods}
        expectInvalid("contact facing disagrees with source stitch"){_=try validate(f,plan:wrongFacing)}
        let falseGather=try mutate(f.plan){$0["usesFiniteCoarseTacks"]=true}
        expectInvalid("ordinary source seam falsely labeled as gather/ease tacks"){_=try validate(f,plan:falseGather)}
        var triangles=f.input.triangleIndices;triangles.swapAt(0,1);c=Changes();c.triangles=triangles
        expectInvalid("single reversed simulation face"){_=try validate(f,input:copy(f.input,c))}
        var ref=f.input.referenceTriangles;ref.swapAt(0,1);c=Changes();c.referenceTriangles=ref
        expectInvalid("single reversed source reference face"){_=try validate(f,input:copy(f.input,c))}
        let panel=f.document.pattern.panels.values.first!,many=Dictionary(uniqueKeysWithValues:(0..<129).map{("panel\($0)",panel)})
        let oversized=GarmentCodePatternFile(pattern:.init(panels:many,stitches:[]))
        var budget=false;do{_=try D.canonicalSourceSHA256(document:oversized)}catch S.SewingError.budgetExceeded{budget=true}
        try require(budget,"Oversized source did not fail explicit source budget");rejected.append("source panel budget")
        var cancelled=false
        do{_=try D.prepare(input:f.input,plan:f.plan,document:f.document,bindings:f.bindings,isCancelled:{true})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Pre-cancelled validation returned verified input");rejected.append("pre-cancel")
        let counter=CancelCounter();cancelled=false
        do{_=try D.prepare(input:f.input,plan:f.plan,document:f.document,bindings:f.bindings,isCancelled:{counter.cancel()})}catch is CancellationError{cancelled=true}
        try require(cancelled,"Cancellation during source verification returned verified input");rejected.append("mid-validation cancellation")
    }
    static func gathered(_ seed:Fixture)throws->Fixture {
        let wb=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/waistband-straight.json"))).geometryPanels()["wb_front"]!
        let skirt=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-two-panel.json"))).geometryPanels()["skirt_front"]!
        let document=try GarmentCodePatternFile(geometry:[skirt.id:skirt,wb.id:wb],stitches:[.init(sides:[.init(panel:skirt.id,edge:2),.init(panel:wb.id,edge:2)])])
        let panels=try document.geometryPanels();var bindings:[S.PanelBinding]=[],flat:[V]=[],triangles:[UInt32]=[]
        for id in panels.keys.sorted(){let mesh=try GarmentCodePanelMesher.prepare(panel:panels[id]!,targetEdgeMeters:0.03);let binding=try S.PanelBinding(mesh:mesh,vertexOffset:flat.count,triangleOffset:triangles.count/3);bindings.append(binding);flat += mesh.flatPositions;triangles += mesh.triangleIndices.map{UInt32(binding.vertexIDs[Int($0)])}}
        var simulated=triangles
        for binding in bindings where binding.mesh.sourceClockwise {for face in binding.triangleIDs {simulated.swapAt(face*3+1,face*3+2)}}
        let area=stride(from:0,to:triangles.count,by:3).reduce(0.0){sum,i in let a=flat[Int(triangles[i])],b=flat[Int(triangles[i+1])],c=flat[Int(triangles[i+2])];return sum+(b-a).cross(c-a).length/2}
        let points=flat.map{$0+V(x:2,y:0,z:0)},pins=Array(repeating:false,count:flat.count)
        var input=K.Input(positions:points,triangleIndices:simulated,referencePositions:flat,referenceTriangles:triangles,referenceToSimulation:Array(flat.indices),panelColumns:0,radialSegments:0,seamPaths:[],seamVertexPairs:[],pinned:pins,springs:sourceSprings(flat,triangles),bendingSprings:[],body:seed.input.body,mannequinPositions:seed.input.mannequinPositions,mannequinTriangleIndices:seed.input.mannequinTriangleIndices,waistCircumferenceMeters:seed.input.waistCircumferenceMeters,hemCircumferenceMeters:seed.input.hemCircumferenceMeters,radialLengthMeters:seed.input.radialLengthMeters,referenceAreaSquareMeters:area,settings:seed.input.settings)
        input.standardBody=seed.input.standardBody;input.bodySurfaceMesh=seed.input.bodySurfaceMesh;input.garmentStyle="Skirt2-StraightWB-validation-only";input=try withMass(input)
        let sha=try D.canonicalSourceSHA256(document:document),source=sourceStitches(document),s=source[0]
        let hint=S.StitchHint(stitchIndex:0,seamID:"gather",a:s.a,b:s.b,aDirection:.forward,bDirection:.reverse,rightWrong:s.rightWrong,intent:.gathered(longerSide:.a,maximumLengthRatio:1.31),maximumTackSpacingMeters:0.10,minimumFreeBoundaryNodes:1)
        let plan=try S.build(bindings:bindings,positions:points,sourceStitches:source,actualSourceSHA256:sha,assembly:.init(sourceSHA256:sha,hints:[hint]))
        return Fixture(document:document,input:input,bindings:bindings,plan:plan)
    }
    static func main()throws {
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json")),body=GarmentCodeBodyParameters(values:catalog.body)
        let resourceFiles=["GarmentCodeStandardBody.json","GarmentCodeStandardBodySource.json","GarmentCodeStandardBodySDF.bin"].map{root.appendingPathComponent("TrailorAss/Resources/"+$0)}
        let resourceBefore=try resourceFiles.map{try Data(contentsOf:$0)}
        let straight=try waistband("StraightWB",catalog:catalog,body:body),fitted=try waistband("FittedWB",catalog:catalog,body:body)
        let sourcesBefore=try [encode(straight.document),encode(fitted.document)]
        try positive(straight,"StraightWB");try positive(fitted,"FittedWB");try malformedChecks(straight)
        var cyclicTriangles=straight.input.triangleIndices,cyclicReference=straight.input.referenceTriangles
        cyclicTriangles.replaceSubrange(0..<3,with:[cyclicTriangles[1],cyclicTriangles[2],cyclicTriangles[0]])
        cyclicReference.replaceSubrange(0..<3,with:[cyclicReference[1],cyclicReference[2],cyclicReference[0]])
        var cyclicChanges=Changes();cyclicChanges.triangles=cyclicTriangles;cyclicChanges.referenceTriangles=cyclicReference
        let cyclic=try validate(straight,input:copy(straight.input,cyclicChanges))
        try require(cyclic.cloth.triangleIndices==cyclicTriangles && cyclic.cloth.referenceTriangles==cyclicReference,"Equivalent cyclic face rotations were changed")
        log("PASS equivalent cyclic triangle rotations preserve reference and original fabric orientation")
        let gather=try gathered(straight);try positive(gather,"fixture-backed sparse gather (placement validation only)")
        try require(!gather.plan.foldIntervals.isEmpty,"Gather test has no free-fold intervals")
        let ids=gather.plan.foldIntervals[0].untackedBoundaryVertexIDs;try require(!ids.isEmpty,"Gather test contains no genuine free boundary nodes")
        var pins=gather.input.pinned;for id in ids{pins[id]=true};var c=Changes();c.pinned=pins
        let locked=try withMass(copy(gather.input,c))
        expectInvalid("gather interval with all purported free nodes pinned"){_=try validate(gather,input:locked)}
        let falseContinuous=try mutate(gather.plan){$0["usesFiniteCoarseTacks"]=false}
        expectInvalid("sparse gather falsely labeled as continuous matching"){_=try validate(gather,plan:falseContinuous)}
        try require(try [encode(straight.document),encode(fitted.document)]==sourcesBefore,"Negative validation mutated the source documents")
        try require(try resourceFiles.map{try Data(contentsOf:$0)}==resourceBefore,"Validation changed the body resources")
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_SEWN_INPUT_OUTPUT"] ?? "/private/tmp/TailorAssSewnInput")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        for (name,f) in [("straight",straight),("fitted",fitted),("gather",gather)] {try encode(f.document).write(to:out.appendingPathComponent(name+"-source.json"));try encode(f.plan).write(to:out.appendingPathComponent(name+"-plan.json"))}
        let summary:[String:Any] = ["passed":acceptedInvalid.isEmpty,"positiveCases":["StraightWB","FittedWB","sparse fixture gather"],"rejectedCases":rejected,"acceptedInvalidCases":acceptedInvalid,"sourceUnchanged":true,"bodyResourcesUnchanged":true,"scope":"Verified source/assembly/mass/body input contracts. This suite does not certify physical fit, final sewn drape, or continuous gathered seam closure."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("sewn-input-summary.json"))
        try require(acceptedInvalid.isEmpty,"Factory accepted invalid inputs: \(acceptedInvalid.joined(separator:", "))")
        print("PASS: verified separate source inputs, mass/body/plan provenance, \(rejected.count) invalid/cancel/budget cases, true free gather DOFs and immutable source")
    }
}
