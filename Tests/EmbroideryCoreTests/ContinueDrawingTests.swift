// Checks Continue drawing's rules: which objects can be carried on, the points that pick them up at each end, and
// turning a path around (twice gives it back; a satin keeps its rails on the same sides).
import XCTest
@testable import EmbroideryCore

final class ContinueDrawingTests: XCTestCase {
    private func object(_ kind: StitchKind, _ points: [Point], closed: Bool = false) -> RunObject {
        var o = RunObject(name: "Object", nodes: points.map { PathNode($0) }); o.closed = closed
        if kind != .run { o.digitizing = DigitizingSettings(kind: kind) }
        return o
    }
    private let column = [Point(0, 2), Point(0, -2), Point(10, 2), Point(10, -2), Point(20, 2), Point(20, -2)]

    func testOpenLinesAndColumnsCanBeContinued() {
        XCTAssertTrue(object(.run, [Point(0, 0), Point(10, 0)]).canContinueDrawing)
        XCTAssertTrue(object(.satin, column).canContinueDrawing)
        XCTAssertFalse(object(.run, [Point(0, 0), Point(10, 0), Point(5, 8)], closed: true).canContinueDrawing, "closed outline")
        XCTAssertFalse(object(.satin, column, closed: true).canContinueDrawing, "border")
        XCTAssertFalse(object(.fill, [Point(0, 0), Point(10, 0), Point(5, 8)], closed: true).canContinueDrawing)
        var locked = object(.run, [Point(0, 0), Point(10, 0)]); locked.locked = true
        XCTAssertFalse(locked.canContinueDrawing)
        var guide = object(.run, [Point(0, 0), Point(10, 0)]); guide.guideFor = UUID()
        XCTAssertFalse(guide.canContinueDrawing)
    }

    func testHandlesAreTheEndPointsOrEndPairs() {
        let line = object(.run, [Point(0, 0), Point(5, 5), Point(10, 0)]).continueHandles
        XCTAssertEqual(line.start, [Point(0, 0)]); XCTAssertEqual(line.end, [Point(10, 0)])
        let satin = object(.satin, column).continueHandles
        XCTAssertEqual(satin.start, [Point(0, 2), Point(0, -2)]); XCTAssertEqual(satin.end, [Point(20, 2), Point(20, -2)])
    }

    func testReversingTwiceGivesThePathBack() {
        let curved = [PathNode(Point(0, 0), smooth: true, outHandle: Point(2, 3)), PathNode(Point(10, 0), smooth: true, inHandle: Point(8, 3))]
        let reversed = RunObject.reversedPath(curved, satin: false)
        XCTAssertEqual(reversed.map(\.point), [Point(10, 0), Point(0, 0)])
        XCTAssertEqual(reversed[0].outHandle, Point(8, 3), "handles swap with the direction")
        XCTAssertEqual(RunObject.reversedPath(reversed, satin: false), curved)

        let nodes = column.map { PathNode($0) }
        let backwards = RunObject.reversedPath(nodes, satin: true)
        XCTAssertEqual(backwards.map(\.point), [Point(20, 2), Point(20, -2), Point(10, 2), Point(10, -2), Point(0, 2), Point(0, -2)],
                       "pairs in reverse, each keeping its left/right order")
        XCTAssertEqual(RunObject.reversedPath(backwards, satin: true), nodes)
    }
}
