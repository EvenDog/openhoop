// A fill's stitch angle drawn as a line across the shape, as Edit Nodes (H) shows it: the line runs across the shape
// in the direction the rows run, through the middle unless it's been dragged somewhere else. Dragging an end turns
// the stitches while the other end stays put; dragging the line moves it (only where it's drawn).
import Foundation

public enum StitchAngleLine {
    /// How far (mm) the line reaches past the shape's edge, so its ends sit clear of the outline's nodes.
    static let overhang = 2.0

    /// True for fills whose rows follow the Angle setting: tatami and satin (unless stitch angle lines steer them),
    /// wave, gradient and motif.
    public static func applies(to object: RunObject) -> Bool {
        guard object.kind == .fill else { return false }
        switch object.settings.fillStyle ?? .tatami {
        case .tatami, .satin: return (object.settings.angleLines ?? []).isEmpty
        case .wave, .gradient, .motif: return true   // gradient rows and motif rows run at the angle too
        case .contour, .radial, .stipple, .crossStitch, .guided: return false
        }
    }

    /// True for fills whose Angle steers only their tatami underlay rows because their own rows don't follow it:
    /// contour, radial and guided fills, and tatami or satin steered by stitch angle lines. Properties shows each
    /// tatami underlay's angle for them as a direction of its own (from horizontal), not one from the fill's angle.
    public static func steersOnlyUnderlay(_ object: RunObject) -> Bool {
        object.kind == .fill && !applies(to: object) && object.settings.sewnUnderlays().contains { $0.style == .tatami }
            && ![.stipple, .motif, .crossStitch].contains(object.settings.fillStyle ?? .tatami)   // these sew without underlay
    }

    /// The line's two ends: through its center (`center(of:)`) at the fill's angle, as long as an end was last
    /// dragged out to, or else reaching just past the shape's edges on both sides. Nil for objects whose stitches
    /// don't follow an angle.
    public static func ends(of object: RunObject) -> (Point, Point)? {
        guard applies(to: object), let middle = center(of: object) else { return nil }
        let radians = object.settings.angle * .pi / 180, along = Point(cos(radians), sin(radians))
        if let length = object.settings.angleLineLength { return (middle - along * (length / 2), middle + along * (length / 2)) }
        // How far along the angle each outline point lies, measured from the center: the line spans from the lowest
        // to the highest, so it crosses the whole shape wherever its center is.
        let distances = object.outlinePaths.flatMap { $0 }.map { ($0.x - middle.x) * along.x + ($0.y - middle.y) * along.y }
        guard let low = distances.min(), let high = distances.max() else { return nil }
        return (middle + along * (low - overhang), middle + along * (high + overhang))
    }

    /// Where the line is centered (and turns around): where it was dragged to, or the middle of the shape.
    public static func center(of object: RunObject) -> Point? { object.settings.angleLineCenter ?? middle(of: object) }

    /// The shortest the line can be dragged (mm), so its two ends never sit on top of each other.
    static let shortest = 1.0

    /// Swings the line by one end: `anchor` (the other end) stays put and the dragged end goes to `point`. The fill's
    /// angle becomes the line's direction, to a tenth of a degree from 0 to 179.9 (a line points both ways, so 180°
    /// is the same as 0°), counted counterclockwise from pointing right as the Angle setting is; the line is then
    /// centered between the two ends, as long as they are apart. A point closer than `shortest` to the anchor
    /// changes nothing.
    public static func swing(_ object: inout RunObject, from anchor: Point, to point: Point) {
        guard anchor.distance(to: point) >= shortest else { return }
        let degrees = (atan2(point.y - anchor.y, point.x - anchor.x) * 180 / .pi * 10).rounded() / 10
        // `truncatingRemainder` is % for decimals; adding 180 first turns negative angles into their positive twin.
        object.digitizing?.angle = (degrees.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
        object.digitizing?.angleLineCenter = (anchor + point) * 0.5
        object.digitizing?.angleLineLength = anchor.distance(to: point)
    }

    /// The center of the shape's bounding box, or nil if it has no outline.
    static func middle(of object: RunObject) -> Point? {
        let points = object.outlinePaths.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return Point((minX + maxX) / 2, (minY + maxY) / 2)
    }
}
