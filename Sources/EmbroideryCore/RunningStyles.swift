// The decorative line stitches a running line can have instead of plain running stitch: zigzag, blanket (E-stitch),
// back stitch and stem stitch. Each is built along the line's path, measured by distance along it, so it follows
// curves and corners. Properties picks the style (DigitizingSettings.runStyle).
import Foundation

public enum RunningStyles {
    /// The needle points for `style` along the line `path` (its points in sewing order; a closed line's last point is
    /// its first again). `width` is across the line and `spacing` along it (mm); `length` is the stitch length.
    /// Returns nil for plain running stitch, which RunningEngine sews.
    public static func stitches(_ style: RunStyle, along path: [Point], closed: Bool, width: Double, spacing: Double, length: Double) -> [Point]? {
        let line = Measured(path)
        guard line.total > 0.01 else { return nil }
        switch style {
        case .running: return nil
        case .zigzag: return zigzag(line, closed: closed, width: width, spacing: spacing)
        case .blanket: return blanket(line, closed: closed, prong: width, spacing: spacing, length: length, inward: closed && AreaGeometry.area(path) > 0)
        case .backStitch: return backStitch(line, length: length, offset: 0)
        case .stemStitch: return backStitch(line, length: length, offset: width / 2)
        }
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
