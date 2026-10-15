// Checks that the selection remembers the order objects were clicked in, which Sequence by Selection Order and
// aligning (to the last one picked) use.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class SelectionOrderTests: XCTestCase {
    @MainActor func testSelectionRemembersClickOrder() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let objects = ["A", "B", "C", "D"].map { RunObject(name: $0, nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))]) }
        state.design.objects = objects
        let (a, b, c, d) = (objects[0].id, objects[1].id, objects[2].id, objects[3].id)
        state.select(c); state.select(a, extend: true); state.select(d, extend: true)
        XCTAssertEqual(state.selectionOrder, [c, a, d])
        state.select(a, extend: true)   // Shift-click again takes it out
        XCTAssertEqual(state.selectionOrder, [c, d])
        state.selection = Set([a, b, c, d])   // all at once (Select All) adds the rest in sewing order
        XCTAssertEqual(state.selectionOrder, [c, d, a, b])
        state.select(b)   // a plain click starts again
        XCTAssertEqual(state.selectionOrder, [b])

        state.select(d); state.select(b, extend: true)
        state.edit("Sequence") { $0.sequence(state.selectionOrder) }   // what the command does (tests have no design window)
        XCTAssertEqual(state.design.objects.map(\.name), ["A", "D", "B", "C"])
    }
}
