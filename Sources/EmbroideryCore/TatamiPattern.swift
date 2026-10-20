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
    ]
}
