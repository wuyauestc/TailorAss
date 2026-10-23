import Foundation

@main
struct SeamGuideRegression {
    typealias Edge = GarmentCodeSeamGuide.EdgeKey

    static func main() throws {
        let a = Edge(panel: "front", edge: 0)
        let b = Edge(panel: "back", edge: 1)
        let dartA = Edge(panel: "front", edge: 2)
        let dartB = Edge(panel: "front", edge: 3)
        func side(_ edge: Edge) -> GarmentCodeStitchSide { .init(panel: edge.panel, edge: edge.edge) }
        let stitches: [GarmentCodeStitch] = [
            .init(sides: [side(a), side(b)]),
            .init(sides: [side(dartA), side(dartB)], rightWrong: true),
            .init(sides: [side(a), side(dartA)]),
            .init(sides: [side(b), side(b)])
        ]
        let guide = GarmentCodeSeamGuide(stitches: stitches)
        precondition(guide.groups.map(\.id) == [0, 1, 2, 3])
        precondition(guide.groups.map(\.number) == [1, 2, 3, 4])
        precondition(guide.groups.map(\.label) == ["缝1", "缝2", "缝3", "缝4"])
        precondition(guide.groups(for: a).map(\.id) == [0, 2], "Shared edges retain every group")
        precondition(guide.groups(for: b).map(\.id) == [0, 3], "Repeated sides must not duplicate the group")
        precondition(guide.groups(forPanel: "front").map(\.id) == [0, 1, 2], "Darts must appear once per panel")
        precondition(guide.groups(forPanel: "missing").isEmpty)
        precondition(guide.groups(for: .init(panel: "missing", edge: 0)).isEmpty)
        precondition(guide.group(id: 1)?.rightWrong == true)
        precondition(guide.group(id: -1) == nil && guide.group(id: 4) == nil)
        precondition(guide.group(id: 3)?.sides == [b, b], "Source side references remain untouched")
        let empty = GarmentCodeSeamGuide(stitches: [])
        precondition(empty.groups.isEmpty && empty.groups(for: a).isEmpty)
        precondition(empty.groups(forPanel: "front").isEmpty && empty.group(id: 0) == nil)
        let emptySides = GarmentCodeSeamGuide(stitches: [.init(sides: []), stitches[0]])
        precondition(emptySides.groups.map(\.id) == [0, 1] && emptySides.groups[0].sides.isEmpty,
                     "Empty groups retain their original stitch indexes")

        let horizontal = [GarmentCodePoint(x: 0, y: 0), .init(x: 10, y: 0)]
        let upper = [GarmentCodePoint(x: 0, y: 4), .init(x: 10, y: 4)]
        let paths = [(edge: a, points: horizontal), (edge: b, points: upper)]
        precondition(GarmentCodeSeamGuide.closestEdge(to: .init(x: 5, y: 0.4), paths: paths, tolerance: 1) == a)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .init(x: 5, y: 3.8), paths: paths, tolerance: 1) == b)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .init(x: 5, y: 2), paths: paths, tolerance: 2) == a,
                     "Equal distances must select the first path consistently")
        precondition(GarmentCodeSeamGuide.closestEdge(to: .init(x: 5, y: 2), paths: paths, tolerance: 1) == nil)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .init(x: 11, y: 0), paths: paths, tolerance: 1) == a,
                     "Distance to the endpoint is included at the tolerance boundary")
        precondition(GarmentCodeSeamGuide.closestEdge(to: .zero, paths: [], tolerance: 10) == nil)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .zero, paths: paths, tolerance: -1) == nil)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .zero, paths: paths, tolerance: .infinity) == nil)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .init(x: .nan, y: 0), paths: paths, tolerance: 10) == nil)

        let curve = GarmentCodeGeometryEdge(id: "arc", start: .zero, end: .init(x: 10, y: 0),
            curvature: .init(type: "quadratic", params: [[0.5, 0.8]]))
        let sampled = curve.sample(maxSegmentLength: 0.1)
        precondition(GarmentCodeSeamGuide.closestEdge(to: curve.point(at: 0.5),
            paths: [(edge: b, points: sampled)], tolerance: 0.1) == b,
            "Hit test follows the sampled curve rather than its endpoint chord")
        let degenerate = [(edge: a, points: [GarmentCodePoint.zero, .zero]),
                          (edge: b, points: [GarmentCodePoint(x: 5, y: 5)])]
        precondition(GarmentCodeSeamGuide.closestEdge(to: .zero, paths: degenerate, tolerance: 0) == a)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .init(x: 5, y: 5), paths: degenerate, tolerance: 0) == b)
        precondition(GarmentCodeSeamGuide.closestEdge(to: .zero,
            paths: [(edge: a, points: [.zero, .init(x: Double.leastNonzeroMagnitude, y: 0)])],
            tolerance: 0) == a, "Very short finite segments remain hittable")
        precondition(GarmentCodeSeamGuide.closestEdge(to: .zero,
            paths: [(edge: a, points: []), (edge: b, points: [.init(x: .nan, y: 0), .zero])], tolerance: 1) == nil)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var officialGroups = 0
        for filename in ["shirt.json", "fitted-shirt.json", "pants.json", "pencil-skirt.json"] {
            let document = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf:
                root.appendingPathComponent("Fixtures/\(filename)")))
            let before = try encoder.encode(document.pattern.stitches)
            let official = GarmentCodeSeamGuide(stitches: document.pattern.stitches)
            precondition(official.groups.count == document.pattern.stitches.count)
            for (index, stitch) in document.pattern.stitches.enumerated() {
                let group = official.group(id: index)!
                precondition(group.sides == stitch.sides.map { Edge(panel: $0.panel, edge: $0.edge) })
                precondition(group.rightWrong == stitch.rightWrong)
                for side in group.sides {
                    precondition(official.groups(for: side).contains { $0.id == index })
                    precondition(official.groups(forPanel: side.panel).contains { $0.id == index })
                }
            }
            let after = try encoder.encode(document.pattern.stitches)
            precondition(after == before,
                         "Building the display index must not mutate source stitches")
            officialGroups += official.groups.count
        }
        print("PASS: seam display indexes preserve \(officialGroups) official stitch groups; darts, repeated references, right/wrong markers, nearest-edge hit testing and degenerate paths")
    }
}
