// Checks the handles round a selection (Select tool): a side handle stretches one way and a corner keeps the
// proportions, each from the opposite side, as one undoable step; clicking the selection again switches to handles
// that rotate (corners) and skew (sides), for objects and for the reference image; and a selected object's real start shows as a marker that can be dragged
// to set its start point.
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

    /// Clicking the selected object again switches its handles: a corner then turns it round the middle of its box,
    /// and the top side leans it sideways with the bottom side staying put. Clicking again, or selecting something
    /// else, brings the resize handles back.
    @MainActor func testClickAgainRotatesAndSkews() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        let object = square()
        state.edit("Setup") { $0.objects = [object] }
        state.selection = [object.id]; state.tool = .select; state.snap = false

        mouse(.leftMouseDown, canvas.screen(Point(5, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(5, 5)), [])
        XCTAssertTrue(state.turnHandles, "a click on what's already selected switches to rotate and skew handles")

        // The top-right corner handle swung a quarter turn counterclockwise, to the top-left: (0, 0) goes to (10, 0).
        let topRight = canvas.screen(Point(10, 10)), topLeft = canvas.screen(Point(0, 10))
        mouse(.leftMouseDown, CGPoint(x: topRight.x + 6, y: topRight.y + 6), [])
        mouse(.leftMouseDragged, CGPoint(x: topLeft.x - 6, y: topLeft.y + 6), [])
        mouse(.leftMouseUp, CGPoint(x: topLeft.x - 6, y: topLeft.y + 6), [])
        XCTAssertEqual(state.design.objects[0].nodes[0].point.distance(to: Point(10, 0)), 0, accuracy: 1e-6)
        XCTAssertEqual(document.undoManager?.undoActionName, "Rotate Objects")
        XCTAssertTrue(state.turnHandles, "the handles stay rotate and skew after a turn")

        // The top side's handle dragged 10 mm right on a 10 mm tall square: 45°, the bottom side stays put.
        let top = canvas.screen(Point(5, 10))
        mouse(.leftMouseDown, CGPoint(x: top.x, y: top.y + 6), [])
        mouse(.leftMouseDragged, CGPoint(x: top.x + 10 * state.zoom, y: top.y + 6), [])
        mouse(.leftMouseUp, CGPoint(x: top.x + 10 * state.zoom, y: top.y + 6), [])
        var box = bounds(state.design.objects[0])
        XCTAssertEqual(box.low.x, 0, accuracy: 1e-6, "the bottom side stays put"); XCTAssertEqual(box.high.x, 20, accuracy: 1e-6, "the top slid 10 mm right")
        XCTAssertEqual(box.high.y - box.low.y, 10, accuracy: 1e-6, "skewing keeps the height")
        XCTAssertEqual(document.undoManager?.undoActionName, "Skew Objects")

        mouse(.leftMouseDown, canvas.screen(Point(10, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(10, 5)), [])
        XCTAssertFalse(state.turnHandles, "clicking again brings the resize handles back")
        mouse(.leftMouseDown, canvas.screen(Point(10, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(10, 5)), [])
        state.selection = []; state.selection = [object.id]
        XCTAssertFalse(state.turnHandles, "a change of selection brings the resize handles back")

        // A drag that moves the object isn't a click: the handles stay as they were.
        mouse(.leftMouseDown, canvas.screen(Point(10, 5)), []); mouse(.leftMouseDragged, canvas.screen(Point(12, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(12, 5)), [])
        XCTAssertFalse(state.turnHandles)
        box = bounds(state.design.objects[0])
        XCTAssertEqual(box.low.x, 2, accuracy: 1e-6, "it moved instead")
    }

    /// With Move & Size Artwork, clicking the image switches its corner handles to rotate and skew handles: a corner
    /// then turns it. Dragging the image still moves it, and picking another tool brings the resize handles back.
    @MainActor func testClickingTheReferenceImageTurnsIt() {
        let document = DesignDocument(), state = document.state
        let (canvas, mouse) = canvas(for: state)
        state.edit("Setup") { $0.artwork = Artwork(data: Data(), name: "logo.png", width: 40, height: 20) }
        state.tool = .artwork; state.snap = false

        mouse(.leftMouseDown, canvas.screen(Point(5, 0)), []); mouse(.leftMouseUp, canvas.screen(Point(5, 0)), [])
        XCTAssertTrue(state.artworkTurnHandles, "a click on the image switches to rotate and skew handles")
        XCTAssertEqual(state.design.artwork?.center, Point(0, 0), "and doesn't move it")

        // The top-right corner swung a quarter turn counterclockwise.
        mouse(.leftMouseDown, canvas.screen(Point(20, 10)), [])
        mouse(.leftMouseDragged, canvas.screen(Point(-10, 20)), [])
        mouse(.leftMouseUp, canvas.screen(Point(-10, 20)), [])
        let turned = try! XCTUnwrap(state.design.artwork)
        XCTAssertEqual(turned.corners[0].distance(to: Point(10, -20)), 0, accuracy: 1e-6, "its own bottom-left is now bottom-right")
        XCTAssertEqual(document.undoManager?.undoActionName, "Rotate Artwork")

        mouse(.leftMouseDown, canvas.screen(Point(0, 5)), []); mouse(.leftMouseDragged, canvas.screen(Point(3, 5)), []); mouse(.leftMouseUp, canvas.screen(Point(3, 5)), [])
        XCTAssertEqual(state.design.artwork!.center.distance(to: Point(3, 0)), 0, accuracy: 1e-6, "a drag moves it")
        XCTAssertTrue(state.artworkTurnHandles, "and keeps the handles as they were")
        state.tool = .select; state.tool = .artwork
        XCTAssertFalse(state.artworkTurnHandles, "another tool brings the resize handles back")
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
