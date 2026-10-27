import Foundation
import CryptoKit

/// Project-authored measurements attached to the original CC0 skin topology.
/// Read-only: this module does not fit, pose, certify or replace a body mesh.
nonisolated enum GarmentCodeBodySurfaceMeasurements {
    typealias V = GarmentCodeCircleDrape.Vector3
    static let approvedContractSHA256 = "6658a5ed298c82f36c0b1bce6df0823a10c0f0bb5aa67c136c142cb6bc5ce610"
    struct Limits: Sendable {
        var maximumResourceBytes = 2_000_000
        var maximumSamples = 4096
    }
    enum MeasurementError: LocalizedError, Sendable {
        case invalid(String), budget
        var errorDescription: String? { switch self {
        case let .invalid(s): return "人体表面量法无效：" + s
        case .budget: return "人体表面量法超出预算。"
        }}
    }
    struct Attachment: Codable, Sendable {
        let sourceVertexIDs: [Int]
        let weights: [Double]
    }
    struct Definition: Codable, Sendable {
        let id: String, title: String, targetKey: String, kind: String, definition: String, targetUse: String
        let closed: Bool?
        let samples: [Attachment]
        let sourceTriangleIDs: [Int]?
        let templateObservedMeters: Double
    }
    struct Contract: Decodable, Sendable {
        let format: String, sourceLicense: String, sourceCommit: String
        let templateResourceSHA256: String, rigResourceSHA256: String
        let sourceVertexCount: Int, visibleVertexCount: Int, triangleCount: Int
        let visibleToSource: [Int]
        let landmarks: [String: Attachment]
        let measurements: [Definition]
    }
    struct Measurement: Codable, Sendable {
        let definition: Definition
        let points: [V]
        let observedMeters: Double, requestedMeters: Double, observedMinusRequestedMeters: Double
    }
    struct Report: Codable, Sendable {
        let contractSHA256: String, templateResourceSHA256: String, rigResourceSHA256: String
        let sourceCommit: String, geometrySHA256: String, parameterSHA256: String
        let positions: [V], triangleIndices: [UInt32], bodyValues: [String: Double]
        let landmarks: [String: V], measurements: [Measurement]
        let bodyFittingApplied: Bool, defaultBodyBehaviorChanged: Bool
        let scope: String
    }
    private struct Template: Decodable {
        let sourceCommit: String, sourceSHA256: String, license: String
        let positions: [[Double]], triangleIndices: [UInt32]
    }
    private struct RigMap: Decodable {
        let sourceCommit: String, templateResourceSHA256: String
        let visibleToSource: [Int], sourceToVisible: [Int]
    }
    struct Prepared: Sendable {
        let contract: Contract
        private let sourceToVisible: [Int], templatePositions: [V], triangles: [UInt32]
        private let contractSHA: String
        init(contractData: Data, templateData: Data, rigData: Data, limits: Limits = .init(),
             isCancelled: @Sendable () -> Bool = { false }) throws {
            if isCancelled() { throw CancellationError() }
            guard (1...2_000_000).contains(limits.maximumResourceBytes), (1...4096).contains(limits.maximumSamples),
                  contractData.count <= limits.maximumResourceBytes, templateData.count <= 8_000_000, rigData.count <= 16_000_000 else {
                throw MeasurementError.budget
            }
            let c = try JSONDecoder().decode(Contract.self, from: contractData)
            let t = try JSONDecoder().decode(Template.self, from: templateData)
            let r = try JSONDecoder().decode(RigMap.self, from: rigData)
            guard hash(contractData) == approvedContractSHA256,
                  c.format == "tailorass-project-body-surface-contract-v1", c.sourceLicense == "CC0-1.0",
                  c.sourceCommit == "a8bc2d54ff0ac92e78ff71431b1023eda42bf482",
                  c.templateResourceSHA256 == hash(templateData), c.rigResourceSHA256 == hash(rigData),
                  t.license == "CC0-1.0", t.sourceCommit == c.sourceCommit, r.sourceCommit == c.sourceCommit,
                  t.sourceSHA256 == "8e761e6624b8f54536409135d1636da63b32486a90d4897f84e121d144f6fb4c",
                  r.templateResourceSHA256 == c.templateResourceSHA256,
                  c.visibleVertexCount == 13380, c.sourceVertexCount == 19158, c.triangleCount == 26756,
                  t.positions.count == c.visibleVertexCount, t.triangleIndices.count == c.triangleCount * 3,
                  c.visibleToSource == r.visibleToSource, r.visibleToSource.count == c.visibleVertexCount,
                  r.sourceToVisible.count == c.sourceVertexCount,
                  Set(c.visibleToSource).count == c.visibleVertexCount else { throw MeasurementError.invalid("源文件或表面契约绑定不匹配。") }
            var p: [V] = []
            for (i, xyz) in t.positions.enumerated() {
                if i % 256 == 0, isCancelled() { throw CancellationError() }
                guard xyz.count == 3, xyz.allSatisfy(\.isFinite), xyz.allSatisfy({ abs($0) < 100 }),
                      (0..<c.sourceVertexCount).contains(c.visibleToSource[i]),
                      r.sourceToVisible[c.visibleToSource[i]] == i else { throw MeasurementError.invalid("源坐标或映射无效。") }
                p.append(.init(x: xyz[0], y: xyz[1], z: xyz[2]))
            }
            for (source, visible) in r.sourceToVisible.enumerated() {
                guard visible == -1 || ((0..<p.count).contains(visible) && c.visibleToSource[visible] == source) else {
                    throw MeasurementError.invalid("反向表面映射无效。")
                }
            }
            guard t.triangleIndices.allSatisfy({ $0 < UInt32(p.count) }), c.measurements.count == 7,
                  Set(c.measurements.map(\.id)).count == c.measurements.count,
                  c.measurements.reduce(0, { $0 + $1.samples.count }) <= limits.maximumSamples else { throw MeasurementError.budget }
            let map = r.sourceToVisible
            func valid(_ a: Attachment) -> Bool {
                (1...3).contains(a.weights.count) && a.sourceVertexIDs.count == a.weights.count &&
                Set(a.sourceVertexIDs).count == a.sourceVertexIDs.count &&
                a.weights.allSatisfy({ $0.isFinite && (0...1).contains($0) }) &&
                abs(a.weights.reduce(0, +) - 1) <= 1e-14 &&
                a.sourceVertexIDs.allSatisfy({ (0..<map.count).contains($0) && map[$0] >= 0 })
            }
            func point(_ a: Attachment) -> V {
                zip(a.sourceVertexIDs, a.weights).reduce(V.zero) { $0 + p[map[$1.0]] * $1.1 }
            }
            for a in c.landmarks.values { guard valid(a) else { throw MeasurementError.invalid("表面标记无效。") } }
            // A segment is genuinely on the original surface only when both
            // barycentric endpoints belong to the same original triangle.
            for m in c.measurements {
                if isCancelled() { throw CancellationError() }
                guard !m.id.isEmpty, !m.title.isEmpty, !m.definition.isEmpty,
                      ["bust", "shoulder_w", "arm_length", "wrist"].contains(m.targetKey),
                      ["projectFittingReference", "referenceOnly"].contains(m.targetUse),
                      m.samples.allSatisfy(valid), m.templateObservedMeters.isFinite, m.templateObservedMeters > 0 else {
                    throw MeasurementError.invalid("量法定义无效。")
                }
                let q = m.samples.map(point)
                if m.kind == "surfacePath" {
                    let n = m.samples.count, closed = m.closed == true
                    guard n >= (closed ? 3 : 2), let faces = m.sourceTriangleIDs, faces.count == n - (closed ? 0 : 1) else {
                        throw MeasurementError.invalid("表面路径长度或面来源无效。")
                    }
                    for (j, face) in faces.enumerated() {
                        guard (0..<c.triangleCount).contains(face) else { throw MeasurementError.invalid("原三角面编号无效。") }
                        let ids = Set((0..<3).map { c.visibleToSource[Int(t.triangleIndices[face * 3 + $0])] })
                        guard m.samples[j].sourceVertexIDs.allSatisfy(ids.contains),
                              m.samples[(j + 1) % n].sourceVertexIDs.allSatisfy(ids.contains) else {
                            throw MeasurementError.invalid("路径离开了所声明的原三角面。")
                        }
                    }
                } else {
                    guard ["pointDistance", "axisDistanceX"].contains(m.kind), m.samples.count == 2,
                          m.sourceTriangleIDs == nil, m.closed != true else { throw MeasurementError.invalid("点跨度定义无效。") }
                }
                guard abs(length(m, q) - m.templateObservedMeters) <= 2e-12 else { throw MeasurementError.invalid("参考路径数值与源表面不匹配。") }
            }
            if isCancelled() { throw CancellationError() }
            contract = c; sourceToVisible = map; templatePositions = p; triangles = t.triangleIndices; contractSHA = hash(contractData)
        }
        func measure(positions: [V], triangleIndices: [UInt32], bodyValues: [String: Double],
                     isCancelled: @Sendable () -> Bool = { false }) throws -> Report {
            if isCancelled() { throw CancellationError() }
            guard positions.count == templatePositions.count, triangleIndices == triangles,
                  positions.allSatisfy({ $0.isFinite && $0.length < 100 }) else { throw MeasurementError.invalid("需要相同源拓扑的完整实际人体。") }
            try validateValues(bodyValues)
            // Do not project to a nearest unrelated face or silently repair
            // invalid current triangles. Stored attachments keep their IDs.
            for face in 0..<(triangles.count / 3) {
                if face % 256 == 0, isCancelled() { throw CancellationError() }
                let a = positions[Int(triangles[face * 3])], b = positions[Int(triangles[face * 3 + 1])], c = positions[Int(triangles[face * 3 + 2])]
                let u = b - a, v = c - a
                let normal = V(x: u.y * v.z - u.z * v.y, y: u.z * v.x - u.x * v.z, z: u.x * v.y - u.y * v.x)
                guard normal.isFinite, normal.length > 0 else { throw MeasurementError.invalid("当前人体含退化三角面。") }
            }
            func point(_ a: Attachment) -> V {
                zip(a.sourceVertexIDs, a.weights).reduce(V.zero) { $0 + positions[sourceToVisible[$1.0]] * $1.1 }
            }
            var result: [Measurement] = []
            for m in contract.measurements {
                if isCancelled() { throw CancellationError() }
                let points = m.samples.map(point), observed = length(m, points), target = bodyValues[m.targetKey]! / 100
                guard observed.isFinite, observed > 0 else { throw MeasurementError.invalid("当前表面路径长度无效。") }
                result.append(.init(definition: m, points: points, observedMeters: observed, requestedMeters: target,
                                    observedMinusRequestedMeters: observed - target))
            }
            let landmarks = contract.landmarks.mapValues(point)
            if isCancelled() { throw CancellationError() }
            return .init(contractSHA256: contractSHA, templateResourceSHA256: contract.templateResourceSHA256,
                rigResourceSHA256: contract.rigResourceSHA256, sourceCommit: contract.sourceCommit,
                geometrySHA256: geometryHash(positions, triangles), parameterSHA256: parameterHash(bodyValues),
                positions: positions, triangleIndices: triangles, bodyValues: bodyValues, landmarks: landmarks, measurements: result,
                bodyFittingApplied: false, defaultBodyBehaviorChanged: false,
                scope: "项目参考量法、尚未拟合。固定原表面附着；参数残差只对应所声明的项目量法。")
        }
    }
    private static func length(_ m: Definition, _ p: [V]) -> Double {
        if m.kind == "pointDistance" { return (p[1] - p[0]).length }
        if m.kind == "axisDistanceX" { return abs(p[1].x - p[0].x) }
        var total = 0.0
        for i in 0..<(p.count - 1) { total += (p[i + 1] - p[i]).length }
        if m.closed == true { total += (p[0] - p[p.count - 1]).length }
        return total
    }
    private static func validateValues(_ v: [String: Double]) throws {
        let raw: Set<String> = ["arm_length","arm_pose_angle","armscye_depth","back_width","bum_points","bust","bust_line","bust_points","crotch_hip_diff","head_l","height","hip_back_width","hip_inclination","hips","hips_line","leg_circ","neck_w","shoulder_incl","shoulder_w","underbust","vert_bust_line","waist","waist_back_width","waist_line","waist_over_bust_line","wrist"]
        let derived: Set<String> = ["_waist_level","_leg_length","_base_sleeve_balance","_bust_line","_hip_inclination","_shoulder_incl","_armscye_depth"]
        guard Set(v.keys) == raw.union(derived), v.values.allSatisfy(\.isFinite),
              ["bust", "shoulder_w", "arm_length", "wrist"].allSatisfy({ v[$0]! > 0 }) else { throw MeasurementError.invalid("需要完整且有效的26项原参数与7项派生值。") }
        let waist = v["height"]! - v["head_l"]! - v["waist_line"]!
        let expected = ["_waist_level":waist, "_leg_length":waist-v["hips_line"]!, "_base_sleeve_balance":v["shoulder_w"]!-2,
            "_bust_line":(2.0/3)*v["vert_bust_line"]!+(1.0/3)*v["bust_line"]!, "_hip_inclination":v["hip_inclination"]!/2,
            "_shoulder_incl":v["shoulder_incl"]!, "_armscye_depth":v["armscye_depth"]!+2.5]
        guard expected.allSatisfy({ v[$0.key]!.bitPattern == $0.value.bitPattern }) else { throw MeasurementError.invalid("派生值与原参数不一致。") }
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func geometryHash(_ p: [V], _ t: [UInt32]) -> String {
        var d = Data("rigid-clearance-visible-body-v1\0".utf8)
        for n in [UInt64(p.count), UInt64(t.count)] { var b = n.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
        for q in p { for x in [q.x, q.y, q.z] { var b = x.bitPattern.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } } }
        for i in t { var b = i.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
        return hash(d)
    }
    private static func parameterHash(_ v: [String: Double]) -> String {
        var d = Data("body-surface-measurements-parameters-v1\0".utf8)
        for k in v.keys.sorted() { d.append(contentsOf: k.utf8); d.append(0); var b = v[k]!.bitPattern.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
        return hash(d)
    }
}
