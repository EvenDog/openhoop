// Smart corners: sharp corners of satin lines, satin outlines and satin borders are sewn the way professional
// digitizing software sews them instead of being rounded off. A mitre: each leg's stitches stay square to the leg and
// stop at the seam running from the inside corner to the outside point, the two legs overlapping a little across it.
// A cap, for very sharp corners: the legs stop at a line across the corner and the point beyond is sewn as a small
// piece of its own, its stitches running across the corner. The corner's edge pair lies along the seam (from the
// inside corner to the outside point), which is how the stitch engine finds it.
import Foundation

public enum SmartCorners {
    /// Corners whose legs meet at less than this angle (degrees) get a mitre; wider ones are rounded as before.
    public static let mitreBelow = 75.0
    /// Corners sharper than this get a cap, unless its stitches would be longer than `capMaximum` (mm).
    public static let capBelow = 45.0
    public static let capMaximum = 8.0
    /// How far (mm) the legs of a mitre overlap across the seam, so no gap shows there.
    public static let mitreOverlap = 0.5

    enum Kind { case mitre, cap }

    /// The angle (radians) between the two legs meeting at `b`, on the way from `a` through `b` to `c`: π for a
    /// straight line, small for a sharp point.
    static func opening(_ a: Point, _ b: Point, _ c: Point) -> Double {
        let u = a - b, v = c - b, lu = hypot(u.x, u.y), lv = hypot(v.x, v.y)
        guard lu > 1e-9, lv > 1e-9 else { return .pi }
        return acos(max(-1, min(1, (u.x * v.x + u.y * v.y) / (lu * lv))))
    }
    /// True for a corner sharp enough to mitre or cap.
    static func isSharp(_ a: Point, _ b: Point, _ c: Point) -> Bool { opening(a, b, c) < mitreBelow * .pi / 180 }

    /// The indexes of the sharp corners of a center line (a ring when `closed`).
    static func sharpCorners(_ line: [Point], closed: Bool) -> [Int] {
        guard line.count >= 3 else { return [] }
        return line.indices.filter { i in
            guard closed || (i > 0 && i < line.count - 1) else { return false }
            return isSharp(line[(i + line.count - 1) % line.count], line[i], line[(i + 1) % line.count])
        }
    }

    /// The center line without the points that lie closer to a sharp corner than its inside corner does: a pair there
    /// would reach past the inside corner, so the inside edge would run backwards. Ends of an open line always stay.
    static func clearedAroundCorners(_ line: [Point], closed: Bool, half: Double) -> [Point] {
        let sharp = Set(sharpCorners(line, closed: closed))
        guard !sharp.isEmpty else { return line }
        let n = line.count
        var drop = Set<Int>()
        for c in sharp {
            let reach = half / tan(max(0.05, opening(line[(c + n - 1) % n], line[c], line[(c + 1) % n])) / 2) + 0.3
            for i in line.indices where i != c && !sharp.contains(i) && (closed || (i > 0 && i < n - 1)) && line[i].distance(to: line[c]) < reach { drop.insert(i) }
        }
        return line.indices.filter { !drop.contains($0) }.map { line[$0] }
    }

    /// The sharp corners of a center line that a satin `half` × 2 wide can mitre: those whose legs are both longer than
    /// the distance from the corner to its inside corner (a hairpin beside a short leg is rounded instead).
    static func fittingCorners(_ line: [Point], closed: Bool, half: Double) -> [Int] {
        let n = line.count
        return sharpCorners(line, closed: closed).filter { c in
            let previous = line[(c + n - 1) % n], next = line[(c + 1) % n]
            let reach = half / tan(max(0.05, opening(previous, line[c], next)) / 2) + 0.3
            return previous.distance(to: line[c]) > reach && next.distance(to: line[c]) > reach
        }
    }

    /// The edge pairs (left, right) of a smart-cornered satin that are corners: those where the column's middle line
    /// turns sharply. Each lies along its corner's seam.
    static func corners(_ pairs: [(Point, Point)], closed: Bool) -> Set<Int> {
        let middles = pairs.map { ($0.0 + $0.1) * 0.5 }
        return Set(sharpCorners(middles, closed: closed))
    }

