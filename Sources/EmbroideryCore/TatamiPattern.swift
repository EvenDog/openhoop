// Tatami patterns: textures made by where the needle goes in. The thread lies in the same flat rows either way; what
// changes is where each row's needle holes start, as a short list repeated down the fill. Lines of holes then show as
// zigzags, waves, blocks or diagonals. Smooth (the default) is the classic tatami: each row a quarter stitch on.
import Foundation

public struct TatamiPattern: Identifiable, Hashable, Sendable {
    /// Saved in the design (DigitizingSettings.tatamiPattern), so never change one once it's out.
    public let id: String
    public let name: String
    /// A few words about it, for the Pattern menu.
    public let tagline: String
    /// Where each row's needle holes start, as a fraction of the stitch length, row after row; the list repeats.
    /// Empty: each row starts somewhere different, at random (but the same every time the fill is worked out).
    public let rows: [Double]

    /// Where row `row`'s holes start (0 up to 1, a fraction of the stitch length). Rows count from the first one sewn.
    public func offset(row: Int) -> Double {
        guard !rows.isEmpty else {
            // A fixed scramble of the row number (a hash), so "random" comes out the same every time.
            var x = UInt64(row) &* 0x9E37_79B9_7F4A_7C15
            x ^= x >> 29; x = x &* 0xBF58_476D_1CE4_E5B9; x ^= x >> 32
            return Double(x % 8) / 8
        }
        return rows[row % rows.count]
    }

    /// The pattern a fill's settings name; Smooth when they name none (or one this version doesn't know).
    public static func of(_ settings: DigitizingSettings) -> TatamiPattern { settings.tatamiPattern.flatMap(named) ?? smooth }
    public static func named(_ id: String) -> TatamiPattern? { library.first { $0.id == id } }

    /// Starts in eighths of a stitch (0 to 7).
    private static func eighths(_ slots: [Int]) -> [Double] { slots.map { Double($0) / 8 } }
    /// Starts in sixteenths of a stitch (0 to 15), for the patterns that curve or wander in smaller steps.
    private static func sixteenths(_ slots: [Int]) -> [Double] { slots.map { Double($0) / 16 } }
    /// One smooth wave over `rows` rows, rising from 0 to `height` (a fraction of the stitch) and back, in sixteenths.
    private static func wave(rows: Int, height: Double) -> [Double] {
        (0..<rows).map { row in (height / 2 * (1 - cos(Double(row) / Double(rows) * 2 * .pi)) * 16).rounded() / 16 }
    }

