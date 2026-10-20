// The Pattern menu of a tatami fill: pointing at a pattern previews it on selected tatami fills only, without
// changing the design.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class TatamiPatternMenuTests: XCTestCase {
    @MainActor func testPointingAtAPatternPreviewsItOnTatamiFillsOnly() async throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        func fill(_ x: Double, _ style: EmbroideryCore.FillStyle?) -> RunObject {
            var object = RunObject(name: "Fill", nodes: [Point(x, 0), Point(x + 30, 0), Point(x + 30, 20), Point(x, 20)].map { PathNode($0) }, color: ThreadColor.palette[0])
            object.closed = true; object.digitizing = DigitizingSettings(kind: .fill); object.digitizing?.fillStyle = style
            return object
        }
        let tatami = fill(0, nil), contour = fill(40, .contour)
        state.edit("Add") { $0.objects = [tatami, contour] }
        state.selection = [tatami.id, contour.id]
        let before = state.design
        let zigzag = try XCTUnwrap(TatamiPattern.named("zigzag"))

        TatamiPatternMenu.preview(zigzag, state)
        for _ in 0..<500 where state.settingsPreview == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let preview = try XCTUnwrap(state.settingsPreview)
        XCTAssertEqual(preview.choice, TatamiPatternMenu.choice(zigzag))
        XCTAssertEqual(preview.objects, [tatami.id], "the contour fill has no pattern to try")
        XCTAssertEqual(state.design, before, "a preview changes nothing")

        TatamiPatternMenu.preview(.smooth, state)   // what it already has: nothing to preview
        XCTAssertNil(state.settingsPreview)
    }
}
