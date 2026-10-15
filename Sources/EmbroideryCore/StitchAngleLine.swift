// A fill's stitch angle drawn as a line across the shape, as Edit Nodes (H) shows it: the line runs through the
// middle of the shape in the direction the rows run, and dragging an end turns the stitches.
import Foundation

public enum StitchAngleLine {
    /// How far (mm) the line reaches past the shape's edge, so its ends sit clear of the outline's nodes.
    static let overhang = 2.0

    /// True for fills whose rows follow the Angle setting: tatami (unless stitch angle lines steer it) and wave.
    public static func applies(to object: RunObject) -> Bool {
        guard object.kind == .fill else { return false }
        switch object.settings.fillStyle ?? .tatami {
        case .tatami: return (object.settings.angleLines ?? []).isEmpty
        case .wave: return true
        case .contour, .radial: return false
        }
    }

    /// The line's two ends: through the middle of the shape (the center of its bounding box) at the fill's angle,
    /// reaching just past its edges. Nil for objects whose stitches don't follow an angle.
    public static func ends(of object: RunObject) -> (Point, Point)? {
        guard applies(to: object), let middle = middle(of: object) else { return nil }
        let radians = object.settings.angle * .pi / 180, along = Point(cos(radians), sin(radians))
        // Half the line: the farthest any outline point reaches along the angle, measured from the middle.
        let reach = object.outlinePaths.flatMap { $0 }.map { abs(($0.x - middle.x) * along.x + ($0.y - middle.y) * along.y) }.max() ?? 0
        let half = along * (reach + overhang)
        return (middle - half, middle + half)
    }

    /// The angle, in whole degrees from 0 to 179, of a line from the middle of `object` toward `point` (a line points
    /// both ways, so 180° is the same as 0°). Counted counterclockwise from pointing right, as the fill's Angle is.
    public static func angle(of object: RunObject, toward point: Point) -> Double {
        guard let middle = middle(of: object), middle.distance(to: point) > 0.001 else { return object.settings.angle }
        let degrees = (atan2(point.y - middle.y, point.x - middle.x) * 180 / .pi).rounded()
        // `truncatingRemainder` is % for decimals; adding 180 first turns negative angles into their positive twin.
        return (degrees.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
    }

    /// The center of the shape's bounding box, or nil if it has no outline.
    static func middle(of object: RunObject) -> Point? {
        let points = object.outlinePaths.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return Point((minX + maxX) / 2, (minY + maxY) / 2)
    }
}
