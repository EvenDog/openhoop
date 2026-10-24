// Satin borders: a closed satin column of a chosen width running all the way around a shape's outside edge,
// centered on it, like the finished edge of a patch. Corners are rounded just enough for the satin to turn.
import Foundation

public struct SatinBorderResult: Sendable {
    public var object: RunObject
    public var warnings: [String]
}

public enum SatinBorder {
    /// As wide as anyone wants (the top only keeps values sane); stitches over 12 mm get a warning when sewn.
    public static let widths = 1.0...1000.0

    /// True for shapes a border can go around: fills and closed outlines.
    public static func canBorder(_ object: RunObject) -> Bool {
        object.rawStitches == nil && (object.kind == .fill || ((object.kind == .run || object.kind == .vector) && object.closed))
    }

    /// A closed satin `width` mm wide, centered on the outside edge of `object` (holes are ignored), in `color`.
    /// Throws if the shape can't take a border that wide.
    public static func around(_ object: RunObject, width: Double, color: ThreadColor, smartCorners: Bool = true) throws -> SatinBorderResult {
        guard canBorder(object) else { throw DesignError.invalid("‘\(object.name)’ isn't a closed shape. Borders go around fills and closed outlines.") }
        guard widths.contains(width) else { throw DesignError.invalid("Border width must be between 1 and 1,000 mm.") }
        let edge = AreaGeometry.ring(object.nodes)
        let nodes = try edgePairs(around: edge, width: width, name: object.name, smartCorners: smartCorners)
        var border = RunObject(name: "\(object.name) border", nodes: nodes, color: color)
        border.closed = true
        border.digitizing = DigitizingSettings(kind: .satin)   // Auto underlay: picked from the width
        if smartCorners {
            border.digitizing?.smartCorners = true
            // Smart corners never make a border fail that sews with rounded ones: if it won't sew, it's rounded instead.
            if (try? AreaEngine.satin(border)) == nil { return try around(object, width: width, color: color, smartCorners: false) }
        }
        // Make sure it sews; this reports anything the satin engine rejects.
        do { _ = try AreaEngine.satin(border) } catch { throw DesignError.invalid("A \(width.formatted()) mm border doesn't fit around ‘\(object.name)’: \(error.localizedDescription) Try a narrower border.") }

        var warnings: [String] = []
        // Sharp points are rounded off by the centerline; count original corners left sticking out past the satin.
        let outside = AreaGeometry.ring(stride(from: 0, to: nodes.count, by: 2).map { nodes[$0] })
        if edge.contains(where: { !AreaGeometry.contains($0, rings: [outside]) }) {
            warnings.append("Sharp points of ‘\(object.name)’ stick out past the border. Round them off, or use a wider border.")
        }
        return SatinBorderResult(object: border, warnings: warnings)
    }

    /// The border's edge pairs (outside rail first in each pair) along `edge` with its corners rounded, or with
    /// `smartCorners`, its sharp corners kept sharp, each with a pair along its seam.
    static func edgePairs(around edge: [Point], width: Double, name: String, smartCorners: Bool = false) throws -> [PathNode] {
        let half = width / 2
        // The centerline's corners must curve more gently than half the width, or the satin stitches on the inside
        // of a corner would cross each other. The extra 0.6 mm leaves room for pull compensation (0.2 mm by default),
        // which pushes the inside ends of the stitches further into the corner. Past 8 mm it grows with the width:
        // with a fixed 0.6 mm, the inside ends of wide borders' stitches bunch up so tightly in the corners that they
        // fold over (from 9 mm on, borders were refused).
        let radius = half + max(0.6, width * 0.2 - 1)
        var center = try rounded(edge, radius: radius, name: name, width: width)
        if AreaGeometry.area(center) < 0 { center.reverse() }   // counterclockwise, so the outward side is to the right
        // Smart corners: the sharp corners go back in where rounding curved them, and the ring is spaced piece by piece
        // between them so they stay exactly where they are.
        let sharpCorners = SmartCorners.fittingCorners(edge, closed: true, half: half).map { i in
            (point: edge[i], opening: SmartCorners.opening(edge[(i + edge.count - 1) % edge.count], edge[i], edge[(i + 1) % edge.count]))
        }
        let sharp = smartCorners ? sharpened(center, at: sharpCorners, radius: radius) : (ring: center, corners: [])
        center = sharp.ring
        // Edge pairs evenly spaced about every 0.8 mm. Uneven spacing could fold a rail back on itself where it is
        // pushed into a corner; even spacing can't, because every corner curves more gently than half the width.
        if sharp.corners.isEmpty { center = evenlySpaced(center, spacing: 0.8) } else {
            let starts = sharp.corners.sorted()
            var spaced: [Point] = []
            for (k, from) in starts.enumerated() {
                let to = k + 1 < starts.count ? starts[k + 1] : starts[0] + center.count
                let piece = (from...to).map { center[$0 % center.count] }
                spaced += SatinLine.evenlySpaced(piece, spacing: 0.8).dropLast()
            }
            center = SmartCorners.clearedAroundCorners(spaced, closed: true, half: half)
        }
        let count = center.count
        guard count >= 3 else { throw DesignError.invalid("‘\(name)’ is too small for a border.") }
        var nodes: [PathNode] = []
        for i in 0..<count {
            let previous = center[(i + count - 1) % count], point = center[i], next = center[(i + 1) % count]
            // Outward normals of the edges before and after this point; the edge pair runs along their average,
            // stretched slightly at bends so both rails stay exactly half the width from the centerline.
            func outward(_ a: Point, _ b: Point) -> Point { let d = b - a, l = hypot(d.x, d.y); return Point(d.y / l, -d.x / l) }
            let n1 = outward(previous, point), n2 = outward(point, next)
            var bisector = n1 + n2
            let length = hypot(bisector.x, bisector.y)
            bisector = length > 1e-9 ? bisector * (1 / length) : n1
            // A smart corner's pair reaches right into the inside corner and out to the point.
            let sharp = smartCorners && SmartCorners.isSharp(previous, point, next)
            let stretch = 1 / max(sharp ? 0.05 : 0.5, bisector.x * n1.x + bisector.y * n1.y)
            nodes.append(PathNode(point + bisector * (half * stretch)))   // left rail: outside
            nodes.append(PathNode(point - bisector * (half * stretch)))   // right rail: inside
        }
        return nodes
    }

