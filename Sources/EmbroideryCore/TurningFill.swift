// Turning fill, made with stitch angles: lines drawn across a fill set which way its stitches run, and lines may
// not cross inside the shape. Beyond the end lines, rows run straight at that line's angle. Between two
// neighbouring lines the rows turn from one line's direction to the other's the way other embroidery software
// does it: every point of the outline gets a share, how far it is from the first line as a fraction of its
// distances to both lines, and each row is the straight stitch line joining the point on one side of the shape to
// the point on the other side with the same share. Across a rectangle that makes rows fanning out from where the
// two lines meet; round a bend it turns the rows all the way round, with no seam at any line (measured against
// that software's exports, 2026-10-19). Shapes the lines don't cross like rungs of a ladder (a ring, a Y, a hole in
// the way) are cut along the lines into pieces and sewn piece by piece instead, as before.
import Foundation

enum TurningFill {
    /// Of the rows between two lines, every other one stops short where the rows have converged to this share of
    /// the row spacing (every fourth where they've converged twice as far, and so on), so they never bunch up.
    /// Measured against the same shapes sewn by other software (2026-10-18), whose rows thin out between 0.57 and
    /// 0.75 of their spacing.
    static let thinning = 0.75

    /// The fill's rows as stitches, sewn in one sweep from one end of the shape to the other. `start` picks which
    /// end of the shape the rows begin from (the one nearest it). With `end`, the last stitch finishes as near it
    /// as the rows allow (the first row runs whichever way brings the last row's end there); a shape sewn piece by
    /// piece (see `sewPieces`) doesn't take it.
    static func rows(in region: [[Point]], angleLines: [[Point]], spacing: Double, length: Double, start: Point?, end: Point? = nil) throws -> [[Point]] {
        let chords = Self.chords(in: region, angleLines: angleLines)
        guard !chords.isEmpty else { return [] }
        if let problem = crossingProblem(chords, in: region) { throw DesignError.invalid(problem) }
        // One line sets the direction for the whole fill: ordinary rows along it.
        if chords.count == 1 {
            if let end { return try straightRows(in: region, along: chords[0], spacing: spacing, length: length, needle: nil, end: end) ?? [] }
            return try AreaEngine.rows(in: region, angle: direction(chords[0]), spacing: spacing, length: length)
        }
        // Three or more lines that all meet at one point outside the fill (lines across a ring, all pointing at the
        // middle of its hole): between every two of them the rows point at that point, so all the way round they do.
        if chords.count >= 3, let centre = meeting(chords[0], chords[1]), !AreaGeometry.contains(centre, rings: region),
           chords.allSatisfy({ offLine(centre, $0) < 0.5 }) {
            return try fan(in: region, centre: centre, from: clearBearing(from: centre, of: region), turn: 2 * .pi, spacing: spacing, length: length)
        }
        if let band = Band(region: region, chords: chords) {
            do {
                guard let end else { return try band.sew(spacing: spacing, length: length, start: start) }
                let ways = try [false, true].map { try band.sew(spacing: spacing, length: length, start: start, flip: $0) }
                return ways.min { ($0.last?.last?.distance(to: end) ?? .infinity) < ($1.last?.last?.distance(to: end) ?? .infinity) }!
            } catch is NotABand {}
        }
        return try sewPieces(in: region, angleLines: angleLines, chords: chords, spacing: spacing, length: length, start: start)
    }

    // MARK: - A band: the lines cross it one after another

    /// Thrown while sewing a band when a row turns out to leave the shape (a notch or hole in its way): the shape
    /// is sewn piece by piece instead.
    struct NotABand: Error {}

