// Checks the stitch angle tools: two clicks across a fill add an angle line, and a click on a line removes it.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class StitchAngleToolTests: XCTestCase {
    @MainActor func testClicksAddAndRemoveAngleLines() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var fill = RunObject(name: "Band", nodes: [Point(0, 0), Point(30, 0), Point(30, 10), Point(0, 10)].map { PathNode($0) }, color: ThreadColor.palette[0])
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        state.design.objects = [fill]; state.selection = [fill.id]
        state.angleTarget = fill.id; state.tool = .addAngles
        state.clickForAngle(Point(5, -2), reach: 1)
        XCTAssertEqual(state.angleStart, Point(5, -2)); XCTAssertNil(state.design.objects[0].settings.angleLines)
        state.clickForAngle(Point(8, 12), reach: 1)
        XCTAssertEqual(state.design.objects[0].settings.angleLines, [[Point(5, -2), Point(8, 12)]])
        XCTAssertNil(state.angleStart)

        state.tool = .removeAngles
        state.clickForAngle(Point(20, 5), reach: 1)
        XCTAssertEqual(state.design.objects[0].settings.angleLines?.count, 1, "a click away from the line removes nothing")
        state.clickForAngle(Point(6.5, 5), reach: 1)
        XCTAssertNil(state.design.objects[0].settings.angleLines, "the last line gone: straight rows again")
    }

    @MainActor func testAClickedAngleLineCanBeFoundAndRemovedAlone() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var fill = RunObject(name: "Band", nodes: [Point(0, 0), Point(30, 0), Point(30, 10), Point(0, 10)].map { PathNode($0) }, color: ThreadColor.palette[0])
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        fill.digitizing?.angleLines = [[Point(5, -2), Point(5, 12)], [Point(25, -2), Point(25, 12)]]
        state.design.objects = [fill]; state.selection = [fill.id]
        XCTAssertNil(state.angleLine(near: Point(15, 5), reach: 1))
        let angle = state.angleLine(near: Point(25.3, 4), reach: 1)
        XCTAssertEqual(angle?.index, 1)
        state.selectedAngle = angle
        state.removeAngleLine(fill.id, 1)
        XCTAssertEqual(state.design.objects.count, 1, "the fill stays")
        XCTAssertEqual(state.design.objects[0].settings.angleLines, [[Point(5, -2), Point(5, 12)]])
        XCTAssertNil(state.selectedAngle)
    }

    /// Angle lines only show with Edit Nodes or the angle tools; on any other tool a line can't stay selected (so
    /// Delete removes the fill, not a line you can't see). A locked fill's lines can't be removed.
    @MainActor func testAChosenLineIsLetGoOnOtherToolsAndLockedFillsKeepTheirs() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var fill = RunObject(name: "Band", nodes: [Point(0, 0), Point(30, 0), Point(30, 10), Point(0, 10)].map { PathNode($0) }, color: ThreadColor.palette[0])
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.angleLines = [[Point(5, -2), Point(8, 12)]]
        state.design.objects = [fill]; state.selection = [fill.id]
        state.tool = .node; state.selectedAngle = (fill.id, 0)
        state.tool = .removeAngles
        XCTAssertNotNil(state.selectedAngle, "still showing with the angle tools")
        state.tool = .select
        XCTAssertNil(state.selectedAngle, "back on Select the lines are hidden, so none is chosen")
        state.design.objects[0].locked = true
        state.removeAngleLine(fill.id, 0)
        XCTAssertEqual(state.design.objects[0].settings.angleLines?.count, 1, "locked: nothing changes")
    }
}
