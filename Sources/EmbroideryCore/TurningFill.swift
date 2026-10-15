// Turning fill, made with stitch angles: lines drawn across a
// fill set which way its stitches run there, and between two lines the stitches turn gradually from one direction
// to the other, so a fill can follow a curved shape the way a satin column does.
import Foundation

enum TurningFill {
    /// The fill's rows as stitches. Each angle line is first stretched to the shape's edge on both sides. Between two
    /// neighbouring lines, in-between lines are laid by sliding each end along from one line's end to the other's,
    /// enough of them that rows are `spacing` apart where they spread widest; before the first line and after the
    /// last, rows run parallel to it (on a ring, where every line runs from the outside edge to the hole, the rows
    /// turn from the last line back round to the first instead). Where rows crowd together (the inside of a bend), each row is cut short where it
    /// comes closer than half the spacing to the rows sewn just before it, like short stitches on a satin, so the inside
    /// doesn't pile up thread. `start` picks which angle line the rows begin from (the nearest one).
    static func rows(in region: [[Point]], angleLines: [[Point]], spacing: Double, length: Double, start: Point?) throws -> [[Point]] {
        let points = region.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return [] }
        let reach = hypot(maxX - minX, maxY - minY) + 1   // longer than any line across the shape
        // Each angle line stretched across the shape: the piece of its line, through its middle, inside the shape.
        var chords: [(a: Point, b: Point)] = angleLines.compactMap { line in
            guard line.count >= 2, line[0].distance(to: line[1]) > 0.01 else { return nil }
            let middle = (line[0] + line[1]) * 0.5, u = (line[1] - line[0]) * (1 / line[0].distance(to: line[1]))
            let pieces = AreaGeometry.clippedSegment(middle - u * reach, middle + u * reach, rings: region)
            return pieces.min { gap(middle, $0) < gap(middle, $1) }.map { (a: $0.0, b: $0.1) }
        }
        guard !chords.isEmpty else { return [] }
        // One line sets the direction for the whole fill: ordinary rows along it.
        if chords.count == 1 { return try AreaEngine.rows(in: region, angle: direction(chords[0]), spacing: spacing, length: length) }
        // Distances are measured inside the shape (round its bends, not across a gap between its arms), by the same
        // route finder travel runs use; straight across if the shape is too complex for it.
        let router = TravelRouter(edges: region.map { Design.cornerNodes($0).map(\.point) }, bounds: (try? AreaGeometry.offset(region, by: 0.05)) ?? region)
        func inside(_ p: Point, _ q: Point) -> Double { router?.route(from: p, to: q).map(AreaGeometry.pathLength) ?? p.distance(to: q) }
        // Order: from the line nearest the start, each time the nearest one left.
        var ordered = [chords.remove(at: start.map { s in chords.indices.min { inside(mid(chords[$0]), s) < inside(mid(chords[$1]), s) }! } ?? 0)]
        while !chords.isEmpty {
            let last = mid(ordered.last!)
            ordered.append(chords.remove(at: chords.indices.min { inside(mid(chords[$0]), last) < inside(mid(chords[$1]), last) }!))
        }
        // Points on the shape's edge, measured as how far round their ring they are (mm from its first point), so the
        // ends of the in-between lines can slide along the edge like a satin's rails.
        let lengths = region.map { ring in ring.indices.map { ring[$0].distance(to: ring[($0 + 1) % ring.count]) } }
        let totals = lengths.map { $0.reduce(0, +) }
        func locate(_ p: Point) -> (ring: Int, s: Double)? {
            var best: (ring: Int, s: Double, d: Double)?
            for (r, ring) in region.enumerated() {
                var s0 = 0.0
                for i in ring.indices {
                    let q = AreaGeometry.projection(p, ring[i], ring[(i + 1) % ring.count]), d = p.distance(to: q)
                    if best == nil || d < best!.d { best = (r, s0 + ring[i].distance(to: q), d) }
                    s0 += lengths[r][i]
                }
            }
            return best.flatMap { $0.d < 0.05 ? ($0.ring, $0.s) : nil }
        }
        func wrap(_ s: Double, _ r: Int) -> Double { let t = s.truncatingRemainder(dividingBy: totals[r]); return t < 0 ? t + totals[r] : t }
        func pointAt(_ r: Int, _ s: Double) -> Point {
            var s = wrap(s, r)
            for i in region[r].indices {
                if s <= lengths[r][i] || i == region[r].count - 1 { let a = region[r][i], b = region[r][(i + 1) % region[r].count]; return a + (b - a) * (lengths[r][i] > 0 ? min(1, s / lengths[r][i]) : 0) }
                s -= lengths[r][i]
            }
            return region[r][0]
        }
        /// The way along the edge from `x` (an end of one line) to `y` (an end of the next) that doesn't pass `z` (the
        /// first line's other end): its ring, start and signed length (negative runs backwards round the ring). nil if
        /// they're not on the same ring.
        func edge(_ x: Point, _ y: Point, avoiding z: Point) -> (ring: Int, s: Double, delta: Double)? {
            guard let lx = locate(x), let ly = locate(y), lx.ring == ly.ring else { return nil }
            let r = lx.ring, forward = wrap(ly.s - lx.s, r), backward = forward - totals[r]
            guard let lz = locate(z), lz.ring == r else { return (r, lx.s, abs(forward) <= abs(backward) ? forward : backward) }
            return (r, lx.s, wrap(lz.s - lx.s, r) < forward ? backward : forward)   // going forward would pass z
        }
        func edgeLength(_ e: (ring: Int, s: Double, delta: Double)?, _ x: Point, _ y: Point) -> Double { e.map { abs($0.delta) } ?? inside(x, y) }
        // Each line's ends the same way round as the one before, so in-between lines don't cross over: whichever
        // pairing makes the shorter way along the edges.
        for k in ordered.indices.dropFirst() {
            let (p, c) = (ordered[k - 1], ordered[k])
            let same = edgeLength(edge(p.a, c.a, avoiding: p.b), p.a, c.a) + edgeLength(edge(p.b, c.b, avoiding: p.a), p.b, c.b)
            let swapped = edgeLength(edge(p.a, c.b, avoiding: p.b), p.a, c.b) + edgeLength(edge(p.b, c.a, avoiding: p.a), p.b, c.a)
            if swapped < same { ordered[k] = (c.b, c.a) }
        }
        // The guide lines, in sewing order.
        var guides: [(a: Point, b: Point)] = []
        /// The part of the shape beyond `chord` (away from the other lines), filled with ordinary rows along it, in
        /// sewing order: towards the line when `towards`, away from it otherwise. The shape is cut along the line, and
        /// the pieces that hold none of the other lines are beyond it.
        func beyond(_ chord: (a: Point, b: Point), others: [(a: Point, b: Point)], towards: Bool) throws -> [[Point]] {
            let u = (chord.b - chord.a) * (0.05 / max(chord.a.distance(to: chord.b), 1e-9))   // a little past each end, to cut right through
            let pieces = try AreaGeometry.subtracting(Design.knifeBand([chord.a - u, chord.b + u]), from: region)
            let far = pieces.filter { piece in !others.contains { AreaGeometry.contains(mid($0), rings: piece) } }
            var rows = try far.flatMap { try AreaEngine.rows(in: $0, angle: direction(chord), spacing: spacing, length: length) }
            func distance(_ row: [Point]) -> Double { gap((row.first! + row.last!) * 0.5, (chord.a, chord.b)) }
            rows.sort { towards ? distance($0) > distance($1) : distance($0) < distance($1) }
            return rows.enumerated().map { $0.offset % 2 == 0 ? $0.element : $0.element.reversed() }   // back and forth
        }
        func clipped(_ line: (a: Point, b: Point)) -> [(Point, Point)] {
            let length = line.a.distance(to: line.b)
            guard length > 1e-6 else { return [] }
            let u = (line.b - line.a) * (1 / length)
            // Stretched to the edge on both sides, but only the stretch along the line itself counts: a piece
            // entirely beyond either end belongs to another part of the shape (the other arm of a U).
            return AreaGeometry.clippedSegment(line.a - u * reach, line.b + u * reach, rings: region).filter { piece in
                func along(_ p: Point) -> Double { (p.x - line.a.x) * u.x + (p.y - line.a.y) * u.y }   // how far along the line
                let s0 = along(piece.0), s1 = along(piece.1)
                return max(s0, s1) > 0.01 && min(s0, s1) < length - 0.01
            }
        }
        // Each pair of neighbouring lines, with the way along the edge each end slides from one to the other.
        typealias Edge = (ring: Int, s: Double, delta: Double)
        var spans: [(p: (a: Point, b: Point), c: (a: Point, b: Point), edgeA: Edge?, edgeB: Edge?)] = []
        // On a ring (every line running from the outside edge to the same hole's edge) the lines go round it in
        // order, and the stitches turn from the last line back round to the first, so the whole ring is covered.
        // Each line's outside end first, and how far round each ring its ends are.
        let ends = ordered.compactMap { chord -> (a: Point, b: Point, sa: Double, sb: Double, hole: Int)? in
            guard let x = locate(chord.a), let y = locate(chord.b) else { return nil }
            if x.ring == 0, y.ring > 0 { return (chord.a, chord.b, x.s, y.s, y.ring) }
            if y.ring == 0, x.ring > 0 { return (chord.b, chord.a, y.s, x.s, x.ring) }
            return nil
        }
        let looped = ordered.count >= 2 && ends.count == ordered.count && Set(ends.map(\.hole)).count == 1
        if looped {
            // Round the outside edge from the line nearest the start, and round the hole in the same direction (a
            // ring's points can run either way round, which the sign of its area tells).
            let hole = ends[0].hole, first = ends[0].sa
            let round = ends.sorted { wrap($0.sa - first, 0) < wrap($1.sa - first, 0) }
            let sameWay = (AreaGeometry.area(region[0]) > 0) == (AreaGeometry.area(region[hole]) > 0)
            for k in round.indices {
                let (p, c) = (round[k], round[(k + 1) % round.count])
                let alongHole = sameWay ? wrap(c.sb - p.sb, hole) : -wrap(p.sb - c.sb, hole)
                spans.append(((p.a, p.b), (c.a, c.b), (0, p.sa, wrap(c.sa - p.sa, 0)), (hole, p.sb, alongHole)))
            }
        } else {
            for k in 0..<(ordered.count - 1) {
                let (p, c) = (ordered[k], ordered[k + 1])
                spans.append((p, c, edge(p.a, c.a, avoiding: p.b), edge(p.b, c.b, avoiding: p.a)))
            }
        }
        // Between each pair of neighbouring lines, in-between lines that turn from one to the other.
        for (p, c, edgeA, edgeB) in spans {
            // Each end slides along the edge (straight across if it can't), with enough lines for rows `spacing`
            // apart along the longer of the two edges.
            let count = max(1, Int(ceil(max(edgeLength(edgeA, p.a, c.a), edgeLength(edgeB, p.b, c.b)) / spacing)))
            func slide(_ e: (ring: Int, s: Double, delta: Double)?, _ x: Point, _ y: Point, _ t: Double) -> Point { e.map { pointAt($0.ring, $0.s + $0.delta * t) } ?? x + (y - x) * t }
            for j in 0..<count {
                let t = Double(j) / Double(count)
                guides.append((a: slide(edgeA, p.a, c.a, t), b: slide(edgeB, p.b, c.b, t)))
            }
        }
        if !looped { guides.append(ordered[ordered.count - 1]) }   // round a ring, the first line already began it
        guard guides.count <= 20000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
        // The rows, each cut short where it crowds the last few rows sewn.
        var rows: [[Point]] = [], recent: [[Point]] = []
        for guide in guides {
            try Task.checkCancellation()
            for piece in clipped(guide) {
                var row = AreaGeometry.sampled([piece.0, piece.1], length: 0.25)
                func crowded(_ p: Point) -> Bool { recent.contains { other in other.contains { $0.distance(to: p) < spacing * 0.5 } } }
                while let first = row.first, crowded(first) { row.removeFirst() }
                while let last = row.last, crowded(last) { row.removeLast() }
                guard let a = row.first, let b = row.last, a.distance(to: b) >= StitchEngine.smallestStitch else { continue }
                recent.append(AreaGeometry.sampled([a, b], length: max(0.2, spacing * 0.25)))
                if recent.count > 8 { recent.removeFirst() }
                rows.append([a, b])
            }
        }
        // Back and forth, each row split into stitches staggered by quarters of a stitch length from row to row,
        // after the rows beyond the first line and before those beyond the last.
        let turning = rows.enumerated().map { index, row in
            let (a, b) = index % 2 == 0 ? (row[0], row[1]) : (row[1], row[0])
            return stitches(a, b, length: length, offset: Double(index % 4) / 4)
        }
        guard !looped else { return turning }   // a ring has no parts beyond its lines
        return try beyond(ordered[0], others: Array(ordered.dropFirst()), towards: true) + turning
            + beyond(ordered[ordered.count - 1], others: Array(ordered.dropLast()), towards: false)
    }
    /// The direction of a line, in degrees.
    static func direction(_ chord: (a: Point, b: Point)) -> Double { atan2(chord.b.y - chord.a.y, chord.b.x - chord.a.x) * 180 / .pi }

    /// Stitches from `a` to `b` at most `length` long, the needle points shifted along by `offset` of a stitch so
    /// rows next to each other don't line their holes up. No end stitch is shorter than 0.3 mm.
    static func stitches(_ a: Point, _ b: Point, length: Double, offset: Double) -> [Point] {
        let total = a.distance(to: b)
        var marks = [0.0], s = offset * length
        if s < 0.3 { s += length }
        while s < total - 0.3 { marks.append(s); s += length }
        marks.append(total)
        return marks.map { a + (b - a) * ($0 / total) }
    }
    static func mid(_ chord: (a: Point, b: Point)) -> Point { (chord.a + chord.b) * 0.5 }
    /// How far `p` is from a segment.
    static func gap(_ p: Point, _ segment: (Point, Point)) -> Double { p.distance(to: AreaGeometry.projection(p, segment.0, segment.1)) }
}