    /// A shape the lines cross one after another like the rungs of a ladder: walking round its outline you pass
    /// one end of each line in turn, then their other ends in reverse order. `order`: the lines (as indices into
    /// `chords`) from one end of the shape to the other. `sides[k]`: the two stretches of outline from line k to
    /// line k + 1 (in that order), both running that way, as points 0.1 mm apart; `shares[k]`: at each of those
    /// points, how far it is from line k as a share of its distances to both lines, 0 on line k and 1 on line k + 1,
    /// growing all the way (or the shape isn't sewn as a band). `ends`: the outline beyond the first and beyond the
    /// last line, each closed by its line.
    struct Band {
        let region: [[Point]]
        let chords: [(a: Point, b: Point)]
        let order: [Int]
        let sides: [(a: [Point], b: [Point])]
        let shares: [(a: [Double], b: [Double])]
        let ends: (first: [Point], last: [Point])

        init?(region: [[Point]], chords: [(a: Point, b: Point)]) {
            guard let outer = region.first, outer.count >= 3, chords.count >= 2 else { return nil }
            let path = outer + [outer[0]]
            // Where each line's two ends sit along the outline (both must be on the outer edge, not a hole).
            var ends: [(chord: Int, along: Double)] = []
            for (c, chord) in chords.enumerated() {
                for p in [chord.a, chord.b] {
                    let hit = AreaGeometry.alongPath(p, path)
                    guard p.distance(to: TurningFill.point(along: path, at: hit.along)) < 0.05 else { return nil }
                    ends.append((c, hit.along))
                }
            }
            ends.sort { $0.along < $1.along }
            // Going round, the ends must read as the lines in some order and then the same lines backwards.
            let n = chords.count, ids = ends.map(\.chord)
            guard let turn = (0..<(2 * n)).first(where: { r in
                (0..<n).allSatisfy { k in ids[(r + k) % (2 * n)] == ids[(r + 2 * n - 1 - k) % (2 * n)] } && Set((0..<n).map { ids[(r + $0) % (2 * n)] }).count == n
            }) else { return nil }
            let firstEnds = (0..<n).map { ends[(turn + $0) % (2 * n)] }, secondEnds = (0..<n).map { ends[(turn + 2 * n - 1 - $0) % (2 * n)] }
            let total = AreaGeometry.pathLength(path)
            /// The outline from `from` forward (the way the points run) round to `to`, as a polyline.
            func arc(from: Double, to: Double) -> [Point] {
                var walked = 0.0, corners: [(s: Double, p: Point)] = []
                let end = to >= from ? to : to + total   // past the outline's first point and on round
                for i in path.indices.dropLast() {
                    for s in [walked, walked + total] where s > from + 1e-9 && s < end - 1e-9 { corners.append((s, path[i])) }
                    walked += path[i].distance(to: path[i + 1])
                }
                let points = [TurningFill.point(along: path, at: from)] + corners.sorted { $0.s < $1.s }.map(\.p) + [TurningFill.point(along: path, at: to)]
                return TurningFill.densified(points, step: 0.1)
            }
            var sides: [(a: [Point], b: [Point])] = [], shares: [(a: [Double], b: [Double])] = []
            for k in 0..<(n - 1) {
                let from = chords[firstEnds[k].chord], to = chords[firstEnds[k + 1].chord]
                let a = arc(from: firstEnds[k].along, to: firstEnds[k + 1].along)
                let b = Array(arc(from: secondEnds[k + 1].along, to: secondEnds[k].along).reversed())
                let fa = a.map { TurningFill.share($0, from: from, to: to) }, fb = b.map { TurningFill.share($0, from: from, to: to) }
                guard TurningFill.grows(fa), TurningFill.grows(fb) else { return nil }
                // The rows must run inside the shape (a stretch round another arm of a Y, or across a hole, won't).
                for step in 1...19 where !AreaGeometry.segmentInside(TurningFill.point(on: a, shares: fa, at: Double(step) / 20), TurningFill.point(on: b, shares: fb, at: Double(step) / 20), rings: region) { return nil }
                sides.append((a, b)); shares.append((fa, fb))
            }
            self.region = region; self.chords = chords; order = firstEnds.map(\.chord); self.sides = sides; self.shares = shares
            self.ends = (first: arc(from: secondEnds[0].along, to: firstEnds[0].along), last: arc(from: firstEnds[n - 1].along, to: secondEnds[n - 1].along))
        }

