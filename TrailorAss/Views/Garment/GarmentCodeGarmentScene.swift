import Foundation

/// Pure metre-space framing. It has no actor, UIKit, simulation or source-model
/// dependency and never changes a garment vertex.
nonisolated enum GarmentCodeDrapeFraming {
    typealias P=SIMD3<Double>
    enum FramingError:LocalizedError,Sendable {case invalid
        var errorDescription:String? {"三维画面边界或相机参数无效。"}}
    enum Focus:Sendable {case visibleGeometry,garment}
    struct Bounds:Sendable,Equatable {
        let minimum:P,maximum:P
        init(points:[P])throws {
            guard let first=points.first,points.count<=220_000,Self.usable(first) else {throw FramingError.invalid}
            var lo=first,hi=first
            for p in points {guard Self.usable(p) else {throw FramingError.invalid};lo=Self.low(lo,p);hi=Self.high(hi,p)}
            minimum=lo;maximum=hi
        }
        private init(minimum:P,maximum:P){self.minimum=minimum;self.maximum=maximum}
        var center:P {minimum+(maximum-minimum)/2}
        var corners:[P] {
            [minimum.x,maximum.x].flatMap{x in [minimum.y,maximum.y].flatMap{y in [minimum.z,maximum.z].map{P(x,y,$0)}}}
        }
        func union(_ b:Bounds)->Bounds {.init(minimum:Self.low(minimum,b.minimum),maximum:Self.high(maximum,b.maximum))}
        private static func usable(_ p:P)->Bool {p.x.isFinite && p.y.isFinite && p.z.isFinite && max(abs(p.x),abs(p.y),abs(p.z))<=1e6}
        private static func low(_ a:P,_ b:P)->P {.init(min(a.x,b.x),min(a.y,b.y),min(a.z,b.z))}
        private static func high(_ a:P,_ b:P)->P {.init(max(a.x,b.x),max(a.y,b.y),max(a.z,b.z))}
    }
    struct Configuration:Sendable {
        var yaw=0.35,pitch = -0.08,zoomScale=1.0
        var verticalFieldOfViewDegrees=44.0
        var showMannequin=true,showSeams=true
        var focus:Focus = .visibleGeometry
    }
    struct Frame:Sendable {
        let center:P,distance:Double,nearPlane:Double,farPlane:Double,verticalFieldOfViewDegrees:Double
        let aspect:Double
    }
    static func rotated(_ p:P,yaw:Double,pitch:Double)->P {
        let cy=cos(yaw),sy=sin(yaw),cx=cos(pitch),sx=sin(pitch)
        let q=P(cy*p.x+sy*p.z,p.y,-sy*p.x+cy*p.z)
        return P(q.x,cx*q.y-sx*q.z,sx*q.y+cx*q.z)
    }
    /// At zoomScale>=1 every selected bound corner fits the perspective frustum
    /// at any yaw/pitch. Smaller zoom is an intentional user crop, while the
    /// camera still stays in front of the selected geometry and visible body.
    static func frame(garment:Bounds,mannequin:Bounds?,configuration c:Configuration,
                      width:Double,height:Double)throws->Frame {
        guard [c.yaw,c.pitch,c.zoomScale,c.verticalFieldOfViewDegrees,width,height].allSatisfy(\.isFinite),
              width>0,height>0,(0.25...8).contains(c.zoomScale),(10...90).contains(c.verticalFieldOfViewDegrees) else {throw FramingError.invalid}
        let body=c.showMannequin ? mannequin:nil
        let selected=c.focus == .visibleGeometry ? body.map{garment.union($0)} ?? garment:garment
        let center=selected.center,aspect=width/height,tanV=tan(c.verticalFieldOfViewDegrees*Double.pi/360),tanH=tanV*aspect
        guard aspect.isFinite,aspect>0,tanH>0 else {throw FramingError.invalid}
        let corners=selected.corners.map{rotated($0-center,yaw:c.yaw,pitch:c.pitch)}
        var fit=0.02,front = -Double.infinity,radius=0.01
        for p in corners {
            front=max(front,p.z);radius=max(radius,sqrt(p.x*p.x+p.y*p.y+p.z*p.z))
            fit=max(fit,p.z+1.12*abs(p.x)/tanH,p.z+1.12*abs(p.y)/tanV)
        }
        var minimumDistance=front+0.002,visibleRadius=radius
        if let body {
            for p in body.corners {
                let d=p-center,r=sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
                visibleRadius=max(visibleRadius,r)
                if c.focus == .garment {minimumDistance=max(minimumDistance,r+0.02)}
            }
        }
        let distance=max(minimumDistance,fit*c.zoomScale),near=max(0.0001,min(0.01,(distance-front)/4))
        let far=distance+2*visibleRadius+0.1
        guard distance.isFinite,near>0,far.isFinite,far>distance else {throw FramingError.invalid}
        return .init(center:center,distance:distance,nearPlane:near,farPlane:far,
                     verticalFieldOfViewDegrees:c.verticalFieldOfViewDegrees,aspect:aspect)
    }
}

