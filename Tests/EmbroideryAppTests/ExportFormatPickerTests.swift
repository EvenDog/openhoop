// The Format popup in the export save window: it starts on the format last exported with, and picking another
// format changes the file name's extension.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ExportFormatPickerTests: XCTestCase {
    @MainActor func testPickingAFormatChangesTheExtension() {
        _ = NSApplication.shared
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Patch"
        let picker = ExportFormatPicker(panel: panel, threadListOnly: false, remembered: nil)
        XCTAssertEqual(picker.choice.id, "pes6", "PES 6 until something else has been exported")
        XCTAssertEqual(panel.nameFieldStringValue, "Patch.pes")

        picker.popup.selectItem(withTitle: "DST — Tajima"); picker.popup.sendAction(picker.popup.action, to: picker.popup.target)
        XCTAssertEqual(picker.choice.format, .dst)
        XCTAssertEqual(panel.nameFieldStringValue, "Patch.dst")

        picker.popup.selectItem(withTitle: "PES 1 — older Brother machines"); picker.popup.sendAction(picker.popup.action, to: picker.popup.target)
        XCTAssertEqual(picker.choice.format, .pes)
        XCTAssertEqual(picker.choice.pesVersion, 1)
        XCTAssertEqual(panel.nameFieldStringValue, "Patch.pes")
    }

    @MainActor func testStartsOnTheRememberedFormat() {
        _ = NSApplication.shared
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Design"
        let picker = ExportFormatPicker(panel: panel, threadListOnly: false, remembered: "jef")
        XCTAssertEqual(picker.choice.format, .jef)
        XCTAssertEqual(panel.nameFieldStringValue, "Design.jef")
        XCTAssertEqual(picker.popup.numberOfItems, ExportFormatPicker.choices.count)
    }

    @MainActor func testTheThreadListStaysACSVFile() {
        _ = NSApplication.shared
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Design"
        let picker = ExportFormatPicker(panel: panel, threadListOnly: true, remembered: "pes1")
        XCTAssertEqual(picker.popup.numberOfItems, ExportFormatPicker.choices.count - 1, "One PES entry: both versions list the same threads")
        XCTAssertEqual(picker.choice.id, "pes6")
        XCTAssertEqual(panel.nameFieldStringValue, "Design.csv")
    }
}
