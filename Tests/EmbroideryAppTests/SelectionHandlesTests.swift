// Checks the handles round a selection (Select tool): a side handle stretches one way and a corner keeps the
// proportions, each from the opposite side, as one undoable step; just outside a corner rotates, and clicking the
// selection again turns the side handles into skew handles; and a selected object's real start shows as a marker
// that can be dragged to set its start point.
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

    /// Just outside a corner, a drag turns the selection round the middle of its box (the corner square itself still
    /// resizes). Clicking the selected object again turns the side handles into skew handles: the top one then leans
    /// it sideways with the bottom side staying put. Clicking again, or selecting something else, brings back the
    /// stretch handles.
    @MainActor func testOutsideACornerRotatesAndClickingAgainSkews() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        let object = square()
        state.edit("Setup") { $0.objects = [object] }
        state.selection = [object.id]; state.tool = .select; state.snap = false

        // From just outside the top-right corner, swung a quarter turn counterclockwise: (0, 0) goes to (10, 0).
        let topRight = canvas.screen(Point(10, 10)), topLeft = canvas.screen(Point(0, 10))
        mouse(.leftMouseDown, CGPoint(x: topRight.x + 16, y: topRight.y + 16), [])
        mouse(.leftMouseDragged, CGPoint(x: topLeft.x - 16, y: topLeft.y + 16), [])
        mouse(.leftMouseUp, CGPoint(x: topLeft.x - 16, y: topLeft.y + 16), [])
        XCTAssertEqual(state.design.objects[0].nodes[0].point.distance(to: Point(10, 0)), 0, accuracy: 1e-6)
        XCTAssertEqual(document.undoManager?.undoActionName, "Rotate Objects")

        mouse(.leftMouseDown, canvas.screen(Point(5, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(5, 5)), [])
        XCTAssertTrue(state.skewHandles, "a click on what's already selected switches the sides to skew handles")

        // The top side's handle dragged 10 mm right on a 10 mm tall square: 45°, the bottom side stays put.
        let top = canvas.screen(Point(5, 10))
        mouse(.leftMouseDown, CGPoint(x: top.x, y: top.y + 6), [])
        mouse(.leftMouseDragged, CGPoint(x: top.x + 10 * state.zoom, y: top.y + 6), [])
        mouse(.leftMouseUp, CGPoint(x: top.x + 10 * state.zoom, y: top.y + 6), [])
        var box = bounds(state.design.objects[0])
        XCTAssertEqual(box.low.x, 0, accuracy: 1e-6, "the bottom side stays put"); XCTAssertEqual(box.high.x, 20, accuracy: 1e-6, "the top slid 10 mm right")
        XCTAssertEqual(box.high.y - box.low.y, 10, accuracy: 1e-6, "skewing keeps the height")
        XCTAssertEqual(document.undoManager?.undoActionName, "Skew Objects")

        // With skew handles on, a corner square still resizes.
        let corner = canvas.screen(Point(20, 10))
        mouse(.leftMouseDown, CGPoint(x: corner.x + 6, y: corner.y + 6), [])
        mouse(.leftMouseDragged, canvas.screen(Point(40, 20)), []); mouse(.leftMouseUp, canvas.screen(Point(40, 20)), [])
        XCTAssertEqual(document.undoManager?.undoActionName, "Resize Objects")

        let middle = { () -> CGPoint in let b = self.bounds(state.design.objects[0]); return canvas.screen((b.low + b.high) * 0.5) }
        mouse(.leftMouseDown, middle(), []); mouse(.leftMouseUp, middle(), [])
        XCTAssertFalse(state.skewHandles, "clicking again brings the stretch handles back")
        mouse(.leftMouseDown, middle(), []); mouse(.leftMouseUp, middle(), [])
        state.selection = []; state.selection = [object.id]
        XCTAssertFalse(state.skewHandles, "a change of selection brings the stretch handles back")

        // A drag that moves the object isn't a click: the handles stay as they were.
        let before = bounds(state.design.objects[0]).low.x, start = middle()
        mouse(.leftMouseDown, start, []); mouse(.leftMouseDragged, CGPoint(x: start.x + 2 * state.zoom, y: start.y), []); mouse(.leftMouseUp, CGPoint(x: start.x + 2 * state.zoom, y: start.y), [])
        XCTAssertFalse(state.skewHandles)
        box = bounds(state.design.objects[0])
        XCTAssertEqual(box.low.x, before + 2, accuracy: 1e-6, "it moved instead")
    }

    /// Each handle shows a pointer for what a drag there does: diagonal arrows on the corners, ↔ and ↕ on the sides
    /// (⇄ once they're skew handles), a curved double arrow just outside a corner, and none elsewhere.
    @MainActor func testHandlesShowWhatTheyDo() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        let object = square()
        state.edit("Setup") { $0.objects = [object] }
        state.selection = [object.id]; state.tool = .select; state.snap = false
        let low = canvas.screen(Point(0, 0)), high = canvas.screen(Point(10, 10)), middleY = (low.y + high.y) / 2
        XCTAssertTrue(canvas.handleCursor(at: CGPoint(x: high.x + 6, y: high.y + 6)) === HandleCursor.rising, "top-right corner: ↗↙")
        XCTAssertTrue(canvas.handleCursor(at: CGPoint(x: low.x - 6, y: high.y + 6)) === HandleCursor.falling, "top-left corner: ↖↘")
        XCTAssertTrue(canvas.handleCursor(at: CGPoint(x: high.x + 6, y: middleY)) === NSCursor.resizeLeftRight)
        XCTAssertTrue(canvas.handleCursor(at: CGPoint(x: high.x + 18, y: high.y + 18)) === HandleCursor.rotate, "just outside a corner")
        XCTAssertNil(canvas.handleCursor(at: canvas.screen(Point(5, 5))), "over the object itself")
        XCTAssertNil(canvas.handleCursor(at: CGPoint(x: high.x + 60, y: high.y + 60)), "far away")
        mouse(.leftMouseDown, canvas.screen(Point(5, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(5, 5)), [])
        XCTAssertTrue(canvas.handleCursor(at: CGPoint(x: high.x + 6, y: middleY)) === HandleCursor.skewUpDown, "a skew handle on the right side")
        XCTAssertTrue(canvas.handleCursor(at: CGPoint(x: (low.x + high.x) / 2, y: high.y + 6)) === HandleCursor.skewSideways, "on the top side")
    }

    /// Near a corner the pointer doesn't flicker: once ↗↙ or ↻ shows, its zone holds on a few points, so a wobble
    /// across the border keeps it; moving clearly out changes it. A press does what the pointer shows.
    @MainActor func testHandlePointersHoldOnNearTheBorder() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        let object = square()
        state.edit("Setup") { $0.objects = [object] }
        state.selection = [object.id]; state.tool = .select; state.snap = false
        let corner = canvas.screen(Point(10, 10)), handle = CGPoint(x: corner.x + 6, y: corner.y + 6)
        /// A point `distance` points out from the corner handle, along the diagonal.
        func out(_ distance: CGFloat) -> CGPoint { CGPoint(x: handle.x + distance / 2.squareRoot(), y: handle.y + distance / 2.squareRoot()) }
        func move(_ p: CGPoint) {
            canvas.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        }
        XCTAssertTrue(canvas.handleCursor(at: out(8)) === HandleCursor.rotate, "coming from nowhere, 8 points out is the rotate zone")
        move(out(4))
        XCTAssertTrue(canvas.handleCursor(at: out(8)) === HandleCursor.rising, "with ↗↙ showing, 8 points out still resizes")
        move(out(8)); move(out(11))
        XCTAssertTrue(canvas.handleCursor(at: out(11)) === HandleCursor.rotate, "moving clearly out shows ↻")
        XCTAssertTrue(canvas.handleCursor(at: out(5)) === HandleCursor.rotate, "with ↻ showing, 5 points out still rotates")
        XCTAssertTrue(canvas.handleCursor(at: out(24)) === HandleCursor.rotate, "and a little past 22 too")
        // Pressing at 5 points out while ↻ shows rotates, as the pointer says, rather than resizing.
        move(out(5))
        let before = state.design.objects[0].nodes[0].point
        mouse(.leftMouseDown, out(5), []); mouse(.leftMouseDragged, CGPoint(x: out(5).x - 40, y: out(5).y + 40), []); mouse(.leftMouseUp, CGPoint(x: out(5).x - 40, y: out(5).y + 40), [])
        XCTAssertEqual(document.undoManager?.undoActionName, "Rotate Objects")
        XCTAssertNotEqual(state.design.objects[0].nodes[0].point, before)
    }

    /// Without a start point set, the marker shows where the stitches really begin (here with the Start & End tool);
    /// dragging it sets the start point.
    @MainActor func testRealStartShowsAndCanBeDragged() async throws {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        let object = square()
        state.edit("Setup") { $0.objects = [object] }
        for _ in 0..<100 where state.busy || state.compiledRevision != state.revision { try await Task.sleep(nanoseconds: 50_000_000) }
        let first = try XCTUnwrap(state.plan.commands.first { $0.op == .stitch && $0.objectID == object.id }?.point)
        state.selection = [object.id]; state.tool = .entryExit; state.snap = false
        mouse(.leftMouseDown, canvas.screen(first), [])
        mouse(.leftMouseDragged, canvas.screen(Point(5, 5)), [])
        mouse(.leftMouseUp, canvas.screen(Point(5, 5)), [])
        XCTAssertEqual(state.design.objects[0].entry, Point(5, 5), "dragging the real start sets the start point")
        XCTAssertEqual(bounds(state.design.objects[0]).high.x, 10, accuracy: 1e-6, "the object itself didn't move")
    }
}
