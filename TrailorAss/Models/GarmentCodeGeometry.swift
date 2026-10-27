import Foundation

/// Deterministic derivative-free minimization for the nonsmooth tangent-fit
/// objective. No random restarts, finite-difference gradient or platform BLAS.
enum GarmentCodeSimplex {
    struct Result { let point: [Double]; let value: Double; let converged: Bool }
    static func minimize(dimension n: Int, initialStep: Double,
                         objective: ([Double]) -> Double) -> Result {
        precondition(n > 0 && initialStep.isFinite && initialStep > 0)
        struct Vertex { var point: [Double]; var value: Double }
        func evaluate(_ point: [Double]) -> Vertex {
            let value = objective(point)
            return Vertex(point: point, value: value.isFinite ? value : .infinity)
        }
        var simplex = [evaluate(Array(repeating: 0, count: n))]
        for axis in 0..<n {
            var p = Array(repeating: 0.0, count: n)
            p[axis] = initialStep
            simplex.append(evaluate(p))
        }
        func sorted(_ a: Vertex, _ b: Vertex) -> Bool {
            if a.value != b.value { return a.value < b.value }
            return a.point.lexicographicallyPrecedes(b.point)
        }
        for _ in 0..<5000 {
            simplex.sort(by: sorted)
            let best = simplex[0], worst = simplex[n]
            let diameter = simplex.dropFirst().flatMap { vertex in
                zip(vertex.point, best.point).map { abs($0 - $1) }
            }.max() ?? 0
            if best.value.isFinite && diameter <= 1e-7 && worst.value - best.value <= 1e-12 {
                return Result(point: best.point, value: best.value, converged: true)
            }
            var centroid = Array(repeating: 0.0, count: n)
            for vertex in simplex.prefix(n) {
                for axis in 0..<n { centroid[axis] += vertex.point[axis] / Double(n) }
            }
            func fromCentroid(_ scale: Double) -> Vertex {
                evaluate(zip(centroid, worst.point).map { $0 + scale * ($0 - $1) })
            }
            let reflected = fromCentroid(1)
            if reflected.value < best.value {
                let expanded = fromCentroid(2)
                simplex[n] = expanded.value < reflected.value ? expanded : reflected
            } else if reflected.value < simplex[n - 1].value {
                simplex[n] = reflected
            } else {
                let outside = reflected.value < worst.value
                let contracted = fromCentroid(outside ? 0.5 : -0.5)
                if outside ? contracted.value <= reflected.value : contracted.value < worst.value {
                    simplex[n] = contracted
                } else {
                    for index in 1...n {
                        simplex[index] = evaluate(zip(best.point, simplex[index].point).map { $0 + 0.5 * ($1 - $0) })
                    }
                }
            }
        }
        simplex.sort(by: sorted)
        return Result(point: simplex[0].point, value: simplex[0].value, converged: false)
    }
}

/// Unbounded formk/subsm path of L-BFGS-B: factor the compact indefinite
/// matrix as Uᵀ diag(-I, I) U and apply its inverse without forming n×n H.
enum GarmentCodeLBFGSCompact {
    static func direction(gradient: [Double], s: [[Double]], y: [[Double]],
                          curvature: [Double]) -> [Double]? {
        let m = s.count, n = gradient.count
        guard m > 0 else { return gradient.map { -$0 } }
        guard y.count == m, curvature.count == m,
              s.allSatisfy({ $0.count == n }), y.allSatisfy({ $0.count == n }),
              curvature.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        func dot(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let theta = dot(y[m - 1], y[m - 1]) / curvature[m - 1]
        guard theta > 0, theta.isFinite else { return nil }
        var u = Array(repeating: Array(repeating: 0.0, count: 2 * m), count: 2 * m)
        for j in 0..<m {
            for i in 0...j { u[i][j] = dot(y[i], y[j]) / theta }
            u[j][j] += curvature[j]
            for i in j..<m { u[i][m + j] = dot(s[j], y[i]) }
        }
        // Column-oriented upper Cholesky, following LINPACK DPOFA order.
        func factor(_ offset: Int) -> Bool {
            for j in 0..<m {
                var diagonalSum = 0.0
                for k in 0..<j {
                    var product = 0.0
                    for i in 0..<k { product += u[offset + i][offset + k] * u[offset + i][offset + j] }
                    let t = (u[offset + k][offset + j] - product) / u[offset + k][offset + k]
                    u[offset + k][offset + j] = t
                    diagonalSum += t * t
                }
                let diagonal = u[offset + j][offset + j] - diagonalSum
                guard diagonal > 0, diagonal.isFinite else { return false }
                u[offset + j][offset + j] = sqrt(diagonal)
            }
            return true
        }
        guard factor(0) else { return nil }
        for column in m..<(2 * m) {
            for row in 0..<m {
                var product = 0.0
                for k in 0..<row { product += u[k][row] * u[k][column] }
                u[row][column] = (u[row][column] - product) / u[row][row]
            }
        }
        for i in m..<(2 * m) {
            for j in i..<(2 * m) {
                for k in 0..<m { u[i][j] += u[k][i] * u[k][j] }
            }
        }
        guard factor(m) else { return nil }
        var d = gradient.map { -$0 }
        var v = y.map { dot($0, d) } + s.map { theta * dot($0, d) }
        for row in 0..<(2 * m) {
            var product = 0.0
            for k in 0..<row { product += u[k][row] * v[k] }
            v[row] = (v[row] - product) / u[row][row]
        }
        for i in 0..<m { v[i] = -v[i] }
        for row in (0..<(2 * m)).reversed() {
            v[row] /= u[row][row]
            for k in 0..<row { v[k] -= v[row] * u[k][row] }
        }
        for j in 0..<m {
            for i in 0..<n { d[i] = d[i] + y[j][i] * v[j] / theta + s[j][i] * v[m + j] }
        }
        return d.map { $0 / theta }
    }
}

/// 21-point Gauss–Kronrod integration used for the cubic fitting objective.
/// Abscissae/weights and local error estimate follow QUADPACK dqk21:
/// https://netlib.org/quadpack/dqk21.f (Piessens / de Doncker).
/// Largest-error subdivision uses scipy.integrate.quad's default tolerances.
enum GarmentCodeQuadrature {
    private static let nodes = [0.9956571630258081, 0.9739065285171717,
        0.9301574913557082, 0.8650633666889845, 0.780817726586417,
        0.6794095682990244, 0.5627571346686047, 0.4333953941292472,
        0.2943928627014602, 0.1488743389816312]
    private static let weights = [0.011694638867371874, 0.03255816230796473,
        0.054755896574351996, 0.07503967481091995, 0.09312545458369761,
        0.10938715880229764, 0.12349197626206585, 0.13470921731147333,
        0.14277593857706008, 0.14773910490133849, 0.1494455540029169]
    private static let gauss = [0.06667134430868814, 0.1494513491505806,
        0.21908636251598204, 0.26926671930999635, 0.29552422471475287]
    private struct Interval {
        let a: Double, b: Double, value: Double, error: Double
    }
    static func integrate(_ f: (Double) -> Double) -> Double {
        func evaluate(_ a: Double, _ b: Double) -> Interval {
            let center = (a + b) * 0.5, half = (b - a) * 0.5
            let fc = f(center)
            var kronrod = weights[10] * fc, g = 0.0
            var absolute = abs(kronrod)
            var left = Array(repeating: 0.0, count: 10), right = left
            // Match dqk21's summation order: Gauss nodes, then extra nodes.
            for i in [1, 3, 5, 7, 9, 0, 2, 4, 6, 8] {
                left[i] = f(center - half * nodes[i])
                right[i] = f(center + half * nodes[i])
                let sum = left[i] + right[i]
                if i % 2 == 1 { g += gauss[i / 2] * sum }
                kronrod += weights[i] * sum
                absolute += weights[i] * (abs(left[i]) + abs(right[i]))
            }
            let mean = kronrod * 0.5
            var variation = weights[10] * abs(fc - mean)
            for i in 0..<10 {
                variation += weights[i] * (abs(left[i] - mean) + abs(right[i] - mean))
            }
            variation *= half
            absolute *= half
            var error = abs((kronrod - g) * half)
            if variation != 0 && error != 0 {
                error = variation * min(1, pow(200 * error / variation, 1.5))
            }
            error = max(error, 50 * Double.ulpOfOne * absolute)
            return Interval(a: a, b: b, value: kronrod * half, error: error)
        }
        var intervals = [evaluate(0, 1)]
        var value = intervals[0].value, error = intervals[0].error
        for _ in 1..<1000 {
            if error <= max(1e-12, 1.49e-8 * abs(value)) { break }
            let index = intervals.indices.max { intervals[$0].error < intervals[$1].error }!
            let old = intervals[index], mid = (old.a + old.b) * 0.5
            let l = evaluate(old.a, mid), r = evaluate(mid, old.b)
            value += l.value + r.value - old.value
            error += l.error + r.error - old.error
            intervals[index] = l
            intervals.append(r)
        }
        // QUADPACK returns the sum of the final partition, not the running sum.
        return intervals.reduce(0) { $0 + $1.value }
    }
}

/// Pattern-only geometry primitives translated from GarmentCode/PyGarment.
/// Coordinates are centimetres in panel-local 2D space. These types deliberately
/// exclude 3D placement, draping and simulator dependencies.
nonisolated struct GarmentCodePoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    static let zero = GarmentCodePoint(x: 0, y: 0)
    static func + (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: Self, rhs: Double) -> Self { .init(x: lhs.x * rhs, y: lhs.y * rhs) }
    var length: Double { hypot(x, y) }
    var normalized: Self { length > 1e-12 ? self * (1 / length) : .zero }
    var leftNormal: Self { .init(x: -y, y: x) }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y }
    func distance(to other: Self) -> Double { (self - other).length }

    func rotated(by angle: Double, around pivot: Self = .zero) -> Self {
        let offset = self - pivot
        let cosine = cos(angle), sine = sin(angle)
        return .init(x: pivot.x + offset.x * cosine - offset.y * sine,
                     y: pivot.y + offset.x * sine + offset.y * cosine)
    }

    func reflected(acrossLineFrom start: Self, to end: Self) -> Self {
        let direction = (end - start).normalized
        guard direction.length > 1e-12 else { return self }
        let offset = self - start
        return start + direction * (2 * offset.dot(direction)) - offset
    }
}

