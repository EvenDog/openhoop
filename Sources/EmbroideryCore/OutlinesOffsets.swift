// Outlines & Offsets: new outlines around a closed shape. One is sewn right on its edge, and up to two more are a
// set distance away from it: outside the shape, or inside it for a distance below zero. They take any line stitch
// and are ordinary closed outlines afterwards, to recolor, reshape or delete like any other object.
import Foundation

/// What Outlines & Offsets makes: which outlines, and the stitch they sew with.
public struct OutlineOptions: Equatable, Sendable {
    /// An outline sewn right on the shape's edge.
    public var edge = true
    /// Two offsets, each a distance in mm from the edge (outside the shape, or inside it below zero), or nil when off.
    public var offsets: [Double?] = [3, nil]
    public var stitch = OpenShapeStitch.running
    /// A satin outline's width in mm.
    public var satinWidth = SatinLine.defaultWidth
    /// Offsets get pointed corners like the shape's own (very narrow ones are flattened); off, they're rounded.
    public var sharpCorners = true
    /// Outline the shape's holes too, not only its outside edge.
    public var holes = false
    public init() {}
    /// True when at least one outline is switched on.
    public var makesSomething: Bool { edge || offsets.contains { $0 != nil } }
}

public struct OutlinesResult: Sendable {
    public var objects: [RunObject]
    public var warnings: [String]
}

public enum OutlinesOffsets {
    /// How far an offset can be from the edge, in mm.
    public static let distances = -100.0...100.0
    /// How far (mm) an offset's straight nodes may stray from the exact offset curve once spare ones are removed.
    static let tolerance = 0.1

    /// The outlines `options` asks for around `object`, in `color`, in sewing order: the edge outline, then each
    /// offset, each with its outside ring before its holes. Offsets always keep clear of the shape's holes; with
    /// `holes` on, the rings around them are kept too. Offset corners are pointed or rounded as chosen. An outline that doesn't fit is left out with a warning.
    public static func around(_ object: RunObject, options: OutlineOptions, color: ThreadColor) throws -> OutlinesResult {
        guard SatinBorder.canBorder(object) else { throw DesignError.invalid("‘\(object.name)’ isn't a closed shape. Outlines go around fills and closed outlines.") }
        var result = OutlinesResult(objects: [], warnings: [])
        /// Adds a closed outline along `nodes` with the chosen stitch, or a warning if a satin that wide won't fit.
        func add(_ nodes: [PathNode], name: String) {
            do { result.objects += try ShapeStitching.closedShape(nodes, fill: nil, outline: options.stitch, satinWidth: options.satinWidth, name: name, color: color) }
            catch { result.warnings.append("‘\(name)’ was left out: \(error.localizedDescription)") }
        }
        if options.edge {
            add(object.nodes, name: "\(object.name) outline")
            if options.holes { for hole in object.holes ?? [] { add(hole, name: "\(object.name) hole outline") } }
        }
        let area = ([object.nodes] + (object.holes ?? [])).map { AreaGeometry.ring($0) }
        for (index, distance) in options.offsets.enumerated() {
            guard let distance else { continue }
            let name = "\(object.name) offset \(index + 1)"
            let rings = try AreaGeometry.offset(area, by: distance, sharp: options.sharpCorners)
            // A ring inside another ring goes round a hole.
            let outside = rings.filter { ring in !rings.contains { $0 != ring && AreaGeometry.contains(ring[0], rings: [$0]) } }
            guard !outside.isEmpty else {
                result.warnings.append("‘\(object.name)’ is too small for an offset \(abs(distance).formatted()) mm inside it, so offset \(index + 1) was left out.")
                continue
            }
            for ring in outside + (options.holes ? rings.filter { !outside.contains($0) } : []) {
                // The offset comes back as many short straight edges; drop the ones that barely change its shape.
                add(Design.reduced([ring.map { PathNode($0) }], closed: true, tolerance: tolerance)[0], name: name)
            }
        }
        return result
    }
}
