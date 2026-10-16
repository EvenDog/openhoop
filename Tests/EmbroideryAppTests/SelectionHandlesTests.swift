// Checks the handles round a selection (Select tool): a side handle stretches one way and a corner keeps the
// proportions, each from the opposite side, as one undoable step; and that a selected object's real start shows as a
// marker that can be dragged to set its start point.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class SelectionHandlesTests: XCTestCase {
    /// A canvas for `state`, and a way to press, drag and let go at screen points.
    @MainActor private func canvas(for state: EditorState) -> (DesignCanvas, (NSEvent.EventType, CGPoint, NSEvent.ModifierFlags) -> Void) {
        _ = NSApplication.shared
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        return (canvas, { type, p, flags in
            let event = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
        })
    }
    private func square() -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)].map { PathNode($0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    private func bounds(_ object: RunObject) -> (low: Point, high: Point) {
        let points = object.outlinePaths.flatMap { $0 }
        return (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
    }

    @MainActor func testHandlesResizeFromTheOppositeSide() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        let object = square()
        state.edit("Setup") { $0.objects = [object] }
        state.selection = [object.id]; state.tool = .select; state.snap = false
        let low = canvas.screen(Point(0, 0)), high = canvas.screen(Point(10, 10))

        // The right side's handle (6 points outside the box), dragged to x = 20: twice as wide, left side and height kept.
        mouse(.leftMouseDown, CGPoint(x: high.x + 6, y: (low.y + high.y) / 2), [])
        mouse(.leftMouseDragged, canvas.screen(Point(20, 5)), [])
        mouse(.leftMouseUp, canvas.screen(Point(20, 5)), [])
        var box = bounds(state.design.objects[0])
        XCTAssertEqual(box.low.x, 0, accuracy: 1e-6); XCTAssertEqual(box.high.x, 20, accuracy: 1e-6)
        XCTAssertEqual(box.high.y - box.low.y, 10, accuracy: 1e-6, "a side handle stretches one way only")
        XCTAssertEqual(document.undoManager?.undoActionName, "Resize Objects")

        // The top-right corner, dragged out by half: proportions kept, bottom-left corner stays put.
        let corner = canvas.screen(Point(20, 10))
        mouse(.leftMouseDown, CGPoint(x: corner.x + 6, y: corner.y + 6), [])
        mouse(.leftMouseDragged, canvas.screen(Point(30, 12)), [])
        mouse(.leftMouseUp, canvas.screen(Point(30, 12)), [])
        box = bounds(state.design.objects[0])
        XCTAssertEqual(box.low.x, 0, accuracy: 1e-6); XCTAssertEqual(box.low.y, 0, accuracy: 1e-6)
        XCTAssertEqual(box.high.x, 30, accuracy: 1e-6); XCTAssertEqual(box.high.y, 15, accuracy: 1e-6, "a corner keeps the proportions")
    }

    /// Without a start point set, the marker shows where the stitches really begin; dragging it sets the start point.
    @MainActor func testRealStartShowsAndCanBeDragged() async throws {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        let object = square()
        state.edit("Setup") { $0.objects = [object] }
        for _ in 0..<100 where state.busy || state.compiledRevision != state.revision { try await Task.sleep(nanoseconds: 50_000_000) }
        let first = try XCTUnwrap(state.plan.commands.first { $0.op == .stitch && $0.objectID == object.id }?.point)
        state.selection = [object.id]; state.tool = .select; state.snap = false
        mouse(.leftMouseDown, canvas.screen(first), [])
        mouse(.leftMouseDragged, canvas.screen(Point(5, 5)), [])
        mouse(.leftMouseUp, canvas.screen(Point(5, 5)), [])
        XCTAssertEqual(state.design.objects[0].entry, Point(5, 5), "dragging the real start sets the start point")
        XCTAssertEqual(bounds(state.design.objects[0]).high.x, 10, accuracy: 1e-6, "the object itself didn't move")
    }
}
