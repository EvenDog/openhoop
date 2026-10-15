// Test-only stitch quality checker: measures a compiled stitch plan for problems that show up at the machine
// (stitches too short or too long, needle holes piling up, thread building up into stiff patches) without needing
// a sew-out. StitchQualityTests runs it over sample designs, fonts and generated shapes and writes a report.
import Foundation
@testable import EmbroideryCore

struct StitchQuality {
    /// Stitches shorter than this tend to break thread or tangle under the fabric.
    static let tinyLength = 0.3
    /// A softer limit: most digitizing software removes stitches under about 0.5 mm.
    static let shortLength = 0.5
    /// Stitches longer than this can snag; satins and running stitches normally stay under it.
    static let snagLength = 7.0
    /// Most machines can't sew one stitch longer than this (PES/DST limit).
    static let machineLimit = 12.1
    /// Needle holes: penetrations are counted in squares this size (mm)…
    static let holeCell = 0.25
    /// …and a square with at least this many is a pile-up that can cut the fabric.
    static let holePileUp = 5
    /// Thread build-up is measured in squares this size (mm).
    static let densityCell = 1.0
    /// One "layer" is the thread a normal fill lays: rows 0.4 mm apart, so 2.5 mm of thread per mm². A satin crosses
    /// its column twice per spacing step, so a normal satin is about 2 layers, and two satins overlapping where a
    /// letter's strokes join (as font designers intend) about 4.
    static let layerThread = 1 / 0.4
    /// More layers than this in one square (three satins deep, or fills and satins piled on each other) makes a
    /// stiff, "bulletproof" patch.
    static let stiffLayers = 6.0

    /// What one problem kind counts, overall and by the object that sewed it.
    struct Tally {
        var count = 0
        var byObject: [String: Int] = [:]
        mutating func add(_ object: String) { count += 1; byObject[object, default: 0] += 1 }
    }

    var stitches = 0
    var zeroLength = Tally()   // a stitch on the same spot as the one before
    var tiny = Tally()         // under 0.3 mm (zero-length ones not included)
    var short = Tally()        // 0.3 to 0.5 mm
    var snag = Tally()         // over 7 mm
    var overLimit = Tally()    // over 12.1 mm
    var holePileUps = Tally()  // 0.25 mm squares with 5+ needle hits, by the object with most hits there
    var worstHole = 0          // the most needle hits in one square
    var stiffCells = Tally()   // 1 mm squares over 4 layers, by the object with most thread there
    var maxLayers = 0.0
    var jumps = 0
    var trims = 0
    var warnings: [String] = []

    /// Measures `plan`, naming objects from `design`.
    init(plan: StitchPlan, design: Design) {
        let names = Dictionary(design.objects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        func name(_ id: UUID?) -> String { id.flatMap { names[$0] } ?? "(no object)" }
        warnings = plan.warnings
        var holes: [Cell: [String: Int]] = [:]
        var thread: [Cell: [String: Double]] = [:]
        var previous: StitchCommand?   // the last needle penetration, while sewing continues without a jump or trim
        for command in plan.commands {
            switch command.op {
            case .stitch:
                stitches += 1
                let object = name(command.objectID)
                holes[Cell(command.point, size: Self.holeCell), default: [:]][object, default: 0] += 1
                if let previous {
                    let length = previous.point.distance(to: command.point)
                    if length < 0.000001 { zeroLength.add(object) }
                    else if length < Self.tinyLength { tiny.add(object) }
                    else if length < Self.shortLength { short.add(object) }
                    if length > Self.machineLimit { overLimit.add(object) } else if length > Self.snagLength { snag.add(object) }
                    // Lay the stitch's thread into the squares it crosses, a tenth of a millimetre at a time.
                    let pieces = max(1, Int(ceil(length / 0.1)))
                    for piece in 0..<pieces {
                        let t = (Double(piece) + 0.5) / Double(pieces)
                        thread[Cell(previous.point + (command.point - previous.point) * t, size: Self.densityCell), default: [:]][object, default: 0] += length / Double(pieces)
                    }
                }
                previous = command
            case .jump: jumps += 1; previous = nil
            case .trim: trims += 1; previous = nil
            default: previous = nil
            }
        }
        for (_, hits) in holes {
            let total = hits.values.reduce(0, +)
            worstHole = max(worstHole, total)
            if total >= Self.holePileUp { holePileUps.add(hits.max { $0.value < $1.value }!.key) }
        }
        let cellArea = Self.densityCell * Self.densityCell
        for (_, lengths) in thread {
            let layers = lengths.values.reduce(0, +) / cellArea / Self.layerThread
            maxLayers = max(maxLayers, layers)
            if layers > Self.stiffLayers { stiffCells.add(lengths.max { $0.value < $1.value }!.key) }
        }
    }

    /// A square on a grid of `size` mm squares.
    struct Cell: Hashable {
        let x: Int, y: Int
        init(_ p: Point, size: Double) { x = Int((p.x / size).rounded(.down)); y = Int((p.y / size).rounded(.down)) }
    }

    /// Problems per 1,000 stitches, so designs of different sizes compare fairly.
    func perThousand(_ tally: Tally) -> Double { stitches == 0 ? 0 : Double(tally.count) * 1000 / Double(stitches) }
}
