// Checks that a design window opens at the size and place it was last left at, rather than shrinking to its
// minimum size when its content is put in.
import XCTest
import AppKit
@testable import EmbroideryApp

final class WindowFrameTests: XCTestCase {
    @MainActor func testTheWindowReopensAtTheSizeItWasClosedAt() throws {
        _ = NSApplication.shared
        let key = "NSWindow Frame DesignWindow"
        let before = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }

        let first = DesignDocument()
        first.makeWindowControllers()
        let left = NSRect(x: 100, y: 150, width: 1000, height: 700)
        try XCTUnwrap(EditorWindowController.host(of: first)?.window).setFrame(left, display: false)
        first.close()

        let second = DesignDocument()
        second.makeWindowControllers()
        let window = try XCTUnwrap(EditorWindowController.host(of: second)?.window)
        XCTAssertEqual(window.frame, left, "the size it was left at, not the 900 × 600 minimum")
        second.close()
    }
}
