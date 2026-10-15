// Number fields: Return commits a typed value once, even though focus then leaves the field (which also commits).
import XCTest
import AppKit
@testable import EmbroideryApp

final class NumberFieldTests: XCTestCase {
    @MainActor func testReturnCommitsOnce() {
        var commits: [Double] = []
        let field = NumberField(value: 0, range: -360...360, commit: { commits.append($0) }, focusCanvas: {})
        let coordinator = field.makeCoordinator()
        let text = NSTextField(string: "45")
        // Return, then the end of editing that follows when the canvas takes focus.
        XCTAssertTrue(coordinator.control(text, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: text))
        XCTAssertEqual(commits, [45], "A \"rotate by\" field must not turn the selection twice")
        // Leaving the field without Return still commits a changed value.
        text.stringValue = "30"
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: text))
        XCTAssertEqual(commits, [45, 30])
        // Values outside the range are refused.
        text.stringValue = "400"
        XCTAssertTrue(coordinator.control(text, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(commits, [45, 30])
    }
}
