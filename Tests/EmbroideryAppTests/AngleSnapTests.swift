// Holding Control snaps a line being drawn to 15° steps: a drawing tool's next point, a stitch angle line, the
// Measure line. ⇧ does it too for the fill's stitch angle line, as for the rotate handles.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class AngleSnapTests: XCTestCase {
    /// The point turns around the origin to the nearest 15° step and keeps its distance from it.
    func testSnappedToAngleKeepsTheDistance() {
        let origin = Point(1, 1)
        let flat = Point(11, 2).snappedToAngle(around: origin)   // about 5.7°: snaps to 0°
        XCTAssertEqual(flat.y, 1, accuracy: 1e-9); XCTAssertEqual(flat.x, 1 + hypot(10, 1), accuracy: 1e-9)
        let steep = Point(2, 11).snappedToAngle(around: origin)   // about 84°: snaps to 90°
        XCTAssertEqual(steep.x, 1, accuracy: 1e-9); XCTAssertEqual(steep.y, 1 + hypot(1, 10), accuracy: 1e-9)
        let diagonal = Point(-9, -8).snappedToAngle(around: origin)   // about 222°: snaps to 225°
        XCTAssertEqual(diagonal.x - origin.x, diagonal.y - origin.y, accuracy: 1e-9)
        XCTAssertLessThan(diagonal.x, origin.x)
        XCTAssertEqual(Point(4, 4).snappedToAngle(around: Point(4, 4)), Point(4, 4), "the origin stays put")
    }

    /// One canvas, with events that can carry modifier keys and a click count.
    @MainActor private func makeCanvas() -> (DesignDocument, DesignCanvas) {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        state.snap = false   // Snap to grid would round the pointer first
        return (document, canvas)
    }
    @MainActor private func mouse(_ canvas: DesignCanvas, _ type: NSEvent.EventType, _ p: Point, _ flags: NSEvent.ModifierFlags = []) {
        let event = NSEvent.mouseEvent(with: type, location: canvas.screen(p), modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type {
        case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event)
        case .mouseMoved: canvas.mouseMoved(with: event); default: canvas.mouseUp(with: event)
        }
    }

    /// A drawing tool: a Control-click puts the next point on the nearest 15° step from the last one (as a corner);
    /// a plain click puts it where the pointer is.
    @MainActor func testControlClickDrawsStraight() throws {
        let (document, canvas) = makeCanvas(), state = canvas.state
        _ = document
        state.tool = .run
        mouse(canvas, .leftMouseDown, Point(0, 0)); mouse(canvas, .leftMouseUp, Point(0, 0))
        mouse(canvas, .leftMouseDown, Point(10, 1), .control); mouse(canvas, .leftMouseUp, Point(10, 1), .control)   // about 6°: snaps to 0°
        let second = try XCTUnwrap(state.draft.last)
        XCTAssertEqual(state.draft.count, 2)
        XCTAssertEqual(second.point.y, 0, accuracy: 0.05, "straight across from the first point")
        XCTAssertEqual(second.point.x, hypot(10, 1), accuracy: 0.05, "as far away as the click")
        XCTAssertFalse(second.smooth, "a corner: Control no longer makes a curve point")
        mouse(canvas, .leftMouseDown, Point(20, 2)); mouse(canvas, .leftMouseUp, Point(20, 2))
        XCTAssertEqual(try XCTUnwrap(state.draft.last).point.y, 2, accuracy: 0.05, "without Control the point goes where it's clicked")
    }

    /// Measure: with Control the line turns to the nearest 15° step from where it starts.
    @MainActor func testControlSnapsTheMeasurement() throws {
        let (document, canvas) = makeCanvas(), state = canvas.state
        _ = document
        state.tool = .measure
        mouse(canvas, .leftMouseDown, Point(0, 0))
        mouse(canvas, .leftMouseDragged, Point(10, 9), .control)   // about 42°: snaps to 45°
        let line = try XCTUnwrap(canvas.measurement)
        XCTAssertEqual(line.end.x, line.end.y, accuracy: 0.05)
        XCTAssertEqual(line.end.distance(to: line.start), hypot(10, 9), accuracy: 0.05)
        mouse(canvas, .leftMouseDragged, Point(10, 9))
        XCTAssertEqual(try XCTUnwrap(canvas.measurement).end.y, 9, accuracy: 0.05, "letting go of Control follows the pointer again")
    }

    /// Add Stitch Angles: with Control, the second click turns the line to the nearest 15° step from the first.
    @MainActor func testControlSnapsANewStitchAngleLine() throws {
        let (document, canvas) = makeCanvas(), state = canvas.state
        var fill = RunObject(name: "Box", nodes: [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        document.undoManager?.groupsByEvent = false
        document.undoManager?.beginUndoGrouping(); state.edit("Add Box") { $0.objects.append(fill) }; document.undoManager?.endUndoGrouping()
        state.selection = [fill.id]; state.tool = .addAngles; state.angleTarget = fill.id
        document.undoManager?.beginUndoGrouping()
        mouse(canvas, .leftMouseDown, Point(-12, 1)); mouse(canvas, .leftMouseUp, Point(-12, 1))
        mouse(canvas, .leftMouseDown, Point(12, 4), .control); mouse(canvas, .leftMouseUp, Point(12, 4), .control)
        document.undoManager?.endUndoGrouping()
        let line = try XCTUnwrap(state.design.objects[0].settings.angleLines?.last)
        XCTAssertEqual(line[1].y, line[0].y, accuracy: 0.05, "straight across")
    }

    /// The fill's stitch angle line (Edit Nodes): Control or ⇧ while dragging an end turns it in 15° steps.
    @MainActor func testControlOrShiftStepsTheFillAngle() throws {
        for key in [NSEvent.ModifierFlags.control, .shift] {
            let (document, canvas) = makeCanvas(), state = canvas.state
            var fill = RunObject(name: "Box", nodes: [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)].map { PathNode($0) })
            fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.angle = 0
            document.undoManager?.groupsByEvent = false
            document.undoManager?.beginUndoGrouping(); state.edit("Add Box") { $0.objects.append(fill) }; document.undoManager?.endUndoGrouping()
            state.selection = [fill.id]; state.tool = .node
            let ends = try XCTUnwrap(StitchAngleLine.ends(of: state.design.objects[0]))   // flat, through the middle
            let grabbed = ends.1, anchor = ends.0
            let target = anchor + Point(cos(34 * Double.pi / 180), sin(34 * Double.pi / 180)) * 20   // 34°: the nearest step is 30°
            mouse(canvas, .leftMouseDown, grabbed)
            mouse(canvas, .leftMouseDragged, target, key)
            document.undoManager?.beginUndoGrouping(); mouse(canvas, .leftMouseUp, target, key); document.undoManager?.endUndoGrouping()
            XCTAssertEqual(state.design.objects[0].settings.angle, 30, accuracy: 1e-9, "\(key)")
        }
    }
}
