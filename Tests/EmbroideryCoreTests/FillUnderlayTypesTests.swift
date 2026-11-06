// Double tatami and zigzag underlay for fills: double tatami sews tatami rows and then the same rows turned 90°, so
// the two passes cross; a zigzag swings from edge to edge across the shape. Also checks they're only allowed on
// fills, that files using them are saved as version 18, and the plain names Edge run and Zigzag.
import XCTest
@testable import EmbroideryCore

final class FillUnderlayTypesTests: XCTestCase {
    /// A 30 × 20 mm rectangle fill with its rows at 0° (along x), so underlay at the default 90° runs up and down.
    private func patch(_ first: UnderlayStyle, _ second: UnderlayStyle? = nil) -> RunObject {
        var o = RunObject(name: "Patch", nodes: [Point(0, 0), Point(30, 0), Point(30, 20), Point(0, 20)].map { PathNode($0) })
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill)
        o.digitizing?.angle = 0; o.digitizing?.underlay = first; o.digitizing?.secondUnderlay = second
        return o
    }

    /// The underlay's stitches (needle point to needle point), each section on its own.
    private func underlayStitches(_ object: RunObject) throws -> [(Point, Point)] {
        try AreaEngine.fill(object).sections.filter(\.underlay).flatMap { zip($0.points, $0.points.dropFirst()).map { ($0, $1) } }
    }

    func testDoubleTatamiCrossesItsOwnRows() throws {
        // The rows' stitches are the long ones; the short steps between rows are only the spacing (1.2 mm).
        let long = try underlayStitches(patch(.doubleTatami)).filter { $0.0.distance(to: $0.1) > 1.3 }
        let upAndDown = long.filter { abs($0.0.x - $0.1.x) < 0.01 }.count, across = long.filter { abs($0.0.y - $0.1.y) < 0.01 }.count
        XCTAssertGreaterThan(upAndDown, 0, "The first pass at 90° from the fill runs up and down")
        XCTAssertGreaterThan(across, 0, "The second pass, turned 90°, runs along the fill")
        XCTAssertEqual(upAndDown + across, long.count, "Nothing else")
        // A single tatami underlay sews only the first pass.
        let single = try underlayStitches(patch(.tatami)).filter { $0.0.distance(to: $0.1) > 1.3 }
        XCTAssertTrue(single.allSatisfy { abs($0.0.x - $0.1.x) < 0.01 })
    }

    func testZigzagSwingsFromEdgeToEdge() throws {
        let stitches = try underlayStitches(patch(.zigzag))
        let points = stitches.flatMap { [$0.0, $0.1] }
        XCTAssertFalse(points.isEmpty)
        // Inside the shape, 0.4 mm in (the inset), and reaching across it both ways.
        XCTAssertTrue(points.allSatisfy { (0.39...29.61).contains($0.x) && (0.39...19.61).contains($0.y) }, "Inside the inset outline")
        XCTAssertLessThan(points.map(\.y).min()!, 0.5); XCTAssertGreaterThan(points.map(\.y).max()!, 19.5)
        XCTAssertLessThan(points.map(\.x).min()!, 1.5); XCTAssertGreaterThan(points.map(\.x).max()!, 28.5)
        // The 19.2 mm swings are split, so no stitch is longer than a satin fill's split length.
        XCTAssertLessThanOrEqual(stitches.map { $0.0.distance(to: $0.1) }.max()!, DigitizingSettings.defaultSatinSplit + 0.0001)
        // Wider spacing, fewer swings.
        var sparse = patch(.zigzag); sparse.digitizing?.setUnderlay(1, spacing: 3)
        XCTAssertLessThan(try underlayStitches(sparse).count, stitches.count)
    }

    func testOnlyFillsHaveThemAndTheyNeedVersion18() throws {
        var design = Design()
        design.objects = [patch(.edge, .doubleTatami), patch(.zigzag, .edge)]
        XCTAssertNoThrow(try design.validate())
        XCTAssertTrue(design.needsSchemaEighteen)
        // A satin's zigzag is older, so it doesn't need version 18; and satins can't have double tatami.
        var column = RunObject(name: "Column", nodes: [Point(-15, 2), Point(-15, -2), Point(15, 2), Point(15, -2)].map { PathNode($0) })
        column.digitizing = DigitizingSettings(kind: .satin); column.digitizing?.underlay = .zigzag
        design.objects = [column, patch(.edge, .tatami)]
        XCTAssertFalse(design.needsSchemaEighteen)
        column.digitizing?.underlay = .doubleTatami
        design.objects = [column]
        XCTAssertThrowsError(try design.validate(), "Double tatami is for fills only")
    }

    func testPlainNames() {
        XCTAssertEqual(UnderlayStyle.edge.title, "Edge run")
        XCTAssertEqual(UnderlayStyle.zigzag.title, "Zigzag")
        XCTAssertEqual(UnderlayStyle.doubleTatami.title, "Double tatami")
        XCTAssertEqual(UnderlayStyle.fillTypes, [.none, .edge, .tatami, .doubleTatami, .zigzag])
    }
}
