// Motif stitches and the cross stitch fill. A motif is a small pattern (heart, leaf, diamond, star, scallop, circle,
// or one of the user's own made from lines with Create Motif) drawn as one stroke of running stitch that starts and
// ends on its baseline, so motifs can be strung along a line (a motif run) or set out in rows across a shape (a motif
// fill). The cross stitch fill covers a shape's whole squares with X's.
import Foundation

public enum Motifs {
    /// The motif as one stroke in a unit box: `x` from 0 (where it starts, on the baseline) to 1 (where it ends, on
    /// the baseline), `y` across it (most motifs stand above the baseline, 0 to 1; the leaf and diamond sit across it).
    /// Points along curves are close together; corners are exact.
    static func stroke(_ motif: Motif) -> [Point] {
        switch motif {
        case .heart:
            // The classic heart curve, with its point at the bottom middle, on the baseline.
            let loop = (0...64).map { k -> Point in
                let t = .pi + 2 * .pi * Double(k) / 64
                let x = 16 * pow(sin(t), 3), y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
                return Point(0.5 + x / 32 * 0.9, (y + 17) / 30)
            }
            return [Point(0, 0)] + loop + [Point(1, 0)]
        case .leaf:
            // The upper edge, the lower edge back, then the vein along the middle.
            let upper = (0...24).map { k -> Point in let u = Double(k) / 24; return Point(u, 0.35 * sin(.pi * u)) }
            let lower = upper.reversed().map { Point($0.x, -$0.y) }
            return upper + lower.dropFirst() + [Point(1, 0)]
        case .diamond:
            return [Point(0, 0), Point(0.5, 0.45), Point(1, 0), Point(0.5, -0.45), Point(0, 0), Point(1, 0)]
        case .star:
            // A five-pointed star standing on its two lower points: once round, then the two lower edges again to
            // finish at the right.
            let corner = { (k: Int) -> Point in
                let a = (90 + 36 * Double(k)) * .pi / 180, r = k % 2 == 0 ? 0.5 : 0.2
                return Point(0.5 + r * cos(a), r * sin(a) + 0.5 * sin(54 * .pi / 180))   // the lower points on y = 0
            }
            return [Point(0, 0)] + (4...14).map { corner($0 % 10) } + [corner(5), corner(6), Point(1, 0)]
        case .scallop:
            return (0...24).map { k -> Point in let u = Double(k) / 24; return Point(u, 0.5 * sin(.pi * u)) }
        case .circle:
            let loop = (0...48).map { k -> Point in let a = -.pi / 2 + 2 * .pi * Double(k) / 48; return Point(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)) }
            return [Point(0, 0)] + loop + [Point(1, 0)]
        }
    }

    /// A motif of one's own from `lines` (running lines' paths, in sewing order), named `name`. The lines are joined
    /// into one stroke by straight runs, each line sewn from whichever of its ends is nearer where the last one ended.
    /// The stroke starts at its left end and finishes at its right end: it's turned and scaled so those sit at (0, 0)
    /// and (1, 0), like the built-in motifs. When its ends meet (a closed shape) it has no left and right ends, so it
    /// starts and finishes at its lowest point instead, with runs in from the bottom left corner and out to the bottom
    /// right, like the circle.
    public static func make(from lines: [[Point]], name: String) throws -> CustomMotif {
        var stroke: [Point] = []
        for line in lines where line.count >= 2 {
            guard let end = stroke.last else { stroke = line; continue }
            stroke += line.last!.distance(to: end) < line.first!.distance(to: end) ? line.reversed() : line
        }
        let xs = stroke.map(\.x), ys = stroke.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), max(maxX - minX, maxY - minY) > 0.1 else {
            throw DesignError.invalid("Select at least one running line to make a motif from.")
        }
        guard stroke.count <= CustomMotif.pointLimit else { throw DesignError.invalid("These lines have too many points for a motif. Try Smooth Shapes first.") }
        let first = stroke.first!, last = stroke.last!, width = maxX - minX
        // "Meet" means closer together than a tenth of the drawing's size, so a hand-drawn loop counts too.
        if first.distance(to: last) < 0.1 * max(width, maxY - minY) {
            guard width > 0.1 else { throw DesignError.invalid("A closed motif needs some width, to join one copy to the next.") }
            // Start the loop again at its lowest point, so the runs in and out go along the bottom.
            var loop = first.distance(to: last) < 1e-6 ? Array(stroke.dropLast()) : stroke
            let lowest = loop.indices.min { loop[$0].y < loop[$1].y }!
            loop = Array(loop[lowest...] + loop[..<lowest]) + [loop[lowest]]
            let placed = [Point(minX, minY)] + loop + [Point(maxX, minY)]
            return CustomMotif(name: name, stroke: placed.map { Point(($0.x - minX) / width, ($0.y - minY) / width) })
        }
        if last.x < first.x { stroke.reverse() }
        // Turn and scale so the start lands on (0, 0) and the end on (1, 0): x is how far along the baseline a point
        // is, y how far to its left (above it), both divided by the baseline's length.
        let start = stroke.first!, along = stroke.last! - start, squared = along.x * along.x + along.y * along.y
        return CustomMotif(name: name, stroke: stroke.map { p in
            let d = p - start
            return Point((d.x * along.x + d.y * along.y) / squared, (along.x * d.y - along.y * d.x) / squared)
        })
    }

    /// A motif run: `motif` (a stroke like `stroke(_:)`'s), `size` mm long, repeated along `path` with `gap` mm between motifs, joined by running
    /// stitch along the line. The row of motifs is centered, so the line's two ends get equal runs. Each motif follows
    /// the line as it curves. Stitches are about `length` mm, shorter in the motifs so their curves stay round.
    public static func run(along path: [Point], motif shape: [Point], size: Double, gap: Double, length: Double) -> [Point] {
        let line = RunningStyles.Measured(path)
        let count = Int((line.total + gap) / (size + gap)), small = max(0.4, min(length, size / 5))
        guard count >= 1 else { return evenly(path, length: length) }
        let used = Double(count) * size + Double(count - 1) * gap, first = (line.total - used) / 2
        var points = [line.point(at: 0)], lastDistance = 0.0
        /// Running stitch along the line from where the last motif (or run) ended to distance `s`.
        func runTo(_ s: Double) {
            let pieces = max(1, Int(ceil((s - lastDistance) / length)))
            if s - lastDistance > 1e-6 { for i in 1...pieces { points.append(line.point(at: lastDistance + (s - lastDistance) * Double(i) / Double(pieces))) } }
            lastDistance = s
        }
        for k in 0..<count {
            let start = first + Double(k) * (size + gap)
            runTo(start)
            let placed = shape.map { p -> Point in let s = start + p.x * size; return line.point(at: s) + line.normal(at: s) * (p.y * size) }
            points += evenly(placed, length: small).dropFirst()
            lastDistance = start + size
        }
        runTo(line.total)
        return points
    }

    /// Motif fill: whole motifs (`motif` is a stroke like `stroke(_:)`'s; `size` mm, `gap` mm apart) set out in rows across `region` at `angle` degrees, every
    /// other row shifted by half a motif, keeping only those entirely inside. Each motif is one section; the rows are
    /// sewn back and forth (odd rows' motifs backwards) so each hop to the next motif is short.
    static func fill(in region: [[Point]], motif shape: [Point], size: Double, gap: Double, angle: Double, length: Double) throws -> [[Point]] {
        let turned = region.map { $0.map { AreaGeometry.rotate($0, degrees: -angle) } }, all = turned.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let pitch = size + gap, small = max(0.4, min(length, size / 5))
        let top = shape.map(\.y).max()!, bottom = shape.map(\.y).min()!, rowPitch = (top - bottom) * size + gap
        guard ((maxX - minX) / pitch) * ((maxY - minY) / rowPitch) <= 40_000 else { throw DesignError.invalid("This motif fill has too many motifs. Make the motifs bigger.") }
        var sections: [[Point]] = []
        var row = 0, y = minY - bottom * size
        while y + top * size <= maxY + 1e-9 {
            var motifs: [[Point]] = []
            var x = minX + (row % 2 == 1 ? pitch / 2 : 0)
            while x + size <= maxX + 1e-9 {
                let placed = shape.map { Point(x + $0.x * size, y + $0.y * size) }
                if placed.allSatisfy({ AreaGeometry.contains($0, rings: turned) }) {
                    motifs.append(evenly(placed, length: small).map { AreaGeometry.rotate($0, degrees: angle) })
                }
                x += pitch
            }
            sections += row % 2 == 0 ? motifs : motifs.reversed().map { $0.reversed() }
            row += 1; y += rowPitch
        }
        return sections
    }

    /// Cross stitch fill: a square grid of `size` mm laid over `region`, and an X in every square entirely inside it.
    /// The X's are sewn as long diagonal lines through runs of neighbouring squares: first all the lines one way,
    /// then all the other way, back and forth so each line starts beside where the last ended. Each line is sewn
    /// forward, back and forward again (like bean stitch) for the weight of stranded floss. The grid is tried at
    /// four alignments, keeping the one that fits the most squares.
    static func crossStitch(in region: [[Point]], size: Double) throws -> [[Point]] {
        let all = region.flatMap { $0 }
        guard let left = all.map(\.x).min(), let right = all.map(\.x).max(), let low = all.map(\.y).min(), let high = all.map(\.y).max() else { return [] }
        let columns = Int(ceil((right - left) / size)) + 1, rows = Int(ceil((high - low) / size)) + 1
        guard columns * rows <= 250_000 else { throw DesignError.invalid("This cross stitch fill has too many squares. Make the squares bigger.") }
        func squares(_ x0: Double, _ y0: Double) -> Set<Int> {
            var inside = Set<Int>()
            for i in 0..<columns { for j in 0..<rows {
                let corners = [(0.0, 0.0), (1, 0), (1, 1), (0, 1), (0.5, 0.5)].map { Point(x0 + (Double(i) + $0.0) * size, y0 + (Double(j) + $0.1) * size) }
                if corners.allSatisfy({ AreaGeometry.contains($0, rings: region) }) { inside.insert(i * rows + j) }
            } }
            return inside
        }
        let tries = [(0.0, 0.0), (0.5, 0.0), (0.0, 0.5), (0.5, 0.5)].map { (x: left - $0.0 * size, y: low - $0.1 * size) }.map { ($0.x, $0.y, squares($0.x, $0.y)) }
        let (x0, y0, inside) = tries.max { $0.2.count < $1.2.count }!
        func corner(_ i: Int, _ j: Int) -> Point { Point(x0 + Double(i) * size, y0 + Double(j) * size) }
        // Diagonal lines through neighbouring squares: "/" runs go up-right, "\" runs go down-right.
        func lines(rising: Bool) -> [[Point]] {
            var result: [[Point]] = []
            let starts = rising ? (-(rows - 1)...(columns - 1)) : (0...(columns + rows - 2))
            for k in starts {
                var current: [Point] = []
                for i in 0..<columns {
                    let j = rising ? i - k : k - i
                    guard j >= 0, j < rows, inside.contains(i * rows + j) else { if current.count > 1 { result.append(current) }; current = []; continue }
                    if current.isEmpty { current = [rising ? corner(i, j) : corner(i, j + 1)] }
                    current.append(rising ? corner(i + 1, j + 1) : corner(i + 1, j))
                }
                if current.count > 1 { result.append(current) }
            }
            return result
        }
        var sections: [[Point]] = []
        for rising in [true, false] {
            var family = lines(rising: rising)
            // Back and forth: every other line is sewn the other way, so each starts beside where the last ended.
            family = family.enumerated().map { $0.offset % 2 == 0 ? $0.element : $0.element.reversed() }
            // The second set starts from whichever end lies nearer where the first set finished.
            if let needle = sections.last?.last, let first = family.first?.first, let last = family.last?.last, last.distance(to: needle) < first.distance(to: needle) {
                family = family.reversed().map { $0.reversed() }
            }
            sections += try family.map { try RunningEngine.repeated($0, passes: 3) }
        }
        return sections
    }

    /// `path` as stitches of about `length` mm: each stretch between sharp corners (turns over 30°) is split into
    /// equal stitches, so corners stay exactly where they are and curves are followed closely.
    static func evenly(_ path: [Point], length: Double) -> [Point] {
        guard path.count >= 2 else { return path }
        func turn(_ i: Int) -> Double {
            let u = path[i] - path[i - 1], v = path[i + 1] - path[i]
            return abs(atan2(AreaGeometry.cross(u, v), u.x * v.x + u.y * v.y))
        }
        let corners = [0] + path.indices.dropFirst().dropLast().filter { path[$0].distance(to: path[$0 - 1]) > 1e-9 && path[$0 + 1].distance(to: path[$0]) > 1e-9 && turn($0) > 30 * .pi / 180 } + [path.count - 1]
        var result = [path[0]]
        for (a, b) in zip(corners, corners.dropFirst()) {
            let stretch = RunningStyles.Measured(Array(path[a...b]))
            guard stretch.total > 1e-9 else { continue }
            let pieces = max(1, Int((stretch.total / length).rounded()))
            for i in 1...pieces { result.append(stretch.point(at: stretch.total * Double(i) / Double(pieces))) }
        }
        return result
    }
}
