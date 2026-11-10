// Checks what the Measure tool reads out: the distance in mm and the angle, counted counterclockwise from pointing right.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class MeasureTests: XCTestCase {
    func testMeasurementReadsDistanceAndAngle() {
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(0, 0), to: Point(3, 4)), "5.0 mm · 53°")
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(10, 10), to: Point(10, 22.5)), "12.5 mm · 90°")
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(0, 0), to: Point(-8, 0)), "8.0 mm · 180°")
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(0, 0), to: Point(5, -5)), "7.1 mm · -45°")
    }

    @MainActor func testTheMeasurementGoesWhenTheToolChanges() {
        _ = NSApplication.shared
        let canvas = DesignCanvas(state: EditorState())
        canvas.state.tool = .measure; canvas.measurement = (Point(0, 0), Point(3, 4))
        canvas.state.tool = .select; canvas.state.tool = .measure
        XCTAssertNil(canvas.measurement, "pressing M again starts afresh, without the last line")
    }

    /// Measuring works by dragging, and by click, move, click: after a click the line's end follows the pointer, and
    /// the next click (not one right on top of the first) puts it down. Escape drops a following line.
    @MainActor func testClickMoveClickMeasures() throws {
        _ = NSApplication.shared
        let state = EditorState(), canvas = DesignCanvas(state: state)
        canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event)
            case .mouseMoved: canvas.mouseMoved(with: event); default: canvas.mouseUp(with: event)
            }
        }
        /// The line's length on screen, in points.
        func length() throws -> Double { let line = try XCTUnwrap(canvas.measurement); return line.start.distance(to: line.end) * state.zoom }
        state.tool = .measure

        // Dragging measures as before.
        mouse(.leftMouseDown, 100, 100); mouse(.leftMouseDragged, 200, 100); mouse(.leftMouseUp, 200, 100)
        XCTAssertEqual(try length(), 100, accuracy: 1); XCTAssertFalse(canvas.measureFollowsPointer)
        mouse(.mouseMoved, 300, 300)
        XCTAssertEqual(try length(), 100, accuracy: 1, "a dragged line stays put")

        // Click, move, click.
        mouse(.leftMouseDown, 300, 300); mouse(.leftMouseUp, 300, 300)
        XCTAssertTrue(canvas.measureFollowsPointer, "a click, not a drag: the end follows the pointer")
        mouse(.mouseMoved, 360, 380)
        XCTAssertEqual(try length(), 100, accuracy: 1, "the end follows the pointer")
        mouse(.leftMouseDown, 300, 300); mouse(.leftMouseUp, 300, 300)   // right on the first click: ignored
        XCTAssertTrue(canvas.measureFollowsPointer)
        mouse(.mouseMoved, 400, 300); mouse(.leftMouseDown, 400, 300)
        XCTAssertFalse(canvas.measureFollowsPointer, "the second click puts the end down")
        XCTAssertEqual(try length(), 100, accuracy: 1)
        mouse(.leftMouseDragged, 450, 300); mouse(.leftMouseUp, 450, 300); mouse(.mouseMoved, 500, 500)
        XCTAssertEqual(try length(), 100, accuracy: 1, "after the second click the line stays put")

        // Escape after a first click drops that line; the tool stays on.
        mouse(.leftMouseDown, 100, 400); mouse(.leftMouseUp, 100, 400); mouse(.mouseMoved, 150, 400)
        canvas.cancelMeasuring()   // what Escape does
        mouse(.mouseMoved, 200, 400)
        XCTAssertNil(canvas.measurement); XCTAssertFalse(canvas.measureFollowsPointer)
        XCTAssertEqual(state.tool, .measure)
    }
}
