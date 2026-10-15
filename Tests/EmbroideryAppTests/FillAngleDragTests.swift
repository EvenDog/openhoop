// Edit Nodes (H) on a tatami fill shows its stitch angle as a line; dragging an end turns the stitches, as one undo
// step.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class FillAngleDragTests: XCTestCase {
    @MainActor func testDraggingTheAngleLineEndTurnsTheFill() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
        }
        var fill = RunObject(name: "Box", nodes: [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)   // 45°, the default
        document.undoManager?.groupsByEvent = false
        document.undoManager?.beginUndoGrouping(); state.edit("Add Box") { $0.objects.append(fill) }; document.undoManager?.endUndoGrouping()
        state.selection = [fill.id]; state.tool = .node

        // Grab the line's upper end and swing it round to straight up from the middle.
        let ends = try XCTUnwrap(StitchAngleLine.ends(of: state.design.objects[0]))
        mouse(.leftMouseDown, canvas.screen(ends.1))
        mouse(.leftMouseDragged, canvas.screen(Point(5, 20)))
        mouse(.leftMouseDragged, canvas.screen(Point(0, 20)))
        XCTAssertEqual(state.design.objects[0].settings.angle, 45, "nothing is saved until the mouse is let go")
        document.undoManager?.beginUndoGrouping(); mouse(.leftMouseUp, canvas.screen(Point(0, 20))); document.undoManager?.endUndoGrouping()
        XCTAssertEqual(state.design.objects[0].settings.angle, 90)
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point), fill.nodes.map(\.point), "the nodes didn't move")
        document.undoManager?.undo()
        XCTAssertEqual(state.design.objects[0].settings.angle, 45, "one undo puts the angle back")

        // A press on a node still grabs the node, not the line.
        state.tool = .node
        mouse(.leftMouseDown, canvas.screen(Point(10, 10))); mouse(.leftMouseDragged, canvas.screen(Point(12, 12)))
        document.undoManager?.beginUndoGrouping(); mouse(.leftMouseUp, canvas.screen(Point(12, 12))); document.undoManager?.endUndoGrouping()
        XCTAssertEqual(state.design.objects[0].settings.angle, 45)
        XCTAssertEqual(state.design.objects[0].nodes[2].point, Point(12, 12))
    }
}
