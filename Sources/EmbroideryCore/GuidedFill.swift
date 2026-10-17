// Guided fill: rows that bend to follow a guide line drawn over the shape. Each row is the guide pushed sideways by a
// whole number of row spacings (a "parallel curve"), so neighbouring rows stay one spacing apart everywhere. Away from
// the guide, rows on the outside of a bend grow rounder and rows on the inside close into a corner, the way the lines
// on a contour map do.
import Foundation

enum GuidedFill {
    /// The fill's rows as stitches about `length` long, from one side of the guide to the other.
    ///
    /// How: the guide is stretched straight on at both ends until it reaches a big box round everything, which cuts
    /// the box in two halves. Shrinking a half by a distance d leaves an edge exactly d from the guide (the box's own
    /// sides are too far away to matter), so the part of that edge inside the shape is a row. Rows are taken every
    /// `spacing` on both sides, plus the guide itself.
    static func rows(in region: [[Point]], guide rawGuide: [Point], spacing: Double, length: Double) throws -> [[Point]] {
        var guide: [Point] = []
        for point in rawGuide where guide.last.map({ $0.distance(to: point) > 0.01 }) ?? true { guide.append(point) }
        guard guide.count >= 2, AreaGeometry.pathLength(guide) >= 1 else { throw DesignError.invalid("The fill's guide line is too short. Draw a longer one.") }
        let all = region.flatMap { $0 } + guide
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        // The box is further from everything than anything in the shape is from the guide.
        let margin = Point(minX, minY).distance(to: Point(maxX, maxY)) + spacing + 5
        let box = (left: minX - margin, right: maxX + margin, bottom: minY - margin, top: maxY + margin)
        guard max(abs(box.left), abs(box.right), abs(box.bottom), abs(box.top)) < 9_000 else {
            throw DesignError.invalid("This guided fill is too big to work out. Make the shape or its guide line smaller.")
        }
        /// Where a ray from `p` going `direction` leaves the box.
        func exit(from p: Point, _ direction: Point) -> Point {
            var t = Double.infinity
            if direction.x > 1e-12 { t = min(t, (box.right - p.x) / direction.x) } else if direction.x < -1e-12 { t = min(t, (box.left - p.x) / direction.x) }
            if direction.y > 1e-12 { t = min(t, (box.top - p.y) / direction.y) } else if direction.y < -1e-12 { t = min(t, (box.bottom - p.y) / direction.y) }
            return p + direction * t
        }
        /// The way the guide heads off from its end `points[0]`: towards it from the point 1 mm along (or the last one).
        func outward(_ points: [Point]) -> Point {
            let end = points[0]
            let inner = points.dropFirst().first { $0.distance(to: end) >= 1 } ?? points[points.count - 1]
            let d = end - inner, size = d.distance(to: Point(0, 0))
            return d * (1 / size)
        }
        let line = [exit(from: guide[0], outward(guide))] + guide + [exit(from: guide[guide.count - 1], outward(guide.reversed()))]
        if crossesItself(line) {
            throw DesignError.invalid("The guide line crosses itself, or curls round so far that its ends would cross it. Draw a gentler guide line.")
        }
        // The rows at each distance from the guide (negative on its right), sides worked out separately.
        var levels: [(offset: Double, rows: [[Point]])] = [(0, clipped(line, to: region))]
        var total = 0
        for (sign, half) in [(1.0, halfBox(line, box, left: true)), (-1.0, halfBox(line, box, left: false))] {
            var steps = [[half]]
            for level in 1... {
                try Task.checkCancellation()
                let inset = try FillStyles.shrunk(&steps, by: Double(level) * spacing)
                if inset.isEmpty { break }
                let rows = inset.flatMap { closedClipped($0, to: region) }
                // No row, and none of the shape lies beyond this one: the shape is behind us, and every later row
                // (inside this one) misses it too.
                if rows.isEmpty && !region.joined().contains(where: { AreaGeometry.contains($0, rings: inset) }) { break }
                levels.append((sign * Double(level) * spacing, rows))
                total += rows.reduce(0) { $0 + $1.count }
                guard level < 5000, total <= 1_000_000 else { throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.") }
            }
        }
        // From the far left of the guide to the far right, back and forth, each row split into stitches staggered by
        // quarters of a stitch length from row to row so neighbouring rows don't line their needle holes up.
        let ordered = levels.sorted { $0.offset > $1.offset }.flatMap(\.rows).filter { AreaGeometry.pathLength($0) >= StitchEngine.smallestStitch }
        return ordered.enumerated().map { index, row in stitches(index % 2 == 0 ? row : row.reversed(), length: length, offset: Double(index % 4) / 4) }
    }

    /// The half of `box` on the guide's left (or right) side, as one ring: along the stretched guide `line`, whose
    /// ends lie on the box's edge, then round the box's edge back to the start.
    static func halfBox(_ line: [Point], _ box: (left: Double, right: Double, bottom: Double, top: Double), left: Bool) -> [Point] {
        // How far round the box's edge a point on it is, counterclockwise from the bottom left corner.
        let width = box.right - box.left, height = box.top - box.bottom
        func around(_ p: Point) -> Double {
            if abs(p.y - box.bottom) < 1e-6 { return p.x - box.left }
            if abs(p.x - box.right) < 1e-6 { return width + p.y - box.bottom }
            if abs(p.y - box.top) < 1e-6 { return width + height + box.right - p.x }
            return 2 * width + height + box.top - p.y
        }
        let corners = [(0.0, Point(box.left, box.bottom)), (width, Point(box.right, box.bottom)), (width + height, Point(box.right, box.top)), (2 * width + height, Point(box.left, box.top))]
        let perimeter = 2 * (width + height)
        // Counterclockwise round the box from the line's end back to its start keeps the guide's left side inside;
        // clockwise keeps its right side.
        let from = around(line[line.count - 1]), to = around(line[0])
        func distance(_ s: Double) -> Double {
            let d = left ? s - from : from - s
            return d < 0 ? d + perimeter : d
        }
        let span = distance(to)
        let passed = corners.filter { distance($0.0) > 1e-9 && distance($0.0) < span - 1e-9 }.sorted { distance($0.0) < distance($1.0) }.map(\.1)
        return line + passed
    }

    /// True when two pieces of `line` that aren't neighbours cross.
    static func crossesItself(_ line: [Point]) -> Bool {
        let n = line.count
        guard n >= 4 else { return false }
        for i in 0..<(n - 1) {
            let low = (min(line[i].x, line[i + 1].x), min(line[i].y, line[i + 1].y)), high = (max(line[i].x, line[i + 1].x), max(line[i].y, line[i + 1].y))
            for j in stride(from: i + 2, to: n - 1, by: 1) {
                let c = line[j], d = line[j + 1]
                if max(c.x, d.x) < low.0 || min(c.x, d.x) > high.0 || max(c.y, d.y) < low.1 || min(c.y, d.y) > high.1 { continue }
                if AreaGeometry.intersects(line[i], line[i + 1], c, d) { return true }
            }
        }
        return false
    }

    /// The parts of the open path `path` inside `region`, each as its own path.
    static func clipped(_ path: [Point], to region: [[Point]]) -> [[Point]] {
        let all = region.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        var pieces: [[Point]] = [], continuing = false
        for (a, b) in zip(path, path.dropFirst()) {
            // Pieces of the path nowhere near the shape are skipped without testing every edge.
            if max(a.x, b.x) < minX || min(a.x, b.x) > maxX || max(a.y, b.y) < minY || min(a.y, b.y) > maxY { continuing = false; continue }
            let inside = AreaGeometry.clippedSegment(a, b, rings: region)
            for (index, part) in inside.enumerated() {
                // A piece starting where the last one stopped carries it on.
                if index == 0, continuing, let last = pieces.last?.last, last.distance(to: part.0) < 1e-6 { pieces[pieces.count - 1].append(part.1) }
                else { pieces.append([part.0, part.1]) }
            }
            continuing = inside.last.map { $0.1.distance(to: b) < 1e-6 } ?? false
        }
        return pieces
    }
    /// The parts of the closed ring `ring` inside `region`. The ring is opened at its leftmost point, which lies out
    /// on the box's edge (outside the shape), so no part inside is cut in two.
    static func closedClipped(_ ring: [Point], to region: [[Point]]) -> [[Point]] {
        guard let start = ring.indices.min(by: { ring[$0].x < ring[$1].x }) else { return [] }
        return clipped(Array(ring[start...] + ring[...start]), to: region)
    }

    /// Stitches along `row` at most about `length` long, the needle points shifted along by `offset` of a stitch.
    /// Sharp bends in the row (where rows close into a corner) always get a needle point, so stitches don't cut them.
    static func stitches(_ row: [Point], length: Double, offset: Double) -> [Point] {
        var result = [row[0]], stretch = [row[0]]
        /// Needle points along the stretch so far, by distance along it, ending at its last point.
        func finish() {
            let total = AreaGeometry.pathLength(stretch)
            guard total > 0 else { return }
            var marks: [Double] = [], s = offset * length
            if s < 0.3 { s += length }
            while s < total - 0.3 { marks.append(s); s += length }
            var walked = 0.0, mark = 0
            for (a, b) in zip(stretch, stretch.dropFirst()) {
                let d = a.distance(to: b)
                guard d > 0 else { continue }
                while mark < marks.count, marks[mark] <= walked + d { result.append(a + (b - a) * ((marks[mark] - walked) / d)); mark += 1 }
                walked += d
            }
            result.append(stretch[stretch.count - 1])
        }
        for index in row.indices.dropFirst() {
            stretch.append(row[index])
            if index < row.count - 1 {
                let u = row[index] - row[index - 1], v = row[index + 1] - row[index]
                if abs(atan2(AreaGeometry.cross(u, v), u.x * v.x + u.y * v.y)) > 25 * .pi / 180 { finish(); stretch = [row[index]] }
            }
        }
        finish()
        return result
    }
}
