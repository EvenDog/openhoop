// Join Lines: open lines (or satin columns) become one, nearest ends first, turned round where needed; touching ends
// share a point, gaps are bridged; the one sewn first keeps its settings, place and direction; mixed or closed
// objects are refused without changing anything.
import XCTest
@testable import EmbroideryCore

final class JoinLinesTests: XCTestCase {
    private func line(_ name: String, _ points: [Point]) -> RunObject {
        var o = RunObject(name: name, nodes: points.map { PathNode($0) }, color: ThreadColor.palette[name == "A" ? 1 : 3])
        o.digitizing = DigitizingSettings(kind: .run); o.stitchLength = name == "A" ? 2 : 3
        return o
    }

    func testLinesJoinNearestEndsFirstTurnedRoundWhereNeeded() throws {
        // Sewing order A, C, B. A runs right; B (drawn backwards) carries on from A's end with a 2 mm gap; C touches B's far end.
        let a = line("A", [Point(0, 0), Point(10, 0)]), b = line("B", [Point(22, 0), Point(12, 0)]), c = line("C", [Point(22, 0), Point(30, 5)])
        var design = Design(); design.objects = [a, c, b, line("Other", [Point(0, 50), Point(10, 50)])]
        let id = try design.joinLines([a.id, b.id, c.id])
        XCTAssertEqual(id, a.id)
        XCTAssertEqual(design.objects.map(\.name), ["A", "Other"], "B and C are gone; A keeps its place")
        XCTAssertEqual(design.objects[0].nodes.map(\.point), [Point(0, 0), Point(10, 0), Point(12, 0), Point(22, 0), Point(30, 5)],
                       "the 2 mm gap is bridged, B is turned round, and B and C's touching ends are one point")
        XCTAssertEqual(design.objects[0].color, a.color); XCTAssertEqual(design.objects[0].stitchLength, 2, "A's settings")
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 10)
    }

    func testALineNearTheFirstOnesStartGoesInFront() throws {
        let a = line("A", [Point(10, 0), Point(20, 0)]), b = line("B", [Point(0, 0), Point(9, 0)])
        var design = Design(); design.objects = [a, b]
        _ = try design.joinLines([a.id, b.id])
        XCTAssertEqual(design.objects[0].nodes.map(\.point), [Point(0, 0), Point(9, 0), Point(10, 0), Point(20, 0)], "A still runs left to right")
    }

    func testSatinColumnsJoinIntoOneColumn() throws {
        func column(_ name: String, from y0: Double, to y1: Double) -> RunObject {
            var o = RunObject(name: name, nodes: [Point(0, y0), Point(4, y0), Point(0, y1), Point(4, y1)].map { PathNode($0) })
            o.digitizing = DigitizingSettings(kind: .satin)
            return o
        }
        let a = column("A", from: 0, to: 10), b = column("B", from: 25, to: 15)   // B runs the other way, 5 mm on
        var design = Design(); design.objects = [a, b]
        _ = try design.joinLines([a.id, b.id])
        XCTAssertEqual(design.objects.count, 1)
        XCTAssertEqual(design.objects[0].nodes.map(\.point), [Point(0, 0), Point(4, 0), Point(0, 10), Point(4, 10), Point(0, 15), Point(4, 15), Point(0, 25), Point(4, 25)],
                       "one column, B's pairs turned round, the rails kept on their sides")
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 50, "the column carries on across the gap")
    }

    func testMixedClosedOrSingleSelectionsAreRefusedUnchanged() {
        let a = line("A", [Point(0, 0), Point(10, 0)])
        var closed = line("Ring", [Point(0, 5), Point(10, 5), Point(5, 10)]); closed.closed = true
        var column = RunObject(name: "Column", nodes: [Point(0, 20), Point(4, 20), Point(0, 30), Point(4, 30)].map { PathNode($0) })
        column.digitizing = DigitizingSettings(kind: .satin)
        var design = Design(); design.objects = [a, closed, column]
        let before = design
        XCTAssertThrowsError(try design.joinLines([a.id]))
        XCTAssertThrowsError(try design.joinLines([a.id, closed.id]))
        XCTAssertThrowsError(try design.joinLines([a.id, column.id]))
        XCTAssertEqual(design, before)
    }
}
