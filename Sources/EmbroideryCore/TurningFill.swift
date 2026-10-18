// Turning fill, made with stitch angles: lines drawn across a
// fill set which way its stitches run there, and between two lines the stitches turn gradually from one direction
// to the other, so a fill can follow a curved shape the way a satin column does.
import Foundation

enum TurningFill {
    /// The fill's rows as stitches, in sections sewn one after another. Each angle line is first stretched to the
    /// shape's edge on both sides. The stitch direction is then worked out everywhere in the shape (`DirectionField`):
    /// along each line it's that line's direction, and in between it turns as evenly as it can from one line to the
    /// next; before the first line and after the last it stays parallel to it (on a ring, where every line runs from
    /// the outside edge to the hole, it turns from the last line back round to the first instead). Rows follow that
    /// direction, so they bend gently, evenly spaced; where they crowd together (the inside of a bend) rows stop
    /// short, like short stitches on a satin, and where they spread apart another row starts between them.
    /// `start` picks which angle line the rows begin from (the nearest one).
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
        var around: Point?
        if looped {
            // Round the outside edge from the line nearest the start, and round the hole in the same direction (a
            // ring's points can run either way round, which the sign of its area tells).
            let hole = ends[0].hole, first = ends[0].sa
            let round = ends.sorted { wrap($0.sa - first, 0) < wrap($1.sa - first, 0) }
            let sameWay = (AreaGeometry.area(region[0]) > 0) == (AreaGeometry.area(region[hole]) > 0)
            around = pointAt(0, first + min(1, wrap(round[1].sa - first, 0) / 2))   // just past the first line, the way round they go
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
        // How far the stitches turn from each line to the next, in degrees (+ is anticlockwise). Lines' directions
        // alone can't tell a turn one way from the other way round (a U turns 180° either way), so in-between lines
        // are laid by sliding each end along the edge from one line's end to the other's, and their small changes
        // of direction are added up.
        func turn(_ span: (p: (a: Point, b: Point), c: (a: Point, b: Point), edgeA: Edge?, edgeB: Edge?)) -> Double {
            let (p, c) = (span.p, span.c)
            let count = max(1, Int(ceil(max(edgeLength(span.edgeA, p.a, c.a), edgeLength(span.edgeB, p.b, c.b)) / spacing)))
            func slide(_ e: Edge?, _ x: Point, _ y: Point, _ t: Double) -> Point { e.map { pointAt($0.ring, $0.s + $0.delta * t) } ?? x + (y - x) * t }
            var total = 0.0, last = direction(p)
            for j in 1...count {
                let t = Double(j) / Double(count)
                let line = j == count ? c : (a: slide(span.edgeA, p.a, c.a, t), b: slide(span.edgeB, p.b, c.b, t))
                guard line.a.distance(to: line.b) > 0.01 else { continue }
                let d = direction(line)
                total += remainder(d - last, 360); last = d
            }
            return total
        }
        let lines = looped ? spans.map(\.p) : ordered
        let turns = spans.map(turn)
        var angles = [direction(lines[0])]
        for k in 0..<(lines.count - 1) { angles.append(angles[k] + turns[k]) }
        // Round a ring the stitches come back to the first line having turned all the way round (360°), so just
        // past the first line, on the side the last line comes from, its angle counts as that much more.
        let loopTurn = looped ? turns.reduce(0, +) : 0
        let field = try DirectionField(region: region, lines: lines, angles: angles, loopTurn: loopTurn, around: around)
        return try Self.rows(field: field, region: region, lines: lines, looped: looped, spacing: spacing, length: length, reach: reach)
    }