/// Swift port of SciPy's MINPACK DCSRCH/`dcstep` Wolfe-1 line search. The
/// upstream tangent fitter calls `minimize(BFGS)` which selects Wolfe-1 in
/// SciPy; matching this line search avoids a noticeably different control point
/// when the tangent-only objective has a shallow, nearly flat valley.
private enum GarmentCodeWolfe1 {
    private struct StepState {
        var bracketed = false
        var stage = 1
        var stx = 0.0, fx = 0.0, gx = 0.0
        var sty = 0.0, fy = 0.0, gy = 0.0
        var stmin = 0.0, stmax = 0.0
        var width = 0.0, width1 = 0.0
    }

    static func search(alpha initialAlpha: Double, valueAtZero: Double, slopeAtZero: Double,
                       sufficientDecrease: Double = 1e-4,
                       curvature: Double = 0.9,
                       relativeTolerance: Double = 1e-14,
                       minimumStep: Double = 1e-100, maximumStep: Double = 1e100,
                       acceptWarning: Bool = false, maximumIterations: Int = 100,
                       value: (Double) -> Double, slope: (Double) -> Double) -> Double? {
        guard initialAlpha > 0, slopeAtZero < 0 else { return nil }
        let c1 = sufficientDecrease, c2 = curvature, xtol = relativeTolerance
        let gtest = c1 * slopeAtZero
        var state = StepState()
        state.fx = valueAtZero; state.gx = slopeAtZero
        state.fy = valueAtZero; state.gy = slopeAtZero
        state.width = maximumStep - minimumStep; state.width1 = 2 * state.width
        state.stmax = initialAlpha * 5
        var alpha = initialAlpha
        for _ in 0..<maximumIterations {
            let f = value(alpha), g = slope(alpha)
            let ftest = valueAtZero + alpha * gtest
            if state.stage == 1 && f <= ftest && g >= 0 { state.stage = 2 }
            if f <= ftest && abs(g) <= c2 * -slopeAtZero { return alpha }
            let warning = (state.bracketed && (alpha <= state.stmin || alpha >= state.stmax ||
                state.stmax - state.stmin <= xtol * state.stmax)) ||
                (alpha == maximumStep && f <= ftest && g <= gtest) ||
                (alpha == minimumStep && (f > ftest || g >= gtest))
            if warning { return acceptWarning ? alpha : nil }

            var fm = f, fxm = state.fx, fym = state.fy
            var gm = g, gxm = state.gx, gym = state.gy
            if state.stage == 1 && f <= state.fx && f > ftest {
                fm -= alpha * gtest
                fxm -= state.stx * gtest; fym -= state.sty * gtest
                gm -= gtest; gxm -= gtest; gym -= gtest
            }
            var proposed = alpha
            dcstep(stx: &state.stx, fx: &fxm, gx: &gxm,
                   sty: &state.sty, fy: &fym, gy: &gym,
                   stp: &proposed, fp: fm, gp: gm, bracketed: &state.bracketed,
                   minimum: state.stmin, maximum: state.stmax)
            if state.stage == 1 && f <= state.fx && f > ftest {
                state.fx = fxm + state.stx * gtest
                state.fy = fym + state.sty * gtest
                state.gx = gxm + gtest; state.gy = gym + gtest
            } else {
                state.fx = fxm; state.fy = fym
                state.gx = gxm; state.gy = gym
            }
            if state.bracketed {
                if abs(state.sty - state.stx) >= 0.66 * state.width1 {
                    proposed = state.stx + 0.5 * (state.sty - state.stx)
                }
                state.width1 = state.width; state.width = abs(state.sty - state.stx)
                state.stmin = min(state.stx, state.sty); state.stmax = max(state.stx, state.sty)
            } else {
                state.stmin = proposed + 1.1 * (proposed - state.stx)
                state.stmax = proposed + 4 * (proposed - state.stx)
            }
            proposed = min(maximumStep, max(minimumStep, proposed))
            if state.bracketed && (proposed <= state.stmin || proposed >= state.stmax ||
                state.stmax - state.stmin <= xtol * state.stmax) { proposed = state.stx }
            alpha = proposed
        }
        return nil
    }

    private static func dcstep(stx: inout Double, fx: inout Double, gx: inout Double,
                               sty: inout Double, fy: inout Double, gy: inout Double,
                               stp: inout Double, fp: Double, gp: Double,
                               bracketed: inout Bool, minimum: Double, maximum: Double) {
        let sgnd = (gp == 0 ? 0 : gp.sign == gx.sign ? 1.0 : -1.0)
        var stpf = stp
        if fp > fx {
            let theta = 3 * (fx - fp) / (stp - stx) + gx + gp
            let scale = max(abs(theta), abs(gx), abs(gp))
            let gamma = scale * sqrt(max(0, (theta / scale) * (theta / scale) - (gx / scale) * (gp / scale)))
                * (stp < stx ? -1 : 1)
            let p = (gamma - gx) + theta, q = ((gamma - gx) + gamma) + gp
            let cubic = stx + (p / q) * (stp - stx)
            let quadratic = stx + ((gx / ((fx - fp) / (stp - stx) + gx)) / 2) * (stp - stx)
            stpf = abs(cubic - stx) <= abs(quadratic - stx) ? cubic : cubic + (quadratic - cubic) / 2
            bracketed = true
        } else if sgnd < 0 {
            let theta = 3 * (fx - fp) / (stp - stx) + gx + gp
            let scale = max(abs(theta), abs(gx), abs(gp))
            var gamma = scale * sqrt(max(0, (theta / scale) * (theta / scale) - (gx / scale) * (gp / scale)))
            if stp > stx { gamma = -gamma }
            let p = (gamma - gp) + theta, q = ((gamma - gp) + gamma) + gx
            let cubic = stp + (p / q) * (stx - stp)
            let secant = stp + gp / (gp - gx) * (stx - stp)
            stpf = abs(cubic - stp) > abs(secant - stp) ? cubic : secant
            bracketed = true
        } else if abs(gp) < abs(gx) {
            let theta = 3 * (fx - fp) / (stp - stx) + gx + gp
            let scale = max(abs(theta), abs(gx), abs(gp))
            var gamma = scale * sqrt(max(0, (theta / scale) * (theta / scale) - (gx / scale) * (gp / scale)))
            if stp > stx { gamma = -gamma }
            let p = (gamma - gp) + theta, q = (gamma + (gx - gp)) + gamma
            let ratio = p / q
            let cubic = ratio < 0 && gamma != 0 ? stp + ratio * (stx - stp) : (stp > stx ? maximum : minimum)
            let secant = stp + gp / (gp - gx) * (stx - stp)
            if bracketed {
                stpf = abs(cubic - stp) < abs(secant - stp) ? cubic : secant
                stpf = stp > stx ? min(stp + 0.66 * (sty - stp), stpf) : max(stp + 0.66 * (sty - stp), stpf)
            } else {
                stpf = abs(cubic - stp) > abs(secant - stp) ? cubic : secant
                stpf = min(maximum, max(minimum, stpf))
            }
        } else if bracketed {
            let theta = 3 * (fp - fy) / (sty - stp) + gy + gp
            let scale = max(abs(theta), abs(gy), abs(gp))
            var gamma = scale * sqrt(max(0, (theta / scale) * (theta / scale) - (gy / scale) * (gp / scale)))
            if stp > sty { gamma = -gamma }
            let p = (gamma - gp) + theta, q = ((gamma - gp) + gamma) + gy
            stpf = stp + (p / q) * (sty - stp)
        } else {
            stpf = stp > stx ? maximum : minimum
        }
        if fp > fx {
            sty = stp; fy = fp; gy = gp
        } else {
            if sgnd < 0 { sty = stx; fy = fx; gy = gx }
            stx = stp; fx = fp; gx = gp
        }
        stp = stpf
    }
}

