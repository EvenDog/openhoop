// Saved workspaces from before panels could be rearranged turn into the matching panel layout.
import XCTest
@testable import EmbroideryApp
import EmbroideryCore

final class PanelPreferenceTests: XCTestCase {
    func testOlderWorkspaceSettingsBecomeAPanelLayout() throws {
        // Settings saved by an older version: inspector on the left and hidden, thread palette hidden.
        let old = #"{"id":"6D7A4C2E-1F1B-4B8F-9C1A-2B3C4D5E6F70","name":"Mine","inspectorVisible":false,"paletteVisible":false,"inspectorOnLeft":true,"objectsWidth":240,"inspectorWidth":300}"#
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(old.utf8))
        XCTAssertNil(workspace.panels)
        let layout = workspace.panelLayout
        XCTAssertFalse(layout.isVisible(.properties)); XCTAssertFalse(layout.isVisible(.threads))
        XCTAssertEqual(layout.right.map(\.panels), [[.sewingOrder]], "The sides swap, as the inspector was on the left")
        XCTAssertEqual(layout.left.map(\.panels), [[.design, .reference]])
        XCTAssertEqual(layout.rightWidth, 240)
        // A fresh workspace is the standard layout, and a saved layout round-trips.
        XCTAssertEqual(Workspace().panelLayout.left, PanelLayout.standard.left); XCTAssertEqual(Workspace().panelLayout.right, PanelLayout.standard.right)
        var saved = Workspace(); saved.panels = PanelLayout(left: [PanelGroup([.threads])], right: [PanelGroup([.properties])])
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(saved)).panelLayout.left.map(\.panels), [[.threads]])
    }

    func testGuidedAndProKeepTheirOwnLayouts() throws {
        var workspace = Workspace()
        XCTAssertEqual(workspace.proPanelLayout, PanelLayout.pro, "Pro starts with its own standard layout")
        XCTAssertEqual(workspace.panelLayout.left, PanelLayout.standard.left)
        // Changing one view's arrangement leaves the other alone.
        var pro = workspace.proPanelLayout; pro.hide(.threads)
        workspace.setPanels(pro, pro: true)
        XCTAssertFalse(workspace.proPanelLayout.isVisible(.threads))
        XCTAssertTrue(workspace.panelLayout.isVisible(.threads))
        var guided = workspace.panelLayout; guided.hide(.reference)
        workspace.setPanels(guided, pro: false)
        XCTAssertTrue(workspace.proPanelLayout.isVisible(.reference)); XCTAssertFalse(workspace.panelLayout.isVisible(.reference))
        let reopened = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(reopened.proPanelLayout, workspace.proPanelLayout); XCTAssertEqual(reopened.panelLayout, workspace.panelLayout)
    }

    func testOlderPreferencesOpenInTheGuidedView() throws {
        // Preferences saved before the Pro view existed have no view or fold settings.
        let old = try JSONEncoder().encode(PreferenceData())
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        dictionary.removeValue(forKey: "proView"); dictionary.removeValue(forKey: "guidedMoreOpen")
        let data = try JSONDecoder().decode(PreferenceData.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertNil(data.proView); XCTAssertNil(data.guidedMoreOpen)
        // The Pro View command's default key doesn't clash with any other default.
        XCTAssertEqual(CommandID.proView.defaults.first?.display, "⌥⌘P")
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