        /// All the rows, as stitches: the end piece nearest `start`, then each stretch between two lines, then the
        /// far end piece, every piece carrying on from where the last one finished. `flip` runs the first row the
        /// other way (each row starts where the last ended, so every row after it turns round too).
        func sew(spacing: Double, length: Double, start: Point?, flip: Bool = false) throws -> [[Point]] {
            let n = order.count
            var forward = true
            if let start {
                let first = chords[order[0]], last = chords[order[n - 1]]
                forward = TurningFill.gap(start, (first.a, first.b)) <= TurningFill.gap(start, (last.a, last.b))
            }
            var sections: [[Point]] = []
            let holes = Array(region.dropFirst())
            func endPiece(_ ring: [Point], chord: (a: Point, b: Point)) throws {
                // A sliver thinner than half a row (the cut of a fill split at its end point lies a hair from the
                // piece's edge) holds no row of its own.
                guard abs(AreaGeometry.area(ring)) > 0.1, ring.map({ TurningFill.offLine($0, chord) }).max() ?? 0 >= spacing / 2 else { return }
                let inside = holes.filter { AreaGeometry.contains(AreaGeometry.centroid($0), rings: [ring]) }
                if let rows = try TurningFill.straightRows(in: [ring] + inside, along: chord, spacing: spacing, length: length, needle: sections.last?.last, flip: flip) { sections += rows }
            }
            try endPiece(forward ? ends.first : ends.last, chord: chords[forward ? order[0] : order[n - 1]])
            for step in 0..<(n - 1) {
                let k = forward ? step : n - 2 - step
                var a = sides[k].a, b = sides[k].b, fa = shares[k].a, fb = shares[k].b
                if !forward { a.reverse(); b.reverse(); fa = fa.reversed().map { 1 - $0 }; fb = fb.reversed().map { 1 - $0 } }
                sections += try between(a, fa, b, fb, spacing: spacing, length: length, needle: sections.last?.last, toTheEnd: step == n - 2, flip: flip)
            }
            try endPiece(forward ? ends.last : ends.first, chord: chords[forward ? order[n - 1] : order[0]])
            return sections
        }

