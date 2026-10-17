// Checks the line stitch styles (zigzag, blanket, back stitch, stem stitch) and the stipple fill: each stays on or
// beside its line or inside its shape, at the sizes chosen; stipple never crosses itself, covers the shape, and sews
// the same way every time; and designs using them are saved as file version 6.
import XCTest
@testable import EmbroideryCore

final class RunningStylesTests: XCTestCase {
    /// A straight 30 mm line along the x axis with `style`.
    private func line(_ style: RunStyle, width: Double? = nil, spacing: Double? = nil) -> RunObject {
        var object = RunObject(name: "Line", nodes: [Point(0, 0), Point(30, 0)].map { PathNode($0) })
        object.digitizing = DigitizingSettings(kind: .run); object.digitizing?.runStyle = style
        object.digitizing?.runWidth = width; object.digitizing?.runSpacing = spacing
        return object
    }
    private func stitches(_ object: RunObject) throws -> [Point] { try StitchEngine.fresh(object, under: []).sections.flatMap(\.points) }

    func testZigzagSwingsSideToSideAtItsWidth() throws {
        let points = try stitches(line(.zigzag, width: 2, spacing: 1.5))
        XCTAssertTrue(points.allSatisfy { abs(abs($0.y) - 1) < 1e-9 }, "every point is half the width from the line")
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { ($0.y > 0) != ($1.y > 0) }, "alternately left and right")
        XCTAssertEqual(points.count, 21, "a point every 1.5 mm along 30 mm")
        XCTAssertEqual(points.first!.x, 0, accuracy: 1e-9); XCTAssertEqual(points.last!.x, 30, accuracy: 1e-9)
    }

    func testBlanketProngsPointIntoAClosedShape() throws {
        var square = RunObject(name: "Square", nodes: [Point(0, 0), Point(30, 0), Point(30, 30), Point(0, 30)].map { PathNode($0) })
        square.closed = true; square.digitizing = DigitizingSettings(kind: .run); square.digitizing?.runStyle = .blanket
        let points = try stitches(square)
        let inside = points.allSatisfy { $0.x >= -1e-9 && $0.x <= 30 + 1e-9 && $0.y >= -1e-9 && $0.y <= 30 + 1e-9 }
        XCTAssertTrue(inside, "the prongs point into the shape")
        // A prong goes out and straight back to the same point: base, tip, base.
        let prongs = points.indices.dropFirst().dropLast().filter { points[$0 - 1] == points[$0 + 1] }.map { (base: points[$0 - 1], tip: points[$0]) }
        XCTAssertEqual(prongs.count, 40, "a prong every 3 mm round 120 mm")
        XCTAssertTrue(prongs.allSatisfy { abs($0.base.distance(to: $0.tip) - 2.5) < 1e-6 }, "each prong 2.5 mm long")
        // Drawn the other way round, the prongs still point inside.
        square.nodes.reverse()
        XCTAssertTrue(try stitches(square).allSatisfy { $0.x >= -1e-9 && $0.x <= 30 + 1e-9 && $0.y >= -1e-9 && $0.y <= 30 + 1e-9 })
    }

    func testBackStitchGoesForwardTwoAndBackOne() throws {
        var object = line(.backStitch); object.stitchLength = 2.5
        let points = try stitches(object), xs = points.map(\.x)
        XCTAssertTrue(points.allSatisfy { abs($0.y) < 1e-9 }, "back stitch stays on the line")
        XCTAssertEqual(Array(xs.prefix(5)), [0, 5, 2.5, 7.5, 5], "forward two, back one")
        XCTAssertEqual(xs.last!, 30, accuracy: 1e-9)

        var stem = line(.stemStitch, width: 1); stem.stitchLength = 2.5
        let rope = try stitches(stem)
        XCTAssertTrue(rope.allSatisfy { abs($0.y) <= 0.5 + 1e-9 }, "stem stitch stays within its width")
        XCTAssertTrue(rope.dropFirst().dropLast().allSatisfy { abs(abs($0.y) - 0.5) < 1e-9 }, "each stitch slants across the line")
    }

    /// A 40 × 30 mm stipple fill: inside the shape, never crossing itself, covering it, and the same every time.
    func testStippleWandersWithoutCrossingAndCoversTheShape() throws {
        var fill = RunObject(name: "Stipple", nodes: [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.fillStyle = .stipple; fill.stitchLength = 2.5
        let sections = try AreaEngine.fill(fill).sections
        XCTAssertFalse(sections.contains(where: \.underlay), "stipple has no underlay")
        let points = sections.flatMap(\.points)
        let shape = [[Point(-0.5, -0.5), Point(40.5, -0.5), Point(40.5, 30.5), Point(-0.5, 30.5)]]
        XCTAssertTrue(points.allSatisfy { AreaGeometry.contains($0, rings: shape) }, "every stitch inside the shape")
        // No two stitches of the line cross (ones sharing a needle hole only touch there, so they're skipped).
        let top = sections.filter { !$0.joined || $0.points.count > 20 }.flatMap(\.points)
        let segments = Array(zip(top, top.dropFirst()))
        var crossings = 0
        for i in segments.indices { for j in (i + 2)..<max(i + 2, min(segments.count, i + 400)) {
            let shared = [segments[j].0, segments[j].1].contains { $0 == segments[i].0 || $0 == segments[i].1 }   // the loop closing on its first hole
            if !shared && AreaGeometry.intersects(segments[i].0, segments[i].1, segments[j].0, segments[j].1) { crossings += 1 }
        } }
        XCTAssertEqual(crossings, 0, "the line never crosses itself")
        // Covered: every point of the shape, 3 mm in from its edge, is within 3 mm of a stitch.
        var gaps = 0
        for x in stride(from: 3.0, through: 37, by: 1) { for y in stride(from: 3.0, through: 27, by: 1) {
            if !points.contains(where: { $0.distance(to: Point(x, y)) < 3 }) { gaps += 1 }
        } }
        XCTAssertEqual(gaps, 0, "no bare patches")
        XCTAssertEqual(try AreaEngine.fill(fill).sections.flatMap(\.points), points, "the same shape always sews the same way")
    }

    /// No line style makes a stitch over 10 mm, even at the largest settings (stem stitch at a 10 mm stitch length,
    /// zigzag 10 mm wide and 10 mm open).
    func testLineStylesKeepStitchesSewable() throws {
        var stem = line(.stemStitch, width: 1); stem.stitchLength = 10
        var zigzag = line(.zigzag, width: 10, spacing: 10)
        zigzag.stitchLength = 10
        for object in [stem, zigzag] {
            let points = try stitches(object)
            XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.distance(to: $1) <= 10 + 1e-9 }, "\(object.settings.runStyle!) stitches at most 10 mm")
        }
    }

    /// A 30 mm heart run: whole hearts 4 mm long with 1 mm gaps, centered, joined along the line, standing on it.
    func testMotifRunStringsWholeMotifsAlongTheLine() throws {
        var object = line(.motif, width: 4, spacing: 1); object.digitizing?.motif = .heart
        let points = try stitches(object)
        XCTAssertEqual(points.first!.x, 0, accuracy: 1e-9); XCTAssertEqual(points.last!.x, 30, accuracy: 1e-9)
        XCTAssertTrue(points.allSatisfy { $0.y >= -1e-9 && $0.y <= 4 + 1e-9 }, "hearts stand on the line, 4 mm tall")
        let tips = points.filter { $0.y > 3.5 }.map(\.x)   // the top of each heart's two lobes
        let hearts = Set(tips.map { Int(($0 - 0.5) / 5) }).count
        XCTAssertEqual(hearts, 6, "six 4 mm hearts with 1 mm gaps fit in 30 mm")
        for motif in Motif.allCases {
            object.digitizing?.motif = motif
            let run = try stitches(object)
            XCTAssertTrue(zip(run, run.dropFirst()).allSatisfy { $0.distance(to: $1) <= 2.5 + 1e-6 }, "\(motif) stitches no longer than the stitch length")
            XCTAssertEqual(run.last!.x, 30, accuracy: 1e-9, "\(motif) ends at the line's end")
        }
    }

    /// Motif, cross stitch and gradient fills of a 40 × 30 mm rectangle stay inside it and have their own structure.
    func testPatternFillsStayInsideTheShape() throws {
        func rectangle(_ style: FillStyle) -> RunObject {
            var fill = RunObject(name: style.title, nodes: [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)].map { PathNode($0) })
            fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.fillStyle = style; fill.digitizing?.angle = 0
            fill.digitizing?.expansion = 0; fill.stitchLength = 2.5
            return fill
        }
        let box = [[Point(-0.01, -0.01), Point(40.01, -0.01), Point(40.01, 30.01), Point(-0.01, 30.01)]]
        for style in [FillStyle.motif, .crossStitch, .gradient] {
            let sections = try AreaEngine.fill(rectangle(style)).sections
            XCTAssertTrue(sections.flatMap(\.points).allSatisfy { AreaGeometry.contains($0, rings: box) }, "\(style) stays inside")
            if style != .gradient { XCTAssertFalse(sections.contains(where: \.underlay), "\(style) has no underlay") }
        }
        // Cross stitch: every needle point on a corner of the 3 mm grid, and plenty of X's (a 13 × 10 grid fits).
        let cross = try Motifs.crossStitch(in: [[Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)]], size: 3).flatMap { $0 }
        let onGrid = cross.allSatisfy { p in [p.x, p.y].allSatisfy { v in let r = (v / 3).truncatingRemainder(dividingBy: 1); return r < 1e-6 || r > 1 - 1e-6 || abs(r - 0.5) < 1e-6 } }
        XCTAssertTrue(onGrid, "needle points on the grid's corners")
        // Gradient: rows start 0.4 mm apart and open up to about 2.5 mm.
        // A row is a height where many stitches line up (travel between rows only passes through).
        let heights = try AreaEngine.fill(rectangle(.gradient)).sections.filter { !$0.underlay }.flatMap(\.points).map { ($0.y * 1000).rounded() / 1000 }
        let rows = Dictionary(grouping: heights, by: { $0 }).filter { $0.value.count >= 5 }.keys.sorted()
        let gaps = zip(rows, rows.dropFirst()).map { $1 - $0 }.filter { $0 > 0.05 }
        XCTAssertEqual(gaps.first!, 0.4, accuracy: 0.05, "dense where it starts")
        XCTAssertGreaterThan(gaps.last!, 2, "open where it ends")
        XCTAssertTrue(zip(gaps, gaps.dropFirst()).allSatisfy { $1 >= $0 - 0.05 }, "the gaps only grow")
    }

    /// Raised satin: padding lanes along the column, inside it, before the top stitches.
    func testRaisedSatinIsPadded() throws {
        let rungs = stride(from: 0.0, through: 30, by: 5).flatMap { y in [PathNode(Point(-2.5, y)), PathNode(Point(2.5, y))] }
        var column = RunObject(name: "Column", nodes: rungs); column.digitizing = DigitizingSettings(kind: .satin)
        let flat = try AreaEngine.satin(column).sections.filter(\.underlay).count
        column.digitizing?.raised = true
        let sections = try AreaEngine.satin(column).sections
        XCTAssertGreaterThanOrEqual(sections.filter(\.underlay).count, flat + 7, "a 5 mm column gets about seven padding lanes")
        XCTAssertTrue(sections.filter(\.underlay).flatMap(\.points).allSatisfy { abs($0.x) <= 2.5 + 1e-9 }, "padding stays inside the column")
        XCTAssertFalse(sections.last!.underlay, "the satin sews last, over the padding")
    }

    func testNewStitchesSaveAsVersionSixAndOldDesignsDont() {
        var design = Design(); design.objects = [RunObject(name: "Plain", nodes: [Point(0, 0), Point(10, 0)].map { PathNode($0) })]
        XCTAssertFalse(design.needsSchemaSix)
        design.objects.append(line(.zigzag))
        XCTAssertTrue(design.needsSchemaSix)
        design.objects = [RunObject(name: "Fill", nodes: [Point(0, 0), Point(10, 0), Point(10, 10)].map { PathNode($0) })]
        design.objects[0].closed = true; design.objects[0].digitizing = DigitizingSettings(kind: .fill); design.objects[0].digitizing?.fillStyle = .stipple
        XCTAssertTrue(design.needsSchemaSix)
        design.objects[0].digitizing?.fillStyle = .gradient
        XCTAssertTrue(design.needsSchemaSix)
        design.schemaVersion = 6
        XCTAssertNoThrow(try design.validate())
    }
}
