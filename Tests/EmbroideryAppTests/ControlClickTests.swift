// Control-click (like Shift- and ⌘-click) adds an object to the selection or takes it out, on the canvas and in the
// sewing order list. In the list, a thin overlay catches only Control-clicks, so plain clicks, drags and right-clicks
// still reach the row.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ControlClickTests: XCTestCase {
    private func square(_ name: String, at center: Point) -> RunObject {
        var object = RunObject(name: name, nodes: [Point(-5, -5), Point(5, -5), Point(5, 5), Point(-5, 5)].map { PathNode(center + $0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    private func click(_ type: NSEvent.EventType = .leftMouseDown, at p: CGPoint = .zero, holding flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @MainActor func testControlClickAddsOnTheCanvas() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        let a = square("A", at: Point(0, 0)), b = square("B", at: Point(20, 0)), c = square("C", at: Point(-20, 0))
        state.edit("Add") { $0.objects = [a, b, c] }
        state.tool = .select
        func press(_ object: RunObject, _ flags: NSEvent.ModifierFlags) {
            let p = canvas.screen(object.nodes[0].point + Point(5, 5))   // the square's middle
            canvas.mouseDown(with: click(at: p, holding: flags)); canvas.mouseUp(with: click(.leftMouseUp, at: p, holding: flags))
        }
        press(a, [])
        XCTAssertEqual(state.selection, [a.id])
        press(b, .control)
        XCTAssertEqual(state.selection, [a.id, b.id], "Control-click adds")
        press(c, .command)
        XCTAssertEqual(state.selection, [a.id, b.id, c.id], "⌘-click adds too")
        press(b, .control)
        XCTAssertEqual(state.selection, [a.id, c.id], "Control-clicking a selected object takes it out")
        press(b, .shift)
        XCTAssertEqual(state.selection, [a.id, b.id, c.id], "Shift-click still adds")
        press(a, [])
        XCTAssertEqual(state.selection, [a.id, b.id, c.id], "a plain click on a selected object keeps the selection, to drag it")
    }

    @MainActor func testControlClickAddsInTheList() {
        let state = EditorState()
        let a = square("A", at: Point(0, 0)), b = square("B", at: Point(20, 0))
        state.design.objects = [a, b]
        state.listClick(a.id, flags: [])
        state.listClick(b.id, flags: .control)
        XCTAssertEqual(state.selection, [a.id, b.id], "Control-click adds a row")
        state.listClick(a.id, flags: .control)
        XCTAssertEqual(state.selection, [b.id], "and takes a selected one out")
        state.listClick(a.id, flags: [])
        XCTAssertEqual(state.selection, [a.id], "a plain click selects just that row")
    }

    func testTheListOverlayCatchesOnlyControlClicks() {
        typealias Catcher = ControlClickCatcher.CatcherView
        XCTAssertTrue(Catcher.catches(click(holding: .control)))
        XCTAssertFalse(Catcher.catches(click(holding: [])), "a plain click reaches the row")
        XCTAssertFalse(Catcher.catches(click(holding: .command)), "so does ⌘-click")
        XCTAssertFalse(Catcher.catches(click(.rightMouseDown, holding: .control)), "and a right-click, for the row's menu")
        XCTAssertFalse(Catcher.catches(nil))
    }
}
