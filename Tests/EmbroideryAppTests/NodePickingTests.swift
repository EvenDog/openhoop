// Checks which node Edit Nodes grabs: the one under the pointer (not the one nearest the snapped point), and the
// selected object's nodes before any other object's.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class NodePickingTests: XCTestCase {
    /// A canvas for `state`, and a way to send it mouse presses, drags and releases at model points (mm).
    @MainActor private func canvas(for state: EditorState) -> (DesignCanvas, (NSEvent.EventType, Point) -> Void) {
        _ = NSApplication.shared
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        return (canvas, { type, p in
            let event = NSEvent.mouseEvent(with: type, location: canvas.screen(p), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
        })
    }

    /// With Snap on, a press at 0.6 mm snaps to 1 mm, which is nearer the node at 1.2 mm. The node under the pointer
    /// (at 0.4 mm) is the one that moves.
    @MainActor func testSnapDoesNotPickANeighbouringNode() {
        let document = DesignDocument(), state = document.state
        let (_, mouse) = canvas(for: state)
        let line = RunObject(name: "Line", nodes: [PathNode(Point(0.4, 0)), PathNode(Point(1.2, 0)), PathNode(Point(1.2, 5))])
        state.edit("Setup") { $0.objects = [line] }
        state.selection = [line.id]; state.tool = .node; state.snap = true
        mouse(.leftMouseDown, Point(0.6, 0)); mouse(.leftMouseDragged, Point(0.6, 3)); mouse(.leftMouseUp, Point(0.6, 3))
        XCTAssertEqual(state.design.objects[0].nodes[0].point, Point(0.4, 3), "the node under the pointer moved")
        XCTAssertEqual(state.design.objects[0].nodes[1].point, Point(1.2, 0), "its neighbour stayed")
    }

    /// Another object's node nearer the pointer doesn't steal the press from the selected object's node; with no
    /// selected node in reach, another object's node is still grabbed (and that object selected).
    @MainActor func testSelectedObjectsNodesComeFirst() {
        let document = DesignDocument(), state = document.state
        let (_, mouse) = canvas(for: state)
        let selected = RunObject(name: "Selected", nodes: [PathNode(Point(0, 0)), PathNode(Point(0, 10))])
        let other = RunObject(name: "Other", nodes: [PathNode(Point(0.3, 0)), PathNode(Point(20, 0))])
        state.edit("Setup") { $0.objects = [selected, other] }
        state.selection = [selected.id]; state.tool = .node; state.snap = false
        mouse(.leftMouseDown, Point(0.4, 0)); mouse(.leftMouseDragged, Point(0.4, 2)); mouse(.leftMouseUp, Point(0.4, 2))
        XCTAssertEqual(state.selection, [selected.id])
        XCTAssertEqual(state.design.objects[0].nodes[0].point, Point(0, 2), "the selected object's node moved")
        XCTAssertEqual(state.design.objects[1].nodes[0].point, Point(0.3, 0), "the other object's nearer node stayed")
        mouse(.leftMouseDown, Point(20, 0)); mouse(.leftMouseDragged, Point(20, 1)); mouse(.leftMouseUp, Point(20, 1))
        XCTAssertEqual(state.selection, [other.id], "far from the selected object, another object's node is grabbed")
        XCTAssertEqual(state.design.objects[1].nodes[1].point, Point(20, 1))
    }
}