        /// Rows between two lines: from the line already sewn (share 0) to the next (share 1), each row joining the
        /// points with the same share on the two sides, `spacing` apart along the longer side. The rows are sewn
        /// back and forth as pairs that stop short together where the rows converge (see `thinning`): rows aren't
        /// rays from one point here, so each row's crowding is measured against its neighbour at either end.
        /// `toTheEnd`: include the row on the far line too (the last stretch; otherwise the next stretch starts there).
        /// `flip`: with nothing sewn yet (no `needle`), the first row runs the other way.
        func between(_ a: [Point], _ fa: [Double], _ b: [Point], _ fb: [Double], spacing: Double, length: Double, needle: Point?, toTheEnd: Bool, flip: Bool = false) throws -> [[Point]] {
            let outerIsA = AreaGeometry.pathLength(a) >= AreaGeometry.pathLength(b)
            let outer = outerIsA ? a : b, fo = outerIsA ? fa : fb, inner = outerIsA ? b : a, fi = outerIsA ? fb : fa
            // Where the rows go: `spacing` apart measured across them at the outer side (further apart along the
            // side where they cross it at a slant), from the first line to the last.
            var measure = [0.0]
            for k in 1..<outer.count {
                let tangent = outer[k] - outer[k - 1], ds = hypot(tangent.x, tangent.y)
                let row = point(on: inner, shares: fi, at: fo[k]) - outer[k], rowLength = hypot(row.x, row.y)
                let slant = ds > 0 && rowLength > 0 ? abs(AreaGeometry.cross(tangent, row)) / (ds * rowLength) : 1
                measure.append(measure[measure.count - 1] + ds * max(slant, 0.05))
            }
            let whole = measure[measure.count - 1]
            let count = max(1, Int((whole / spacing).rounded()))
            guard count <= 20000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
            var rows: [(o: Point, i: Point)] = []
            for j in 0...(toTheEnd ? count : count - 1) {
                // The row on the first line sits a tenth of a row in from it, clear of the shape's edge there.
                let m = max(min(0.1 * spacing, whole), min(whole, whole * Double(j) / Double(count)))
                let k = max(1, measure.firstIndex { $0 >= m } ?? outer.count - 1)
                let t = measure[k] > measure[k - 1] ? (m - measure[k - 1]) / (measure[k] - measure[k - 1]) : 0
                let o = outer[k - 1] + (outer[k] - outer[k - 1]) * t, share = fo[k - 1] + (fo[k] - fo[k - 1]) * t
                rows.append((o, point(on: inner, shares: fi, at: share)))
            }
            // Each row seen from its narrow end (where it's closer to its neighbour): the direction to its wide end,
            // its length, the gaps to the neighbouring row at both ends, and the part of it inside the shape (as
            // distances from the narrow end).
            typealias Row = (origin: Point, out: Point, length: Double, gapNarrow: Double, gapWide: Double, spans: [(near: Double, far: Double)])
            var laid: [Row] = [], narrowAtInner = true
            for (j, row) in rows.enumerated() {
                if j % 64 == 0 { try Task.checkCancellation() }
                let other = rows[j + 1 < rows.count ? j + 1 : max(0, j - 1)]
                let gapO = TurningFill.offLine(row.o, (a: other.o, b: other.i)), gapI = TurningFill.offLine(row.i, (a: other.o, b: other.i))
                // Rows as good as parallel keep the last row's choice of narrow end, so they go on alternating.
                if abs(gapI - gapO) > 0.01 * spacing { narrowAtInner = gapI < gapO }
                let narrow = narrowAtInner ? row.i : row.o, wide = narrowAtInner ? row.o : row.i
                let rowLength = narrow.distance(to: wide)
                guard rowLength > StitchEngine.smallestStitch else { continue }
                let out = (wide - narrow) * (1 / rowLength)
                // A row cutting across a sharp inner corner keeps its long part inside the shape and drops the sliver
                // beyond the corner; one mostly outside the shape (a notch or hole in the way) means this isn't a band.
                let spans = AreaGeometry.clippedSegment(narrow, wide, rings: region).map { (near: narrow.distance(to: $0.0), far: narrow.distance(to: $0.1)) }
                guard let span = spans.max(by: { $0.far - $0.near < $1.far - $1.near }), span.far - span.near > 0.7 * rowLength else { throw NotABand() }
                laid.append((origin: narrow, out: out, length: rowLength, gapNarrow: min(gapO, gapI), gapWide: max(gapO, gapI), spans: [span]))
            }
            guard !laid.isEmpty else { return [] }
            // Which way each row is sewn: back and forth, each row starting at the end nearer where the last one
            // finished (the first, nearer the needle). A row heads in when it ends at its narrow end.
            var headsIn: [Bool] = [], needleAt = needle
            for row in laid {
                let far = row.origin + row.out * row.length
                let startsNarrow = needleAt.map { $0.distance(to: row.origin) <= $0.distance(to: far) } ?? flip
                headsIn.append(!startsNarrow); needleAt = startsNarrow ? far : row.origin
            }
            // Pairs stop short in a repeating pattern of 4 (pairs 1 and 3 of each 4, at two depths), or 8, 16… where
            // the rows converge so far that keeping half of them still crowds them (see `fan`). A pair is a row
            // heading in and the row heading back out after it; both stop where the gap to the next row (growing
            // evenly along the row) reaches the share of the spacing the pattern allows the pair, so the needle
            // only steps across between them. A row without a partner (where the narrow end swaps sides) runs full.
            let tightest = laid.map(\.gapNarrow).filter { $0 > 0 }.min() ?? spacing
            let pattern = 1 << max(2, Int(ceil(log2(max(1, TurningFill.thinning * spacing / tightest)))) + 1)
            var stops = [Double](repeating: 0, count: laid.count), pair = 0
            var k = 0
            while k + 1 < laid.count {
                guard headsIn[k], !headsIn[k + 1] else { k += 1; continue }
                let row = laid[k], allowed = (k + 1 == laid.count - 1 ? 0 : TurningFill.evenShare(pair % pattern)) * TurningFill.thinning * spacing
                if row.gapNarrow < allowed, row.gapWide > row.gapNarrow {
                    stops[k] = (allowed - row.gapNarrow) / (row.gapWide - row.gapNarrow) * row.length; stops[k + 1] = stops[k]
                }
                pair += 1; k += 2
            }
            return TurningFill.sewRows(laid.indices.map { k in
                let row = laid[k]
                return (origin: row.origin, out: row.out, spans: row.spans, stop: stops[k], depth: stops[k], headsIn: headsIn[k], holeShift: Double(k % 4) / 4 * length)
            }, in: region, length: length, byNeedle: true)
        }

