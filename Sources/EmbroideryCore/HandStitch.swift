// Hand stitch: an effect for satins and running lines that makes machine stitches look sewn by hand. Each needle
// hole is nudged a little at random, along its stitch (uneven lengths) and across it (tilted stitches), and each
// stitch can be sewn over more than once, landing in new holes. A satin can have the effect on one edge only, with
// the other edge left crisp. The random numbers come from a fixed seed, so a design sews the same every time it's
// opened.
import Foundation

/// A satin's or running line's hand stitch settings (`DigitizingSettings.handStitch`; nil there means off).
public struct HandStitch: Codable, Hashable, Sendable {
    /// Roughness: how much stitch lengths vary (each step up to 4% of the stitch, either way) and how much stitches
    /// tilt (each step up to 2°, either way). 0 leaves them as they are.
    public var length = 2, angle = 2
    /// Mass: how many times each stitch is sewn, and how often (from 1, never, to 5, 40% of stitches) a stitch gets
    /// one pass more, or now and then one fewer.
    public var count = 1, random = 1
    /// Which of ten random versions of the same settings.
    public var variant = 1
    /// A satin's edge that gets the effect, as seen looking along the satin the way it sews; nil means both edges.
    /// The other edge stays crisp. Running lines ignore it.
    public var side: Side?
    public enum Side: String, Codable, Sendable { case left, right }
    public init() {}
    public static let levels = 0...5, counts = 1...3, randomLevels = 1...5, variants = 1...10
    var isValid: Bool {
        Self.levels.contains(length) && Self.levels.contains(angle) && Self.counts.contains(count) && Self.randomLevels.contains(random) && Self.variants.contains(variant)
    }

    /// The seed for an object's hand stitch: from its id, so moving or reshaping it keeps its look's character,
    /// and the same in every launch (Swift's own hashes change from launch to launch).
    static func seed(_ id: UUID) -> UInt64 {
        id.uuidString.utf8.reduce(0xcbf29ce484222325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }

    /// `stitches` with the effect on their top sections; underlay stays as it is. `crisp` gives, for a hole on the
    /// edge that stays crisp, which way that edge runs there (nil for other holes, or no `crisp`: none are).
    func applied(to stitches: ObjectStitches, seed: UInt64, crisp: ((Point) -> Point?)? = nil) -> ObjectStitches {
        var dice = FillStyles.Seeded(seed: seed &+ UInt64(variant) &* 0x9E3779B97F4A7C15)
        var result = stitches
        for i in result.sections.indices where !result.sections[i].underlay {
            result.sections[i].points = roughened(result.sections[i].points, &dice, crisp: crisp)
        }
        return result
    }

    /// For a satin sewn with `side` set: for a hole on the other, crisp edge, the way that edge runs beside it (a
    /// unit step); nil for holes elsewhere. A hole belongs to the edge it's nearer (compensation only ever pushes a
    /// hole out from its own edge). Left is worked out from the shape,
    /// not from the order its edge points were drawn in: walking along the column, on screen (where y goes up), the
    /// left edge is on the left.
    static func crispEdge(of satin: RunObject, rough side: Side) -> (Point) -> Point? {
        let nodes = satin.nodes
        let rails = [0, 1].map { first in
            RunningEngine.flatten(nodes.enumerated().filter { $0.offset % 2 == first }.map(\.element), closed: satin.closed).flatMap { $0 }
        }
        // Add up, pair by pair, whether the second edge lies to the left of the way the column goes.
        let pairs = stride(from: 0, to: nodes.count - 1, by: 2).map { (nodes[$0].point, nodes[$0 + 1].point) }
        var leftward = 0.0
        for k in 0..<pairs.count - 1 {
            let way = (pairs[k + 1].0 + pairs[k + 1].1) * 0.5 - (pairs[k].0 + pairs[k].1) * 0.5, across = pairs[k].1 - pairs[k].0
            leftward += way.x * across.y - way.y * across.x
        }
        let roughRail = (leftward > 0) == (side == .left) ? 1 : 0
        /// The piece of `rail` nearest `p`: how far it is, and its direction.
        func nearest(_ p: Point, _ rail: [Point]) -> (distance: Double, direction: Point) {
            var best = (distance: Double.infinity, direction: Point(1, 0))
            for (a, b) in zip(rail, rail.dropFirst() + (satin.closed ? Array(rail.prefix(1)) : [])) where a.distance(to: b) > 1e-9 {
                let d = p.distance(to: AreaGeometry.projection(p, a, b))
                if d < best.distance { best = (d, (b - a) * (1 / a.distance(to: b))) }
            }
            return best
        }
        return { p in
            let crisp = nearest(p, rails[1 - roughRail])
            return crisp.distance < nearest(p, rails[roughRail]).distance ? crisp.direction : nil
        }
    }

    /// One section's needle holes, nudged and sewn over. Its first and last holes stay put, so tie-ins and the
    /// moves to and from the next part still line up. Holes `crisp` picks out stay on their edge.
    func roughened(_ points: [Point], _ dice: inout FillStyles.Seeded, crisp: ((Point) -> Point?)? = nil) -> [Point] {
        guard points.count >= 3 else { return points }
        let lengthShare = Double(length) * 0.04, tilt = tan(Double(angle) * 2 * .pi / 180)
        let crispEdge = points.map { crisp?($0) }
        /// `point` moved at random along and across the stitch that arrives at it from `from`. Moving one end of a
        /// stitch sideways by half its length × tan(angle) tilts it by up to that angle. A hole on the crisp edge
        /// (`edge`, the way that edge runs) doesn't move; sewn over again (`again`), it lands beside itself, slid
        /// along the edge, never in the same hole.
        func nudged(_ point: Point, from: Point, edge: Point? = nil, again: Bool = false) -> Point {
            let stitch = from.distance(to: point)
            guard stitch > 0.01 else { return point }
            let along = (point - from) * (1 / stitch), across = Point(-along.y, along.x)
            // Both dice are rolled either way, so the rough edge comes out the same as with the effect on both edges.
            let alongDie = dice.unit() * 2 - 1, acrossDie = dice.unit() * 2 - 1
            guard let edge else { return point + along * (alongDie * lengthShare * stitch) + across * (acrossDie * tilt * stitch / 2) }
            guard again else { return point }
            // 0.1 to 0.2 mm either way: clear of the hole itself, and short of halfway to the next hole along the
            // edge (satin holes are usually 0.4 mm apart there).
            return point + edge * ((acrossDie < 0 ? -1 : 1) * (0.1 + abs(acrossDie) * 0.1))
        }
        // Each hole is nudged relative to the stitch that reaches it in the original, so nudges don't add up.
        let moved = [points[0]] + (1..<points.count - 1).map { nudged(points[$0], from: points[$0 - 1], edge: crispEdge[$0]) } + [points[points.count - 1]]
        guard count > 1 || random > 1 else { return moved }
        var sewn = [moved[0]]
        for k in 1..<moved.count {
            var passes = count
            if dice.unit() < Double(random - 1) * 0.1 { passes += passes > 1 && dice.below(3) == 0 ? -1 : 1 }
            sewn.append(moved[k])
            // Each extra pass goes back near the stitch's start and forward near its end, in new holes. The very last
            // forward lands exactly on the section's last hole.
            for pass in 1..<max(passes, 1) {
                let back = nudged(moved[k - 1], from: moved[k], edge: crispEdge[k - 1], again: true)
                let isLast = k == moved.count - 1 && pass == passes - 1
                sewn += [back, isLast ? moved[k] : nudged(moved[k], from: back, edge: crispEdge[k], again: true)]
            }
        }
        return sewn
    }
}
