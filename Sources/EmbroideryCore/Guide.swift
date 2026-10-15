// Guide lines: straight lines across the canvas, dragged out of the rulers, to line things up against. They're
// saved with the design but never sewn. With Snap on, points close to a guide land exactly on it.
import Foundation

public struct Guide: Codable, Hashable, Sendable {
    /// True for an up-and-down line (at an x position), false for a side-to-side one (at a y position).
    public var vertical: Bool
    /// Where the line is, in mm: its x when vertical, its y when horizontal.
    public var position: Double
    public init(vertical: Bool, position: Double) { self.vertical = vertical; self.position = position }

    /// The most guides one design can hold.
    public static let limit = 100

    /// `point` moved onto the nearest guide within `reach` mm in each direction: a vertical guide sets its x, a
    /// horizontal one its y. Returns nil for a direction with no guide in reach, so the caller can snap it another way.
    public static func snap(_ point: Point, to guides: [Guide], reach: Double) -> (x: Double?, y: Double?) {
        func nearest(_ vertical: Bool, _ value: Double) -> Double? {
            guides.filter { $0.vertical == vertical && abs($0.position - value) <= reach }
                .min { abs($0.position - value) < abs($1.position - value) }?.position
        }
        return (nearest(true, point.x), nearest(false, point.y))
    }
}