/// A PyGarment Edge/CurveEdge/CircleEdge-compatible edge. Bezier control
/// points use GarmentCode's edge-local coordinates: x along the chord, y along
/// its left normal. Circle parameters match the official serialized tuple.
struct GarmentCodeGeometryEdge: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var start: GarmentCodePoint
    var end: GarmentCodePoint
    var curvature: GarmentCodeCurvature?
    var label: String?

    nonisolated var chordLength: Double { start.distance(to: end) }

    nonisolated func point(at t: Double) -> GarmentCodePoint {
        let t = min(1, max(0, t))
        guard let curvature else { return start + (end - start) * t }
        switch curvature.type {
        case "quadratic":
            guard let cp = curvature.params?.first.map({ Self.absolute($0, from: start, to: end) }) else { return start + (end - start) * t }
            let u = 1 - t
            return start * (u * u) + cp * (2 * u * t) + end * (t * t)
        case "cubic":
            guard let params = curvature.params, params.count == 2 else { return start + (end - start) * t }
            let c1 = Self.absolute(params[0], from: start, to: end)
            let c2 = Self.absolute(params[1], from: start, to: end)
            let u = 1 - t
            return start * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + end * (t * t * t)
        case "circle":
            return Self.circlePoint(start: start, end: end, curvature: curvature, t: t)
        default:
            return start + (end - start) * t
        }
    }

    nonisolated func length(tolerance: Double = 1e-8) -> Double {
        guard let curvature else { return chordLength }
        if curvature.type == "circle", let circle = curvature.circle,
           let arc = Self.circleArc(start: start, end: end, radius: circle.radius,
                                    largeArc: circle.largeArc, right: circle.right) {
            return abs(arc.delta) * arc.radius
        }
        // A midpoint chord test incorrectly treats symmetric S-curves as
        // straight lines. Integrate analytic speed instead, with compulsory
        // initial subdivision so an inflection cannot hide the curvature.
        guard let controls = curvature.params else { return chordLength }
        let points = [start] + controls.map { Self.absolute($0, from: start, to: end) } + [end]
        func speed(_ t: Double) -> Double {
            let u = 1 - t
            if points.count == 3 {
                return ((points[1] - points[0]) * (2 * u) +
                        (points[2] - points[1]) * (2 * t)).length
            }
            guard points.count == 4 else { return chordLength }
            return ((points[1] - points[0]) * (3 * u * u) +
                    (points[2] - points[1]) * (6 * u * t) +
                    (points[3] - points[2]) * (3 * t * t)).length
        }
        func integrate(_ a: Double, _ b: Double, _ fa: Double, _ fm: Double, _ fb: Double,
                       _ whole: Double, _ epsilon: Double, _ depth: Int) -> Double {
            let m = (a + b) / 2
            let fl = speed((a + m) / 2), fr = speed((m + b) / 2)
            let left = (m - a) * (fa + 4 * fl + fm) / 6
            let right = (b - m) * (fm + 4 * fr + fb) / 6
            let delta = left + right - whole
            if depth >= 24 || (depth >= 4 && abs(delta) <= 15 * epsilon) {
                return left + right + delta / 15
            }
            return integrate(a, m, fa, fl, fm, left, epsilon / 2, depth + 1) +
                integrate(m, b, fm, fr, fb, right, epsilon / 2, depth + 1)
        }
        let fa = speed(0), fm = speed(0.5), fb = speed(1)
        return integrate(0, 1, fa, fm, fb, (fa + 4 * fm + fb) / 6,
                         max(1e-12, tolerance), 0)
    }

    func sample(maxSegmentLength: Double = 0.75, minimumSegments: Int = 2) -> [GarmentCodePoint] {
        // Cap in floating point BEFORE converting to Int: imported, finite
        // coordinates can still describe a length beyond Int.max.
        let requested = ceil(length() / max(0.05, maxSegmentLength))
        let bounded = requested.isFinite ? min(512, max(2, requested)) : 512
        let n = max(min(512, max(2, minimumSegments)), Int(bounded))
        return (0...n).map { point(at: Double($0) / Double(n)) }
    }

    func reversed() -> Self {
        var result = self
        swap(&result.start, &result.end)
        if let curvature {
            if curvature.type == "circle", let circle = curvature.circle {
                result.curvature = GarmentCodeCurvature(circleRadius: circle.radius,
                                                        largeArc: circle.largeArc,
                                                        right: !circle.right)
            } else if let params = curvature.params {
                result.curvature = GarmentCodeCurvature(type: curvature.type,
                                                        params: params.reversed().map { [1 - $0[0], -$0[1]] })
            }
        }
        return result
    }

    func translated(by delta: GarmentCodePoint) -> Self {
        var result = self
        result.start = start + delta
        result.end = end + delta
        return result
    }

    mutating func moveEndpoints(to newStart: GarmentCodePoint, newEnd: GarmentCodePoint) {
        let oldLength = chordLength
        let newLength = newStart.distance(to: newEnd)
        if let curve = curvature, curve.type == "circle", let arc = curve.circle, oldLength > 1e-12 {
            curvature = .init(circleRadius: arc.radius * newLength / oldLength,
                              largeArc: arc.largeArc, right: arc.right)
        }
        start = newStart
        end = newEnd
    }

    func rotated(by angle: Double, around pivot: GarmentCodePoint) -> Self {
        var result = self
        result.start = start.rotated(by: angle, around: pivot)
        result.end = end.rotated(by: angle, around: pivot)
        return result
    }

    func reflected(acrossLineFrom axisStart: GarmentCodePoint,
                   to axisEnd: GarmentCodePoint) -> Self {
        var result = self
        result.start = start.reflected(acrossLineFrom: axisStart, to: axisEnd)
        result.end = end.reflected(acrossLineFrom: axisStart, to: axisEnd)
        if let curve = curvature {
            if curve.type == "circle", let circle = curve.circle {
                result.curvature = .init(circleRadius: circle.radius,
                                         largeArc: circle.largeArc, right: !circle.right)
            } else if let params = curve.params {
                result.curvature = .init(type: curve.type,
                                         params: params.map { [$0[0], -$0[1]] })
            }
        }
        return result
    }

    func split(at parameter: Double, idPrefix: String? = nil) -> (Self, Self) {
        let t = min(1 - 1e-8, max(1e-8, parameter))
        let splitPoint = point(at: t)
        let prefix = idPrefix ?? id
        if curvature?.type == "circle", let circle = curvature?.circle,
           let arc = Self.circleArc(start: start, end: end, radius: circle.radius,
                                    largeArc: circle.largeArc, right: circle.right) {
            let d0 = arc.delta * t
            let d1 = arc.delta - d0
            let first = Self(id: "\(prefix)-a", start: start, end: splitPoint,
                             curvature: .init(circleRadius: arc.radius, largeArc: abs(d0) > .pi,
                                              right: circle.right), label: label)
            let second = Self(id: "\(prefix)-b", start: splitPoint, end: end,
                              curvature: .init(circleRadius: arc.radius, largeArc: abs(d1) > .pi,
                                               right: circle.right), label: label)
            return (first, second)
        }
        let left = Self.subcurve(edge: self, lower: 0, upper: t)
        let right = Self.subcurve(edge: self, lower: t, upper: 1)
        return (Self(id: "\(prefix)-a", start: start, end: splitPoint,
                     curvature: Self.curvature(for: left), label: label),
                Self(id: "\(prefix)-b", start: splitPoint, end: end,
                     curvature: Self.curvature(for: right), label: label))
    }

    static func curvature(for points: [GarmentCodePoint]) -> GarmentCodeCurvature? {
        guard points.count > 2 else { return nil }
        let start = points[0], end = points[points.count - 1]
        let controls = points.dropFirst().dropLast().map { relative($0, from: start, to: end) }
        return .init(type: controls.count == 1 ? "quadratic" : "cubic", params: controls)
    }

    /// Pattern-only port of PyGarment `curve_match_tangents`. The source
    /// curve's endpoints and overall direction are retained while its two
    /// controls and endpoint are adjusted to match requested tangents and
    /// preserve the requested arc length. GarmentCode invokes SciPy
    /// L-BFGS-B without bounds. The native path retains its objective but uses
    /// deterministic simplex search: max-curvature is nonsmooth and tiny finite
    /// differences made the upstream optimizer sensitive to one-ULP inputs.
    static func cubicMatchingTangents(_ source: Self,
                                      targetStartTangent: GarmentCodePoint,
                                      targetEndTangent: GarmentCodePoint,
                                      targetLength: Double? = nil,
                                      id: String? = nil,
                                      absoluteControlPoints: [GarmentCodePoint]? = nil,
                                      useLegacyOptimizer: Bool = false,
                                      objectiveObserver: ((Double) -> Void)? = nil,
                                      iterationObserver: (([Double]) -> Void)? = nil) throws -> Self {
        guard source.curvature?.type == "cubic",
              let relativeControls = source.curvature?.params, relativeControls.count == 2,
              source.chordLength > 1e-10 else {
            throw GarmentCodeGeometryError.invalidPanel(source.id)
        }
        let initial = absoluteControlPoints ?? [source.start,
                       absolute(relativeControls[0], from: source.start, to: source.end),
                       absolute(relativeControls[1], from: source.start, to: source.end),
                       source.end]
        guard initial.count == 4, initial.first == source.start, initial.last == source.end,
              initial.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw GarmentCodeGeometryError.invalidPanel(source.id)
        }
        func numpyUnit(_ p: GarmentCodePoint) -> GarmentCodePoint {
            let norm = sqrt(p.x * p.x + p.y * p.y)
            return norm > 1e-12 ? .init(x: p.x / norm, y: p.y / norm) : .zero
        }
        let direction = numpyUnit(source.end - source.start)
        let tangent0 = numpyUnit(targetStartTangent)
        let tangent1 = numpyUnit(targetEndTangent)
        let desiredLength = targetLength ?? source.length()
        if ProcessInfo.processInfo.environment["GARMENTCODE_FIT_INPUTS"] == "1" {
            let record: [String: Any] = ["source": initial.map { [$0.x, $0.y] },
                "start_tangent": [targetStartTangent.x, targetStartTangent.y],
                "end_tangent": [targetEndTangent.x, targetEndTangent.y], "length": desiredLength]
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
                FileHandle.standardError.write(Data("FIT_INPUT ".utf8) + data + Data("\n".utf8))
            }
        }
        guard desiredLength.isFinite, desiredLength > 0,
              tangent0.length > 0, tangent1.length > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }

        func control(_ shift: [Double]) -> [GarmentCodePoint] {
            [initial[0],
             initial[1] + .init(x: shift[0], y: shift[1]),
             initial[2] + .init(x: shift[2], y: shift[3]),
             initial[3] + direction * shift[4]]
        }
        var objectiveEvaluations = 0
        func objective(_ shift: [Double]) -> Double {
            objectiveEvaluations += 1
            let points = control(shift)
            func derivatives(_ t: Double) -> (GarmentCodePoint, GarmentCodePoint) {
                let u = 1 - t
                let first = (points[1] - points[0]) * 3 * (u * u) +
                    (points[2] - points[1]) * 6 * u * t +
                    (points[3] - points[2]) * 3 * (t * t)
                let second = ((points[2] - points[1] * 2 + points[0]) * u +
                    (points[3] - points[2] * 2 + points[1]) * t) * 6
                return (first, second)
            }
            let length = GarmentCodeQuadrature.integrate { derivatives($0).0.length }
            var maximumCurvature = 0.0
            for index in 0..<70 {
                let (first, second) = derivatives(index == 69 ? 1 : Double(index) * (1.0 / 69))
                let speed = sqrt(first.x * first.x + first.y * first.y)
                if speed > 1e-10 {
                    maximumCurvature = max(maximumCurvature,
                        abs(first.x * second.y - first.y * second.x) / pow(speed, 3))
                }
            }
            func complexUnit(_ p: GarmentCodePoint) -> GarmentCodePoint {
                let norm = p.length
                return .init(x: p.x / norm, y: p.y / norm)
            }
            let firstDirection = complexUnit(derivatives(0).0)
            let lastDirection = complexUnit(derivatives(1).0)
            let lengthDifference = pow(length - desiredLength, 2)
            return lengthDifference + pow(firstDirection.distance(to: tangent0), 2) +
                pow(lastDirection.distance(to: tangent1), 2) + maximumCurvature * maximumCurvature +
                0.001 * (shift[4] * shift[4])
        }
        if !useLegacyOptimizer {
            let fit = GarmentCodeSimplex.minimize(dimension: 5,
                initialStep: max(1, desiredLength * 0.05), objective: objective)
            let points = control(fit.point)
            guard fit.converged, fit.value.isFinite,
                  let resultCurvature = curvature(for: points) else {
                throw GarmentCodeProgramError.curveFitDidNotConverge
            }
            objectiveObserver?(fit.value)
            return .init(id: id ?? source.id, start: points[0], end: points[3],
                         curvature: resultCurvature, label: source.label)
        }
        // Kept solely for explicit regression diagnostics, not the app route.
        func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
            zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
        }
        func gradient(_ values: [Double]) -> [Double] {
            let base = objective(values)
            return values.indices.map { index in
                var shifted = values
                shifted[index] += 1e-8
                return (objective(shifted) - base) / (shifted[index] - values[index])
            }
        }
        func add(_ lhs: [Double], _ rhs: [Double], scale: Double = 1) -> [Double] {
            zip(lhs, rhs).map { $0.0 + scale * $0.1 }
        }
        var optimum = Array(repeating: 0.0, count: 5)
        var value = objective(optimum)
        var grad = gradient(optimum)
        if ProcessInfo.processInfo.environment["GARMENTCODE_OPTIMIZER_TRACE"] == "1" {
            FileHandle.standardError.write(Data("FIT initial objective=\(value) gradient=\(grad)\n".utf8))
        }
        var sHistory: [[Double]] = []
        var yHistory: [[Double]] = []
        var curvatureHistory: [Double] = []
        var completedIterations = 0
        for iteration in 0..<15000 {
            completedIterations = iteration
            if grad.map(abs).max()! <= 1e-5 { break }
            guard let compactDirection = GarmentCodeLBFGSCompact.direction(
                gradient: grad, s: sHistory, y: yHistory, curvature: curvatureHistory) else {
                sHistory.removeAll(); yHistory.removeAll(); curvatureHistory.removeAll()
                continue
            }
            // subsm updates the candidate point, then mainlb subtracts x to
            // recover d. Retain that rounding path for the compact solve.
            var fullStepPoint = add(optimum, compactDirection)
            var direction = zip(fullStepPoint, optimum).map { $0 - $1 }
            if dot(direction, grad) >= -1e-16 {
                direction = grad.map { -$0 }
                fullStepPoint = add(optimum, direction)
                sHistory.removeAll(); yHistory.removeAll(); curvatureHistory.removeAll()
            }
            func trial(_ alpha: Double) -> [Double] {
                // lnsrlb copies the subspace candidate for a full step instead
                // of subtracting/adding x again, which can lose an ulp.
                alpha == 1 ? fullStepPoint : add(optimum, direction, scale: alpha)
            }
            // With no bounds L-BFGS-B normalizes its first displacement to
            // unit length; alpha may exceed 1 when the gradient is small.
            var step = iteration == 0 ? min(1e10, 1 / max(sqrt(dot(direction, direction)), 1e-15)) : 1.0
            var candidate = optimum
            var candidateValue = value
            var candidateGradient = grad
            var accepted = false
            if let wolfeStep = GarmentCodeWolfe1.search(
                alpha: step, valueAtZero: value, slopeAtZero: dot(grad, direction),
                sufficientDecrease: 1e-3, curvature: 0.9,
                relativeTolerance: 0.1, minimumStep: 0, maximumStep: 1e10,
                acceptWarning: true, maximumIterations: 20,
                value: { objective(trial($0)) },
                slope: { dot(gradient(trial($0)), direction) }) {
                step = wolfeStep
                candidate = trial(step)
                candidateValue = objective(candidate)
                candidateGradient = gradient(candidate)
                accepted = true
            }
            if !accepted {
                // L-BFGS-B restores the old iterate, clears its correction
                // memory and retries; an Armijo fallback is a different solver.
                guard !sHistory.isEmpty else { break }
                sHistory.removeAll(); yHistory.removeAll(); curvatureHistory.removeAll()
                continue
            }
            let s = direction.map { $0 * step }
            let y = zip(candidateGradient, grad).map { $0.0 - $0.1 }
            let curvature = (dot(candidateGradient, direction) - dot(grad, direction)) * step
            if curvature > Double.ulpOfOne * (-dot(grad, direction) * step) {
                if sHistory.count == 10 {
                    sHistory.removeFirst(); yHistory.removeFirst(); curvatureHistory.removeFirst()
                }
                sHistory.append(s); yHistory.append(y); curvatureHistory.append(curvature)
            }
            let improvement = value - candidateValue
            let convergenceScale = max(1, abs(value), abs(candidateValue))
            optimum = candidate; value = candidateValue; grad = candidateGradient
            iterationObserver?(optimum)
            if improvement <= 2.220446049250313e-9 * convergenceScale { break }
            if objectiveEvaluations > 15000 { break }
        }
        let points = control(optimum)
        if ProcessInfo.processInfo.environment["GARMENTCODE_OPTIMIZER_TRACE"] == "1" {
            let line = "FIT iterations=\(completedIterations) objective=\(value) gradient=\(grad.map(abs).max()!) shift=\(optimum)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        let finalCurvature = curvature(for: points)
        guard value.isFinite, let finalCurvature else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        return .init(id: id ?? source.id, start: points[0], end: points[3],
                     curvature: finalCurvature, label: source.label)
    }

    static func subcurve(edge: Self, lower: Double, upper: Double) -> [GarmentCodePoint] {
        // De Casteljau at both boundaries yields the exact Bezier subcurve.
        let controls: [GarmentCodePoint]
        if edge.curvature?.type == "quadratic", let p = edge.curvature?.params?.first {
            controls = [edge.start, absolute(p, from: edge.start, to: edge.end), edge.end]
        } else if edge.curvature?.type == "cubic", let params = edge.curvature?.params, params.count == 2 {
            controls = [edge.start, absolute(params[0], from: edge.start, to: edge.end),
                        absolute(params[1], from: edge.start, to: edge.end), edge.end]
        } else {
            return [edge.point(at: lower), edge.point(at: upper)]
        }
        let atUpper = splitBezier(controls, t: upper).0
        if lower <= 0 { return atUpper }
        return splitBezier(atUpper, t: lower / upper).1
    }

    private static func splitBezier(_ points: [GarmentCodePoint], t: Double) -> ([GarmentCodePoint], [GarmentCodePoint]) {
        var levels = [points]
        while let last = levels.last, last.count > 1 {
            levels.append(zip(last, last.dropFirst()).map { $0 * (1 - t) + $1 * t })
        }
        let left = levels.enumerated().map { $0.element[0] }
        let right = levels.enumerated().reversed().map { $0.element.last! }
        return (left, right)
    }

    private static func relative(_ point: GarmentCodePoint, from start: GarmentCodePoint, to end: GarmentCodePoint) -> [Double] {
        let chord = end - start
        let offset = point - start
        let denominator = max(chord.dot(chord), 1e-18)
        return [offset.dot(chord) / denominator, offset.dot(chord.leftNormal) / denominator]
    }

    static func relativeCoordinates(_ point: GarmentCodePoint,
                                    from start: GarmentCodePoint,
                                    to end: GarmentCodePoint) -> [Double] {
        relative(point, from: start, to: end)
    }

    /// PyGarment `CurveEdgeFactory.curve_from_tangents` port. Tangent vectors
    /// are expressed in garment coordinates and normalized after conversion to
    /// the edge-local frame; the control-point objective matches upstream's
    /// squared unit-tangent error for a quadratic Bezier on (0,0)→(1,0).
    static func quadraticFromTangents(id: String,
                                      start: GarmentCodePoint,
                                      end: GarmentCodePoint,
                                      startTangent: GarmentCodePoint? = nil,
                                      endTangent: GarmentCodePoint? = nil,
                                      initialGuess: GarmentCodePoint = .init(x: 0.5, y: 0)) -> Self {
        let chord = end - start
        let chordSquared = chord.dot(chord)
        guard chordSquared > 1e-18 else { return .init(id: id, start: start, end: end) }
        func localUnit(_ vector: GarmentCodePoint?) -> GarmentCodePoint? {
            guard let vector else { return nil }
            let local = GarmentCodePoint(x: vector.dot(chord) / chordSquared,
                                         y: vector.dot(chord.leftNormal) / chordSquared).normalized
            return local.length > 1e-12 ? local : nil
        }
        let targetStart = localUnit(startTangent)
        let targetEnd = localUnit(endTangent)
        func objective(_ p: GarmentCodePoint) -> Double {
            var value = 0.0
            if let targetStart {
                let tangent = p.normalized
                value += pow(tangent.x - targetStart.x, 2) + pow(tangent.y - targetStart.y, 2)
            }
            if let targetEnd {
                let tangent = (GarmentCodePoint(x: 1, y: 0) - p).normalized
                value += pow(tangent.x - targetEnd.x, 2) + pow(tangent.y - targetEnd.y, 2)
            }
            return value
        }
        func gradient(_ p: GarmentCodePoint) -> GarmentCodePoint {
            // scipy.optimize.minimize(BFGS)'s default forward finite difference.
            let h = 1.4901161193847656e-8
            return .init(x: (objective(.init(x: p.x + h, y: p.y)) - objective(p)) / h,
                         y: (objective(.init(x: p.x, y: p.y + h)) - objective(p)) / h)
        }
        var point = initialGuess
        var inverse = [[1.0, 0.0], [0.0, 1.0]]
        var grad = gradient(point)
        // SciPy initializes this estimate once, then carries the preceding
        // objective value between iterations of its Wolfe line search.
        var previousValue = objective(point) + hypot(grad.x, grad.y) / 2
        for _ in 0..<400 {
            if max(abs(grad.x), abs(grad.y)) <= 1e-5 { break }
            let direction = GarmentCodePoint(
                x: -(inverse[0][0] * grad.x + inverse[0][1] * grad.y),
                y: -(inverse[1][0] * grad.x + inverse[1][1] * grad.y))
            let slope = grad.dot(direction)
            if slope >= 0 { inverse = [[1, 0], [0, 1]]; continue }
            let oldValue = objective(point)
            let oldPoint = point
            let oldGradient = grad
            func trial(_ alpha: Double) -> (point: GarmentCodePoint, value: Double, gradient: GarmentCodePoint) {
                let candidate = oldPoint + direction * alpha
                return (candidate, objective(candidate), gradient(candidate))
            }
            let c1 = 1e-4, c2 = 0.9
            func quadraticMinimum(_ a: Double, _ fa: Double, _ fpa: Double,
                                  _ b: Double, _ fb: Double) -> Double? {
                let db = b - a
                let denominator = 2 * (fb - fa - fpa * db)
                guard denominator.isFinite, abs(denominator) > 1e-30 else { return nil }
                let x = a - fpa * db * db / denominator
                return x.isFinite ? x : nil
            }
            func cubicMinimum(_ a: Double, _ fa: Double, _ fpa: Double,
                              _ b: Double, _ fb: Double,
                              _ c: Double, _ fc: Double) -> Double? {
                let db = b - a, dc = c - a
                let denominator = (db * dc) * (db * dc) * (db - dc)
                guard denominator.isFinite, abs(denominator) > 1e-30 else { return nil }
                let vb = fb - fa - fpa * db
                let vc = fc - fa - fpa * dc
                let aa = (dc * dc * vb - db * db * vc) / denominator
                let bb = (-dc * dc * dc * vb + db * db * db * vc) / denominator
                let discriminant = bb * bb - 3 * aa * fpa
                guard discriminant >= 0, abs(aa) > 1e-30 else { return nil }
                let x = a + (-bb + sqrt(discriminant)) / (3 * aa)
                return x.isFinite ? x : nil
            }
            func zoom(_ initialLo: Double, _ initialHi: Double,
                      _ initialFLo: Double, _ initialFHi: Double,
                      _ initialSlopeLo: Double) -> (Double, (point: GarmentCodePoint, value: Double, gradient: GarmentCodePoint))? {
                var lo = initialLo, hi = initialHi
                var fLo = initialFLo, fHi = initialFHi, slopeLo = initialSlopeLo
                var recordAlpha = 0.0, recordValue = oldValue
                for iteration in 0...10 {
                    let delta = hi - lo
                    let lower = min(lo, hi) + 0.1 * abs(delta)
                    let upper = max(lo, hi) - 0.1 * abs(delta)
                    var candidateAlpha: Double? = nil
                    var cubicWasAccepted = false
                    if iteration > 0 {
                        candidateAlpha = cubicMinimum(lo, fLo, slopeLo, hi, fHi,
                                                      recordAlpha, recordValue)
                        let cubicLower = min(lo, hi) + 0.2 * abs(delta)
                        let cubicUpper = max(lo, hi) - 0.2 * abs(delta)
                        if candidateAlpha != nil && candidateAlpha! >= cubicLower && candidateAlpha! <= cubicUpper {
                            cubicWasAccepted = true
                        }
                    }
                    if !cubicWasAccepted {
                        candidateAlpha = quadraticMinimum(lo, fLo, slopeLo, hi, fHi)
                    }
                    if candidateAlpha == nil || candidateAlpha! < lower || candidateAlpha! > upper {
                        candidateAlpha = lo + 0.5 * delta
                    }
                    let alpha = candidateAlpha!
                    let result = trial(alpha)
                    let slopeAt = result.gradient.dot(direction)
                    if result.value > oldValue + c1 * alpha * slope || result.value >= fLo {
                        recordAlpha = hi; recordValue = fHi
                        hi = alpha; fHi = result.value
                    } else {
                        if abs(slopeAt) <= -c2 * slope { return (alpha, result) }
                        if slopeAt * (hi - lo) >= 0 {
                            recordAlpha = hi; recordValue = fHi
                            hi = lo; fHi = fLo
                        } else {
                            recordAlpha = lo; recordValue = fLo
                        }
                        lo = alpha; fLo = result.value; slopeLo = slopeAt
                    }
                }
                return nil
            }
            var alpha1 = min(1.0, 1.01 * 2 * (oldValue - previousValue) / slope)
            if alpha1 < 0 { alpha1 = 1 }
            let phi0 = oldValue
            var accepted: (point: GarmentCodePoint, value: Double, gradient: GarmentCodePoint)?
            if let alpha = GarmentCodeWolfe1.search(
                alpha: alpha1, valueAtZero: oldValue, slopeAtZero: slope,
                value: { trial($0).value },
                slope: { trial($0).gradient.dot(direction) }) {
                accepted = trial(alpha)
            }
            var alpha0 = 0.0
            var phiA0 = phi0
            var slopeA0 = slope
            var phiA1 = trial(alpha1).value
            if accepted == nil {
                for iteration in 0..<10 {
                    if phiA1 > phi0 + c1 * alpha1 * slope ||
                        (phiA1 >= phiA0 && iteration > 0) {
                        accepted = zoom(alpha0, alpha1, phiA0, phiA1, slopeA0)?.1
                        break
                    }
                    let candidate = trial(alpha1)
                    let slopeA1 = candidate.gradient.dot(direction)
                    if abs(slopeA1) <= -c2 * slope { accepted = candidate; break }
                    if slopeA1 >= 0 {
                        accepted = zoom(alpha1, alpha0, phiA1, phiA0, slopeA1)?.1
                        break
                    }
                    alpha0 = alpha1; alpha1 *= 2
                    phiA0 = phiA1; phiA1 = trial(alpha1).value; slopeA0 = slopeA1
                }
            }
            guard let accepted else { break }
            previousValue = oldValue
            point = accepted.point
            grad = accepted.gradient
            let s = point - oldPoint
            let y = grad - oldGradient
            let ys = y.dot(s)
            if ys > 1e-12 {
                let rho = 1 / ys
                let a = [[1 - rho * s.x * y.x, -rho * s.x * y.y],
                         [-rho * s.y * y.x, 1 - rho * s.y * y.y]]
                let b = [[1 - rho * y.x * s.x, -rho * y.x * s.y],
                         [-rho * y.y * s.x, 1 - rho * y.y * s.y]]
                var next = [[0.0, 0.0], [0.0, 0.0]]
                for i in 0..<2 { for j in 0..<2 {
                    for k in 0..<2 { for l in 0..<2 {
                        next[i][j] += a[i][k] * inverse[k][l] * b[l][j]
                    }}
                    next[i][j] += rho * (i == 0 ? s.x : s.y) * (j == 0 ? s.x : s.y)
                }}
                inverse = next
            }
        }
        let control = start + chord * point.x + chord.leftNormal * point.y
        return .init(id: id, start: start, end: end,
                     curvature: .init(type: "quadratic", params: [relative(control, from: start, to: end)]))
    }

    nonisolated private static func absolute(_ point: [Double], from start: GarmentCodePoint, to end: GarmentCodePoint) -> GarmentCodePoint {
        guard point.count == 2 else { return start }
        let chord = end - start
        return start + chord * point[0] + chord.leftNormal * point[1]
    }

    nonisolated private static func circleArc(start: GarmentCodePoint, end: GarmentCodePoint, radius: Double,
                                  largeArc: Bool, right: Bool) -> (center: GarmentCodePoint, delta: Double, radius: Double)? {
        let chord = end - start
        let d = chord.length
        guard radius > 0, d > 1e-12 else { return nil }
        // svgpathtools' SVG Arc implementation scales undersized radii up until
        // the endpoints can lie on the requested circle.
        let correctedRadius = max(radius, d / 2)
        let midpoint = (start + end) * 0.5
        let height = sqrt(max(0, correctedRadius * correctedRadius - d * d / 4))
        // SVG/svgtpathtools use the stored `right` flag as sweep: the center
        // coefficient is negative when large-arc and sweep flags agree.
        let sign = (largeArc == right) ? -1.0 : 1.0
        let center = midpoint + chord.normalized.leftNormal * (height * sign)
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var delta = endAngle - startAngle
        let sweepPositive = right
        if sweepPositive {
            while delta < 0 { delta += 2 * .pi }
            while delta >= 2 * .pi { delta -= 2 * .pi }
        } else {
            while delta > 0 { delta -= 2 * .pi }
            while delta <= -2 * .pi { delta += 2 * .pi }
        }
        // At a diameter both SVG arc sizes describe the same semicircle.
        // Applying the large-arc correction at exactly pi reverses its sweep.
        if abs(delta) != .pi && (abs(delta) > .pi) != largeArc {
            delta += sweepPositive ? -2 * .pi : 2 * .pi
        }
        return (center, delta, correctedRadius)
    }

    nonisolated private static func circlePoint(start: GarmentCodePoint, end: GarmentCodePoint,
                                    curvature: GarmentCodeCurvature, t: Double) -> GarmentCodePoint {
        guard let circle = curvature.circle,
              let arc = circleArc(start: start, end: end, radius: circle.radius,
                                  largeArc: circle.largeArc, right: circle.right) else {
            return start + (end - start) * t
        }
        let a = atan2(start.y - arc.center.y, start.x - arc.center.x) + arc.delta * t
        return .init(x: arc.center.x + arc.radius * cos(a), y: arc.center.y + arc.radius * sin(a))
    }
}

