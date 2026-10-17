// Checks Properties › Width for satin borders and satin lines: a new width rebuilds the selected satin as one Undo
// step, and a width that can't sew changes nothing and says why.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class SatinWidthTests: XCTestCase {
    @MainActor func testSettingABordersWidthIsOneUndoableStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        var patch = RunObject(name: "Patch", nodes: [Point(-20, -20), Point(20, -20), Point(20, 20), Point(-20, 20)].map { PathNode($0) })
        patch.digitizing = DigitizingSettings(kind: .fill); patch.closed = true
        let border = try SatinBorder.around(patch, width: 3, color: ThreadColor.palette[1]).object
        state.edit("Add") { $0.objects = [patch, border] }
        // In a test everything happens in one event, which Undo would treat as one step; start the history here.
        document.undoManager?.removeAllActions()
        state.selection = [border.id]

        state.setSatinWidth(5)
        XCTAssertEqual(try XCTUnwrap(SatinLine.evenWidth(of: state.design.objects[1])), 5, accuracy: 0.05)
        XCTAssertEqual(state.design.objects[0], patch, "the shape it goes around is untouched")
        document.undoManager?.undo()
        XCTAssertEqual(try XCTUnwrap(SatinLine.evenWidth(of: document.state.design.objects[1])), 3, accuracy: 0.05)
    }

    @MainActor func testAWidthThatCantSewChangesNothing() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var line = RunObject(name: "Corner", nodes: [Point(-20, 0), Point(0, 0), Point(0, 20)].map { PathNode($0) })
        line.digitizing = DigitizingSettings(kind: .run)
        let satin = try SatinLine.column(from: line, width: 4)
        state.edit("Add") { $0.objects = [satin] }
        state.selection = [satin.id]
        let before = state.design
        state.setSatinWidth(8)   // its sharp turn was rounded for 4 mm
        XCTAssertEqual(state.design, before)
        XCTAssertTrue(state.status.contains("Try a narrower width"), state.status)
    }
}
