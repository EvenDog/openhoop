// Checks lettering made in Properties: Add Lettering is a tool whose click puts a word on the hoop (selected, with
// its text box asked to take the keyboard), new lettering starts in the last font used, switching fonts keeps the
// height and picks the Bold style, and fonts tried one after another undo as one step.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class LetteringPanelTests: XCTestCase {
    /// Lets the run loop end the current event, which closes its undo group (as each key press does in the app).
    private func nextEvent() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    private func center(_ objects: [RunObject]) -> Point {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        return Point((points.map(\.x).min()! + points.map(\.x).max()!) / 2, (points.map(\.y).min()! + points.map(\.y).max()!) / 2)
    }

    @MainActor func testClickingWithTheTextToolAddsSelectedLettering() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        XCTAssertEqual(Tool.forCommand[.lettering], .text, "Add Lettering turns on a tool rather than opening a box")
        state.tool = .text
        state.addLettering(at: Point(12, -8))
        let letters = state.design.objects
        XCTAssertFalse(letters.isEmpty)
        XCTAssertEqual(Set(letters.compactMap { $0.lettering?.id }).count, 1, "one lettering")
        XCTAssertEqual(state.selection, Set(letters.map(\.id)), "the new lettering is selected")
        XCTAssertEqual(state.tool, .select, "back to Select, so the next click doesn't add more")
        XCTAssertTrue(state.letteringTextFocusRequested, "Properties is asked to put the keyboard in its text box")
        let middle = center(letters)
        XCTAssertEqual(middle.x, 12, accuracy: 1, "centered where you clicked")
        XCTAssertEqual(middle.y, -8, accuracy: letters[0].lettering!.height)
    }

    @MainActor func testNewLetteringStartsInTheLastFontUsed() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        state.addLettering(at: Point(0, 0))
        let spec = try XCTUnwrap(state.design.objects.first?.lettering)
        var next = InspectorPanel.spec(spec, withFont: .system("Georgia")); next.height = 15
        XCTAssertTrue(state.rebuildLettering(next))
        state.addLettering(at: Point(0, 30))
        let newest = try XCTUnwrap(state.design.objects.last?.lettering)
        XCTAssertNotEqual(newest.id, spec.id)
        XCTAssertEqual(newest.font, next.font, "the font used last")
        XCTAssertEqual(newest.height, 15, "and its height")
    }

    @MainActor func testSwitchingToAMacFontKeepsTheHeightAndPicksBold() {
        let spec = LetteringSpec(text: "Ellie", fontKind: .system, font: "Helvetica", height: 18)
        let next = InspectorPanel.spec(spec, withFont: .system("Georgia"))
        XCTAssertEqual(next.font, "Georgia-Bold")
        XCTAssertEqual(next.height, 18)
        XCTAssertEqual(LetteringFontChoice(next), .system("Georgia"), "the list shows the family as chosen")
    }

    @MainActor func testFontsTriedInARowUndoAsOneStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let undo = try XCTUnwrap(document.undoManager)
        state.addLettering(at: Point(0, 0)); nextEvent()
        let start = try XCTUnwrap(state.design.objects.first?.lettering)
        func tryFont(_ family: String) {
            let spec = state.design.objects.first!.lettering!
            state.rebuildLettering(InspectorPanel.spec(spec, withFont: .system(family)), action: "Lettering Font", run: "font \(spec.id)"); nextEvent()
        }
        tryFont("Georgia"); tryFont("Futura"); tryFont("Courier New")
        XCTAssertEqual(state.design.objects.first?.lettering?.font, "CourierNewPS-BoldMT")
        undo.undo(); nextEvent()
        XCTAssertEqual(state.design.objects.first?.lettering?.font, start.font, "one Undo goes back to the font before trying")
        XCTAssertFalse(state.design.objects.isEmpty, "and keeps the lettering")

        // Another change in between starts a new step.
        undo.redo(); nextEvent()
        tryFont("Georgia")
        var spec = state.design.objects.first!.lettering!; spec.height = 20
        state.rebuildLettering(spec, action: "Letter Height"); nextEvent()
        tryFont("Futura")
        undo.undo(); nextEvent()
        XCTAssertEqual(state.design.objects.first?.lettering?.font, "Georgia-Bold", "only the fonts tried after the height change are undone")
        XCTAssertEqual(state.design.objects.first?.lettering?.height, 20)
    }
}
