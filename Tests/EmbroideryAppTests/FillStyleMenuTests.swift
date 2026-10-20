// The Fill style menu: every style has a picture, pointing at a style previews it on the selected fill without
// changing the design, and a chosen style's preview stays until the fresh stitches arrive.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class FillStyleMenuTests: XCTestCase {
    func testEveryStyleHasSampleStitches() {
        for style in EmbroideryCore.FillStyle.allCases {
            let points = FillStyleSamples.stitches(style).joined()
            XCTAssertGreaterThan(points.count, 20, "\(style.title) has a picture")
            XCTAssertTrue(points.allSatisfy { abs($0.x) <= 30 && abs($0.y) <= 21 }, "\(style.title) stays on the sample shape")
        }
    }

    /// A selected 40 × 30 mm tatami square in a fresh document. The document must stay alive: edits go through it.
    @MainActor private func documentWithASquare() -> (DesignDocument, RunObject) {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var square = RunObject(name: "Square", nodes: [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)].map { PathNode($0) }, color: ThreadColor.palette[0])
        square.closed = true; square.digitizing = DigitizingSettings(kind: .fill)
        state.edit("Add") { $0.objects = [square] }
        state.selection = [square.id]
        return (document, square)
    }
    @MainActor private func waitFor(_ done: () -> Bool) async throws {
        for _ in 0..<500 where !done() { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(done(), "timed out")
    }

    @MainActor func testPointingAtAStylePreviewsItWithoutChangingTheDesign() async throws {
        let (document, square) = documentWithASquare(), state = document.state
        let before = state.design
        FillStyleMenu.preview(.contour, state)
        try await waitFor { state.settingsPreview != nil }
        let preview = try XCTUnwrap(state.settingsPreview)
        XCTAssertEqual(preview.choice, FillStyleMenu.choice(.contour))
        XCTAssertEqual(preview.objects, [square.id])
        XCTAssertTrue(preview.plan.commands.contains { $0.op == .stitch && $0.objectID == square.id })
        XCTAssertEqual(state.design, before, "a preview changes nothing")

        FillStyleMenu.preview(.tatami, state)   // its own style: nothing to preview
        XCTAssertNil(state.settingsPreview)
        FillStyleMenu.preview(.radial, state); state.previewSettings(nil)   // moved off before it was ready
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(state.settingsPreview, "a late preview doesn't show up after moving off")
    }

    @MainActor func testAChosenStyleStaysPreviewedUntilItsStitchesArrive() async throws {
        let (document, _) = documentWithASquare(), state = document.state
        try await waitFor { state.compiledRevision == state.revision }
        FillStyleMenu.preview(.contour, state)
        try await waitFor { state.settingsPreview != nil }
        state.editSelected("Fill Style") { $0.digitizing?.fillStyle = .contour }
        state.keepSettingsPreview(FillStyleMenu.choice(.contour))
        state.previewSettings(nil)   // the menu closing
        XCTAssertEqual(state.settingsPreview?.kept, true, "still shown while the new stitches are worked out")
        try await waitFor { state.settingsPreview == nil }
        XCTAssertEqual(state.compiledRevision, state.revision, "gone once they're in")
    }
}
