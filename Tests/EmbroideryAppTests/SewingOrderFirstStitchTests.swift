// Checks that the Sewing order panel comes to the front when a design gets its first object, opening if it was
// closed, and that later objects leave the panels as they are.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class SewingOrderFirstStitchTests: XCTestCase {
    @MainActor func testTheFirstObjectShowsSewingOrder() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // tests use temporary preferences
        /// The tab showing in the group that holds Sewing order (nil when it's closed).
        func frontTab() -> PanelID? {
            let panels = Preferences.shared.panels
            return (panels.left + panels.right).first { $0.panels.contains(.sewingOrder) }?.selected
        }
        func line(_ y: Double) -> RunObject { RunObject(name: "Line", nodes: [PathNode(Point(0, y)), PathNode(Point(20, y))]) }

        Preferences.shared.updatePanels { $0.show(.design) }   // another tab in front
        XCTAssertNotEqual(frontTab(), .sewingOrder)
        state.edit("Add") { $0.objects.append(line(0)) }
        XCTAssertEqual(frontTab(), .sewingOrder, "the first object brings it to the front")

        Preferences.shared.updatePanels { $0.show(.design) }
        state.edit("Add") { $0.objects.append(line(10)) }
        XCTAssertEqual(frontTab(), .design, "later objects leave the panels alone")

        state.edit("Clear") { $0.objects = [] }
        Preferences.shared.updatePanels { $0.hide(.sewingOrder) }
        XCTAssertFalse(Preferences.shared.panels.isVisible(.sewingOrder))
        state.edit("Add") { $0.objects.append(line(0)) }
        XCTAssertTrue(Preferences.shared.panels.isVisible(.sewingOrder), "a closed panel opens")
        XCTAssertEqual(frontTab(), .sewingOrder)
    }
}
