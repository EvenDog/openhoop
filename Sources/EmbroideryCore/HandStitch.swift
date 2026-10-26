// Hand stitch: an effect for satins and running lines that makes machine stitches look sewn by hand. Each needle
// hole is nudged a little at random, along its stitch (uneven lengths) and across it (tilted stitches), and each
// stitch can be sewn over more than once, landing in new holes. The random numbers come from a fixed seed, so a
// design sews the same every time it's opened.
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

    /// `stitches` with the effect on their top sections; underlay stays as it is.
    func applied(to stitches: ObjectStitches, seed: UInt64) -> ObjectStitches {
        var dice = FillStyles.Seeded(seed: seed &+ UInt64(variant) &* 0x9E3779B97F4A7C15)
        var result = stitches
        for i in result.sections.indices where !result.sections[i].underlay {
            result.sections[i].points = roughened(result.sections[i].points, &dice)
        }
        return result
    }

    /// One section's needle holes, nudged and sewn over. Its first and last holes stay put, so tie-ins and the
    /// moves to and from the next part still line up.
    func roughened(_ points: [Point], _ dice: inout FillStyles.Seeded) -> [Point] {
        guard points.count >= 3 else { return points }
        let lengthShare = Double(length) * 0.04, tilt = tan(Double(angle) * 2 * .pi / 180)
        /// `point` moved at random along and across the stitch that arrives at it from `from`. Moving one end of a
        /// stitch sideways by half its length × tan(angle) tilts it by up to that angle.
        func nudged(_ point: Point, from: Point) -> Point {
            let stitch = from.distance(to: point)
            guard stitch > 0.01 else { return point }
            let along = (point - from) * (1 / stitch), across = Point(-along.y, along.x)
            let alongShift = (dice.unit() * 2 - 1) * lengthShare * stitch, acrossShift = (dice.unit() * 2 - 1) * tilt * stitch / 2
            return point + along * alongShift + across * acrossShift
        }
        // Each hole is nudged relative to the stitch that reaches it in the original, so nudges don't add up.
        let moved = [points[0]] + (1..<points.count - 1).map { nudged(points[$0], from: points[$0 - 1]) } + [points[points.count - 1]]
        guard count > 1 || random > 1 else { return moved }
        var sewn = [moved[0]]
        for k in 1..<moved.count {
            var passes = count
            if dice.unit() < Double(random - 1) * 0.1 { passes += passes > 1 && dice.below(3) == 0 ? -1 : 1 }
            sewn.append(moved[k])
            // Each extra pass goes back near the stitch's start and forward near its end, in new holes. The very last
            // forward lands exactly on the section's last hole.
            for pass in 1..<max(passes, 1) {
                let back = nudged(moved[k - 1], from: moved[k])
                let isLast = k == moved.count - 1 && pass == passes - 1
                sewn += [back, isLast ? moved[k] : nudged(moved[k], from: back)]
            }
        }
        return sewn
    }
}
