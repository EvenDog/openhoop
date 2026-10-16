// Checks the mm/inch switch: designs stay in millimeters, and lengths are converted only where they're shown or typed.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class LengthUnitTests: XCTestCase {
    func testConvertsAndLabelsLengths() {
        XCTAssertEqual(LengthUnit.inches.shown(25.4), 1)
        XCTAssertEqual(LengthUnit.inches.millimeters(2), 50.8)
        XCTAssertEqual(LengthUnit.millimeters.shown(12.5), 12.5)
        XCTAssertEqual(LengthUnit.millimeters.text(100), "100.0 mm")
        XCTAssertEqual(LengthUnit.inches.text(100), "3.94 in", "inches show one more decimal than mm")
        XCTAssertEqual(LengthUnit.inches.size(127, 177.8), "5.00 × 7.00 in")
        XCTAssertEqual(LengthUnit.millimeters.short(25), "25 mm", "short labels drop trailing zeros")
        XCTAssertEqual(LengthUnit.inches.short(38.1), "1.5 in")
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(0, 0), to: Point(3, 4), unit: .inches), "0.20 in · 53°", "Measure reads in inches too")
    }

    func testSnapsToWholeMillimetersOrTwentiethsOfAnInch() {
        XCTAssertEqual(LengthUnit.millimeters.snap(12.4), 12)
        XCTAssertEqual(LengthUnit.inches.snap(12.4), 12.7, accuracy: 1e-9, "0.5 in")
        XCTAssertEqual(LengthUnit.inches.snap(-1.0), -1.27, accuracy: 1e-9, "-0.05 in")
    }

    /// In inches, a field shows the length in inches and commits millimeters. Leaving a field you didn't change commits
    /// nothing, so the rounding of what it shows never nudges the design.
    @MainActor func testNumberFieldInInchesShowsInchesAndCommitsMillimeters() {
        var commits: [Double] = []
        let field = NumberField(value: 100, range: 0.1...1000, unit: .inches, commit: { commits.append($0) }, focusCanvas: {})
        let coordinator = field.makeCoordinator()
        XCTAssertEqual(field.text, "3.94")
        let text = NSTextField(string: field.text)
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: text))
        XCTAssertEqual(commits, [], "tabbing through an unchanged field leaves 100 mm alone")
        text.stringValue = "5"
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: text))
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0], 127, accuracy: 1e-9)
        text.stringValue = "40"   // 1016 mm, beyond the 1000 mm limit
        XCTAssertTrue(coordinator.control(text, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(commits.count, 1, "the limit is checked in millimeters")
    }

    @MainActor func testTheChoiceIsRememberedAndOldPreferencesMeanMillimeters() throws {
        let old = try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(PreferenceData()))
        XCTAssertNil(old.lengthUnit)
        var inches = PreferenceData(); inches.lengthUnit = .inches
        XCTAssertEqual(try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(inches)).lengthUnit, .inches)
    }
}
