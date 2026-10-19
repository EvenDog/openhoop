// Checks that every command's icon can be shown: each name is either a built-in Apple symbol or one of the icons
// OpenHoop draws, and the drawn ones take the color of the text around them.
import XCTest
import AppKit
@testable import EmbroideryApp
import EmbroideryCore

final class DrawnIconTests: XCTestCase {
    func testEveryCommandHasAnIcon() {
        for command in CommandID.allCases {
            let found = NSImage.drawn(command.symbol, size: 14) != nil || NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil) != nil
            XCTAssertTrue(found, "\(command.rawValue) has no icon named \(command.symbol)")
        }
    }

    func testSatinIconIsDrawnAsATemplate() throws {
        let icon = try XCTUnwrap(NSImage.drawn(CommandID.satinTool.symbol, size: 14))
        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, NSSize(width: 17, height: 17))
        XCTAssertNil(NSImage.drawn("line.3.horizontal", size: 14), "built-in names aren't drawn")
    }

    func testMonogramIconIsDrawnAsATemplate() throws {
        let icon = try XCTUnwrap(NSImage.drawn(CommandID.addMonogram.symbol, size: 14))
        XCTAssertTrue(icon.isTemplate)
        XCTAssertNotNil(icon.cgImage(forProposedRect: nil, context: nil, hints: nil), "it draws")
    }
}
