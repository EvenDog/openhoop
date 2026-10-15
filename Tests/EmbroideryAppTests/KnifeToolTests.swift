// Checks the Knife tool end to end: points clicked across a fill, then Return, cut it into pieces as one undoable
// step, select them, and keep the Knife on.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class KnifeToolTests: XCTestCase {
    @MainActor func testReturnCutsAlongTheClickedLine() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var leaf = RunObject(name: "Leaf", nodes: [Point(-5, -5), Point(5, -5), Point(5, 5), Point(-5, 5)].map { PathNode($0) }, color: ThreadColor.palette[0])
        leaf.closed = true; leaf.digitizing = DigitizingSettings(kind: .fill)
        state.design.objects = [leaf]
        state.tool = .knife
        state.draft = [PathNode(Point(0, -8)), PathNode(Point(0, 8))]
        state.finishPath()
        XCTAssertEqual(state.design.objects.map(\.name), ["Leaf", "Leaf 2"])
        XCTAssertEqual(state.selection, Set(state.design.objects.map(\.id)))
        XCTAssertTrue(state.draft.isEmpty); XCTAssertEqual(state.tool, .knife)
        document.undoManager?.undo()
        XCTAssertEqual(state.design.objects.count, 1, "one undo puts the leaf back")
    }
}
