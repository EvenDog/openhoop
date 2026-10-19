// Turning fill, made with stitch angles: lines drawn across a fill set which way its stitches run. As in other
// embroidery software, each line is extended right across the shape, like a cut, and lines may not cross inside it.
// Beyond the first and last line, rows run straight at that line's angle; between two neighbouring lines, rows are
// straight lines fanning out from the point where those two lines meet, so the direction turns evenly from one line
// to the other. The pieces are sewn one after another across the shape, so each line shows as a seam.
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
            return try fan(in: region, centre: centre, from: 0, turn: 2 * .pi, spacing: spacing, length: length)
        }
        // In order across the shape: by where each line's middle lies, measured across the lines' average direction
        // (averaged with doubled angles, so a line and its reverse count the same). From the end nearest the start.
        let doubled = chords.map { 2 * direction($0) * .pi / 180 }
        let mean = atan2(doubled.map(sin).reduce(0, +), doubled.map(cos).reduce(0, +)) / 2, across = Point(-sin(mean), cos(mean))
        chords.sort { dot(mid($0), across) < dot(mid($1), across) }
        if let start, start.distance(to: mid(chords[chords.count - 1])) < start.distance(to: mid(chords[0])) { chords.reverse() }

        // `later[k]`: the side of line k (+1 left, −1 right) the lines after it lie on.
        let later = chords.indices.map { k in
            k + 1 < chords.count ? sideOf(mid(chords[k + 1]), chords[k]) : -sideOf(mid(chords[k - 1]), chords[k])
        }
        let reach = Self.reach(across: region)
        /// The part of the plane on `side` of the line through `chord`, as a big square (for cutting the shape).
        func halfPlane(_ chord: (a: Point, b: Point), _ side: Double) -> [Point] {
            let u = unit(chord), n = Point(-u.y, u.x) * side, m = mid(chord)
            let ring = [m - u * reach, m + u * reach, m + u * reach + n * reach, m - u * reach + n * reach]
            return AreaGeometry.area(ring) < 0 ? ring.reversed() : ring
        }
        var sections: [[Point]] = []
        for k in 0...chords.count {
            // The piece between line k−1 and line k: the shape without what lies before the one or after the other.
            var piece = [region]
            if k > 0 { piece = try piece.flatMap { try AreaGeometry.subtracting([halfPlane(chords[k - 1], -later[k - 1])], from: $0) } }
            if k < chords.count { piece = try piece.flatMap { try AreaGeometry.subtracting([halfPlane(chords[k], later[k])], from: $0) } }
            let rings = piece.flatMap { $0 }
            guard !rings.isEmpty else { continue }
            var rows: [[Point]]
            if k == 0 || k == chords.count {
                // An end piece: straight rows at its line's angle, sewn so they finish (or, the last piece, begin) at the line.
                let line = chords[k == 0 ? 0 : k - 1]
                let ways = try [false, true].map { try AreaEngine.rows(in: rings, angle: direction(line), spacing: spacing, length: length, fromTop: $0) }.filter { !$0.isEmpty }
                guard !ways.isEmpty else { continue }
                rows = ways.min { k == 0 ? offLine($0.last!.last!, line) < offLine($1.last!.last!, line) : offLine($0[0][0], line) < offLine($1[0][0], line) }!
            } else {
                rows = try fan(in: rings, between: chords[k - 1], and: chords[k], spacing: spacing, length: length)
            }
            // Start each piece's rows at the end nearest where the last piece finished.
            if let needle = sections.last?.last, let first = rows.first?.first, let last = rows.last?.last, needle.distance(to: last) < needle.distance(to: first) {
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
    static func fan(in piece: [[Point]], between first: (a: Point, b: Point), and second: (a: Point, b: Point), spacing: Double, length: Double) throws -> [[Point]] {
        guard let centre = meeting(first, second) else {
            return try AreaEngine.rows(in: piece, angle: direction(first), spacing: spacing, length: length)   // parallel lines
        }
        // The rows' directions, seen from the centre: from the first line's to the second's, the short way round.
        func bearing(_ p: Point) -> Double { atan2(p.y - centre.y, p.x - centre.x) }
        let from = bearing(mid(first))
        return try fan(in: piece, centre: centre, from: from, turn: remainder(bearing(mid(second)) - from, 2 * .pi), spacing: spacing, length: length)
    }
    /// Rows across `piece`, all pointing at `centre`, at directions (radians, seen from the centre) from `from` to
    /// `from + turn`; a whole turn (2π) goes all the way round.
    static func fan(in piece: [[Point]], centre: Point, from: Double, turn: Double, spacing: Double, length: Double) throws -> [[Point]] {
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
            let angle = from + turn * Double(k) / Double(count), out = Point(cos(angle), sin(angle))
            let ts = crossings(piece, from: centre, along: out)
            for i in stride(from: 0, to: ts.count - 1, by: 2) where ts[i + 1] - ts[i] > StitchEngine.smallestStitch { spans.append((k, out, ts[i], ts[i + 1])) }
        }
        let narrowest = spans.map(\.near).min() ?? 0
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
                // lines run the whole way.
                let share = k == count ? 0 : evenShare((k / 2) % pattern), limit = share * crowded
                let near = span.near < limit ? min(span.far, span.near + max(0, limit - narrowest)) : span.near
                guard span.far - near > StitchEngine.smallestStitch else { continue }
                // Needle holes at set distances from the narrow edge, a quarter stitch further on each row, like
                // tatami, so they line up along that edge.
                var holes = [near], r = span.near + Double(k % 4) / 4 * length
                while r <= near + 0.3 { r += length }
                while r < span.far - 0.3 { holes.append(r); r += length }
                holes.append(span.far)
                var points = holes.map { centre + span.out * $0 }
                if k % 2 == 0 { points.reverse() }   // even rows head in, odd rows back out, so pairs turn together
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
    /// +1 if `p` is to the left of the line through `chord` (looking from a to b), −1 if to the right.
    static func sideOf(_ p: Point, _ chord: (a: Point, b: Point)) -> Double { AreaGeometry.cross(chord.b - chord.a, p - chord.a) >= 0 ? 1 : -1 }
    static func unit(_ chord: (a: Point, b: Point)) -> Point { (chord.b - chord.a) * (1 / chord.a.distance(to: chord.b)) }
    static func dot(_ u: Point, _ v: Point) -> Double { u.x * v.x + u.y * v.y }
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

extension RunObject {
    /// Why this fill's stitch angle lines can't be used together (two of them, stretched right across the shape,
    /// meet inside it), or nil when they can.
    public var angleLineProblem: String? { TurningFill.crossingProblem(self) }
}
