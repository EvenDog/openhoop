// Fill styles other than straight rows. Contour fills sew rings that follow the shape's outline inward; radial
// fills sew rays fanning out from a center point. Both return their stitches as a few long sections in sewing
// order; AreaEngine.fill adds underlay and joins the sections with travel runs. (Wave fills are straight rows
// bent into a ripple; they live in AreaEngine.rows.)
import Foundation

enum FillStyles {
    /// Contour fill: rings `spacing` apart, shrinking inward from the edge of `region` until nothing is left, each
    /// sewn all the way round in stitches of about `length`. After each ring the needle steps with one short stitch
    /// onto the nearest ring not yet sewn, so the fill sews as a few long spirals; when the nearest ring is too far
    /// for a short step (another lobe of the shape), a new section starts. Sewing begins on an outermost ring, at
    /// the point nearest `start` if given.
    static func contour(in region: [[Point]], spacing: Double, length: Double, start: Point?) throws -> [[Point]] {
        // Every ring at every depth: each depth's inset can have several rings (lobes, and the edges of holes).
        // Each depth shrinks the one before by a row spacing (the first by half of one), since the geometry library
        // only offsets up to 10 mm at a time.
        var loops: [[Point]] = [], round: [Bool] = [], outermost = 0, total = 0, inset = region
        for level in 0... {
            try Task.checkCancellation()
            inset = try AreaGeometry.offset(inset, by: level == 0 ? -spacing / 2 : -spacing)
            if inset.isEmpty { break }
            for ring in inset {
                let loop = resampled(ring, length: length)
                if loop.count >= 3 { loops.append(loop); round.append(isRound(ring)); total += loop.count }
            }
            if level == 0 { outermost = loops.count }   // loops before this index are the first depth's
            guard level < 5000, total <= 1_000_000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
        }
        guard !loops.isEmpty else { return [] }

        // First the order: each ring, starting at the point nearest where the last one ended, and whether the needle
        // can step straight onto it from there (false starts a new section).
        var order: [(loop: [Point], round: Bool, joined: Bool)] = []
        var needle = start ?? loops[0][0], remaining = Set(loops.indices)
        let shortStep = 2 * spacing + length   // the longest step that's sewn straight across to the next ring
        while !remaining.isEmpty {
            try Task.checkCancellation()
            // The ring point nearest the needle, among the rings not yet sewn.
            var best = (ring: -1, index: 0, distance: Double.infinity)
            // In ring order: a Set's own order changes from run to run, and where two rings are equally near, the
            // first one checked wins, so the same fill must always check them in the same order.
            for r in remaining.sorted() where !order.isEmpty || r < outermost {
                for (i, p) in loops[r].enumerated() { let d = p.distance(to: needle); if d < best.distance { best = (r, i, d) } }
            }
            let ring = loops[best.ring]
            let loop = Array(ring[best.index...] + ring[..<best.index]) + [ring[best.index]]   // all the way round
            order.append((loop, round[best.ring], !order.isEmpty && best.distance <= shortStep && AreaGeometry.segmentInside(needle, loop[0], rings: region)))
            needle = loop.last!; remaining.remove(best.ring)
        }
        // Then the stitches. Stepping straight across after every ring lines the steps up into a visible seam from the
        // edge to the middle, so between two round rings the needle spirals instead: over the lap, it drifts from this
        // ring to the next (by the share of the lap sewn so far), ending where the next ring begins. A run of spiral
        // laps starts and ends with a plain ring, so the edges stay covered. Rings with sharp corners keep the step:
        // matching points between them bends the laps across each other near the corners.
        func spirals(_ k: Int) -> Bool { k >= 0 && k + 1 < order.count && order[k + 1].joined && order[k].round && order[k + 1].round }
        var sections: [[Point]] = []
        for k in order.indices {
            var stitches: [Point] = []
            if !spirals(k - 1) || !spirals(k) { stitches = order[k].loop }   // a plain ring, all the way round
            if spirals(k) { stitches += spiral(order[k].loop, into: order[k + 1].loop, length: length).dropFirst(stitches.isEmpty ? 0 : 1) }
            if order[k].joined, var last = sections.popLast() {
                // A spiral lap already ends on this ring's first point. After a plain ring the needle is still on that
                // ring, so it steps across to this one's first point, split into stitches no longer than `length`
                // (dropping the first point instead made one stitch reach the second point, over the machine's limit).
                if let end = last.last, let first = stitches.first, end.distance(to: first) > 0.00001 {
                    last += AreaGeometry.sampled([end, first], length: length).dropFirst()
                }
                last += stitches.dropFirst(); sections.append(last)
            } else { sections.append(stitches) }
        }
        return sections
    }

