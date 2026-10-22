// The panel layout saved in preferences, including settings saved while OpenHoop had both Guided and Pro views.
import XCTest
@testable import EmbroideryApp
import EmbroideryCore

final class PanelPreferenceTests: XCTestCase {
    func testTheProArrangementIsKeptAndTheGuidedOneLeftUnread() throws {
        // Saved with both views: the Guided arrangement under "panels", the Pro one (threads hidden) under "proPanels".
        let guided = PanelLayout(left: [PanelGroup([.threads])], right: [PanelGroup([.properties])])
        var pro = PanelLayout.standard; pro.hide(.threads)
        let both = #"{"id":"6D7A4C2E-1F1B-4B8F-9C1A-2B3C4D5E6F70","name":"Mine","panels":"# + String(decoding: try JSONEncoder().encode(guided), as: UTF8.self)
            + #","proPanels":"# + String(decoding: try JSONEncoder().encode(pro), as: UTF8.self) + "}"
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: Data(both.utf8)).panelLayout, pro)
        // Only a Guided arrangement (or none, or the oldest settings): the standard layout.
        let onlyGuided = #"{"id":"6D7A4C2E-1F1B-4B8F-9C1A-2B3C4D5E6F70","name":"Mine","panels":"# + String(decoding: try JSONEncoder().encode(guided), as: UTF8.self) + "}"
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: Data(onlyGuided.utf8)).panelLayout, .standard)
        let oldest = #"{"id":"6D7A4C2E-1F1B-4B8F-9C1A-2B3C4D5E6F70","name":"Mine","inspectorVisible":false,"paletteVisible":false,"inspectorOnLeft":true,"objectsWidth":240,"inspectorWidth":300}"#
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: Data(oldest.utf8)).panelLayout, .standard)
        XCTAssertEqual(Workspace().panelLayout, .standard)
        // A changed arrangement saves and reopens.
        var saved = Workspace(); saved.panels = guided
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(saved)).panelLayout, guided)
    }

    func testPreferencesFromTheGuidedViewStillOpen() throws {
        // The view switch, the More settings fold and a Pro View key are left over in older preferences.
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PreferenceData())) as? [String: Any])
        dictionary["proView"] = false; dictionary["guidedMoreOpen"] = true
        XCTAssertNoThrow(try JSONDecoder().decode(PreferenceData.self, from: JSONSerialization.data(withJSONObject: dictionary)))
        var profile = ShortcutProfile(); profile.bindings["proView"] = [.init("p", 5)]
        XCTAssertNoThrow(try profile.validate())
        XCTAssertNil(profile.command(for: .init("p", 5), context: .canvas), "⌥⌘P does nothing now")
        XCTAssertNoThrow(try ShortcutProfile().validate())
    }

    /// A tool's tooltip names it, shows its key, and says what it does.
    @MainActor func testPickingAToolWithChoicesOpensProperties() {
        // The next shape's choices are in Properties, so a shape tool opens the panel if it was closed.
        let preferences = Preferences.shared, before = preferences.data.workspace
        defer { preferences.data.workspace = before; preferences.save(announce: false) }
        preferences.updatePanels { $0.hide(.properties) }
        let state = EditorState()
        state.tool = .run
        XCTAssertFalse(preferences.panels.isVisible(.properties), "a tool without choices leaves the panel closed")
        state.tool = .basicShape
        XCTAssertTrue(preferences.panels.isVisible(.properties))
        XCTAssertTrue(ToolOptions.applies(to: .node)); XCTAssertTrue(ToolOptions.applies(to: .stitchEdit)); XCTAssertFalse(ToolOptions.applies(to: .select))
    }

    @MainActor func testToolTooltipNamesTheToolItsKeyAndWhatItDoes() {
        let hint = Preferences.shared.hint(.knifeTool)
        XCTAssertTrue(hint.hasPrefix("Knife"), hint)
        XCTAssertTrue(hint.hasSuffix(CommandID.knifeTool.explanation), hint)
        XCTAssertFalse(Preferences.shared.hint(.lettering).contains("…"), "no trailing dots from menu titles")
    }
}