/// A mutable panel edge loop corresponding to PyGarment EdgeSequence.
struct GarmentCodePanelGeometry: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String?
    var edges: [GarmentCodeGeometryEdge]

    init(id: String, label: String? = nil, edges: [GarmentCodeGeometryEdge]) {
        self.id = id
        self.label = label
        self.edges = edges
    }

    init(id: String, panel: GarmentCodePanel,
         curvatureCoordinates: String = "relative", unitScale: Double = 1) throws {
        guard panel.vertices.count >= 2, panel.edges.count >= 2 else {
            throw GarmentCodeGeometryError.invalidPanel(id)
        }
        guard unitScale.isFinite, unitScale > 0,
              ["relative", "absolute"].contains(curvatureCoordinates) else {
            throw GarmentCodeGeometryError.invalidPanel(id)
        }
        var converted: [GarmentCodeGeometryEdge] = []
        for (index, edge) in panel.edges.enumerated() {
            guard edge.endpoints.count == 2,
                  edge.endpoints.allSatisfy(panel.vertices.indices.contains) else {
                throw GarmentCodeGeometryError.invalidPanelVertex(id, index)
            }
            let start = panel.vertices[edge.endpoints[0]]
            let end = panel.vertices[edge.endpoints[1]]
            guard start.count == 2, end.count == 2,
                  start.allSatisfy(\.isFinite), end.allSatisfy(\.isFinite) else {
                throw GarmentCodeGeometryError.invalidPanelVertex(id, index)
            }
            let localStart = GarmentCodePoint(x: start[0] * unitScale, y: start[1] * unitScale)
            let localEnd = GarmentCodePoint(x: end[0] * unitScale, y: end[1] * unitScale)
            guard [localStart.x, localStart.y, localEnd.x, localEnd.y].allSatisfy(\.isFinite) else {
                throw GarmentCodeGeometryError.invalidPanelVertex(id, index)
            }
            let normalizedCurvature: GarmentCodeCurvature?
            if let curve = edge.curvature, curve.type == "circle", let arc = curve.circle {
                normalizedCurvature = .init(circleRadius: arc.radius * unitScale,
                                            largeArc: arc.largeArc, right: arc.right)
            } else if let curve = edge.curvature, curvatureCoordinates == "absolute",
                      let points = curve.params {
                guard points.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else {
                    throw GarmentCodeGeometryError.invalidPanelVertex(id, index)
                }
                let absoluteControls = points.map { GarmentCodePoint(x: $0[0] * unitScale, y: $0[1] * unitScale) }
                let relativeControls = absoluteControls.map {
                    GarmentCodeGeometryEdge.relativeCoordinates($0, from: localStart, to: localEnd)
                }
                normalizedCurvature = .init(type: curve.type, params: relativeControls)
            } else {
                normalizedCurvature = edge.curvature
            }
            if let normalizedCurvature, !normalizedCurvature.isValidForPreview {
                throw GarmentCodeGeometryError.invalidPanelVertex(id, index)
            }
            converted.append(GarmentCodeGeometryEdge(
                id: "\(id)-e\(index)",
                start: localStart,
                end: localEnd,
                curvature: normalizedCurvature,
                label: edge.label
            ))
        }
        self.init(id: id, label: panel.label, edges: converted)
        guard isClosed else { throw GarmentCodeGeometryError.invalidPanel(id) }
    }

    var isClosed: Bool {
        guard !edges.isEmpty else { return false }
        return edges.indices.allSatisfy { edges[$0].end.distance(to: edges[($0 + 1) % edges.count].start) <= 1e-6 }
    }

    var boundaryLength: Double { edges.reduce(0) { $0 + $1.length() } }

    var signedArea: Double {
        let points = edges.flatMap { $0.sample(maxSegmentLength: 0.25).dropLast() }
        guard points.count > 2 else { return 0 }
        return points.indices.reduce(0) { sum, i in
            let a = points[i], b = points[(i + 1) % points.count]
            return sum + a.x * b.y - b.x * a.y
        } / 2
    }

    mutating func translate(by delta: GarmentCodePoint) {
        edges = edges.map { $0.translated(by: delta) }
    }

    mutating func rotate(by angle: Double) {
        guard let pivot = edges.first?.start else { return }
        edges = edges.map { $0.rotated(by: angle, around: pivot) }
    }

    mutating func reflect(acrossLineFrom axisStart: GarmentCodePoint,
                          to axisEnd: GarmentCodePoint) {
        edges = edges.map { $0.reflected(acrossLineFrom: axisStart, to: axisEnd) }
    }

    /// PyGarment EdgeSequence.extend: scale vertex projections along the
    /// sequence's endpoint chord while keeping the first point fixed.
    mutating func extend(edgeIDs: [String], by factor: Double) -> Bool {
        guard !edgeIDs.isEmpty, factor.isFinite, factor > 0,
              let indices = Optional(edgeIDs.compactMap { id in edges.firstIndex { $0.id == id } }),
              indices.count == edgeIDs.count,
              Set(indices).count == indices.count else { return false }
        let sequence = indices.map { edges[$0] }
        guard zip(sequence, sequence.dropFirst()).allSatisfy({ $0.end.distance(to: $1.start) <= 1e-6 }) else { return false }
        let fixed = sequence[0].start
        let target = (sequence[sequence.count - 1].end - fixed).normalized
        guard target.length > 1e-12,
              sequence[sequence.count - 1].end.distance(to: fixed) > 1e-8 else { return false }
        func extended(_ point: GarmentCodePoint) -> GarmentCodePoint {
            let projection = target * (point - fixed).dot(target)
            return point + projection * (factor - 1)
        }
        let oldVertices = Set(sequence.flatMap { [$0.start, $0.end] })
        var remapped: [GarmentCodePoint: GarmentCodePoint] = [:]
        for vertex in oldVertices { remapped[vertex] = extended(vertex) }
        edges = edges.map { edge in
            var updated = edge
            updated.moveEndpoints(to: remapped[edge.start] ?? edge.start,
                                 newEnd: remapped[edge.end] ?? edge.end)
            return updated
        }
        return true
    }

    mutating func reverse() {
        edges = edges.reversed().map { $0.reversed() }
    }

    mutating func splitEdge(id edgeID: String, at fraction: Double) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }) else { return false }
        let edge = edges[index]
        let firstLength = edge.length() * fraction
        var low = 0.0, high = 1.0
        for _ in 0..<48 {
            let mid = (low + high) / 2
            if edge.split(at: mid).0.length() < firstLength { low = mid } else { high = mid }
        }
        let pieces = edge.split(at: (low + high) / 2)
        edges.replaceSubrange(index...index, with: [pieces.0, pieces.1])
        return true
    }

    mutating func splitEdge(id edgeID: String, atFractions fractions: [Double]) -> [String]? {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }) else { return nil }
        let cuts = Array(Set(fractions.filter { $0 > 1e-7 && $0 < 1 - 1e-7 }.map { min(1, max(0, $0)) })).sorted()
        guard !cuts.isEmpty else { return [edgeID] }
        let original = edges[index]
        var pieces: [GarmentCodeGeometryEdge] = []
        var remainder = original
        var previous = 0.0
        for (cutIndex, globalFraction) in cuts.enumerated() {
            let localFraction = (globalFraction - previous) / (1 - previous)
            let targetLength = remainder.length() * localFraction
            var low = 0.0, high = 1.0
            for _ in 0..<48 {
                let middle = (low + high) / 2
                if remainder.split(at: middle).0.length() < targetLength {
                    low = middle
                } else {
                    high = middle
                }
            }
            let split = remainder.split(at: (low + high) / 2,
                                        idPrefix: "\(edgeID)-s\(cutIndex)")
            pieces.append(split.0)
            remainder = split.1
            previous = globalFraction
        }
        pieces.append(remainder)
        edges.replaceSubrange(index...index, with: pieces)
        return pieces.map(\.id)
    }

    func serializedVertices() -> [[Double]] { edges.map { [$0.start.x, $0.start.y] } }

    func serializedEdges() -> [GarmentCodeEdge] {
        edges.indices.map { index in
            let edge = edges[index]
            let serializedCurve: GarmentCodeCurvature?
            if let curve = edge.curvature, curve.type == "circle", let circle = curve.circle {
                serializedCurve = GarmentCodeCurvature(circleRadius: circle.radius,
                                                       largeArc: circle.largeArc, right: circle.right)
            } else { serializedCurve = edge.curvature }
            return GarmentCodeEdge(endpoints: [index, (index + 1) % edges.count],
                                   label: edge.label, curvature: serializedCurve)
        }
    }
}

