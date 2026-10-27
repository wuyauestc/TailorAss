import Foundation
import CryptoKit
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Source-bound reference measurements, not a body fitter or anatomical
/// landmark detector. Every original contour remains in each result.
nonisolated enum GarmentCodeBodyMeasurements {
    typealias B=GarmentCodeBodySections
    typealias V=B.V
    struct Limits:Sendable {
        var sections=B.Limits()
        var maximumMeasurements=8
        var maximumSelectorEdgeTests=1_000_000
        var boundaryToleranceMeters=1e-9
    }
    enum MeasurementError:LocalizedError,Sendable {
        case invalid(String),budget
        var errorDescription:String? {switch self {
        case let .invalid(s):return "人体参考测量无效："+s
        case .budget:return "人体参考测量超出预算。"
        }}
    }
    struct Axis:Codable,Sendable {
        let origin:V,direction:V
        init(origin:V,direction:V)throws {
            guard origin.isFinite,origin.length<100,direction.isFinite,
                  direction.length.isFinite,direction.length>1e-12 else {throw MeasurementError.invalid("参考轴无效。")}
            self.origin=origin;self.direction=direction/direction.length
        }
    }
    struct Request:Codable,Sendable {
        let id:String,formula:String,targetKey:String
        let plane:B.Plane,axis:Axis
        init(id:String,formula:String,targetKey:String,plane:B.Plane,axis:Axis)throws {
            guard !id.isEmpty,id.utf8.count<=128,!formula.isEmpty,formula.utf8.count<=1024,
                  targetKeys.contains(targetKey) else {throw MeasurementError.invalid("测量名称、公式或目标键无效。")}
            self.id=id;self.formula=formula;self.targetKey=targetKey;self.plane=plane;self.axis=axis
        }
    }
    struct Snapshot:Codable,Sendable {
        let geometrySHA256:String,parameterSHA256:String
        let positions:[V],triangleIndices:[UInt32],bodyValues:[String:Double]
        fileprivate init(section:B.Section,positions:[V],triangleIndices:[UInt32],bodyValues:[String:Double]) {
            geometrySHA256=section.bodyGeometrySHA256;parameterSHA256=parameterHash(bodyValues)
            self.positions=positions;self.triangleIndices=triangleIndices;self.bodyValues=bodyValues
        }
    }
    enum Issue:String,Codable,Sendable {
        case sectionIndeterminate,axisParallelOrUncertain,anchorOutOfBounds
        case anchorOnBoundaryOrUncertain,noContainingLoop,multipleContainingLoops,numericalSelectionUncertain
        case uncertifiedAnatomicalRegion
    }
    enum Status:String,Codable,Sendable {case measuredReference,unsupported}
    struct Statistics:Codable,Sendable {let edgeTests:Int,directionAttempts:Int}
    struct Measurement:Codable,Sendable {
        let request:Request,section:B.Section,status:Status,issue:Issue?
        let anchor:V?,selectedLoopIndex:Int?,observedMeters:Double?,requestedMeters:Double
        /// Only the named reference geometry is compared. It is never a
        /// certified natural-waist/fullest-chest/fullest-hip fit error.
        let observedMinusRequestedMeters:Double?
        let anatomicalComparisonStatus:Status,anatomicalComparisonIssue:Issue
        let statistics:Statistics
    }
    struct Height:Codable,Sendable {
        let minimumY:Double,maximumY:Double,observedMeters:Double,requestedMeters:Double
        let observedMinusRequestedMeters:Double
        let definition:String
    }
    struct Report:Codable,Sendable {
        let source:Snapshot,height:Height,measurements:[Measurement]
        let bodyFittingApplied:Bool,anatomicalDefinitionsEstablished:Bool
    }
    struct Prepared:Sendable {
        let source:Snapshot,height:Height
        private let limits:Limits,waistSection:B.Section
        init(positions:[V],triangleIndices:[UInt32],bodyValues:[String:Double],limits:Limits = .init(),
             isCancelled:@Sendable()->Bool={false})throws {
            if isCancelled(){throw CancellationError()}
            guard nearestRounding else {throw MeasurementError.invalid("不支持当前浮点舍入环境。")}
            guard (1...16).contains(limits.maximumMeasurements),(1...8_000_000).contains(limits.maximumSelectorEdgeTests),
                  limits.boundaryToleranceMeters.isFinite,(0...1e-6).contains(limits.boundaryToleranceMeters) else {throw MeasurementError.invalid("预算或边界带无效。")}
            try validateValues(bodyValues)
            // Reuse the existing closed, oriented topology validation and
            // identical geometry SHA. An indeterminate plane is retained;
            // it does not mean the source topology failed or may be repaired.
            let plane=try B.Plane(origin:.zero,normal:V(x:0,y:1,z:0))
            let s=try B.slice(positions:positions,triangleIndices:triangleIndices,plane:plane,limits:limits.sections,isCancelled:isCancelled)
            let minimum=positions.map(\.y).min()!,maximum=positions.map(\.y).max()!,requested=bodyValues["height"]!/100
            guard maximum>minimum else {throw MeasurementError.invalid("可见网格没有竖直高度。")}
            if isCancelled(){throw CancellationError()}
            source=Snapshot(section:s,positions:positions,triangleIndices:triangleIndices,bodyValues:bodyValues)
            height = .init(minimumY:minimum,maximumY:maximum,observedMeters:maximum-minimum,requestedMeters:requested,
                observedMinusRequestedMeters:maximum-minimum-requested,definition:"Actual visible mesh +Y extent; no anatomical endpoint detector")
            self.limits=limits;waistSection=s
        }
        func referenceRequests()throws->[Request] {
            let values=source.bodyValues,axis=try Axis(origin:.zero,direction:V(x:0,y:1,z:0))
            func request(_ id:String,_ key:String,_ y:Double,_ formula:String)throws->Request {
                try .init(id:id,formula:formula,targetKey:key,
                    plane:.init(origin:V(x:0,y:y,z:0),normal:V(x:0,y:1,z:0)),axis:axis)
            }
            return [try request("waist-reference","waist",0,"y = 0; declared template waist reference"),
                try request("hips-reference","hips",-values["hips_line"]!/100,"y = -hips_line / 100"),
                try request("chest-vertical-reference","bust",(values["waist_line"]!-values["vert_bust_line"]!)/100,
                    "y = (waist_line - vert_bust_line) / 100; pure vertical construction reference, not blended _bust_line or detected fullest chest")]
        }
        func referenceReport(isCancelled:@Sendable()->Bool={false})throws->Report {
            try report(requests:referenceRequests(),isCancelled:isCancelled)
        }
        func report(requests:[Request],isCancelled:@Sendable()->Bool={false})throws->Report {
            if isCancelled(){throw CancellationError()}
            guard nearestRounding else {throw MeasurementError.invalid("不支持当前浮点舍入环境。")}
            guard !requests.isEmpty,requests.count<=limits.maximumMeasurements,Set(requests.map(\.id)).count==requests.count else {throw MeasurementError.budget}
            for r in requests {
                guard !r.id.isEmpty,r.id.utf8.count<=128,!r.formula.isEmpty,r.formula.utf8.count<=1024,targetKeys.contains(r.targetKey),
                      r.axis.origin.isFinite,r.axis.origin.length<100,r.axis.direction.isFinite,abs(r.axis.direction.length-1)<1e-12,
                      r.plane.origin.isFinite,r.plane.origin.length<100,r.plane.unitNormal.isFinite,abs(r.plane.unitNormal.length-1)<1e-12 else {
                    throw MeasurementError.invalid("解码后的测量请求无效。")
                }
            }
            var used=0,measurements:[Measurement]=[]
            for request in requests {
                if isCancelled(){throw CancellationError()}
                measurements.append(try measure(request,used:&used,isCancelled:isCancelled))
            }
            if isCancelled(){throw CancellationError()}
            return .init(source:source,height:height,measurements:measurements,bodyFittingApplied:false,anatomicalDefinitionsEstablished:false)
        }
        private func measure(_ request:Request,used:inout Int,isCancelled:@Sendable()->Bool)throws->Measurement {
            let s:B.Section
            if request.plane.origin == .zero && request.plane.unitNormal == V(x:0,y:1,z:0) {s=waistSection}
            else {s=try B.slice(positions:source.positions,triangleIndices:source.triangleIndices,plane:request.plane,
                limits:limits.sections,isCancelled:isCancelled)}
            guard s.bodyGeometrySHA256==source.geometrySHA256 else {throw MeasurementError.invalid("截面来源不同。")}
            let initial=used,target=source.bodyValues[request.targetKey]!/100
            var attempts=0
            func result(_ issue:Issue?,_ anchor:V?=nil,_ selected:Int?=nil)->Measurement {
                let value=selected.map{s.loops[$0].perimeterMeters}
                return .init(request:request,section:s,status:issue==nil ? .measuredReference:.unsupported,issue:issue,
                    anchor:anchor,selectedLoopIndex:selected,observedMeters:value,requestedMeters:target,
                    observedMinusRequestedMeters:value.map{$0-target},anatomicalComparisonStatus:.unsupported,
                    anatomicalComparisonIssue:.uncertifiedAnatomicalRegion,statistics:.init(edgeTests:used-initial,directionAttempts:attempts))
            }
            guard s.status == .complete else {return result(.sectionIndeterminate)}
            let denominator=dotI(request.axis.direction,request.plane.unitNormal)
            guard denominator.finite,!denominator.containsZero else {return result(.axisParallelOrUncertain)}
            let numerator=(0..<3).reduce(I(0)){value,i in
                value+(I(coordinate(request.plane.origin,i))-I(coordinate(request.axis.origin,i)))*I(coordinate(request.plane.unitNormal,i))
            }
            let time=numerator/denominator
            let anchorI=(0..<3).map{I(coordinate(request.axis.origin,$0))+I(coordinate(request.axis.direction,$0))*time}
            guard anchorI.allSatisfy(\.finite) else {return result(.anchorOutOfBounds)}
            let nominal=dot(request.plane.origin-request.axis.origin,request.plane.unitNormal)/dot(request.axis.direction,request.plane.unitNormal)
            let anchor=request.axis.origin+request.axis.direction*nominal
            guard anchor.isFinite,anchor.length<100 else {return result(.anchorOutOfBounds)}
            guard (0..<3).allSatisfy({anchorI[$0].lo<=coordinate(anchor,$0) && coordinate(anchor,$0)<=anchorI[$0].hi}) else {
                return result(.numericalSelectionUncertain,anchor)
            }
            let n=request.plane.unitNormal,drop=[abs(n.x),abs(n.y),abs(n.z)].enumerated().max{$0.element<$1.element}!.offset
            let first=(drop+1)%3,second=(drop+2)%3
            var containing:[Int]=[]
            for (index,loop) in s.loops.enumerated() {
                var classification:Containment = .uncertain
                // Alternative exact linear projection axes only resolve ray
                // vertex ties, never move the anchor/plane or the source ring.
                for (a,b) in [(1.0,0.0),(0,1),(1,1),(1,-1),(1,2),(2,1),(1,3),(3,1)] {
                    attempts+=1
                    classification=try contains(loop,anchor:anchorI,first:first,second:second,a:a,b:b,
                        tolerance:limits.boundaryToleranceMeters,used:&used,maximum:limits.maximumSelectorEdgeTests,isCancelled:isCancelled)
                    if classification != .uncertain {break}
                }
                switch classification {
                case .inside:containing.append(index)
                case .outside:break
                case .boundary:return result(.anchorOnBoundaryOrUncertain,anchor)
                case .uncertain:return result(.numericalSelectionUncertain,anchor)
                }
            }
            if isCancelled(){throw CancellationError()}
            guard containing.count==1 else {return result(containing.isEmpty ? .noContainingLoop:.multipleContainingLoops,anchor)}
            return result(nil,anchor,containing[0])
        }
    }
    private static let rawKeys:Set<String>=["arm_length","arm_pose_angle","armscye_depth","back_width","bum_points","bust","bust_line","bust_points","crotch_hip_diff","head_l","height","hip_back_width","hip_inclination","hips","hips_line","leg_circ","neck_w","shoulder_incl","shoulder_w","underbust","vert_bust_line","waist","waist_back_width","waist_line","waist_over_bust_line","wrist"]
    private static let targetKeys:Set<String>=["waist","hips","bust"]
    private static var nearestRounding:Bool {
        #if os(macOS)
        return fegetround()==FE_TONEAREST
        #elseif canImport(NativeClothCollision)
        return FloatingPointEnvironment.isNearestRounding
        #else
        return false
        #endif
    }
    private static func validateValues(_ v:[String:Double])throws {
        let derived:Set<String>=["_waist_level","_leg_length","_base_sleeve_balance","_bust_line","_hip_inclination","_shoulder_incl","_armscye_depth"]
        guard Set(v.keys)==rawKeys.union(derived),v.values.allSatisfy(\.isFinite) else {throw MeasurementError.invalid("需要原26项及7项派生值，不能补默认或丢弃未知键。")}
        guard ["height","bust","waist","hips"].allSatisfy({v[$0]!>0}) else {
            throw MeasurementError.invalid("身高及本模块比较的胸、腰、臀围目标必须为正。")
        }
        let waist=v["height"]!-v["head_l"]!-v["waist_line"]!
        let expected=["_waist_level":waist,"_leg_length":waist-v["hips_line"]!,"_base_sleeve_balance":v["shoulder_w"]!-2,
            "_bust_line":(2.0/3)*v["vert_bust_line"]!+(1.0/3)*v["bust_line"]!,"_hip_inclination":v["hip_inclination"]!/2,
            "_shoulder_incl":v["shoulder_incl"]!,"_armscye_depth":v["armscye_depth"]!+2.5]
        guard expected.allSatisfy({v[$0.key]!.bitPattern==$0.value.bitPattern}) else {throw MeasurementError.invalid("派生值与原值不一致。")}
    }
    private static func parameterHash(_ values:[String:Double])->String {
        var data=Data("body-reference-measurements-parameters-v1\0".utf8)
        for key in values.keys.sorted() {
            data.append(contentsOf:key.utf8);data.append(0)
            var bits=values[key]!.bitPattern.littleEndian;withUnsafeBytes(of:&bits){data.append(contentsOf:$0)}
        }
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    private static func coordinate(_ p:V,_ i:Int)->Double {i==0 ? p.x:(i==1 ? p.y:p.z)}
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func dotI(_ a:V,_ b:V)->I {I(a.x)*I(b.x)+I(a.y)*I(b.y)+I(a.z)*I(b.z)}
    private enum Containment {case inside,outside,boundary,uncertain}
    private struct P {let x:I,y:I}
    private static func contains(_ loop:B.Loop,anchor:[I],first:Int,second:Int,a:Double,b:Double,tolerance:Double,
        used:inout Int,maximum:Int,isCancelled:@Sendable()->Bool)throws->Containment {
        func project(_ x:I,_ y:I)->P {.init(x:I(a)*x+I(b)*y,y:I(-b)*x+I(a)*y)}
        let p=project(anchor[first],anchor[second]),vertices=loop.vertices.map{project(I(coordinate($0.position,first)),I(coordinate($0.position,second)))}
        var winding=0
        for i in vertices.indices {
            if used>=maximum {throw MeasurementError.budget};used+=1
            if used%64==0,isCancelled(){throw CancellationError()}
            let u=vertices[i],v=vertices[(i+1)%vertices.count]
            let dx=v.x-u.x,dy=v.y-u.y,orient=dx*(p.y-u.y)-dy*(p.x-u.x)
            guard orient.finite else {return .uncertain}
            let length=hypot(max(abs(dx.lo),abs(dx.hi)),max(abs(dy.lo),abs(dy.hi))).nextUp
            let band=(tolerance*hypot(a,b).nextUp*length).nextUp
            guard band.isFinite else {return .uncertain}
            let padding=(tolerance*hypot(a,b).nextUp).nextUp
            let box=p.x.hi>=(min(u.x.lo,v.x.lo)-padding).nextDown && p.x.lo<=(max(u.x.hi,v.x.hi)+padding).nextUp &&
                p.y.hi>=(min(u.y.lo,v.y.lo)-padding).nextDown && p.y.lo<=(max(u.y.hi,v.y.hi)+padding).nextUp
            if box && orient.lo<=band && orient.hi>=(-band) {return .boundary}
            let uBelow=u.y.hi<=p.y.lo,vBelow=v.y.hi<=p.y.lo,uAbove=u.y.lo>p.y.hi,vAbove=v.y.lo>p.y.hi
            guard (uBelow || uAbove) && (vBelow || vAbove) else {return .uncertain}
            if uBelow && vAbove {if orient.lo>0{winding+=1}else if orient.hi>=0{return .uncertain}}
            if uAbove && vBelow {if orient.hi<0{winding-=1}else if orient.lo<=0{return .uncertain}}
        }
        guard abs(winding)<=1 else {return .uncertain}
        return winding==0 ? .outside:.inside
    }
    /// Outward basic arithmetic on the actual binary input. Zero/unit fast
    /// paths are exact and preserve legitimate ray ties at a zero coordinate.
    private struct I {
        let lo:Double,hi:Double
        init(_ x:Double){lo=x;hi=x}
        init(_ l:Double,_ h:Double){lo=l;hi=h}
        var finite:Bool {lo.isFinite && hi.isFinite && lo<=hi}
        var containsZero:Bool {lo<=0 && hi>=0}
        var zero:Bool {lo==0 && hi==0}
        static func +(a:I,b:I)->I {if a.zero{return b};if b.zero{return a};return I((a.lo+b.lo).nextDown,(a.hi+b.hi).nextUp)}
        static func -(a:I,b:I)->I {if b.zero{return a};if a.lo==a.hi && b.lo==b.hi && a.lo==b.lo{return I(0)};return I((a.lo-b.hi).nextDown,(a.hi-b.lo).nextUp)}
        static func *(a:I,b:I)->I {
            if a.zero || b.zero{return I(0)}
            if a.lo==1 && a.hi==1{return b};if b.lo==1 && b.hi==1{return a}
            if a.lo == -1 && a.hi == -1{return I(-b.hi,-b.lo)};if b.lo == -1 && b.hi == -1{return I(-a.hi,-a.lo)}
            let p=[a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi];return I(p.min()!.nextDown,p.max()!.nextUp)
        }
        static func /(a:I,b:I)->I {
            if b.containsZero{return I(-.infinity,.infinity)}
            return a*I((1/b.hi).nextDown,(1/b.lo).nextUp)
        }
    }
}
