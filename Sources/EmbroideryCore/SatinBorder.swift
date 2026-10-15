// Satin borders: a closed satin column of a chosen width running all the way around a shape's outside edge,
// centered on it, like the finished edge of a patch. Corners are rounded just enough for the satin to turn.
import Foundation

public struct SatinBorderResult: Sendable {
    public var object: RunObject
    public var warnings: [String]
}

public enum SatinBorder {
    public static let widths = 1.0...8.0

    /// True for shapes a border can go around: fills and closed outlines.
    public static func canBorder(_ object: RunObject) -> Bool {
        object.rawStitches == nil && (object.kind == .fill || ((object.kind == .run || object.kind == .vector) && object.closed))
    }

    /// A closed satin `width` mm wide, centered on the outside edge of `object` (holes are ignored), in `color`.
    /// Throws if the shape can't take a border that wide.
    public static func around(_ object: RunObject, width: Double, color: ThreadColor) throws -> SatinBorderResult {
        guard canBorder(object) else { throw DesignError.invalid("‘\(object.name)’ isn't a closed shape. Borders go around fills and closed outlines.") }
        guard widths.contains(width) else { throw DesignError.invalid("Border width must be between 1 and 8 mm.") }
        let edge = AreaGeometry.ring(object.nodes)
        let nodes = try edgePairs(around: edge, width: width, name: object.name)
        var border = RunObject(name: "\(object.name) border", nodes: nodes, color: color)
        border.closed = true
        border.digitizing = DigitizingSettings(kind: .satin)   // Auto underlay: picked from the width
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

    /// The border's edge pairs (outside rail first in each pair) along `edge` with its corners rounded.
    static func edgePairs(around edge: [Point], width: Double, name: String) throws -> [PathNode] {
        let half = width / 2
        // The centerline's corners must curve more gently than half the width, or the satin stitches on the inside
        // of a corner would cross each other. The extra 0.6 mm leaves room for pull compensation (0.2 mm by default),
        // which pushes the inside ends of the stitches further into the corner.
        var center = try rounded(edge, radius: half + 0.6, name: name, width: width)
        if AreaGeometry.area(center) < 0 { center.reverse() }   // counterclockwise, so the outward side is to the right
        // Edge pairs evenly spaced about every 0.8 mm. Uneven spacing could fold a rail back on itself where it is
        // pushed into a corner; even spacing can't, because every corner curves more gently than half the width.
        center = evenlySpaced(center, spacing: 0.8)
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
            let stretch = 1 / max(0.5, bisector.x * n1.x + bisector.y * n1.y)
            nodes.append(PathNode(point + bisector * (half * stretch)))   // left rail: outside
            nodes.append(PathNode(point - bisector * (half * stretch)))   // right rail: inside
        }
        return nodes
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
