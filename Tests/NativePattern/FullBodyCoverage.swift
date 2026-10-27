import Foundation
import CryptoKit

/// Full anatomical SDF coverage and exact preservation of its prior lower grid.
/// This checks the fixed standard mannequin, not individualized upper-body fit.
@main
struct FullBodyCoverageRegression {
    enum Failure: Error { case check(String) }
    typealias V = GarmentCodeCircleDrape.Vector3

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.check(message) }
    }
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = ProcessInfo.processInfo.environment["GARMENTCODE_FULL_BODY_RESOURCE_DIR"]
            .map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("TrailorAss/Resources")
        let json = try Data(contentsOf: resources.appendingPathComponent("GarmentCodeStandardBody.json"))
        let source = try Data(contentsOf: resources.appendingPathComponent("GarmentCodeStandardBodySource.json"))
        let metadata = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let provenance = try JSONSerialization.jsonObject(with: source) as! [String: Any]
        let grid = metadata["collisionGrid"] as! [String: Any]
        let dimensions = grid["dimensions"] as! [Int]
        let origin = grid["origin"] as! [Double]
        let spacing = grid["spacing"] as! Double
        try require(dimensions == [128,181,65], "Unexpected full-body grid dimensions")
        try require(origin == [-0.6337,-1.1137,-0.3037] && spacing == 0.01,
                    "Legacy grid origin or spacing changed")
        let field = try Data(contentsOf: resources.appendingPathComponent(grid["filename"] as! String))
        try require(field.count == 128*181*65*4, "Full-body SDF byte count")
        try require(hash(field) == provenance["collisionFieldSHA256"] as? String,
                    "Full-body field hash differs from provenance")
        try require(hash(json) == provenance["derivedMeshSHA256"] as? String,
                    "Derived resource hash differs from provenance")

        // Layout is X-fastest, then Y, then Z. Extending Y changes every Z
        // slab stride, so comparing a contiguous prefix would miss regressions.
        var legacy = Data(capacity: 128*133*65*4)
        for z in 0..<65 {
            for y in 0..<133 {
                let offset = ((z*181+y)*128)*4
                legacy.append(field.subdata(in: offset..<offset+128*4))
            }
        }
        let originalLowerHash = "81251419a12a69de9946e8d85237a5ff77fe8c5775c992360e8b8878ca9d9172"
        try require(hash(legacy) == originalLowerHash,
                    "At least one original lower-body grid byte changed")

        let catalog = try GarmentCodeParameterCatalog.load(
            from: root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body = try GarmentCodeStandardBody.load(body: .init(values: catalog.body), resourceDirectory: resources)
        try require(body.positions.count == 13380 && body.triangleIndices.count == 26756*3,
                    "Visible mannequin topology changed")
        let high = (0..<3).map { origin[$0]+spacing*Double(dimensions[$0]-1) }
        for point in body.positions {
            let xyz = [point.x,point.y,point.z]
            try require((0..<3).allSatisfy { xyz[$0] > origin[$0] && xyz[$0] < high[$0] },
                        "A visible body vertex lies outside the full collision grid")
            try require(body.signedDistance(point) != nil, "Visible body vertex has no distance-field coverage")
        }

        var maximumSurfaceError = 0.0
        func probe(_ label: String, near anchor: V) throws {
            var nearest: (V,V)? = nil
            var best = Double.infinity
            for t in stride(from: 0, to: body.triangleIndices.count, by: 3) {
                let a = body.positions[Int(body.triangleIndices[t])]
                let b = body.positions[Int(body.triangleIndices[t+1])]
                let c = body.positions[Int(body.triangleIndices[t+2])]
                let center = (a+b+c)/3
                let normal = (b-a).cross(c-a)
                guard normal.length > 1e-10 else { continue }
                let distance = (center-anchor).lengthSquared
                if distance < best { best=distance; nearest=(center,normal/normal.length) }
            }
            guard let (surface,normal) = nearest else { throw Failure.check("Missing \(label) surface") }
            try require(surface.y > 0.2163, "\(label) probe must exercise newly covered upper body")
            guard let surfaceDistance=body.signedDistance(surface),
                  let inside=body.signedDistance(surface-normal*0.02),
                  let outside=body.signedDistance(surface+normal*0.02) else {
                throw Failure.check("\(label) has no full-body field coverage")
            }
            maximumSurfaceError=max(maximumSurfaceError,abs(surfaceDistance))
            try require(abs(surfaceDistance)<0.012, "\(label) field does not follow the unchanged visible surface")
            try require(inside < -0.005 && outside > 0.005,
                        "\(label) inside/outside sign failed: \(inside), \(outside)")
            let projected=body.project(surface-normal*0.02,thickness:0.0025)
            try require(projected.isFinite && body.penetration(projected)<0.003,
                        "\(label) contact projection failed")
            print("\(label): y=\(surface.y)m inside=\(inside)m outside=\(outside)m")
        }
        try probe("chest", near: .init(x:0,y:0.25,z:0.11))
        try probe("left shoulder", near: .init(x:-0.17,y:0.35,z:0))
        try probe("right shoulder", near: .init(x:0.17,y:0.35,z:0))
        try probe("left upper arm", near: .init(x:-0.27,y:0.27,z:0.03))
        try probe("right upper arm", near: .init(x:0.27,y:0.27,z:0.03))
        try probe("head", near: .init(x:0,y:0.54,z:0.11))
        try require((body.signedDistance(.init(x:0,y:0.67,z:0)) ?? -1) > 0.015,
                    "Free space above the head should remain outside")
        try require(body.signedDistance(.init(x:0,y:0.8,z:0)) == nil,
                    "Out-of-grid queries must remain explicitly uncovered")
        print("PASS: complete fixed-body vertex coverage, six upper-body sign/projection probes, " +
              "legacy 1,106,560 lower floats bitwise preserved; upper surface error \(maximumSurfaceError*1000)mm")
    }
}
