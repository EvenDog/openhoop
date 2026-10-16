// Checks the Start/End tool on grouped objects such as a laydown's parts: with the group selected, a click sets the
// start (Option-click the end) of the part under the pointer, even under other objects; with nothing selected, a
// click picks one part, not its whole group.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class StartEndToolTests: XCTestCase {
    /// A square fill `size` mm across with its lower left corner at `corner`.
    private func square(_ name: String, at corner: Point, size: Double, group: UUID? = nil) -> RunObject {
        let points = [Point(0, 0), Point(size, 0), Point(size, size), Point(0, size)].map { PathNode(corner + $0) }
        var object = RunObject(name: name, nodes: points); object.closed = true; object.groupID = group
        object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }

    @MainActor func testStartAndEndGoOnOnePartOfAGroup() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func click(_ p: Point, option: Bool = false) {
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.screen(p), modifierFlags: option ? [.option] : [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            canvas.mouseDown(with: event)
        }
        // A laydown in two parts, and a design object sewn over the second part.
        let group = UUID()
        let left = square("Laydown", at: Point(-20, -10), size: 15, group: group), right = square("Laydown", at: Point(5, -10), size: 15, group: group)
        let top = square("Top", at: Point(6, -9), size: 10)
        state.edit("Setup") { $0.objects = [left, right, top] }
        state.tool = .entryExit; state.snap = false

        // With the whole laydown selected, a click on its second part (under Top) sets that part's start.
        state.selection = [left.id, right.id]
        click(Point(10, -5))
        XCTAssertEqual(state.selection, [right.id], "just the clicked part")
        XCTAssertEqual(state.design.objects[1].entry, Point(10, -5))
        XCTAssertNil(state.design.objects[0].entry, "the other part is left alone")
        XCTAssertNil(state.design.objects[2].entry, "the object on top is left alone")
        click(Point(18, -8), option: true)
        XCTAssertEqual(state.design.objects[1].exit, Point(18, -8), "Option-click sets the end")

        // With nothing selected, a click picks one part, not the whole group, and the next click sets its start.
        state.selection = []
        click(Point(-10, -5))
        XCTAssertEqual(state.selection, [left.id])
        click(Point(-12, -4))
        XCTAssertEqual(state.design.objects[0].entry, Point(-12, -4))
    }
}