    /// The rows, traced along `field`'s directions and evenly spaced: each new row starts one spacing beside one
    /// already laid, where there's room, and runs both ways until it reaches the shape's edge or comes closer than
    /// 0.6 of a spacing to another row (where rows crowd together on the inside of a bend, like short stitches on a
    /// satin). Where rows spread apart (the outside of a bend), another row starts half way between them once the
    /// gap passes 1.5 spacings (well clear of the 1.2 where rows stop, so rows don't stop and start again). The first
    /// row runs through the middle of the first line. Returns the rows as sections of stitches in sewing order,
    /// across the shape from the far edge beyond the first line, across it, towards the others.
    static func rows(field: DirectionField, region: [[Point]], lines: [(a: Point, b: Point)], looped: Bool, spacing: Double, length: Double, reach: Double) throws -> [[Point]] {
        let step = min(0.1, spacing / 4)
        // Every row laid so far is kept as points in a grid of squares half a spacing wide, so a point is checked
        // only against the points in the squares around it.
        let size = spacing * 0.5
        var grid: [SIMD2<Int>: [(point: Point, row: Int)]] = [:]
        func square(_ p: Point) -> SIMD2<Int> { SIMD2(Int((p.x / size).rounded(.down)), Int((p.y / size).rounded(.down))) }
        /// A row that comes within `limit` of `p`, if any.
        func rowNear(_ p: Point, within limit: Double) -> Int? {
            let s = square(p), r = Int(ceil(limit / size))
            for dx in -r...r { for dy in -r...r { if let hit = grid[s &+ SIMD2(dx, dy)]?.first(where: { $0.point.distance(to: p) < limit }) { return hit.row } } }
            return nil
        }
        func crowded(_ p: Point, within limit: Double) -> Bool { rowNear(p, within: limit) != nil }
        func dot(_ u: Point, _ v: Point) -> Double { u.x * v.x + u.y * v.y }
        /// A row through `seed`, its points running the way of `heading`: traced a small step at a time (each step's
        /// direction taken half way along it, which keeps the row true round bends), first one way and then the other.
        func trace(_ seed: Point, heading start: Point) -> [Point] {
            var halves: [[Point]] = []
            for sign in [1.0, -1.0] {
                var points: [Point] = [], p = seed, heading = start * sign
                for _ in 0..<Int(2 * reach / step) {
                    // A direction has two ways along it; keep going the way the row is already heading.
                    guard var v = field.direction(at: p) else { break }
                    if dot(v, heading) < 0 { v = v * -1 }
                    guard var u = field.direction(at: p + v * (step / 2)) else { break }
                    if dot(u, v) < 0 { u = u * -1 }
                    var q = p + u * step, leaving = false
                    // Near the edge, a step that leaves the shape ends the row exactly on the edge.
                    if !field.deep(q) {
                        guard let piece = AreaGeometry.clippedSegment(p, q, rings: region).first, piece.0.distance(to: p) < 1e-6 else { break }
                        if piece.1.distance(to: q) > 1e-6 { q = piece.1; leaving = true }
                    }
                    if crowded(q, within: spacing * 0.6) { break }
                    if q.distance(to: p) > 0.01 { points.append(q) }
                    if leaving { break }
                    heading = u; p = q
                }
                halves.append(points)
            }
            return halves[1].reversed() + [seed] + halves[0]
        }
        // Each row's points run the same way as its neighbour's, so "left" means the same side for all of them. Each
        // row knows the rows just left of it (`left`), and has a rough place across the shape: how many spacings
        // left of the first row it is (negative: right), which only breaks ties.
        var rows: [[Point]] = [], places: [Double] = [], left: [[Int]] = []
        func lay(_ row: [Point], at place: Double) {
            rows.append(row); places.append(place); left.append([])
            for p in AreaGeometry.sampled(row, length: max(0.05, spacing * 0.25)) { grid[square(p), default: []].append((p, rows.count - 1)) }
        }
        /// Where a new row can start beside row `r`'s point `k`, on its `side` (+1 left, -1 right), and how far out:
        /// one spacing, where nothing is in the way for two; half way across a gap of 1.5 to 2 spacings to the next
        /// row (also given, as `beyond`); nowhere if the gap is narrower or the shape's edge is less than a spacing away.
        func seed(beside r: Int, at k: Int, side: Double) -> (point: Point, offset: Double, beyond: Int?)? {
            let row = rows[r], a = row[max(k - 1, 0)], b = row[min(k + 1, row.count - 1)]
            let length = a.distance(to: b)
            guard length > 1e-9 else { return nil }
            let normal = Point(-(b.y - a.y), b.x - a.x) * (side / length)
            // Usually there's a row one spacing out already.
            if crowded(row[k] + normal * spacing, within: spacing * 0.35) { return nil }
            // Out along the normal a little at a time to the next row (where a point comes within 0.3 spacings of it).
            for out in stride(from: spacing * 0.4, through: spacing * 2, by: spacing * 0.05) {
                let p = row[k] + normal * out
                if !AreaGeometry.contains(p, rings: region) { return out > spacing ? (row[k] + normal * spacing, spacing, nil) : nil }
                if let beyond = rowNear(p, within: spacing * 0.3) {
                    let gap = out + spacing * 0.3
                    return gap >= spacing * 1.5 ? (row[k] + normal * (gap / 2), gap / 2, beyond) : nil
                }
            }
            return (row[k] + normal * spacing, spacing, nil)
        }
        // The first row through the middle of the first line, then rows out from each row in turn, trying both
        // sides every half spacing along it (round a ring, the first row only its left).
        let first = lines[0]
        guard let heading = field.direction(at: mid(first)) else { return [] }
        lay(trace(mid(first), heading: heading), at: 0)
        let every = max(1, Int((spacing * 0.5 / step).rounded()))
        var next = 0
        while next < rows.count {
            try Task.checkCancellation()
            for k in stride(from: 0, to: rows[next].count, by: every) {
                // Round a ring, rows spread from the first one to its left only, all the way round back to it.
                for side in looped && next == 0 ? [1.0] : [1.0, -1.0] {
                    guard let (p, offset, beyond) = seed(beside: next, at: k, side: side) else { continue }
                    let row = rows[next], along = row[min(k + 1, row.count - 1)] - row[max(k - 1, 0)]
                    lay(trace(p, heading: along * (1 / max(along.distance(to: Point(0, 0)), 1e-9))), at: places[next] + side * offset / spacing)
                    // The new row lies between this one and the row beyond it.
                    let new = rows.count - 1
                    if side > 0 { left[next].append(new); if let beyond { left[new].append(beyond) } }
                    else { left[new].append(next); if let beyond { left[beyond].append(new) } }
                    guard rows.count <= 20000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
                }
            }
            next += 1
        }
        // In order across the shape, starting on the first row's side away from the other lines. Rows at the same
        // place in different parts of the shape (either side of a notch) are sorted into separate streams. Rows under
        // 1 mm are left out: they're specks where rows pinch together.
        let along = rows[0][rows[0].count - 1] - rows[0][0]
        let awayIsLeft = lines.count > 1 && AreaGeometry.cross(along, mid(lines[1]) - mid(first)) < 0
        // From right to left: a row comes after every row known to be right of it (the furthest right of those ready
        // first). Round a ring the rows on the far side close the circle; there the furthest right left goes next.
        var waiting = [Int](repeating: 0, count: rows.count)
        for r in rows.indices { for n in left[r] { waiting[n] += 1 } }
        var ready = rows.indices.filter { waiting[$0] == 0 }, order: [Int] = [], done = [Bool](repeating: false, count: rows.count)
        while order.count < rows.count {
            let pick = ready.min { places[$0] < places[$1] } ?? rows.indices.filter { !done[$0] }.min { places[$0] < places[$1] }!
            ready.removeAll { $0 == pick }; done[pick] = true; order.append(pick)
            for n in left[pick] where !done[n] { waiting[n] -= 1; if waiting[n] == 0 { ready.append(n) } }
        }
        if awayIsLeft { order.reverse() }
        let tree = streams(order.map { rows[$0] }.filter { AreaGeometry.pathLength($0) >= 1 }, beside: spacing * 1.5, region: region)
        // Each section comes back as one line of stitches, already in sewing order, each row split into stitches
        // staggered by quarters of a stitch length from row to row so neighbouring rows don't line their needle
        // holes up. The step from one row to the next is split into stitches too when it's long (into a row that
        // stops part way across, it runs in the gap between that row's neighbours); a step that would leave the
        // shape ends the section, and the fill's travel planner finds a way round.
        var index = 0, sections: [[Point]] = []
        for section in sewingOrder(tree, near: max(spacing * 3, length * 2)) {
            var stitched: [Point] = []
            for row in section {
                if let end = stitched.last {
                    if !AreaGeometry.segmentInside(end, row[0], rings: region) { sections.append(stitched); stitched = [] }
                    else if end.distance(to: row[0]) > length { stitched += AreaGeometry.sampled([end, row[0]], length: length).dropFirst().dropLast() }
                }
                stitched += GuidedFill.stitches(row, length: length, offset: Double(index % 4) / 4)
                index += 1
            }
            sections.append(stitched)
        }
        return sections.filter { !$0.isEmpty }
    }

