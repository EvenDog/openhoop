// Checks the handles round a selection (Select tool): a side handle stretches one way and a corner keeps the
// Checks the handles round a selection (Select tool): a side handle stretches one way and a corner keeps the
// proportions, each from the opposite side, as one undoable step; just outside a corner rotates, and clicking the
// selection again turns the side handles into skew handles, for objects and for the reference image; and a selected
// object's real start shows as a marker that can be dragged to set its start point.
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

    /// With Move & Size Artwork, a drag from just outside a corner of the image turns it, and its corner squares
    /// still resize it. Clicking the image shows skew diamonds on its sides; dragging the image still moves it, and
    /// picking another tool hides the diamonds again.
    @MainActor func testOutsideACornerTurnsTheReferenceImageAndClickingShowsSkewHandles() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        state.edit("Setup") { $0.artwork = Artwork(data: Data(), name: "logo.png", width: 40, height: 20) }
        state.tool = .artwork; state.snap = false
        let cornerPoint = canvas.screen(Point(20, 10))
        XCTAssertTrue(canvas.handleCursor(at: cornerPoint) === HandleCursor.rising, "the top-right corner resizes: ↗↙")
        XCTAssertTrue(canvas.handleCursor(at: CGPoint(x: cornerPoint.x + 14, y: cornerPoint.y + 14)) === HandleCursor.rotate)
        XCTAssertNil(canvas.handleCursor(at: canvas.screen(Point(0, 0))), "the image itself keeps the hand")

        // From 14 points beyond the top-right corner (along the line from the middle through it), swung a quarter
        // turn counterclockwise.
        let reach = 1 + 14 / state.zoom / Point(20, 10).distance(to: Point(0, 0))
        let start = Point(20, 10) * reach, end = Point(-start.y, start.x)
        mouse(.leftMouseDown, canvas.screen(start), []); mouse(.leftMouseDragged, canvas.screen(end), []); mouse(.leftMouseUp, canvas.screen(end), [])
        let turned = try! XCTUnwrap(state.design.artwork)
        XCTAssertEqual(turned.corners[0].distance(to: Point(10, -20)), 0, accuracy: 1e-6, "its own bottom-left is now bottom-right")
        XCTAssertEqual(document.undoManager?.undoActionName, "Rotate Artwork")

        mouse(.leftMouseDown, canvas.screen(Point(0, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(0, 5)), [])
        XCTAssertTrue(state.artworkSkewHandles, "a click on the image shows the skew handles")
        XCTAssertEqual(state.design.artwork?.center, Point(0, 0), "and doesn't move it")

        // A corner square still resizes.
        let corner = canvas.screen(turned.corners[2])
        mouse(.leftMouseDown, corner, []); mouse(.leftMouseDragged, CGPoint(x: corner.x - 10 * state.zoom, y: corner.y + 20 * state.zoom), [])
        mouse(.leftMouseUp, CGPoint(x: corner.x - 10 * state.zoom, y: corner.y + 20 * state.zoom), [])
        XCTAssertEqual(document.undoManager?.undoActionName, "Resize Artwork")

        mouse(.leftMouseDown, canvas.screen(Point(0, 5)), []); mouse(.leftMouseDragged, canvas.screen(Point(3, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(3, 5)), [])
        XCTAssertEqual(document.undoManager?.undoActionName, "Move Artwork", "a drag moves it")
        XCTAssertTrue(state.artworkSkewHandles, "and keeps the handles as they were")
        state.tool = .select; state.tool = .artwork
        XCTAssertFalse(state.artworkSkewHandles, "another tool hides the skew handles")
    }

    /// While cropping, a box dragged over the image keeps just that part, as one undoable step, and cropping ends. A
    /// click (no box) keeps cropping.
    @MainActor func testDraggingABoxCropsTheReferenceImage() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        state.edit("Setup") { $0.artwork = Artwork(data: Data(), name: "logo.png", width: 40, height: 20) }
        state.tool = .artwork; state.snap = false; state.croppingArtwork = true

        mouse(.leftMouseDown, canvas.screen(Point(2, 2)), []); mouse(.leftMouseUp, canvas.screen(Point(2, 2)), [])
        XCTAssertTrue(state.croppingArtwork, "a click isn't a box: still cropping")
        XCTAssertNil(state.design.artwork?.crop)

        mouse(.leftMouseDown, canvas.screen(Point(0, 0)), [])
        mouse(.leftMouseDragged, canvas.screen(Point(30, 20)), [])
        mouse(.leftMouseUp, canvas.screen(Point(30, 20)), [])
        let kept = try! XCTUnwrap(state.design.artwork)
        XCTAssertEqual(kept.width, 20, accuracy: 1e-6, "clipped to the image's right edge"); XCTAssertEqual(kept.height, 10, accuracy: 1e-6)
        XCTAssertEqual(kept.center.distance(to: Point(10, 5)), 0, accuracy: 1e-6, "the part kept stays where it was")
        XCTAssertNotNil(kept.crop)
        XCTAssertFalse(state.croppingArtwork, "cropping ends")
        XCTAssertEqual(document.undoManager?.undoActionName, "Crop Artwork")
        state.tool = .select; state.tool = .artwork; state.croppingArtwork = true; state.tool = .select
        XCTAssertFalse(state.croppingArtwork, "another tool stops cropping")
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
