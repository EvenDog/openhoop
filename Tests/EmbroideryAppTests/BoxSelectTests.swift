// Select tool: dragging a box from empty canvas selects every object wholly inside it. Shift keeps the selection
// so far, an object only partly inside is left out, and a group is picked only when all of it is inside.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class BoxSelectTests: XCTestCase {
    private func square(_ x: Double, _ y: Double) -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(x, y), Point(x + 10, y), Point(x + 10, y + 10), Point(x, y + 10)].map { PathNode($0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }

    @MainActor func testDraggingABoxSelectsWhatIsWhollyInside() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        /// Presses at `from`, drags to `to` and lets go there (both in mm), with `flags` held.
        func drag(_ from: Point, _ to: Point, _ flags: NSEvent.ModifierFlags = []) {
            for (type, p) in [(NSEvent.EventType.leftMouseDown, from), (.leftMouseDragged, to), (.leftMouseUp, to)] {
                let event = NSEvent.mouseEvent(with: type, location: canvas.screen(p), modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
            }
        }
        let left = square(-30, 0), middle = square(-5, 0)
        var right = square(20, 0), rightTop = square(20, 15)
        let group = UUID(); right.groupID = group; rightTop.groupID = group
        state.edit("Setup") { $0.objects = [left, middle, right, rightTop] }
        state.tool = .select; state.snap = false

        // A box round the left square picks just that one.
        drag(Point(-33, -3), Point(-17, 13))
        XCTAssertEqual(state.selection, [left.id])

        // With Shift, a box round the middle square adds it.
        drag(Point(-8, -3), Point(8, 13), .shift)
        XCTAssertEqual(state.selection, [left.id, middle.id])

        // Without Shift, a new box starts again; the middle square, only half inside, is left out.
        drag(Point(-33, -3), Point(0, 13))
        XCTAssertEqual(state.selection, [left.id])

        // A box round one member of a group picks nothing; round the whole group, both members.
        drag(Point(17, -3), Point(33, 13))
        XCTAssertEqual(state.selection, [])
        drag(Point(17, -3), Point(33, 28))
        XCTAssertEqual(state.selection, [right.id, rightTop.id])

        // A plain click on empty canvas clears the selection.
        drag(Point(0, 40), Point(0, 40))
        XCTAssertEqual(state.selection, [])
    }
}
