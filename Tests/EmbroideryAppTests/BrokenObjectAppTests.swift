// A stitch error in one object: the rest still get fresh stitches (the broken one is listed for its red outline, and
// nothing counts as ready to export), and a node drag that would break a sewable satin goes back.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class BrokenObjectAppTests: XCTestCase {
    /// A satin column 20 mm long and 3 mm wide, rungs every 5 mm, centered on `x`.
    private func satin(_ name: String, x: Double) -> RunObject {
        let rungs = stride(from: 0.0, through: 20, by: 5).flatMap { y in [PathNode(Point(x - 1.5, y)), PathNode(Point(x + 1.5, y))] }
        var object = RunObject(name: name, nodes: rungs); object.digitizing = DigitizingSettings(kind: .satin)
        return object
    }

    @MainActor func testOtherObjectsKeepFreshStitchesDuringAnError() async throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var bad = satin("Bad", x: 0); bad.nodes[4].point = Point(3, 12)   // its middle rung crosses the right rail
        let good = satin("Good", x: 20)
        state.edit("Setup") { $0.objects = [bad, good] }
        for _ in 0..<100 where state.busy { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(state.brokenObjects, [bad.id])
        XCTAssertNotNil(state.generationError, "the error stays up, so export stays blocked")
        XCTAssertNotEqual(state.compiledRevision, state.revision, "the shown stitches aren't treated as ready to export")
        XCTAssertEqual(Set(state.plan.commands.compactMap(\.objectID)), [good.id], "the good satin's stitches are shown")
        // Fixed: everything compiles and the red outline goes.
        state.edit("Fix") { $0.objects[0].nodes[4].point = Point(-1.5, 10) }
        for _ in 0..<100 where state.busy { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(state.brokenObjects.isEmpty); XCTAssertNil(state.generationError); XCTAssertEqual(state.compiledRevision, state.revision)
    }

    @MainActor func testDragThatWouldBreakASatinGoesBack() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func mouse(_ type: NSEvent.EventType, _ p: Point) {
            let event = NSEvent.mouseEvent(with: type, location: canvas.screen(p), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
        }
        let column = satin("Column", x: 0)
        state.edit("Setup") { $0.objects = [column] }
        state.selection = [column.id]; state.tool = .node; state.snap = false
        // The middle rung's left point, dragged across the right rail: it goes back.
        mouse(.leftMouseDown, Point(-1.5, 10)); mouse(.leftMouseDragged, Point(3, 12)); mouse(.leftMouseUp, Point(3, 12))
        XCTAssertEqual(state.design.objects[0].nodes[4].point, Point(-1.5, 10))
        XCTAssertTrue(state.status.contains("went back"), state.status)
        // A drag that keeps it sewable is kept.
        mouse(.leftMouseDown, Point(-1.5, 10)); mouse(.leftMouseDragged, Point(-2.5, 10)); mouse(.leftMouseUp, Point(-2.5, 10))
        XCTAssertEqual(state.design.objects[0].nodes[4].point, Point(-2.5, 10))
        // An object that's already broken can still be edited (any edit may be the fix).
        state.edit("Break") { $0.objects[0].nodes[4].point = Point(3, 12) }
        mouse(.leftMouseDown, Point(3, 12)); mouse(.leftMouseDragged, Point(3.5, 12)); mouse(.leftMouseUp, Point(3.5, 12))
        XCTAssertEqual(state.design.objects[0].nodes[4].point, Point(3.5, 12))
    }
}
