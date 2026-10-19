// Locking and hiding from the sewing order: a row's lock or menu sets every object of the row (a group's or
// lettering's too) the same way, as one Undo step.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class LayerControlsTests: XCTestCase {
    @MainActor func testLockAndHideSetTheWholeRowAsOneUndoStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let a = RunObject(name: "A", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))], color: ThreadColor.palette[0])
        var b = RunObject(name: "B", nodes: [PathNode(Point(0, 5)), PathNode(Point(10, 5))], color: ThreadColor.palette[1])
        b.locked = true   // one already locked: the row's lock locks both rather than flipping each
        state.edit("Add") { $0.objects = [a, b] }
        document.undoManager?.removeAllActions()

        XCTAssertFalse(state.allLocked([a.id, b.id]))
        state.setLocked([a.id, b.id], true)
        XCTAssertTrue(state.allLocked([a.id, b.id]))
        document.undoManager?.undo()
        XCTAssertEqual(document.state.design.objects.map(\.locked), [false, true], "one Undo puts both back")

        state.setVisible([a.id], false)
        XCTAssertEqual(state.design.objects.map(\.visible), [false, true], "only that row's object")
        XCTAssertFalse(state.allLocked([]), "an empty row isn't locked")
    }
}