    /// The rounded ring with sharp corners put back: near each of `corners` (the shape's sharp corners, with the angle
    /// between their sides), the points the rounding curved are replaced by the corner itself. Returns the ring and
    /// where the corners now are in it.
    static func sharpened(_ ring: [Point], at corners: [(point: Point, opening: Double)], radius: Double) -> (ring: [Point], corners: [Int]) {
        var ring = ring
        for (corner, opening) in corners {
            guard let nearest = ring.indices.min(by: { ring[$0].distance(to: corner) < ring[$1].distance(to: corner) }) else { continue }
            // The arc rounding a corner ends where it touches the two sides, at most this far from the corner.
            let n = ring.count
            let reach = radius / tan(max(0.05, opening) / 2) + 0.3
            guard ring[nearest].distance(to: corner) <= reach else { continue }
            // The run of points round `nearest` within reach, replaced by the corner.
            var first = nearest, last = nearest
            while (last - first + 1) < n - 2, ring[(first + n - 1) % n].distance(to: corner) <= reach { first -= 1 }
            while (last - first + 1) < n - 2, ring[(last + 1) % n].distance(to: corner) <= reach { last += 1 }
            let keep = (last + 1...first + n - 1).map { ring[$0 % n] }
            ring = [corner] + keep
        }
        // Each corner's place, found again after all of them are in.
        let places = corners.compactMap { corner in ring.firstIndex { $0.distance(to: corner.point) < 1e-9 } }
        return (ring, places)
    }

    /// Points evenly spaced along a closed ring, about `spacing` apart (exactly equal steps all the way round).
    static func evenlySpaced(_ ring: [Point], spacing: Double) -> [Point] {
        let closed = ring + [ring[0]], perimeter = AreaGeometry.pathLength(closed)
        let count = max(12, Int(ceil(perimeter / spacing))), step = perimeter / Double(count)
        var result: [Point] = [], segment = 0, walked = 0.0   // `walked` is the distance to the start of `segment`
        for k in 0..<count {
            let target = Double(k) * step
            while segment < closed.count - 2 && walked + closed[segment].distance(to: closed[segment + 1]) < target {
                walked += closed[segment].distance(to: closed[segment + 1]); segment += 1
            }
            let a = closed[segment], b = closed[segment + 1], length = a.distance(to: b)
            result.append(length > 0 ? a + (b - a) * ((target - walked) / length) : a)
        }
        return result
    }

    /// The ring with every corner rounded to at least `radius`: growing then shrinking rounds the inward corners,
    /// shrinking then growing rounds the outward ones (the geometry library's offsets use round joins). Throws when
    /// parts of the shape are too narrow to survive, which would split the border.
    static func rounded(_ ring: [Point], radius: Double, name: String, width: Double) throws -> [Point] {
        var rings = try AreaGeometry.offset([ring], by: radius)
        rings = try AreaGeometry.offset(rings, by: -radius)
        rings = try AreaGeometry.offset(rings, by: -radius)
        rings = try AreaGeometry.offset(rings, by: radius)
        // Closing a narrow gap can leave a hole; only outer rings (those not inside another ring) matter here.
        let outer = rings.filter { ring in abs(AreaGeometry.area(ring)) > 0.01 && !rings.contains { $0 != ring && AreaGeometry.contains(ring[0], rings: [$0]) } }
        guard let largest = outer.max(by: { abs(AreaGeometry.area($0)) < abs(AreaGeometry.area($1)) }) else {
            throw DesignError.invalid("‘\(name)’ is too small or thin for a \(width.formatted()) mm border. Try a narrower border.")
        }
        guard outer.count == 1 else {
            throw DesignError.invalid("‘\(name)’ has a narrow neck that a \(width.formatted()) mm border can't follow. Try a narrower border.")
        }
        return largest
    }
}
