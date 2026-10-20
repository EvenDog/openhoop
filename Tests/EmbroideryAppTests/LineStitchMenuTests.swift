// The line stitch menus: every line stitch has a picture, and pointing at a Line style previews it on the selected
// line without changing the design.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class LineStitchMenuTests: XCTestCase {
    func testEveryLineStitchHasSampleStitches() {
        for stitch in LineStitch.all {
            let points = LineStitchSamples.stitches(stitch).joined()
            XCTAssertGreaterThan(points.count, 8, "\(stitch) has a picture")
            XCTAssertTrue(points.allSatisfy { abs($0.x) <= 20 && abs($0.y) <= 20 }, "\(stitch) stays near the sample curve")
        }
        // A satin line is wider than a running line, so the pictures differ.
        func height(_ stitch: LineStitch) -> Double { let ys = LineStitchSamples.stitches(stitch).joined().map(\.y); return ys.max()! - ys.min()! }
        XCTAssertGreaterThan(height(.newLine(.satin)), height(.newLine(.running)) + 2)
    }

    @MainActor func testPointingAtALineStylePreviewsItWithoutChangingTheDesign() async throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        let line = RunObject(name: "Line", nodes: [Point(0, 0), Point(40, 10)].map { PathNode($0) }, color: ThreadColor.palette[0])
        state.edit("Add") { $0.objects = [line] }
        state.selection = [line.id]
        let before = state.design
        LineStyleMenu.preview(.zigzag, state)
        for _ in 0..<500 where state.settingsPreview == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let preview = try XCTUnwrap(state.settingsPreview)
        XCTAssertEqual(preview.choice, LineStyleMenu.choice(.zigzag))
        XCTAssertEqual(preview.objects, [line.id])
        // Zigzag swings off the line: its stitches reach further from it than a running line's.
        let offLine = preview.plan.commands.filter { $0.op == .stitch }.map { abs($0.point.y - $0.point.x / 4) }
        XCTAssertGreaterThan(offLine.max() ?? 0, 0.5)
        XCTAssertEqual(state.design, before, "a preview changes nothing")

        LineStyleMenu.preview(.running, state)   // its own style: nothing to preview
        XCTAssertNil(state.settingsPreview)
    }
}
