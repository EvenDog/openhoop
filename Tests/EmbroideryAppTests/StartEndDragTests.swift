// A selected object's start and end markers can be dragged to move where it starts and ends sewing, with the
// Select tool, Edit Nodes and the Start & End tool alike, and each drag is one Undo step.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class StartEndDragTests: XCTestCase {
    @MainActor func testStartAndEndMarkersDragInEveryToolThatShowsThem() {
        _ = NSApplication.shared
        for tool in [Tool.select, .node, .entryExit] {
            let document = DesignDocument(), state = document.state
            let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
            state.snap = false
            var square = RunObject(name: "Square", nodes: [Point(0, 0), Point(30, 0), Point(30, 30), Point(0, 30)].map { PathNode($0) })
            square.closed = true; square.digitizing = DigitizingSettings(kind: .fill)
            square.entry = Point(6, 6); square.exit = Point(24, 24)
            state.edit("Add") { $0.objects = [square] }
            state.selection = [square.id]; state.tool = tool
            document.undoManager?.removeAllActions()   // in a test everything is one event; start the history here
            /// Presses at `from`, drags to `to` and lets go there (both in mm).
            func drag(_ from: Point, _ to: Point) {
                for (type, p) in [(NSEvent.EventType.leftMouseDown, from), (.leftMouseDragged, to), (.leftMouseUp, to)] {
                    let event = NSEvent.mouseEvent(with: type, location: canvas.screen(p), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
                }
            }
            drag(Point(6, 6), Point(10, 15))
            XCTAssertEqual(state.design.objects[0].entry?.x ?? 0, 10, accuracy: 0.01, "\(tool): the start follows the drag")
            XCTAssertEqual(state.design.objects[0].entry?.y ?? 0, 15, accuracy: 0.01, "\(tool)")
            drag(Point(24, 24), Point(20, 12))
            XCTAssertEqual(state.design.objects[0].exit?.x ?? 0, 20, accuracy: 0.01, "\(tool): the end follows the drag")
            XCTAssertEqual(state.design.objects[0].exit?.y ?? 0, 12, accuracy: 0.01, "\(tool)")
            XCTAssertEqual(state.design.objects[0].nodes.map(\.point), square.nodes.map(\.point), "\(tool): the shape itself doesn't move")
            document.undoManager?.undo()
            XCTAssertEqual(document.state.design.objects[0].exit, Point(24, 24), "\(tool): one Undo puts the end back")
        }
    }
}