struct GarmentCodeInterfaceEdgeReference: Codable, Hashable {
    var panel: String
    var edge: String
    var reversed = false
    var ruffle = 1.0
    var rightWrong = false
}

/// PyGarment Interface's pattern-only subset: an ordered edge sequence with
/// per-edge ruffle projection and fabric-side orientation metadata.
struct GarmentCodeInterface: Codable, Hashable {
    var edges: [GarmentCodeInterfaceEdgeReference]

    func projectingLengths(in panels: [String: GarmentCodePanelGeometry]) throws -> [Double] {
        try edges.map { reference in
            guard let panel = panels[reference.panel],
                  let edge = panel.edges.first(where: { $0.id == reference.edge }),
                  reference.ruffle.isFinite, reference.ruffle > 0 else {
                throw GarmentCodeGeometryError.invalidInterfaceEdge(reference.panel, reference.edge)
            }
            return edge.length() / reference.ruffle
        }
    }

    func fractions(in panels: [String: GarmentCodePanelGeometry]) throws -> [Double] {
        let lengths = try projectingLengths(in: panels)
        let total = lengths.reduce(0, +)
        guard total > 1e-9 else { throw GarmentCodeGeometryError.zeroLengthInterface }
        return lengths.map { $0 / total }
    }
}

enum GarmentCodeGeometryError: LocalizedError {
    case invalidInterfaceEdge(String, String)
    case invalidPanel(String)
    case invalidPanelVertex(String, Int)
    case zeroLengthInterface
    case unmatchedStitching

