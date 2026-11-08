// Which of Weld, Remove Overlaps and Join Lines suit a selection, so Properties offers only those buttons: each check
// says yes exactly when its command would do something.
import XCTest
@testable import EmbroideryCore

final class SelectionActionsTests: XCTestCase {
    private func square(_ x: Double) -> RunObject {
        var fill = RunObject(name: "Square", nodes: ShapeGeometry.nodes(.rectangle, in: (Point(x, 0), Point(x + 10, 10))))
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        return fill
    }
    private func line(_ y: Double) -> RunObject { RunObject(name: "Line", nodes: [PathNode(Point(0, y)), PathNode(Point(20, y))]) }
    private func satin(_ y: Double) -> RunObject {
        var column = RunObject(name: "Satin", nodes: [PathNode(Point(0, y)), PathNode(Point(0, y + 3)), PathNode(Point(20, y)), PathNode(Point(20, y + 3))])
        column.digitizing = DigitizingSettings(kind: .satin)
        return column
    }

    func testFillsCanBeWeldedAndCutButNotJoined() {
        var design = Design(); design.objects = [square(0), square(5)]
        let ids = Set(design.objects.map(\.id))
        XCTAssertTrue(design.canWeld(ids)); XCTAssertTrue(design.canRemoveOverlaps(ids)); XCTAssertFalse(design.canJoinLines(ids))
    }

    func testLinesCanBeJoinedButNotWeldedOrCut() {
        var design = Design(); design.objects = [line(0), line(5), line(10)]
        let ids = Set(design.objects.map(\.id))
        XCTAssertTrue(design.canJoinLines(ids)); XCTAssertFalse(design.canWeld(ids)); XCTAssertFalse(design.canRemoveOverlaps(ids))
        XCTAssertNoThrow(try design.joinLines(ids), "the check agrees with the command")
    }

    func testSatinsJoinWithSatinsButNotWithLines() {
        var design = Design(); design.objects = [satin(0), satin(10), line(20)]
        let satins = Set(design.objects.prefix(2).map(\.id)), all = Set(design.objects.map(\.id))
        XCTAssertTrue(design.canJoinLines(satins))
        XCTAssertFalse(design.canJoinLines(all), "lines and satins can't be joined at once")
    }

    func testMixedOrLockedSelections() {
        var design = Design(); design.objects = [square(0), line(20)]
        let mixed = Set(design.objects.map(\.id))
        XCTAssertFalse(design.canWeld(mixed), "one fill alone has nothing to weld to")
        XCTAssertTrue(design.canRemoveOverlaps(mixed), "a fill is selected")
        XCTAssertFalse(design.canJoinLines(mixed))
        design.objects = [square(0), square(5)]; design.objects[1].locked = true
        let locked = Set(design.objects.map(\.id))
        XCTAssertFalse(design.canWeld(locked), "a locked fill isn't welded")
        XCTAssertTrue(design.canRemoveOverlaps(locked))
    }
}
