// Edit Nodes (H): a click on a selected object's edge adds a corner node (holding and dragging pulls it into place,
// one undo step), a right-click adds a curve node, and right-clicking a node still switches its type.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class NodeClickTests: XCTestCase {
    @MainActor func testClickAddsCornerAndRightClickAddsCurveNode() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        document.undoManager?.groupsByEvent = false
        func mouse(_ type: NSEvent.EventType, _ p: Point) {
            let event = NSEvent.mouseEvent(with: type, location: canvas.screen(p), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            document.undoManager?.beginUndoGrouping()
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            case .rightMouseDown: canvas.rightMouseDown(with: event)
            default: canvas.mouseUp(with: event)
            }
            document.undoManager?.endUndoGrouping()
        }
        var square = RunObject(name: "Square", nodes: [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)].map { PathNode($0) })
        square.closed = true; square.digitizing = DigitizingSettings(kind: .fill)
        document.undoManager?.beginUndoGrouping(); state.edit("Add Square") { $0.objects = [square] }; document.undoManager?.endUndoGrouping()
        state.selection = [square.id]; state.tool = .node; state.snap = false
        var nodes: [PathNode] { state.design.objects[0].nodes }

        // A click on the bottom edge: a corner node right there, as one undo step.
        mouse(.leftMouseDown, Point(4, -10)); mouse(.leftMouseUp, Point(4, -10))
        XCTAssertEqual(nodes.count, 5)
        XCTAssertEqual(nodes[1].point.x, 4, accuracy: 0.01); XCTAssertEqual(nodes[1].point.y, -10, accuracy: 0.01); XCTAssertFalse(nodes[1].smooth)
        document.undoManager?.undo(); XCTAssertEqual(nodes.count, 4)

        // Press on the edge and drag: the new node follows, saved as one step.
        mouse(.leftMouseDown, Point(-4, -10)); mouse(.leftMouseDragged, Point(-4, -14)); mouse(.leftMouseUp, Point(-4, -14))
        XCTAssertEqual(nodes.count, 5); XCTAssertEqual(nodes[1].point.y, -14, accuracy: 0.01)
        document.undoManager?.undo(); XCTAssertEqual(nodes.count, 4, "one undo takes the dragged node away")

        // Right-click on the right edge: a curve node; right-clicking it again switches it to a corner.
        mouse(.rightMouseDown, Point(10, 3))
        XCTAssertEqual(nodes.count, 5); XCTAssertTrue(nodes[2].smooth); XCTAssertEqual(nodes[2].point.y, 3, accuracy: 0.01)
        mouse(.rightMouseDown, Point(10, 3)); XCTAssertFalse(nodes[2].smooth)

        // Inside the fill, away from its edges, a press doesn't add a node.
        mouse(.leftMouseDown, Point(0, 0)); mouse(.leftMouseUp, Point(0, 0))
        XCTAssertEqual(nodes.count, 5)
    }
}
