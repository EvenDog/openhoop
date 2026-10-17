// Checks Use Line as Fill Guide from the app: it needs a fill and an open line selected, links them as one undoable
// step, and reshaping the guide (or duplicating the pair) keeps the fill following its own guide.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class FillGuideAppTests: XCTestCase {
    @MainActor func testLineBecomesTheFillsGuide() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var fill = RunObject(name: "Leaf", nodes: [Point(0, 0), Point(30, 0), Point(30, 20), Point(0, 20)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        let line = RunObject(name: "Line", nodes: [Point(-2, 5), Point(15, 14), Point(32, 5)].map { PathNode($0) })
        state.edit("Setup") { $0.objects = [fill, line] }

        state.selection = [fill.id]
        XCTAssertNil(state.fillAndGuideLine)
        state.useSelectedLineAsFillGuide()
        XCTAssertTrue(state.status.hasPrefix("Select a fill and an open line"), state.status)

        state.selection = [fill.id, line.id]
        state.useSelectedLineAsFillGuide()
        XCTAssertTrue(state.status.hasPrefix("The line now guides the fill"), state.status)
        XCTAssertEqual(state.design.objects[1].guideFor, fill.id)
        XCTAssertEqual(state.design.objects[0].settings.fillStyle, .guided)
        XCTAssertEqual(document.undoManager?.undoActionName, "Use Line as Fill Guide", "one undoable step")

        // Moving a guide point (any edit) updates the fill's copy of the guide.
        state.edit("Move Node") { $0.objects[1].nodes[1].point = Point(15, 18) }
        XCTAssertEqual(state.design.objects[0].settings.guideLine, state.design.objects[1].outlinePaths[0])

        // A duplicated pair: the copied guide guides the copied fill.
        state.selection = [fill.id, line.id]
        state.duplicateSelection()
        let copies = state.design.objects.filter { state.selection.contains($0.id) }
        XCTAssertEqual(copies.first { $0.kind == .vector }?.guideFor, copies.first { $0.kind == .fill }?.id)
    }
}
