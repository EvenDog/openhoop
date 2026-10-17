// Guide lines dragged out of the rulers, and the grid's color.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class GuideAndGridTests: XCTestCase {
    /// Automatic grid lines are light on dark cloth and dark on light cloth; a custom color wins.
    func testGridColorSuitsTheCloth() throws {
        func brightness(_ color: NSColor) -> CGFloat { let c = color.usingColorSpace(.sRGB)!; return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent }
        let onBlack = DesignCanvas.gridColor(fabric: 0x1C1C1E, custom: nil, opacity: nil), onWhite = DesignCanvas.gridColor(fabric: 0xFFFFFF, custom: nil, opacity: nil)
        XCTAssertGreaterThan(brightness(onBlack), 0.9); XCTAssertLessThan(brightness(onWhite), 0.6)
        let custom = try XCTUnwrap(DesignCanvas.gridColor(fabric: 0x1C1C1E, custom: 0xFF0000, opacity: 0.7).usingColorSpace(.sRGB))
        XCTAssertEqual(custom.redComponent, 1, accuracy: 0.01); XCTAssertEqual(custom.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(custom.alphaComponent, 0.7, accuracy: 0.01)
    }

    /// With Select, the pointer is over a guide (and turns ↔ or ↕) where a drag would grab it: on the line, not over
    /// an object, and not with other tools.
    @MainActor func testPointerKnowsWhenItIsOverAGuide() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func move(to p: Point) {
            canvas.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: canvas.screen(p), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                       context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        }
        var square = RunObject(name: "Square", nodes: [Point(-5, -5), Point(5, -5), Point(5, 5), Point(-5, 5)].map { PathNode($0) })
        square.closed = true; square.digitizing = DigitizingSettings(kind: .fill)
        state.edit("Setup") { $0.guides = [Guide(vertical: true, position: 0)]; $0.objects = [square] }
        state.tool = .select
        move(to: Point(0, 30)); XCTAssertEqual(canvas.hoveredGuide, 0, "on the guide, away from the square")
        move(to: Point(0, 0)); XCTAssertNil(canvas.hoveredGuide, "the square is under the pointer: a drag would move it")
        move(to: Point(8, 30)); XCTAssertNil(canvas.hoveredGuide, "off the line")
        move(to: Point(0, 30)); XCTAssertEqual(canvas.hoveredGuide, 0)
        state.tool = .run; canvas.toolDidChange(); move(to: Point(0, 31))
        XCTAssertNil(canvas.hoveredGuide, "other tools don't grab guides")
    }

    /// A guide dragged down out of the top ruler is added where it's let go (one undo step), moves when dragged with
    /// Select, catches points with Snap on, and goes when dragged back onto its ruler.
    @MainActor func testGuideDraggedOutOfTheRulerAndBack() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        document.undoManager?.groupsByEvent = false
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: document.undoManager?.beginUndoGrouping(); canvas.mouseUp(with: event); document.undoManager?.endUndoGrouping()
            }
        }
        state.tool = .select; state.snap = false
        let target = canvas.screen(Point(0, 12.34))
        mouse(.leftMouseDown, CGPoint(x: 300, y: 590))   // in the top ruler
        mouse(.leftMouseDragged, CGPoint(x: 300, y: 400)); mouse(.leftMouseDragged, target)
        XCTAssertNil(state.design.guides, "nothing is added until the mouse is let go")
        mouse(.leftMouseUp, target)
        XCTAssertEqual(state.design.guides, [Guide(vertical: false, position: 12.3)], "a horizontal guide, to 0.1 mm")
        document.undoManager?.undo(); XCTAssertNil(state.design.guides)
        document.undoManager?.redo(); XCTAssertEqual(state.design.guides?.count, 1)

        // Grab it with Select (nothing else is there) and move it.
        let moved = canvas.screen(Point(0, -20))
        mouse(.leftMouseDown, canvas.screen(Point(30, 12.3))); mouse(.leftMouseDragged, moved); mouse(.leftMouseUp, moved)
        XCTAssertEqual(state.design.guides, [Guide(vertical: false, position: -20)])

        // With Snap on, a point close to the guide lands on it; far from it, on the nearest millimeter.
        state.snap = true
        XCTAssertEqual(canvas.snapped(Point(3.3, -20.4)), Point(3, -20))
        XCTAssertEqual(canvas.snapped(Point(3.3, -27.6)), Point(3, -28))

        // A vertical guide from the left ruler, then dragged back onto its ruler to remove it.
        mouse(.leftMouseDown, CGPoint(x: 10, y: 300)); mouse(.leftMouseDragged, canvas.screen(Point(15, 0))); mouse(.leftMouseUp, canvas.screen(Point(15, 0)))
        XCTAssertEqual(state.design.guides?.last, Guide(vertical: true, position: 15), "whole mm with Snap on")
        mouse(.leftMouseDown, canvas.screen(Point(15, 40))); mouse(.leftMouseDragged, CGPoint(x: 10, y: 300)); mouse(.leftMouseUp, CGPoint(x: 10, y: 300))
        XCTAssertEqual(state.design.guides, [Guide(vertical: false, position: -20)])
        // A guide dragged out and let go back over its ruler is never added.
        mouse(.leftMouseDown, CGPoint(x: 10, y: 300)); mouse(.leftMouseDragged, CGPoint(x: 200, y: 300)); mouse(.leftMouseDragged, CGPoint(x: 12, y: 300)); mouse(.leftMouseUp, CGPoint(x: 12, y: 300))
        XCTAssertEqual(state.design.guides?.count, 1)
    }

    /// The rulers mark where the pointer is: a line on the top ruler at its x and on the left ruler at its y. With
    /// rulers and guides switched off (View › Show Rulers & Guides), the marks hide, guides stop catching points, and
    /// dragging where the top ruler was adds no guide. Guides aren't deleted: they come back with the rulers.
    @MainActor func testRulerMarksFollowThePointerAndRulersCanBeHidden() throws {
        _ = NSApplication.shared
        let preferences = Preferences.shared, saved = preferences.data.showRulers
        defer { preferences.data.showRulers = saved }   // changed in memory only, never saved to the preferences file
        preferences.data.showRulers = nil
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .mouseMoved: canvas.mouseMoved(with: event)
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        let at = canvas.screen(Point(10, -5))
        mouse(.mouseMoved, at)
        XCTAssertFalse(canvas.topRulerMark.isHidden); XCTAssertFalse(canvas.leftRulerMark.isHidden)
        XCTAssertEqual(canvas.topRulerMark.frame.midX, at.x, accuracy: 0.5)
        XCTAssertEqual(canvas.topRulerMark.frame.minY, 600 - 23, "on the top ruler")
        XCTAssertEqual(canvas.leftRulerMark.frame.midY, at.y, accuracy: 0.5)
        XCTAssertEqual(canvas.leftRulerMark.frame.minX, 0, "on the left ruler")

        state.edit("Guide") { $0.guides = [Guide(vertical: true, position: 2.4)] }
        state.snap = true
        XCTAssertEqual(canvas.snapped(Point(2.5, 3)).x, 2.4, accuracy: 1e-9, "a guide catches the point")
        preferences.data.showRulers = false
        mouse(.mouseMoved, at)
        XCTAssertTrue(canvas.topRulerMark.isHidden); XCTAssertTrue(canvas.leftRulerMark.isHidden)
        XCTAssertEqual(canvas.snapped(Point(2.5, 3)).x, 3, "a hidden guide doesn't")
        state.tool = .select
        mouse(.leftMouseDown, CGPoint(x: 300, y: 590)); mouse(.leftMouseDragged, CGPoint(x: 300, y: 400)); mouse(.leftMouseUp, CGPoint(x: 300, y: 400))
        XCTAssertEqual(state.design.guides?.count, 1, "no new guide without the rulers")
    }
}
