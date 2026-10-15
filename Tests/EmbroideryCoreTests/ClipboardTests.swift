// Copy and paste of objects: what gets copied, fresh identities on paste, groups kept together, and the offset.
import XCTest
@testable import EmbroideryCore

final class ClipboardTests: XCTestCase {
    private func square(_ name: String, at x: Double) -> RunObject {
        var object = RunObject(name: name, nodes: [Point(x, 0), Point(x + 10, 0), Point(x + 10, 10), Point(x, 10)].map { PathNode($0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }

    func testCopyKeepsSewingOrderAndOnlyTheSelection() {
        var design = Design(); design.objects = [square("A", at: 0), square("B", at: 20), square("C", at: 40)]
        let clipboard = design.copying([design.objects[2].id, design.objects[0].id])
        XCTAssertEqual(clipboard.objects.map(\.name), ["A", "C"])
    }

    func testPasteMakesSeparateUnlockedCopiesAtTheEnd() throws {
        var design = Design(); design.objects = [square("A", at: 0), square("B", at: 20)]
        design.objects[0].locked = true
        let clipboard = design.copying(Set(design.objects.map(\.id)))
        let ids = design.paste(clipboard, offset: Point(3, -3))
        XCTAssertEqual(design.objects.map(\.name), ["A", "B", "A", "B"])
        XCTAssertEqual(Set(ids), Set(design.objects[2...].map(\.id)))
        XCTAssertTrue(Set(ids).isDisjoint(with: clipboard.objects.map(\.id)), "Pasted objects get new ids")
        XCTAssertFalse(design.objects[2].locked, "Pasted objects are unlocked")
        XCTAssertEqual(design.objects[2].nodes[0].point, Point(3, -3))
        XCTAssertEqual(design.objects[0].nodes[0].point, Point(0, 0), "Originals don't move")
        XCTAssertNoThrow(try design.validate())
    }

    func testGroupsAndLetteringStayTogetherButSeparateFromOriginals() {
        var design = Design(); design.objects = [square("A", at: 0), square("B", at: 20), square("C", at: 40)]
        let group = UUID(); design.objects[0].groupID = group; design.objects[1].groupID = group
        let letters = LetteringSpec(text: "AB", fontKind: .system, font: "Helvetica", height: 10)
        design.objects[0].lettering = letters; design.objects[1].lettering = letters
        let ids = design.paste(design.copying(Set(design.objects.map(\.id))))
        let pasted = design.objects.filter { ids.contains($0.id) }
        XCTAssertEqual(pasted[0].groupID, pasted[1].groupID)
        XCTAssertNotNil(pasted[0].groupID); XCTAssertNotEqual(pasted[0].groupID, group)
        XCTAssertNil(pasted[2].groupID)
        XCTAssertEqual(pasted[0].lettering?.id, pasted[1].lettering?.id)
        XCTAssertNotEqual(pasted[0].lettering?.id, letters.id, "Pasted lettering edits separately from the original")
    }

    func testClipboardRoundTripsThroughJSON() throws {
        var design = Design(); design.objects = [square("A", at: 0)]
        let clipboard = design.copying([design.objects[0].id])
        XCTAssertEqual(try JSONDecoder().decode(ObjectClipboard.self, from: JSONEncoder().encode(clipboard)), clipboard)
    }

    func testCutCopyPasteHaveStandardKeys() {
        XCTAssertEqual(CommandID.copyObjects.defaults, [KeyBinding("c", 1)])
        XCTAssertEqual(CommandID.cutObjects.defaults, [KeyBinding("x", 1)])
        XCTAssertEqual(CommandID.pasteObjects.defaults, [KeyBinding("v", 1)])
        XCTAssertFalse(CommandID.copyObjects.contexts.contains(.text), "In a text field, ⌘C copies text instead")
    }
}
