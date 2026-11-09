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

    /// Numbers show at most two decimals and no trailing zeros; counts show none.
    @MainActor func testNumbersDropTrailingZeros() {
        func shown(_ value: Double, whole: Bool = false) -> String {
            NumberField(value: value, range: -1000...1000, commit: { _ in }, focusCanvas: {}, whole: whole).text
        }
        XCTAssertEqual(shown(100), "100")
        XCTAssertEqual(shown(0.4), "0.4")
        XCTAssertEqual(shown(0.65), "0.65")
        XCTAssertEqual(shown(2.004), "2", "rounded to two decimals first")
        XCTAssertEqual(shown(-0.001), "0", "never \"-0\"")
        XCTAssertEqual(shown(-12.5), "-12.5")
        XCTAssertEqual(shown(3, whole: true), "3")
    }
}
