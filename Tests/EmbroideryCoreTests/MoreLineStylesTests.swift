// Checks the line styles added in file version 21 (chain, feather, cross stitch, herringbone, ladder, candlewick):
// each stays beside its line at its width and covers it end to end in sewable stitches, each has the shape its name
// says, and a design using one is saved as version 21.
import XCTest
@testable import EmbroideryCore

final class MoreLineStylesTests: XCTestCase {
    private let newStyles: [RunStyle] = [.chain, .feather, .crossStitch, .herringbone, .ladder, .candlewick]

    /// A straight 30 mm line along the x axis with `style`.
    private func line(_ style: RunStyle, width: Double? = nil, spacing: Double? = nil) -> RunObject {
        var object = RunObject(name: "Line", nodes: [Point(0, 0), Point(30, 0)].map { PathNode($0) })
        object.digitizing = DigitizingSettings(kind: .run); object.digitizing?.runStyle = style
        object.digitizing?.runWidth = width; object.digitizing?.runSpacing = spacing
        return object
    }
    private func stitches(_ object: RunObject) throws -> [Point] { try StitchEngine.fresh(object, under: []).sections.flatMap(\.points) }

    func testEachStaysBesideItsLineEndToEndInSewableStitches() throws {
        for style in newStyles {
            let width = DigitizingSettings.defaultRunWidth(style)
            let points = try stitches(line(style))
            XCTAssertGreaterThan(points.count, 20, "\(style)")
            XCTAssertTrue(points.allSatisfy { abs($0.y) <= width / 2 + 1e-6 && $0.x >= -width / 2 - 1e-6 && $0.x <= 30 + width / 2 + 1e-6 }, "\(style) stays within its width")
            XCTAssertLessThan(points.map(\.x).min()!, 0.5, "\(style) starts at the line's start")
            XCTAssertGreaterThan(points.map(\.x).max()!, 29.5, "\(style) reaches the line's end")
            XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.distance(to: $1) <= 10 + 1e-9 }, "\(style) stitches at most 10 mm")
            // A closed line works too, and stays near its outline.
            var square = RunObject(name: "Square", nodes: [Point(0, 0), Point(30, 0), Point(30, 30), Point(0, 30)].map { PathNode($0) })
            square.closed = true; square.digitizing = DigitizingSettings(kind: .run); square.digitizing?.runStyle = style
            let round = try stitches(square)
            XCTAssertGreaterThan(round.count, 40, "\(style) on a closed line")
            XCTAssertTrue(round.allSatisfy { $0.x > -width && $0.x < 30 + width && $0.y > -width && $0.y < 30 + width }, "\(style) closed")
        }
    }

    /// Chain: no stitch runs through a loop's middle: the only stitches near the line itself are short steps in to
    /// where the next loop starts.
    func testChainLoopsHaveNoStitchThroughTheirMiddle() throws {
        let points = try stitches(line(.chain, width: 2, spacing: 3.5))
        let alongMiddle = zip(points, points.dropFirst()).filter { abs($0.y) < 0.05 && abs($1.y) < 0.05 && $0.distance(to: $1) > 0.3 }
        XCTAssertEqual(alongMiddle.count, 0)
        XCTAssertGreaterThan(points.filter { $0.y > 0.9 }.count, 10, "loops reach the left side")
        XCTAssertGreaterThan(points.filter { $0.y < -0.9 }.count, 10, "and the right")
    }

    /// Cross stitch: every point along the line has a stitch end on both sides, so the two zigzags make X's.
    func testCrossStitchZigzagsOutAndBackIntoXs() throws {
        let points = try stitches(line(.crossStitch, width: 2.5, spacing: 2.5))
        for k in 0...12 {
            let x = Double(k) * 2.5
            XCTAssertTrue(points.contains { abs($0.x - x) < 1e-6 && abs($0.y - 1.25) < 1e-6 }, "left at \(x)")
            XCTAssertTrue(points.contains { abs($0.x - x) < 1e-6 && abs($0.y + 1.25) < 1e-6 }, "right at \(x)")
        }
    }

    /// Herringbone: each slant crosses the one before it.
    func testHerringboneSlantsCross() throws {
        let points = try stitches(line(.herringbone, width: 3, spacing: 3))
        let slants = zip(points, points.dropFirst()).filter { abs($0.y - $1.y) > 2.9 }
        XCTAssertGreaterThan(slants.count, 10)
        for (a, b) in zip(slants, slants.dropFirst()) {
            // Two slants from opposite sides cross when the later one starts before the earlier one ends.
            XCTAssertLessThan(b.0.x, a.1.x, "slants cross")
        }
    }

    /// Ladder: both rails are sewn the whole way, with a rung every 2.5 mm.
    func testLadderHasBothRailsAndRungs() throws {
        let points = try stitches(line(.ladder, width: 3, spacing: 2.5))
        let pairs = zip(points, points.dropFirst())
        for k in 0..<12 {
            let from = Double(k) * 2.5, to = from + 2.5
            for side in [1.5, -1.5] {
                XCTAssertTrue(pairs.contains { abs($0.y - side) < 1e-6 && abs($1.y - side) < 1e-6 && Set([($0.x * 1000).rounded(), ($1.x * 1000).rounded()]) == Set([(from * 1000).rounded(), (to * 1000).rounded()]) },
                              "rail \(side) from \(from) to \(to)")
            }
            XCTAssertTrue(pairs.contains { abs($0.x - from) < 1e-6 && abs($1.x - from) < 1e-6 && abs($0.y - $1.y) > 2.9 }, "a rung at \(from)")
        }
    }

    /// Candlewick: a knot at each end and every 5 mm between (eight tiny stitches round each), joined by running stitch.
    func testCandlewickKnotsEveryFiveMillimeters() throws {
        let points = try stitches(line(.candlewick, width: 1.2, spacing: 5))
        for k in 0...6 {
            let center = Point(Double(k) * 5, 0)
            XCTAssertGreaterThanOrEqual(points.filter { $0.distance(to: center) < 1e-6 }.count, 9, "a knot at \(center.x)")
            XCTAssertEqual(points.filter { abs($0.distance(to: center) - 0.6) < 1e-6 }.count, 8, "its eight points round it")
        }
    }

    /// Feather: arms alternate from side to side.
    func testFeatherArmsAlternate() throws {
        let points = try stitches(line(.feather, width: 4, spacing: 2.5))
        let tips = points.filter { abs(abs($0.y) - 2) < 1e-6 }
        XCTAssertGreaterThan(tips.count, 8)
        XCTAssertTrue(zip(tips, tips.dropFirst()).allSatisfy { ($0.y > 0) != ($1.y > 0) }, "left, right, left…")
    }

    func testNewStylesSaveAsVersionTwentyOne() {
        var design = Design()
        for style in RunStyle.allCases {
            design.objects = [line(style)]
            XCTAssertEqual(design.needsSchemaTwentyOne, newStyles.contains(style), "\(style)")
        }
        XCTAssertEqual(RunStyle.addedInVersionTwentyOne, Set(newStyles))
        design.objects = [line(.chain)]; design.schemaVersion = 21
        XCTAssertNoThrow(try design.validate())
    }
}
