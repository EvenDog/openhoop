// Checks that the Open Shape, Closed Shape, Freehand and shape tools add objects with the stitch picked for them, named
// after that stitch or shape, as one undoable step.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ShapeToolTests: XCTestCase {
    @MainActor func testOpenAndClosedShapeUseThePickedStitch() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let shapes = Preferences.shared.shapes   // read only: tests never change the person's saved choices
        state.tool = .closedShape
        state.draft = [PathNode(Point(0, 0)), PathNode(Point(20, 0)), PathNode(Point(10, 15))]
        state.finishPath()
        // The saved choice may be a fill, an outline, or both (two grouped objects, all selected).
        let made = state.design.objects, closed = made.first
        XCTAssertEqual(made.count, shapes.closedFill != nil && shapes.closedOutline != nil ? 2 : 1)
        XCTAssertEqual(closed?.closed, true)
        XCTAssertEqual(closed?.kind, shapes.closedFill != nil ? .fill : shapes.closedOutline == .satin ? .satin : .run)
        XCTAssertEqual(closed?.name, "\(closed?.stitchTitle ?? "") 1")
        XCTAssertTrue(state.draft.isEmpty)
        XCTAssertEqual(state.selection, Set(made.map(\.id)))

        state.tool = .openShape
        state.draft = [PathNode(Point(0, 30)), PathNode(Point(30, 30))]
        state.finishPath()
        XCTAssertEqual(state.design.objects.count, made.count + 1)
        XCTAssertEqual(state.design.objects.last?.closed, false)
        XCTAssertEqual(state.design.objects.last?.kind, shapes.openStitch == .satin ? .satin : .run)
    }

    @MainActor func testDraggedShapeIsAddedAsOneUndoableStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        state.tool = .ellipse
        state.draft = ShapeGeometry.nodes(.ellipse, in: (Point(-10, -10), Point(10, 10)))
        state.finishShape(.ellipse)
        let ellipse = try XCTUnwrap(state.design.objects.first)   // then its outline, if the saved choice has one
        XCTAssertEqual(ellipse.name, "Ellipse 1")
        XCTAssertTrue(ellipse.closed)
        XCTAssertTrue(state.draft.isEmpty)
        document.undoManager?.undo()
        XCTAssertTrue(document.state.design.objects.isEmpty)
    }

    /// Return pressed while still dragging out a rectangle used to add a stray running-stitch line, and Escape couldn't
    /// cancel the drag. Now Return waits for the mouse to be let go, Escape forgets the drag, and a shape left
    /// unfinished (a draft restored after a crash) is finished as that shape.
    @MainActor func testReturnAndEscapeDuringAShapeDrag() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
        }
        state.tool = .rectangle
        mouse(.leftMouseDown, 300, 300); mouse(.leftMouseDragged, 400, 380)
        XCTAssertTrue(canvas.isDraggingShape); XCTAssertFalse(state.draft.isEmpty)
        state.finishPath()   // Return mid-drag
        XCTAssertTrue(state.design.objects.isEmpty, "nothing is added until the mouse is let go")
        mouse(.leftMouseUp, 400, 380)
        let perShape = state.design.objects.count   // 1, or 2 when the saved Next shape choice adds an outline
        XCTAssertEqual(state.design.objects.first?.name, "Rectangle 1")

        mouse(.leftMouseDown, 100, 100); mouse(.leftMouseDragged, 150, 150)
        canvas.cancelShapeDrag(); state.draft = []   // what Escape does
        mouse(.leftMouseDragged, 200, 200); mouse(.leftMouseUp, 200, 200)
        XCTAssertEqual(state.design.objects.count, perShape, "a cancelled drag adds nothing")

        state.draft = ShapeGeometry.nodes(.rectangle, in: (Point(-5, -5), Point(5, 5)))   // a restored, unfinished shape
        state.finishPath()
        let restored = state.design.objects[perShape]
        XCTAssertEqual(restored.name, "Rectangle \(perShape + 1)")
        XCTAssertEqual(restored.closed, true, "a closed rectangle, not an open running line")
    }

    /// Freehand: pressing and dragging draws a stroke that follows the pointer; letting go adds it with the Next shape
    /// choices, closed for Freehand Closed Shape, open for Freehand Open Shape. Escape mid-stroke adds nothing, and
    /// so does a click without a drag.
    @MainActor func testFreehandStrokeIsAddedWhenLetGo() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
        }
        /// Drags round a circle of `radius` canvas points about (300, 300), from the right, in 60 steps.
        func circle(_ radius: Double, from start: Double = 0, to end: Double = 2 * .pi) {
            let steps = 60
            for i in 0...steps {
                let a = start + (end - start) * Double(i) / Double(steps), x = 300 + radius * cos(a), y = 300 + radius * sin(a)
                mouse(i == 0 ? .leftMouseDown : .leftMouseDragged, x, y)
            }
        }
        let shapes = Preferences.shared.shapes   // read only: tests never change the person's saved choices
        state.tool = .freehandClosed
        circle(100)
        XCTAssertFalse(state.draft.isEmpty, "the stroke shows while it's drawn")
        XCTAssertTrue(state.design.objects.isEmpty, "nothing is added until the pointer is let go")
        mouse(.leftMouseUp, 400, 300)
        let made = state.design.objects, closed = try XCTUnwrap(made.first)
        XCTAssertEqual(made.count, shapes.closedFill != nil && shapes.closedOutline != nil ? 2 : 1)
        XCTAssertTrue(closed.closed)
        XCTAssertTrue(closed.nodes.allSatisfy(\.smooth))
        XCTAssertLessThan(closed.nodes.count, 40, "\(closed.nodes.count) nodes: the stroke was smoothed, not kept point by point")
        XCTAssertEqual(closed.kind, shapes.closedFill != nil ? .fill : shapes.closedOutline == .satin ? .satin : .run)
        XCTAssertEqual(closed.name, "\(closed.stitchTitle) 1")
        XCTAssertTrue(state.draft.isEmpty)
        XCTAssertEqual(state.selection, Set(made.map(\.id)))
        document.undoManager?.undo()
        XCTAssertTrue(state.design.objects.isEmpty, "one undoable step")

        state.tool = .freehandOpen
        circle(80, from: 0, to: .pi)   // half a circle: an open arc
        mouse(.leftMouseUp, 220, 300)
        let arc = try XCTUnwrap(state.design.objects.last)
        XCTAssertEqual(state.design.objects.count, 1)
        XCTAssertFalse(arc.closed)
        XCTAssertEqual(arc.kind, shapes.openStitch == .satin ? .satin : .run)

        circle(50, from: 0, to: .pi / 2)
        canvas.cancelShapeDrag(); state.draft = []   // what Escape does
        mouse(.leftMouseDragged, 300, 400); mouse(.leftMouseUp, 300, 400)
        XCTAssertEqual(state.design.objects.count, 1, "a cancelled stroke adds nothing")

        mouse(.leftMouseDown, 100, 100); mouse(.leftMouseUp, 100, 100)
        XCTAssertEqual(state.design.objects.count, 1, "a click without a drag adds nothing")
        XCTAssertTrue(state.draft.isEmpty)
    }
}
