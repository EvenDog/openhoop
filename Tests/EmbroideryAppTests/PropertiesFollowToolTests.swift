// Picking a shape tool while something is selected switches Properties to the tool's Next shape choices; selecting
// something (such as the shape just drawn) shows its properties again.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class PropertiesFollowToolTests: XCTestCase {
    @MainActor func testPickingAShapeToolShowsItsChoices() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let heart = RunObject(name: "Heart 1", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0)), PathNode(Point(5, 8))], color: .palette[0])
        state.edit("Add") { $0.objects = [heart] }
        state.selection = [heart.id]
        XCTAssertFalse(ToolOptions.showsNextShape(state), "The Select tool shows the heart's properties")

        // Picking Rectangle, as its button does (Application.swift): the choices show though the heart stays selected.
        state.tool = .rectangle; state.toolPicked = NextShapeOptions.shows(state.tool)
        XCTAssertTrue(ToolOptions.showsNextShape(state))
        XCTAssertEqual(state.selection, [heart.id])

        // Selecting something brings its properties back.
        state.selection = []; state.selection = [heart.id]
        XCTAssertFalse(state.toolPicked)
        XCTAssertFalse(ToolOptions.showsNextShape(state))
        // With nothing selected, the choices show as before.
        state.selection = []
        XCTAssertTrue(ToolOptions.showsNextShape(state))

        // Drawing a rectangle selects it, so Properties shows the new rectangle, and goes back to Select.
        state.selection = [heart.id]
        state.tool = .rectangle; state.toolPicked = NextShapeOptions.shows(state.tool)
        state.draft = ShapeGeometry.nodes(.rectangle, in: (Point(20, 20), Point(40, 30)))
        state.finishShape(.rectangle)
        XCTAssertFalse(state.selection.contains(heart.id))
        XCTAssertFalse(ToolOptions.showsNextShape(state))
        XCTAssertEqual(state.tool, .select)

        // Tools without Next shape choices never switch Properties.
        state.selection = [heart.id]
        state.tool = .knife; state.toolPicked = NextShapeOptions.shows(state.tool)
        XCTAssertFalse(ToolOptions.showsNextShape(state))
    }
}
