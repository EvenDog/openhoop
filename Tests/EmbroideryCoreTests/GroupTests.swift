// Groups: objects sharing a group ID are selected together; labels name groups with two or more members.
import XCTest
@testable import EmbroideryCore

final class GroupTests: XCTestCase {
    func testMembersAndLabels() {
        var design = Design.sample()   // three objects
        let group = UUID(), lonely = UUID()
        design.objects[0].groupID = group; design.objects[2].groupID = group; design.objects[1].groupID = lonely
        XCTAssertEqual(design.groupMembers(of: design.objects[2].id), [design.objects[0].id, design.objects[2].id])
        XCTAssertEqual(design.groupMembers(of: design.objects[1].id), [design.objects[1].id])
        XCTAssertEqual(design.groupLabels, [group: "Group A"], "A one-member group gets no label")
    }

    func testGroupingLeavesStitchesUnchanged() throws {
        var design = Design.sample()
        let plain = try RunningEngine.compile(design).commands.map(\.point)
        let group = UUID()
        for i in design.objects.indices { design.objects[i].groupID = group }
        XCTAssertEqual(try RunningEngine.compile(design).commands.map(\.point), plain)
        XCTAssertFalse(design.needsSchemaFive)
    }
}

final class GroupShortcutTests: XCTestCase {
    func testGroupShortcutsReachTheirCommands() {
        let profile = ShortcutProfile()
        XCTAssertEqual(profile.command(for: KeyBinding("g", 1), context: .canvas), .group)
        XCTAssertEqual(profile.command(for: KeyBinding("u", 1), context: .canvas), .ungroup)
        XCTAssertEqual(profile.command(for: KeyBinding("e", 4), context: .canvas), .entryExitTool)
    }
}
