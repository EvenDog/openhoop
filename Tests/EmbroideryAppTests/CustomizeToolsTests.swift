// Checks View › Customize Tools…: what each drag does to the arrangement, and how it's saved and read back.
import XCTest
@testable import EmbroideryApp
import EmbroideryCore

final class CustomizeToolsTests: XCTestCase {
    /// Group 0 is Pick & shape: select, nodes, edit stitches, smooth, knife… in that order.
    @MainActor func testDraggingLeftLandsBeforeTheTargetAndRightLandsAfterIt() {
        var arrangement = ToolArrangement.builtIn
        arrangement.move(.knifeTool, to: 0, onto: .nodeTool)
        XCTAssertEqual(Array(arrangement.groups[0].commands.prefix(3)), [.selectTool, .knifeTool, .nodeTool])
        arrangement.move(.selectTool, to: 0, onto: .nodeTool)
        XCTAssertEqual(Array(arrangement.groups[0].commands.prefix(3)), [.knifeTool, .nodeTool, .selectTool])
        arrangement.move(.knifeTool, to: 0)
        XCTAssertEqual(arrangement.groups[0].commands.last, .knifeTool, "dropped on the group, it goes at the end")
    }

    @MainActor func testToolsMoveBetweenGroupsAndIntoHiddenAndBack() {
        var arrangement = ToolArrangement.builtIn
        arrangement.move(.measureTool, to: 0, onto: .selectTool)
        XCTAssertEqual(arrangement.groups[0].commands.first, .measureTool)
        XCTAssertFalse(arrangement.groups[4].commands.contains(.measureTool), "it left the View group")
        arrangement.move(.knifeTool, to: nil)
        arrangement.move(.weldObjects, to: nil, onto: .knifeTool)
        XCTAssertEqual(arrangement.hidden, [.weldObjects, .knifeTool])
        XCTAssertFalse(arrangement.groups[0].commands.contains(.knifeTool))
        arrangement.move(.knifeTool, to: 1)
        XCTAssertEqual(arrangement.hidden, [.weldObjects])
        XCTAssertEqual(arrangement.groups[1].commands.last, .knifeTool)
        let all = arrangement.groups.flatMap(\.commands) + arrangement.hidden
        XCTAssertEqual(Set(all), Set(ToolStrip.proGroups.flatMap(\.commands)), "no tool lost")
        XCTAssertEqual(Set(all).count, all.count, "no tool twice")
    }

    @MainActor func testGroupsMoveToTheDroppedGroupsPlace() {
        var arrangement = ToolArrangement.builtIn
        arrangement.moveGroup("Zoom", to: 0)
        XCTAssertEqual(arrangement.groups.map(\.title), ["Zoom", "Pick & shape", "Stitch", "Shape", "Add", "View", "Show"])
        arrangement.moveGroup("Zoom", to: 2)
        XCTAssertEqual(arrangement.groups.map(\.title), ["Pick & shape", "Stitch", "Zoom", "Shape", "Add", "View", "Show"])
    }

    @MainActor func testTheBuiltInArrangementSavesAsNothing() throws {
        XCTAssertNil(ToolLayout(.builtIn))
        XCTAssertEqual(ToolLayout.arrangement(nil), .builtIn)
        var arrangement = ToolArrangement.builtIn
        arrangement.move(.knifeTool, to: nil)
        let saved = try XCTUnwrap(ToolLayout(arrangement))
        let reread = try JSONDecoder().decode(ToolLayout.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(ToolLayout.arrangement(reread), arrangement)
        arrangement.move(.knifeTool, to: 0, onto: .weldObjects)
        XCTAssertNil(ToolLayout(arrangement), "putting it back is the built-in arrangement again")
    }

    /// A saved layout from another version: an unknown tool, a tool listed twice, a missing group and a tool that's
    /// nowhere (as a tool new in this version would be).
    @MainActor func testASavedLayoutIsRepairedWhenRead() {
        var groups = ToolArrangement.builtIn.groups.map { ToolLayout.Group(title: $0.title, tools: $0.commands.map(\.rawValue)) }
        groups[0].tools = ["futureTool", "knifeTool", "selectTool", "knifeTool"]   // the rest of Pick & shape is nowhere
        groups.removeAll { $0.title == "Zoom" }
        groups.append(.init(title: "Old group", tools: ["measureTool"]))
        let arrangement = ToolLayout.arrangement(ToolLayout(groups: groups, hidden: ["weldObjects"]))
        XCTAssertEqual(arrangement.groups.map(\.title), ["Pick & shape", "Stitch", "Shape", "Add", "View", "Show", "Zoom"])
        XCTAssertEqual(Array(arrangement.groups[0].commands.prefix(3)), [.knifeTool, .selectTool, .nodeTool], "unplaced tools join their group at the end")
        XCTAssertFalse(arrangement.groups[0].commands.contains(.weldObjects), "hidden stays hidden")
        XCTAssertEqual(arrangement.groups[6].commands, ToolStrip.proGroups[6].commands, "the missing group comes back full")
        let all = arrangement.groups.flatMap(\.commands) + arrangement.hidden
        XCTAssertEqual(Set(all), Set(ToolStrip.proGroups.flatMap(\.commands)))
        XCTAssertEqual(Set(all).count, all.count)
    }
}