        func point(on side: [Point], shares: [Double], at value: Double) -> Point { TurningFill.point(on: side, shares: shares, at: value) }
    }

    /// The point on `side` whose share is `value` (the sides' shares only grow, so it's found by halving).
    static func point(on side: [Point], shares: [Double], at value: Double) -> Point {
        var lo = 0, hi = side.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if shares[mid] < value { lo = mid } else { hi = mid } }
        let t = shares[hi] > shares[lo] ? max(0, min(1, (value - shares[lo]) / (shares[hi] - shares[lo]))) : 0
        return side[lo] + (side[hi] - side[lo]) * t
    }

    /// Rows given as `origin` + `out` × distance, each sewn over its `spans` (distances from the origin, in pairs),
    /// with needle holes every `length` from `holeShift` on, heading in towards the origin (`headsIn`) or out; with
    /// `byNeedle`, a row carrying on a run instead starts at whichever end is nearer where the run is, so a row
    /// left out or stopping short doesn't throw the back-and-forth off. A span starting nearer the origin than
    /// `stop` is a row stopping short: it begins `depth` further out instead.
    /// Rows split by a notch go into separate runs, as tatami's do: a row's piece carries on the run of the piece
    /// beside it on the row before when that's the only one it touches, and touches only it; elsewhere (where the
    /// shape splits or joins) a new run starts. Each run is sewn back and forth on its own, the step from one row
    /// to the next staying inside `rings`.
    static func sewRows(_ rows: [(origin: Point, out: Point, spans: [(near: Double, far: Double)], stop: Double, depth: Double, headsIn: Bool, holeShift: Double)], in rings: [[Point]], length: Double, byNeedle: Bool = false) -> [[Point]] {
        let inside = (try? AreaGeometry.offset(rings, by: 0.05)) ?? rings
        var sections: [[Point]] = []   // each run's needle points
        var previous: [(near: Double, far: Double, run: Int)] = []
        for row in rows {
            func overlap(_ a: (near: Double, far: Double), _ b: (near: Double, far: Double)) -> Bool { min(a.far, b.far) - max(a.near, b.near) > 0 }
            var current: [(near: Double, far: Double, run: Int)] = []
            for span in row.spans {
                let parents = previous.filter { overlap(($0.near, $0.far), (span.near, span.far)) }
                var run: Int? = nil
                if parents.count == 1, row.spans.filter({ overlap((parents[0].near, parents[0].far), ($0.near, $0.far)) }).count == 1 { run = parents[0].run }
                if run == nil { run = sections.count; sections.append([]) }
                current.append((span.near, span.far, run!))
                let near = span.near < row.stop ? min(span.far, span.near + row.depth) : span.near
                guard span.far - near > StitchEngine.smallestStitch else { continue }
                // Needle holes at set distances from the narrow edge, a quarter stitch further on each row, like
                // tatami, so they line up along that edge.
                var holes = [near], r = span.near + row.holeShift
                while r <= near + 0.3 { r += length }
                while r < span.far - 0.3 { holes.append(r); r += length }
                holes.append(span.far)
                var points = holes.map { row.origin + row.out * $0 }
                let r0 = run!
                if byNeedle, let end = sections[r0].last {
                    if end.distance(to: points[points.count - 1]) < end.distance(to: points[0]) { points.reverse() }
                } else if row.headsIn { points.reverse() }
                // Join the run when the step from where it ended stays inside the shape; otherwise start a new one.
                if let end = sections[r0].last {
                    if end.distance(to: points[0]) <= 2 * length, AreaGeometry.segmentInside(end, points[0], rings: inside) {
                        sections[r0] += Array(AreaGeometry.sampled([end, points[0]], length: length).dropFirst()) + points.dropFirst()
                    } else {
                        sections.append(points)
                        current[current.count - 1].run = sections.count - 1
                    }
                } else {
                    sections[r0] = points
                }
            }
            previous = current
        }
        sections.removeAll { $0.isEmpty }
        return sections
    }

    /// Straight rows at the line's angle across `rings`, sewn so they finish at the line when nothing has been
    /// sewn yet (`needle` nil), otherwise begin at the line, at the end of it nearest the needle. Nil when the
    /// rings hold no rows. With nothing sewn yet, `end` asks for the way whose last stitch finishes nearest it,
    /// and `flip` for the way whose first row runs the other way from the usual choice.
    static func straightRows(in rings: [[Point]], along line: (a: Point, b: Point), spacing: Double, length: Double, needle: Point?, flip: Bool = false, end: Point? = nil) throws -> [[Point]]? {
        let ways = try [false, true].flatMap { top in try [false, true].map { try AreaEngine.rows(in: rings, angle: direction(line), spacing: spacing, length: length, fromTop: top, startReversed: $0) } }.filter { !$0.isEmpty }
        guard !ways.isEmpty else { return nil }
        guard let needle else {
            let usual = ways.min { offLine($0.last!.last!, line) < offLine($1.last!.last!, line) }!
            let finishing = ways.filter { offLine($0.last!.last!, line) <= offLine(usual.last!.last!, line) + 0.5 }   // all the ways finishing at the line
            if let end { return finishing.min { $0.last!.last!.distance(to: end) < $1.last!.last!.distance(to: end) } }
            return flip ? finishing.first { $0[0][0].distance(to: usual[0][0]) > 0.5 } ?? usual : usual
        }
        let atLine = ways.map { offLine($0[0][0], line) }.min()!
        return ways.filter { offLine($0[0][0], line) <= atLine + 0.5 }.min { needle.distance(to: $0[0][0]) < needle.distance(to: $1[0][0]) }
    }

    /// How far `p` is from the line `from` as a share of its distances to both lines: 0 on `from`, 1 on `to`.
    static func share(_ p: Point, from: (a: Point, b: Point), to: (a: Point, b: Point)) -> Double {
        let d1 = gap(p, (from.a, from.b)), d2 = gap(p, (to.a, to.b))
        return d1 + d2 > 0 ? d1 / (d1 + d2) : 0
    }
    /// Whether the values only grow (allowing for rounding), from about 0 to about 1.
    static func grows(_ values: [Double]) -> Bool {
        guard let first = values.first, let last = values.last, first < 0.02, last > 0.98 else { return false }
        return zip(values, values.dropFirst()).allSatisfy { $1 >= $0 - 1e-6 }
    }
    /// `path` with points added so no step along it is longer than `step`.
    static func densified(_ path: [Point], step: Double) -> [Point] {
        guard path.count >= 2 else { return path }
        var result: [Point] = []
        for (a, b) in zip(path, path.dropFirst()) {
            let n = max(1, Int(ceil(a.distance(to: b) / step)))
            for k in 0..<n { result.append(a + (b - a) * (Double(k) / Double(n))) }
        }
        result.append(path[path.count - 1])
        return result
    }

    // MARK: - Any other shape: cut along the lines and sewn piece by piece

    /// Each line is extended right across the shape, like a cut. In a piece beyond the end line, rows run
    /// straight at that line's angle; in a piece between two lines, rows are straight lines fanning out from the
    /// point where those two lines meet, so the direction turns evenly from one line to the other (straight,
    /// between parallel lines). The pieces are sewn one after another, each next to the last and carrying on from
    /// where the last finished, so each line shows as a seam.
    private static func sewPieces(in region: [[Point]], angleLines: [[Point]], chords: [(a: Point, b: Point)], spacing: Double, length: Double, start: Point?) throws -> [[Point]] {
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
            switch touching.count {
            case 2:
                // Between two lines: rows fan from the one it was entered by to the other, the first row starting
                // from whichever end of that line the needle is nearer. Between parallel lines, straight rows.
                let from = entry ?? borders[i][0], to = borders[i].first { cuts[$0].line != cuts[from].line }!
                guard let centre = meeting(cuts[from].chord, cuts[to].chord) else {
                    guard let picked = try straightRows(in: rings, along: cuts[from].chord, spacing: spacing, length: length, needle: sections.last?.last) else { continue }
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
                guard let picked = try straightRows(in: rings, along: line, spacing: spacing, length: length, needle: sections.last?.last) else { continue }
                rows = picked
            default:
                // Where three or more lines meet a piece (the middle of a Y): straight rows at their average angle,
                // averaged with doubled angles so a line and its reverse count the same, begun nearest the needle.
                let doubled = touching.map { 2 * direction(chords[$0]) * .pi / 180 }
                let mean = atan2(doubled.map(sin).reduce(0, +), doubled.map(cos).reduce(0, +)) / 2 * 180 / .pi
                let all = try [false, true].flatMap { top in try [false, true].map { try AreaEngine.rows(in: rings, angle: mean, spacing: spacing, length: length, fromTop: top, startReversed: $0) } }.filter { !$0.isEmpty }
                let needle = sections.last?.last ?? start ?? Point(0, 0)
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

    /// Why these lines can't be used together, or nil: two of them cross inside the shape. Across a band (see
    /// `Band`) that means the lines themselves, as stretched across it; for any other shape, two lines extended
    /// right across it meeting inside it (its pieces fan from where their lines meet).
    static func crossingProblem(_ chords: [(a: Point, b: Point)], in region: [[Point]]) -> String? {
        let message = "Angle lines must not cross inside the fill area. Stretched right across the shape, two of them meet inside it: move or remove one."
        for i in chords.indices { for j in chords.indices where j > i {
            if offLine(chords[j].a, chords[i]) < 0.01, offLine(chords[j].b, chords[i]) < 0.01 { continue }   // the same line drawn twice
            if AreaGeometry.intersects(chords[i].a, chords[i].b, chords[j].a, chords[j].b) { return message }
        }}
        if chords.count >= 2, Band(region: region, chords: chords) != nil { return nil }
        for i in chords.indices { for j in chords.indices where j > i {
            if let meeting = meeting(chords[i], chords[j]), AreaGeometry.contains(meeting, rings: region) { return message }
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
        let byRow = Dictionary(grouping: spans, by: \.k)
        return sewRows(byRow.keys.sorted().map { k in
            let row = byRow[k]!
            // Pair p (rows 2p and 2p + 1) is needed only where the rows are spread enough: further from the
            // centre than share × crowded, where share runs 0, ½, ¼, ¾ (then ⅛, ⅝… for longer patterns; bits
            // reversed), so whatever share of the pairs carries on, it's spread evenly. The rows on the two
            // lines run the whole way, with the row paired with the last one, so the needle ends at the line.
            let pair = (k + shift) / 2
            let share = k == count || pair == (count + shift) / 2 ? 0 : evenShare(pair % pattern), limit = share * crowded
            // The places pairs turn keep the same distance from the narrow edge, so they line up along it.
            return (origin: centre, out: row[0].out, spans: row.map { (near: $0.near, far: $0.far) }, stop: limit, depth: max(0, limit - narrowest), headsIn: (k + shift) % 2 == 0, holeShift: Double(k % 4) / 4 * length)
        }, in: piece, length: length)
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