    /// A center line with the corners it was rounded at put back: where a run of short pieces bends one way round
    /// (the arc a rounded corner was given), and the legs on either side would meet at a sharp corner, the arc is
    /// replaced by that corner. `width` is the satin's, which sets how round its corners were made; gentler curves
    /// are left alone.
    static func restoredCorners(_ line: [Point], closed: Bool, width: Double) -> [Point] {
        let n = line.count
        guard n >= 4 else { return line }
        let radius = width / 2 + max(0.6, width * 0.2 - 1)   // the most a satin line or border corner was rounded by
        let short = 2 * (0.2 * radius).squareRoot() + 0.9    // the longest piece an arc that round was cut into
        func at(_ i: Int) -> Point { line[((i % n) + n) % n] }
        func turn(_ i: Int) -> Double { AreaGeometry.cross(at(i) - at(i - 1), at(i + 1) - at(i)) }
        var result = line, replaced = [Int: Point](), removed = Set<Int>()
        var i = closed ? 0 : 1
        let last = closed ? n - 1 : n - 2
        while i <= last {
            guard abs(turn(i)) > 1e-9, !removed.contains(i) else { i += 1; continue }
            // A run of vertices turning the same way, joined by short pieces.
            let sign = turn(i) > 0
            var end = i
            while end + 1 <= (closed ? i + n - 2 : last), at(end).distance(to: at(end + 1)) < short, abs(turn(end + 1)) > 1e-9, (turn(end + 1) > 0) == sign { end += 1 }
            guard end > i else { i += 1; continue }
            let before = at(i - 1), first = at(i), lastPoint = at(end), after = at(end + 1)
            let d1 = first - before, d2 = after - lastPoint
            let denominator = AreaGeometry.cross(d1, d2)
            if abs(denominator) > 1e-9, isSharp(before, first, first + d2) {
                // Where the legs' lines meet.
                let s = AreaGeometry.cross(lastPoint - before, d2) / denominator
                let corner = before + d1 * s
                let arc = (i..<end).reduce(0.0) { $0 + at($1).distance(to: at($1 + 1)) }
                let bend = Double.pi - opening(before, first, first + d2)
                // Only an arc about as round as the satin's own corners, and a corner close by.
                if arc <= bend * radius * 1.6 + 0.5, corner.distance(to: (first + lastPoint) * 0.5) <= radius * 3 + width {
                    replaced[((i % n) + n) % n] = corner
                    for k in (i + 1)...end { removed.insert(((k % n) + n) % n) }
                }
            }
            i = end + 1
        }
        guard !replaced.isEmpty else { return line }
        result = line.indices.compactMap { removed.contains($0) ? nil : (replaced[$0] ?? line[$0]) }
        return result
    }

    /// One stitch of a span next to a corner: its two ends, and whether each lies on the column's edge (so pull
    /// compensation pushes it outward) or on a seam or cut line (left where it is).
    struct Rung { var left: Point; var right: Point; var leftOnEdge: Bool; var rightOnEdge: Bool }

    /// What the engine needs to know about a corner to sew the legs beside it.
    struct Corner {
        let kind: Kind
        let inner: Point, outer: Point
        /// From the inside corner toward the point.
        let tip: Point
        /// The outside edges of the leg before and the leg after: a point on each and its direction.
        let outerBefore: (Point, Point), outerAfter: (Point, Point)
        /// The cap's stitches, from the point back to the cut line (empty for a mitre).
        let cap: [(Point, Point)]
    }

    /// The corner at edge pair `pair`, between `previous` and `next`: mitre or cap (a cap whose stitches would pass
    /// `capMaximum` becomes a mitre), with the cap's stitches `spacing` apart.
    static func corner(previous: (Point, Point), pair: (Point, Point), next: (Point, Point), spacing: Double) -> Corner {
        let middlePrevious = (previous.0 + previous.1) * 0.5, middle = (pair.0 + pair.1) * 0.5, middleNext = (next.0 + next.1) * 0.5
        // The inside corner is the one on the side the column turns toward: nearer the line joining its neighbours.
        let chord = (middlePrevious + middleNext) * 0.5
        let firstInside = pair.0.distance(to: chord) < pair.1.distance(to: chord)
        let inner = firstInside ? pair.0 : pair.1, outer = firstInside ? pair.1 : pair.0
        let outerBefore = (outer, (firstInside ? previous.1 : previous.0) - outer), outerAfter = (outer, (firstInside ? next.1 : next.0) - outer)
        let tip = unit(outer - inner)
        var kind: Kind = opening(middlePrevious, middle, middleNext) < capBelow * .pi / 180 ? .cap : .mitre
        var cap: [(Point, Point)] = []
        if kind == .cap {
            // Stitches across the corner, square to the tip direction, from just short of the point back to the cut line
            // through the inside corner.
            let depth = dot(outer - inner, tip), across = Point(-tip.y, tip.x)
            var q = depth - spacing / 2
            while q > -1e-9 {
                let base = inner + tip * q
                if let a = meet(base, across, outerBefore.0, outerBefore.1), let b = meet(base, across, outerAfter.0, outerAfter.1), a.distance(to: b) > 0.05 { cap.append((a, b)) }
                q -= spacing
            }
            if let widest = cap.last, widest.0.distance(to: widest.1) > capMaximum { kind = .mitre; cap = [] }
        }
        return Corner(kind: kind, inner: inner, outer: outer, tip: tip, outerBefore: outerBefore, outerAfter: outerAfter, cap: cap)
    }

