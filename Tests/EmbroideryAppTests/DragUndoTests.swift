// Undo pressed while dragging: letting go of the mouse used to save the design as it was before the Undo (plus the
// drag), undoing the Undo. Now the drag is cancelled instead.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class DragUndoTests: XCTestCase {
    @MainActor func testUndoMidDragIsNotUndoneOnMouseUp() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        /// `saves`: letting go is expected to save the drag as an Undo step, which the test opens a group for (the app
        /// does that per event). A cancelled drag saves nothing, so it gets no group: an empty one would be undone next.
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint, saves: Bool = false) {
            let event = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default:
                if saves { document.undoManager?.beginUndoGrouping() }
                canvas.mouseUp(with: event)
                if saves { document.undoManager?.endUndoGrouping() }
            }
        }
        func square(_ name: String, at center: Point) -> RunObject {
            var object = RunObject(name: name, nodes: [Point(-5, -5), Point(5, -5), Point(5, 5), Point(-5, 5)].map { PathNode(center + $0) })
            object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
            return object
        }
        // Each edit is its own Undo step (in the app, each comes from a separate key press or click).
        document.undoManager?.groupsByEvent = false
        func step(_ name: String, _ object: RunObject) {
            document.undoManager?.beginUndoGrouping(); state.edit(name) { $0.objects.append(object) }; document.undoManager?.endUndoGrouping()
        }
        step("Add A", square("A", at: Point(0, 0)))
        step("Add B", square("B", at: Point(20, 0)))
        state.tool = .select
        let grab = canvas.screen(Point(0, 0))
        mouse(.leftMouseDown, grab); mouse(.leftMouseDragged, CGPoint(x: grab.x + 30, y: grab.y))
        document.undoManager?.undo()   // ⌘Z mid-drag: B goes
        XCTAssertEqual(state.design.objects.map(\.name), ["A"])
        mouse(.leftMouseDragged, CGPoint(x: grab.x + 60, y: grab.y)); mouse(.leftMouseUp, CGPoint(x: grab.x + 60, y: grab.y))
        XCTAssertEqual(state.design.objects.map(\.name), ["A"], "B stays undone")
        XCTAssertEqual(state.design.objects[0].nodes[0].point, Point(-5, -5), "the cancelled drag didn't move A")

        // Undo pressed and the mouse let go without moving again: still cancelled.
        mouse(.leftMouseDown, grab); mouse(.leftMouseDragged, CGPoint(x: grab.x + 30, y: grab.y))
        document.undoManager?.undo()   // A goes
        mouse(.leftMouseUp, CGPoint(x: grab.x + 30, y: grab.y))
        XCTAssertTrue(state.design.objects.isEmpty)

        // An ordinary drag still moves the object.
        step("Add C", square("C", at: Point(0, 0)))
        mouse(.leftMouseDown, grab); mouse(.leftMouseDragged, CGPoint(x: grab.x + 30, y: grab.y)); mouse(.leftMouseUp, CGPoint(x: grab.x + 30, y: grab.y), saves: true)
        XCTAssertGreaterThan(state.design.objects[0].nodes[0].point.x, -5)
    }
}
