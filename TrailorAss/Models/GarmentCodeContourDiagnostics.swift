import Foundation

/// Early, non-mutating witnesses on original source edges. An empty report is
/// not a simple-loop certificate: Bezier/Bezier and circle/circle pairs, touch,
/// overlap and numerically ambiguous intersections remain for later validators.
enum GarmentCodeContourDiagnostics {
    struct Crossing: Codable, Equatable, Sendable {
        let panel: String
        let firstEdge: Int
        let secondEdge: Int
        let firstParameter: Double
        let secondParameter: Double
        let point: GarmentCodePoint
    }
    struct Report: Sendable {
        let crossings: [Crossing]
        let testedPairs: Int
        let unsupportedPairs: Int
        let budgetReached: Bool
    }

    static func inspect(_ document: GarmentCodePatternFile, maximumPairs: Int = 200_000) throws -> Report {
        let panels = try document.geometryPanels()
        var crossings: [Crossing] = [], tested = 0, unsupported = 0
        for name in panels.keys.sorted() {
            let edges = panels[name]!.edges
            for i in edges.indices {
                for j in edges.indices where j > i {
                    guard tested < max(0, maximumPairs) else {
                        return Report(crossings: crossings, testedPairs: tested,
                                      unsupportedPairs: unsupported, budgetReached: true)
                    }
                    tested += 1
                    let first = edges[i], second = edges[j]
                    let roots: [(Double, Double, GarmentCodePoint)]
                    switch (first.curvature?.type, second.curvature?.type) {
                    case (nil, nil): roots = lineLine(first, second)
                    case ("circle", nil): roots = circleLine(first, second)
                    case (nil, "circle"):
                        roots = circleLine(second, first).map { ($0.1, $0.0, $0.2) }
                    default: unsupported += 1; continue
                    }
                    // Adjacent source edges can intersect again away from their
                    // shared endpoint. Test every pair and exclude only roots
                    // near the endpoints, never the entire adjacent pair.
                    for (a, b, point) in roots {
                        crossings.append(Crossing(panel: name, firstEdge: i, secondEdge: j,
                            firstParameter: a, secondParameter: b, point: point))
                    }
                }
            }
        }
        return Report(crossings: crossings, testedPairs: tested,
                      unsupportedPairs: unsupported, budgetReached: false)
    }

    static func messages(_ report: Report, document: GarmentCodePatternFile) -> [String] {
        var seen: Set<String> = []
        let messages = report.crossings.filter { seen.insert($0.panel).inserted }.map {
            "“\(GarmentCodeChinese.panel($0.panel))”第 \($0.firstEdge + 1) 条边与第 \($0.secondEdge + 1) 条边在轮廓内部交叉，当前尺寸组合不能形成可裁剪的裁片。"
        }
        guard !messages.isEmpty else { return [] }
        let design = document.parameters?["design"]?.objectValue
        let bottom: String?
        if case let .string(value)? = design?["meta"]?.objectValue?["bottom"]?.objectValue?["v"] {
            bottom = value
        } else { bottom = nil }
        let hint: String
        if bottom == "SkirtManyPanels" {
            hint = "请减小裙片下摆弧线系数的内凹程度，或调整裙片数与展开量后重新生成。"
        } else if bottom == "GodetSkirt" {
            hint = "请检查插片底边宽、插片高度、相邻插片间距与侧缝装饰切口的组合，避免切口相互重叠。"
        } else {
            hint = "请调整相应裁片的宽度、长度或切口参数后重新生成。"
        }
        return messages + [hint]
    }

