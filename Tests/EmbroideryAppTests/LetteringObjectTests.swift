// Checks that lettering behaves as one object: clicking a letter (even Option-clicking) selects the whole word,
// Ungroup leaves it whole, editing rebuilds it in place as one undo step, Break Apart Lettering turns it into
// shapes, and with Edit Nodes dragging a letter's handle moves just that letter and remembers it.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class LetteringObjectTests: XCTestCase {
    /// A document holding the word "Abc" in a Mac font (the bundled embroidery fonts aren't loaded in tests).
    @MainActor private func word() throws -> (DesignDocument, LetteringSpec) {
        _ = NSApplication.shared
        let document = DesignDocument()
        let spec = LetteringSpec(text: "Abc", fontKind: .system, font: "Helvetica-Bold", height: 12)
        let objects = try spec.build(color: ThreadColor.palette[0], embroideryFonts: []).objects
        document.state.edit("Setup") { $0.objects = objects }
        return (document, objects[0].lettering!)
    }
    private func box(_ objects: [RunObject]) -> (min: Point, max: Point) {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        return (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
    }

    @MainActor func testLetteringIsOneObject() throws {
        let (document, spec) = try word(), state = document.state
        let all = Set(state.design.objects.map(\.id))
        state.select(state.design.objects[1].id, single: true)
        XCTAssertEqual(state.selection, all, "Option-clicking a letter still selects the whole word")
        state.ungroupSelection()
        XCTAssertTrue(state.design.objects.allSatisfy { $0.lettering != nil && $0.groupID != nil }, "Ungroup leaves lettering whole")
        XCTAssertTrue(state.status.contains("Break Apart Lettering"), state.status)

        var next = spec; next.text = "Abcd"
        XCTAssertTrue(state.rebuildLettering(next, action: "Edit Text"))
        XCTAssertEqual(state.design.letteringObjects(spec.id).first?.lettering?.text, "Abcd")
        XCTAssertEqual(state.design.letteringObjects(spec.id).first?.lettering?.anchor, spec.anchor, "rebuilt in the same place")
        XCTAssertEqual(state.selection, Set(state.design.objects.map(\.id)), "the new letters are selected")
        XCTAssertEqual(document.undoManager?.undoActionName, "Edit Text")

        state.breakApartLettering()
        XCTAssertTrue(state.design.objects.allSatisfy { $0.lettering == nil && $0.groupID != nil }, "plain shapes, still grouped")
        XCTAssertEqual(document.undoManager?.undoActionName, "Break Apart Lettering")
    }

    /// Edit Nodes: dragging the first letter's handle 2 mm up moves just that letter, and the move is kept as a nudge.
    @MainActor func testDraggingALetterMovesJustThatLetter() throws {
        let (document, spec) = try word(), state = document.state
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type { case .leftMouseDown: canvas.mouseDown(with: event); case .leftMouseDragged: canvas.mouseDragged(with: event); default: canvas.mouseUp(with: event) }
        }
        state.selection = Set(state.design.objects.map(\.id)); state.tool = .node; state.snap = false
        let first = box(state.design.objects.filter { $0.letterKey == 0 }), third = box(state.design.objects.filter { $0.letterKey == 2 })
        let base = canvas.screen(Point((first.min.x + first.max.x) / 2, first.min.y)), handle = CGPoint(x: base.x, y: base.y - 8)
        mouse(.leftMouseDown, handle)
        mouse(.leftMouseDragged, CGPoint(x: handle.x, y: handle.y + 2 * state.zoom))
        mouse(.leftMouseUp, CGPoint(x: handle.x, y: handle.y + 2 * state.zoom))
        let objects = state.design.letteringObjects(spec.id)
        XCTAssertEqual(box(objects.filter { $0.letterKey == 0 }).min.y, first.min.y + 2, accuracy: 0.01, "the first letter moved up 2 mm")
        XCTAssertEqual(box(objects.filter { $0.letterKey == 2 }).min.y, third.min.y, accuracy: 1e-9, "the others stayed put")
        XCTAssertEqual(objects.first?.lettering?.letterOffsets?[0]?.y ?? 0, 2.0 / 12, accuracy: 1e-6, "kept as a share of the height")
        XCTAssertEqual(document.undoManager?.undoActionName, "Move Letter")
    }
}