    var errorDescription: String? {
        switch self {
        case let .invalidInterfaceEdge(panel, edge): "接口引用无效边：\(panel).\(edge)"
        case let .invalidPanel(panel): "裁片 \(panel) 不是有效闭合轮廓"
        case let .invalidPanelVertex(panel, edge): "裁片 \(panel) 的边 \(edge) 顶点索引或坐标无效"
        case .zeroLengthInterface: "接口总投影长度为零"
        case .unmatchedStitching: "接口细分后无法匹配"
        }
    }
}

/// Pattern-only StitchingRule port. It refines both interfaces to a common
/// projected-length partition before emitting the official edge-pair records.
enum GarmentCodeStitchingRule {
    static func assemble(_ first: inout GarmentCodeInterface,
                         _ second: inout GarmentCodeInterface,
                         panels: inout [String: GarmentCodePanelGeometry],
                         tolerance: Double = 1e-2,
                         upstreamSequential: Bool = false) throws -> [GarmentCodeStitch] {
        guard !first.edges.isEmpty, !second.edges.isEmpty else { throw GarmentCodeGeometryError.zeroLengthInterface }
        let fractions1 = try first.fractions(in: panels)
        let fractions2 = try second.fractions(in: panels)
        if first.edges.count == second.edges.count &&
            zip(fractions1, fractions2).allSatisfy({ abs($0.0 - $0.1) <= 0.05 }) {
            return try zip(first.edges, second.edges).map { a, b in
                guard let panelA = panels[a.panel], let panelB = panels[b.panel],
                      let edgeA = panelA.edges.firstIndex(where: { $0.id == a.edge }),
                      let edgeB = panelB.edges.firstIndex(where: { $0.id == b.edge }) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(a.panel, a.edge)
                }
                return .init(sides: [.init(panel: a.panel, edge: edgeA),
                                     .init(panel: b.panel, edge: edgeB)],
                             rightWrong: a.rightWrong || b.rightWrong)
            }
        }
        if upstreamSequential {
            let fractions1 = try first.fractions(in: panels)
            let fractions2 = try second.fractions(in: panels)
            let splitTolerance = min(0.01, min(fractions1.min() ?? 1,
                                               fractions2.min() ?? 1) / 2)
            try refineSequential(&first, against: fractions2,
                                 tolerance: splitTolerance, panels: &panels)
            try refineSequential(&second, against: fractions1,
                                 tolerance: splitTolerance, panels: &panels)
            guard first.edges.count == second.edges.count else {
                throw GarmentCodeGeometryError.unmatchedStitching
            }
            return try zip(first.edges, second.edges).map { a, b in
                guard let panelA = panels[a.panel], let panelB = panels[b.panel],
                      let edgeA = panelA.edges.firstIndex(where: { $0.id == a.edge }),
                      let edgeB = panelB.edges.firstIndex(where: { $0.id == b.edge }) else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(a.panel, a.edge)
                }
                return .init(sides: [.init(panel: a.panel, edge: edgeA),
                                     .init(panel: b.panel, edge: edgeB)],
                             rightWrong: a.rightWrong || b.rightWrong)
            }
        }
        func boundaries(_ fractions: [Double]) -> [Double] {
            var result = [0.0]
            for fraction in fractions { result.append(min(1, result.last! + fraction)) }
            return result
        }
        let firstBounds = boundaries(fractions1)
        let secondBounds = boundaries(fractions2)
        let minimumFraction = min(fractions1.min() ?? 1, fractions2.min() ?? 1)
        let snapTolerance = min(0.01, minimumFraction / 2)
        let firstTarget = (firstBounds + secondBounds.filter { candidate in
            !firstBounds.contains(where: { abs($0 - candidate) <= snapTolerance })
        }).sorted()
        let secondTarget = (secondBounds + firstBounds.filter { candidate in
            !secondBounds.contains(where: { abs($0 - candidate) <= snapTolerance })
        }).sorted()
        try refine(&first, to: firstTarget, panels: &panels)
        try refine(&second, to: secondTarget, panels: &panels)

        let normalized1 = try first.fractions(in: panels)
        let normalized2 = try second.fractions(in: panels)
        guard first.edges.count == second.edges.count,
              zip(normalized1, normalized2).allSatisfy({ abs($0.0 - $0.1) <= max(tolerance, 0.05) }) else {
            throw GarmentCodeGeometryError.unmatchedStitching
        }
        return try zip(first.edges, second.edges).map { a, b in
            guard let panelA = panels[a.panel], let panelB = panels[b.panel],
                  let edgeA = panelA.edges.firstIndex(where: { $0.id == a.edge }),
                  let edgeB = panelB.edges.firstIndex(where: { $0.id == b.edge }) else {
                throw GarmentCodeGeometryError.invalidInterfaceEdge(a.panel, a.edge)
            }
            return GarmentCodeStitch(sides: [
                GarmentCodeStitchSide(panel: a.panel, edge: edgeA),
                GarmentCodeStitchSide(panel: b.panel, edge: edgeB)
            ], rightWrong: a.rightWrong || b.rightWrong)
        }
    }

    /// Literal `_match_to_fractions` walk from the pinned connector.py. It
    /// differs from a sorted boundary union when neighboring SVG curves have
    /// nearly coincident cumulative fractions.
    private static func refineSequential(_ interface: inout GarmentCodeInterface,
                                         against targetFractions: [Double],
                                         tolerance: Double,
                                         panels: inout [String: GarmentCodePanelGeometry]) throws {
        var addedIndex = 0, interfaceIndex = 0
        var coveredInitial = 0.0, coveredAdded = 0.0
        var current = try interface.fractions(in: panels)
        while interfaceIndex < interface.edges.count && addedIndex < targetFractions.count {
            let nextInitial = min(coveredInitial + current[interfaceIndex], 1)
            let nextAdded = min(coveredAdded + targetFractions[addedIndex], 1)
            if abs(nextInitial - nextAdded) < tolerance {
                interfaceIndex += 1; addedIndex += 1
                coveredInitial = nextInitial; coveredAdded = nextAdded
            } else if nextInitial < nextAdded {
                interfaceIndex += 1
                coveredInitial = nextInitial
            } else {
                let localFraction = current[interfaceIndex]
                var splitFraction = (localFraction - (nextInitial - nextAdded)) / localFraction
                let reference = interface.edges[interfaceIndex]
                if reference.reversed { splitFraction = 1 - splitFraction }
                guard var panel = panels[reference.panel],
                      let ids = panel.splitEdge(id: reference.edge,
                                                atFractions: [splitFraction]),
                      ids.count == 2 else {
                    throw GarmentCodeGeometryError.invalidInterfaceEdge(reference.panel, reference.edge)
                }
                panels[reference.panel] = panel
                let ordered = reference.reversed ? Array(ids.reversed()) : ids
                interface.edges.replaceSubrange(interfaceIndex...interfaceIndex,
                    with: ordered.map {
                        GarmentCodeInterfaceEdgeReference(panel: reference.panel, edge: $0,
                                                           reversed: reference.reversed,
                                                           ruffle: reference.ruffle,
                                                           rightWrong: reference.rightWrong)
                    })
                current = try interface.fractions(in: panels)
                coveredInitial += current[interfaceIndex]
                coveredAdded = nextAdded
                interfaceIndex += 1; addedIndex += 1
            }
        }
        guard addedIndex == targetFractions.count else {
            throw GarmentCodeGeometryError.unmatchedStitching
        }
    }

    private static func refine(_ interface: inout GarmentCodeInterface,
                               to globalBoundaries: [Double],
                               panels: inout [String: GarmentCodePanelGeometry]) throws {
        let lengths = try interface.projectingLengths(in: panels)
        let total = lengths.reduce(0, +)
        guard total > 1e-9 else { throw GarmentCodeGeometryError.zeroLengthInterface }
        var result: [GarmentCodeInterfaceEdgeReference] = []
        var covered = 0.0
        for (index, reference) in interface.edges.enumerated() {
            let projectedLength = lengths[index]
            let edgeStart = covered / total
            let edgeEnd = (covered + projectedLength) / total
            let localCuts = globalBoundaries.filter { $0 > edgeStart + 1e-8 && $0 < edgeEnd - 1e-8 }
                .map { ($0 - edgeStart) / (edgeEnd - edgeStart) }
            guard var panel = panels[reference.panel],
                  let panelCuts = panel.splitEdge(id: reference.edge,
                                                  atFractions: reference.reversed ? localCuts.map { 1 - $0 } : localCuts) else {
                throw GarmentCodeGeometryError.invalidInterfaceEdge(reference.panel, reference.edge)
            }
            panels[reference.panel] = panel
            let orderedIDs = reference.reversed ? panelCuts.reversed() : panelCuts
            result.append(contentsOf: orderedIDs.map {
                GarmentCodeInterfaceEdgeReference(panel: reference.panel, edge: $0,
                                                   reversed: reference.reversed, ruffle: reference.ruffle,
                                                   rightWrong: reference.rightWrong)
            })
            covered += projectedLength
        }
        interface.edges = result
    }
}

