// A quicker way to ask "is this point inside the shape?" when the same shape is asked about thousands of times, as
// travel routing does. It gives exactly the same answers as `AreaGeometry.contains` and `AreaGeometry.segmentInside`,
// worked out with the same arithmetic; it only leaves out edges of the shape that can't change the answer.
import Foundation

struct InsideTest {
    let rings: [[Point]]
    /// Every edge of every ring, as its start, its end, and end minus start (worked out once instead of per question).
    private var starts: [Point] = [], ends: [Point] = [], directions: [Point] = []
    /// The shape cut into horizontal bands. Each band lists the edges that reach into it, or come within `margin` of it.
    private var bands: [[Int]] = []
    private var bottom = 0.0, bandHeight = 1.0
    /// How far outside a band an edge may be and still be listed. Much more than the 0.00001 mm "on the edge" distance
    /// `contains` allows, so rounding can never leave out an edge that matters.
    private static let margin = 0.001

    /// Sorts the shape's edges into bands. A shape the bands can't safely be used for (a ring of fewer than three
    /// points, or a coordinate that isn't a real number) is left unsorted, and every question goes to `AreaGeometry`.
    init(_ rings: [[Point]]) {
        self.rings = rings
        guard !rings.isEmpty, rings.allSatisfy({ $0.count >= 3 && $0.allSatisfy(\.finite) }) else { return }
        for ring in rings {
            for i in ring.indices {
                let c = ring[i], d = ring[(i + 1) % ring.count]
                starts.append(c); ends.append(d); directions.append(d - c)
            }
        }
        let ys = rings.flatMap { $0.map(\.y) }
        bottom = ys.min()!
        let height = ys.max()! - bottom
        // About four edges per band, so a point is checked against a handful of edges instead of all of them.
        let count = max(1, min(starts.count / 4, 1024))
        bandHeight = height > 0 ? height / Double(count) : 1
        bands = Array(repeating: [], count: count)
        for e in starts.indices {
            let low = min(starts[e].y, ends[e].y) - Self.margin, high = max(starts[e].y, ends[e].y) + Self.margin
            for band in band(low)...band(high) { bands[band].append(e) }
        }
    }

    /// Which band height `y` falls in (the nearest end band when it's above or below the shape). Never goes down as
    /// `y` goes up, which is what makes the bands safe: an edge listed in the bands for its lowest and highest
    /// heights (plus the margin) is listed in the band of every height in between.
    private func band(_ y: Double) -> Int {
        let position = ((y - bottom) / bandHeight).rounded(.down)
        return Int(max(0, min(Double(bands.count - 1), position)))
    }

    /// The same as `AreaGeometry.contains(p, rings:)`: true when `p` is inside the shape or on its edge.
    /// That counts how many edges a line from `p` to the right crosses (odd means inside), unless `p` lies within
    /// 0.00001 mm of an edge. Only edges that reach `p`'s height can do either, and all of those are in `p`'s band.
    func contains(_ p: Point) -> Bool {
        guard !bands.isEmpty, p.finite else { return AreaGeometry.contains(p, rings: rings) }
        var inside = false
        for e in bands[band(p.y)] {
            let a = starts[e], b = ends[e]
            if p.distance(to: AreaGeometry.projection(p, a, b)) < 0.00001 { return true }
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }

    /// The same as `AreaGeometry.segmentInside(a, b, rings:)`: true when the straight line from `a` to `b` stays inside
    /// the shape. `aInside` and `bInside` are `contains(a)` and `contains(b)`, for a caller that already knows them.
    func segmentInside(_ a: Point, _ b: Point, aInside: Bool? = nil, bInside: Bool? = nil) -> Bool {
        guard !bands.isEmpty else { return AreaGeometry.segmentInside(a, b, rings: rings) }
        guard aInside ?? contains(a), bInside ?? contains(b) else { return false }
        // From here on, the same sums as `AreaGeometry.segmentInside`: find where the line meets the edges, and check
        // the middle of each piece between those places. (The edges come in the same order; it wouldn't matter anyway,
        // since the places are sorted.)
        let u = b - a; var cuts = [0.0, 1.0]
        let squared = u.x * u.x + u.y * u.y
        if squared < 1e-16 { return true }
        for e in starts.indices {
            let c = starts[e], v = directions[e], den = AreaGeometry.cross(u, v)
            if abs(den) > 1e-10 {
                // Where along the edge the line meets it (s), then where along the line (t). Most edges never reach the
                // line, so checking s first skips working out t for them; the answer is the same.
                let s = AreaGeometry.cross(c - a, u) / den
                if s >= 0 && s <= 1 { let t = AreaGeometry.cross(c - a, v) / den; if t > 0 && t < 1 { cuts.append(t) } }
            } else if abs(AreaGeometry.cross(c - a, u)) < 1e-8 {
                for p in [c, ends[e]] { let t = ((p - a).x * u.x + (p - a).y * u.y) / squared; if t > 0 && t < 1 { cuts.append(t) } }
            }
        }
        cuts.sort()
        return zip(cuts, cuts.dropFirst()).allSatisfy { contains(a + u * (($0 + $1) / 2)) }
    }
}
