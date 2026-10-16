// Checks switching a point between corner and smooth: the selected point changes (a corner loses its handles), as one
// undoable step, and a right-click switches the point under the pointer even with Snap on.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class NodeTypeTests: XCTestCase {
    @MainActor func testSelectedPointSwitchesBetweenCornerAndSmooth() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var curve = PathNode(Point(10, 5), smooth: true); curve.outHandle = Point(14, 8); curve.inHandle = Point(6, 2)
        let line = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), curve, PathNode(Point(20, 0))])
        state.edit("Setup") { $0.objects = [line] }
        state.tool = .node; state.selection = [line.id]
        state.selectedNode = NodeLocation(object: line.id, ring: -1, index: 1)

        state.setSelectedNode(smooth: false)
        XCTAssertEqual(state.selectedPathNode?.smooth, false)
        XCTAssertNil(state.selectedPathNode?.outHandle, "a corner has no handles")
        XCTAssertTrue(state.status.hasPrefix("Corner point"), state.status)
        state.setSelectedNode(smooth: true)
        XCTAssertEqual(state.selectedPathNode?.smooth, true)
        XCTAssertTrue(state.status.hasPrefix("Smooth point"), state.status)
        XCTAssertEqual(document.undoManager?.undoActionName, "Make Smooth Point", "each switch is an undoable step")

        state.selectedNode = nil
        state.setSelectedNode(smooth: true)
        XCTAssertTrue(state.status.contains("click a point first"), state.status)
    }

    /// With Snap on, a right-click at 0.6 mm snaps to 1 mm, nearer the point at 1.2 mm; the point under the pointer
    /// (at 0.4 mm) is the one that switches.
    @MainActor func testRightClickSwitchesThePointUnderThePointer() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        let line = RunObject(name: "Line", nodes: [PathNode(Point(0.4, 0)), PathNode(Point(1.2, 0)), PathNode(Point(1.2, 5))])
        state.edit("Setup") { $0.objects = [line] }
        state.selection = [line.id]; state.tool = .node; state.snap = true
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: canvas.screen(Point(0.6, 0)), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        canvas.rightMouseDown(with: event)
        XCTAssertEqual(state.design.objects[0].nodes[0].smooth, true, "the point under the pointer switched")
        XCTAssertEqual(state.design.objects[0].nodes[1].smooth, false, "its neighbour didn't")
    }
}
