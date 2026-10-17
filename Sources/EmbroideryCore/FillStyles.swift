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
        // Every ring at every depth: each depth's inset can have several rings (lobes, and the edges of holes). The
        // first depth is half a row spacing in from the edge, and each one after is a row spacing further in.
        var loops: [[Point]] = [], round: [Bool] = [], counterclockwise: [Bool] = [], outermost = 0, total = 0, steps = [region]
        for level in 0... {
            try Task.checkCancellation()
            let inset = try shrunk(&steps, by: spacing / 2 + Double(level) * spacing)
            if inset.isEmpty { break }
            for ring in inset {
                let loop = resampled(ring, length: length)
                if loop.count >= 3 { loops.append(loop); round.append(isRound(ring)); counterclockwise.append(AreaGeometry.area(ring) > 0); total += loop.count }
            }
            if level == 0 { outermost = loops.count }   // loops before this index are the first depth's
            guard level < 5000, total <= 1_000_000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
        }
        guard !loops.isEmpty else { return [] }

        // First the order: each ring, starting at the point nearest where the last one ended, and whether the needle
        // can step straight onto it from there (false starts a new section).
        var order: [(loop: [Point], round: Bool, counterclockwise: Bool, joined: Bool)] = []
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
            order.append((loop, round[best.ring], counterclockwise[best.ring], !order.isEmpty && best.distance <= shortStep && AreaGeometry.segmentInside(needle, loop[0], rings: region)))
            needle = loop.last!; remaining.remove(best.ring)
        }
        // Then the stitches. Stepping straight across after every ring lines the steps up into a visible seam from the
        // edge to the middle, so between two round rings the needle spirals instead: over the lap, it drifts from this
        // ring to the next (by the share of the lap sewn so far), ending where the next ring begins. A run of spiral
        // laps starts and ends with a plain ring, so the edges stay covered. Rings with sharp corners keep the step:
        // matching points between them bends the laps across each other near the corners. So do rings running opposite
        // ways round (an outline's rings and a hole's): drifting from one to the other would swing the stitches across the hole.
        func spirals(_ k: Int) -> Bool {
            k >= 0 && k + 1 < order.count && order[k + 1].joined && order[k].round && order[k + 1].round && order[k].counterclockwise == order[k + 1].counterclockwise
        }
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

    /// The region `steps[0]` shrunk by `depth` mm: the rings of one contour depth. Returns no rings once nothing is left.
    ///
    /// Each depth is shrunk from the whole region, not from the depth before it. Both give the same shape (to within
    /// a few hundredths of a millimeter), but every shrink rounds the corners with extra points, and the next shrink
    /// keeps those and adds more. Shrinking a shrunk ring over and over piled them up: a big fill's rings reached
    /// many thousands of points, took seconds to work out, and could pass the geometry library's limit of 20,000
    /// points per ring, which failed the fill.
    /// The library shrinks at most 10 mm at a time, so deeper rings start from the region already shrunk by whole
    /// 10 mm steps. `steps` keeps those (the region itself, then shrunk by 10, 20 … mm) and grows as depths need them.
    static func shrunk(_ steps: inout [[[Point]]], by depth: Double) throws -> [[Point]] {
        // Whole 10 mm steps first, then the rest: more than 0 and at most 10 mm.
        let whole = max(0, Int(ceil(depth / 10)) - 1)
        while steps.count <= whole, let last = steps.last, !last.isEmpty { steps.append(try AreaGeometry.offset(last, by: -10)) }
        guard whole < steps.count, !steps[whole].isEmpty else { return [] }
        return try AreaGeometry.offset(steps[whole], by: -(depth - Double(whole) * 10))
    }

    /// Stipple fill: one wandering line per separate part of `region` that loops through it and never crosses itself,
    /// about `spacing` apart from its own neighbouring passes, in stitches of about `length` (2 mm at most). Sewing begins on the
    /// loop nearest `start`, at its point nearest it.
    ///
    /// How: the shape is covered with square cells twice `spacing` across, and a random maze (a tree of corridors) is
    /// dug through the cells that fit inside it. Walking round the walls of a maze, always keeping them on one side,
    /// visits every cell and comes back to the start without crossing its own path, so that walk is the line. Its
    /// corners are wobbled a little and rounded off, so it meanders instead of looking like a maze. The randomness is
    /// seeded from the shape itself, so the same shape always sews the same way.
    static func stipple(in region: [[Point]], spacing: Double, length: Double, start: Point?) throws -> [[Point]] {
        let cell = spacing * 2, all = region.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let columns = Int(ceil((maxX - minX) / cell)), rows = Int(ceil((maxY - minY) / cell))
        guard columns * rows <= 250_000 else { throw DesignError.invalid("This stipple fill is too big for its spacing. Increase the stipple spacing.") }
        // The cells the line can use: the square the line wanders in (half a cell across, round the cell's middle)
        // lies inside the shape.
        func middle(_ i: Int, _ j: Int) -> Point { Point(minX + (Double(i) + 0.5) * cell, minY + (Double(j) + 0.5) * cell) }
        var usable = [Bool](repeating: false, count: columns * rows)
        for i in 0..<columns { for j in 0..<rows {
            let m = middle(i, j), h = spacing / 2
            usable[i * rows + j] = [m, m + Point(-h, -h), m + Point(h, -h), m + Point(h, h), m + Point(-h, h)].allSatisfy { AreaGeometry.contains($0, rings: region) }
        } }
        var random = Seeded(region)
        // The maze: from each part's first cell, dig to a random unvisited neighbour, backing up when there's none.
        // It prefers to turn rather than go straight on, so the corridors twist and the line wiggles everywhere
        // instead of running straight. open[cell][direction] says whether a corridor leads that way (0 right, 1 up,
        // 2 left, 3 down).
        let steps = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        var open = [[Bool]](repeating: [false, false, false, false], count: columns * rows), visited = usable.map { !$0 }
        var parts: [Int] = []   // each part's first cell
        var arrivedBy = [Int](repeating: -1, count: columns * rows)   // the direction each cell was dug into from
        for first in usable.indices where !visited[first] {
            parts.append(first); visited[first] = true
            var stack = [first]
            while let here = stack.last {
                let i = here / rows, j = here % rows
                let ways = (0..<4).filter { d in
                    let (a, b) = (i + steps[d].0, j + steps[d].1)
                    return a >= 0 && a < columns && b >= 0 && b < rows && !visited[a * rows + b]
                }
                guard !ways.isEmpty else { stack.removeLast(); continue }
                // Straight on only one time in five when there's a turn to take instead.
                let turns = ways.filter { $0 != arrivedBy[here] }
                let choices = !turns.isEmpty && turns.count < ways.count && random.below(5) > 0 ? turns : ways
                let d = choices[random.below(choices.count)], next = (i + steps[d].0) * rows + j + steps[d].1
                open[here][d] = true; open[next][(d + 2) % 4] = true; visited[next] = true; arrivedBy[next] = d; stack.append(next)
            }
        }
        // The walk round the walls, on a grid twice as fine: each cell has four corner points, joined across the
        // cell where a wall closes that side and through to the next cell where a corridor opens it. Every point
        // then has exactly two neighbours, so following them goes once round each part's maze.
        let fine = rows * 2
        func id(_ x: Int, _ y: Int) -> Int { x * fine + y }
        var links: [Int: [Int]] = [:]
        func link(_ a: Int, _ b: Int) { links[a, default: []].append(b); links[b, default: []].append(a) }
        for here in usable.indices where usable[here] {
            let x = here / rows * 2, y = here % rows * 2
            if open[here][0] { link(id(x + 1, y), id(x + 2, y)); link(id(x + 1, y + 1), id(x + 2, y + 1)) } else { link(id(x + 1, y), id(x + 1, y + 1)) }
            if open[here][1] { link(id(x, y + 1), id(x, y + 2)); link(id(x + 1, y + 1), id(x + 1, y + 2)) } else { link(id(x, y + 1), id(x + 1, y + 1)) }
            if !open[here][2] { link(id(x, y), id(x, y + 1)) }
            if !open[here][3] { link(id(x, y), id(x + 1, y)) }
        }
        // Each corner point's place, wobbled by up to 0.15 × spacing so the line meanders (neighbouring passes stay at
        // least 0.7 × spacing apart, so it still can't cross).
        // A point the wobble would push out of the shape (where the line runs along its edge) stays put.
        func place(_ point: Int) -> Point {
            var wobble = Seeded(seed: UInt64(point) &* 0x9E3779B97F4A7C15 &+ random.seed)
            let x = Double(point / fine), y = Double(point % fine)
            let exact = Point(minX + (x + 0.5) * spacing, minY + (y + 0.5) * spacing)
            let moved = exact + Point((wobble.unit() - 0.5) * 0.3 * spacing, (wobble.unit() - 0.5) * 0.3 * spacing)
            return AreaGeometry.contains(moved, rings: region) ? moved : exact
        }
        var loops: [[Point]] = []
        for first in parts {
            let begin = id(first / rows * 2, first % rows * 2)
            var loop = [begin], previous = -1, here = begin
            while let next = links[here]?.first(where: { $0 != previous }) ?? links[here]?.first, next != begin {
                loop.append(next); previous = here; here = next
                guard loop.count <= 4 * columns * rows + 4 else { break }
            }
            // Rounded off: each corner is cut twice (Chaikin), which keeps the line inside the corridors.
            var points = loop.map(place)
            for _ in 0..<3 { points = points.indices.flatMap { k -> [Point] in let a = points[k], b = points[(k + 1) % points.count]; return [a * 0.75 + b * 0.25, a * 0.25 + b * 0.75] } }
            // A gentle wave along the line (0.2 × spacing to either side, a crest every 1.6 × spacing) breaks up straight
            // stretches so it meanders everywhere. With the wobble above, neighbouring passes still keep at least
            // 0.3 × spacing apart.
            let even = resampled(points, length: spacing / 8)
            var walked = 0.0, waved: [Point] = []
            for k in even.indices {
                let a = even[(k + even.count - 1) % even.count], b = even[(k + 1) % even.count], d = b - a, size = max(1e-9, hypot(d.x, d.y))
                if k > 0 { walked += even[k].distance(to: even[k - 1]) }
                let moved = even[k] + Point(-d.y / size, d.x / size) * (0.2 * spacing * sin(2 * .pi * walked / (1.6 * spacing)))
                waved.append(AreaGeometry.contains(moved, rings: region) ? moved : even[k])   // never out past the edge
            }
            // Stitches no longer than 2 mm, so the rounded turns stay round rather than becoming a stitch or two.
            loops.append(resampled(waved, length: min(length, 2)))
        }
        // Each loop begins at its point nearest the needle (the start point, then where the last loop ended) and goes
        // all the way round; the nearest loop goes first.
        var needle = start ?? loops.first?.first ?? Point(minX, minY), remaining = loops.filter { $0.count >= 3 }, sections: [[Point]] = []
        while !remaining.isEmpty {
            let nearest = remaining.indices.min { remaining[$0].map { $0.distance(to: needle) }.min()! < remaining[$1].map { $0.distance(to: needle) }.min()! }!
            let loop = remaining.remove(at: nearest), k = loop.indices.min { loop[$0].distance(to: needle) < loop[$1].distance(to: needle) }!
            let section = Array(loop[k...] + loop[..<k]) + [loop[k]]
            sections.append(section); needle = section.last!
        }
        return sections
    }

    /// Random numbers that come out the same every time for the same seed (SplitMix64), so a stipple fill doesn't
    /// change from one launch to the next.
    struct Seeded {
        private(set) var seed: UInt64
        private var state: UInt64
        init(seed: UInt64) { self.seed = seed; state = seed }
        /// Seeded from a shape's points (to a thousandth of a millimeter), so each shape gets its own pattern.
        init(_ region: [[Point]]) {
            var h: UInt64 = 0xcbf29ce484222325
            for p in region.flatMap({ $0 }) {
                for v in [p.x, p.y] { h = (h ^ UInt64(bitPattern: Int64((v * 1000).rounded()))) &* 0x100000001b3 }
            }
            self.init(seed: h)
        }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        /// A whole number from 0 up to (not including) `n`.
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        /// A number from 0 up to 1.
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
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
