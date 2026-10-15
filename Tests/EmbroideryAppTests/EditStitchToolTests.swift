// Checks the Edit Stitch tool: deleting and adding needle points saves hand-edited stitches, and changing a
// setting afterwards replaces them with fresh stitches, with a warning.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class EditStitchToolTests: XCTestCase {
    @MainActor func testDeleteAndAddNeedlePointsThenASettingChangeDropsThem() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let line = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(20, 0))], color: ThreadColor.palette[0])
        state.design.objects = [line]; state.selection = [line.id]
        state.startStitchEdit()
        XCTAssertEqual(state.tool, .stitchEdit)
        let fresh = state.stitchSections
        XCTAssertGreaterThan(fresh.first?.points.count ?? 0, 3)

        state.selectedStitches = [StitchRef(section: 0, index: 1)]
        state.deleteSelectedStitches()
        XCTAssertEqual(state.design.objects[0].stitchEdits?.sections[0].points.count, fresh[0].points.count - 1)
        XCTAssertEqual(state.stitchSections[0].points.count, fresh[0].points.count - 1, "Edit Stitch now shows the edited stitches")

        state.insertStitch(at: Point(10, 0.1), reach: 1)
        XCTAssertEqual(state.design.objects[0].stitchEdits?.sections[0].points.count, fresh[0].points.count)
        XCTAssertEqual(state.selectedStitches.count, 1, "the new point is selected, ready to drag")

        state.editSelected("Stitch Length") { $0.stitchLength = 1.5 }
        XCTAssertNil(state.design.objects[0].stitchEdits, "a new setting means fresh stitches")
        XCTAssertTrue(state.status.contains("replaced by fresh ones"))
    }
}
