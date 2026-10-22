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
            (.init("f7"), .applique), (.init("o", 3), .outlinesOffsets), (.init("u"), .toggleUnderlay), (.init("k"), .lockObject),
            (.init("g", 2), .grid), (.init("g", 3), .snap), (.init("."), .needles), (.init("d"), .artwork),
            (.init("z"), .zoomIn), (.init("z", 2), .zoomOut), (.init("0", 4), .zoomFit), (.init("1", 1), .mirrorH), (.init("1", 4), .mirrorV),
            (.init("u", 1), .ungroup), (.init("y", 1), .redo), (.init("r", 2), .play), (.init("home"), .rewind), (.init("e", 1), .exportMachine), (.init("e", 2), .exportMachine),
            (.init("p", 1), .productionWorksheet), (.init("d", 1), .duplicate), (.init("escape"), .done), (.init("delete"), .delete),
            (.init("t"), .threadView), (.init("b"), .zoomBoxTool), (.init("1"), .zoomActual), (.init("0"), .zoomDesign), (.init("0", 2), .zoomSelected),
            (.init("s"), .showStitches), (.init("l"), .showOutlines), (.init("c", 2), .showConnectors), (.init("s", 2), .hideOthers), (.init("m"), .measureTool),
            (.init("k", 4), .knifeTool), (.init("w", 4), .weldObjects), (.init("n", 4), .smoothShapes), (.init("l", 6), .laydown), (.init("i"), .branching), (.init("i", 6), .insertNode), (.init("h", 8), .addStitchAngles), (.init("h", 10), .removeStitchAngles), (.init("e"), .editStitches), (.init("m", 6), .addMonogram),
            (.init("e", 3), .removeOverlaps), (.init("x", 3), .clearGuides), (.init("l", 2), .panelSewingOrder), (.init("p", 4), .panelDesign),
            (.init("1", 5), .panelSewingOrder), (.init("2", 5), .panelDesign), (.init("3", 5), .panelReference), (.init("4", 5), .palette),
            (.init("[", 1), .earlier), (.init("]", 1), .later), (.init("left", 5), .rotateLeft), (.init("right", 5), .rotateRight), (.init("h", 3), .hideObject),
            (.init("end"), .toEnd), (.init("pagedown"), .nextColor), (.init("pageup"), .previousColor), (.init("t", 1), .nextObject), (.init("t", 2), .previousObject),
            (.init("right", 4), .nextTrim), (.init("left", 4), .previousTrim)
        ]
        for (key, command) in expected { XCTAssertEqual(profile.command(for: key, context: .canvas), command, key.display) }
    }
    /// Space plays the stitch player, except while drawing, where it finishes the shape as Return does.
    func testSpaceFinishesTheShapeWhileDrawing() throws {
        let profile = ShortcutProfile()
        XCTAssertEqual(profile.command(for: .init("space"), context: .canvas), .play)
        XCTAssertEqual(profile.command(for: .init("space"), context: .drawing), .finishPath)
        XCTAssertEqual(profile.command(for: .init("return"), context: .drawing), .finishPath)
        XCTAssertEqual(profile.command(for: .init("r", 2), context: .canvas), .play)
        try profile.validate()
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
        XCTAssertEqual(saved.keySet, 6)
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
    func testSavedProfileMovesExportPESKeysToTheOneExport() throws {
        // Saved before the exports became one: ⌘E on Export PES…, ⇧E and ⇧⌘E on Export Machine File…, and a key the
        // person gave Export DST….
        var profile = ShortcutProfile(); profile.keySet = 3
        profile.bindings[CommandID.exportMachine.rawValue] = [.init("e", 2), .init("e", 3)]
        profile.bindings["exportPES"] = [.init("e", 1)]; profile.bindings["exportDST"] = [.init("d", 5)]
        profile.bindings[CommandID.removeOverlaps.rawValue] = nil   // it came later
        XCTAssertTrue(profile.upgrade())
        XCTAssertEqual(profile.bindings[CommandID.exportMachine.rawValue], [.init("e", 2), .init("e", 3), .init("e", 1), .init("d", 5)])
        XCTAssertNil(profile.bindings["exportPES"]); XCTAssertNil(profile.bindings["exportDST"])
        XCTAssertEqual(profile.command(for: .init("e", 1), context: .canvas), .exportMachine)
        XCTAssertFalse(profile.updateToOneExport(), "only once")
        try profile.validate()

        // A key another command took in the meantime stays with it.
        var taken = ShortcutProfile(); taken.keySet = 3
        taken.bindings[CommandID.exportMachine.rawValue] = []; taken.bindings["exportPES"] = [.init("e", 1)]
        taken.bindings[CommandID.productionWorksheet.rawValue] = [.init("e", 1)]
        taken.upgrade()
        XCTAssertEqual(taken.bindings[CommandID.exportMachine.rawValue], [])
    }
    func testSavedProfileGivesOutlinesOffsetsShiftCommandOOnce() throws {
        // Saved before Outlines & Offsets: ⇧⌘O on Add Satin Border, and no key for the new command yet.
        var profile = ShortcutProfile(); profile.keySet = 4
        profile.bindings[CommandID.satinBorder.rawValue] = [.init("o", 3)]; profile.bindings[CommandID.outlinesOffsets.rawValue] = nil
        XCTAssertTrue(profile.upgrade())
        XCTAssertEqual(profile.bindings[CommandID.satinBorder.rawValue], [])
        XCTAssertEqual(profile.command(for: .init("o", 3), context: .canvas), .outlinesOffsets)
        XCTAssertFalse(profile.updateToOutlinesKey(), "only once")
        try profile.validate()

        // Someone who gave Add Satin Border a key of their own keeps it.
        var own = ShortcutProfile(); own.keySet = 4
        own.bindings[CommandID.satinBorder.rawValue] = [.init("o", 3), .init("b", 4)]; own.bindings[CommandID.outlinesOffsets.rawValue] = nil
        own.upgrade()
        XCTAssertEqual(own.bindings[CommandID.satinBorder.rawValue], [.init("o", 3), .init("b", 4)])
        XCTAssertEqual(own.bindings[CommandID.outlinesOffsets.rawValue], [], "its key is taken, so it waits")
    }
    func testInsertNodeKeyClearedOnPurposeStaysCleared() {
        var profile = ShortcutProfile(); profile.keySet = 2
        profile.bindings[CommandID.insertNode.rawValue] = []; profile.bindings[CommandID.branching.rawValue] = nil
        profile.upgrade()
        XCTAssertEqual(profile.bindings[CommandID.insertNode.rawValue], [])
        XCTAssertEqual(profile.bindings[CommandID.branching.rawValue], [.init("i")])
    }
    func testSavedProfileMovesToTheWilcomKeysOnce() throws {
        // Saved with key set 5: ⇧⌘E on Export Machine File…, Return alone to finish, and no keys for the commands that
        // now have them, except one the person gave Clear Guides themselves and ⌘[ they put on Group.
        var profile = ShortcutProfile(); profile.keySet = 5
        profile.bindings[CommandID.exportMachine.rawValue] = [.init("e", 1), .init("e", 2), .init("e", 3)]
        profile.bindings[CommandID.finishPath.rawValue] = [.init("return")]
        for command in [CommandID.removeOverlaps, .panelSewingOrder, .panelDesign, .panelReference, .palette, .earlier, .later, .rotateLeft, .rotateRight, .hideObject] {
            profile.bindings[command.rawValue] = []
        }
        profile.bindings[CommandID.clearGuides.rawValue] = [.init("j", 12)]
        profile.bindings[CommandID.group.rawValue] = [.init("g", 1), .init("[", 1)]
        XCTAssertTrue(profile.upgrade())
        XCTAssertEqual(profile.bindings[CommandID.exportMachine.rawValue], [.init("e", 1), .init("e", 2)])
        XCTAssertEqual(profile.command(for: .init("e", 3), context: .canvas), .removeOverlaps)
        XCTAssertEqual(profile.bindings[CommandID.finishPath.rawValue], [.init("return"), .init("space")])
        XCTAssertEqual(profile.bindings[CommandID.clearGuides.rawValue], [.init("j", 12)], "their own key stays")
        XCTAssertEqual(profile.bindings[CommandID.earlier.rawValue], [], "⌘[ is theirs on Group, so Sew Earlier waits")
        XCTAssertEqual(profile.bindings[CommandID.later.rawValue], [.init("]", 1)])
        XCTAssertEqual(profile.command(for: .init("4", 5), context: .canvas), .palette)
        XCTAssertFalse(profile.updateToWilcomKeys(), "only once")
        try profile.validate()

        // Someone who changed Export Machine File…'s keys keeps all of them, so Remove Overlaps waits.
        var own = ShortcutProfile(); own.keySet = 5
        own.bindings[CommandID.exportMachine.rawValue] = [.init("e", 3)]; own.bindings[CommandID.removeOverlaps.rawValue] = []
        own.upgrade()
        XCTAssertEqual(own.bindings[CommandID.exportMachine.rawValue], [.init("e", 3)])
        XCTAssertEqual(own.bindings[CommandID.removeOverlaps.rawValue], [])
    }
    /// With nothing selected, the arrow keys step the stitch player: ← → by a stitch, ↑ ↓ by ten.
    func testArrowKeysStepThePlayerWithNothingSelected() {
        XCTAssertEqual(CommandID.nudgeRight.stepWithoutSelection, .stepForward)
        XCTAssertEqual(CommandID.nudgeLeft.stepWithoutSelection, .stepBackward)
        XCTAssertEqual(CommandID.nudgeDown.stepWithoutSelection, .stepForward10)
        XCTAssertEqual(CommandID.nudgeUp.stepWithoutSelection, .stepBackward10)
        XCTAssertEqual(CommandID.stepForward10.stitchStep, .stitches(10))
        XCTAssertNil(CommandID.zoomIn.stepWithoutSelection)
    }
    /// A profile saved before the stepping commands picks up their keys.
    func testSavedProfileGetsTheSteppingKeys() throws {
        var saved = ShortcutProfile()
        for command in [CommandID.toEnd, .nextColor, .previousColor, .nextObject, .previousObject, .nextTrim, .previousTrim] { saved.bindings[command.rawValue] = nil }
        saved.upgrade()
        XCTAssertEqual(saved.command(for: .init("pagedown"), context: .canvas), .nextColor)
        XCTAssertEqual(saved.command(for: .init("t", 1), context: .canvas), .nextObject)
        try saved.validate()
    }
}