    /// Which way the stitches run at each point of the shape, spread out from the angle lines. It's worked out on a
    /// grid of small squares: the squares an angle line passes through keep that line's angle, and every other
    /// square inside the shape takes the average of its neighbours', over and over until nothing changes. Like heat
    /// spreading from the lines, the angle changes as evenly as it can from one line to the next, and only through
    /// the shape (round a notch, not across it); beyond the last line it stays at that line's angle.
    struct DirectionField {
        let origin: Point, size: Double, width: Int
        /// Each square's direction as a unit arrow; nil outside the shape and not next to it.
        private var arrows: [Point?]
        /// Squares well inside the shape (no edge passes through them or their neighbours), so any point in one is inside.
        private var deepSquares: [Bool]

        /// `angles` are the lines' angles in degrees, each continuing on from the one before (so 350° then 370°, not
        /// 10°). Round a ring, `loopTurn` is how far the angle turns all the way round, and `around` a point just
        /// past the first line on the side the turning starts.
        init(region: [[Point]], lines: [(a: Point, b: Point)], angles: [Double], loopTurn: Double, around: Point?) throws {
            let points = region.flatMap { $0 }
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!, minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            // Squares half a millimetre wide, or bigger for a big shape, keeping the grid to about 60,000 squares.
            var size = 0.5
            while ((maxX - minX) / size + 3) * ((maxY - minY) / size + 3) > 60_000 { size *= 1.25 }
            let width = Int((maxX - minX) / size) + 3, height = Int((maxY - minY) / size) + 3, count = width * height
            let origin = Point(minX - size, minY - size)
            (self.origin, self.size, self.width) = (origin, size, width)
            func centre(_ i: Int) -> Point { Point(origin.x + (Double(i % width) + 0.5) * size, origin.y + (Double(i / width) + 0.5) * size) }
            // Which squares' middles are inside: along each row of squares, where the edges cross it, in and out in turn.
            var inside = [Bool](repeating: false, count: count)
            for j in 0..<height {
                let y = origin.y + (Double(j) + 0.5) * size
                var crossings: [Double] = []
                for ring in region { for k in ring.indices {
                    let a = ring[k], b = ring[(k + 1) % ring.count]
                    if (a.y > y) != (b.y > y) { crossings.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)) }
                } }
                crossings.sort()
                for pair in stride(from: 0, to: crossings.count - 1, by: 2) {
                    let from = max(0, Int(ceil((crossings[pair] - origin.x) / size - 0.5))), to = min(width - 1, Int(floor((crossings[pair + 1] - origin.x) / size - 0.5)))
                    if from <= to { for i in from...to { inside[j * width + i] = true } }
                }
            }
            // Squares an edge passes through, and their neighbours, aren't deep.
            var deep = inside
            for ring in region { for k in ring.indices {
                for p in AreaGeometry.sampled([ring[k], ring[(k + 1) % ring.count]], length: size / 2) {
                    let i = Int(((p.x - origin.x) / size).rounded(.down)), j = Int(((p.y - origin.y) / size).rounded(.down))
                    for dj in -1...1 { for di in -1...1 where (0..<width).contains(i + di) && (0..<height).contains(j + dj) { deep[(j + dj) * width + i + di] = false } }
                }
            } }
            // The squares each line passes through keep its angle.
            var angle = [Double](repeating: .nan, count: count), line = [Int](repeating: -1, count: count)
            for (k, chord) in lines.enumerated() {
                let low = Point(min(chord.a.x, chord.b.x) - size, min(chord.a.y, chord.b.y) - size), high = Point(max(chord.a.x, chord.b.x) + size, max(chord.a.y, chord.b.y) + size)
                for j in max(0, Int((low.y - origin.y) / size))...min(height - 1, Int((high.y - origin.y) / size)) {
                    for i in max(0, Int((low.x - origin.x) / size))...min(width - 1, Int((high.x - origin.x) / size)) where inside[j * width + i] {
                        // Within ¾ of a square of the line: enough that no two neighbouring squares are on opposite sides of it.
                        if TurningFill.gap(centre(j * width + i), chord) <= size * 0.75 { angle[j * width + i] = angles[k]; line[j * width + i] = k }
                    }
                }
            }
            // Round a ring, the first line is where the turning starts and ends: next to it on the far side, its
            // angle counts as having turned all the way round.
            let first = lines[0]
            func side(_ p: Point) -> Bool { AreaGeometry.cross(first.b - first.a, p - first.a) > 0 }
            let startSide = around.map(side)
            func reading(_ n: Int, from cell: Int) -> Double {
                if let startSide, line[n] == 0, side(centre(cell)) != startSide { return angle[n] + loopTurn }
                return angle[n]
            }
            func neighbours(_ cell: Int) -> [Int] {
                let i = cell % width
                return [i > 0 ? cell - 1 : -1, i < width - 1 ? cell + 1 : -1, cell - width, cell + width].filter { $0 >= 0 && $0 < count && inside[$0] }
            }
            // Starting values: spread out from the lines a square at a time.
            var queue = line.indices.filter { line[$0] >= 0 }, next = 0
            while next < queue.count {
                let cell = queue[next]; next += 1
                for n in neighbours(cell) where angle[n].isNaN { angle[n] = reading(cell, from: n); queue.append(n) }
            }
            // A piece of the shape no line reaches takes the first line's angle.
            for cell in angle.indices where inside[cell] && angle[cell].isNaN { angle[cell] = angles[0] }
            // Then each square becomes the average of its neighbours, again and again until no square moves more than
            // a hundredth of a degree. Each change is overdone a little (×1.9), which gets there many times faster.
            let free = angle.indices.filter { inside[$0] && line[$0] < 0 }.map { cell in (cell, neighbours(cell)) }.filter { !$0.1.isEmpty }
            for _ in 0..<4000 {
                try Task.checkCancellation()
                var largest = 0.0
                for (cell, around) in free {
                    var total = 0.0
                    for n in around { total += line[n] >= 0 ? reading(n, from: cell) : angle[n] }
                    let change = total / Double(around.count) - angle[cell]
                    angle[cell] += 1.9 * change
                    largest = max(largest, abs(change))
                }
                if largest < 0.01 { break }
            }
            var arrows: [Point?] = angle.map { $0.isNaN ? nil : Point(cos($0 * .pi / 180), sin($0 * .pi / 180)) }
            // Squares just outside get their inside neighbours' average, so a point right at the edge has a direction.
            for _ in 0..<2 {
                var grown = arrows
                for cell in arrows.indices where arrows[cell] == nil {
                    let i = cell % width
                    var sum = Point(0, 0)
                    for dj in [-width, 0, width] { for di in -1...1 where (0..<width).contains(i + di) {
                        let n = cell + dj + di
                        if n >= 0, n < count, let arrow = arrows[n] { sum = sum + arrow }
                    } }
                    let length = sum.distance(to: Point(0, 0))
                    if length > 1e-6 { grown[cell] = sum * (1 / length) }
                }
                arrows = grown
            }
            (self.arrows, self.deepSquares) = (arrows, deep)
        }

        /// The direction at `p` (a unit arrow, either way along it), blended from the four squares round it; nil off the grid.
        func direction(at p: Point) -> Point? {
            let fx = (p.x - origin.x) / size - 0.5, fy = (p.y - origin.y) / size - 0.5
            let i = Int(fx.rounded(.down)), j = Int(fy.rounded(.down)), tx = fx - Double(i), ty = fy - Double(j)
            var sum = Point(0, 0)
            for (di, dj, weight) in [(0, 0, (1 - tx) * (1 - ty)), (1, 0, tx * (1 - ty)), (0, 1, (1 - tx) * ty), (1, 1, tx * ty)] {
                let x = i + di, y = j + dj
                guard x >= 0, x < width, y >= 0, y * width + x < arrows.count, let arrow = arrows[y * width + x] else { continue }
                sum = sum + arrow * weight
            }
            let length = sum.distance(to: Point(0, 0))
            return length > 1e-6 ? sum * (1 / length) : nil
        }

        /// True when `p` is surely inside the shape (well away from its edge).
        func deep(_ p: Point) -> Bool {
            let i = Int(((p.x - origin.x) / size).rounded(.down)), j = Int(((p.y - origin.y) / size).rounded(.down))
            return i >= 0 && i < width && j >= 0 && j * width + i < deepSquares.count && deepSquares[j * width + i]
        }
    }

    /// Rows sorted into streams, each an area the rows sweep across without a break, sewn back and forth. `rows`
    /// come in order across the shape. Each row joins a stream whose last row it runs beside (most of the shorter
    /// of the two lies within `beside` of the other; rows either side of a notch only touch at its tip), or the row
    /// before that if the needle can step to it inside `region`: of those, the one whose needle finished nearest.
    /// It's sewn from its end nearer that needle. Otherwise it starts a new stream (where the shape divides, round a
    /// notch or into two arms): a branch off the stream that took the row before, after that stream's row `at`.
    static func streams(_ rows: [[Point]], beside: Double, region: [[Point]]) -> [(rows: [[Point]], parent: Int?, at: Int)] {
        /// How far `p` is from the line through `points`.
        func distance(_ p: Point, _ points: [Point]) -> Double { zip(points, points.dropFirst()).map { gap(p, ($0, $1)) }.min() ?? p.distance(to: points[0]) }
        /// True when most of the shorter row lies beside the longer one: of 9 points spread along it, 5 or more.
        func alongside(_ row: [Point], _ other: [Point]) -> Bool {
            let (short, long) = AreaGeometry.pathLength(row) <= AreaGeometry.pathLength(other) ? (row, other) : (other, row)
            let total = AreaGeometry.pathLength(short)
            return (1...9).filter { k in distance(point(along: short, at: total * Double(k) / 10), long) <= beside }.count >= 5
        }
        /// `row` running from its end nearer `needle`.
        func from(_ needle: Point?, _ row: [Point]) -> [Point] { needle.map { $0.distance(to: row[row.count - 1]) < $0.distance(to: row[0]) } == true ? row.reversed() : row }
        func reach(_ needle: Point, _ row: [Point]) -> Double { min(needle.distance(to: row[0]), needle.distance(to: row[row.count - 1])) }
        var streams: [(rows: [[Point]], parent: Int?, at: Int)] = [], latest: Int?
        for row in rows {
            // Streams whose last row this one runs beside (only those with a point of it in this row's box, widened).
            let low = Point(row.map(\.x).min()! - beside, row.map(\.y).min()! - beside), high = Point(row.map(\.x).max()! + beside, row.map(\.y).max()! + beside)
            let neighbours = streams.indices.filter { s in
                let last = streams[s].rows.last!, near = last.contains { $0.x >= low.x && $0.x <= high.x && $0.y >= low.y && $0.y <= high.y }
                if near && alongside(row, last) { return true }
                // Or beside the row before, where this one carries on from the last row's line (a stub filling the gap
                // past where that row stopped), when the needle can step to it inside the shape.
                guard streams[s].rows.count >= 2, alongside(row, streams[s].rows[streams[s].rows.count - 2]) else { return false }
                let needle = last.last!
                return AreaGeometry.segmentInside(needle, from(needle, row)[0], rings: region)
            }
            if let s = neighbours.min(by: { reach(streams[$0].rows.last!.last!, row) < reach(streams[$1].rows.last!.last!, row) }) {
                streams[s].rows.append(from(streams[s].rows.last!.last!, row))
                latest = s
                continue
            }
            // A new stream starts from the end nearer its parent's needle, so a branch sewn back to its start
            // finishes near where the parent carries on.
            let parent = latest
            streams.append(([from(parent.map { streams[$0].rows.last!.last! }, row)], parent, parent.map { streams[$0].rows.count - 1 } ?? 0))
            latest = streams.count - 1
        }
        return streams
    }

    /// The streams in sewing order, as sections (runs of rows sewn in one go). A stream is sewn from its start; where
    /// a branch leaves it part way, the needle first goes to the far end of the branch (travelling through the
    /// branch while it's still bare, so the branch's own rows cover the travel), sews the branch back to where it
    /// began, and then carries on. Where the stream ends (or a branch starts within `near` of its end), all but the
    /// biggest of the branches there are sewn the same way, there and back, and the biggest carries on from there.
    static func sewingOrder(_ streams: [(rows: [[Point]], parent: Int?, at: Int)], near: Double) -> [[[Point]]] {
        var sections: [[[Point]]] = []
        /// The branches off stream `s`: those leaving part way, by the row they leave after, and those at its end.
        func branches(of s: Int) -> (part: [Int: [Int]], end: [Int]) {
            let rows = streams[s].rows, finish = rows.last!.last!
            var part: [Int: [Int]] = [:], end: [Int] = []
            for b in streams.indices where streams[b].parent == s {
                if streams[b].at >= rows.count - 1 || streams[b].rows[0][0].distance(to: finish) <= near { end.append(b) }
                else { part[streams[b].at, default: []].append(b) }
            }
            return (part, end)
        }
        /// How many rows a stream and everything branching off it have.
        func size(_ s: Int) -> Int { streams[s].rows.count + streams.indices.filter { streams[$0].parent == s }.map(size).reduce(0, +) }
        func forwards(_ s: Int) {
            let (part, end) = branches(of: s)
            var run: [[Point]] = []
            for (i, row) in streams[s].rows.enumerated() {
                run.append(row)
                for b in part[i] ?? [] { sections.append(run); run = []; backwards(b) }
            }
            sections.append(run)
            let ordered = end.sorted { size($0) < size($1) }
            for b in ordered.dropLast() { backwards(b) }
            if let last = ordered.last { forwards(last) }
        }
        /// Stream `s` and its branches sewn from their far ends back to where `s` starts.
        func backwards(_ s: Int) {
            let (part, end) = branches(of: s)
            for b in end { backwards(b) }
            var run: [[Point]] = []
            for i in streams[s].rows.indices.reversed() {
                for b in part[i] ?? [] { if !run.isEmpty { sections.append(run); run = [] }; backwards(b) }
                run.append(streams[s].rows[i].reversed())
            }
            sections.append(run)
        }
        for s in streams.indices where streams[s].parent == nil { forwards(s) }
        return sections.filter { !$0.isEmpty }
    }

    /// The direction of a line, in degrees.
    static func direction(_ chord: (a: Point, b: Point)) -> Double { atan2(chord.b.y - chord.a.y, chord.b.x - chord.a.x) * 180 / .pi }

    static func mid(_ chord: (a: Point, b: Point)) -> Point { (chord.a + chord.b) * 0.5 }
    /// The point `distance` mm along `path` (its last point if the path is shorter).
    static func point(along path: [Point], at distance: Double) -> Point {
        var left = distance
        for (a, b) in zip(path, path.dropFirst()) {
            let d = a.distance(to: b)
            if d > 0, left <= d { return a + (b - a) * (left / d) }
            left -= d
        }
        return path[path.count - 1]
    }
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
