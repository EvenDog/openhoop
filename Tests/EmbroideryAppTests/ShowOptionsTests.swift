// Checks the Show list's choices: Hide Unselected keeps only the selection in view (everything when nothing is
// selected), hidden objects stay hidden, and connectors follow the view until switched.
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
}
