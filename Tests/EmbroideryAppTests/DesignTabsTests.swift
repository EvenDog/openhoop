// Checks OpenHoop's own design tabs: new designs join the front window as tabs, the window's document link
// follows the tab on screen, and closing a design takes out only its tab (the window closes with the last one).
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class DesignTabsTests: XCTestCase {
    func testTabPickedAfterClosingIsTheRightNeighborElseTheLeft() {
        XCTAssertEqual(tabToSelect(afterClosing: 0, count: 3), 0)   // the old second tab moves into first place
        XCTAssertEqual(tabToSelect(afterClosing: 1, count: 3), 1)
        XCTAssertEqual(tabToSelect(afterClosing: 2, count: 3), 1)   // the last tab hands over to its left
        XCTAssertNil(tabToSelect(afterClosing: 0, count: 1))
    }

    @MainActor func testDesignsShareOneWindowAndTheDocumentLinkFollowsTheTab() throws {
        _ = NSApplication.shared
        let first = DesignDocument(), second = DesignDocument()
        first.makeWindowControllers()
        let window = try XCTUnwrap(EditorWindowController.host(of: first))
        second.makeWindowControllers()
        XCTAssertTrue(EditorWindowController.host(of: second) === window, "a new design joins the open window as a tab")
        XCTAssertEqual(window.panes.count, 2)
        XCTAssertTrue(window.document === second)
        XCTAssertTrue(window.state === second.state)
        XCTAssertTrue(first.windowControllers.isEmpty, "only the design on screen is linked to the window")
        XCTAssertEqual(window.tabModel.tabs.count, 2)

        window.select(window.panes[0])
        XCTAssertTrue(window.document === first)
        XCTAssertEqual(first.windowControllers.count, 1)
        XCTAssertTrue(second.windowControllers.isEmpty)

        window.selectNeighbor(1)
        XCTAssertTrue(window.document === second)
        window.selectNeighbor(1)   // wraps around
        XCTAssertTrue(window.document === first)

        // Closing the design on screen shows its neighbor and leaves the window open.
        first.close()
        XCTAssertEqual(window.panes.count, 1)
        XCTAssertTrue(window.document === second)
        XCTAssertNotNil(window.window)
        XCTAssertEqual(window.tabModel.tabs.map(\.title), [second.displayName])
        second.fileURL = URL(fileURLWithPath: "/tmp/Team patch.stitchproj")
        XCTAssertEqual(window.tabModel.tabs.map(\.title), ["Team patch"], "a saved design's tab shows its name without the extension")
        second.fileURL = nil

        // The last design takes the window with it.
        second.close()
        XCTAssertTrue(window.panes.isEmpty)
        XCTAssertNil(EditorWindowController.host(of: second))
        XCTAssertNil(EditorWindowController.tabHost().flatMap { $0 === window ? $0 : nil }, "a closed window takes no new tabs")
    }

    @MainActor func testClosingADesignInTheBackgroundKeepsTheOneOnScreen() throws {
        _ = NSApplication.shared
        let first = DesignDocument(), second = DesignDocument(), third = DesignDocument()
        first.makeWindowControllers(); second.makeWindowControllers(); third.makeWindowControllers()
        let window = try XCTUnwrap(EditorWindowController.host(of: first))
        XCTAssertTrue(window.document === third)
        second.close()
        XCTAssertEqual(window.panes.map { $0.document }, [first, third])
        XCTAssertTrue(window.document === third)
        first.close(); third.close()
    }

    @MainActor func testClosingABackgroundTabWithItsCloseButtonStaysOnTheCurrentDesign() throws {
        _ = NSApplication.shared
        let first = DesignDocument(), second = DesignDocument()
        first.makeWindowControllers(); second.makeWindowControllers()
        let window = try XCTUnwrap(EditorWindowController.host(of: first))
        XCTAssertTrue(window.document === second)
        window.closeTab(window.panes[0])   // the background tab has no unsaved changes, so it closes without asking
        let closed = expectation(description: "background tab closed")
        DispatchQueue.main.async { closed.fulfill() }
        wait(for: [closed], timeout: 2)
        XCTAssertEqual(window.panes.map { $0.document }, [second])
        XCTAssertTrue(window.document === second)
        second.close()
    }

    func testTabShortcutsDoNotClash() throws {
        let profile = ShortcutProfile()
        XCTAssertEqual(profile.command(for: KeyBinding("tab", 8), context: .canvas), .nextTab)
        XCTAssertEqual(profile.command(for: KeyBinding("tab", 10), context: .canvas), .previousTab)
        XCTAssertEqual(profile.command(for: KeyBinding("]", 3), context: .canvas), .nextTab)
        try profile.validate()
    }

    /// A design reloaded from disk while its tab is in the background (say, changed by another app) used to keep
    /// showing no stitches until it was edited. Switching to its tab now works them out.
    @MainActor func testADesignReloadedInTheBackgroundGetsItsStitchesWhenShown() throws {
        _ = NSApplication.shared
        let source = DesignDocument()
        source.state.design.objects = [RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(20, 0))], color: .palette[0])]
        source.state.revision += 1
        let saved = try source.fileWrapper(ofType: "Embroidery Project")   // no stitch preview saved: none was worked out
        let first = DesignDocument(), second = DesignDocument()
        first.makeWindowControllers(); second.makeWindowControllers()   // the second tab is in front
        let window = try XCTUnwrap(EditorWindowController.host(of: first))
        try first.read(from: saved, ofType: "Embroidery Project")
        XCTAssertEqual(first.state.plan.stitchCount, 0, "in the background, nothing is worked out yet")
        window.select(window.panes[0])
        let deadline = Date() + 10
        while first.state.compiledRevision != first.state.revision && Date() < deadline { RunLoop.main.run(until: Date() + 0.05) }
        XCTAssertGreaterThan(first.state.plan.stitchCount, 0)
        first.close(); second.close()
    }
}

