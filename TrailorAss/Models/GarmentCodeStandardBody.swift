import Foundation

/// The visible anatomical mesh and collision field come from the same CC0
/// MakeHuman surface. Dimensional fitting is not personal body reconstruction.
enum GarmentCodeStandardBody {
    typealias Vector3 = GarmentCodeCircleDrape.Vector3

    nonisolated struct Snapshot: Sendable {
        let positions: [Vector3]
        let triangleIndices: [UInt32]
        let profileName: String
        let waistCircumferenceMeters: Double
        let hipsCircumferenceMeters: Double
        let gridSpacingMeters: Double
        private let waistPath: [Vector3]
        private let waistLengths: [Double]
        private let grid: [Float]
        private let dimensions: [Int]
        private let origin: Vector3
        private let spacing: Double
        private let waistScale: Double
        private let hipsScale: Double
        private let hipScaleY: Double
        private let lowerScaleY: Double
        private let upperScaleY: Double
        private let baselineHipLine: Double

        fileprivate init(asset: Asset, values: [Float], bodyValues: [String: Double]) throws {
            guard let height=bodyValues["height"],let waist=bodyValues["waist"],let hips=bodyValues["hips"],
                  let hipLine=bodyValues["hips_line"],let waistLevel=bodyValues["_waist_level"],
                  [height,waist,hips,hipLine,waistLevel].allSatisfy({$0.isFinite && $0>0}),
                  waistLevel>hipLine, height>waistLevel,
                  let baseHeight=asset.baseline["height"], let baseWaist=asset.baseline["waist"],
                  let baseHips=asset.baseline["hips"],let baseHipLine=asset.baseline["hipLine"],
                  let baseWaistLevel=asset.baseline["waistLevel"] else {throw BodyError.invalid("标准人台需要完整、有效的身高、腰围、臀围、腰臀高与腰线高度。")}
            let ws=waist/100/baseWaist,hs=hips/100/baseHips
            let hy=hipLine/100/baseHipLine
            let ly=(waistLevel-hipLine)/100/(baseWaistLevel-baseHipLine)
            let uy=(height-waistLevel)/100/(baseHeight-baseWaistLevel)
            guard [ws,hs,hy,ly,uy].allSatisfy({(0.5...1.8).contains($0)}) else {
                throw BodyError.invalid("量体数据超出当前标准人台的有限尺寸拟合范围，不能可靠构造碰撞体。")
            }
            func transform(_ p:[Double])->Vector3 {
                let y=p[1],t=max(0,min(1,(y+baseHipLine)/baseHipLine)),blend=t*t*(3-2*t)
                let h=hs+(ws-hs)*blend
                let yy=y>=0 ? y*uy : (y>=(-baseHipLine) ? y*hy : -baseHipLine*hy+(y+baseHipLine)*ly)
                return .init(x:p[0]*h,y:yy,z:p[2]*h)
            }
            positions=asset.positions.map(transform)
            triangleIndices=asset.triangleIndices
            profileName="MakeHuman CC0 标准人台（有限尺寸拟合）"
            waistCircumferenceMeters=waist/100;hipsCircumferenceMeters=hips/100
            gridSpacingMeters=asset.collisionGrid.spacing*max(ws,hs,hy,ly,uy)
            waistPath=asset.waistPath.map(transform)
            var lengths=[0.0]
            for i in waistPath.indices {lengths.append(lengths.last!+(waistPath[(i+1)%waistPath.count]-waistPath[i]).length)}
            waistLengths=lengths
            grid=values;dimensions=asset.collisionGrid.dimensions
            origin = .init(x:asset.collisionGrid.origin[0],y:asset.collisionGrid.origin[1],z:asset.collisionGrid.origin[2])
            spacing=asset.collisionGrid.spacing
            waistScale=ws;hipsScale=hs;hipScaleY=hy;lowerScaleY=ly;upperScaleY=uy;baselineHipLine=baseHipLine
        }

        /// Equal arc-length sampling of the actual mesh's waist contour.
        func waistPoint(arcFraction: Double) -> Vector3 {
            let fraction=arcFraction-floor(arcFraction),target=fraction*waistLengths.last!
            var low=0,high=waistPath.count
            while high-low>1 {let mid=(low+high)/2;if waistLengths[mid]<target{low=mid}else{high=mid}}
            let t=(target-waistLengths[low])/max(1e-12,waistLengths[low+1]-waistLengths[low])
            return waistPath[low]*(1-t)+waistPath[(low+1)%waistPath.count]*t
        }

        /// Signed distance estimate from the body's one-centimetre triangle SDF.
        /// Coverage includes the full visible body, from feet through the head
        /// and outstretched hands. The lower grid samples retain their original
        /// bit patterns; extending coverage does not alter the body geometry.
        /// It does not claim continuous collision or exact personal geometry.
        func signedDistance(_ point: Vector3) -> Double? {contact(point)?.distance}
        func penetration(_ point: Vector3) -> Double {max(0,-(signedDistance(point) ?? 0))}

        func project(_ point: Vector3, thickness: Double) -> Vector3 {
            var p=point
            for _ in 0..<3 {
                guard let c=contact(p),c.distance<thickness else {break}
                // Bounded projection prevents a bad initial point jumping
                // through a limb; diagnostics retain any unresolved penetration.
                p=p+c.normal*min(0.04,thickness-c.distance)
            }
            return p
        }

        private func contact(_ p:Vector3)->(distance:Double,normal:Vector3)? {
            guard p.isFinite else{return nil}
            let canonicalY:Double,verticalScale:Double
            if p.y>=0 {canonicalY=p.y/upperScaleY;verticalScale=upperScaleY}
            else if p.y>=(-baselineHipLine*hipScaleY) {canonicalY=p.y/hipScaleY;verticalScale=hipScaleY}
            else {canonicalY = -baselineHipLine+(p.y+baselineHipLine*hipScaleY)/lowerScaleY;verticalScale=lowerScaleY}
            let t=max(0,min(1,(canonicalY+baselineHipLine)/baselineHipLine))
            let h=hipsScale+(waistScale-hipsScale)*t*t*(3-2*t)
            let derivative=(canonicalY>(-baselineHipLine) && canonicalY<0) ? (waistScale-hipsScale)*6*t*(1-t)/baselineHipLine : 0
            let q=Vector3(x:p.x/h,y:canonicalY,z:p.z/h)
            let sx=(q.x-origin.x)/spacing,sy=(q.y-origin.y)/spacing,sz=(q.z-origin.z)/spacing
            guard sx>=0,sy>=0,sz>=0,sx<Double(dimensions[0]-1),sy<Double(dimensions[1]-1),sz<Double(dimensions[2]-1) else{return nil}
            let ix=Int(sx),iy=Int(sy),iz=Int(sz),fx=sx-Double(ix),fy=sy-Double(iy),fz=sz-Double(iz)
            let nx=dimensions[0],ny=dimensions[1]
            func value(_ x:Int,_ y:Int,_ z:Int)->Double {Double(grid[((iz+z)*ny+iy+y)*nx+ix+x])}
            let a=value(0,0,0),b=value(1,0,0),c=value(0,1,0),d=value(1,1,0)
            let e=value(0,0,1),f=value(1,0,1),g=value(0,1,1),j=value(1,1,1)
            let ab=a*(1-fx)+b*fx,cd=c*(1-fx)+d*fx,ef=e*(1-fx)+f*fx,gj=g*(1-fx)+j*fx
            let lower=ab*(1-fy)+cd*fy,upper=ef*(1-fy)+gj*fy
            let distance=lower*(1-fz)+upper*fz
            let gx=(((b-a)*(1-fy)+(d-c)*fy)*(1-fz)+((f-e)*(1-fy)+(j-g)*fy)*fz)/spacing
            let gy=((cd-ab)*(1-fz)+(gj-ef)*fz)/spacing
            let gz=(upper-lower)/spacing
            let gradient=Vector3(x:gx/h,y:(gy-gx*q.x*derivative/h-gz*q.z*derivative/h)/verticalScale,z:gz/h)
            let magnitude=gradient.length
            // A medial-axis/flat-grid gradient cannot erase a valid negative
            // sample. Keep penetration observable; zero normal deliberately
            // leaves an unresolved contact for the quality gate to reject.
            guard magnitude>1e-8,magnitude.isFinite else{
                return (distance*min(h,verticalScale),.zero)
            }
            return (distance/magnitude,gradient/magnitude)
        }
    }

