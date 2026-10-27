import Foundation
import CryptoKit

/// Conservative, source-isometric *initialization* outside the unchanged visible
/// body. This proves body clearance only; it does not prove mutual cloth
/// clearance, sewing convergence, support, fit or a physical drape.
nonisolated enum GarmentCodeRigidBodyClearance {
    typealias V = GarmentCodeCircleDrape.Vector3

    struct Panel: Sendable {
        let panelID: String
        let positions: [V]
        let u: V
        let v: V
        let normal: V
        /// The paper curve can extend beyond the sampled mesh boundary by this
        /// certified mesher error. It affects conservative selection, not rest.
        var maximumBoundaryDeviationMeters: Double = 0
    }
    struct Limits: Sendable {
        var maximumPanels = 128
        var maximumClothVertices = 20_000
        var maximumBodyVertices = 40_000
        var maximumBodyTriangles = 80_000
        var maximumTrianglePanelTests = 10_240_000
    }
    struct Bounds2: Codable, Sendable {
        let minimumU: Double, maximumU: Double, minimumV: Double, maximumV: Double
    }
    struct PanelProof: Codable, Sendable {
        let panelID: String
        let origin: V, u: V, v: V, normal: V
        let originalPlaneCoordinateMeters: Double
        let clothBounds: Bounds2, selectedBounds: Bounds2
        let boundaryDeviationMeters: Double
        /// Every body triangle with an overlapping projected AABB is retained,
        /// including degenerate projections and false-positive AABB overlap.
        let candidateBodyTriangleIDs: [Int]
        let minimumBodyNormalCoordinateMeters: Double?
        let maximumBodyNormalCoordinateMeters: Double?
        let chosenNormalSign: Double
        let minimumRequiredTranslationMeters: Double
        let appliedTranslation: V
        let finalPlaneCoordinateMeters: Double
        let selectedTriangleSupportClearanceMeters: Double?
        let maximumOriginalPlaneDeviationMeters: Double
    }
    struct Proof: Codable, Sendable {
        let algorithm: String
        let requestedShellMeters: Double
        let numericalSeparationReserveMeters: Double
        let commonTranslationMagnitudeMeters: Double
        let bodyGeometrySHA256: String
        let bodyVertexCount: Int, bodyTriangleCount: Int
        let trianglePanelTests: Int
        let panels: [PanelProof]
        let bodyOnlyInitializationProof: Bool
    }
    struct Result: Sendable {
        let positionsByPanel: [String: [V]]
        let proof: Proof
    }
    enum ClearanceError: LocalizedError, Sendable {
        case invalid(String), budget(String)
        var errorDescription: String? {
            switch self {
            case let .invalid(s): return "刚体人体间隙初始化无效：" + s
            case let .budget(s): return "刚体人体间隙初始化超过预算：" + s
            }
        }
    }
    private struct Selection {
        let panel: Panel, origin: V, bounds: Bounds2, expanded: Bounds2
        let plane: Double, deviation: Double, candidates: [Int]
        let low: Double?, high: Double?, sign: Double, required: Double
    }
    /// Translation is along each panel's unchanged plane normal. All panels use
    /// the same amplitude, with their own nearest-outside direction. No vertex
    /// is individually projected, no body mesh is rebuilt, and no pin is added.
    static func prepare(panels: [Panel], bodyPositions: [V], bodyTriangleIndices: [UInt32],
        shellMeters: Double = 0.0025, limits: Limits = .init(),
        isCancelled: @Sendable () -> Bool = {false}) throws -> Result {
        if isCancelled() { throw CancellationError() }
        guard (1...128).contains(limits.maximumPanels), (3...20_000).contains(limits.maximumClothVertices),
              (3...40_000).contains(limits.maximumBodyVertices), (1...80_000).contains(limits.maximumBodyTriangles),
              (1...10_240_000).contains(limits.maximumTrianglePanelTests),
              shellMeters.isFinite, (0.000001...0.02).contains(shellMeters),
              !panels.isEmpty, !bodyTriangleIndices.isEmpty, bodyTriangleIndices.count % 3 == 0 else {
            throw ClearanceError.invalid("需要有界裁片、有限壳厚和完整人体三角面。")
        }
        guard panels.count <= limits.maximumPanels,
              bodyPositions.count >= 3, bodyPositions.count <= limits.maximumBodyVertices,
              bodyTriangleIndices.count / 3 <= limits.maximumBodyTriangles,
              panels.reduce(0, {$0 + $1.positions.count}) <= limits.maximumClothVertices,
              panels.count * (bodyTriangleIndices.count / 3) <= limits.maximumTrianglePanelTests else {
            throw ClearanceError.budget("未省略任何裁片或人体三角面。")
        }
        guard Set(panels.map(\.panelID)).count == panels.count,
              panels.allSatisfy({!$0.panelID.isEmpty && $0.positions.count >= 3}),
              bodyPositions.allSatisfy(valid), panels.allSatisfy({$0.positions.allSatisfy(valid)}),
              bodyTriangleIndices.allSatisfy({Int($0) < bodyPositions.count}) else {
            throw ClearanceError.invalid("顶点、裁片名称或人体索引无效。")
        }
        var bodyLow = bodyPositions[0], bodyHigh = bodyLow
        for (i,p) in bodyPositions.enumerated() {
            if i % 256 == 0 && isCancelled() { throw CancellationError() }
            bodyLow = .init(x:min(bodyLow.x,p.x),y:min(bodyLow.y,p.y),z:min(bodyLow.z,p.z))
            bodyHigh = .init(x:max(bodyHigh.x,p.x),y:max(bodyHigh.y,p.y),z:max(bodyHigh.z,p.z))
        }
        // Reject invalid source triangles rather than silently dropping them.
        for offset in stride(from:0,to:bodyTriangleIndices.count,by:3) {
            if offset % 768 == 0 && isCancelled() { throw CancellationError() }
            let a=bodyPositions[Int(bodyTriangleIndices[offset])], b=bodyPositions[Int(bodyTriangleIndices[offset+1])], c=bodyPositions[Int(bodyTriangleIndices[offset+2])]
            guard (b-a).cross(c-a).length > 1e-16 else { throw ClearanceError.invalid("人体三角面退化。") }
        }
        let center=(bodyLow+bodyHigh)/2, reserve=1e-9
        var selections:[Selection]=[], magnitude=0.0
        for panel in panels {
            if isCancelled() { throw CancellationError() }
            let u=panel.u,v=panel.v,n=panel.normal,origin=panel.positions[0], plane=dot(n,origin)
            guard u.isFinite,v.isFinite,n.isFinite,
                  abs(u.length-1)<1e-10,abs(v.length-1)<1e-10,abs(n.length-1)<1e-10,
                  abs(dot(u,v))<1e-10,abs(dot(u,n))<1e-10,abs(dot(v,n))<1e-10,
                  abs(abs(dot(u.cross(v),n))-1)<1e-10,
                  panel.maximumBoundaryDeviationMeters.isFinite,
                  (0...0.001).contains(panel.maximumBoundaryDeviationMeters) else {
                throw ClearanceError.invalid("每片必须保留真实刚体平面和有界边界离散误差。")
            }
            var loU=Double.infinity,hiU = -Double.infinity,loV=Double.infinity,hiV = -Double.infinity,deviation=0.0
            for p in panel.positions {
                let q=p-origin, a=dot(u,q), b=dot(v,q)
                loU=min(loU,a);hiU=max(hiU,a);loV=min(loV,b);hiV=max(hiV,b)
                deviation=max(deviation,abs(dot(n,q)))
            }
            guard deviation <= 1e-10,hiU-loU > 1e-10,hiV-loV > 1e-10 else {
                throw ClearanceError.invalid("裁片必须是非退化原始刚体平面，不能预先贴身或弯折。")
            }
            let bounds=Bounds2(minimumU:loU,maximumU:hiU,minimumV:loV,maximumV:hiV)
            // Any triangle closer than shell to the real source curve/mesh
            // overlaps this expanded UV rectangle. Translation along n leaves
            // these projections unchanged, so selection remains valid afterward.
            let padding=shellMeters+panel.maximumBoundaryDeviationMeters+reserve
            let expanded=Bounds2(minimumU:loU-padding,maximumU:hiU+padding,minimumV:loV-padding,maximumV:hiV+padding)
            var candidates:[Int]=[],low=Double.infinity,high = -Double.infinity
            for offset in stride(from:0,to:bodyTriangleIndices.count,by:3) {
                if offset % 768 == 0 && isCancelled() { throw CancellationError() }
                let points=(0..<3).map{bodyPositions[Int(bodyTriangleIndices[offset+$0])]}
                let uv=points.map{p -> (Double,Double) in let q=p-origin;return(dot(u,q),dot(v,q))}
                let a=uv.map(\.0),b=uv.map(\.1)
                if a.max()! < expanded.minimumU || a.min()! > expanded.maximumU ||
                   b.max()! < expanded.minimumV || b.min()! > expanded.maximumV { continue }
                candidates.append(offset/3)
                for p in points { let d=dot(n,p);low=min(low,d);high=max(high,d) }
            }
            let sign:Double, required:Double
            if candidates.isEmpty {
                let panelCenter=origin+u*((loU+hiU)/2)+v*((loV+hiV)/2), side=dot(n,panelCenter-center)
                sign=abs(side)>1e-12 ? (side>0 ? 1:-1):canonicalSign(n)
                required=0
            } else {
                let positive=max(0,high+shellMeters+reserve+deviation-plane)
                let negative=max(0,plane-(low-shellMeters-reserve-deviation))
                if abs(positive-negative)<=1e-12 {sign=canonicalSign(n);required=positive}
                else if positive<negative {sign=1;required=positive}
                else {sign = -1;required=negative}
            }
            magnitude=max(magnitude,required)
            selections.append(.init(panel:panel,origin:origin,bounds:bounds,expanded:expanded,
                plane:plane,deviation:deviation,candidates:candidates,low:candidates.isEmpty ? nil:low,
                high:candidates.isEmpty ? nil:high,sign:sign,required:required))
        }
        guard magnitude.isFinite,magnitude <= 10 else { throw ClearanceError.budget("保守支撑平面的刚体位移超过 10 m。") }
        var positioned:[String:[V]]=[:], proofs:[PanelProof]=[]
        for selection in selections {
            if isCancelled() { throw CancellationError() }
            let panel=selection.panel, shift=panel.normal*(selection.sign*magnitude)
            let positions=panel.positions.map{$0+shift}
            guard positions.allSatisfy(valid) else {throw ClearanceError.invalid("刚体平移后坐标溢出。")}
            positioned[panel.panelID]=positions
            let final=selection.plane+selection.sign*magnitude
            let clearance:Double? = selection.sign>0 ? selection.high.map{final-$0-selection.deviation}:selection.low.map{$0-final-selection.deviation}
            if let clearance,clearance < shellMeters-1e-12 {throw ClearanceError.invalid("选中三角面支撑平面未达到原壳厚。")}
            proofs.append(.init(panelID:panel.panelID,origin:selection.origin,u:panel.u,v:panel.v,normal:panel.normal,
                originalPlaneCoordinateMeters:selection.plane,clothBounds:selection.bounds,selectedBounds:selection.expanded,
                boundaryDeviationMeters:panel.maximumBoundaryDeviationMeters,candidateBodyTriangleIDs:selection.candidates,
                minimumBodyNormalCoordinateMeters:selection.low,maximumBodyNormalCoordinateMeters:selection.high,
                chosenNormalSign:selection.sign,minimumRequiredTranslationMeters:selection.required,appliedTranslation:shift,
                finalPlaneCoordinateMeters:final,selectedTriangleSupportClearanceMeters:clearance,
                maximumOriginalPlaneDeviationMeters:selection.deviation))
        }
        if isCancelled() { throw CancellationError() }
        return .init(positionsByPanel:positioned,proof:.init(
            algorithm:"All UV-AABB-overlapping visible body triangles; nearest outside support plane; common rigid amplitude; no cloth self-clearance guarantee",
            requestedShellMeters:shellMeters,numericalSeparationReserveMeters:reserve,commonTranslationMagnitudeMeters:magnitude,
            bodyGeometrySHA256:geometrySHA256(positions:bodyPositions,indices:bodyTriangleIndices),
            bodyVertexCount:bodyPositions.count,bodyTriangleCount:bodyTriangleIndices.count/3,
            trianglePanelTests:panels.count*(bodyTriangleIndices.count/3),panels:proofs,bodyOnlyInitializationProof:true))
    }
    private static func dot(_ a:V,_ b:V)->Double {a.x*b.x+a.y*b.y+a.z*b.z}
    private static func valid(_ p:V)->Bool { p.isFinite && max(abs(p.x),abs(p.y),abs(p.z)) <= 100 }
    /// This tie break is invariant to reversing the input normal: world-space
    /// displacement always points along its first nonzero positive component.
    private static func canonicalSign(_ n:V)->Double {
        for value in [n.x,n.y,n.z] where abs(value)>1e-12 {return value>0 ? 1:-1}
        return 1
    }
    static func geometrySHA256(positions:[V],indices:[UInt32])->String {
        var bytes=Data("rigid-clearance-visible-body-v1\0".utf8)
        func append<T:FixedWidthInteger>(_ value:T) {var little=value.littleEndian;withUnsafeBytes(of:&little){bytes.append(contentsOf:$0)}}
        append(UInt64(positions.count));append(UInt64(indices.count))
        for p in positions {append(p.x.bitPattern);append(p.y.bitPattern);append(p.z.bitPattern)}
        for id in indices {append(id)}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
}
