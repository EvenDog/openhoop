// Turning fill, made with stitch angles: lines drawn across a fill set which way its stitches run. As in other
// embroidery software, each line is extended right across the shape, like a cut, and lines may not cross inside it.
// In a piece beyond the end line, rows run straight at that line's angle; in a piece between two lines, rows are
// straight lines fanning out from the point where those two lines meet, so the direction turns evenly from one line
// to the other (straight, between parallel lines). The pieces are sewn one after another, each next to the last
// and carrying on from where the last finished, so each line shows as a seam.
import Foundation

enum TurningFill {
    /// Of the fan's rows, every other one stops short where the rows have converged to this share of the row spacing
    /// (every fourth where they've converged twice as far, and so on), so they never bunch up. Measured against the
    /// same shapes sewn by other software (2026-10-18), whose rows thin out between 0.57 and 0.75 of their spacing.
    static let thinning = 0.75

    /// The fill's rows as stitches, in sections sewn one after another across the shape. `start` picks which end of
    /// the shape the rows begin from (the one nearest it).
    static func rows(in region: [[Point]], angleLines: [[Point]], spacing: Double, length: Double, start: Point?) throws -> [[Point]] {
        var chords = Self.chords(in: region, angleLines: angleLines)
        guard !chords.isEmpty else { return [] }
        if let problem = crossingProblem(chords, in: region) { throw DesignError.invalid(problem) }
        // One line sets the direction for the whole fill: ordinary rows along it.
        if chords.count == 1 { return try AreaEngine.rows(in: region, angle: direction(chords[0]), spacing: spacing, length: length) }
        // Three or more lines that all meet at one point outside the fill (lines across a ring, all pointing at the
        // middle of its hole): between every two of them the rows point at that point, so all the way round they do.
        if chords.count >= 3, let centre = meeting(chords[0], chords[1]), !AreaGeometry.contains(centre, rings: region),
           chords.allSatisfy({ offLine(centre, $0) < 0.5 }) {
            return try fan(in: region, centre: centre, from: clearBearing(from: centre, of: region), turn: 2 * .pi, spacing: spacing, length: length)
        }
        // Cut the shape along each line, everywhere the line crosses it but no further, so however the shape bends
        // each piece is bordered by the lines next to it. `cuts`: those stretches, each with its line's number;
        // `sides[c]`: the pieces just beside cut c's middle, on its two sides; `borders[i]`: the cuts piece i touches.
        let cuts = stretches(in: region, angleLines: angleLines).enumerated().flatMap { k, line in line.map { (line: k, chord: $0) } }
        var pieces = [region]
        for cut in cuts { pieces = try pieces.flatMap { try AreaGeometry.subtracting([slit(cut.chord)], from: $0) } }
        guard !pieces.isEmpty else { return [] }
        let sides = cuts.map { cut -> [Int] in
            let n = Point(-unit(cut.chord).y, unit(cut.chord).x) * 0.02
            return [mid(cut.chord) + n, mid(cut.chord) - n].compactMap { p in pieces.firstIndex { AreaGeometry.contains(p, rings: $0) } }
        }
        let borders = pieces.indices.map { i in cuts.indices.filter { sides[$0].contains(i) } }
        /// The different lines piece `i` touches, in order.
        func lines(_ i: Int) -> [Int] { borders[i].map { cuts[$0].line }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
        /// How far `p` is from the nearest of the cuts numbered `which`.
        func gap(_ p: Point, _ which: [Int]) -> Double { which.map { Self.gap(p, (cuts[$0].chord.a, cuts[$0].chord.b)) }.min() ?? .infinity }

        // Sew piece by piece, each next to the last across a line: from the end piece nearest the start, on into
        // each neighbour in turn (a branch is sewn to its end before the next one), taking the neighbour across the
        // cut nearest the needle first. `pending`: pieces to sew, with the cut crossed into each (its entry); the
        // last is sewn next. A piece far smaller than a stitch (a corner a line just grazes) isn't worth a jump.
        let ends = pieces.indices.filter { lines($0).count == 1 }
        var first = ends.first ?? 0
        if let start { first = (ends.isEmpty ? Array(pieces.indices) : ends).min { gap(start, borders[$0]) < gap(start, borders[$1]) }! }
        var pending: [(piece: Int, entry: Int?)] = [(first, nil)], seen = Set<Int>()
        var sections: [[Point]] = []
        while seen.count < pieces.count {
            guard let (i, entry) = pending.popLast() else {
                pending.append((pieces.indices.first { !seen.contains($0) }!, nil))   // a piece no line borders (cut off by the fill's shape)
                continue
            }
            guard seen.insert(i).inserted else { continue }
            let rings = pieces[i], touching = lines(i)
            defer {
                let needle = sections.last?.last
                let next = borders[i].flatMap { c in sides[c].filter { $0 != i && !seen.contains($0) }.map { (piece: $0, entry: Optional(c)) } }
                pending += next.sorted { a, b in needle.map { gap($0, [a.entry!]) > gap($0, [b.entry!]) } ?? false }
            }
            if abs(AreaGeometry.area(rings[0])) - rings.dropFirst().map { abs(AreaGeometry.area($0)) }.reduce(0, +) < 0.1 { continue }
            var rows: [[Point]]
            /// `ways`: straight rows sewn each of the four ways (from either side, each row begun at either end);
            /// the one that starts on `line` (if any does) at the end nearest the needle, or finishing at `line` for
            /// the first piece, so the next piece carries on from there.
            func straight(_ ways: [[[Point]]], from line: (a: Point, b: Point)) -> [[Point]]? {
                guard !ways.isEmpty else { return nil }
                guard let needle = sections.last?.last else { return ways.min { offLine($0.last!.last!, line) < offLine($1.last!.last!, line) } }
                let atLine = ways.map { offLine($0[0][0], line) }.min()!
                return ways.filter { offLine($0[0][0], line) <= atLine + 0.5 }.min { needle.distance(to: $0[0][0]) < needle.distance(to: $1[0][0]) }
            }
            func ways(angle: Double) throws -> [[[Point]]] {
                try [false, true].flatMap { top in try [false, true].map { try AreaEngine.rows(in: rings, angle: angle, spacing: spacing, length: length, fromTop: top, startReversed: $0) } }.filter { !$0.isEmpty }
            }
            switch touching.count {
            case 2:
                // Between two lines: rows fan from the one it was entered by to the other, the first row starting
                // from whichever end of that line the needle is nearer. Between parallel lines, straight rows.
                let from = entry ?? borders[i][0], to = borders[i].first { cuts[$0].line != cuts[from].line }!
                guard let centre = meeting(cuts[from].chord, cuts[to].chord) else {
                    guard let picked = try straight(ways(angle: direction(cuts[from].chord)), from: cuts[from].chord) else { continue }
                    rows = picked; break
                }
                var outward = false
                if let needle = sections.last?.last {
                    let (a, b) = cuts[from].chord, near = a.distance(to: centre) < b.distance(to: centre) ? a : b, far = near == a ? b : a
                    outward = needle.distance(to: near) < needle.distance(to: far)
                }
                rows = try fan(in: rings, between: cuts[from].chord, and: cuts[to].chord, spacing: spacing, length: length, outwardFirst: outward)
            case 0, 1:
                // An end piece: straight rows at its line's angle, sewn so they finish at the line if it's sewn first,
                // otherwise begin there, at the end of the line nearest the needle. (A piece no line borders takes the
                // nearest line's angle.)
                let line = cuts[borders[i].first ?? cuts.indices.min { gap(rings[0][0], [$0]) < gap(rings[0][0], [$1]) }!].chord
                guard let picked = try straight(ways(angle: direction(line)), from: line) else { continue }
                rows = picked
            default:
                // Where three or more lines meet a piece (the middle of a Y): straight rows at their average angle,
                // averaged with doubled angles so a line and its reverse count the same, begun nearest the needle.
                let doubled = touching.map { 2 * direction(chords[$0]) * .pi / 180 }
                let mean = atan2(doubled.map(sin).reduce(0, +), doubled.map(cos).reduce(0, +)) / 2 * 180 / .pi
                let all = try ways(angle: mean), needle = sections.last?.last ?? start ?? Point(0, 0)
                guard let nearest = all.min(by: { needle.distance(to: $0[0][0]) < needle.distance(to: $1[0][0]) }) else { continue }
                rows = nearest
            }
            // A piece entered across a line already starts at that line, so it's sewn on from there, row after row
            // beside the last piece's. Any other piece starts at the end nearest where the last one finished.
            if entry == nil, let needle = sections.last?.last, let first = rows.first?.first, let last = rows.last?.last, needle.distance(to: last) < needle.distance(to: first) {
                rows = rows.reversed().map { $0.reversed() }
            }
            sections += rows
        }
        return sections
    }

    /// Why these lines can't be used together, or nil: two of them, extended right across the shape, meet inside it.
    static func crossingProblem(_ chords: [(a: Point, b: Point)], in region: [[Point]]) -> String? {
        for i in chords.indices { for j in chords.indices where j > i {
            if let meeting = meeting(chords[i], chords[j]), AreaGeometry.contains(meeting, rings: region) {
                return "Angle lines must not cross inside the fill area. Stretched right across the shape, two of them meet inside it: move or remove one."
            }
        }}
        return nil
    }
    /// The same check for a fill's own angle lines, as drawn (the fill's settings and shape, before compensation).
    static func crossingProblem(_ object: RunObject) -> String? {
        let region = ([object.nodes] + (object.holes ?? [])).map { AreaGeometry.ring($0) }
        return crossingProblem(chords(in: region, angleLines: object.settings.angleLines ?? []), in: region)
    }

    /// Rows between two lines, each pointing at the spot where the lines meet, so the direction turns evenly from one
    /// line's to the other's. They're `spacing` apart at the wide end and sewn back and forth from the first line to
    /// the second, a row in toward the narrow end and the next back out, as a pair. Where the rows converge, pairs stop
    /// short of the narrow edge, more of them the more crowded it gets (`thinning`), so the spacing stays even; both
    /// rows of a pair turn at the same place, so the needle only steps across to the next row. The places pairs turn
    /// keep the same distance from the narrow edge, so they line up along it.
    /// `outwardFirst`: the first row heads out from the narrow end instead of in toward it (pairs then start one row on).
    static func fan(in piece: [[Point]], between first: (a: Point, b: Point), and second: (a: Point, b: Point), spacing: Double, length: Double, outwardFirst: Bool = false) throws -> [[Point]] {
        guard let centre = meeting(first, second) else {
            return try AreaEngine.rows(in: piece, angle: direction(first), spacing: spacing, length: length)   // parallel lines
        }
        // The rows' directions, seen from the centre: from the first line's to the second's, the short way round.
        func bearing(_ p: Point) -> Double { atan2(p.y - centre.y, p.x - centre.x) }
        let from = bearing(mid(first))
        return try fan(in: piece, centre: centre, from: from, turn: remainder(bearing(mid(second)) - from, 2 * .pi), spacing: spacing, length: length, outwardFirst: outwardFirst)
    }
    /// Rows across `piece`, all pointing at `centre`, at directions (radians, seen from the centre) from `from` to
    /// `from + turn`; a whole turn (2π) goes all the way round.
    static func fan(in piece: [[Point]], centre: Point, from: Double, turn: Double, spacing: Double, length: Double, outwardFirst: Bool = false) throws -> [[Point]] {
        let full = abs(abs(turn) - 2 * .pi) < 1e-9
        // Rows are `spacing` apart across the wide end on average: measured at the far end of 65 trial rows.
        let trials = (0...64).compactMap { i -> Double? in
            let angle = from + turn * Double(i) / 64
            return crossings(piece, from: centre, along: Point(cos(angle), sin(angle))).last
        }
        let far = trials.isEmpty ? 0 : trials.reduce(0, +) / Double(trials.count)
        let count = max(1, Int((abs(turn) * far / spacing).rounded())), step = abs(turn) / Double(count)
        guard count <= 20000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
        // Each row's spans inside the piece (distances from the centre), and the narrowest end of any of them.
        var spans: [(k: Int, out: Point, near: Double, far: Double)] = []
        for k in 0...(full ? count - 1 : count) {   // all the way round, the last row would be the first again
            if k % 64 == 0 { try Task.checkCancellation() }
            // The rows on the two lines run a tenth of a row in from them, clear of the hair-thin cut along each
            // line, where a ray along it would find the piece's edge only here and there and give a broken row.
            let t = full ? Double(k) : k == 0 ? 0.1 : k == count ? Double(count) - 0.1 : Double(k)
            let angle = from + turn * t / Double(count), out = Point(cos(angle), sin(angle))
            let ts = crossings(piece, from: centre, along: out)
            for i in stride(from: 0, to: ts.count - 1, by: 2) where ts[i + 1] - ts[i] > StitchEngine.smallestStitch { spans.append((k, out, ts[i], ts[i + 1])) }
        }
        let narrowest = spans.map(\.near).min() ?? 0
        // Rows are counted from the first one there is (a row right along a line can fall on the piece's edge and
        // be left out), or from one before it, so the first row is a pair's out row, when it should head out.
        let shift = (outwardFirst ? 1 : 0) - (spans.map(\.k).min() ?? 0)
        let crowded = thinning * spacing / step   // nearer the centre than this, all the rows together are too close
        // Pairs stop short in a repeating pattern of 4 (pairs 1 and 3 of each 4, at two depths), or 8, 16… where
        // the rows converge so far that keeping half of them still crowds them. A few set depths, as other software
        // does, rather than every pair stopping somewhere different, which leaves thin gaps where single pairs are missing.
        let pattern = 1 << max(2, Int(ceil(log2(max(1, crowded / max(narrowest, 0.001))))) + 1)
        // Rows split by a notch go into separate runs, as tatami's do: a row's piece carries on the run of the piece
        // beside it on the row before when that's the only one it touches, and touches only it; elsewhere (where
        // the shape splits or joins) a new run starts. Each run is sewn back and forth on its own.
        let inside = (try? AreaGeometry.offset(piece, by: 0.05)) ?? piece
        var sections: [[Point]] = [], rowsIn: [Int] = []   // each run's needle points, and how many rows it has
        var previous: [(near: Double, far: Double, run: Int)] = []
        let byRow = Dictionary(grouping: spans, by: \.k)
        for k in byRow.keys.sorted() {
            let row = byRow[k]!
            func overlap(_ a: (near: Double, far: Double), _ b: (near: Double, far: Double)) -> Bool { min(a.far, b.far) - max(a.near, b.near) > 0 }
            var current: [(near: Double, far: Double, run: Int)] = []
            for span in row {
                let parents = previous.filter { overlap(($0.near, $0.far), (span.near, span.far)) }
                var run: Int? = nil
                if parents.count == 1, row.filter({ overlap((parents[0].near, parents[0].far), ($0.near, $0.far)) }).count == 1 { run = parents[0].run }
                if run == nil { run = sections.count; sections.append([]); rowsIn.append(0) }
                current.append((span.near, span.far, run!))
                // Pair p (rows 2p and 2p + 1) is needed only where the rows are spread enough: further from the
                // centre than share × crowded, where share runs 0, ½, ¼, ¾ (then ⅛, ⅝… for longer patterns; bits
                // reversed), so whatever share of the pairs carries on, it's spread evenly. The rows on the two
                // lines run the whole way, with the row paired with the last one, so the needle ends at the line.
                let pair = (k + shift) / 2
                let share = k == count || pair == (count + shift) / 2 ? 0 : evenShare(pair % pattern), limit = share * crowded
                let near = span.near < limit ? min(span.far, span.near + max(0, limit - narrowest)) : span.near
                guard span.far - near > StitchEngine.smallestStitch else { continue }
                // Needle holes at set distances from the narrow edge, a quarter stitch further on each row, like
                // tatami, so they line up along that edge.
                var holes = [near], r = span.near + Double(k % 4) / 4 * length
                while r <= near + 0.3 { r += length }
                while r < span.far - 0.3 { holes.append(r); r += length }
                holes.append(span.far)
                var points = holes.map { centre + span.out * $0 }
                if (k + shift) % 2 == 0 { points.reverse() }   // even rows head in, odd rows back out, so pairs turn together
                // Join the run when the step from where it ended stays inside the piece; otherwise start a new one.
                let r0 = run!
                if let end = sections[r0].last {
                    if end.distance(to: points[0]) <= 2 * length, AreaGeometry.segmentInside(end, points[0], rings: inside) {
                        sections[r0] += Array(AreaGeometry.sampled([end, points[0]], length: length).dropFirst()) + points.dropFirst()
                    } else {
                        sections.append(points); rowsIn.append(1)
                        current[current.count - 1].run = sections.count - 1
                        continue
                    }
                } else {
                    sections[r0] = points
                }
                rowsIn[r0] += 1
            }
            previous = current
        }
        sections.removeAll { $0.isEmpty }
        return sections
    }

    /// The `n`th number of the sequence 0, ½, ¼, ¾, ⅛, ⅝, ⅜, ⅞…: n's binary digits mirrored behind the point. However
    /// many of the first numbers you take, they're spread evenly between 0 and 1.
    static func evenShare(_ n: Int) -> Double {
        var n = n, share = 0.0, digit = 0.5
        while n > 0 { if n & 1 == 1 { share += digit }; n >>= 1; digit /= 2 }
        return share
    }
    /// A direction (radians) from `centre` in which a ray misses `rings` altogether: the middle of the widest such
    /// gap, so a fan all the way round starts and ends outside the shape rather than in the middle of a piece.
    /// 0 when no ray misses (a ring round the centre).
    static func clearBearing(from centre: Point, of rings: [[Point]]) -> Double {
        let steps = 360
        let clear = (0..<steps).map { crossings(rings, from: centre, along: Point(cos(Double($0) / Double(steps) * 2 * .pi), sin(Double($0) / Double(steps) * 2 * .pi))).isEmpty }
        guard let hit = clear.firstIndex(of: false), clear.contains(true) else { return 0 }
        var best = (start: 0, length: 0), run = 0
        for n in 1...steps {   // round once from a direction that hits, so each gap is seen whole
            let i = (hit + n) % steps
            run = clear[i] ? run + 1 : 0
            if run > best.length { best = ((i - run + 1 + steps) % steps, run) }
        }
        return Double(best.start) / Double(steps) * 2 * .pi + Double(best.length - 1) / Double(steps) * .pi
    }
    /// Where the lines through two chords meet, or nil if they're parallel.
    static func meeting(_ p: (a: Point, b: Point), _ q: (a: Point, b: Point)) -> Point? {
        let u = p.b - p.a, v = q.b - q.a, den = AreaGeometry.cross(u, v)
        guard abs(den) > 1e-9 * (u.x * u.x + u.y * u.y + v.x * v.x + v.y * v.y) else { return nil }
        return p.a + u * (AreaGeometry.cross(q.a - p.a, v) / den)
    }
    /// How far along the ray from `origin` in direction `out` (a unit vector) it crosses the edges of `rings`, sorted:
    /// pairs of them are where the ray is inside.
    static func crossings(_ rings: [[Point]], from origin: Point, along out: Point) -> [Double] {
        var ts: [Double] = []
        for ring in rings { for i in ring.indices {
            let a = ring[i], e = ring[(i + 1) % ring.count] - a, den = AreaGeometry.cross(out, e)
            guard abs(den) > 1e-12 else { continue }
            let t = AreaGeometry.cross(a - origin, e) / den, s = AreaGeometry.cross(a - origin, out) / den
            if s >= 0 && s < 1 && t > 0 { ts.append(t) }
        }}
        return ts.sorted()
    }
    static func unit(_ chord: (a: Point, b: Point)) -> Point { (chord.b - chord.a) * (1 / chord.a.distance(to: chord.b)) }
    /// How far `p` is from the (endless) line through `chord`.
    static func offLine(_ p: Point, _ chord: (a: Point, b: Point)) -> Double { abs(AreaGeometry.cross(unit(chord), p - chord.a)) }

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
    /// A hair-thin strip along `chord`, a little longer than it, for cutting the shape in two along the chord.
    static func slit(_ chord: (a: Point, b: Point)) -> [Point] {
        let u = unit(chord) * 0.05, n = Point(-u.y, u.x) * 0.04
        let ring = [chord.a - u - n, chord.b + u - n, chord.b + u + n, chord.a - u + n]
        return AreaGeometry.area(ring) < 0 ? ring.reversed() : ring
    }
    /// How far `p` is from a segment.
    static func gap(_ p: Point, _ segment: (Point, Point)) -> Double { p.distance(to: AreaGeometry.projection(p, segment.0, segment.1)) }

    /// A length longer than any line across `region` (its bounding box's diagonal plus 1 mm), or 1 for an empty one.
    static func reach(across region: [[Point]]) -> Double {
        let points = region.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return 1 }
        return hypot(maxX - minX, maxY - minY) + 1
    }