    public static let smooth = TatamiPattern(id: "smooth", name: "Smooth", tagline: "Even, fine diagonals: the classic tatami.", rows: eighths([0, 2, 4, 6]))
    /// Every pattern, in the order the menu shows them.
    public static let library: [TatamiPattern] = [
        smooth,
        TatamiPattern(id: "steep", name: "Steep", tagline: "Diagonals of holes that climb steeply.", rows: eighths([0, 1, 2, 3, 4, 5, 6, 7])),
        TatamiPattern(id: "shallow", name: "Shallow", tagline: "Long, gently sloping diagonals.", rows: eighths([0, 3, 6, 1, 4, 7, 2, 5])),
        TatamiPattern(id: "reverse", name: "Reverse", tagline: "Smooth, with its diagonals leaning the other way.", rows: eighths([0, 6, 4, 2])),
        TatamiPattern(id: "thirds", name: "Thirds", tagline: "Each row a third of a stitch on.", rows: [0, 1.0 / 3, 2.0 / 3]),
        TatamiPattern(id: "fifths", name: "Fifths", tagline: "A spread-out diagonal, hard to spot.", rows: [0, 0.4, 0.8, 0.2, 0.6]),
        TatamiPattern(id: "ribbed", name: "Ribbed", tagline: "Holes in line row after row: deep grooves.", rows: [0]),
        TatamiPattern(id: "fineRibs", name: "Fine ribs", tagline: "Light grooves, half a stitch apart.", rows: [0, 0.5]),
        TatamiPattern(id: "zigzag", name: "Zigzag", tagline: "Lines of holes that zigzag across.", rows: eighths([0, 1, 2, 3, 3, 2, 1, 0])),
        TatamiPattern(id: "smallZigzag", name: "Small zigzag", tagline: "A tight, quick zigzag.", rows: eighths([0, 1, 2, 1])),
        TatamiPattern(id: "bigZigzag", name: "Big zigzag", tagline: "A wide zigzag, the whole stitch across.", rows: eighths([0, 1, 2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 3, 2, 1, 0])),
        TatamiPattern(id: "tallZigzag", name: "Tall zigzag", tagline: "A zigzag stretched over more rows.", rows: eighths([0, 0, 1, 1, 2, 2, 3, 3, 3, 3, 2, 2, 1, 1, 0, 0])),
        TatamiPattern(id: "wave", name: "Wave", tagline: "Lines of holes that ripple.", rows: wave(rows: 16, height: 7.0 / 8)),
        TatamiPattern(id: "gentleWave", name: "Gentle wave", tagline: "A long, low ripple.", rows: wave(rows: 24, height: 4.0 / 8)),
        TatamiPattern(id: "bigWave", name: "Big wave", tagline: "A tall, slow wave.", rows: wave(rows: 32, height: 15.0 / 16)),
        TatamiPattern(id: "ripple", name: "Ripple", tagline: "Short, rounded ripples.", rows: eighths([0, 1, 3, 4, 3, 1])),
        TatamiPattern(id: "herringbone", name: "Herringbone", tagline: "Bands of diagonals leaning in turn.", rows: eighths([0, 2, 4, 6, 0, 2, 4, 6, 6, 4, 2, 0, 6, 4, 2, 0])),
        TatamiPattern(id: "wideHerringbone", name: "Wide herringbone", tagline: "Herringbone in broader bands.", rows: eighths([0, 2, 4, 6, 0, 2, 4, 6, 0, 2, 4, 6, 0, 2, 4, 6, 6, 4, 2, 0, 6, 4, 2, 0, 6, 4, 2, 0, 6, 4, 2, 0])),
        TatamiPattern(id: "chevron", name: "Chevron", tagline: "Stacked V shapes.", rows: eighths([0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 4, 3, 2, 1, 0, 4, 3, 2, 1, 0])),
        TatamiPattern(id: "blocks", name: "Blocks", tagline: "Checks of four rows each.", rows: eighths([0, 0, 0, 0, 4, 4, 4, 4])),
        TatamiPattern(id: "bricks", name: "Bricks", tagline: "Small, brick-like checks.", rows: eighths([0, 0, 4, 4])),
        TatamiPattern(id: "largeBlocks", name: "Large blocks", tagline: "Bold checks of eight rows.", rows: eighths([0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 4, 4, 4])),
        TatamiPattern(id: "steps", name: "Steps", tagline: "A diagonal in short steps.", rows: eighths([0, 0, 2, 2, 4, 4, 6, 6])),
        TatamiPattern(id: "tallSteps", name: "Tall steps", tagline: "A diagonal in taller steps.", rows: eighths([0, 0, 0, 2, 2, 2, 4, 4, 4, 6, 6, 6])),
        TatamiPattern(id: "broadSteps", name: "Broad steps", tagline: "A steep staircase of holes.", rows: eighths([0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7])),
        TatamiPattern(id: "scattered", name: "Scattered", tagline: "Holes at random: no lines at all.", rows: []),
        // Added in file version 20 (see addedInVersionTwenty).
        TatamiPattern(id: "steepReverse", name: "Steep reverse", tagline: "Steep diagonals leaning the other way.", rows: eighths([0, 7, 6, 5, 4, 3, 2, 1])),
        // Short runs of Steep, each starting somewhere else.
        TatamiPattern(id: "rain", name: "Rain", tagline: "Short slanting dashes, scattered.", rows: eighths([0, 1, 2, 3, 5, 6, 7, 0, 2, 3, 4, 5, 7, 0, 1, 2, 3, 4, 5, 6, 6, 7, 0, 1, 1, 2, 3, 4, 4, 5, 6, 7])),
        // A diagonal with a curve added on: it climbs, levels out, then climbs again.
        TatamiPattern(id: "hills", name: "Hills", tagline: "Diagonals that rise and level out.", rows: sixteenths([0, 2, 4, 6, 7, 8, 8, 8, 8, 8, 8, 8, 9, 10, 12, 14])),
        TatamiPattern(id: "hillsReversed", name: "Hills reversed", tagline: "Hills leaning the other way.", rows: sixteenths([0, 14, 12, 10, 9, 8, 8, 8, 8, 8, 8, 8, 7, 6, 4, 2])),
        TatamiPattern(id: "rollingHills", name: "Rolling hills", tagline: "Longer, gentler hills.", rows: sixteenths([0, 1, 2, 4, 5, 5, 6, 7, 7, 8, 8, 8, 8, 8, 8, 8, 9, 9, 10, 11, 11, 12, 14, 15])),
        // Two waves added together, one twice as quick as the other.
        TatamiPattern(id: "sCurves", name: "S-curves", tagline: "Lines that bend one way, then the other.", rows: sixteenths([0, 3, 5, 6, 6, 5, 3, 2, 1, 0, 0, 0, 15, 14, 13, 11, 10, 10, 11, 13])),
        // Half a wave, repeated: round on one side, pointed where the arches meet.
        TatamiPattern(id: "arches", name: "Arches", tagline: "Rows of low, rounded arches.", rows: sixteenths([0, 2, 4, 6, 7, 8, 8, 8, 7, 6, 4, 2])),
        TatamiPattern(id: "feather", name: "Feather", tagline: "Curved herringbone: arcs leaning in turn.", rows: sixteenths([0, 2, 4, 6, 6, 6, 4, 2, 0, 14, 12, 10, 10, 10, 12, 14])),
        TatamiPattern(id: "sawtooth", name: "Sawtooth", tagline: "A slow climb, then a quick drop.", rows: sixteenths([0, 2, 4, 6, 8, 10, 12, 14, 10, 6, 2])),
        TatamiPattern(id: "sawtoothReversed", name: "Sawtooth reversed", tagline: "A quick climb, then a slow drop.", rows: sixteenths([0, 4, 8, 12, 14, 12, 10, 8, 6, 4, 2])),
        TatamiPattern(id: "lightning", name: "Lightning", tagline: "A zigzag with one long and one short arm.", rows: eighths([0, 1, 2, 3, 4, 5, 3, 1])),
        TatamiPattern(id: "doubleZigzag", name: "Double zigzag", tagline: "A zigzag with a small zigzag on it.", rows: eighths([0, 1, 0, 1, 2, 3, 2, 3, 4, 5, 4, 5, 4, 3, 4, 3, 2, 1, 2, 1])),
        TatamiPattern(id: "arrows", name: "Arrows", tagline: "Pointed V shapes with straight runs between.", rows: eighths([0, 1, 2, 3, 4, 3, 2, 1, 0, 0, 0, 0])),
        TatamiPattern(id: "bands", name: "Bands", tagline: "Smooth bands between grooved ones.", rows: eighths([0, 0, 0, 0, 0, 2, 4, 6, 0, 2, 4, 6])),
        TatamiPattern(id: "basket", name: "Basket", tagline: "Checks of grooves and diagonals.", rows: eighths([0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 4, 6, 0, 2, 4, 6])),
        // The last three wander: each row's start moves a little from the one before, picked once at random and fixed here.
        TatamiPattern(id: "woodGrain", name: "Wood grain", tagline: "Wandering lines, like grain in wood.", rows: sixteenths([14, 14, 12, 12, 14, 14, 14, 14, 14, 14, 14, 0, 0, 0, 0, 0, 0, 0, 0, 14, 12, 14, 0, 0, 0, 14, 0, 0, 0, 0, 0, 0, 0, 0, 14, 0, 2, 0, 14, 12, 14, 14, 12, 12, 12, 12, 12, 10])),
        TatamiPattern(id: "bark", name: "Bark", tagline: "Rougher wandering lines.", rows: sixteenths([15, 14, 14, 1, 1, 4, 7, 7, 7, 4, 3, 0, 1, 2, 5, 5, 8, 8, 7, 10, 7, 6, 9, 6, 3, 2, 3, 2, 1, 2, 5, 5, 4, 7, 8, 11, 14, 14, 13, 0])),
        TatamiPattern(id: "flames", name: "Flames", tagline: "Lines that wander and climb.", rows: sixteenths([1, 3, 2, 2, 3, 5, 6, 8, 7, 6, 6, 7, 7, 8, 9, 11, 12, 14, 15, 15, 0, 0, 15, 0, 1, 3, 5, 6, 7, 8, 7, 6, 6, 7, 6, 7, 7, 7, 6, 5])),
    ]

    /// The patterns added in file version 20. A design using one is saved as version 20, so older versions of the
    /// app, which don't know these names, say the file needs a newer OpenHoop instead of calling it damaged.
    public static let addedInVersionTwenty: Set<String> = [
        "steepReverse", "rain", "hills", "hillsReversed", "rollingHills", "sCurves", "arches", "feather", "sawtooth",
        "sawtoothReversed", "lightning", "doubleZigzag", "arrows", "bands", "basket", "woodGrain", "bark", "flames",
    ]
}
