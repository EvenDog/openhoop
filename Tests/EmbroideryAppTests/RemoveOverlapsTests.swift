// Checks Remove Overlaps end to end: it cuts what shapes sewn later cover out of the fills' own outlines (the
// selected fills, or all with nothing selected), once, as one undoable step. Moving the shape on top afterwards leaves
// the fill as it was cut.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class RemoveOverlapsTests: XCTestCase {
    private func square(_ name: String, x: Double, size: Double) -> RunObject {
        let h = size / 2
        var o = RunObject(name: name, nodes: [Point(x - h, -h), Point(x + h, -h), Point(x + h, h), Point(x - h, h)].map { PathNode($0) }, color: ThreadColor.palette[0])
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill)
        return o
    }

    @MainActor func testRemoveOverlapsCutsOnceAndStays() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let base = square("Base", x: 0, size: 40), top = square("Top", x: 0, size: 20), other = square("Other", x: 60, size: 20)
        let cover = square("Cover", x: 60, size: 10)
        state.design.objects = [base, other, top, cover]
        func holes(_ name: String) -> Int { state.design.objects.first { $0.name == name }?.holes?.count ?? 0 }

        // Only Other selected: just it is cut.
        state.selection = [other.id]
        state.removeOverlaps()
        XCTAssertEqual(holes("Other"), 1, "Cover is cut out of it"); XCTAssertEqual(holes("Base"), 0)
        XCTAssertEqual(state.selection, [other.id], "it stays selected")
        document.undoManager?.undo()
        XCTAssertEqual(holes("Other"), 0, "one undo")

        // Nothing selected: every fill with something on top (not Top or Cover, which have nothing after them).
        state.selection = []
        state.removeOverlaps()
        XCTAssertEqual(holes("Base"), 1); XCTAssertEqual(holes("Other"), 1); XCTAssertEqual(holes("Top"), 0)
        XCTAssertTrue(state.status.hasPrefix("Overlaps removed"), state.status)
        // The hole is Top less the 1 mm tuck: 18 mm across.
        let hole = state.design.objects.first { $0.name == "Base" }!.holes![0].map(\.point)
        XCTAssertEqual(hole.map(\.x).max()! - hole.map(\.x).min()!, 18, accuracy: 0.01)

        // Moving Top away leaves Base as it was cut: the cut doesn't follow it.
        let cutBase = state.design.objects.first { $0.name == "Base" }!
        state.edit("Move") { $0.move([top.id], by: Point(100, 0)) }
        XCTAssertEqual(state.design.objects.first { $0.name == "Base" }, cutBase)

        // Again, with nothing overlapping any more: says so and changes nothing.
        state.removeOverlaps()
        XCTAssertTrue(state.status.hasPrefix("Nothing sewn on top"), state.status)
        XCTAssertEqual(state.design.objects.first { $0.name == "Base" }, cutBase)
    }
}
