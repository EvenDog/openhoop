// Checks Continue drawing end to end: picking up a satin at its end or start, adding pairs, then Return, keeps the
// same object (name, place in the sewing order, direction) with the new pairs added, as one undoable step; Esc leaves
// it as it was.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ContinueDrawingFlowTests: XCTestCase {
    private let pairs = [Point(0, 2), Point(0, -2), Point(10, 2), Point(10, -2)]

    @MainActor private func setUp(_ state: EditorState) -> RunObject {
        var satin = RunObject(name: "Stem", nodes: pairs.map { PathNode($0) }, color: ThreadColor.palette[0])
        satin.digitizing = DigitizingSettings(kind: .satin)
        var other = RunObject(name: "After", nodes: [Point(0, 20), Point(10, 20)].map { PathNode($0) }, color: ThreadColor.palette[1])
        other.digitizing = DigitizingSettings(kind: .run)
        state.design.objects = [satin, other]
        state.tool = .satin; state.selection = [satin.id]
        return satin
    }

    @MainActor func testContinuingFromTheEndAddsPairsToTheSameSatin() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let satin = setUp(state)
        state.continueDrawing(satin.id, fromStart: false)
        XCTAssertEqual(state.draft.map(\.point), pairs)
        state.draft += [PathNode(Point(20, 2)), PathNode(Point(20, -2))]
        state.finishPath()
        XCTAssertEqual(state.design.objects.map(\.name), ["Stem", "After"], "no new object, same place")
        XCTAssertEqual(state.design.objects[0].id, satin.id)
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point), pairs + [Point(20, 2), Point(20, -2)])
        XCTAssertTrue(state.draft.isEmpty); XCTAssertNil(state.continuing); XCTAssertEqual(state.selection, [satin.id])
        document.undoManager?.undo()
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point), pairs, "one undo takes the added pairs away")
    }

    @MainActor func testContinuingFromTheStartKeepsTheDirection() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let satin = setUp(state)
        state.continueDrawing(satin.id, fromStart: true)
        XCTAssertEqual(state.draft.first?.point, Point(10, 2), "the drawing runs out of the start")
        state.draft += [PathNode(Point(-10, 2)), PathNode(Point(-10, -2))]
        state.finishPath()
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point), [Point(-10, 2), Point(-10, -2)] + pairs,
                       "the new pair goes before the old ones, so the satin still sews the same way")
    }

    @MainActor func testEscapeLeavesTheSatinAsItWas() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let satin = setUp(state)
        state.continueDrawing(satin.id, fromStart: false)
        state.draft += [PathNode(Point(20, 2)), PathNode(Point(20, -2))]
        state.draft = []   // what Esc (Cancel Path) does
        XCTAssertNil(state.continuing)
        XCTAssertEqual(state.design.objects[0].nodes.map(\.point), pairs)
        // The next satin drawn is a new one.
        state.draft = [Point(0, 30), Point(0, 26), Point(10, 30), Point(10, 26)].map { PathNode($0) }
        state.finishPath()
        XCTAssertEqual(state.design.objects.count, 3)
    }
}
