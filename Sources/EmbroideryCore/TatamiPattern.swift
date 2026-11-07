// Tatami patterns: textures made by where the needle goes in. The thread lies in the same flat rows either way; what
// changes is where each row's needle holes start, as a short list repeated down the fill. Lines of holes then show as
// zigzags, waves, blocks or diagonals. Smooth (the default) is the classic tatami: each row a quarter stitch on.
// Picture patterns (Diamonds, Hearts…) also put a hole wherever a row crosses the outline of a small shape repeated
// across the fill, so lines of holes draw the shapes; the rest of each row is Smooth.
import Foundation

/// A picture pattern's shape: closed outlines in a tile 1 wide and `height` tall (a fraction of its width, y up),
/// repeated side by side and band above band across the fill. The tile turns with the rows (the fill angle).
public struct TatamiPicture: Hashable, Sendable {
    /// The outlines, x from 0 to 1 across the tile and y from 0 to 1 up it (scaled by the tile's width and height).
    public let outlines: [[Point]]
    /// How tall the tile is, as a fraction of its width.
    public let height: Double
    /// True: every other band of tiles is shifted half a tile sideways, like bricks.
    public let halfDrop: Bool
    /// The tile's width in mm when the fill doesn't set a Shape size.
    public let defaultSize: Double

    /// Where the row at height `y` crosses an outline, strictly between `lo` and `hi`, with tiles `width` wide.
    /// Crossings closer than `minimumGap` (where two edges meet at a tip) count once. Sorted left to right.
    func crossings(y: Double, from lo: Double, to hi: Double, width: Double, minimumGap: Double) -> [Double] {
        let tileHeight = width * height, band = floor(y / tileHeight), v = y / tileHeight - band
        let shift = halfDrop && band.truncatingRemainder(dividingBy: 2) != 0 ? 0.5 : 0
        // Where the row crosses the outlines within one tile (as a fraction of its width)…
        var inTile: [Double] = []
        for ring in outlines {
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                if (a.y <= v && b.y > v) || (b.y <= v && a.y > v) { inTile.append(a.x + (v - a.y) * (b.x - a.x) / (b.y - a.y)) }
            }
        }
        // …then in every tile along the row.
        var marks: [Double] = []
        for tile in Int(floor(lo / width)) - 1...Int(ceil(hi / width)) + 1 {
            for u in inTile {
                let x = (Double(tile) + shift + u) * width
                if x > lo && x < hi { marks.append(x) }
            }
        }
        var merged: [Double] = []
        for x in marks.sorted() where merged.last.map({ x - $0 >= minimumGap }) ?? true { merged.append(x) }
        return merged
    }
}

public struct TatamiPattern: Identifiable, Hashable, Sendable {
    /// Saved in the design (DigitizingSettings.tatamiPattern), so never change one once it's out.
    public let id: String
    public let name: String
    /// A few words about it, for the Pattern menu.
    public let tagline: String
    /// Where each row's needle holes start, as a fraction of the stitch length, row after row; the list repeats.
    /// Empty: each row starts somewhere different, at random (but the same every time the fill is worked out).
    public let rows: [Double]
    /// Picture patterns: the shape whose outlines the holes also draw. nil for the patterns made of row starts only.
    public var picture: TatamiPicture? = nil