#if canImport(UIKit) && canImport(SwiftUI) && canImport(SceneKit)
import UIKit
import SwiftUI
import SceneKit
import simd

/// Read-only viewer for an immutable producer-validated Output. It neither
/// starts simulation nor promotes an initialization/diagnostic mesh to a result.
struct GarmentCodeGarmentScene:UIViewRepresentable {
    let output:GarmentCodeCircleDrape.Output
    let meshID:UUID
    var configuration=GarmentCodeDrapeFraming.Configuration()
    var panelNames:[String:String]=[:]
    /// Explicit original source stitch IDs, one per seamPath. Nil retains the
    /// legacy orange overlay; the viewer never guesses pairing from topology.
    var seamGroupIDs:[Int]?=nil
    @Binding var renderIssue:String?

    func makeCoordinator()->Coordinator {Coordinator()}
    func makeUIView(context:Context)->SCNView {
        let view=LayoutSceneView();view.scene=context.coordinator.scene;view.pointOfView=context.coordinator.camera
        view.backgroundColor=UIColor(red:0.94,green:0.93,blue:0.90,alpha:1)
        view.antialiasingMode = .multisampling4X;view.allowsCameraControl=false
        view.onLayout={ [weak coordinator=context.coordinator,weak view] in guard let view else{return};coordinator?.updateCamera(view.bounds.size)}
        context.coordinator.view=view;return view
    }
    func updateUIView(_ view:SCNView,context:Context) {
        let c=context.coordinator;c.configuration=configuration
        if c.identity != meshID {
            c.begin(output:output,id:meshID,names:panelNames,seamGroups:seamGroupIDs,issue:$renderIssue)
        }
        c.bodyNode?.isHidden = !configuration.showMannequin;c.seamNode?.isHidden = !configuration.showSeams
        c.content.simdOrientation=simd_quatf(angle:Float(configuration.pitch),axis:[1,0,0])*simd_quatf(angle:Float(configuration.yaw),axis:[0,1,0])
        c.updateCamera(view.bounds.size)
    }
    static func dismantleUIView(_ view:SCNView,coordinator:Coordinator) {coordinator.cancel();view.scene=nil}

