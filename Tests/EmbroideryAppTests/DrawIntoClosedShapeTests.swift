// Checks drawing more points into a closed outline: with the Fill tool, a click on a point of the selected fill picks
// it up, new points go in between that point and the next, and Return puts them in the same fill (first point still
// first) as one undoable step. A fill whose new outline crosses itself is refused; a project saved part way through
// opens still drawing into the same fill.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class DrawIntoClosedShapeTests: XCTestCase {
    private let square = [Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)]

    @MainActor private func setUp(_ state: EditorState) -> RunObject {
        var fill = RunObject(name: "Patch", nodes: square.map { PathNode($0) }, color: ThreadColor.palette[0])
        fill.digitizing = DigitizingSettings(kind: .fill); fill.closed = true
        state.design.objects = [fill]
        state.tool = .fill; state.selection = [fill.id]
        return fill
    }

    @MainActor func testNewPointsGoAfterThePickedPoint() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let fill = setUp(state)
        state.drawInto(fill.id, after: 1)
        state.draft += [PathNode(Point(15, 3)), PathNode(Point(15, 7))]
        state.finishPath()
        XCTAssertEqual(state.design.objects.count, 1, "no new object")
        XCTAssertEqual(state.design.objects[0].id, fill.id)
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point),
                       [Point(0, 0), Point(10, 0), Point(15, 3), Point(15, 7), Point(10, 10), Point(0, 10)])
        XCTAssertTrue(state.draft.isEmpty); XCTAssertNil(state.drawingInto); XCTAssertEqual(state.selection, [fill.id])
        document.undoManager?.undo()
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point), square, "one undo takes the new points away")
    }

    @MainActor func testAnOutlineThatCrossesItselfIsRefused() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let fill = setUp(state)
        state.drawInto(fill.id, after: 1)
        state.draft += [PathNode(Point(-5, 15))]   // between (10, 0) and (10, 10), across the fill to the far side
        state.finishPath()
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point), square, "the fill is unchanged")
        XCTAssertFalse(state.draft.isEmpty, "the drawing stays, to fix with Delete")
    }

    @MainActor func testPointingAtAPointOfTheFillOffersToAddAfterIt() {
        _ = NSApplication.shared
        let state = EditorState(), fill = setUp(state)
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 600); state.canvas = canvas
        canvas.updateContinueHover(at: canvas.screen(Point(10, 10)))
        XCTAssertEqual(canvas.hoveredPick, .after(fill.id, index: 2))
        XCTAssertEqual(state.status, "Click to add points to ‘Patch’ between this point and the next one (marked).")
        state.tool = .run
        canvas.updateContinueHover(at: canvas.screen(Point(10, 10)))
        XCTAssertNil(canvas.hoveredPick, "the Running tool doesn't pick up a fill")
    }

    @MainActor func testASavedProjectOpensStillDrawingIntoTheFill() throws {
        _ = NSApplication.shared
        let source = DesignDocument(), fill = setUp(source.state)
        source.state.drawInto(fill.id, after: 1)
        source.state.draft += [PathNode(Point(15, 5))]
        let saved = try source.fileWrapper(ofType: "Embroidery Project")
        let loaded = DesignDocument()
        try loaded.read(from: saved, ofType: "Embroidery Project")
        XCTAssertEqual(loaded.state.drawingInto?.id, fill.id); XCTAssertNil(loaded.state.continuing)
        loaded.state.finishPath()
        XCTAssertEqual(loaded.state.design.objects.count, 1)
        XCTAssertEqual(loaded.state.design.objects[0].nodes.map(\.point), [Point(0, 0), Point(10, 0), Point(15, 5), Point(10, 10), Point(0, 10)])
    }
}
