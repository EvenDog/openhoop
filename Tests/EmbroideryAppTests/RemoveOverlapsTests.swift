// Checks Remove Overlaps end to end: it switches on "Cut out shapes sewn on top" for the fills that something sewn
// later overlaps (the selected ones, or all with nothing selected), as one undoable step, and choosing it again
// switches it off.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class RemoveOverlapsTests: XCTestCase {
    private func square(_ name: String, x: Double, size: Double) -> RunObject {
        let h = size / 2
        var o = RunObject(name: name, nodes: [Point(x - h, -h), Point(x + h, -h), Point(x + h, h), Point(x - h, h)].map { PathNode($0) }, color: ThreadColor.palette[0])
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill)
        return o
    }

    @MainActor func testRemoveThenRestoreOverlaps() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let base = square("Base", x: 0, size: 40), top = square("Top", x: 0, size: 20), other = square("Other", x: 60, size: 20)
        let cover = square("Cover", x: 60, size: 10)
        state.design.objects = [base, other, top, cover]
        func cuts(_ name: String) -> Bool { state.design.objects.first { $0.name == name }?.settings.cutOutOverlaps == true }

        // Only Other selected: just it changes.
        state.selection = [other.id]
        state.removeOverlaps()
        XCTAssertTrue(cuts("Other")); XCTAssertFalse(cuts("Base"))
        document.undoManager?.undo()
        XCTAssertFalse(cuts("Other"), "one undo")

        // Nothing selected: every fill with something on top (not Top or Cover, which have nothing after them).
        state.selection = []
        state.removeOverlaps()
        XCTAssertTrue(cuts("Base")); XCTAssertTrue(cuts("Other")); XCTAssertFalse(cuts("Top")); XCTAssertFalse(cuts("Cover"))
        XCTAssertTrue(state.status.hasPrefix("Overlaps removed: 2 fills"), state.status)
        // Again: they all have it on, so it goes off.
        state.removeOverlaps()
        XCTAssertFalse(cuts("Base")); XCTAssertFalse(cuts("Other"))
        XCTAssertTrue(state.status.hasPrefix("Overlaps restored"), state.status)

        // Nothing on top of the selection: says so and changes nothing.
        state.selection = [cover.id]
        state.removeOverlaps()
        XCTAssertFalse(cuts("Cover")); XCTAssertTrue(state.status.hasPrefix("Nothing sewn on top"), state.status)
    }
}
