// Checks the Show list's choices: Hide Unselected keeps only the selection in view (everything when nothing is
// selected), hidden objects stay hidden, connectors follow the view until switched, and choices carry over to the
// next design.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ShowOptionsTests: XCTestCase {
    @MainActor func testHideUnselectedShowsOnlyTheSelection() {
        let state = EditorState()
        var hidden = RunObject(name: "Hidden", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))]); hidden.visible = false
        let a = RunObject(name: "A", nodes: [PathNode(Point(0, 5)), PathNode(Point(10, 5))])
        let b = RunObject(name: "B", nodes: [PathNode(Point(0, 9)), PathNode(Point(10, 9))])
        state.design.objects = [hidden, a, b]
        XCTAssertEqual(state.design.objects.map(state.isShown), [false, true, true])

        state.hideOthers = true
        XCTAssertEqual(state.design.objects.map(state.isShown), [false, true, true], "with nothing selected, everything shows")
        state.selection = [a.id]
        XCTAssertEqual(state.design.objects.map(state.isShown), [false, true, false])
        state.selection = [hidden.id]
        XCTAssertEqual(state.design.objects.map(state.isShown), [false, false, false], "selecting a hidden object doesn't show it")
    }

    @MainActor func testConnectorsFollowTheViewUntilSwitched() {
        let state = EditorState()
        XCTAssertEqual(state.showsConnectors, !Preferences.shared.threadView, "shown in the stitch view, hidden in Thread View")
        state.connectors = true
        XCTAssertTrue(state.showsConnectors)
        state.connectors = false
        XCTAssertFalse(state.showsConnectors)
    }

    @MainActor func testShowChoicesCarryOverToTheNextDesign() {
        let before = Preferences.shared.data.shown
        defer { Preferences.shared.data.shown = before; Preferences.shared.save(announce: false) }
        let first = EditorState()
        first.needles = false; first.showOutlines = true; first.grid = false
        let next = EditorState()
        XCTAssertFalse(next.needles, "needle points stay off in the next design")
        XCTAssertTrue(next.showOutlines)
        XCTAssertFalse(next.grid)
        XCTAssertFalse(next.hideOthers, "Hide unselected always starts off: it needs a selection")
        next.needles = true
        XCTAssertTrue(EditorState().needles, "switching back on is remembered too")
    }
}