    /// True when `ring` has no sharp corner: it never turns more than 60° at one point.
    static func isRound(_ ring: [Point]) -> Bool {
        let n = ring.count
        guard n >= 3 else { return false }
        for i in 0..<n {
            let a = ring[(i + n - 1) % n], b = ring[i], c = ring[(i + 1) % n], u = b - a, v = c - b
            let lengths = u.distance(to: Point(0, 0)) * v.distance(to: Point(0, 0))
            if lengths > 0, (u.x * v.x + u.y * v.y) / lengths < cos(60 * Double.pi / 180) { return false }
        }
        return true
    }

    /// The lap `loop` (closed: its last point is its first) drifting into `next` (closed the same way): each point
    /// moves toward the point the same share of the way round `next` by the share of the lap sewn so far, ending on
    /// `next`'s first point. Stitches that come out longer than `length` are split.
    static func spiral(_ loop: [Point], into next: [Point], length: Double) -> [Point] {
        let here = Arc(loop), there = Arc(next)
        guard here.length > 0, there.length > 0 else { return loop }
        var result: [Point] = []
        for (p, along) in zip(loop, here.lengths) {
            let t = along / here.length, q = p + (there.at(t) - p) * t
            if let last = result.last, last.distance(to: q) > length {
                let pieces = Int(ceil(last.distance(to: q) / length))
                for piece in 1..<pieces { result.append(last + (q - last) * (Double(piece) / Double(pieces))) }
            }
            result.append(q)
        }
        return result
    }

    /// A polyline measured along its length, to find the point a given share of the way along it.
    struct Arc {
        let points: [Point], lengths: [Double]
        var length: Double { lengths.last ?? 0 }
        init(_ points: [Point]) { self.points = points; lengths = zip(points, points.dropFirst()).reduce(into: [0.0]) { $0.append($0.last! + $1.0.distance(to: $1.1)) } }
        /// The point `fraction` (0…1) of the way along.
        func at(_ fraction: Double) -> Point {
            let target = length * max(0, min(1, fraction))
            guard let i = lengths.firstIndex(where: { $0 >= target }), i > 0 else { return points[0] }
            let span = lengths[i] - lengths[i - 1]
            return points[i - 1] + (points[i] - points[i - 1]) * (span > 0 ? (target - lengths[i - 1]) / span : 0)
        }
    }