    final class Coordinator {
        let scene=SCNScene(),content=SCNNode(),camera=SCNNode()
        weak var view:SCNView?
        var bodyNode:SCNNode?,seamNode:SCNNode?,identity:UUID?
        var configuration=GarmentCodeDrapeFraming.Configuration()
        var garmentBounds:GarmentCodeDrapeFraming.Bounds?,bodyBounds:GarmentCodeDrapeFraming.Bounds?
        private var worker:Task<Payload,Error>?,observer:Task<Void,Never>?
        init() {
            scene.rootNode.addChildNode(content);camera.camera=SCNCamera();camera.camera?.projectionDirection = .vertical
            scene.rootNode.addChildNode(camera)
            let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=450;scene.rootNode.addChildNode(ambient)
            for (x,y,z,intensity) in [(1.5,2.5,2.0,1000.0),(-2.0,1.0,-1.5,600.0)] {
                let light=SCNNode();light.light=SCNLight();light.light?.type = .directional;light.light?.intensity=CGFloat(intensity)
                light.position=SCNVector3(Float(x),Float(y),Float(z));light.look(at:SCNVector3Zero);scene.rootNode.addChildNode(light)
            }
        }
        func cancel(){identity=nil;worker?.cancel();observer?.cancel();worker=nil;observer=nil}
        func begin(output:GarmentCodeCircleDrape.Output,id:UUID,names:[String:String],seamGroups:[Int]?,issue:Binding<String?>) {
            cancel();identity=id;content.childNodes.forEach{$0.removeFromParentNode()};garmentBounds=nil;bodyBounds=nil
            let task=Task.detached(priority:.userInitiated){try Payload.prepare(output,seamGroups:seamGroups)};worker=task
            observer=Task { @MainActor [weak self] in
                do {
                    let p=try await task.value;try Task.checkCancellation()
                    guard let self,self.identity==id else{return}
                    self.garmentBounds=p.garmentBounds;self.bodyBounds=p.bodyBounds
                    for mesh in p.panels {
                        let node=self.model(mesh,color:UIColor(red:0.14,green:0.48,blue:0.52,alpha:1));node.name=names[mesh.id] ?? mesh.id
                        self.content.addChildNode(node)
                    }
                    if let mesh=p.body {let node=self.model(mesh,color:UIColor(red:0.70,green:0.66,blue:0.60,alpha:1));self.bodyNode=node;self.content.addChildNode(node)}
                    let seam=self.lines(p.clothPositions,p.lines);self.seamNode=seam;self.content.addChildNode(seam)
                    self.bodyNode?.isHidden = !self.configuration.showMannequin;seam.isHidden = !self.configuration.showSeams
                    self.updateCamera(self.view?.bounds.size ?? .zero);issue.wrappedValue=nil
                } catch is CancellationError {} catch {
                    guard let self,self.identity==id,!Task.isCancelled else{return}
                    self.content.childNodes.forEach{$0.removeFromParentNode()}
                    issue.wrappedValue="三维显示失败：\(error.localizedDescription)"
                }
            }
        }
        func updateCamera(_ size:CGSize) {
            guard size.width>0,size.height>0,let bounds=garmentBounds,
                  let f=try? GarmentCodeDrapeFraming.frame(garment:bounds,mannequin:bodyBounds,configuration:configuration,width:Double(size.width),height:Double(size.height)) else{return}
            // Subtract xyz centre BEFORE rotation; all complete source pieces
            // and the avatar retain exactly the same relative coordinates.
            for node in content.childNodes {node.simdPosition = -SIMD3(Float(f.center.x),Float(f.center.y),Float(f.center.z))}
            camera.position=SCNVector3(0,0,Float(f.distance));camera.look(at:SCNVector3Zero)
            camera.camera?.fieldOfView=CGFloat(f.verticalFieldOfViewDegrees);camera.camera?.zNear=f.nearPlane;camera.camera?.zFar=f.farPlane
        }
        private func model(_ p:Mesh,color:UIColor)->SCNNode {
            let vertices=p.positions.map{SCNVector3($0.x,$0.y,$0.z)},normals=p.normals.map{SCNVector3($0.x,$0.y,$0.z)}
            let element=SCNGeometryElement(data:p.indices.withUnsafeBytes{Data($0)},primitiveType:.triangles,primitiveCount:p.indices.count/3,bytesPerIndex:4)
            let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[element])
            let material=SCNMaterial();material.lightingModel = .physicallyBased;material.diffuse.contents=color;material.roughness.contents=0.85;material.isDoubleSided=true
            geometry.materials=[material];return SCNNode(geometry:geometry)
        }
        private func lines(_ positions:[SIMD3<Float>],_ groups:[Int:[UInt32]])->SCNNode {
            let source=SCNGeometrySource(vertices:positions.map{SCNVector3($0.x,$0.y,$0.z)})
            let ids=groups.keys.sorted(),elements=ids.map {id in let a=groups[id]!;return SCNGeometryElement(data:a.withUnsafeBytes{Data($0)},primitiveType:.line,primitiveCount:a.count/2,bytesPerIndex:4)}
            let geometry=SCNGeometry(sources:[source],elements:elements)
            let palette:[UIColor]=[.init(red:0,green:0.45,blue:0.70,alpha:1),.init(red:0.80,green:0.28,blue:0,alpha:1),.init(red:0,green:0.49,blue:0.35,alpha:1),.init(red:0.53,green:0.28,blue:0.65,alpha:1),.init(red:0.70,green:0.09,blue:0.29,alpha:1),.init(red:0,green:0.47,blue:0.55,alpha:1),.init(red:0.49,green:0.35,blue:0,alpha:1),.init(red:0.22,green:0.30,blue:0.63,alpha:1)]
            geometry.materials=ids.map{id in let m=SCNMaterial();m.lightingModel = .constant;m.diffuse.contents=id<0 ? UIColor.orange:palette[id%palette.count];m.isDoubleSided=true;m.writesToDepthBuffer=false;return m}
            let node=SCNNode(geometry:geometry);node.renderingOrder=10;return node
        }
    }
    private final class LayoutSceneView:SCNView {
        var onLayout:(()->Void)?
        override func layoutSubviews(){super.layoutSubviews();onLayout?()}
    }
    private nonisolated struct Mesh:Sendable {let id:String,positions:[SIMD3<Float>],normals:[SIMD3<Float>],indices:[UInt32]}
    private nonisolated struct Payload:Sendable {
        let panels:[Mesh],body:Mesh?,clothPositions:[SIMD3<Float>],lines:[Int:[UInt32]]
        let garmentBounds:GarmentCodeDrapeFraming.Bounds,bodyBounds:GarmentCodeDrapeFraming.Bounds?
        static func prepare(_ o:GarmentCodeCircleDrape.Output,seamGroups:[Int]?)throws->Payload {
            try Task.checkCancellation()
            guard !o.positions.isEmpty,o.positions.count<=20_000,o.triangleIndices.count<=120_000,
                  o.mannequinPositions.count<=200_000,o.mannequinTriangleIndices.count<=1_200_000,
                  o.seamPaths.count<=8192,o.seamPaths.reduce(0,{$0+$1.count})<=100_000,
                  seamGroups==nil || seamGroups!.count==o.seamPaths.count else {throw GarmentCodeDrapeFraming.FramingError.invalid}
            let groups=o.validatedPanelGroups
            guard o.panelGroups==nil || groups != nil,(groups?.count ?? 1)<=128 else {throw GarmentCodeDrapeFraming.FramingError.invalid}
            let positions=try floats(o.positions),proxy=try floats(o.mannequinPositions)
            var panels:[Mesh]=[]
            if let groups {
                for g in groups {
                    try Task.checkCancellation();let map=Dictionary(uniqueKeysWithValues:g.vertexIDs.enumerated().map{($0.element,UInt32($0.offset))})
                    let indices=try g.triangleIDs.flatMap{face in try (0..<3).map{offset in guard let id=map[Int(o.triangleIndices[face*3+offset])] else {throw GarmentCodeDrapeFraming.FramingError.invalid};return id}}
                    panels.append(try mesh(g.panelID,g.vertexIDs.map{positions[$0]},indices))
                }
            } else {panels=[try mesh("garment",positions,o.triangleIndices)]}
            let body:Mesh?
            if proxy.isEmpty && o.mannequinTriangleIndices.isEmpty {body=nil}
            else {body=try mesh("mannequin",proxy,o.mannequinTriangleIndices)}
            var lines:[Int:[UInt32]]=[:]
            for (i,path) in o.seamPaths.enumerated() {
                try Task.checkCancellation();let group=seamGroups?[i] ?? -1
                guard group>=(-1),group<=8192,path.allSatisfy({positions.indices.contains($0)}) else {throw GarmentCodeDrapeFraming.FramingError.invalid}
                for (a,b) in zip(path,path.dropFirst()) where a != b {lines[group,default:[]] += [UInt32(a),UInt32(b)]}
            }
            let bounds=try GarmentCodeDrapeFraming.Bounds(points:o.positions.map{.init($0.x,$0.y,$0.z)})
            let bodyBounds=try proxy.isEmpty ? nil:GarmentCodeDrapeFraming.Bounds(points:o.mannequinPositions.map{.init($0.x,$0.y,$0.z)})
            try Task.checkCancellation();return .init(panels:panels,body:body,clothPositions:positions,lines:lines,garmentBounds:bounds,bodyBounds:bodyBounds)
        }
        private static func floats(_ points:[GarmentCodeCircleDrape.Vector3])throws->[SIMD3<Float>] {
            var out:[SIMD3<Float>]=[];out.reserveCapacity(points.count)
            for (i,p) in points.enumerated() {if i%128==0 {try Task.checkCancellation()};guard p.isFinite,max(abs(p.x),abs(p.y),abs(p.z))<=1e6 else {throw GarmentCodeDrapeFraming.FramingError.invalid};out.append(.init(Float(p.x),Float(p.y),Float(p.z)))}
            return out
        }
        private static func mesh(_ id:String,_ points:[SIMD3<Float>],_ indices:[UInt32])throws->Mesh {
            guard !points.isEmpty,!indices.isEmpty,indices.count%3==0 else {throw GarmentCodeDrapeFraming.FramingError.invalid}
            var normals=Array(repeating:SIMD3<Float>.zero,count:points.count)
            for t in stride(from:0,to:indices.count,by:3) {
                if t%384==0 {try Task.checkCancellation()}
                let a=Int(indices[t]),b=Int(indices[t+1]),c=Int(indices[t+2])
                guard points.indices.contains(a),points.indices.contains(b),points.indices.contains(c),a != b,b != c,c != a else {throw GarmentCodeDrapeFraming.FramingError.invalid}
                let n=simd_cross(points[b]-points[a],points[c]-points[a]);guard simd_length_squared(n)>0 else {throw GarmentCodeDrapeFraming.FramingError.invalid}
                normals[a]+=n;normals[b]+=n;normals[c]+=n
            }
            normals=normals.map{simd_length_squared($0)>0 ? simd_normalize($0):SIMD3(0,1,0)}
            return .init(id:id,positions:points,normals:normals,indices:indices)
        }
    }
}
#endif
