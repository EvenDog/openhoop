// The sew-out test pack: thirteen designs for a 100 × 100 mm hoop that put the stitch settings worth checking on a real
// machine side by side (satin widths and compensation, the fill styles, small lettering, a monogram, travel and
// finishing, the line styles and stipple, and motifs, cross stitch, gradient and raised satin, then wide satin, Remove Overlaps and Outlines & Offsets,
// then moves and jumps of known lengths for Review Sewing Order's warnings, then smart corners beside rounded ones, then run connectors beside jumps, then push compensation side by side, then hand stitch). The test checks each one sews and fits the hoop. Run it with SEWOUT_DIR set to a folder to write the
// designs there as OpenHoop projects:
//   SEWOUT_DIR="$PWD/docs/sewout" swift test --filter SewOutPackTests
import XCTest
@testable import EmbroideryCore

final class SewOutPackTests: XCTestCase {
    private let fonts = EmbroideryFont.all(in: EmbroideryFontTests.directory)
    private let threads = ThreadColor.palette

    /// A satin column running up from `bottom`, `length` mm long and `width` mm wide, with a rung every 5 mm.
    private func column(_ name: String, at bottom: Point, length: Double, width: Double, color: ThreadColor) -> RunObject {
        let rungs = stride(from: 0.0, through: length, by: 5).flatMap { y in [PathNode(Point(bottom.x - width / 2, bottom.y + y)), PathNode(Point(bottom.x + width / 2, bottom.y + y))] }
        var satin = RunObject(name: name, nodes: rungs, color: color)
        satin.digitizing = DigitizingSettings(kind: .satin)
        return satin
    }
    private func fill(_ name: String, _ nodes: [PathNode], color: ThreadColor) -> RunObject {
        var object = RunObject(name: name, nodes: nodes, color: color)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill); object.stitchLength = 3
        return object
    }
    private func box(_ center: Point, _ half: Double) -> (min: Point, max: Point) { (center - Point(half, half), center + Point(half, half)) }
    private func newDesign() -> Design { var design = Design(); design.hoop = Hoop(width: 100, height: 100); return design }

    /// 1 · Satin: widths on Auto underlay (top row), then compensation as a share of the width (bottom row).
    func satinSheet() -> Design {
        var design = newDesign()
        for (i, width) in [1.5, 3.0, 5.0].enumerated() {
            design.objects.append(column("Satin \(width.formatted()) mm, Auto underlay", at: Point(Double(i - 1) * 28, 6), length: 34, width: width, color: threads[0]))
        }
        for (i, percent) in [0.0, 3.0, 5.0].enumerated() {
            var satin = column("Satin 4 mm, compensation \(Int(percent))%", at: Point(Double(i - 1) * 28, -40), length: 34, width: 4, color: threads[1])
            satin.digitizing?.pullPercent = percent
            design.objects.append(satin)
        }
        return design
    }

    /// 2 · Fills, 24 mm each: tatami, contour, radial (top row); wave, turning (stitch angles), tatami with a hole.
    func fillSheet() -> Design {
        var design = newDesign()
        let top = 22.0, bottom = -22.0
        design.objects.append(fill("Tatami 45°", ShapeGeometry.nodes(.rectangle, in: box(Point(-30, top), 12)), color: threads[0]))
        var contour = fill("Contour fill", ShapeGeometry.nodes(.ellipse, in: box(Point(0, top), 12)), color: threads[1]); contour.digitizing?.fillStyle = .contour
        var settings = ShapeSettings(); settings.starPoints = 5
        var radial = fill("Radial fill", ShapeGeometry.nodes(.star, in: box(Point(30, top), 12), settings: settings), color: threads[2]); radial.digitizing?.fillStyle = .radial
        var wave = fill("Wave fill", ShapeGeometry.nodes(.rectangle, in: box(Point(-30, bottom), 12)), color: threads[3]); wave.digitizing?.fillStyle = .wave
        // A quarter ring whose stitches turn round the bend, with an angle line across each end and the middle.
        let ring = (0...12).map { k -> Point in let a = Double(k) / 12 * .pi / 2; return Point(-12 + 24 * cos(a), bottom - 12 + 24 * sin(a)) }
            + (0...12).reversed().map { k -> Point in let a = Double(k) / 12 * .pi / 2; return Point(-12 + 13 * cos(a), bottom - 12 + 13 * sin(a)) }
        var turning = fill("Turning fill (stitch angles)", ring.map { PathNode($0) }, color: threads[4])
        turning.digitizing?.angleLines = [5.0, 45, 85].map { degrees in
            let a = degrees * .pi / 180; return [Point(-12 + 11 * cos(a), bottom - 12 + 11 * sin(a)), Point(-12 + 26 * cos(a), bottom - 12 + 26 * sin(a))]
        }
        var holed = fill("Tatami with a hole", ShapeGeometry.nodes(.rectangle, in: box(Point(30, bottom), 12)), color: threads[5])
        holed.holes = [ShapeGeometry.nodes(.ellipse, in: box(Point(30, bottom), 5))]
        design.objects += [contour, radial, wave, turning, holed]
        return design
    }

    /// 3 · Lettering: an embroidery font at three small sizes, a tiny one, and a Mac font converted to fill.
    func letteringSheet() throws -> Design {
        var design = newDesign()
        let lines: [(text: String, font: String, kind: LetteringSpec.FontKind, height: Double, y: Double)] = [
            ("Abc 123", "small_font", .embroidery, 12, 30), ("Abc 123", "small_font", .embroidery, 8, 12), ("Abc 123", "small_font", .embroidery, 5, 0),
            ("tiny 4 mm", "glacial_tiny", .embroidery, 4, -12), ("OpenHoop", "Helvetica-Bold", .system, 10, -30)
        ]
        for (index, line) in lines.enumerated() {
            var spec = LetteringSpec(text: line.text, fontKind: line.kind, font: line.font, height: line.height)
            spec.transform { $0 + Point(0, line.y) }
            design.objects += try spec.build(color: threads[index % 3], embroideryFonts: fonts).objects
        }
        return design
    }

    /// 4 · A monogram: three initials, big middle, swirls and a satin circle border.
    func monogramSheet() throws -> Design {
        var design = newDesign()
        let spec = MonogramSpec(initials: "JMS", fontKind: .embroidery, font: "venezia", height: 22, layout: .bigMiddle, ornament: .swirls, border: .circle, borderWidth: 2.5, borderGap: 2.5)
        design.objects = try spec.build(color: threads[2], embroideryFonts: fonts).objects
        return design
    }

    /// 5 · Travel and finishing: overlapping circles branched (top left) and the same not branched (top right), a
    /// patch with a satin border, running and bean lines, and the basting box around it all.
    func travelSheet() throws -> Design {
        var design = newDesign()
        func circles(_ x: Double, _ name: String) -> [RunObject] { (0..<3).map { k in fill("\(name) circle \(k + 1)", ShapeGeometry.nodes(.ellipse, in: box(Point(x + Double(k) * 9, 28), 6)), color: threads[0]) } }
        design.objects = circles(-38, "Unbranched") + circles(6, "Branched")
        _ = try design.branch(Set(design.objects.suffix(3).map(\.id)), entry: nil, exit: nil)
        let patch = fill("Patch", ShapeGeometry.nodes(.ellipse, in: box(Point(-20, -6), 12)), color: threads[1])
        let border = try SatinBorder.around(patch, width: 3, color: threads[2]).object
        design.objects += [patch, border]
        let wavy = (0...6).map { k in PathNode(Point(4 + Double(k) * 6, -6 + (k % 2 == 0 ? 4 : -4)), smooth: true) }
        design.objects.append(RunObject(name: "Running line", nodes: wavy, color: threads[3]))
        var bean = RunObject(name: "Bean line", nodes: wavy.map { var n = $0; n.point = n.point + Point(0, -14); return n }, color: threads[3])
        bean.digitizing = DigitizingSettings(kind: .run); bean.digitizing?.runPasses = 3
        design.objects.append(bean)
        design.basting = 4
        return design
    }

    /// 6 · Line styles and stipple: zigzag at 2 and 4 mm, back stitch, stem stitch and an open blanket line (left),
    /// a square with a blanket edge whose prongs should point inward (top right), and stipple at 4 and 2.5 mm (bottom).
    func lineStyleSheet() -> Design {
        var design = newDesign()
        func line(_ name: String, y: Double, _ style: RunStyle, width: Double? = nil, spacing: Double? = nil, color: ThreadColor) -> RunObject {
            var object = RunObject(name: name, nodes: [PathNode(Point(-44, y)), PathNode(Point(-24, y + 3), smooth: true), PathNode(Point(-4, y))], color: color)
            object.digitizing = DigitizingSettings(kind: .run); object.digitizing?.runStyle = style
            object.digitizing?.runWidth = width; object.digitizing?.runSpacing = spacing
            return object
        }
        design.objects = [
            line("Zigzag 2 mm", y: 40, .zigzag, color: threads[0]), line("Zigzag 4 mm, spacing 2 mm", y: 30, .zigzag, width: 4, spacing: 2, color: threads[0]),
            line("Back stitch", y: 20, .backStitch, color: threads[1]), line("Stem stitch", y: 10, .stemStitch, color: threads[1]),
            line("Blanket line", y: -2, .blanket, color: threads[2])
        ]
        var square = RunObject(name: "Blanket edge (prongs inward)", nodes: ShapeGeometry.nodes(.rectangle, in: box(Point(24, 24), 13)), color: threads[2])
        square.closed = true; square.digitizing = DigitizingSettings(kind: .run); square.digitizing?.runStyle = .blanket
        design.objects.append(square)
        for (index, spacing) in [4.0, 2.5].enumerated() {
            let x = index == 0 ? -22.0 : 22.0
            var stipple = fill("Stipple \(spacing.formatted()) mm", ShapeGeometry.nodes(.ellipse, in: (Point(x - 19, -44), Point(x + 19, -16))), color: threads[3 + index])
            stipple.digitizing?.fillStyle = .stipple; stipple.digitizing?.stippleSpacing = spacing
            design.objects.append(stipple)
        }
        return design
    }

    /// 7 · Motifs and more: heart, leaf and star motif runs (top left), a star motif fill (top right), and along the
    /// bottom a cross stitch fill, a gradient fill, and a 5 mm satin flat then raised.
    func patternSheet() -> Design {
        var design = newDesign()
        for (row, motif) in [Motif.heart, .leaf, .star].enumerated() {
            let y = 40.0 - Double(row) * 12
            var line = RunObject(name: "\(motif.title) motif run", nodes: [PathNode(Point(-44, y)), PathNode(Point(-24, y + 2), smooth: true), PathNode(Point(-4, y))], color: threads[row])
            line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.runStyle = .motif; line.digitizing?.motif = motif
            design.objects.append(line)
        }
        var motifs = fill("Star motif fill", ShapeGeometry.nodes(.ellipse, in: (Point(6, 10), Point(44, 46))), color: threads[2])
        motifs.digitizing?.fillStyle = .motif; motifs.digitizing?.motif = .star; motifs.digitizing?.angle = 0
        var cross = fill("Cross stitch fill", ShapeGeometry.nodes(.ellipse, in: (Point(-44, -44), Point(-14, -14))), color: threads[1])
        cross.digitizing?.fillStyle = .crossStitch
        var gradient = fill("Gradient fill", ShapeGeometry.nodes(.rectangle, in: (Point(-8, -44), Point(16, -12))), color: threads[0])
        gradient.digitizing?.fillStyle = .gradient; gradient.digitizing?.angle = 0
        var raised = column("Satin 5 mm, raised", at: Point(38, -44), length: 30, width: 5, color: threads[4]); raised.digitizing?.raised = true
        design.objects += [motifs, cross, gradient, column("Satin 5 mm, flat", at: Point(27, -44), length: 30, width: 5, color: threads[4]), raised]
        return design
    }

    /// 8 · Wide satin, overlaps and outlines: a 6 mm satin beside two 14 mm ones, split and not split (top left); a
    /// star with an edge outline and two offsets outside it (top right); and a square with a circle sewn on top, with
    /// Remove Overlaps on (bottom left) and off (bottom right).
    func wideSatinOverlapsAndOutlinesSheet() throws -> Design {
        var design = newDesign()
        let split = column("Satin 14 mm, split", at: Point(-24, 8), length: 34, width: 14, color: threads[0])
        // Not split: Maximum stitch raised past the width, so its stitches sew the full 14 mm (and get the long-stitch warning).
        var unsplit = column("Satin 14 mm, not split", at: Point(-6, 8), length: 34, width: 14, color: threads[0])
        unsplit.digitizing?.autoSplit = false; unsplit.digitizing?.maximumSatin = 16
        design.objects = [column("Satin 6 mm", at: Point(-40, 8), length: 34, width: 6, color: threads[0]), split, unsplit]
        var settings = ShapeSettings(); settings.starPoints = 5
        let star = fill("Star", ShapeGeometry.nodes(.star, in: box(Point(27, 25), 10), settings: settings), color: threads[1])
        var options = OutlineOptions(); options.offsets = [2.5, 5]
        design.objects += [star] + (try OutlinesOffsets.around(star, options: options, color: threads[3]).objects)
        // Both squares, then both circles, so each thread is used once.
        var squares: [RunObject] = [], circles: [RunObject] = []
        for (x, removed) in [(-24.0, true), (24.0, false)] {
            var square = fill("Square, overlaps \(removed ? "removed" : "kept")", ShapeGeometry.nodes(.rectangle, in: box(Point(x, -26), 17)), color: threads[2])
            if removed { square.digitizing?.cutOutOverlaps = true }
            squares.append(square)
            circles.append(fill("Circle on top, overlaps \(removed ? "removed" : "kept")", ShapeGeometry.nodes(.ellipse, in: box(Point(x, -26), 9)), color: threads[4]))
        }
        design.objects += squares + circles
        return design
    }

    /// The gaps (mm) between the bars of sheet 9's top two rows: either side of the 15 mm long-move warning, and
    /// beyond it.
    static let moveGaps = [6.0, 10, 14, 16, 20, 25]
    /// 9 · Moves and jumps: one thread per row, so changing rows is a thread change (never warned about). Each mark is
    /// a 10 mm bean-stitch line (three passes, to show up well). Top: marks with moves of `moveGaps` between them,
    /// trimmed. Middle: the same with Trim after off, so the thread jumps across untrimmed. Bottom: marks 1, 2, 3, 4
    /// and 6 mm apart, either side of the 3 mm trim distance (closer ones are stitched across, farther ones trimmed).
    /// The marks sew up and down in turn, from end to end, so each move runs straight across and is exactly its gap
    /// long; each is named after the move to it.
    func movesAndJumpsSheet() -> Design {
        var design = newDesign()
        /// One row of marks at `y` (their bottom), `gaps` apart and centred.
        func row(_ label: String, y: Double, gaps: [Double], color: ThreadColor, trim: TrimRule = .whenFar) -> [RunObject] {
            var x = -gaps.reduce(0, +) / 2
            return (0...gaps.count).map { index in
                if index > 0 { x += gaps[index - 1] }
                let bottom = PathNode(Point(x, y)), top = PathNode(Point(x, y + 10))
                let name = index == 0 ? "\(label): first" : "\(label): after \(gaps[index - 1].formatted()) mm"
                var mark = RunObject(name: name, nodes: index % 2 == 0 ? [bottom, top] : [top, bottom], color: color)
                mark.digitizing = DigitizingSettings(kind: .run); mark.digitizing?.runPasses = 3
                mark.trimRule = trim
                return mark
            }
        }
        design.objects = row("Trimmed", y: 26, gaps: Self.moveGaps, color: threads[0])
            + row("Not trimmed", y: -2, gaps: Self.moveGaps, color: threads[1], trim: .off)
            + row("Short move", y: -32, gaps: [1, 2, 3, 4, 6], color: threads[2])
        return design
    }

    /// 10 · Smart corners: each shape twice, smart corners on (first thread) beside off, i.e. rounded (second
    /// thread). Top: satin lines in a V, 4 mm wide at 60° (mitred) and 3 mm wide at 30° (capped). Middle: a 3 mm
    /// border round a triangle (three mitres). Bottom: a 3 mm border round a star (five capped points).
    func smartCornersSheet() throws -> Design {
        var design = newDesign()
        /// A V-shaped line with 16 mm legs and `angle` degrees between them, its point at `point`, opening upward.
        func vee(_ angle: Double, at point: Point) -> RunObject {
            let half = angle / 2 * .pi / 180
            return RunObject(name: "V", nodes: [Point(-16 * sin(half), 16 * cos(half)), Point(0, 0), Point(16 * sin(half), 16 * cos(half))].map { PathNode($0 + point) })
        }
        func shape(_ points: [Point]) -> RunObject {
            var object = RunObject(name: "Shape", nodes: points.map { PathNode($0) }, color: threads[0])
            object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
            return object
        }
        var on: [RunObject] = [], off: [RunObject] = []
        /// The same satin built with smart corners on (left of the pair) and off.
        func both(_ name: String, _ make: (Bool) throws -> RunObject) throws {
            var smart = try make(true), rounded = try make(false)
            smart.name = "\(name), smart corners"; smart.color = threads[0]
            rounded.name = "\(name), rounded"; rounded.color = threads[1]
            on.append(smart); off.append(rounded)
        }
        for (x, angle, width) in [(-36.0, 60.0, 4.0), (12, 30, 3)] {
            try both("Satin \(width.formatted()) mm, \(Int(angle))° V") { smart in
                try SatinLine.column(from: vee(angle, at: Point(smart ? x : x + 24, 29)), width: width, smartCorners: smart)
            }
        }
        try both("Triangle, 3 mm border") { smart in
            let x = smart ? -24.0 : 24
            return try SatinBorder.around(shape([Point(x - 12, -6), Point(x + 12, -6), Point(x, 16)]), width: 3, color: threads[0], smartCorners: smart).object
        }
        try both("Star, 3 mm border") { smart in
            let center = Point(smart ? -24 : 24, -28)
            let star = (0..<10).map { k -> Point in let r = k % 2 == 0 ? 13.0 : 5.7, a = Double(k) * .pi / 5 + .pi / 2; return center + Point(r * cos(a), r * sin(a)) }
            return try SatinBorder.around(shape(star), width: 3, color: threads[0], smartCorners: smart).object
        }
        design.objects = on + off
        return design
    }

    /// 11 · Connectors: Run (left, first thread) beside Jump (right, second thread). A run is hidden only where a
    /// later part sews over it. Top: three touching 10 mm squares, each run crossing the next square corner to corner.
    /// Then three 10 mm squares 4 mm apart, each run straight across the gap. Then four 3 mm satin bars 6 mm apart,
    /// sewn up and down in turn, so each run crosses the top or bottom gap. Bottom: "ONE" with Between letters Run
    /// beside the font's own trims.
    func connectorsSheet() throws -> Design {
        var design = newDesign()
        /// Three 10 mm squares from x `left`, `gap` apart, centred on `y`. With `across`, each starts near its top-right
        /// corner and ends near its bottom-right one (1 mm in, so the corner rows aren't crowded), so the move to the next crosses that square; otherwise each ends
        /// at the middle of its right edge and the next starts at the middle of its left edge.
        func squares(_ label: String, left: Double, y: Double, gap: Double, across: Bool, connector: Connector, color: ThreadColor) -> [RunObject] {
            (0..<3).map { k in
                let x = left + Double(k) * (10 + gap)
                var square = fill("\(label) square \(k + 1)", ShapeGeometry.nodes(.rectangle, in: (Point(x, y - 5), Point(x + 10, y + 5))), color: color)
                square.entry = across ? Point(x + 9, y + 4) : Point(x, y)
                square.exit = across ? Point(x + 9, y - 4) : Point(x + 10, y)
                if k < 2 { square.connectorType = connector }
                return square
            }
        }
        /// Four 3 mm satin bars 14 mm tall, 9 mm apart centre to centre from x `left`, sewn up and down in turn.
        func bars(_ label: String, left: Double, connector: Connector, color: ThreadColor) -> [RunObject] {
            (0..<4).map { k in
                let x = left + Double(k) * 9
                var bar = column("\(label) bar \(k + 1)", at: Point(x, -10), length: 14, width: 3, color: color)
                bar.entry = Point(x, k % 2 == 0 ? -10 : 4); bar.exit = Point(x, k % 2 == 0 ? 4 : -10)
                if k < 3 { bar.connectorType = connector }
                return bar
            }
        }
        /// "ONE" in the small embroidery font, 10 mm tall, centred on x.
        func word(_ x: Double, run: Bool, color: ThreadColor) throws -> [RunObject] {
            var spec = LetteringSpec(text: "ONE", fontKind: .embroidery, font: "small_font", height: 10)
            if run { spec.betweenLetters = .run }
            spec.transform { $0 + Point(x, -32) }
            return try spec.build(color: color, embroideryFonts: fonts).objects
        }
        design.objects = squares("Run, touching", left: -44, y: 34, gap: 0, across: true, connector: .run, color: threads[0])
            + squares("Run, 4 mm gaps", left: -46, y: 14, gap: 4, across: false, connector: .run, color: threads[0])
            + bars("Run", left: -42.5, connector: .run, color: threads[0])
            + (try word(-25, run: true, color: threads[0]))
            + squares("Jump, touching", left: 14, y: 34, gap: 0, across: true, connector: .jump, color: threads[1])
            + squares("Jump, 4 mm gaps", left: 8, y: 14, gap: 4, across: false, connector: .jump, color: threads[1])
            + bars("Jump", left: 15.5, connector: .jump, color: threads[1])
            + (try word(25, run: false, color: threads[1]))
        return design
    }

    /// The push compensation (mm) of sheet 12's three columns, left to right.
    static let pushSteps = [0.0, 0.2, 0.4]

    /// 12 · Push and pull: tatami fills with Push 0, 0.2 and 0.4 mm (left to right), each with the default 0.2 mm
    /// pull. Top: 20 mm squares with rows across (0°); middle: the same with rows up and down (90°); bottom: 20 mm
    /// circles at 45°. Each is then outlined in the second thread exactly where it was drawn, so the edges the rows run
    /// along show whether they sew wider than drawn, and the row ends whether they reach the outline.
    func pushAndPullSheet() -> Design {
        var design = newDesign(), outlines: [RunObject] = []
        for (row, (y, angle, shape)) in [(26.0, 0.0, BasicShape.rectangle), (0, 90, .rectangle), (-26, 45, .ellipse)].enumerated() {
            for (column, push) in Self.pushSteps.enumerated() {
                let nodes = ShapeGeometry.nodes(shape, in: box(Point(Double(column - 1) * 28, y), 10))
                var shapeFill = fill("Row \(row + 1), push \(push.formatted()) mm", nodes, color: threads[0])
                shapeFill.digitizing?.angle = angle; shapeFill.digitizing?.pushCompensation = push
                design.objects.append(shapeFill)
                var outline = RunObject(name: "Outline \(row + 1), push \(push.formatted()) mm", nodes: nodes, color: threads[1])
                outline.closed = true; outline.digitizing = DigitizingSettings(kind: .run)
                outlines.append(outline)
            }
        }
        design.objects += outlines
        return design
    }

    /// Sheet 13's hand stitch settings, left to right (satins) and top to bottom (lines): off, then
    /// (length, angle, count) 2·2·1×, 4·4·1× and 2·2·2×.
    static let handSteps: [(length: Int, angle: Int, count: Int)?] = [nil, (2, 2, 1), (4, 4, 1), (2, 2, 2)]

    /// 13 · Hand stitch: four 4 mm satins 30 mm tall (left, first thread) and four gently curved running lines 36 mm
    /// long (right, second thread), each plain, then with the settings in `handSteps`.
    func handStitchSheet() -> Design {
        var design = newDesign()
        func hand(_ step: (length: Int, angle: Int, count: Int)?) -> HandStitch? {
            step.map { var h = HandStitch(); h.length = $0.length; h.angle = $0.angle; h.count = $0.count; return h }
        }
        func label(_ step: (length: Int, angle: Int, count: Int)?) -> String { step.map { "hand \($0.length)·\($0.angle)·\($0.count)×" } ?? "plain" }
        for (k, step) in Self.handSteps.enumerated() {
            var satin = column("Satin \(k + 1), \(label(step))", at: Point(-40 + Double(k) * 11, -15), length: 30, width: 4, color: threads[0])
            satin.digitizing?.handStitch = hand(step)
            design.objects.append(satin)
        }
        for (k, step) in Self.handSteps.enumerated() {
            let y = 21 - Double(k) * 14
            var line = RunObject(name: "Line \(k + 1), \(label(step))", nodes: [PathNode(Point(6, y)), PathNode(Point(24, y + 4), smooth: true), PathNode(Point(42, y))], color: threads[1])
            line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.handStitch = hand(step)
            design.objects.append(line)
        }
        return design
    }

    func testHandStitchSheetRoughensAllButThePlainOnes() throws {
        let sheet = handStitchSheet()
        XCTAssertTrue(sheet.needsSchemaThirteen)
        XCTAssertEqual(sheet.objects.filter { $0.settings.handStitch == nil }.count, 2, "one plain satin and one plain line")
        XCTAssertNoThrow(try RunningEngine.compile(sheet))
    }

    func testPushAndPullSheetPullsInOnlyTheSidesItSays() throws {
        let sheet = pushAndPullSheet()
        XCTAssertTrue(sheet.needsSchemaTwelve)
        // In the top row (rows across), more push lowers the top of the fill, and the rows stay as long.
        let tops = try Self.pushSteps.map { push -> (top: Double, width: Double) in
            let object = try XCTUnwrap(sheet.objects.first { $0.name == "Row 1, push \(push.formatted()) mm" })
            let points = try AreaEngine.fill(object).sections.filter { !$0.underlay }.flatMap(\.points)
            return (points.map(\.y).max()!, points.map(\.x).max()! - points.map(\.x).min()!)
        }
        XCTAssertEqual(tops[0].top - tops[2].top, 0.4, accuracy: 0.1)
        XCTAssertEqual(tops[0].width, tops[2].width, accuracy: 0.02)
    }

    func testConnectorsSheetRunsWhereItSays() throws {
        let sheet = try connectorsSheet(), plan = try RunningEngine.compile(sheet)
        func trims(_ prefix: String) -> Int {
            let ids = Set(sheet.objects.filter { $0.name.hasPrefix(prefix) }.map(\.id))
            return plan.commands.filter { $0.op == .trim && $0.objectID.map(ids.contains) == true }.count
        }
        // Each run group trims only after its last part; the jump groups trim between parts too.
        for (run, jump) in [("Run, touching", "Jump, touching"), ("Run, 4 mm gaps", "Jump, 4 mm gaps"), ("Run bar", "Jump bar")] {
            XCTAssertLessThan(trims(run), trims(jump), run)
        }
        XCTAssertFalse(plan.warnings.contains { $0.contains("run connector") }, "every run is under 15 mm")
        XCTAssertTrue(sheet.needsSchemaEleven)
    }

    func testSmartCornersSheetHasTheCornersItSaysItHas() throws {
        let sheet = try smartCornersSheet()
        func kinds(_ name: String) throws -> [SmartCorners.Kind] {
            let object = try XCTUnwrap(sheet.objects.first { $0.name == name }, name)
            let p = stride(from: 0, to: object.nodes.count, by: 2).map { (object.nodes[$0].point, object.nodes[$0 + 1].point) }
            return SmartCorners.corners(p, closed: object.closed).map { c in
                SmartCorners.corner(previous: p[(c + p.count - 1) % p.count], pair: p[c], next: p[(c + 1) % p.count], spacing: 0.4).kind
            }
        }
        XCTAssertEqual(try kinds("Satin 4 mm, 60° V, smart corners"), [.mitre])
        XCTAssertEqual(try kinds("Satin 3 mm, 30° V, smart corners"), [.cap])
        XCTAssertEqual(try kinds("Triangle, 3 mm border, smart corners"), [.mitre, .mitre, .mitre])
        XCTAssertEqual(try kinds("Star, 3 mm border, smart corners"), Array(repeating: .cap, count: 5))
        for name in ["Satin 4 mm, 60° V", "Satin 3 mm, 30° V", "Triangle, 3 mm border", "Star, 3 mm border"] {
            XCTAssertEqual(try kinds("\(name), rounded"), [], name)
        }
        XCTAssertTrue(sheet.needsSchemaTen)
    }

    func testMovesAndJumpsSheetIsWarnedAboutAsIntended() throws {
        let sheet = movesAndJumpsSheet(), steps = sheet.sewingSteps(plan: try RunningEngine.compile(sheet))
        let gaps = Self.moveGaps, bars = gaps.count + 1
        XCTAssertEqual(steps.count, bars * 2 + 6)
        // Each move is its gap long.
        for (index, gap) in gaps.enumerated() {
            XCTAssertEqual(steps[index + 1].travel?.length ?? 0, gap, accuracy: 0.05, "trimmed move \(index + 1)")
            XCTAssertEqual(steps[bars + index + 1].travel?.length ?? 0, gap, accuracy: 0.05, "untrimmed move \(index + 1)")
        }
        let warnings = sheet.sewingWarnings(steps)
        // Top row: the moves of 16 mm and more. Middle row: every move (each is longer than the 3 mm trim distance).
        // Bottom row and the row changes: none.
        let longMoves = gaps.indices.filter { gaps[$0] >= SewingTravel.longMove }.map { $0 + 1 }
        XCTAssertEqual(Set(warnings.keys), Set(longMoves + (1...gaps.count).map { bars + $0 }))
        XCTAssertTrue(longMoves.allSatisfy { if case .longMove = warnings[$0] { return true } else { return false } })
        XCTAssertTrue((1...gaps.count).allSatisfy { if case .untrimmedJump = warnings[bars + $0] { return true } else { return false } })
        // Bottom row: 1 and 2 mm are stitched across, 3 mm and more trimmed.
        let shortMoves = steps.suffix(5).map { $0.travel! }
        XCTAssertEqual(shortMoves.map(\.trimmed), [false, false, true, true, true])
    }

    func testEverySheetSewsAndFitsTheHoop() throws {
        let sheets: [(String, Design)] = [("1 Satin", satinSheet()), ("2 Fills", fillSheet()), ("3 Lettering", try letteringSheet()),
                                          ("4 Monogram", try monogramSheet()), ("5 Travel and finishing", try travelSheet()), ("6 Line styles and stipple", lineStyleSheet()), ("7 Motifs, cross stitch and more", patternSheet()),
                                          ("8 Wide satin, overlaps and outlines", try wideSatinOverlapsAndOutlinesSheet()), ("9 Moves and jumps", movesAndJumpsSheet()),
                                          ("10 Smart corners", try smartCornersSheet()), ("11 Connectors", try connectorsSheet()),
                                          ("12 Push and pull", pushAndPullSheet()), ("13 Hand stitch", handStitchSheet())]
        for (name, sheet) in sheets {
            var design = sheet
            design.schemaVersion = design.needsSchemaThirteen ? 13 : design.needsSchemaTwelve ? 12 : design.needsSchemaEleven ? 11 : design.needsSchemaTen ? 10 : design.needsSchemaNine ? 9 : design.needsSchemaEight ? 8 : design.needsSchemaSeven ? 7 : design.needsSchemaSix ? 6 : design.needsSchemaFive ? 5 : 4
            let plan = try RunningEngine.compile(design)
            XCTAssertGreaterThan(plan.stitchCount, 100, name)
            XCTAssertTrue(plan.commands.allSatisfy { design.hoop.contains($0.point, tolerance: -2) }, "\(name) stays 2 mm inside the hoop")
            if let folder = ProcessInfo.processInfo.environment["SEWOUT_DIR"] {
                let package = URL(fileURLWithPath: folder).appendingPathComponent("\(name).stitchproj")
                try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(design).write(to: package.appendingPathComponent("design.json"))
            }
        }
        // The branched circles sew with fewer trims than the same circles not branched.
        let travel = try travelSheet(), plan = try RunningEngine.compile(travel)
        func trims(_ prefix: String) -> Int {
            let ids = Set(travel.objects.filter { $0.name.hasPrefix(prefix) }.map(\.id))
            return plan.commands.filter { $0.op == .trim && $0.objectID.map(ids.contains) == true }.count
        }
        XCTAssertLessThan(trims("Branched"), trims("Unbranched"))
        // The square with its overlap removed sews fewer stitches than the one that keeps it.
        let sheet8 = try wideSatinOverlapsAndOutlinesSheet(), plan8 = try RunningEngine.compile(sheet8)
        func stitches(_ name: String) -> Int {
            let id = sheet8.objects.first { $0.name == name }?.id
            return plan8.commands.filter { $0.op == .stitch && $0.objectID == id }.count
        }
        XCTAssertLessThan(stitches("Square, overlaps removed"), stitches("Square, overlaps kept"))
    }
}