    /// Each angle line stretched across the shape: every piece of its line that lies inside `region` (a line can cross
    /// the shape more than once), the one through or nearest the line's middle first. Lines that miss the shape
    /// entirely, or are too short to have a direction, are left out, so an empty result means the fill can't use them.
    static func stretches(in region: [[Point]], angleLines: [[Point]]) -> [[(a: Point, b: Point)]] {
        let reach = reach(across: region)
        return angleLines.compactMap { line in
            guard line.count >= 2, line[0].distance(to: line[1]) > 0.01 else { return nil }
            let middle = (line[0] + line[1]) * 0.5, u = (line[1] - line[0]) * (1 / line[0].distance(to: line[1]))
            let pieces = AreaGeometry.clippedSegment(middle - u * reach, middle + u * reach, rings: region)
            return pieces.isEmpty ? nil : pieces.sorted { gap(middle, $0) < gap(middle, $1) }.map { (a: $0.0, b: $0.1) }
        }
    }
    /// Each angle line's piece across the shape through (or nearest) its middle.
    static func chords(in region: [[Point]], angleLines: [[Point]]) -> [(a: Point, b: Point)] {
        stretches(in: region, angleLines: angleLines).map { $0[0] }
    }
}

extension RunObject {
    /// Why this fill's stitch angle lines can't be used together (two of them, stretched right across the shape,
    /// meet inside it), or nil when they can.
    public var angleLineProblem: String? { TurningFill.crossingProblem(self) }
}
