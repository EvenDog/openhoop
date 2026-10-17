// Checks renaming an object in place (the sewing order and Properties): only that object changes, spaces are
// trimmed, an empty name keeps the old one, and Undo puts the old name back.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class RenameTests: XCTestCase {
    @MainActor func testRenamingOneObjectIsOneUndoableStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let a = RunObject(name: "Tatami 1", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))])
        let b = RunObject(name: "Tatami 2", nodes: [PathNode(Point(0, 5)), PathNode(Point(10, 5))])
        state.edit("Add") { $0.objects = [a, b] }
        // In a test everything happens in one event, which Undo would treat as one step; start the history here.
        document.undoManager?.removeAllActions()

        state.rename(a.id, to: "  Big star  ")
        XCTAssertEqual(state.design.objects.map(\.name), ["Big star", "Tatami 2"], "only that object, with the spaces trimmed")
        state.rename(a.id, to: "   ")
        XCTAssertEqual(state.design.objects.first?.name, "Big star", "an empty name keeps the old one")

        document.undoManager?.undo()
        XCTAssertEqual(document.state.design.objects.map(\.name), ["Tatami 1", "Tatami 2"])
    }
}
