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
        let reach = Self.reach(across: region)
        var chords = Self.chords(in: region, angleLines: angleLines)
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
        /// The part of the shape beyond `chord` (away from the other lines), filled with ordinary rows along it, as
        /// streams in sewing order: towards the line when `towards`, away from it otherwise. The shape is cut along the
        /// line, and the pieces that hold none of the other lines are beyond it.
        func beyond(_ chord: (a: Point, b: Point), others: [(a: Point, b: Point)], towards: Bool) throws -> [[[Point]]] {
            let u = (chord.b - chord.a) * (0.05 / max(chord.a.distance(to: chord.b), 1e-9))   // a little past each end, to cut right through
            let pieces = try AreaGeometry.subtracting(Design.knifeBand([chord.a - u, chord.b + u]), from: region)
            let far = pieces.filter { piece in !others.contains { AreaGeometry.contains(mid($0), rings: piece) } }
            var rows = try far.flatMap { try AreaEngine.rows(in: $0, angle: direction(chord), spacing: spacing, length: length) }
            func distance(_ row: [Point]) -> Double { gap((row.first! + row.last!) * 0.5, (chord.a, chord.b)) }
            rows.sort { towards ? distance($0) > distance($1) : distance($0) < distance($1) }
            // Rows the same distance from the line are one scan line, split where the shape is; each part is
            // finished before the next.
            var groups: [[[Point]]] = []
            for row in rows {
                if let last = groups.last?.last, abs(distance(last) - distance(row)) < spacing * 0.5 { groups[groups.count - 1].append(row) }
                else { groups.append([row]) }
            }
            return streams(groups, near: spacing * 3)
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
        // The rows, one group per in-between line (a line crossing a notch or gap in the shape has a row on each
        // side), leaving out every part that would land on thread already laid: the inside of a bend, where rows
        // crowd together (like short stitches on a satin), and any part of the shape earlier rows already filled,
        // such as the far side of a notch, which the in-between lines can sweep across twice. Every row laid so far
        // is kept as points in a grid of squares half a row spacing wide, so a point is checked only against the
        // points in the squares around it.
        let near = spacing * 0.5
        var groups: [[[Point]]] = [], grid: [SIMD2<Int>: [Point]] = [:]
        func square(_ p: Point) -> SIMD2<Int> { SIMD2(Int((p.x / near).rounded(.down)), Int((p.y / near).rounded(.down))) }
        func covered(_ p: Point) -> Bool {
            let s = square(p)
            for dx in -1...1 { for dy in -1...1 where grid[s &+ SIMD2(dx, dy)]?.contains(where: { $0.distance(to: p) < near }) == true { return true } }
            return false
        }
        for guide in guides {
            try Task.checkCancellation()
            var group: [[Point]] = [], laid: [Point] = []
            for piece in clipped(guide) {
                // Covered ends are left off. In between, a short covered stretch (where rows pinch together for a
                // moment) is sewn through rather than cut, which would mean an extra trip; a long one (an area that's
                // already filled) splits the row. Each remaining stretch at least 1 mm long is a row.
                let points = AreaGeometry.sampled([piece.0, piece.1], length: 0.25)
                var keep = points.map { !covered($0) }
                var k = 0
                while k < points.count {
                    guard !keep[k] else { k += 1; continue }
                    var end = k
                    while end + 1 < points.count, !keep[end + 1] { end += 1 }
                    let inside = k > 0 && end < points.count - 1
                    if inside, points[k].distance(to: points[end]) < 3 { for m in k...end { keep[m] = true } }
                    k = end + 1
                }
                var start: Int?
                for m in points.indices + [points.count] {
                    if m < points.count, keep[m] { if start == nil { start = m }; continue }
                    if let first = start, points[first].distance(to: points[m - 1]) >= 1 {
                        group.append([points[first], points[m - 1]]); laid += AreaGeometry.sampled([points[first], points[m - 1]], length: max(0.2, spacing * 0.25))
                    }
                    start = nil
                }
            }
            for p in laid { grid[square(p), default: []].append(p) }   // after the whole line, so its own pieces don't cut each other
            if !group.isEmpty { groups.append(group) }
        }
        // The streams: the rows beyond the first line, the turning rows, then those beyond the last line (a ring has
        // no parts beyond its lines), each stream sewn back and forth in one go. The turning rows (only their ends
        // so far) are split into stitches staggered by quarters of a stitch length from row to row; the rows beyond
        // the lines already are. Each stream comes back as one line of stitches, so the fill's travel planner can put
        // the streams in the order that needs least travel.
        let before = looped ? [] : try beyond(ordered[0], others: Array(ordered.dropFirst()), towards: true)
        let after = looped ? [] : try beyond(ordered[ordered.count - 1], others: Array(ordered.dropLast()), towards: false)
        let turning = streams(groups, near: spacing * 3)
        var index = 0
        return backAndForth(before + turning + after).enumerated().map { number, stream in
            let isTurning = number >= before.count && number < before.count + turning.count
            return stream.flatMap { row -> [Point] in
                defer { index += 1 }
                return isTurning ? stitches(row[0], row[1], length: length, offset: Double(index % 4) / 4) : row
            }
        }
    }
    /// Rows sorted into streams, each an area the rows sweep across without a break. `groups` are the rows in order,
    /// a group for each line across the shape (more than one row where the line crosses a notch or gap). Each row
    /// joins the stream whose last row lies right beside it (within `near`), one row per stream from each group, the
    /// closest pairs first, or starts a new stream. Sewn one stream after another, the needle finishes one side of a
    /// notch before moving to the other, instead of crossing back and forth after every row.
    static func streams(_ groups: [[[Point]]], near: Double) -> [[[Point]]] {
        /// How far apart two rows are: the closest any end of one comes to the other.
        func apart(_ row: [Point], _ other: [Point]) -> Double {
            let (a, b, c, d) = (row.first!, row.last!, other.first!, other.last!)
            return min(gap(a, (c, d)), gap(b, (c, d)), gap(c, (a, b)), gap(d, (a, b)))
        }
        var streams: [[[Point]]] = []
        for group in groups {
            let pairs = group.indices.flatMap { r in streams.indices.map { (row: r, stream: $0, gap: apart(group[r], streams[$0].last!)) } }
                .filter { $0.gap <= near }.sorted { $0.gap < $1.gap }
            var placed = [Int?](repeating: nil, count: group.count), taken = Set<Int>()
            for pair in pairs where placed[pair.row] == nil && !taken.contains(pair.stream) { placed[pair.row] = pair.stream; taken.insert(pair.stream) }
            for (r, row) in group.enumerated() {
                if let s = placed[r] { streams[s].append(row) } else { streams.append([row]) }
            }
        }
        return streams
    }

    /// Each stream's rows back and forth; each stream starts from the end of its first row nearer where the needle
    /// finished the one before.
    static func backAndForth(_ streams: [[[Point]]]) -> [[[Point]]] {
        var result: [[[Point]]] = []
        for stream in streams {
            let end = result.last?.last?.last
            var forward = end.map { $0.distance(to: stream[0].first!) <= $0.distance(to: stream[0].last!) } ?? true
            result.append(stream.map { row in defer { forward.toggle() }; return forward ? row : row.reversed() })
        }
        return result
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

    /// A length longer than any line across `region` (its bounding box's diagonal plus 1 mm), or 1 for an empty one.
    static func reach(across region: [[Point]]) -> Double {
        let points = region.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return 1 }
        return hypot(maxX - minX, maxY - minY) + 1
    }

    /// Each angle line stretched across the shape: the piece of its line, through its middle, that lies inside
    /// `region` (the nearest piece, where the line crosses the shape more than once). Lines that miss the shape
    /// entirely, or are too short to have a direction, are left out, so an empty result means the fill can't use them.
    static func chords(in region: [[Point]], angleLines: [[Point]]) -> [(a: Point, b: Point)] {
        let reach = reach(across: region)
        return angleLines.compactMap { line in
            guard line.count >= 2, line[0].distance(to: line[1]) > 0.01 else { return nil }
            let middle = (line[0] + line[1]) * 0.5, u = (line[1] - line[0]) * (1 / line[0].distance(to: line[1]))
            let pieces = AreaGeometry.clippedSegment(middle - u * reach, middle + u * reach, rings: region)
            return pieces.min { gap(middle, $0) < gap(middle, $1) }.map { (a: $0.0, b: $0.1) }
        }
    }
}
