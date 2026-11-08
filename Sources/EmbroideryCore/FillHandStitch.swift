// Hand stitch for fills: an effect that makes a fill's machine-straight rows look sewn by hand. Each needle hole
// inside a row moves a little at random, along the row (uneven stitch lengths, holes no longer in tidy lines) and
// across it (stitches tilt and cross their neighbours). The ends of each row stay put, so the fill's outline stays
// crisp, and the underlay isn't touched. The random numbers come from a fixed seed, so a design sews the same every
// time it's opened. (Satins and running lines have their own hand stitch, HandStitch.swift.)
import Foundation

/// A fill's hand stitch settings (`DigitizingSettings.fillHandStitch`; nil there means off).
public struct FillHandStitch: Codable, Hashable, Sendable {
    /// How far the holes move.
    public var strength = Strength.medium
    /// Which of ten random versions of the same settings.
    public var variant = 1
    public init() {}
    public static let variants = 1...10
    var isValid: Bool { Self.variants.contains(variant) }

    public enum Strength: String, Codable, CaseIterable, Sendable {
        case light, medium, strong
        public var title: String { rawValue.capitalized }
        /// The share of Medium's movement.
        var scale: Double { switch self { case .light: return 0.5; case .medium: return 1; case .strong: return 1.6 } }
    }

    /// At Medium, the most a hole moves along its row (as a share of the stitch length) and across it (mm). Each moves
    /// a random part of these, either way.
    static let along = 0.25, across = 0.45

    /// `stitches` with the effect on their top sections; underlay stays as it is. `length` is the fill's stitch length.
    /// A hole that would land outside `region` (the fill's outline and holes) stays where it was.
    func applied(to stitches: ObjectStitches, seed: UInt64, length: Double, region: [[Point]]) -> ObjectStitches {
        // A different mix from the other effects', so an object never rolls the same numbers twice.
        var dice = FillStyles.Seeded(seed: (seed ^ 0xBB67AE8584CAA73B) &+ UInt64(variant) &* 0x9E3779B97F4A7C15)
        let alongMost = Self.along * length * strength.scale, acrossMost = Self.across * strength.scale
        var result = stitches
        for i in result.sections.indices where !result.sections[i].underlay {
            let points = result.sections[i].points
            guard points.count >= 3 else { continue }
            var moved = points
            for k in 1..<(points.count - 1) {
                let before = points[k] - points[k - 1], after = points[k + 1] - points[k]
                let a = hypot(before.x, before.y), b = hypot(after.x, after.y)
                // Only holes in the middle of a row: both stitches full-sized and carrying straight on. Where the
                // needle turns (the end of a row, a corner of travel), the hole stays.
                guard a >= 0.8, b >= 0.8, (before.x * after.x + before.y * after.y) / (a * b) >= 0.9 else { continue }
                let direction = (before + after) * (1 / (a + b)), size = hypot(direction.x, direction.y)
                let along = direction * (1 / size), across = Point(-along.y, along.x)
                let shift = along * ((dice.unit() * 2 - 1) * alongMost) + across * ((dice.unit() * 2 - 1) * acrossMost)
                let candidate = points[k] + shift
                if AreaGeometry.contains(candidate, rings: region) { moved[k] = candidate }
            }
            result.sections[i].points = moved
        }
        return result
    }
}
