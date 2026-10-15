// Satin improvements: split wide satin, short stitches on curves, and satin from a center line.
import XCTest
@testable import EmbroideryCore

final class SatinToolsTests: XCTestCase {
    /// A straight satin column `width` mm wide and 30 mm long, drawn as two edge pairs.
    private func column(width: Double, settings: (inout DigitizingSettings) -> Void = { _ in }) -> RunObject {
        var o = RunObject(name: "Column", nodes: [Point(-15, width / 2), Point(-15, -width / 2), Point(15, width / 2), Point(15, -width / 2)].map { PathNode($0) })
        var s = DigitizingSettings(kind: .satin); s.underlay = .none; settings(&s); o.digitizing = s
        return o
    }
    private func line(_ points: [Point], closed: Bool = false) -> RunObject {
        var o = RunObject(name: "Line", nodes: points.map { PathNode($0) }); o.closed = closed
        o.digitizing = DigitizingSettings(kind: .run)
        return o
    }

    func testSplitBreaksLongStitchesIntoStaggeredBricks() {
        let points = [Point(0, 0), Point(25, 0), Point(0, 1), Point(4, 1)]
        let split = AreaEngine.splitLong(points, maximum: 10)
        XCTAssertTrue(zip(split, split.dropFirst()).allSatisfy { $0.distance(to: $1) <= 10.0001 })
        XCTAssertEqual(split.first, points.first); XCTAssertEqual(split.last, points.last)
        // First long stitch: breaks at 1/3 and 2/3. Second (going back): staggered by half a step, so 4 parts.
        XCTAssertEqual(split.filter { $0.y == 0 }.count, 4)
        XCTAssertEqual(split.count, 4 + 4 + 1 + 0, "2 breaks in the first, 3 in the second, none in the short last stitch")
        XCTAssertEqual(AreaEngine.splitLong([Point(0, 0), Point(5, 0)], maximum: 10), [Point(0, 0), Point(5, 0)])
    }

    func testWideSatinSewsWhenSplitAndIsRefusedOtherwise() throws {
        let wide = try AreaEngine.satin(column(width: 16))
        let stitches = wide.sections.flatMap(\.points)
        XCTAssertTrue(zip(stitches, stitches.dropFirst()).allSatisfy { $0.distance(to: $1) <= 10.0001 })
        XCTAssertThrowsError(try AreaEngine.satin(column(width: 16) { $0.autoSplit = nil }))
    }

    func testShortStitchesOnlyOnTheInsideOfCurves() {
        // A quarter ring: inner rail radius 3, outer radius 9.
        let pairs = (0...12).map { k -> (Point, Point) in
            let t = Double(k) / 12 * .pi / 2
            return (Point(cos(t), sin(t)) * 9, Point(cos(t), sin(t)) * 3)
        }
        let short = AreaEngine.shortened(pairs)
        XCTAssertEqual(short[0].1, pairs[0].1); XCTAssertEqual(short[12].1, pairs[12].1)
        XCTAssertEqual(short[1].1.distance(to: .init(0, 0)), 5, accuracy: 0.001, "Every other inner end moves a third of the way out")
        XCTAssertEqual(short[2].1, pairs[2].1)
        for (after, before) in zip(short, pairs) { XCTAssertEqual(after.0, before.0, "The outer ends never move") }
        let straight: [(Point, Point)] = (0...6).map { (Point(Double($0), 3), Point(Double($0), -3)) }
        let unchanged = AreaEngine.shortened(straight)
        for (after, before) in zip(unchanged, straight) { XCTAssertEqual(after.0, before.0); XCTAssertEqual(after.1, before.1) }
    }