    /// Where the needle goes into row `row` (at height `y` across the rows), strictly between the row's ends `lo` and
    /// `hi`, for stitches `length` long. Returns the holes left to right, without the ends themselves. A picture
    /// pattern's tiles are `size` wide (nil: its own starting size), in the same units as `y` and `length`.
    public func holes(row: Int, y: Double, from lo: Double, to hi: Double, length: Double, size: Double? = nil) -> [Double] {
        var holes: [Double] = []
        var x = floor(lo / length) * length + offset(row: row) * length
        while x <= lo + 0.00001 { x += length }
        while x < hi - 0.00001 { holes.append(x); x += length }
        guard let picture else { return holes }
        let marks = picture.crossings(y: y, from: lo + 0.00001, to: hi - 0.00001, width: size ?? picture.defaultSize, minimumGap: 0.15 * length)
        guard !marks.isEmpty else { return holes }
        // The outline holes, plus the row's own holes that aren't right next to one (so no stitch is tiny)…
        let kept = holes.filter { hole in !marks.contains { abs($0 - hole) < 0.35 * length } }
        // …and where dropping a hole left a gap longer than a stitch, holes spread evenly across it.
        var result: [Double] = [], previous = lo
        for next in (kept + marks).sorted() + [hi] {
            let pieces = Int(ceil((next - previous) / length - 0.00001))
            if pieces > 1 { for k in 1..<pieces { result.append(previous + (next - previous) * Double(k) / Double(pieces)) } }
            if next < hi { result.append(next) }
            previous = next
        }
        return result
    }

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
        // Added in file version 21 (see addedInVersionTwentyOne): picture patterns. Only edges that cross the rows
        // steeply show as lines of holes (an edge running along a row crosses it once at most), so the shapes are
        // tall and pointed rather than square.
        picture("diamonds", "Diamonds", "A grid of diamonds.", [diamond(0.05)], height: 1, halfDrop: false, size: 9),
        picture("smallDiamonds", "Small diamonds", "A finer grid of diamonds.", [diamond(0.05)], height: 1, halfDrop: false, size: 6),
        picture("argyle", "Argyle", "Tall diamonds, like a sweater.", [diamond(0.03)], height: 2, halfDrop: false, size: 6),
        picture("triangles", "Triangles", "Rows of triangles.", [[Point(0.5, 0.9), Point(0.92, 0.15), Point(0.08, 0.15)]], height: 1, halfDrop: true, size: 9),
        picture("hearts", "Hearts", "Little hearts.", [heart], height: 1, halfDrop: true, size: 9),
        picture("raindrops", "Raindrops", "Drops with a pointed top.", [raindrop], height: 1.2, halfDrop: true, size: 7.5),
        picture("circles", "Circles", "Rings in staggered rows.", [ellipse(0.4, 0.4)], height: 1, halfDrop: true, size: 9),
        picture("dots", "Dots", "Small rings, close together.", [ellipse(0.3, 0.3)], height: 1, halfDrop: true, size: 6),
        picture("tallOvals", "Tall ovals", "Upright ovals.", [ellipse(0.3, 0.45)], height: 1.4, halfDrop: true, size: 7.5),
        picture("almonds", "Almonds", "Pointed ovals, like leaves.", [almond], height: 1.4, halfDrop: true, size: 7.5),
        picture("lattice", "Lattice", "Large diamonds, each with a small one inside.",
                [diamond(0), [Point(0.5, 0.3), Point(0.7, 0.5), Point(0.5, 0.7), Point(0.3, 0.5)]], height: 1, halfDrop: false, size: 12),
        picture("kites", "Kites", "Diamonds with a long tail.", [[Point(0.5, 0.95), Point(0.85, 0.65), Point(0.5, 0.05), Point(0.15, 0.65)]], height: 1.4, halfDrop: true, size: 7.5),
    ]

    /// A picture pattern: Smooth's holes, plus holes along `outlines` (see TatamiPicture). `size`: starting width in mm.
    private static func picture(_ id: String, _ name: String, _ tagline: String, _ outlines: [[Point]], height: Double, halfDrop: Bool, size: Double) -> TatamiPattern {
        TatamiPattern(id: id, name: name, tagline: tagline, rows: smooth.rows,
                      picture: TatamiPicture(outlines: outlines, height: height, halfDrop: halfDrop, defaultSize: size))
    }
    /// A diamond filling the tile, `margin` in from each side.
    private static func diamond(_ margin: Double) -> [Point] {
        [Point(0.5, margin), Point(1 - margin, 0.5), Point(0.5, 1 - margin), Point(margin, 0.5)]
    }
    /// An oval in the middle of the tile, `rx` across and `ry` up from its center (fractions of the tile).
    private static func ellipse(_ rx: Double, _ ry: Double) -> [Point] {
        (0..<48).map { k in let t = 2 * .pi * Double(k) / 48; return Point(0.5 + rx * cos(t), 0.5 + ry * sin(t)) }
    }
    /// The classic heart curve, point down.
    private static let heart: [Point] = (0..<60).map { k in
        let t = 2 * .pi * Double(k) / 60
        let x = 16 * pow(sin(t), 3), y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        return Point(0.5 + x / 34 * 0.9, 0.48 + y / 34 * 0.9)
    }
    /// A drop: round at the bottom, narrowing to a point at the top.
    private static let raindrop: [Point] = (0..<48).map { k in
        let t = 2 * .pi * Double(k) / 48
        return Point(0.5 + 0.425 * sin(t) * pow(sin(t / 2), 1.2), 0.5 + 0.425 * cos(t))
    }
    /// Two arcs meeting in a point at the top and bottom.
    private static let almond: [Point] = {
        let right = (0...40).map { k -> Point in let t = Double(k) / 40; return Point(0.5 + 0.4 * sin(.pi * t), 0.96 - 0.92 * t) }
        return right + right.dropFirst().dropLast().reversed().map { Point(1 - $0.x, $0.y) }
    }()

    /// The patterns added in file version 20. A design using one is saved as version 20, so older versions of the
    /// app, which don't know these names, say the file needs a newer OpenHoop instead of calling it damaged.
    public static let addedInVersionTwenty: Set<String> = [
        "steepReverse", "rain", "hills", "hillsReversed", "rollingHills", "sCurves", "arches", "feather", "sawtooth",
        "sawtoothReversed", "lightning", "doubleZigzag", "arrows", "bands", "basket", "woodGrain", "bark", "flames",
    ]
    /// The picture patterns, added in file version 21 (a design using one is saved as version 21, as above).
    public static let addedInVersionTwentyOne: Set<String> = [
        "diamonds", "smallDiamonds", "argyle", "triangles", "hearts", "raindrops", "circles", "dots", "tallOvals", "almonds", "lattice", "kites",
    ]
}
