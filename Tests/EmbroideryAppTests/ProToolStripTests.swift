// Checks that the Pro view's tools are all one click away: every tool has its own button, in the two-row strip and
// in the left rail alike, and no button appears twice.
import XCTest
@testable import EmbroideryApp
import EmbroideryCore

final class ProToolStripTests: XCTestCase {
    @MainActor func testEveryToolHasItsOwnButtonInBothLayouts() {
        let strip = ToolStrip.proGroups.flatMap(\.commands), rail = ToolStrip.railGroups.flatMap { $0 }
        XCTAssertEqual(Set(strip).count, strip.count, "no button twice in the strip")
        XCTAssertEqual(strip, rail, "the rail has the same buttons, in the same order")
        // Every tool you can switch to, and every Show option (once a list behind a button), is out on its own.
        let tools = Set(Tool.forCommand.keys)
        XCTAssertTrue(tools.isSubset(of: Set(strip)), "missing: \(tools.subtracting(strip).map(\.rawValue).sorted())")
        let showOptions: Set<CommandID> = [.showStitches, .showOutlines, .showConnectors, .needles, .showUnderlay, .hideOthers]
        XCTAssertTrue(showOptions.isSubset(of: Set(strip)))
        // The rail sits three across, so every group but the last fills whole rows.
        XCTAssertTrue(ToolStrip.railGroups.dropLast().allSatisfy { $0.count >= 3 })
    }

    func testOlderPreferencesKeepTheToolsOnTop() throws {
        // A preferences file saved before the setting existed has no proToolsOnLeft, so the tools stay across the top.
        let old = try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(PreferenceData()))
        XCTAssertNil(old.proToolsOnLeft)
        var moved = PreferenceData(); moved.proToolsOnLeft = true
        XCTAssertEqual(try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(moved)).proToolsOnLeft, true)
    }
}
