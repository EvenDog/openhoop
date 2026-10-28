// The decorative line stitches a running line can have instead of plain running stitch: zigzag, blanket (E-stitch),
// back stitch, stem stitch, motifs and ripple. Each is built along the line's path, measured by distance along it, so
// it follows curves and corners. Properties picks the style (DigitizingSettings.runStyle).
import Foundation

public enum RunningStyles {
    /// The needle points for `style` along the line `path` (its points in sewing order; a closed line's last point is
    /// its first again). `width` is across the line and `spacing` along it (mm), for a motif its size and the gap
    /// between motifs (`motif` is its stroke, nil for hearts); `length` is the stitch length. A ripple shrinks `lines` copies toward `target` (nil is the
    /// default, `rippleTarget`). Returns nil for plain running stitch, which RunningEngine sews.
    public static func stitches(_ style: RunStyle, along path: [Point], closed: Bool, width: Double, spacing: Double, length: Double, motif: [Point]? = nil,
                                target: Point? = nil, lines: Int = DigitizingSettings.defaultRippleLines) -> [Point]? {
        let line = Measured(path)
        guard line.total > 0.01, style != .running else { return nil }
        // Back and stem stitch step forward two stitch lengths, so their stitch length is kept to 4 mm at most.
        let points: [Point]
        switch style {
        case .running: return nil
        case .zigzag: points = zigzag(line, closed: closed, width: width, spacing: spacing)
        case .blanket: points = blanket(line, closed: closed, prong: width, spacing: spacing, length: length, inward: closed && AreaGeometry.area(path) > 0)
        case .backStitch: points = backStitch(line, length: min(length, 4), offset: 0)
        case .stemStitch: points = backStitch(line, length: min(length, 4), offset: width / 2)
        case .motif: points = Motifs.run(along: path, motif: motif ?? Motifs.stroke(.heart), size: width, gap: spacing, length: length)
        case .ripple: points = ripple(line, closed: closed, target: target ?? rippleTarget(path, closed: closed), lines: lines, length: length)
        }
        return split(points, longest: longestStitch)
    }

    /// Ripple: the line sewn `lines` times, each copy the same shape scaled down toward `target`, like ripples on
    /// water. A closed line spirals in: the copy shrinks gradually all the way round each lap, so it's one unbroken
    /// line from the outline in to the smallest ring (a `lines`th of the size). An open line is sewn there and back,
    /// each copy smaller, joined by a short stitch from one copy's end to the next. In stitches of about `length`.
    static func ripple(_ line: Measured, closed: Bool, target: Point, lines: Int, length: Double) -> [Point] {
        let count = max(2, lines)
        func scaled(_ p: Point, _ factor: Double) -> Point { target + (p - target) * factor }
        guard closed else {
            var points: [Point] = []
            for k in 0..<count {
                let copy = line.points.map { scaled($0, 1 - Double(k) / Double(count)) }
                points += GuidedFill.stitches(k % 2 == 0 ? copy : copy.reversed(), length: length, offset: 0)
            }
            return points
        }
        // Where the spiral is worked out on each lap: every corner of the outline, and every quarter millimetre.
        let marks = Array(Set(line.distances + stride(from: 0, to: line.total, by: 0.25).map { $0 })).sorted().filter { $0 < line.total }
        var spiral: [Point] = []
        for lap in 0..<(count - 1) {
            for s in marks { spiral.append(scaled(line.point(at: s), 1 - (Double(lap) + s / line.total) / Double(count))) }
        }
        spiral.append(scaled(line.points[0], 1 / Double(count)))
        // (GuidedFill.stitches spaces stitches evenly along a curved path, with a needle point at every sharp corner.)
        return GuidedFill.stitches(spiral, length: length, offset: 0)
    }
    /// Where a ripple shrinks toward unless its target has been moved: the middle of a closed shape; for an open line,
    /// the middle of its points, or, when that's on the line (a nearly straight or wavy one), half the distance
    /// between its ends off to one side of the line from end to end, so the copies fan out. The line's direction
    /// doesn't matter.
    public static func rippleTarget(_ path: [Point], closed: Bool) -> Point {
        let line = Measured(path)
        guard line.points.count >= 2 else { return line.points.first ?? Point(0, 0) }
        if closed { return AreaGeometry.centroid(line.points) }
        // The line taken from its left (or lower) end, so the side doesn't depend on which way it's sewn.
        let first = line.points[0], last = line.points[line.points.count - 1]
        let forward = first.x < last.x || (first.x == last.x && first.y <= last.y)
        let along = forward ? line : Measured(line.points.reversed())
        var middle = Point(0, 0)
        for (a, b) in zip(along.points, along.points.dropFirst()) { middle = middle + (a + b) * (0.5 * a.distance(to: b) / along.total) }
        let nearest = zip(along.points, along.points.dropFirst()).map { middle.distance(to: AreaGeometry.projection(middle, $0, $1)) }.min() ?? 0
        guard nearest < 0.15 * along.total else { return middle }
        let ends = along.points[along.points.count - 1] - along.points[0], span = max(1e-9, ends.distance(to: Point(0, 0)))
        return (along.points[0] + along.points[along.points.count - 1]) * 0.5 + Point(-ends.y, ends.x) * (0.5 * max(span, along.total / 2) / span)
    }