    func testOlderSatinsSewAsBeforeAndNewOnesUseTheImprovements() throws {
        XCTAssertEqual(DigitizingSettings(kind: .satin).shortStitches, true)
        XCTAssertEqual(DigitizingSettings(kind: .satin).autoSplit, true)
        XCTAssertNil(DigitizingSettings(kind: .fill).shortStitches)
        let old = try JSONDecoder().decode(DigitizingSettings.self, from: Data(#"{"kind":"satin","spacing":0.4,"expansion":0.2,"angle":45,"maximumSatin":10,"underlay":"center","inset":0.4,"underlaySpacing":1.2}"#.utf8))
        XCTAssertNil(old.shortStitches); XCTAssertNil(old.autoSplit)
        var design = Design(); design.objects = [column(width: 3)]
        XCTAssertTrue(design.needsSchemaFive, "Older versions would sew these satins differently, so they must refuse the file")
        design.objects = [column(width: 3) { $0.shortStitches = nil; $0.autoSplit = nil; $0.pullPercent = nil }]
        XCTAssertFalse(design.needsSchemaFive)
    }

    func testCenterLineBecomesAnEvenColumn() throws {
        let satin = try SatinLine.column(from: line([Point(-20, 0), Point(20, 0)]), width: 3)
        XCTAssertEqual(satin.kind, .satin); XCTAssertEqual(satin.name, "Line")
        XCTAssertEqual(satin.nodes.count % 2, 0)
        XCTAssertLessThanOrEqual(satin.nodes.count / 2, 6, "A straight line needs only a few pairs (one at least every 10 mm)")
        for i in stride(from: 0, to: satin.nodes.count, by: 2) {
            let left = satin.nodes[i].point, right = satin.nodes[i + 1].point
            XCTAssertEqual(left.distance(to: right), 3, accuracy: 0.01)
            XCTAssertEqual((left.y + right.y) / 2, 0, accuracy: 0.01, "Centered on the line")
        }
        XCTAssertGreaterThan(try AreaEngine.satin(satin).sections.flatMap(\.points).count, 100)
    }

    func testSharpTurnsAreRoundedAndClosedLinesWork() throws {
        let corner = try SatinLine.column(from: line([Point(-20, 0), Point(0, 0), Point(0, 20)]), width: 4)
        XCTAssertNoThrow(try AreaEngine.satin(corner))
        let zigzag = try SatinLine.column(from: line([Point(-20, 0), Point(-10, 8), Point(0, 0), Point(10, 8), Point(20, 0)]), width: 2.5)
        XCTAssertNoThrow(try AreaEngine.satin(zigzag))
        let ring = try SatinLine.column(from: line([Point(-15, -15), Point(15, -15), Point(15, 15), Point(-15, 15)], closed: true), width: 3)
        XCTAssertTrue(ring.closed); XCTAssertNoThrow(try AreaEngine.satin(ring))
    }

    func testWhatCantBecomeASatinIsExplained() {
        var fill = line([Point(0, 0), Point(10, 0), Point(10, 10)], closed: true); fill.digitizing = DigitizingSettings(kind: .fill)
        XCTAssertFalse(SatinLine.canConvert(fill))
        XCTAssertThrowsError(try SatinLine.column(from: line([Point(0, 0), Point(0.5, 0)]), width: 3))
        XCTAssertThrowsError(try SatinLine.column(from: line([Point(0, 0), Point(10, 0)]), width: 12))
        // A hairpin turn tighter than the column can follow.
        XCTAssertThrowsError(try SatinLine.column(from: line([Point(0, 0), Point(20, 0), Point(0, 1)]), width: 6)) { error in
            XCTAssertTrue(error.localizedDescription.contains("doesn't fit"), error.localizedDescription)
        }
    }

    /// A Λ from a real design: a column up one leg, sharply over the top and down the other. The first stitches of the turn pass
    /// the inner corner's tip less than 0.02 mm outside the column, which is nothing on fabric, so it sews.
    func testSharpTurnWhoseStitchesGrazeTheInnerCornerSews() throws {
        let points = [(-10.44, -13.73), (-13.74, -13.68), (-9.27, 9.92), (-11.63, 13.5), (-8.82, 8.75), (-7.5, 13.37), (-1.36, -13.11), (0.38, -8.81)]
        var satin = RunObject(name: "Satin 1", nodes: points.map { PathNode(Point($0.0, $0.1)) }, color: ThreadColor.palette[0])
        satin.digitizing = DigitizingSettings(kind: .satin)
        XCTAssertNoThrow(try AreaEngine.satin(satin))
    }

    /// Stitches that really leave the column (here by about half a millimeter, over a dent in the right edge) are
    /// still refused.
    func testStitchesThatClearlyLeaveTheColumnAreStillRefused() {
        var satin = RunObject(name: "Dent", nodes: [Point(0, 0), Point(0, 10), Point(10, 0), Point(5, 1)].map { PathNode($0) }, color: ThreadColor.palette[0])
        satin.digitizing = DigitizingSettings(kind: .satin)
        XCTAssertThrowsError(try AreaEngine.satin(satin)) { XCTAssertTrue("\($0)".contains("crosses a rail"), "\($0)") }
    }

    /// Neighbouring stitches crossing in the middle are a twist; crossing near an end (a fan round a corner) isn't.
    func testOnlyACrossingInTheMiddleCountsAsATwist() {
        let stitch = (Point(0, 0), Point(4, 0))
        XCTAssertTrue(AreaEngine.crossInMiddle(stitch, (Point(1, -1), Point(3, 1))), "an X across the middle")
        XCTAssertFalse(AreaEngine.crossInMiddle(stitch, (Point(0.2, -1), Point(0.4, 3))), "crossing near the end, fanning")
        XCTAssertFalse(AreaEngine.crossInMiddle(stitch, (Point(0, 0.4), Point(4, 0.4))), "side by side")
    }
}
