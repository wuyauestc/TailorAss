import Foundation
import CryptoKit
#if os(macOS)
import Darwin
#elseif canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// Complete STATIC closed-triangle intersection audit of the supplied mesh.
/// It grants no SDF, anatomical, orientation, closure or swept-motion claim.
/// A shared source vertex/edge exempts only that simplex, never a whole pair.
nonisolated enum GarmentCodeBodySurfaceValidator {
    typealias V=GarmentCodeCircleDrape.Vector3
    struct Limits:Sendable {
        var maximumVertices=100_000
        var maximumTriangles=200_000
        var maximumCandidatePairs=500_000
        var maximumBVHWork=10_000_000
        var maximumPredicates=10_000_000
        var maximumExactWordOperations=50_000_000
        var maximumExactWords=512
        var maximumEstimatedWorkingBytes=128*1024*1024
    }
    struct Report:Codable,Sendable {
        let geometrySHA256:String,vertices:Int,triangles:Int
        let completedAllPairs:Bool,candidateTrianglePairs:Int,separatedPairs:Int,expectedTopologicalTouchPairs:Int
        let bvhNodes:Int,bvhWork:Int,predicates:Int,exactPredicates:Int,exactWordOperations:Int,maximumExactWords:Int
        let maximumEstimatedWorkingBytes:Int
        let staticSurfaceOnly:Bool
    }
    enum ValidationError:LocalizedError,Sendable {
        case invalidInput(String),budget(String),unsupportedRounding,degenerateTriangle(Int)
        case intersection(Int,Int,String),foreignGeometry
        var errorDescription:String? {
            switch self {
            case let .invalidInput(s):return "人体表面验证输入无效："+s
            case let .budget(s):return "人体完整表面验证超出预算："+s
            case .unsupportedRounding:return "人体表面精确验证要求最近舍入环境。"
            case let .degenerateTriangle(i):return "人体表面含精确退化三角面 \(i)。"
            case let .intersection(a,b,s):return "人体面 \(a)／\(b) 存在非拓扑接触或重叠："+s
            case .foreignGeometry:return "人体表面凭证未绑定当前完整顶点／三角面。"
            }
        }
    }
    /// Immutable actual-geometry capability; Codable reports are data only.
    struct Certificate:Sendable {
        let geometrySHA256:String,report:Report
        private let positions:[V],indices:[UInt32]
        fileprivate init(_ p:[V],_ ids:[UInt32],_ report:Report) {
            positions=p;indices=ids;self.report=report;geometrySHA256=report.geometrySHA256
        }
        func verify(positions:[V],triangleIndices:[UInt32],isCancelled:@Sendable()->Bool={false})throws {
            try checkpoint(isCancelled)
            guard triangleIndices==indices,positions.count==self.positions.count else {throw ValidationError.foreignGeometry}
            for i in positions.indices {
                if i%128==0 {try checkpoint(isCancelled)}
                let a=positions[i],b=self.positions[i]
                guard a.x.bitPattern==b.x.bitPattern,a.y.bitPattern==b.y.bitPattern,a.z.bitPattern==b.z.bitPattern else {throw ValidationError.foreignGeometry}
            }
            try checkpoint(isCancelled)
        }
    }
    static func validate(positions:[V],triangleIndices:[UInt32],limits:Limits=Limits(),
                         isCancelled:@escaping @Sendable()->Bool={false})throws->Certificate {
        try checkpoint(isCancelled)
        let worker=try Worker(positions,triangleIndices,limits,isCancelled)
        let report=try worker.audit()
        try checkpoint(isCancelled)
        return Certificate(positions,triangleIndices,report)
    }
    private static func checkpoint(_ cancelled:@Sendable()->Bool)throws {
        if cancelled(){throw CancellationError()}
        #if os(macOS)
        guard fegetround()==FE_TONEAREST else {throw ValidationError.unsupportedRounding}
        #elseif canImport(NativeClothCollision)
        guard FloatingPointEnvironment.isNearestRounding else {throw ValidationError.unsupportedRounding}
        #else
        throw ValidationError.unsupportedRounding
        #endif
    }
    private static func coordinate(_ p:V,_ axis:Int)->Double {axis==0 ? p.x:(axis==1 ? p.y:p.z)}
    private static func hash(_ p:[V],_ ids:[UInt32])->String {
        var d=Data("rigid-clearance-visible-body-v1\0".utf8)
        func append<T:FixedWidthInteger>(_ x:T) {var x=x.littleEndian;withUnsafeBytes(of:&x){d.append(contentsOf:$0)}}
        append(UInt64(p.count));append(UInt64(ids.count))
        for v in p {append(v.x.bitPattern);append(v.y.bitPattern);append(v.z.bitPattern)}
        for id in ids {append(id)}
        return SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()
    }
    private struct Box {
        let lo:V,hi:V
        init(_ a:V,_ b:V,_ c:V) {
            lo = .init(x:min(a.x,b.x,c.x),y:min(a.y,b.y,c.y),z:min(a.z,b.z,c.z))
            hi = .init(x:max(a.x,b.x,c.x),y:max(a.y,b.y,c.y),z:max(a.z,b.z,c.z))
        }
        init(lo:V,hi:V){self.lo=lo;self.hi=hi}
        func union(_ b:Self)->Self {.init(lo:.init(x:min(lo.x,b.lo.x),y:min(lo.y,b.lo.y),z:min(lo.z,b.lo.z)),hi:.init(x:max(hi.x,b.hi.x),y:max(hi.y,b.hi.y),z:max(hi.z,b.hi.z)))}
        func overlaps(_ b:Self)->Bool {lo.x<=b.hi.x && hi.x>=b.lo.x && lo.y<=b.hi.y && hi.y>=b.lo.y && lo.z<=b.hi.z && hi.z>=b.lo.z}
    }
    private struct Face {let ids:[Int],box:Box,projection:Int}
    private struct Node {let box:Box,left:Int,right:Int,start:Int,count:Int}
    /// Outward intervals are a sign FAST PATH only. A zero/overflow/underflow
    /// enclosure falls back to the exact integer determinant of binary inputs.
    private struct I {
        let lo:Double,hi:Double
        init(_ x:Double){lo=x;hi=x}
        init(_ l:Double,_ h:Double){lo=l;hi=h}
        var valid:Bool {lo.isFinite && hi.isFinite && lo<=hi}
        var sign:Int? {guard valid else{return nil};return lo>0 ? 1:(hi<0 ? -1:nil)}
        static func - (a:Self,b:Self)->Self {guard a.valid,b.valid else{return .init(.nan,.nan)};return .init((a.lo-b.hi).nextDown,(a.hi-b.lo).nextUp)}
        static func + (a:Self,b:Self)->Self {guard a.valid,b.valid else{return .init(.nan,.nan)};return .init((a.lo+b.lo).nextDown,(a.hi+b.hi).nextUp)}
        static func * (a:Self,b:Self)->Self {
            guard a.valid,b.valid else{return .init(.nan,.nan)}
            let p=[a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi]
            guard p.allSatisfy(\.isFinite) else{return .init(.nan,.nan)}
            return .init(p.min()!.nextDown,p.max()!.nextUp)
        }
    }
    /// Signed magnitude, base2^32. All coordinates have one common power-of-two
    /// denominator. No rational intersection coordinates or floating epsilons
    /// are needed by the determinant/closed-set tests below.
    private struct Z {var sign:Int,words:[UInt32]}
    private final class Worker {
        let p:[V],ids:[UInt32],limits:Limits,cancel:@Sendable()->Bool
        var exact:[[Z]]=[],faces:[Face]=[],nodes:[Node]=[],order:[Int]=[]
        var bvhWork=0,predicates=0,exactPredicates=0,wordOps=0,maxWords=0,estimatedBytes=0
        init(_ p:[V],_ ids:[UInt32],_ limits:Limits,_ cancel:@escaping @Sendable()->Bool)throws {
            self.p=p;self.ids=ids;self.limits=limits;self.cancel=cancel
            guard (1...100_000).contains(limits.maximumVertices),(1...200_000).contains(limits.maximumTriangles),
                  (1...5_000_000).contains(limits.maximumCandidatePairs),(1...50_000_000).contains(limits.maximumBVHWork),
                  (1...50_000_000).contains(limits.maximumPredicates),(1...250_000_000).contains(limits.maximumExactWordOperations),
                  (8...1024).contains(limits.maximumExactWords),(1...256*1024*1024).contains(limits.maximumEstimatedWorkingBytes) else {throw ValidationError.invalidInput("工作预算范围无效。")}
            guard !p.isEmpty,!ids.isEmpty,ids.count%3==0 else {throw ValidationError.invalidInput("需要完整三角面索引。")}
            guard p.count<=limits.maximumVertices,ids.count/3<=limits.maximumTriangles else {throw ValidationError.budget("源网格数量")}
            var exponent=Int.max,largest=Int.min
            for (i,v) in p.enumerated() {
                if i%128==0 {try checkpoint(cancel)}
                guard v.isFinite else {throw ValidationError.invalidInput("顶点必须有限。")}
                for a in [v.x,v.y,v.z] where a != 0 {
                    let raw=Int((a.bitPattern>>52)&0x7ff),e=raw==0 ? -1074:raw-1023-52
                    exponent=min(exponent,e);largest=max(largest,e)
                }
            }
            guard exponent != Int.max else {throw ValidationError.invalidInput("全部顶点重合。")}
            let coordinateWords=(largest-exponent+53+31)/32+1
            // Conservative Swift-array/index/sort-path plus bounded exact
            // arithmetic scratch estimate, not an RSS claim or unlimited cache.
            estimatedBytes=p.count*(3*(96+4*coordinateWords)+24)+(ids.count/3)*640+limits.maximumExactWords*4*128
            guard estimatedBytes<=limits.maximumEstimatedWorkingBytes else {throw ValidationError.budget("完整源／BVH／精确算术内存")}
            exact.reserveCapacity(p.count)
            for (i,v) in p.enumerated() {
                if i%128==0 {try checkpoint(cancel)}
                exact.append(try [v.x,v.y,v.z].map{try integer($0,exponent)})
            }
            faces.reserveCapacity(ids.count/3)
            for k in stride(from:0,to:ids.count,by:3) {
                if k%384==0 {try checkpoint(cancel)}
                let a=Int(ids[k]),b=Int(ids[k+1]),c=Int(ids[k+2])
                guard a<p.count,b<p.count,c<p.count,a != b,b != c,a != c else {throw ValidationError.invalidInput("三角面编号越界或重复。")}
                var projection:Int?
                for axis in 0..<3 where projection==nil {if try o2(a,b,c,axis) != 0 {projection=axis}}
                guard let projection else {throw ValidationError.degenerateTriangle(k/3)}
                faces.append(.init(ids:[a,b,c],box:.init(p[a],p[b],p[c]),projection:projection))
            }
            _ = try build(Array(faces.indices))
            try checkpoint(cancel)
        }
        func charge(_ n:Int=1)throws {
            guard n>=0,n<=limits.maximumExactWordOperations-wordOps else {throw ValidationError.budget("精确整数运算")}
            wordOps+=n
            if wordOps%1024<n {try checkpoint(cancel)}
        }
        func normalized(_ sign:Int,_ words:[UInt32])throws->Z {
            var w=words;while w.last==0 {w.removeLast()}
            guard w.count<=limits.maximumExactWords else {throw ValidationError.budget("精确整数容量")}
            maxWords=max(maxWords,w.count);return .init(sign:w.isEmpty ? 0:sign,words:w)
        }
        func integer(_ x:Double,_ exponent:Int)throws->Z {
            if x==0 {return .init(sign:0,words:[])}
            let bits=x.bitPattern,raw=Int((bits>>52)&0x7ff),m=(bits&0x000fffffffffffff)|(raw==0 ? 0:0x0010000000000000)
            let shift=(raw==0 ? -1074:raw-1023-52)-exponent,offset=shift/32,part=shift%32
            var w=Array(repeating:UInt32(0),count:offset+3)
            let lo=m<<part;w[offset]=UInt32(truncatingIfNeeded:lo);w[offset+1]=UInt32(truncatingIfNeeded:lo>>32)
            if part>11 {w[offset+2]=UInt32(truncatingIfNeeded:m>>(64-part))}
            return try normalized(bits>>63==0 ? 1:-1,w)
        }
        func compare(_ a:[UInt32],_ b:[UInt32])->Int {
            if a.count != b.count{return a.count<b.count ? -1:1}
            for i in a.indices.reversed() where a[i] != b[i] {return a[i]<b[i] ? -1:1};return 0
        }
        func add(_ a:Z,_ b:Z)throws->Z {
            if a.sign==0{return b};if b.sign==0{return a}
            try charge(max(a.words.count,b.words.count))
            if a.sign==b.sign {
                var out:[UInt32]=[],carry:UInt64=0
                for i in 0..<max(a.words.count,b.words.count) {let t=UInt64(i<a.words.count ? a.words[i]:0)+UInt64(i<b.words.count ? b.words[i]:0)+carry;out.append(UInt32(truncatingIfNeeded:t));carry=t>>32}
                if carry != 0 {out.append(UInt32(carry))};return try normalized(a.sign,out)
            }
            let cmp=compare(a.words,b.words);if cmp==0{return .init(sign:0,words:[])}
            let big=cmp>0 ? a:b,small=cmp>0 ? b:a;var out=big.words,borrow:UInt64=0
            for i in out.indices {let sub=UInt64(i<small.words.count ? small.words[i]:0)+borrow,t=UInt64(out[i]);out[i]=UInt32(truncatingIfNeeded:t &- sub);borrow=t<sub ? 1:0}
            return try normalized(big.sign,out)
        }
        func sub(_ a:Z,_ b:Z)throws->Z {try add(a,.init(sign:-b.sign,words:b.words))}
        func mul(_ a:Z,_ b:Z)throws->Z {
            if a.sign==0 || b.sign==0{return .init(sign:0,words:[])}
            guard a.words.count+b.words.count<=limits.maximumExactWords+1 else {throw ValidationError.budget("精确乘积容量")}
            try charge(a.words.count*b.words.count)
            var out=Array(repeating:UInt32(0),count:a.words.count+b.words.count)
            for i in a.words.indices {var carry:UInt64=0
                for j in b.words.indices {let t=UInt64(a.words[i])*UInt64(b.words[j])+UInt64(out[i+j])+carry;out[i+j]=UInt32(truncatingIfNeeded:t);carry=t>>32}
                out[i+b.words.count]=UInt32(carry)
            }
            return try normalized(a.sign*b.sign,out)
        }
        func predicate()throws {guard predicates<limits.maximumPredicates else {throw ValidationError.budget("几何谓词")};predicates+=1;if predicates%256==0{try checkpoint(cancel)}}
        func o2(_ a:Int,_ b:Int,_ c:Int,_ axis:Int)throws->Int {
            try predicate();let u=(axis+1)%3,v=(axis+2)%3
            let f=(I(coordinate(p[b],u))-I(coordinate(p[a],u)))*(I(coordinate(p[c],v))-I(coordinate(p[a],v)))-(I(coordinate(p[b],v))-I(coordinate(p[a],v)))*(I(coordinate(p[c],u))-I(coordinate(p[a],u)))
            if let s=f.sign{return s};exactPredicates+=1
            return try sub(mul(sub(exact[b][u],exact[a][u]),sub(exact[c][v],exact[a][v])),mul(sub(exact[b][v],exact[a][v]),sub(exact[c][u],exact[a][u]))).sign
        }
        func o3(_ a:Int,_ b:Int,_ c:Int,_ d:Int)throws->Int {
            try predicate()
            let x=(0..<3).map{I(coordinate(p[a],$0))-I(coordinate(p[d],$0))},y=(0..<3).map{I(coordinate(p[b],$0))-I(coordinate(p[d],$0))},z=(0..<3).map{I(coordinate(p[c],$0))-I(coordinate(p[d],$0))}
            let f=x[0]*(y[1]*z[2]-y[2]*z[1])-x[1]*(y[0]*z[2]-y[2]*z[0])+x[2]*(y[0]*z[1]-y[1]*z[0])
            if let s=f.sign{return s};exactPredicates+=1
            let xx=try (0..<3).map{try sub(exact[a][$0],exact[d][$0])},yy=try (0..<3).map{try sub(exact[b][$0],exact[d][$0])},zz=try (0..<3).map{try sub(exact[c][$0],exact[d][$0])}
            let t0=try mul(xx[0],sub(mul(yy[1],zz[2]),mul(yy[2],zz[1])))
            let t1=try mul(xx[1],sub(mul(yy[0],zz[2]),mul(yy[2],zz[0])))
            let t2=try mul(xx[2],sub(mul(yy[0],zz[1]),mul(yy[1],zz[0])))
            return try add(sub(t0,t1),t2).sign
        }
        func inside(_ point:Int,_ t:Face)throws->Bool {
            let ids=t.ids,s=try o2(ids[0],ids[1],ids[2],t.projection)
            for i in 0..<3 {let x=try o2(ids[i],ids[(i+1)%3],point,t.projection);if x != 0 && x != s{return false}}
            return true
        }
        func onSegment(_ point:Int,_ a:Int,_ b:Int,_ axis:Int)throws->Bool {
            guard try o2(a,b,point,axis)==0 else{return false}
            for k in 0..<3 where k != axis {if coordinate(p[point],k)<min(coordinate(p[a],k),coordinate(p[b],k)) || coordinate(p[point],k)>max(coordinate(p[a],k),coordinate(p[b],k)){return false}}
            return true
        }
        func crosses2(_ a:Int,_ b:Int,_ c:Int,_ d:Int,_ axis:Int)throws->Bool {
            let x=try o2(a,b,c,axis),y=try o2(a,b,d,axis)
            guard x != 0,y != 0,x != y else{return false}
            let z=try o2(c,d,a,axis),w=try o2(c,d,b,axis);return z != 0 && w != 0 && z != w
        }
        func coplanar(_ a:Face,_ b:Face,_ shared:[Int])throws->Bool {
            for v in a.ids where !shared.contains(v) {if try inside(v,b){return true}}
            for v in b.ids where !shared.contains(v) {if try inside(v,a){return true}}
            for i in 0..<3 {for j in 0..<3 {if try crosses2(a.ids[i],a.ids[(i+1)%3],b.ids[j],b.ids[(j+1)%3],b.projection){return true}}}
            return false
        }
        func segmentInPlane(_ a:Int,_ b:Int,_ face:Face,_ shared:[Int])throws->Bool {
            for v in [a,b] where !shared.contains(v) {if try inside(v,face){return true}}
            for v in face.ids where !shared.contains(v) {if try onSegment(v,a,b,face.projection){return true}}
            for j in 0..<3 {if try crosses2(a,b,face.ids[j],face.ids[(j+1)%3],face.projection){return true}}
            return false
        }
        func edgeHits(_ a:Face,_ b:Face,_ distances:[Int],_ shared:[Int])throws->Bool {
            for i in 0..<3 {let j=(i+1)%3,u=a.ids[i],v=a.ids[j],x=distances[i],y=distances[j]
                if x==0 && y==0 {if try segmentInPlane(u,v,b,shared){return true};continue}
                if x==0 {if !shared.contains(u),try inside(u,b){return true};continue}
                if y==0 {if !shared.contains(v),try inside(v,b){return true};continue}
                if x==y {continue}
                let signs=try (0..<3).map{try o3(u,v,b.ids[$0],b.ids[($0+1)%3])}
                if signs.allSatisfy({$0>=0}) || signs.allSatisfy({$0<=0}) {return true}
            }
            return false
        }
        /// Returns true iff the intersection is precisely the actual shared
        /// source simplex. All other contacts throw, including closed touches.
        func pair(_ i:Int,_ j:Int)throws->Bool {
            let a=faces[i],b=faces[j],shared=a.ids.filter{b.ids.contains($0)}
            if shared.count==3 {throw ValidationError.intersection(i,j,"重复三角面")}
            if shared.count==2 {
                let aa=a.ids.first{!shared.contains($0)}!,bb=b.ids.first{!shared.contains($0)}!
                if try o3(a.ids[0],a.ids[1],a.ids[2],bb) != 0 {return true}
                let x=try o2(shared[0],shared[1],aa,a.projection),y=try o2(shared[0],shared[1],bb,a.projection)
                if x != y {return true}
                throw ValidationError.intersection(i,j,"共有边之外的共面重叠")
            }
            let da=try a.ids.map{shared.contains($0) ? 0:try o3(b.ids[0],b.ids[1],b.ids[2],$0)}
            let db=try b.ids.map{shared.contains($0) ? 0:try o3(a.ids[0],a.ids[1],a.ids[2],$0)}
            if da.allSatisfy({$0>0}) || da.allSatisfy({$0<0}) || db.allSatisfy({$0>0}) || db.allSatisfy({$0<0}) {return false}
            if shared.count==1 {
                let x=zip(a.ids,da).filter{!shared.contains($0.0)}.map(\.1),y=zip(b.ids,db).filter{!shared.contains($0.0)}.map(\.1)
                if (x[0] != 0 && x[0]==x[1]) || (y[0] != 0 && y[0]==y[1]) {return true}
            }
            if da.allSatisfy({$0==0}) {
                if try coplanar(a,b,shared){throw ValidationError.intersection(i,j,"共面重叠／非拓扑闭接触")}
            } else if try edgeHits(a,b,da,shared) || edgeHits(b,a,db,shared) {throw ValidationError.intersection(i,j,"非拓扑闭三角交集")}
            return !shared.isEmpty
        }
        func bvhCharge()throws {guard bvhWork<limits.maximumBVHWork else {throw ValidationError.budget("BVH／排序访问")};bvhWork+=1;if bvhWork%1024==0 {try checkpoint(cancel)}}
        func build(_ list:[Int])throws->Int {
            try checkpoint(cancel);try bvhCharge()
            let box=list.dropFirst().reduce(faces[list[0]].box){$0.union(faces[$1].box)},index=nodes.count
            nodes.append(.init(box:box,left:-1,right:-1,start:0,count:0))
            if list.count<=8 {let start=order.count;order+=list;nodes[index] = .init(box:box,left:-1,right:-1,start:start,count:list.count)}
            else {
                let s=box.hi-box.lo,axis=s.x>=s.y && s.x>=s.z ? 0:(s.y>=s.z ? 1:2)
                let sorted=try list.sorted {a,b in try bvhCharge();let x=coordinate(faces[a].box.lo,axis),y=coordinate(faces[b].box.lo,axis);return x==y ? a<b:x<y},mid=sorted.count/2
                let l=try build(Array(sorted[..<mid])),r=try build(Array(sorted[mid...]))
                nodes[index] = .init(box:box,left:l,right:r,start:0,count:0)
            }
            return index
        }
        func audit()throws->Report {
            var candidates=0,separated=0,touches=0
            for i in faces.indices {
                if i%128==0 {try checkpoint(cancel)}
                var stack=[0]
                while let n=stack.popLast() {
                    try bvhCharge();let node=nodes[n]
                    if !node.box.overlaps(faces[i].box){continue}
                    if node.count==0 {stack.append(node.right);stack.append(node.left);continue}
                    for k in node.start..<(node.start+node.count) {
                        let j=order[k]
                        if j<=i || !faces[i].box.overlaps(faces[j].box){continue}
                        guard candidates<limits.maximumCandidatePairs else {throw ValidationError.budget("全部闭AABB候选")}
                        candidates+=1
                        if try pair(i,j){touches+=1}else{separated+=1}
                    }
                }
            }
            try checkpoint(cancel)
            return .init(geometrySHA256:hash(p,ids),vertices:p.count,triangles:faces.count,completedAllPairs:true,
                candidateTrianglePairs:candidates,separatedPairs:separated,expectedTopologicalTouchPairs:touches,
                bvhNodes:nodes.count,bvhWork:bvhWork,predicates:predicates,exactPredicates:exactPredicates,
                exactWordOperations:wordOps,maximumExactWords:maxWords,maximumEstimatedWorkingBytes:estimatedBytes,staticSurfaceOnly:true)
        }
    }
}
