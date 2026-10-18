// The density map: where a stitch plan lays too much thread, measured in 1 mm squares, so heavy and over-dense spots
// show on the canvas before they're sewn (and pucker the fabric, break thread or bend the needle).
import Foundation

public enum DensityMap {
    /// How crowded a 1 mm square is.
    public enum Level: Sendable { case heavy, tooDense }
    /// One "layer" is the thread a normal fill lays: rows 0.2 mm apart (Row spacing 0.40, measured across two rows), so
    /// 5 mm of thread per mm². A satin is about 1 layer; two satins overlapping where a letter's strokes join, about 2.
    static let layerThread = 1 / 0.2
    /// Over this many layers a square is heavy (shown yellow): a little over two, so the corner of an ordinary fill,
    /// where its rows, underlay and ties meet, isn't flagged…
    public static let heavyLayers = 2.2
    /// …and over this many, too dense: a stiff, "bulletproof" patch (shown red).
    public static let tooDenseLayers = 3.0
    /// Needle holes are counted in squares this size (mm); this many in one is a pile-up that can cut the fabric (red).
    /// (Along a fill's edge each square already has a row end or two, and its starting corner a tie as well.)
    static let holeCell = 0.25, holePileUp = 6

    /// The crowded 1 mm squares of `plan`, by their lower left corner (in mm), and how crowded each is. Squares
    /// with normal density aren't listed.
    public static func cells(_ plan: StitchPlan) -> [(corner: Point, level: Level)] {
        var thread: [Cell: Double] = [:], holes: [Cell: Int] = [:]
        var previous: Point?
        for command in plan.commands {
            switch command.op {
            case .stitch:
                holes[Cell(command.point, size: holeCell), default: 0] += 1
                if let previous {
                    // Lay the stitch's thread into the squares it crosses, a tenth of a millimetre at a time.
                    let length = previous.distance(to: command.point), pieces = max(1, Int(ceil(length / 0.1)))
                    for piece in 0..<pieces {
                        let t = (Double(piece) + 0.5) / Double(pieces)
                        thread[Cell(previous + (command.point - previous) * t, size: 1), default: 0] += length / Double(pieces)
                    }
                }
                previous = command.point
            default: previous = nil   // jumps and trims lay no thread
            }
        }
        var levels: [Cell: Level] = [:]
        for (cell, length) in thread {
            let layers = length / layerThread
            if layers > tooDenseLayers { levels[cell] = .tooDense } else if layers > heavyLayers { levels[cell] = .heavy }
        }
        // A needle-hole pile-up makes its 1 mm square too dense, however little thread it has.
        for (cell, count) in holes where count >= holePileUp {
            let square = Cell(x: Int((Double(cell.x) * holeCell).rounded(.down)), y: Int((Double(cell.y) * holeCell).rounded(.down)))
            levels[square] = .tooDense
        }
        return levels.map { (Point(Double($0.key.x), Double($0.key.y)), $0.value) }
    }

    /// A square on a grid of `size` mm squares.
    struct Cell: Hashable {
        let x: Int, y: Int
        init(x: Int, y: Int) { self.x = x; self.y = y }
        init(_ p: Point, size: Double) { x = Int((p.x / size).rounded(.down)); y = Int((p.y / size).rounded(.down)) }
    }
}
