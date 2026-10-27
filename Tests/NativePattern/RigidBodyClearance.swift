import Foundation

@main @MainActor struct RigidBodyClearanceRegression {
    typealias R=GarmentCodeRigidBodyClearance
    typealias K=GarmentCodeCircleDrape
    typealias V=K.Vector3
    typealias Oracle=BodySurfaceContactRegression
    enum Failure:Error{case check(String)}
    struct Rest:Encodable {
        let a:Int,b:Int,length:Double,isShear:Bool
        init(_ s:K.Spring){a=s.a;b=s.b;length=s.length;isShear=s.isShear}
    }
    struct SavedInput:Encodable {
        let positions:[V],referencePositions:[V],triangleIndices:[UInt32],referenceTriangles:[UInt32]
        let inverseMasses:[Double],pinned:[Bool],sourceSHA256:String
        let springs:[Rest],bendingSprings:[Rest]
        let mannequinPositions:[V],mannequinTriangleIndices:[UInt32]
    }
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func v(_ x:Double,_ y:Double,_ z:Double)->V{.init(x:x,y:y,z:z)}
    static func dot(_ a:V,_ b:V)->Double{a.x*b.x+a.y*b.y+a.z*b.z}
    static func require(_ b:@autoclosure()throws->Bool,_ s:String)throws{if try !b(){throw Failure.check(s)}}
    static func encode<T:Encodable>(_ x:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return try e.encode(x)}
    static func object<T:Encodable>(_ x:T)throws->Any{try JSONSerialization.jsonObject(with:encode(x))}
    static func log(_ s:String){FileHandle.standardError.write(Data((s+"\n").utf8))}
    static func panel(_ id:String="sheet",_ z:Double=0,_ x:Double=0)->R.Panel {
        .init(panelID:id,positions:[v(x-1,-1,z),v(x+1,-1,z),v(x+1,1,z),v(x-1,1,z)],u:v(1,0,0),v:v(0,1,0),normal:v(0,0,1))
    }
    /// Independent 2D convex clipping for positive-area coplanar overlap. Proper
    /// 3D crossings use the separate segment/triangle oracle. Edge touches have
    /// zero area and are not silently expanded into a panel contact exemption.
    static func coplanarOverlap(_ a:Oracle.Face,_ b:Oracle.Face)->Bool {
        if !a.overlaps(b) || a.normal.lengthSquared<0.5 || b.normal.lengthSquared<0.5 ||
            a.normal.cross(b.normal).length>1e-10 || abs(dot(b.a-a.a,a.normal))>1e-9{return false}
        let n=a.normal,drop=abs(n.x)>abs(n.y) ? (abs(n.x)>abs(n.z) ? 0:2):(abs(n.y)>abs(n.z) ? 1:2)
        func point(_ p:V)->(Double,Double){drop==0 ? (p.y,p.z):(drop==1 ? (p.x,p.z):(p.x,p.y))}
        func cross(_ a:(Double,Double),_ b:(Double,Double),_ c:(Double,Double))->Double{(b.0-a.0)*(c.1-a.1)-(b.1-a.1)*(c.0-a.0)}
        let triangle=[point(b.a),point(b.b),point(b.c)],sign=cross(triangle[0],triangle[1],triangle[2])>0 ? 1.0:-1.0
        var polygon=[point(a.a),point(a.b),point(a.c)]
        for i in 0..<3 {
            if polygon.isEmpty{return false}
            let start=triangle[i],end=triangle[(i+1)%3],old=polygon
            polygon=[]
            for j in old.indices {
                let p=old[j],q=old[(j+1)%old.count],dp=sign*cross(start,end,p),dq=sign*cross(start,end,q)
                if dp>=0{polygon.append(p)}
                if (dp>=0) != (dq>=0){let t=dp/(dp-dq);polygon.append((p.0+t*(q.0-p.0),p.1+t*(q.1-p.1)))}
            }
        }
        if polygon.count<3{return false}
        var area=0.0
        for i in polygon.indices{let p=polygon[i],q=polygon[(i+1)%polygon.count];area += p.0*q.1-p.1*q.0}
        return abs(area)/2>1e-14
    }
    /// Recompute every candidate and support bound independently, including all
    /// triangles whose AABB is a false positive. No source triangle is skipped.
    static func audit(_ input:[R.Panel],_ body:Oracle.Mesh,_ result:R.Result)throws {
        try require(result.proof.bodyGeometrySHA256==R.geometrySHA256(positions:body.positions,indices:body.indices),"Body geometry identity changed")
        for proof in result.proof.panels {
            let p=input.first{$0.panelID==proof.panelID}!,moved=result.positionsByPanel[p.panelID]!,origin=p.positions[0]
            var candidates:[Int]=[],extents:[Double]=[]
            for t in stride(from:0,to:body.indices.count,by:3) {
                let points=(0..<3).map{body.positions[Int(body.indices[t+$0])]},us=points.map{dot($0-origin,p.u)},vs=points.map{dot($0-origin,p.v)},b=proof.selectedBounds
                if us.min()!<=b.maximumU && us.max()!>=b.minimumU && vs.min()!<=b.maximumV && vs.max()!>=b.minimumV {
                    candidates.append(t/3);extents += points.map{dot($0,p.normal)}
                }
            }
            try require(candidates==proof.candidateBodyTriangleIDs,"Candidate omission, including edge/vertex UV equality")
            for i in p.positions.indices {
                try require((moved[i]-p.positions[i]-proof.appliedTranslation).length<1e-12,"Per-vertex deformation replaced a rigid shift")
                for j in p.positions.indices{try require(abs((moved[i]-moved[j]).length-(p.positions[i]-p.positions[j]).length)<1e-12,"Rigid source distance changed")}
            }
            try require(abs(proof.appliedTranslation.length-result.proof.commonTranslationMagnitudeMeters)<1e-12,"Panels did not share amplitude")
            if !extents.isEmpty {
                let plane=dot(moved[0],p.normal),actual=proof.chosenNormalSign>0 ? plane-extents.max()!:extents.min()!-plane
                try require(actual>=result.proof.requestedShellMeters-1e-12 && abs(actual-proof.selectedTriangleSupportClearanceMeters!)<1e-10,"Actual support shell not certified")
            }
        }
    }
    static func analytic()throws->[String:Any] {
        var cases:[String]=[]
        let box=Oracle.box(center:.zero,half:v(0.1,0.1,0.08)),sheet=panel()
        let result=try R.prepare(panels:[sheet],bodyPositions:box.positions,bodyTriangleIndices:box.indices)
        try audit([sheet],box,result)
        try require(abs(result.proof.commonTranslationMagnitudeMeters-0.082500001)<1e-12 && result.proof.panels[0].chosenNormalSign==1,"Closed box nearest/tie support plane incorrect")
        cases.append("closed box exact support shell")
        let panels=[panel("front",0.01),panel("back",-0.03),panel("no-hit",0,4)]
        let grouped=try R.prepare(panels:panels,bodyPositions:box.positions,bodyTriangleIndices:box.indices)
        try audit(panels,box,grouped)
        try require(grouped.proof.panels[0].chosenNormalSign==1 && grouped.proof.panels[1].chosenNormalSign == -1 && grouped.proof.panels[2].candidateBodyTriangleIDs.isEmpty,"Same-facing front/back or no-hit direction changed")
        try require(grouped.proof.panels[2].appliedTranslation.length>0,"No-hit panel omitted common translation")
        cases.append("common amplitude opposite sides and no-hit panel")
        let transform=try GarmentCodePanelPlacement.Transform(rotationDegrees:[23,37,-11],translation:[13,8,-4],unitsInMeter:100,waistLevelCentimeters:0)
        let tilted=R.Panel(panelID:"tilted",positions:try sheet.positions.map{try transform.point($0)},u:try transform.direction(sheet.u),v:try transform.direction(sheet.v),normal:try transform.direction(sheet.normal))
        let tiltedBody=Oracle.Mesh(positions:try box.positions.map{try transform.point($0)},indices:box.indices)
        let tiltedResult=try R.prepare(panels:[tilted],bodyPositions:tiltedBody.positions,bodyTriangleIndices:tiltedBody.indices)
        try audit([tilted],tiltedBody,tiltedResult)
        try require(abs(tiltedResult.proof.commonTranslationMagnitudeMeters-result.proof.commonTranslationMagnitudeMeters)<1e-12,"Rigidly rotated input changed support distance")
        let reversed=R.Panel(panelID:tilted.panelID,positions:tilted.positions,u:tilted.u,v:tilted.v,normal:tilted.normal * -1)
        let reverseResult=try R.prepare(panels:[reversed],bodyPositions:tiltedBody.positions,bodyTriangleIndices:Oracle.reverse(tiltedBody).indices)
        try audit([reversed],Oracle.reverse(tiltedBody),reverseResult)
        try require(zip(tiltedResult.positionsByPanel[tilted.panelID]!,reverseResult.positionsByPanel[tilted.panelID]!).allSatisfy{($0-$1).length<1e-12},"Reversing cloth/body normals changed actual outside placement")
        cases.append("tilted plane and reversed normals")
        let slanted=Oracle.Mesh(positions:[v(-0.5,-0.5,-0.03),v(0.5,-0.5,0.13),v(0,0.5,-0.02)],indices:[0,1,2])
        var near=panel();near=R.Panel(panelID:near.panelID,positions:near.positions.map{$0+v(0,0,0.08)},u:near.u,v:near.v,normal:near.normal)
        let slantedResult=try R.prepare(panels:[near],bodyPositions:slanted.positions,bodyTriangleIndices:slanted.indices)
        try audit([near],slanted,slantedResult)
        try require(abs(slantedResult.proof.panels[0].minimumRequiredTranslationMeters-0.052500001)<1e-12,"Slanted triangle vertex extrema omitted")
        cases.append("slanted body triangle support extrema")
        let curveBody=Oracle.Mesh(positions:[v(1.00252,-0.01,-0.1),v(1.00253,-0.01,0.1),v(1.00252,0.01,0.1)],indices:[0,1,2])
        var curve=sheet;curve.maximumBoundaryDeviationMeters=0.00005
        let curveResult=try R.prepare(panels:[curve],bodyPositions:curveBody.positions,bodyTriangleIndices:curveBody.indices)
        try audit([curve],curveBody,curveResult)
        let chordResult=try R.prepare(panels:[sheet],bodyPositions:curveBody.positions,bodyTriangleIndices:curveBody.indices)
        try require(curveResult.proof.panels[0].candidateBodyTriangleIDs==[0] && chordResult.proof.panels[0].candidateBodyTriangleIDs.isEmpty,"Curve error/shell-expanded rectangle was not conservative")
        cases.append("curved-boundary conservative UV bounds")
        let far=panel("far",0,4),empty=try R.prepare(panels:[far],bodyPositions:box.positions,bodyTriangleIndices:box.indices)
        try audit([far],box,empty)
        try require(empty.positionsByPanel["far"]==far.positions && empty.proof.panels[0].candidateBodyTriangleIDs.isEmpty,"No-hit-only input should need no support shift")
        cases.append("no body candidates")
        let f=Oracle.Face(v(0,0,0),v(1,0,0),v(0,1,0)),overlap=Oracle.Face(v(0.1,0.1,0),v(0.8,0.1,0),v(0.1,0.8,0)),touch=Oracle.Face(v(0,0,0),v(-1,0,0),v(0,-1,0))
        try require(coplanarOverlap(f,overlap) && !coplanarOverlap(f,touch),"Independent self oracle must distinguish overlap from corner touch")
        cases.append("independent coplanar self-overlap oracle")
        var rejected=0
        func rejects(_ label:String,_ operation:()throws->Void)throws {
            do{try operation()}catch is R.ClearanceError{rejected += 1;return}catch is CancellationError{rejected += 1;return}
            throw Failure.check("Expected explicit rejection: "+label)
        }
        try rejects("duplicate panel"){_=try R.prepare(panels:[sheet,sheet],bodyPositions:box.positions,bodyTriangleIndices:box.indices)}
        try rejects("wrong normal"){let p=R.Panel(panelID:"bad",positions:sheet.positions,u:sheet.u,v:sheet.v,normal:v(1,0,0));_=try R.prepare(panels:[p],bodyPositions:box.positions,bodyTriangleIndices:box.indices)}
        try rejects("nonplanar"){var q=sheet.positions;q[0].z=0.001;let p=R.Panel(panelID:"bad",positions:q,u:sheet.u,v:sheet.v,normal:sheet.normal);_=try R.prepare(panels:[p],bodyPositions:box.positions,bodyTriangleIndices:box.indices)}
        try rejects("body bad index"){_=try R.prepare(panels:[sheet],bodyPositions:box.positions,bodyTriangleIndices:[0,1,999])}
        try rejects("body degenerate"){_=try R.prepare(panels:[sheet],bodyPositions:box.positions,bodyTriangleIndices:[0,0,1])}
        try rejects("nonfinite shell"){_=try R.prepare(panels:[sheet],bodyPositions:box.positions,bodyTriangleIndices:box.indices,shellMeters:.nan)}
        try rejects("nonfinite source"){var q=sheet.positions;q[0].x = .infinity;let p=R.Panel(panelID:"bad",positions:q,u:sheet.u,v:sheet.v,normal:sheet.normal);_=try R.prepare(panels:[p],bodyPositions:box.positions,bodyTriangleIndices:box.indices)}
        try rejects("cloth budget"){var limits=R.Limits();limits.maximumClothVertices=3;_=try R.prepare(panels:[sheet],bodyPositions:box.positions,bodyTriangleIndices:box.indices,limits:limits)}
        try rejects("triangle test budget"){var limits=R.Limits();limits.maximumTrianglePanelTests=1;_=try R.prepare(panels:[sheet],bodyPositions:box.positions,bodyTriangleIndices:box.indices,limits:limits)}
        try rejects("cancel start"){_=try R.prepare(panels:[sheet],bodyPositions:box.positions,bodyTriangleIndices:box.indices,isCancelled:{true})}
        let counter=NativeAssemblyRegression.CancellationCounter(limit:5)
        try rejects("cancel mid-query"){_=try R.prepare(panels:panels,bodyPositions:box.positions,bodyTriangleIndices:box.indices,isCancelled:{counter.cancelled()})}
        return ["passed":true,"cases":cases,"explicitRefusals":rejected,"sourceRestModified":false,"bodyGeometryModified":false]
    }
    struct Edge:Hashable {
        let a:Int,b:Int
        init(_ a:Int,_ b:Int) {self.a=min(a,b);self.b=max(a,b)}
    }
    struct Cell:Hashable {let u:Int,v:Int}
    struct RayTriangle {
        let a:V,e1u:Double,e1v:Double,e2u:Double,e2v:Double,det:Double,axis1:Double,axis2:Double
    }
    struct Parity:Codable {var outside=0,inside=0,ambiguous=0}
    /// Independent +X/+Y/+Z parity against actual closed body triangles.
    /// It never consults the production SDF or body-contact implementation.
    struct BodyVolume {
        let bins:[[Cell:[RayTriangle]]]
        static let cell=0.025,epsilon=1e-7
        static func coord(_ p:V,_ axis:Int)->Double {axis==0 ? p.x : (axis==1 ? p.y : p.z)}
        @MainActor init(positions:[V],indices:[UInt32])throws {
            var edges:[Edge:(Int,Int)]=[:],volume=0.0,all=Array(repeating:[Cell:[RayTriangle]](),count:3)
            for offset in stride(from:0,to:indices.count,by:3) {
                let ids=(0..<3).map{Int(indices[offset+$0])},a=positions[ids[0]],b=positions[ids[1]],c=positions[ids[2]]
                volume += a.x*(b.y*c.z-b.z*c.y)+a.y*(b.z*c.x-b.x*c.z)+a.z*(b.x*c.y-b.y*c.x)
                for (x,y) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])] {
                    let key=Edge(x,y),old=edges[key] ?? (0,0)
                    edges[key]=(old.0+1,old.1+(x<y ? 1 : -1))
                }
                for axis in 0..<3 {
                    let u=(axis+1)%3,v=(axis+2)%3
                    let x=Self.coord(b,u)-Self.coord(a,u),y=Self.coord(b,v)-Self.coord(a,v)
                    let z=Self.coord(c,u)-Self.coord(a,u),w=Self.coord(c,v)-Self.coord(a,v),det=x*w-y*z
                    if abs(det)<1e-18 {continue}
                    let packet=RayTriangle(a:a,e1u:x,e1v:y,e2u:z,e2v:w,det:det,axis1:Self.coord(b,axis)-Self.coord(a,axis),axis2:Self.coord(c,axis)-Self.coord(a,axis))
                    let loU=Int(floor(min(Self.coord(a,u),Self.coord(b,u),Self.coord(c,u))/Self.cell)),hiU=Int(floor(max(Self.coord(a,u),Self.coord(b,u),Self.coord(c,u))/Self.cell))
                    let loV=Int(floor(min(Self.coord(a,v),Self.coord(b,v),Self.coord(c,v))/Self.cell)),hiV=Int(floor(max(Self.coord(a,v),Self.coord(b,v),Self.coord(c,v))/Self.cell))
                    for i in loU...hiU {for j in loV...hiV {all[axis][.init(u:i,v:j),default:[]].append(packet)}}
                }
            }
            try RigidBodyClearanceRegression.require(edges.values.allSatisfy{$0.0==2 && $0.1==0} && volume>0,"Body parity requires an outward closed two-manifold")
            bins=all
        }
        func classify(_ points:[V])->Parity {
            var result=Parity()
            for p in points {
                var bits:[Bool]=[],uncertain=false
                for axis in 0..<3 {
                    let u=(axis+1)%3,v=(axis+2)%3,key=Cell(u:Int(floor(Self.coord(p,u)/Self.cell)),v:Int(floor(Self.coord(p,v)/Self.cell)))
                    var hits:[(Double,Int)]=[]
                    for q in bins[axis][key] ?? [] {
                        let pu=Self.coord(p,u)-Self.coord(q.a,u),pv=Self.coord(p,v)-Self.coord(q.a,v)
                        let b=(pu*q.e2v-pv*q.e2u)/q.det,c=(q.e1u*pv-q.e1v*pu)/q.det
                        if b < -1e-10 || c < -1e-10 || b+c>1+1e-10 {continue}
                        let t=Self.coord(q.a,axis)+b*q.axis1+c*q.axis2-Self.coord(p,axis)
                        if abs(t)<=Self.epsilon {uncertain=true}
                        else if t>Self.epsilon {hits.append((t,q.det>0 ? 1 : -1))}
                    }
                    hits.sort{$0.0<$1.0}
                    var count=0,last = -Double.infinity,sign=0
                    for hit in hits {
                        if abs(hit.0-last)<=Self.epsilon {if hit.1 != sign {uncertain=true}}
                        else {count += 1;last=hit.0;sign=hit.1}
                    }
                    bits.append(count%2==1)
                }
                if uncertain || Set(bits).count != 1 {result.ambiguous += 1}
                else if bits[0] {result.inside += 1}
                else {result.outside += 1}
            }
            return result
        }
    }

    static func quality(_ prepared:GarmentCodeSewnDrape.PreparedInput)throws->[String:Any] {
        let input=prepared.cloth,positions=input.positions
        let topology=try GarmentCodeSewnDrape.contactTopology(vertexCount:positions.count,triangleIndices:input.triangleIndices,plan:prepared.plan,referencePositions:input.referencePositions)
        let selfQ=try GarmentCodeClothContact.inspect(positions:positions,topology:topology,thickness:0.005)
        let bodyQ=try GarmentCodeBodySurfaceContact.inspect(positions:positions,topology:topology,body:input.bodySurfaceMesh!,thickness:input.settings.bodySurfaceClearanceMeters)
        let crossings=Oracle.oracleCount(cloth:.init(positions:positions,indices:input.triangleIndices),body:.init(positions:input.mannequinPositions,indices:input.mannequinTriangleIndices))
        let volume=try BodyVolume(positions:input.mannequinPositions,indices:input.mannequinTriangleIndices),vertices=volume.classify(positions)
        let centers=stride(from:0,to:input.triangleIndices.count,by:3).map{i in (0..<3).reduce(V.zero){$0+positions[Int(input.triangleIndices[i+$1])]} / 3},centroids=volume.classify(centers)
        var pairCrossings=0,coplanarCrossings=0
        for a in prepared.panelBindings.indices{for b in prepared.panelBindings.indices where b>a{
            let first=prepared.panelBindings[a],second=prepared.panelBindings[b]
            let pa=first.vertexIDs.map{positions[$0]},pb=second.vertexIDs.map{positions[$0]}
            pairCrossings += Oracle.oracleCount(cloth:.init(positions:pa,indices:first.mesh.triangleIndices),body:.init(positions:pb,indices:second.mesh.triangleIndices))
            let fa=Oracle.faces(.init(positions:pa,indices:first.mesh.triangleIndices)),fb=Oracle.faces(.init(positions:pb,indices:second.mesh.triangleIndices))
            for x in fa{for y in fb where x.overlaps(y){if coplanarOverlap(x,y){coplanarCrossings += 1}}}
        }}
        let sewing=try GarmentCodeSewing.inspect(positions:positions,constraints:prepared.plan.constraints)
        return ["source":try NativeAssemblyRegression.check(prepared,document:currentDocument!),"selfQuality":try object(selfQ),"bodyQuality":try object(bodyQ),
            "independentBodyTriangleCrossings":crossings,"independentInterPanelProperCrossings":pairCrossings,"independentInterPanelCoplanarOverlaps":coplanarCrossings,
            "insideVertices":vertices.inside,"ambiguousVertices":vertices.ambiguous,"insideCentroids":centroids.inside,"ambiguousCentroids":centroids.ambiguous,
            "maximumSDFBodyPenetrationMeters":positions.map{input.standardBody!.penetration($0)}.max() ?? 0,
            "maximumActualInitialSeamGapMeters":sewing.maximumGapMeters,"physicalAcceptance":false]
    }
    static var currentDocument:GarmentCodePatternFile?
    static func main()throws {
        let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["GARMENTCODE_CLEARANCE_OUTPUT"] ?? "/private/tmp/TailorAssRigidBodyClearance")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        func save(_ x:[String:Any],_ name:String)throws{try JSONSerialization.data(withJSONObject:x,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent(name+".json"))}
        let analyticProof=try analytic();try save(analyticProof,"analytic-proof");log("PASS conservative support-plane analytic proof and refusals")
        let document=try GarmentCodePatternFile.validatedImport(from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Fixtures/3d-sewn-point-block/straight-default-source.json")))
        currentDocument=document
        guard case let .object(bodyValues)?=document.parameters?["body"],case let .object(designValues)?=document.parameters?["design"] else{throw Failure.check("Complete paper parameters missing")}
        let body=GarmentCodeBodyParameters(values:bodyValues.compactMapValues(\.numberValue))
        let nodes=try JSONDecoder().decode([String:GarmentCodeParameterNode].self,from:encode(JSONValue.object(designValues)))
        let catalog=GarmentCodeParameterCatalog(design:nodes,body:body.values,bodyDerivedFormulas:nil),design=GarmentCodeDesignParameters(catalog:catalog)
        var settings=NativeAssemblyRegression.settings();settings.targetEdgeMeters=0.035
        let before=try encode(document),native=try GarmentCodeNativeAssembly.prepare(document:document,body:body,design:design,settings:settings)
        let explicit=try GarmentCodeNativeAssembly.prepareWithReport(document:document,body:body,design:design,settings:settings,initialization:.nativeConstruction)
        try require(explicit.bodyClearanceProof==nil && native.cloth.positions==explicit.preparedInput.cloth.positions && encode(native.plan)==encode(explicit.preparedInput.plan),"Default native matrices/plan changed")
        let preparation=try GarmentCodeNativeAssembly.prepareWithReport(document:document,body:body,design:design,settings:settings,initialization:.rigidBodyClearance)
        let cleared=preparation.preparedInput,input=cleared.cloth,proof=preparation.bodyClearanceProof!
        try require(before==encode(document) && native.sourceSHA256==cleared.sourceSHA256 && native.cloth.referencePositions==input.referencePositions && native.cloth.referenceTriangles==input.referenceTriangles && native.cloth.triangleIndices==input.triangleIndices && native.cloth.inverseMasses==input.inverseMasses && native.cloth.pinned==input.pinned,"Source, DOF, paper, mass or topology changed")
        try require(native.cloth.mannequinPositions==input.mannequinPositions && native.cloth.mannequinTriangleIndices==input.mannequinTriangleIndices,"Visible body was replaced")
        try require(encode(native.cloth.springs.map(Rest.init))==encode(input.springs.map(Rest.init)) && encode(native.cloth.bendingSprings.map(Rest.init))==encode(input.bendingSprings.map(Rest.init)),"Original source rest graph changed")
        let helperPanels=native.panelBindings.map{binding -> R.Panel in
            let p=proof.panels.first{$0.panelID==binding.mesh.panelID}!
            return .init(panelID:binding.mesh.panelID,positions:binding.vertexIDs.map{native.cloth.positions[$0]},u:p.u,v:p.v,normal:p.normal,maximumBoundaryDeviationMeters:binding.mesh.maximumBoundaryDeviationMeters)
        }
        let proofResult=R.Result(positionsByPanel:Dictionary(uniqueKeysWithValues:cleared.panelBindings.map{($0.mesh.panelID,$0.vertexIDs.map{input.positions[$0]})}),proof:proof)
        try audit(helperPanels,.init(positions:input.mannequinPositions,indices:input.mannequinTriangleIndices),proofResult)
        let nativeQuality=try quality(native),clearQuality=try quality(cleared)
        try save(nativeQuality,"native-before-quality");try save(clearQuality,"clearance-after-quality")
        try encode(proof).write(to:out.appendingPathComponent("body-clearance-proof.json"));try before.write(to:out.appendingPathComponent("complete-source.json"));try encode(cleared.plan).write(to:out.appendingPathComponent("complete-plan.json"))
        try encode(SavedInput(positions:input.positions,referencePositions:input.referencePositions,triangleIndices:input.triangleIndices,referenceTriangles:input.referenceTriangles,inverseMasses:input.inverseMasses,pinned:input.pinned,sourceSHA256:cleared.sourceSHA256,springs:input.springs.map(Rest.init),bendingSprings:input.bendingSprings.map(Rest.init),mannequinPositions:input.mannequinPositions,mannequinTriangleIndices:input.mannequinTriangleIndices)).write(to:out.appendingPathComponent("clearance-initial-input.json"))
        let selfQ=clearQuality["selfQuality"] as! [String:Any],bodyQ=clearQuality["bodyQuality"] as! [String:Any]
        let passed=(selfQ["intersectingTrianglePairs"] as! Int)==0 && (bodyQ["intersectingTrianglePairs"] as! Int)==0 && (clearQuality["independentBodyTriangleCrossings"] as! Int)==0 && (clearQuality["independentInterPanelProperCrossings"] as! Int)==0 && (clearQuality["independentInterPanelCoplanarOverlaps"] as! Int)==0 && (clearQuality["insideVertices"] as! Int)==0 && (clearQuality["insideCentroids"] as! Int)==0 && (clearQuality["ambiguousVertices"] as! Int)==0 && (clearQuality["ambiguousCentroids"] as! Int)==0
        try save(["passedRigidBodyAndSelfFreeInitialization":passed,"sourceSHA256":cleared.sourceSHA256,"commonTranslationMagnitudeMeters":proof.commonTranslationMagnitudeMeters,"sourceAndMassPreserved":true,"artificialPins":0,"nativeDefaultUnchanged":true,"actualQuality":clearQuality,"scope":"Rigid source initialization only, no dynamics/CCD/sewn-cloth acceptance run"],"rigid-initialization-summary")
        log("CLEARANCE common shift \(proof.commonTranslationMagnitudeMeters)m, body \(clearQuality["independentBodyTriangleCrossings"]!), self \(selfQ["intersectingTrianglePairs"]!), source \((clearQuality["source"] as! [String:Any])["maximumInitialSourceStrain"]!), initial gap \(clearQuality["maximumActualInitialSeamGapMeters"]!)m")
        try require(passed,"Rigid support-plane shift is not a body/self-free initialization; actual proof retained, no crossing masked")
    }
}