    /// The stitches across the span from edge pair `a` to edge pair `b` when either is a corner (`startCorner`,
    /// `endCorner`): square to the span, about `spacing` apart, between its two edges, and cut off at a corner's seam
    /// (a mitre, overlapping half `mitreOverlap` past it) or at the cut line through its inside corner (a cap,
    /// overlapping half a row past it). Without a corner at `a`, the first stitch is `a`'s own and comes only with
    /// `includeStart` (the span before already sewed it); without one at `b`, the last stitch is `b`'s own.
    static func rungs(from a: (Point, Point), to b: (Point, Point), startCorner: Corner?, endCorner: Corner?, spacing: Double, includeStart: Bool) -> [Rung] {
        let middleA = (a.0 + a.1) * 0.5, middleB = (b.0 + b.1) * 0.5
        let advance = middleA.distance(to: middleB)
        guard advance > 1e-6 else { return [] }
        let along = (middleB - middleA) * (1 / advance), across = Point(-along.y, along.x)
        // How far along the span the stitches reach: past a corner, out to its point.
        let reach = { (corner: Corner?, fallback: Double) in corner.map { [$0.inner, $0.outer].map { dot($0 - middleA, along) } } ?? [fallback] }
        let low = (reach(startCorner, 0) + [0]).min()!, high = (reach(endCorner, advance) + [advance]).max()!
        // Positions along the span, `spacing` apart. Next to a normal pair they land exactly on it.
        var positions: [Double] = []
        if endCorner == nil { var s = advance; while s >= low - 1e-9 { positions.insert(s, at: 0); s -= spacing } }
        else if startCorner == nil { var s = 0.0; while s <= high + 1e-9 { positions.append(s); s += spacing } }
        else { var s = low; while s <= high + 1e-9 { positions.append(s); s += spacing } }
        if startCorner == nil && !includeStart { positions.removeAll { abs($0) < 1e-9 } }
        var result: [Rung] = []
        for s in positions {
            let base = middleA + along * s
            // Where the stitch's line meets the left and right edges of the span.
            guard var left = meet(base, across, a.0, b.0 - a.0), var right = meet(base, across, a.1, b.1 - a.1) else { continue }
            var leftOnEdge = true, rightOnEdge = true
            var keep = true
            // Cut off at each corner: its seam or cut line, and the outside edge of the other leg.
            for (corner, isStart) in [(startCorner, true), (endCorner, false)] {
                guard let corner, keep else { continue }
                let (origin, normal, limit): (Point, Point, Double)
                switch corner.kind {
                case .mitre:
                    // Square to the seam, pointing away from this span.
                    var n = Point(-corner.tip.y, corner.tip.x)
                    let inside = isStart ? middleB : middleA
                    if dot(inside - corner.inner, n) > 0 { n = n * -1 }
                    (origin, normal, limit) = (corner.inner, n, mitreOverlap / 2)
                case .cap:
                    (origin, normal, limit) = (corner.inner, corner.tip, spacing / 2)
                }
                guard let cut = clip(left, right, origin: origin, normal: normal, limit: limit) else { keep = false; continue }
                if cut.0.distance(to: left) > 1e-9 { leftOnEdge = false }
                if cut.1.distance(to: right) > 1e-9 { rightOnEdge = false }
                (left, right) = cut
                // The other leg's outside edge bounds the overlap near the point.
                let other = isStart ? corner.outerBefore : corner.outerAfter
                var side = Point(-other.1.y, other.1.x)
                if dot(corner.inner - other.0, side) < 0 { side = side * -1 }
                guard let inside = clip(left, right, origin: other.0, normal: side * -1, limit: 0) else { keep = false; continue }
                if inside.0.distance(to: left) > 1e-9 { leftOnEdge = true }
                if inside.1.distance(to: right) > 1e-9 { rightOnEdge = true }
                (left, right) = inside
            }
            guard keep, left.distance(to: right) > 0.05 else { continue }
            result.append(Rung(left: left, right: right, leftOnEdge: leftOnEdge, rightOnEdge: rightOnEdge))
        }
        return result
    }

    /// The part of segment a–b where (p − origin)·normal ≤ limit, or nil if none of it is.
    static func clip(_ a: Point, _ b: Point, origin: Point, normal: Point, limit: Double) -> (Point, Point)? {
        let fa = dot(a - origin, normal) - limit, fb = dot(b - origin, normal) - limit
        if fa > 0 && fb > 0 { return nil }
        if fa <= 0 && fb <= 0 { return (a, b) }
        let m = a + (b - a) * (fa / (fa - fb))
        return fa <= 0 ? (a, m) : (m, b)
    }
    /// Where the line through `p` along `d` meets the line through `q` along `e`, or nil if they're parallel.
    static func meet(_ p: Point, _ d: Point, _ q: Point, _ e: Point) -> Point? {
        let denominator = AreaGeometry.cross(d, e)
        guard abs(denominator) > 1e-12 else { return nil }
        return p + d * (AreaGeometry.cross(q - p, e) / denominator)
    }
    static func dot(_ a: Point, _ b: Point) -> Double { a.x * b.x + a.y * b.y }
    static func unit(_ p: Point) -> Point { let l = hypot(p.x, p.y); return l > 1e-12 ? p * (1 / l) : Point(1, 0) }
}