    /// Radial fill: rays from `center` out to the edge of `region`, sewn alternately inward and outward, so each
    /// ray joins the next with a short stitch along the edge or near the center. Rays are `spacing` apart at the
    /// farthest edge; nearer the center, where they crowd together, every other ray stops short (then every fourth,
    /// and so on), so the middle doesn't pile up with thread. Where a ray crosses the shape more than once (notches,
    /// holes, or a center outside the shape), each crossing continues the matching run of the ray before it, or
    /// starts a new section. The first ray points toward `start` if given.
    static func radial(in region: [[Point]], center: Point, spacing: Double, length: Double, start: Point?) throws -> [[Point]] {
        let points = region.flatMap { $0 }
        guard let reach = points.map({ $0.distance(to: center) }).max(), reach > spacing else { return [] }
        // A multiple of 64 rays, so the stop-short pattern (every 2nd, 4th … 64th ray) repeats evenly all the way round.
        let rayCount = (Int(ceil(2 * .pi * reach / spacing)) + 63) / 64 * 64
        guard rayCount <= 40_000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
        let step = 2 * .pi / Double(rayCount)
        let firstAngle = start.map { atan2($0.y - center.y, $0.x - center.x) } ?? 0
        /// How close to the center ray `i` comes. A ray whose index is divisible by 2^level is one of the rays kept
        /// where neighbors 2^level apart are still at least about `spacing` apart (a gap of r · step · 2^level).
        func innerRadius(_ i: Int) -> Double {
            let level = Double(min(6, i == 0 ? 6 : i.trailingZeroBitCount))
            return max(spacing, 0.7 * spacing / (step * pow(2, level)))
        }

        // Ray ends lie exactly on the edge, where "inside or not" is a coin toss, so steps between rays are checked
        // against the shape grown by 0.01 mm.
        let bounds = (try? AreaGeometry.offset(region, by: 0.01)) ?? region
        struct Run { var section: Int; var near: Double; var far: Double; var inward: Bool }
        var sections: [[Point]] = [], previous: [Run] = [], total = 0
        for i in 0..<rayCount {
            if i % 32 == 0 { try Task.checkCancellation() }
            let angle = firstAngle + Double(i) * step, direction = Point(cos(angle), sin(angle))
            let pieces = AreaGeometry.clippedSegment(center + direction * innerRadius(i), center + direction * (reach + 1), rings: region)
            var current: [Run] = [], used = Set<Int>()
            for (a, b) in pieces where a.distance(to: b) > 0.05 {
                let near = a.distance(to: center), far = b.distance(to: center)
                // Carry on the run of the previous ray that overlaps this piece, going the other way along it.
                var run: Run?
                if let k = previous.indices.first(where: { !used.contains($0) && min(previous[$0].far, far) - max(previous[$0].near, near) > 0 }) {
                    let inward = !previous[k].inward
                    if let end = sections[previous[k].section].last, AreaGeometry.segmentInside(end, inward ? b : a, rings: bounds) {
                        used.insert(k); run = Run(section: previous[k].section, near: near, far: far, inward: inward)
                        sections[run!.section] += AreaGeometry.sampled([end, inward ? b : a], length: length).dropFirst()
                    }
                }
                if run == nil { run = Run(section: sections.count, near: near, far: far, inward: true); sections.append([]) }
                // Stitches along the ray, staggered from ray to ray so needle holes don't line up.
                var distances = [near], d = floor(near / length) * length + Double(i % 4) * length / 4
                while d <= near + 0.00001 { d += length }
                while d < far - 0.3 { if d - near >= 0.3 { distances.append(d) }; d += length }   // no stitches under 0.3 mm at the ends
                distances.append(far)
                if run!.inward { distances.reverse() }
                let stitches = distances.map { center + direction * $0 }
                // The section may already end where these stitches begin. That point was worked out another way, so
                // it's only nearly equal; an exact == missed it and sewed the same hole twice.
                if let last = sections[run!.section].last, last.distance(to: stitches[0]) < 0.001 { sections[run!.section] += stitches.dropFirst() } else { sections[run!.section] += stitches }
                total += stitches.count
                guard total <= 1_000_000 else { throw DesignError.invalid("Fill exceeds the one-million-stitch limit.") }
                current.append(run!)
            }
            // A ray that stops short of the shape (near the center, where the edge dips in) has nothing to sew;
            // the next ray carries on from the one before it.
            if !current.isEmpty { previous = current }
        }
        return sections.filter { $0.count >= 2 }
    }

    /// A ring as evenly spaced stitch points about `length` apart, keeping its real corners (turns sharper than
    /// 25°) so stitches don't cut across them. Points closer than 0.3 mm are merged. The ring isn't closed: its
    /// last point leads back to the first.
    static func resampled(_ ring: [Point], length: Double) -> [Point] {
        let n = ring.count
        guard n >= 3 else { return ring }
        func turn(_ i: Int) -> Double {
            let a = ring[(i + n - 1) % n], b = ring[i], c = ring[(i + 1) % n]
            let u = b - a, v = c - b
            return abs(atan2(AreaGeometry.cross(u, v), u.x * v.x + u.y * v.y))
        }
        var corners = ring.indices.filter { turn($0) > 25 * .pi / 180 }
        if corners.isEmpty { corners = [0] }
        var result: [Point] = []
        for (k, c) in corners.enumerated() {
            // The stretch of ring from this corner to the next, split into equal stitches.
            let next = corners[(k + 1) % corners.count]
            var stretch = [ring[c]], i = (c + 1) % n
            while true { stretch.append(ring[i]); if i == next { break }; i = (i + 1) % n }
            let arcLength = AreaGeometry.pathLength(stretch)
            let pieces = max(1, Int(ceil(arcLength / length)))
            for piece in 0..<pieces { result.append(point(along: stretch, at: arcLength * Double(piece) / Double(pieces))) }
        }
        var merged: [Point] = []
        for p in result where merged.last.map({ $0.distance(to: p) >= 0.3 }) ?? true { merged.append(p) }
        if merged.count > 1, merged.last!.distance(to: merged[0]) < 0.3 { merged.removeLast() }
        return merged
    }

    /// The point `distance` mm along a path.
    private static func point(along path: [Point], at distance: Double) -> Point {
        var remaining = distance
        for (a, b) in zip(path, path.dropFirst()) {
            let d = a.distance(to: b)
            if remaining <= d { return d > 0 ? a + (b - a) * (remaining / d) : a }
            remaining -= d
        }
        return path.last!
    }
}