    nonisolated fileprivate struct Asset: Decodable {
        struct Grid:Decodable {let origin:[Double];let spacing:Double;let dimensions:[Int];let filename:String}
        let format:String
        let baseline:[String:Double]
        let positions:[[Double]]
        let triangleIndices:[UInt32]
        let waistPath:[[Double]]
        let collisionGrid:Grid
    }
    nonisolated enum BodyError:LocalizedError {
        case invalid(String)
        var errorDescription:String? {if case let .invalid(message)=self{return message};return nil}
    }
    private static var cached:(URL,Asset,[Float])?

    static func load(body:GarmentCodeBodyParameters,resourceDirectory:URL?=nil)throws->Snapshot {
        let url:URL
        if let directory=resourceDirectory {url=directory.appendingPathComponent("GarmentCodeStandardBody.json")}
        else if let bundled=Bundle.main.url(forResource:"GarmentCodeStandardBody",withExtension:"json"){url=bundled}
        else {throw BodyError.invalid("标准人台资源缺失，请重新构建 App。")}
        if let (path,asset,grid)=cached,path==url {return try Snapshot(asset:asset,values:grid,bodyValues:body.values)}
        let asset=try JSONDecoder().decode(Asset.self,from:Data(contentsOf:url))
        let cfg=asset.collisionGrid
        guard asset.format=="tailorass-standard-body-v1",cfg.dimensions.count==3,cfg.origin.count==3,
              cfg.dimensions.allSatisfy({(2...256).contains($0)}),cfg.spacing.isFinite,cfg.spacing>0,
              asset.positions.allSatisfy({$0.count==3 && $0.allSatisfy(\.isFinite)}),
              !asset.positions.isEmpty,asset.triangleIndices.count%3==0,
              asset.triangleIndices.allSatisfy({Int($0)<asset.positions.count}),
              asset.waistPath.count>10,asset.waistPath.allSatisfy({$0.count==3 && $0.allSatisfy(\.isFinite)}) else {throw BodyError.invalid("标准人台资源格式不正确。")}
        let data=try Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent(cfg.filename))
        let count=cfg.dimensions.reduce(1,*)
        guard data.count==count*4 else {throw BodyError.invalid("标准人台碰撞场不完整。")}
        let grid:[Float]=data.withUnsafeBytes { raw in
            (0..<count).map {Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))}
        }
        guard grid.allSatisfy(\.isFinite) else {throw BodyError.invalid("标准人台碰撞场包含无效数值。")}
        cached=(url,asset,grid)
        return try Snapshot(asset:asset,values:grid,bodyValues:body.values)
    }
}