/// Port of PyGarment `even_armhole_openings`. Sleeve halves share an aligned
/// underarm seam: when the front opening is longer, the excess curve is split,
/// reflected onto the back, and both openings are rotated to a vertical axis.
enum GarmentCodeSleeveGeometry {
    static func armholeCurve(id: String,
                             inclination: Double,
                             width: Double,
                             restAngle: Double,
                             bottomAngleMix: Double,
                             targetLength requestedLength: Double? = nil) throws
        -> (projection: [GarmentCodeGeometryEdge], opening: [GarmentCodeGeometryEdge]) {
        guard inclination > 0, width > 0, restAngle.isFinite,
              bottomAngleMix.isFinite else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let controlPoints = [[0.5, 0.2], [0.8, 0.35]]
        let source = GarmentCodeGeometryEdge(
            id: id,
            start: .init(x: inclination, y: width), end: .zero,
            curvature: .init(type: "cubic", params: controlPoints))
        let projection = source.reversed()
        let targetLength = requestedLength ?? source.length()
        guard targetLength.isFinite, targetLength > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let chordLength = source.chordLength
        var inverse = GarmentCodeGeometryEdge(
            id: "\(id)-inverse",
            start: .init(x: inclination, y: width),
            end: .init(x: inclination, y: width - chordLength),
            // PyGarment passes the same mutable `cps` array to the projection
            // edge, reverses that edge in-place, then copies the now-reversed
            // controls before flipping the final control's normal coordinate.
            curvature: .init(type: "cubic", params: [[0.2, -0.35], [0.5, 0.2]]))
            .rotated(by: -restAngle, around: .init(x: inclination, y: width))
        let down = GarmentCodePoint(x: 0, y: -1)
        let rotatedDirection = (inverse.end - inverse.start).normalized
        let sideDirection = GarmentCodePoint(x: -1, y: 0)
        let targetDirection = bottomAngleMix > 0
            ? rotatedDirection * (1 - bottomAngleMix) + down * bottomAngleMix
            : rotatedDirection * (1 - bottomAngleMix) - sideDirection * bottomAngleMix
        inverse = try GarmentCodeGeometryEdge.cubicMatchingTangents(
            inverse, targetStartTangent: down, targetEndTangent: targetDirection,
            targetLength: targetLength)
        return (projection: [projection], opening: [inverse.reversed()])
    }

    static func panel(id: String,
                      opening: [GarmentCodeGeometryEdge],
                      endWidthRatio: Double,
                      sleeveLengthRatio: Double,
                      armLength: Double,
                      wristCircumference: Double,
                      connectRuffle: Double = 1,
                      lengthShift: Double = 0,
                      standingShoulder: Bool = false,
                      standingLength: Double = 0,
                      standingAngle: Double = 0) throws -> GarmentCodePanelGeometry {
        guard !opening.isEmpty, endWidthRatio > 0, sleeveLengthRatio > 0,
              connectRuffle.isFinite, connectRuffle > 0,
              armLength > 0, wristCircumference > 0 else {
            throw GarmentCodeProgramError.invalidMeasurements
        }
        let openingStart = opening[0].start, openingEnd = opening[opening.count - 1].end
        let endWidth = max(endWidthRatio * abs(openingStart.y - openingEnd.y),
                           wristCircumference / 2)
        var extendedOpening = opening
        if abs(connectRuffle - 1) > 1e-10 {
            var sequence = GarmentCodePanelGeometry(id: "\(id)-opening", edges: opening)
            guard sequence.extend(edgeIDs: opening.map(\.id), by: connectRuffle) else {
                throw GarmentCodeGeometryError.invalidPanel(id)
            }
            extendedOpening = sequence.edges
        }
        let extendedEnd = extendedOpening[extendedOpening.count - 1].end
        let armWidth = abs(openingStart.y - extendedEnd.y)
        let openingLength = abs(openingStart.x - extendedEnd.x)
        let length = max(sleeveLengthRatio * (armLength - openingLength) + lengthShift, 5)
        let lowerInner = GarmentCodePoint.zero
        let lowerOuter = GarmentCodePoint(x: 0, y: -endWidth)
        let upperOuter = GarmentCodePoint(x: length, y: -armWidth)
        let offset = upperOuter - openingStart
        let translatedOpening = extendedOpening.map { $0.translated(by: offset) }
        var edges = [
            GarmentCodeGeometryEdge(id: "\(id)-inner", start: lowerInner, end: lowerOuter),
            GarmentCodeGeometryEdge(id: "\(id)-cuff", start: lowerOuter, end: upperOuter)
        ]
        edges += translatedOpening
        var closingStart = translatedOpening.last!.end
        if standingShoulder {
            guard standingLength > 0, standingAngle.isFinite else {
                throw GarmentCodeProgramError.invalidMeasurements
            }
            let shelfEnd = closingStart + .init(x: -standingLength * cos(standingAngle),
                                                 y: standingLength * sin(standingAngle))
            edges.append(.init(id: "\(id)-standing", start: closingStart, end: shelfEnd))
            closingStart = shelfEnd
        }
        edges.append(.init(id: "\(id)-close", start: closingStart, end: lowerInner))
        return GarmentCodePanelGeometry(id: id, label: "arm", edges: edges)
    }

