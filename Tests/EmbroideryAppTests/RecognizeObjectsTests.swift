// Checks Recognize Objects end to end: the selected imported stitches become a fill, as one undoable step, with the
// new objects selected and a message saying what was found; other objects and unselected blocks stay as they are.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class RecognizeObjectsTests: XCTestCase {
    /// An imported block of tatami rows, 20 × 10 mm, 0.2 mm apart, with 2.5 mm stitches.
    private func importedRows(_ name: String) -> RunObject {
        var commands: [RawStitch] = [], y = 0.0, forward = true
        while y <= 10 {
            for x in stride(from: 0.0, through: 20, by: 2.5) { commands.append(RawStitch(.stitch, Point(forward ? x : 20 - x, y))) }
            y += 0.2; forward.toggle()
        }
        var block = RunObject(name: name, nodes: [], color: ThreadColor.palette[1])
        block.rawStitches = RawStitchBlock(start: Point(0, 0), commands: commands, sourceFormat: "pes")
        block.tieIn = false; block.tieOut = false; block.trimAfter = false
        return block
    }

    @MainActor func testRecognizeObjectsTurnsTheSelectedStitchesIntoAFill() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let chosen = importedRows("Chosen"), other = importedRows("Other")
        state.design.objects = [chosen, other]

        // Nothing imported selected: it says what to select.
        state.selection = []
        state.recognizeObjects()
        XCTAssertTrue(state.status.hasPrefix("Select imported stitches first"), state.status)

        state.selection = [chosen.id]
        state.recognizeObjects()
        XCTAssertEqual(state.design.objects.map(\.kind), [.fill, .raw], "the chosen block is a fill now, in its place")
        XCTAssertEqual(state.design.objects.last, other)
        XCTAssertEqual(state.selection, [state.design.objects[0].id], "the new fill is selected")
        XCTAssertTrue(state.status.hasPrefix("Recognized 1 fill and 0 satin columns"), state.status)
        XCTAssertEqual(state.design.objects[0].settings.spacing, 0.4, accuracy: 0.01, "rows 0.2 mm apart, measured across two")

        document.undoManager?.undo()
        XCTAssertEqual(state.design.objects, [chosen, other], "one undo puts the stitches back")
    }
}
