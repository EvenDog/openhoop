// The sew-out test pack: seven designs for a 100 × 100 mm hoop that put the stitch settings worth checking on a real
// machine side by side (satin widths and compensation, the fill styles, small lettering, a monogram, travel and
// finishing, the line styles and stipple, and motifs, cross stitch, gradient and raised satin). The test checks each one sews and fits the hoop. Run it with SEWOUT_DIR set to a folder to write the
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

    func testEverySheetSewsAndFitsTheHoop() throws {
        let sheets: [(String, Design)] = [("1 Satin", satinSheet()), ("2 Fills", fillSheet()), ("3 Lettering", try letteringSheet()),
                                          ("4 Monogram", try monogramSheet()), ("5 Travel and finishing", try travelSheet()), ("6 Line styles and stipple", lineStyleSheet()), ("7 Motifs, cross stitch and more", patternSheet())]
        for (name, sheet) in sheets {
            var design = sheet
            design.schemaVersion = design.needsSchemaSix ? 6 : design.needsSchemaFive ? 5 : 4
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
    }
}