    static func evenOpenings(front: [GarmentCodeGeometryEdge],
                             back: [GarmentCodeGeometryEdge]) throws
        -> (front: [GarmentCodeGeometryEdge], back: [GarmentCodeGeometryEdge]) {
        guard !front.isEmpty, !back.isEmpty,
              zip(front, front.dropFirst()).allSatisfy({ $0.end.distance(to: $1.start) < 1e-6 }),
              zip(back, back.dropFirst()).allSatisfy({ $0.end.distance(to: $1.start) < 1e-6 }) else {
            throw GarmentCodeGeometryError.zeroLengthInterface
        }
        var frontResult = front
        var backResult = back
        var reflectedBack = reflectAndReverse(back)
        let reflectedStart = reflectedBack[0].start
        let reflectedTarget = frontResult[frontResult.count - 1].end
        reflectedBack = reflectedBack.map { $0.translated(by: reflectedTarget - reflectedStart) }

        let slope = reflectedBack[reflectedBack.count - 1].end - frontResult[0].start
        guard slope.length > 1e-9 else { throw GarmentCodeGeometryError.zeroLengthInterface }
        let lastFront = frontResult[frontResult.count - 1]
        let tolerance = min(0.5, 0.2 / max(front.reduce(0) { $0 + $1.length() }, 1e-9))
        // Upstream leaves both curves intact when the bisector misses the
        // front opening, then still aligns the combined slope below.
        if let splitParameter = intersectionParameter(of: lastFront,
                linePoint: (reflectedBack.last!.end + frontResult[0].start) * 0.5,
                lineDirection: slope.leftNormal),
           splitParameter > tolerance && splitParameter < 1 - tolerance {
            let (frontPart, transferredPart) = lastFront.split(at: splitParameter,
                                                              idPrefix: "\(lastFront.id)-even")
            frontResult[frontResult.count - 1] = frontPart
            var transfer = reflectAndReverse([transferredPart])
            let transferStart = transfer[0].start
            let target = backResult[backResult.count - 1].end
            transfer = transfer.map { $0.translated(by: target - transferStart) }
            backResult.append(contentsOf: transfer)
        }

        let angle = atan2(-slope.x, slope.y)
        frontResult = rotateSequence(frontResult, by: -angle)
        backResult = rotateSequence(backResult, by: angle)
        return (frontResult, backResult)
    }

    private static func rotateSequence(_ edges: [GarmentCodeGeometryEdge],
                                       by angle: Double) -> [GarmentCodeGeometryEdge] {
        guard let pivot = edges.first?.start else { return edges }
        return edges.map { $0.rotated(by: angle, around: pivot) }
    }

    private static func reflectAndReverse(_ edges: [GarmentCodeGeometryEdge]) -> [GarmentCodeGeometryEdge] {
        edges.reversed().map {
            $0.reflected(acrossLineFrom: .zero, to: .init(x: 1, y: 0)).reversed()
        }
    }

    /// Find the intersection with an infinite line by sampling then bisecting
    /// the signed cross-product. Like upstream's empty intersection list, a
    /// missing intersection means no redistribution rather than invalid paper.
    private static func intersectionParameter(of edge: GarmentCodeGeometryEdge,
                                              linePoint: GarmentCodePoint,
                                              lineDirection: GarmentCodePoint) -> Double? {
        func side(_ t: Double) -> Double {
            let point = edge.point(at: t) - linePoint
            return point.x * lineDirection.y - point.y * lineDirection.x
        }
        let samples = 256
        var previousT = 0.0
        var previous = side(previousT)
        var brackets: [(Double, Double)] = []
        for index in 1...samples {
            let t = Double(index) / Double(samples)
            let value = side(t)
            if value == 0 || previous == 0 || value.sign != previous.sign {
                brackets.append((previousT, t))
            }
            previousT = t
            previous = value
        }
        guard !brackets.isEmpty else { return nil }
        let bracket = brackets.min { abs(($0.0 + $0.1) / 2 - 0.5) < abs(($1.0 + $1.1) / 2 - 0.5) }!
        var low = bracket.0, high = bracket.1
        var lowValue = side(low)
        for _ in 0..<56 {
            let middle = (low + high) / 2
            let value = side(middle)
            if abs(value) < 1e-12 { return middle }
            if value.sign == lowValue.sign { low = middle; lowValue = value }
            else { high = middle }
        }
        return (low + high) / 2
    }
}

/// Pattern-only port of PyGarment `ops.cut_corner` for a corner made from two
/// consecutive panel edges. The target shape is positioned by minimizing the
/// squared difference between its shortcut and the vector joining points on
/// the two corner edges, then the corner edges are split around that insertion.
enum GarmentCodeCornerProjection {
    static func cut(panel: inout GarmentCodePanelGeometry,
                    firstEdgeID: String,
                    secondEdgeID: String,
                    targetShape: [GarmentCodeGeometryEdge]) throws -> [GarmentCodeGeometryEdge] {
        guard let firstIndex = panel.edges.firstIndex(where: { $0.id == firstEdgeID }),
              let secondIndex = panel.edges.firstIndex(where: { $0.id == secondEdgeID }),
              secondIndex == firstIndex + 1,
              !targetShape.isEmpty else {
            throw GarmentCodeGeometryError.invalidPanel(panel.id)
        }
        let first = panel.edges[firstIndex], second = panel.edges[secondIndex]
        let swapped = first.start.y > second.end.y
        let curve1 = swapped ? second : first
        let curve2 = swapped ? first : second
        var shape = targetShape
        if shape[0].start.y > shape[shape.count - 1].end.y {
            shape = reverseSequence(shape)
            let delta = GarmentCodePoint.zero - shape[0].start
            shape = shape.map { $0.translated(by: delta) }
        }
        let shortcut = shape[shape.count - 1].end - shape[0].start
        var location = bestProjection(curve1: curve1, curve2: curve2, difference: shortcut)
        let pointOnFirst = curve1.point(at: location.0)
        let delta = pointOnFirst - shape[0].start
        shape = shape.map { $0.translated(by: delta) }
        if swapped {
            shape = reverseSequence(shape)
            swap(&location.0, &location.1)
        }
        let firstSplit = first.split(at: location.0, idPrefix: "\(first.id)-corner")
        let secondSplit = second.split(at: location.1, idPrefix: "\(second.id)-corner")
        var prefix = firstSplit.0
        prefix.moveEndpoints(to: prefix.start, newEnd: shape[0].start)
        var suffix = secondSplit.1
        suffix.moveEndpoints(to: shape[shape.count - 1].end, newEnd: suffix.end)
        let keepPrefix = prefix.length() > 1e-9
        let keepSuffix = suffix.length() > 1e-9
        if !keepPrefix { shape[0].moveEndpoints(to: first.start, newEnd: shape[0].end) }
        if !keepSuffix { shape[shape.count - 1].moveEndpoints(to: shape[shape.count - 1].start,
                                                              newEnd: second.end) }
        let inserted = (keepPrefix ? [prefix] : []) + shape + (keepSuffix ? [suffix] : [])
        panel.edges.replaceSubrange(firstIndex...secondIndex, with: inserted)
        guard panel.isClosed else {
            let gaps = panel.edges.indices.map { index in
                panel.edges[index].end.distance(to: panel.edges[(index + 1) % panel.edges.count].start)
            }
            FileHandle.standardError.write(Data("CUT_CORNER_GAPS \(panel.id) \(gaps) inserted=\(inserted.map { ($0.start, $0.end) })\n".utf8))
            throw GarmentCodeGeometryError.invalidPanel(panel.id)
        }
        return Array(inserted.dropFirst(keepPrefix ? 1 : 0)
            .dropLast(keepSuffix ? 1 : 0))
    }

    private static func reverseSequence(_ edges: [GarmentCodeGeometryEdge]) -> [GarmentCodeGeometryEdge] {
        edges.reversed().map { $0.reversed() }
    }

    private static func bestProjection(curve1: GarmentCodeGeometryEdge,
                                       curve2: GarmentCodeGeometryEdge,
                                       difference: GarmentCodePoint) -> (Double, Double) {
        func objective(_ first: Double, _ second: Double) -> Double {
            let residual = curve2.point(at: second) - curve1.point(at: first) - difference
            return residual.dot(residual)
        }
        var point = (0.5, 0.5)
        for _ in 0..<100 {
            let residual = curve2.point(at: point.1) - curve1.point(at: point.0) - difference
            let oldValue = residual.dot(residual)
            if oldValue < 1e-20 { break }
            let h = 1e-5
            let d1 = (curve1.point(at: min(1, point.0 + h)) -
                      curve1.point(at: max(0, point.0 - h))) *
                (-1 / (min(1, point.0 + h) - max(0, point.0 - h)))
            let d2 = (curve2.point(at: min(1, point.1 + h)) -
                      curve2.point(at: max(0, point.1 - h))) *
                (1 / (min(1, point.1 + h) - max(0, point.1 - h)))
            let a = d1.dot(d1), b = d1.dot(d2), c = d2.dot(d2)
            let r1 = d1.dot(residual), r2 = d2.dot(residual)
            let determinant = a * c - b * b
            guard determinant > 1e-14 else { break }
            let delta = ((-c * r1 + b * r2) / determinant,
                         (b * r1 - a * r2) / determinant)
            var scale = 1.0
            var improved = false
            while scale > 1e-8 {
                let candidate = (min(1, max(0, point.0 + scale * delta.0)),
                                 min(1, max(0, point.1 + scale * delta.1)))
                if objective(candidate.0, candidate.1) < oldValue {
                    point = candidate
                    improved = true
                    break
                }
                scale *= 0.5
            }
            if !improved { break }
        }
        return point
    }
}
