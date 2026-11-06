// Checks the stitch view's selection highlight: with Thread View off, a selected object's stitches are drawn in the
// highlight blue; unselected, or in Thread View, they keep their thread color.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class StitchHighlightTests: XCTestCase {
    @MainActor func testSelectedStitchesTurnBlueOnlyInTheStitchView() throws {
        _ = NSApplication.shared
        var fill = RunObject(name: "Red", nodes: [Point(-15, -15), Point(15, -15), Point(15, 15), Point(-15, 15)].map { PathNode($0) }, color: ThreadColor("Red", 0xFF0000))
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.stitchLength = 3
        let document = DesignDocument(), state = document.state
        state.design.objects = [fill]
        document.makeWindowControllers()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.setFrame(NSRect(x: 0, y: 0, width: 1100, height: 800), display: true)
        let deadline = Date().addingTimeInterval(10)
        while state.plan.stitchCount == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        state.needles = false
        let canvas = try XCTUnwrap(state.canvas)

        /// How many pixels in the middle 10 × 10 mm of the fill are clearly blue.
        func bluePixels(threadView: Bool) throws -> Int {
            Preferences.shared.data.threadView = threadView
            canvas.needsDisplay = true; canvas.display()
            let rep = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            let scale = Double(rep.pixelsWide) / canvas.bounds.width
            let low = canvas.screen(Point(-5, -5)), high = canvas.screen(Point(5, 5))
            var count = 0
            for y in stride(from: low.y, to: high.y, by: 1) { for x in stride(from: low.x, to: high.x, by: 1) {
                // The canvas isn't flipped (y points up); the picture's rows go down.
                guard let color = rep.colorAt(x: Int(x * scale), y: Int((canvas.bounds.height - y) * scale))?.usingColorSpace(.sRGB) else { continue }
                if color.blueComponent > color.redComponent + 0.2 { count += 1 }
            } }
            return count
        }
        state.selection = []
        XCTAssertEqual(try bluePixels(threadView: false), 0, "not selected: red stitches")
        state.selection = [fill.id]
        XCTAssertGreaterThan(try bluePixels(threadView: false), 100, "selected, stitch view: blue stitches")
        XCTAssertEqual(try bluePixels(threadView: true), 0, "Thread View shows the real thread")
    }
}
