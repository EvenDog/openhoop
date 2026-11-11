// Checks monograms made and changed in Properties: Add Monogram puts one in the middle of the hoop (selected, with
// its Initials box asked to take the keyboard), each change rebuilds it in the same place in the sewing order as
// one undoable step, initials and fonts tried in a row undo as one step, a locked monogram isn't changed, the tile
// pictures show just their one choice, and the first monogram fits a 4 × 4 inch hoop.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class MonogramPanelTests: XCTestCase {
    /// Lets the run loop end the current event, which closes its undo group (as each key press does in the app).
    private func nextEvent() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    private func box(_ objects: [RunObject]) -> (min: Point, max: Point) {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        return (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
    }
    @MainActor private func monogram(_ state: EditorState) -> MonogramSpec? { state.design.objects.first?.monogram }

    @MainActor func testAddMonogramPutsOneSelectedInTheMiddleOfTheHoop() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        state.tool = .fill
        state.addMonogram()
        let parts = state.design.objects
        XCTAssertFalse(parts.isEmpty)
        XCTAssertEqual(Set(parts.compactMap { $0.monogram?.id }).count, 1, "one monogram")
        XCTAssertEqual(state.selection, Set(parts.map(\.id)), "the whole monogram is selected")
        XCTAssertEqual(state.tool, .select)
        XCTAssertTrue(state.monogramInitialsFocusRequested, "Properties is asked to put the keyboard in its Initials box")
        XCTAssertEqual(parts.first?.monogram?.anchor, Point(0, 0), "placed on the middle of the hoop")
        let (low, high) = box(parts)
        XCTAssertTrue(low.x < 0 && high.x > 0 && low.y < 0 && high.y > 0, "around the middle of the hoop")
    }

    @MainActor func testAChangeRebuildsItInPlaceAsOneStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let undo = try XCTUnwrap(document.undoManager)
        // Something sewn before and after it, to check it keeps its place in the sewing order.
        state.edit("Add") { $0.objects.append(RunObject(name: "Before", nodes: [PathNode(Point(-40, 40)), PathNode(Point(-30, 40))])) }; nextEvent()
        state.addMonogram(); nextEvent()
        state.edit("Add") { $0.objects.append(RunObject(name: "After", nodes: [PathNode(Point(30, -40)), PathNode(Point(40, -40))])) }; nextEvent()
        let start = try XCTUnwrap(state.design.objects.first { $0.monogram != nil }?.monogram)
        XCTAssertEqual(start.border, .circle)

        var next = start; next.border = .shield
        XCTAssertTrue(state.rebuildMonogram(next, action: "Monogram Border")); nextEvent()
        let names = state.design.objects.map(\.name)
        XCTAssertEqual(names.first, "Before"); XCTAssertEqual(names.last, "After", "still sewn between the same objects")
        let parts = state.design.monogramObjects(start.id)
        XCTAssertTrue(parts.allSatisfy { $0.monogram?.border == .shield }, "the same monogram, rebuilt")
        XCTAssertEqual(state.selection, Set(parts.map(\.id)), "and selected")

        undo.undo(); nextEvent()
        XCTAssertEqual(state.design.monogramObjects(start.id).first?.monogram?.border, .circle, "one Undo puts the circle back")
    }

    @MainActor func testInitialsAndFontsTriedInARowUndoAsOneStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let undo = try XCTUnwrap(document.undoManager)
        state.addMonogram(); nextEvent()
        let start = try XCTUnwrap(monogram(state))
        for initials in ["E", "EM", "EMR"] {
            var next = monogram(state)!; next.initials = initials
            state.rebuildMonogram(next, action: "Monogram Initials", run: "initials \(start.id)"); nextEvent()
        }
        for family in ["Georgia", "Baskerville"] {
            let spec = monogram(state)!
            state.rebuildMonogram(InspectorPanel.monogram(spec, withFont: .system(family)), action: "Monogram Font", run: "font \(start.id)"); nextEvent()
        }
        XCTAssertEqual(monogram(state)?.initials, "EMR")
        XCTAssertEqual(monogram(state)?.font, "Baskerville-Bold")
        undo.undo(); nextEvent()
        XCTAssertEqual(monogram(state)?.font, start.font, "one Undo takes back both fonts")
        XCTAssertEqual(monogram(state)?.initials, "EMR")
        undo.undo(); nextEvent()
        XCTAssertEqual(monogram(state)?.initials, start.initials, "and one more takes back the typing")
    }

    @MainActor func testALockedMonogramIsLeftAlone() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        state.addMonogram(); nextEvent()
        state.edit("Lock") { design in for i in design.objects.indices { design.objects[i].locked = true } }; nextEvent()
        var next = try XCTUnwrap(monogram(state)); next.layout = .stacked
        XCTAssertFalse(state.rebuildMonogram(next))
        XCTAssertEqual(monogram(state)?.layout, .bigMiddle)
        XCTAssertTrue(state.status.contains("Unlock"), state.status)
    }

    /// Each picture shows only its own choice, in the monogram's initials and font; ornament pictures show just the
    /// first initial. Equal choices give equal samples, so a picture built once is found again.
    @MainActor func testTilePicturesShowJustTheirChoice() {
        let spec = MonogramSpec(initials: "EMR", fontKind: .system, font: "Georgia-Bold", height: 30, layout: .diamond, ornament: .laurel, border: .shield)
        let layout = InspectorPanel.tileSample(spec, layout: .stacked)
        XCTAssertEqual(layout.layout, .stacked); XCTAssertEqual(layout.ornament, .none); XCTAssertEqual(layout.border, .none)
        XCTAssertEqual(layout.initials, "EMR"); XCTAssertEqual(layout.font, "Georgia-Bold")
        let ornament = InspectorPanel.tileSample(spec, ornament: .stars)
        XCTAssertEqual(ornament.initials, "E"); XCTAssertEqual(ornament.ornament, .stars); XCTAssertEqual(ornament.border, .none)
        let border = InspectorPanel.tileSample(spec, border: .heart)
        XCTAssertEqual(border.layout, .diamond, "a border is shown around the monogram's own layout")
        XCTAssertEqual(border.border, .heart); XCTAssertEqual(border.ornament, .none)
        XCTAssertEqual(InspectorPanel.tileSample(spec, border: .heart), border, "the same choice gives the same sample")
    }

    /// The first monogram (ABC in Caesarus SC, 30 mm, in a circle) fits inside a 100 × 100 mm hoop, the SE600's.
    @MainActor func testTheFirstMonogramFitsASmallHoop() throws {
        let fonts = EmbroideryFont.all(in: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/EmbroideryFonts"))
        XCTAssertNotNil(fonts.first { $0.folder.lastPathComponent == "caesarus_SC_FI" })
        let spec = MonogramSpec(initials: "ABC", fontKind: .embroidery, font: "caesarus_SC_FI", height: 30, layout: .bigMiddle, ornament: .none, border: .circle)
        let made = try spec.build(color: .palette[0], embroideryFonts: fonts)
        XCTAssertTrue(made.notes.isEmpty, "30 mm is a size the font is digitized for: \(made.notes)")
        let (low, high) = box(made.objects)
        XCTAssertLessThan(high.x - low.x, 95); XCTAssertLessThan(high.y - low.y, 95)
    }
}
