// Stitches that hold the fabric rather than decorate it: the basting box (long running stitches around
// the design, sewn first, that hold the fabric to the stabilizer) and laydown (a light open fill under the design
// that flattens the pile of towels and fleece so the stitches on top don't sink into it).
import Foundation

/// The choices for a laydown, as the Laydown dialog sets them.
public struct LaydownSettings: Equatable, Sendable {
    /// How far the laydown reaches past the edge of what it's under, in mm.
    public var offset = 1.5
    /// The gap between its rows, in mm: far wider than a normal fill, so it pins the pile down without covering it.
    public var spacing = 2.0
    /// The rows' direction, in degrees.
    public var angle = 45.0
    /// 1, or 2 for a second layer at right angles to the first (a light grid that pins the pile both ways).
    public var layers = 2
    /// The longest stitch along each row, in mm.
    public var stitchLength = 4.0
    public static let offsets = 0.0...10.0, spacings = 1.0...5.0, stitchLengths = 2.0...7.0
    public init() {}
}

extension Design {
    /// The basting box's ID in the stitches it sews (it isn't one of the design's objects, so it can't be selected).
    public static let bastingID = UUID(uuidString: "BA57B0C5-0000-4000-8000-000000000000")!
    /// The basting box's margins, in mm.
    public static let bastingMargins = 0.0...20.0
    /// The longest stitch along the basting box, in mm: long, so it's quick to sew and easy to pull out.
    public static let bastingStitch = 5.0

    /// The basting box this design sews first, or nil when it's off or nothing sews: a rectangle of running
    /// stitches `basting` mm outside everything that sews, in the first object's thread (so the machine doesn't
    /// stop to change thread), followed by a trim. It stays inside the hoop: on a rectangular hoop it's cut back to
    /// the hoop's edge; on an oval one the margin shrinks until the corners fit (if even none fits, the hoop check
    /// reports it).
    public var bastingBox: RunObject? {
        guard let margin = basting else { return nil }
        let sewn = objects.filter { $0.kind != .vector }
        guard let first = sewn.first, let box = bounds(of: Set(sewn.map(\.id))) else { return nil }
        func corners(_ m: Double) -> [Point] {
            [Point(box.min.x - m, box.min.y - m), Point(box.max.x + m, box.min.y - m), Point(box.max.x + m, box.max.y + m), Point(box.min.x - m, box.max.y + m)]
        }
        var points = corners(margin)
        if hoop.oval {
            // Try smaller margins, half a millimeter at a time.
            var m = margin
            while m > 0, !corners(m).allSatisfy({ hoop.contains($0) }) { m = max(0, m - 0.5) }
            points = corners(m)
        } else {
            let x = hoop.width / 2, y = hoop.height / 2
            points = points.map { Point(min(max($0.x, -x), x), min(max($0.y, -y), y)) }
        }
        var object = RunObject(name: "Basting box", nodes: points.map { PathNode($0) }, color: first.color)
        object.id = Self.bastingID; object.closed = true; object.stitchLength = Self.bastingStitch
        return object
    }

    /// Laydown: light open fills under the objects in `ids` (the whole design if `ids` is empty), reaching
    /// `settings.offset` mm past their edges, in `color`. Their outlines are joined, so the laydown covers the gaps
    /// inside and between them (the counter of an O, the space between close letters); parts too far apart get
    /// laydowns of their own. With two layers, each part gets a second fill at right angles. The fills are grouped
    /// and have no underlay or compensation. They're returned, not added (the dialog previews them first).
    public func laydown(under ids: Set<UUID>, settings: LaydownSettings, color: ThreadColor) throws -> [RunObject] {
        let covered = objects.filter { (ids.isEmpty || ids.contains($0.id)) && $0.kind != .vector }
        // Each object's outer edge, counterclockwise, so joining them adds up instead of cancelling out. Lines
        // (running stitches, imported stitches) count as a 1 mm wide band along them.
        var rings: [[Point]] = []
        for object in covered {
            if let area = object.areaRings { rings.append(Self.oriented([area[0]])[0]) }
            else { for path in object.outlinePaths where path.count >= 2 { rings += Self.band(path, halfWidth: 0.5) } }
        }
        guard !rings.isEmpty else { return [] }
        let joined = try AreaGeometry.svgRegions(rings, nonzero: true).map { $0[0] }   // outer edges only: no holes
        let grown = try AreaGeometry.offset(joined, by: settings.offset)
        let parts = try AreaGeometry.svgRegions(grown, nonzero: false).map { $0[0] }.sorted { abs(AreaGeometry.area($0)) > abs(AreaGeometry.area($1)) }
        let group = UUID()
        var made: [RunObject] = []
        for part in parts {
            let nodes = Self.cornerNodes(part)
            for layer in 0..<max(1, min(2, settings.layers)) {
                var fill = RunObject(name: "Laydown", nodes: nodes, color: color)
                fill.closed = true; fill.stitchLength = settings.stitchLength; fill.groupID = group
                var stitches = DigitizingSettings(kind: .fill)
                stitches.spacing = settings.spacing; stitches.expansion = 0; stitches.underlay = .none
                stitches.angle = Lettering.turned(settings.angle, by: Double(layer) * 90)
                fill.digitizing = stitches
                made.append(fill)
            }
        }
        if made.count > 1 { for i in made.indices { made[i].name = "Laydown \(i + 1)" } }
        return made
    }

    /// Adds `laydown` (from laydown(under:settings:color:)) so it sews before everything it lies under: before
    /// the first of the objects in `ids` (at the very start when `ids` is empty).
    public mutating func addLaydown(_ laydown: [RunObject], under ids: Set<UUID>) {
        let index = ids.isEmpty ? 0 : objects.firstIndex { ids.contains($0.id) } ?? 0
        objects.insert(contentsOf: laydown, at: index)
    }

    /// A band `halfWidth` mm to each side of an open path, as counterclockwise rectangles (one per segment, a
    /// little longer than it so they join up).
    static func band(_ path: [Point], halfWidth w: Double) -> [[Point]] {
        zip(path, path.dropFirst()).compactMap { a, b in
            let length = a.distance(to: b)
            guard length > 1e-6 else { return nil }
            let u = (b - a) * (w / length), n = Point(-u.y, u.x)   // along and across the segment, each w long
            return [a - u - n, b + u - n, b + u + n, a - u + n]
        }
    }
}
