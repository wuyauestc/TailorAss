import Foundation

/// Read-only indexes for displaying the official stitch list. Group IDs and
/// edge references retain their source order; colors and selection are UI state.
struct GarmentCodeSeamGuide {
    struct EdgeKey: Hashable {
        let panel: String
        let edge: Int
    }

    struct Group: Identifiable {
        let id: Int
        let sides: [EdgeKey]
        let rightWrong: Bool

        var number: Int { id + 1 }
        var label: String { "缝\(number)" }
    }

    let groups: [Group]
    private let edgeGroups: [EdgeKey: [Int]]
    private let panelGroups: [String: [Int]]

    init(stitches: [GarmentCodeStitch]) {
        groups = stitches.enumerated().map { index, stitch in
            Group(id: index,
                  sides: stitch.sides.map { EdgeKey(panel: $0.panel, edge: $0.edge) },
                  rightWrong: stitch.rightWrong)
        }
        var byEdge: [EdgeKey: [Int]] = [:]
        var byPanel: [String: [Int]] = [:]
        for group in groups {
            // A dart connects two edges of one panel. Duplicate references in
            // imported data must not make the group appear twice in a list.
            var seenEdges: Set<EdgeKey> = []
            var seenPanels: Set<String> = []
            for side in group.sides {
                if seenEdges.insert(side).inserted { byEdge[side, default: []].append(group.id) }
                if seenPanels.insert(side.panel).inserted { byPanel[side.panel, default: []].append(group.id) }
            }
        }
        edgeGroups = byEdge
        panelGroups = byPanel
    }

    func groups(for edge: EdgeKey) -> [Group] {
        (edgeGroups[edge] ?? []).map { groups[$0] }
    }

    func groups(forPanel panel: String) -> [Group] {
        (panelGroups[panel] ?? []).map { groups[$0] }
    }

    func group(id: Int) -> Group? {
        groups.indices.contains(id) ? groups[id] : nil
    }

    /// `paths` and `point` use the same coordinate system (normally screen
    /// points). The caller supplies only stitched edges. Ties keep input order.
    static func closestEdge(to point: GarmentCodePoint,
                            paths: [(edge: EdgeKey, points: [GarmentCodePoint])],
                            tolerance: Double) -> EdgeKey? {
        guard point.x.isFinite, point.y.isFinite,
              tolerance.isFinite, tolerance >= 0 else { return nil }
        var result: EdgeKey?
        var nearest = tolerance
        func finite(_ p: GarmentCodePoint) -> Bool { p.x.isFinite && p.y.isFinite }
        func consider(_ candidate: Double, edge: EdgeKey) {
            guard candidate.isFinite, candidate <= tolerance,
                  result == nil || candidate < nearest else { return }
            nearest = candidate
            result = edge
        }
        for path in paths {
            if path.points.count == 1, let only = path.points.first, finite(only) {
                consider(point.distance(to: only), edge: path.edge)
            }
            for (start, end) in zip(path.points, path.points.dropFirst()) {
                guard finite(start), finite(end) else { continue }
                let vector = end - start
                let length = vector.length
                guard length.isFinite else { continue }
                if length == 0 {
                    consider(point.distance(to: start), edge: path.edge)
                    continue
                }
                // Divide components directly so even subnormal short segments
                // do not overflow while taking the reciprocal of their length.
                let unit = GarmentCodePoint(x: vector.x / length, y: vector.y / length)
                let projection = (point - start).dot(unit)
                guard !projection.isNaN else { continue }
                let closest: GarmentCodePoint
                if projection <= 0 { closest = start }
                else if projection >= length { closest = end }
                else { closest = start + unit * projection }
                consider(point.distance(to: closest), edge: path.edge)
            }
        }
        return result
    }
}