    /// The longest stitch a line style makes (mm). A longer one (a very wide, very open zigzag, say) is split into
    /// equal stitches along it: machines can't sew much over 12 mm, and long stitches snag.
    static let longestStitch = 10.0
    /// `points` with every stitch longer than `longest` split into equal pieces along it.
    static func split(_ points: [Point], longest: Double) -> [Point] {
        guard let first = points.first else { return points }
        var result = [first]
        for (a, b) in zip(points, points.dropFirst()) {
            let pieces = max(1, Int(ceil(a.distance(to: b) / longest)))
            for i in 1...pieces { result.append(a + (b - a) * (Double(i) / Double(pieces))) }
        }
        return result
    }

    /// Zigzag: points spaced about `spacing` apart along the line, alternately half the width to its left and right.
    /// A closed line has an even number of them, so the zigzag meets itself in step.
    static func zigzag(_ line: Measured, closed: Bool, width: Double, spacing: Double) -> [Point] {
        var count = max(2, Int((line.total / spacing).rounded()))
        if closed && count % 2 == 1 { count += 1 }
        return (0...count).map { k in
            let s = line.total * Double(k) / Double(count), side = k % 2 == 0 ? 1.0 : -1.0
            return line.point(at: s) + line.normal(at: s) * (side * width / 2)
        }
    }

    /// Blanket (E-stitch): running stitch along the line, and every `spacing` a prong straight out to one side by
    /// `prong` and back. The prongs go to the left of the sewing direction, which is inside a counterclockwise
    /// closed shape; `inward` says the shape's inside is to the left, so they always point into it.
    static func blanket(_ line: Measured, closed: Bool, prong: Double, spacing: Double, length: Double, inward: Bool) -> [Point] {
        let count = max(1, Int((line.total / spacing).rounded())), side = closed && !inward ? -1.0 : 1.0
        var points: [Point] = []
        for k in 0...count {
            let s = line.total * Double(k) / Double(count), base = line.point(at: s)
            // The run from the last prong to this one, in stitches of about `length`.
            if k > 0 {
                let from = line.total * Double(k - 1) / Double(count), pieces = max(1, Int(ceil((s - from) / length)))
                for i in 1..<pieces { points.append(line.point(at: from + (s - from) * Double(i) / Double(pieces))) }
            }
            points.append(base)
            // A closed line's last prong would sit on its first, so it's left out.
            if !(closed && k == count) { points += [base + line.normal(at: s) * (side * prong), base] }
        }
        return points
    }

    /// Back stitch: each stitch goes forward two stitch lengths and back one, so every stretch is sewn over and the
    /// line looks solid. Stem stitch is the same with the forward stitches `offset` to the left and the backward
    /// ones to the right, so each slants across the line like a twisted rope.
    static func backStitch(_ line: Measured, length: Double, offset: Double) -> [Point] {
        let count = max(1, Int((line.total / length).rounded()))
        func place(_ k: Int, _ side: Double) -> Point {
            let s = line.total * Double(min(k, count)) / Double(count)
            return line.point(at: s) + line.normal(at: s) * (side * offset)
        }
        guard count >= 2 else { return [place(0, 0), place(count, 0)] }
        var points = [place(0, 0)]
        for k in 0..<(count - 1) { points += [place(k + 2, 1), place(k + 1, -1)] }
        points.append(place(count, 0))
        return points
    }

    /// A path measured by distance along it: the point and the left-hand direction at any distance from its start.
    struct Measured {
        let points: [Point]
        /// The distance along the path at each of its points.
        let distances: [Double]
        var total: Double { distances.last ?? 0 }
        init(_ path: [Point]) {
            var kept: [Point] = []
            for p in path where kept.last.map({ $0.distance(to: p) > 1e-9 }) ?? true { kept.append(p) }
            points = kept
            var walked = 0.0, distances = [0.0]
            for (a, b) in zip(kept, kept.dropFirst()) { walked += a.distance(to: b); distances.append(walked) }
            self.distances = distances
        }
        /// Which piece of the path distance `s` falls on (the index of its first point).
        private func piece(_ s: Double) -> Int {
            var low = 0, high = max(0, points.count - 2)
            while low < high { let mid = (low + high + 1) / 2; if distances[mid] <= s { low = mid } else { high = mid - 1 } }
            return low
        }
        func point(at s: Double) -> Point {
            guard points.count > 1 else { return points.first ?? Point(0, 0) }
            let i = piece(s), a = points[i], b = points[i + 1], span = distances[i + 1] - distances[i]
            return span > 0 ? a + (b - a) * ((s - distances[i]) / span) : a
        }
        /// The direction 90° to the left of the path at `s` (one unit long). At a corner exactly, the corner's two
        /// pieces are averaged, so a prong or zig there points between them.
        func normal(at s: Double) -> Point {
            guard points.count > 1 else { return Point(0, 1) }
            let i = piece(s)
            func left(_ k: Int) -> Point { let d = points[k + 1] - points[k], n = max(1e-12, hypot(d.x, d.y)); return Point(-d.y / n, d.x / n) }
            var n = left(i)
            // The piece before: the one before this, or, at the start of a closed path, its last piece.
            let closed = points.count > 2 && points[0].distance(to: points[points.count - 1]) < 1e-9
            let before = abs(s - distances[i]) < 1e-9 ? (i > 0 ? i - 1 : closed ? points.count - 2 : nil) : nil
            if let before { let m = left(before) + n; let size = hypot(m.x, m.y); if size > 1e-9 { n = m * (1 / size) } }
            return n
        }
    }
}
