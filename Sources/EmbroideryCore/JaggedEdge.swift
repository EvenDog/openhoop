// Jagged edge: an effect for satin columns and satin fills that gives their edges a rough, uneven look, like fur,
// grass or feathers. Each needle hole on an edge moves a random distance along its own stitch: in (the stitch gets
// shorter) or out (it gets longer). A satin column can have it on one edge only. The random numbers come from a
// fixed seed, so a design sews the same every time it's opened.
import Foundation

/// A satin's jagged edge settings (`DigitizingSettings.jaggedEdge`; nil there means off).
public struct JaggedEdge: Codable, Hashable, Sendable {
    /// The most (mm) an edge hole moves; each moves a random part of it.
    public var amount = 1.0
    /// True when holes move out past the edge (longer stitches); false moves them in (shorter stitches).
    public var outward = false
    /// A satin column's edge that gets the effect, as seen looking along the column the way it sews; nil means both
    /// edges. Satin fills ignore it.
    public var side: HandStitch.Side?
    /// Which of ten random versions of the same settings.
    public var variant = 1
    public init() {}
    public static let amounts = 0.2...5.0, variants = 1...10
    var isValid: Bool { Self.amounts.contains(amount) && Self.variants.contains(variant) }

    /// `stitches` with the effect on their top sections; underlay stays as it is. `crisp` returns non-nil for a hole
    /// on an edge that stays crisp (HandStitch.crispEdge), or is nil when both edges are jagged.
    func applied(to stitches: ObjectStitches, seed: UInt64, crisp: ((Point) -> Point?)? = nil) -> ObjectStitches {
        // A different mix from hand stitch's, so an object with both effects doesn't roll the same numbers twice.
        var dice = FillStyles.Seeded(seed: (seed ^ 0x6A09E667F3BCC909) &+ UInt64(variant) &* 0x9E3779B97F4A7C15)
        var result = stitches
        for i in result.sections.indices where !result.sections[i].underlay {
            result.sections[i].points = jagged(result.sections[i].points, &dice, crisp: crisp)
        }
        return result
    }

    /// One section's needle holes with its edge holes moved. An edge hole is one where the needle turns back: satin
    /// stitches go across and come back, while a hole where the needle carries straight on is a split in the middle
    /// of a long stitch and stays put. The first and last holes stay put too, so tie-ins and the moves to and from
    /// the next part still line up.
    func jagged(_ points: [Point], _ dice: inout FillStyles.Seeded, crisp: ((Point) -> Point?)? = nil) -> [Point] {
        guard points.count >= 3 else { return points }
        var result = points
        for k in 1..<points.count - 1 {
            let incoming = points[k] - points[k - 1], outgoing = points[k + 1] - points[k]
            let length = points[k - 1].distance(to: points[k])
            // Every hole rolls the die, so a hole jags the same whatever is decided about the holes before it.
            let share = dice.unit()
            guard length > 0.01, incoming.x * outgoing.x + incoming.y * outgoing.y < 0, crisp?(points[k]) == nil else { continue }
            // Moving in never takes more than 40% off a stitch, so short stitches near a satin's ends don't vanish.
            let move = outward ? share * amount : -min(share * amount, 0.4 * length)
            result[k] = points[k] + incoming * (move / length)
        }
        return result
    }
}