    private static let parameterMargin = 1e-7
    private static func interior(_ x: Double) -> Bool {
        x.isFinite && x > parameterMargin && x < 1 - parameterMargin
    }
    private static func interior(_ x: Interval) -> Bool {
        x.finite && x.lo > parameterMargin && x.hi < 1 - parameterMargin
    }
    /// Outward arithmetic encloses the roots of the original stored binary
    /// coordinates. Ill-conditioned or ambiguous cases produce no witness;
    /// a plausible Double root/residual alone must never block valid paper.
    private struct Interval {
        let lo: Double, hi: Double
        init(_ exact: Double) { lo = exact; hi = exact }
        init(_ lower: Double, _ upper: Double) { lo = lower; hi = upper }
        var finite: Bool { lo.isFinite && hi.isFinite && lo <= hi }
        var midpoint: Double { lo * 0.5 + hi * 0.5 }
        static let unknown = Interval(-.infinity, .infinity)
        static func + (a: Self, b: Self) -> Self { .init((a.lo+b.lo).nextDown,(a.hi+b.hi).nextUp) }
        static func - (a: Self, b: Self) -> Self { .init((a.lo-b.hi).nextDown,(a.hi-b.lo).nextUp) }
        static prefix func - (a: Self) -> Self { .init(-a.hi,-a.lo) }
        static func * (a: Self, b: Self) -> Self {
            let p = [a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi]
            guard p.allSatisfy(\.isFinite) else { return .unknown }
            return .init(p.min()!.nextDown,p.max()!.nextUp)
        }
        static func / (a: Self, b: Self) -> Self {
            guard b.finite, b.lo > 0 || b.hi < 0 else { return .unknown }
            return a * .init((1/b.hi).nextDown,(1/b.lo).nextUp)
        }
        func squared() -> Self {
            guard finite else { return .unknown }
            let a = lo*lo, b = hi*hi
            let lower = lo <= 0 && hi >= 0 ? 0 : max(0,min(a,b).nextDown)
            return .init(lower,max(a,b).nextUp)
        }
        func root() -> Self {
            guard finite, lo >= 0 else { return .unknown }
            return .init(max(0,sqrt(lo).nextDown),sqrt(hi).nextUp)
        }
    }
    private struct BoxPoint {
        let x: Interval, y: Interval
        init(_ point: GarmentCodePoint) { x = .init(point.x); y = .init(point.y) }
        init(_ x: Interval, _ y: Interval) { self.x = x; self.y = y }
        static func + (a: Self, b: Self) -> Self { .init(a.x+b.x,a.y+b.y) }
        static func - (a: Self, b: Self) -> Self { .init(a.x-b.x,a.y-b.y) }
        static func * (a: Self, b: Interval) -> Self { .init(a.x*b,a.y*b) }
        static func / (a: Self, b: Interval) -> Self { .init(a.x/b,a.y/b) }
        var leftNormal: Self { .init(-y,x) }
        func dot(_ b: Self) -> Interval { x*b.x+y*b.y }
        func cross(_ b: Self) -> Interval { x*b.y-y*b.x }
        var squaredLength: Interval { x.squared()+y.squared() }
    }
    private static func lineLine(_ a: GarmentCodeGeometryEdge, _ b: GarmentCodeGeometryEdge)
        -> [(Double, Double, GarmentCodePoint)] {
        let u = a.end - a.start, v = b.end - b.start, w = b.start - a.start
        let scale = max(u.length, v.length, w.length)
        guard scale.isFinite, scale > 0 else { return [] }
        let divisor = Interval(scale)
        let x = (BoxPoint(a.end)-BoxPoint(a.start))/divisor
        let y = (BoxPoint(b.end)-BoxPoint(b.start))/divisor
        let z = (BoxPoint(b.start)-BoxPoint(a.start))/divisor
        let denominator = x.cross(y)
        let sBounds = z.cross(y)/denominator, tBounds = z.cross(x)/denominator
        guard interior(sBounds), interior(tBounds) else { return [] }
        let s = sBounds.midpoint, t = tBounds.midpoint
        let p = a.point(at: s), q = b.point(at: t)
        guard p.distance(to: q) <= scale * 1e-9 else { return [] }
        return [(s, t, p)]
    }

