// Checks OpenHoop's default keys, and that shortcut profiles saved with older default keys move to the current
// ones without losing keys the person set themselves.
import XCTest
@testable import EmbroideryCore

final class DefaultKeysTests: XCTestCase {
    /// Modifier values: 1 = ⌘, 2 = ⇧, 4 = ⌥.
    func testDefaultKeys() {
        let profile = ShortcutProfile()
        let expected: [(KeyBinding, CommandID)] = [
            (.init("o"), .selectTool), (.init("h"), .nodeTool), (.init("p"), .panTool), (.init("a"), .lettering),
            (.init("n", 2), .runTool), (.init("f8"), .runTool), (.init("a", 2), .satinTool), (.init("f4"), .satinTool),
            (.init("f6"), .convertSatin), (.init("i", 2), .convertSatin), (.init("f3"), .fillTool), (.init("m", 2), .convertFill),
            (.init("f7"), .applique), (.init("o", 3), .satinBorder), (.init("u"), .toggleUnderlay), (.init("k"), .lockObject),
            (.init("g", 2), .grid), (.init("g", 3), .snap), (.init("."), .needles), (.init("d"), .artwork),
            (.init("z"), .zoomIn), (.init("z", 2), .zoomOut), (.init("0", 4), .zoomFit), (.init("1", 1), .mirrorH), (.init("1", 4), .mirrorV),
            (.init("u", 1), .ungroup), (.init("y", 1), .redo), (.init("r", 2), .play), (.init("home"), .rewind), (.init("e", 2), .exportMachine),
            (.init("p", 1), .productionWorksheet), (.init("d", 1), .duplicate), (.init("escape"), .done), (.init("delete"), .delete),
            (.init("t"), .threadView), (.init("b"), .zoomBoxTool), (.init("1"), .zoomActual), (.init("0"), .zoomDesign), (.init("0", 2), .zoomSelected),
            (.init("s"), .showStitches), (.init("l"), .showOutlines), (.init("c", 2), .showConnectors), (.init("s", 2), .hideOthers), (.init("m"), .measureTool),
            (.init("k", 4), .knifeTool), (.init("w", 4), .weldObjects), (.init("n", 4), .smoothShapes), (.init("l", 6), .laydown), (.init("i"), .branching), (.init("i", 6), .insertNode), (.init("h", 8), .addStitchAngles), (.init("h", 10), .removeStitchAngles), (.init("e"), .editStitches), (.init("m", 6), .addMonogram)
        ]
        for (key, command) in expected { XCTAssertEqual(profile.command(for: key, context: .canvas), command, key.display) }
    }
    /// Every function-key tool also has a letter key, because Mac keyboards need fn for F1–F12.
    func testFunctionKeyToolsAlsoHaveALetter() {
        for command in CommandID.allCases where command.defaults.contains(where: { $0.key.hasPrefix("f") && $0.key.count > 1 }) {
            XCTAssertTrue(command.defaults.contains { !($0.key.hasPrefix("f") && $0.key.count > 1) }, command.title)
        }
    }
    /// The Mac reserves ⌘H (hide), ⌘M (minimize), ⌘Q (quit) and ⌘Space (Spotlight).
    func testDefaultsAvoidKeysTheMacReserves() {
        let reserved: [KeyBinding] = [.init("h", 1), .init("m", 1), .init("q", 1), .init("space", 1)]
        for command in CommandID.allCases { XCTAssertTrue(Set(command.defaults).isDisjoint(with: reserved), command.title) }
    }
    /// Zoom to Design came after people had saved their keys: a saved profile picks up 0 for it, unless they had
    /// already put something on 0 themselves.
    func testSavedProfileGetsZeroForZoomToDesign() {
        var saved = ShortcutProfile(); saved.bindings[CommandID.zoomDesign.rawValue] = nil   // saved before it existed
        saved.upgrade()
        XCTAssertEqual(saved.command(for: .init("0"), context: .canvas), .zoomDesign)
        var theirs = ShortcutProfile(); theirs.bindings[CommandID.zoomDesign.rawValue] = nil; theirs.bindings[CommandID.grid.rawValue] = [.init("0")]
        theirs.upgrade()
        XCTAssertEqual(theirs.command(for: .init("0"), context: .canvas), .grid, "their own key stays")
        XCTAssertEqual(theirs.bindings[CommandID.zoomDesign.rawValue], [])
    }
    func testOldProfileMovesToTheSecondKeySetButKeepsChangedKeys() throws {
        // A profile saved before the change: every command on its old default, except two the person changed.
        var profile = ShortcutProfile()
        for (command, keys) in CommandID.firstDefaults { profile.bindings[command.rawValue] = keys }
        profile.bindings[CommandID.fillTool.rawValue] = [.init("j")]           // their own key for fill
        profile.bindings[CommandID.threadChart.rawValue] = [.init("k")]        // clashes with the new Lock default
        profile.keySet = nil
        XCTAssertTrue(profile.updateToSecondKeySet())
        XCTAssertEqual(profile.bindings[CommandID.selectTool.rawValue], [.init("o")])
        XCTAssertEqual(profile.bindings[CommandID.runTool.rawValue], CommandID.runTool.defaults)
        XCTAssertEqual(profile.bindings[CommandID.fillTool.rawValue], [.init("j")])
        XCTAssertEqual(profile.bindings[CommandID.threadChart.rawValue], [.init("k")])
        XCTAssertEqual(profile.bindings[CommandID.lockObject.rawValue], [])     // its new key was taken, so it waits
        XCTAssertEqual(profile.keySet, 2)
        XCTAssertFalse(profile.updateToSecondKeySet())                            // only once
        try profile.validate()
    }
    func testProfileKeySetSurvivesSaving() throws {
        let saved = try JSONDecoder().decode(ShortcutProfile.self, from: JSONEncoder().encode(ShortcutProfile()))
        XCTAssertEqual(saved.keySet, 3)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ShortcutProfile())) as! [String: Any]
        old.removeValue(forKey: "keySet")
        XCTAssertNil(try JSONDecoder().decode(ShortcutProfile.self, from: JSONSerialization.data(withJSONObject: old)).keySet)
    }
    func testSavedProfileGivesBranchingTheIKeyOnce() throws {
        // A profile from before Branching: Insert Node on I, and no key for Branching yet.
        var profile = ShortcutProfile(); profile.keySet = 2
        profile.bindings[CommandID.insertNode.rawValue] = [.init("i")]; profile.bindings[CommandID.branching.rawValue] = []
        XCTAssertTrue(profile.updateToBranchingKey())
        XCTAssertEqual(profile.bindings[CommandID.branching.rawValue], [.init("i")])
        XCTAssertEqual(profile.bindings[CommandID.insertNode.rawValue], [.init("i", 6)])
        XCTAssertFalse(profile.updateToBranchingKey(), "only once")
        try profile.validate()

        // Someone who put Insert Node on their own key keeps it.
        var own = ShortcutProfile(); own.keySet = 2
        own.bindings[CommandID.insertNode.rawValue] = [.init("j", 4)]; own.bindings[CommandID.branching.rawValue] = []
        own.updateToBranchingKey()
        XCTAssertEqual(own.bindings[CommandID.insertNode.rawValue], [.init("j", 4)])
        XCTAssertEqual(own.bindings[CommandID.branching.rawValue], [.init("i")])
    }
    func testOldProfileGetsTheNewToolsKeysTheMoveFreed() throws {
        // Saved with the first default keys and before the newest tools, whose keys the old ones held (S was Satin,
        // T Lettering, E Start/End, B Artwork). Once the old ones move, the new tools get those keys.
        var profile = ShortcutProfile(); profile.bindings = [:]
        for (command, keys) in CommandID.firstDefaults { profile.bindings[command.rawValue] = keys }
        profile.keySet = nil
        XCTAssertTrue(profile.upgrade())
        for command in [CommandID.showStitches, .threadView, .editStitches, .zoomBoxTool, .branching] {
            XCTAssertEqual(profile.bindings[command.rawValue], command.defaults, command.title)
        }
        XCTAssertFalse(profile.upgrade(), "only once")
        try profile.validate()
    }
    func testInsertNodeKeyClearedOnPurposeStaysCleared() {
        var profile = ShortcutProfile(); profile.keySet = 2
        profile.bindings[CommandID.insertNode.rawValue] = []; profile.bindings[CommandID.branching.rawValue] = nil
        profile.upgrade()
        XCTAssertEqual(profile.bindings[CommandID.insertNode.rawValue], [])
        XCTAssertEqual(profile.bindings[CommandID.branching.rawValue], [.init("i")])
    }
}
