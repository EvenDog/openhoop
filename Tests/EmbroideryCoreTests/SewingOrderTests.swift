// Rearranging the sewing order: dragging objects to a new place in the list (never into the middle of a group,
// lettering or branch), and Sequence by Color, which gathers each thread's objects together.
import XCTest
@testable import EmbroideryCore

final class SewingOrderTests: XCTestCase {
    /// A design of small lines named by `names`, in that order, with `colors` (palette indexes) if given.
    private func design(_ names: [String], colors: [Int]? = nil) -> Design {
        var design = Design()
        design.objects = names.enumerated().map { index, name in
            var object = RunObject(name: name, nodes: [Point(Double(index), 0), Point(Double(index), 5)].map { PathNode($0) })
            if let colors { object.color = ThreadColor.palette[colors[index]] }
            return object
        }
        return design
    }
    private func names(_ design: Design) -> String { design.objects.map(\.name).joined() }
    private func ids(_ design: Design, _ names: String) -> Set<UUID> { Set(design.objects.filter { names.contains($0.name) }.map(\.id)) }

    func testDraggingMovesTheSelectionBeforeTheObjectDroppedOn() {
        var d = design(["A", "B", "C", "D", "E"])
        XCTAssertTrue(d.moveInSewingOrder(ids(d, "D"), to: 1)); XCTAssertEqual(names(d), "ADBCE", "before B")
        XCTAssertTrue(d.moveInSewingOrder(ids(d, "A"), to: 5)); XCTAssertEqual(names(d), "DBCEA", "to the end")
        XCTAssertTrue(d.moveInSewingOrder(ids(d, "CA"), to: 0)); XCTAssertEqual(names(d), "CADBE", "two at once, keeping their order")
        XCTAssertFalse(d.moveInSewingOrder(ids(d, "D"), to: 3), "dropped where it already is")
        XCTAssertFalse(d.moveInSewingOrder(ids(d, "D"), to: 2), "or just before itself")
    }

    func testADropInsideAGroupLandsAfterIt() {
        var d = design(["A", "B", "C", "D"])
        let group = UUID(); d.objects[1].groupID = group; d.objects[2].groupID = group   // B and C are grouped
        XCTAssertTrue(d.moveInSewingOrder(ids(d, "A"), to: 2))
        XCTAssertEqual(names(d), "BCAD", "between B and C would split the group, so A goes after it")
    }

    func testSequenceByColorGathersEachThreadKeepingGroupsWhole() {
        // Colors 0 1 0 2 1 0; C and D are grouped, so D (color 2) travels with C (color 0).
        var d = design(["A", "B", "C", "D", "E", "F"], colors: [0, 1, 0, 2, 1, 0])
        let group = UUID(); d.objects[2].groupID = group; d.objects[3].groupID = group
        XCTAssertTrue(d.sequenceByColor())
        XCTAssertEqual(names(d), "ACDFBE", "color 0 (with its group), then color 1")
        XCTAssertFalse(d.sequenceByColor(), "already in color order")
    }
}