    private static func circleLine(_ arc: GarmentCodeGeometryEdge, _ line: GarmentCodeGeometryEdge)
        -> [(Double, Double, GarmentCodePoint)] {
        guard let circle = arc.curvature?.circle else { return [] }
        let chord = arc.end - arc.start, direction = line.end - line.start
        let scale = max(chord.length, direction.length, abs(circle.radius))
        guard scale.isFinite, scale > 0, circle.radius > 0 else { return [] }
        let divisor = Interval(scale)
        let e = (BoxPoint(arc.end)-BoxPoint(arc.start))/divisor
        let d = (BoxPoint(line.end)-BoxPoint(line.start))/divisor
        let chordLength = e.squaredLength.root(), requestedRadius = Interval(circle.radius)/divisor
        guard chordLength.finite, chordLength.lo > 0 else { return [] }
        let halfChord = chordLength*Interval(0.5)
        let radius = Interval(max(requestedRadius.lo,halfChord.lo),max(requestedRadius.hi,halfChord.hi))
        let heightSquared = radius.squared()-e.squaredLength*Interval(0.25)
        // SVG radius correction guarantees nonnegative height; clamping only
        // intersects that known domain with its outward enclosure.
        let height = Interval(max(0,heightSquared.lo),heightSquared.hi).root()
        guard height.finite else { return [] }
        let sign = circle.largeArc == circle.right ? -1.0 : 1.0
        let center = e*Interval(0.5)+(e.leftNormal/chordLength)*(height*Interval(sign))
        let offset = (BoxPoint(line.start)-BoxPoint(arc.start))/divisor-center
        let aa = d.squaredLength, bb = offset.dot(d)*Interval(2), cc = offset.squaredLength-radius.squared()
        let discriminant = bb.squared()-aa*cc*Interval(4)
        guard discriminant.finite, discriminant.lo > 0 else { return [] }
        let root = discriminant.root()
        let q = (bb+(bb.midpoint >= 0 ? root : -root))*Interval(-0.5)
        let zero = BoxPoint(.init(x:0,y:0)), startVector = zero-center, endVector = e-center
        let startAngle = atan2(startVector.y.midpoint,startVector.x.midpoint)
        let endAngle = atan2(endVector.y.midpoint,endVector.x.midpoint)
        var delta = endAngle - startAngle
        if circle.right {
            while delta < 0 { delta += 2 * .pi }
            while delta >= 2 * .pi { delta -= 2 * .pi }
        } else {
            while delta > 0 { delta -= 2 * .pi }
            while delta <= -2 * .pi { delta += 2 * .pi }
        }
        if abs(delta) != .pi && (abs(delta) > .pi) != circle.largeArc { delta += circle.right ? -2 * .pi : 2 * .pi }
        guard abs(delta) > 1e-10 else { return [] }
        var result: [(Double, Double, GarmentCodePoint)] = []
        for tBounds in [q/aa,cc/q].sorted(by: { $0.midpoint < $1.midpoint }) where interior(tBounds) {
            let local = offset+d*tBounds
            // Circle tangent is radial.leftNormal: its determinant with the
            // line equals minus radial.dot(line), not radial.cross(line).
            let crossing = local.dot(d)
            guard crossing.finite, crossing.lo > 0 || crossing.hi < 0 else { continue }
            let sweep = Interval(circle.right ? 1 : -1)
            let fromStart = startVector.cross(local)*sweep, toEnd = local.cross(endVector)*sweep
            guard fromStart.finite, toEnd.finite else { continue }
            let onSelectedArc = circle.largeArc ? fromStart.lo > 0 || toEnd.lo > 0 : fromStart.lo > 0 && toEnd.lo > 0
            guard onSelectedArc else { continue }
            let t = tBounds.midpoint
            // Trigonometry locates the display marker only. Arc membership and
            // transverse interior root were proved above without atan2.
            var angle = atan2(local.y.midpoint,local.x.midpoint)-startAngle
            if delta > 0 { while angle < 0 { angle += 2 * .pi } }
            else { while angle > 0 { angle -= 2 * .pi } }
            let s = angle / delta
            guard interior(s) else { continue }
            result.append((s, t, line.point(at: t)))
        }
        return result
    }
}
