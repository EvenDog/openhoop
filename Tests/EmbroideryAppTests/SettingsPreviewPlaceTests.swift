// Checks that trying a choice from a picture menu (here a fill style) only changes the tried object's stitches on the
// canvas: they're drawn at its place in the sewing order, so an object sewn after it still lies on top.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class SettingsPreviewPlaceTests: XCTestCase {
    @MainActor func testATriedFillStaysUnderWhatIsSewnAfterIt() throws {
        _ = NSApplication.shared
        func square(_ name: String, _ half: Double, _ hex: Int, angle: Double) -> RunObject {
            var o = RunObject(name: name, nodes: [Point(-half, -half), Point(half, -half), Point(half, half), Point(-half, half)].map { PathNode($0) }, color: ThreadColor(name, hex))
            o.closed = true; var s = DigitizingSettings(kind: .fill); s.angle = angle; o.digitizing = s; o.stitchLength = 3
            return o
        }
        // A red fill, then a smaller blue one sewn on top of its middle.
        let base = square("Base", 20, 0xFF0000, angle: 45), top = square("Top", 8, 0x0000FF, angle: -45)
        let document = DesignDocument()
        document.state.design.objects = [base, top]
        document.makeWindowControllers()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.setFrame(NSRect(x: 0, y: 0, width: 1100, height: 800), display: true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        document.state.selection = [base.id]
        let canvas = try XCTUnwrap(document.state.canvas)

        /// How many pixels in the middle 10 × 10 mm (inside the blue fill) are more blue than red.
        func bluePixels() throws -> Int {
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
        let before = try bluePixels()
        XCTAssertGreaterThan(before, 100, "the blue fill shows")

        document.state.previewSettings("style:contour") { $0.fillStyle = .contour }
        let deadline = Date().addingTimeInterval(10)
        while document.state.settingsPreview == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertNotNil(document.state.settingsPreview, "the tried style is ready")
        canvas.display()
        XCTAssertGreaterThan(Double(try bluePixels()), 0.8 * Double(before), "the red fill's tried stitches stay under the blue fill")
    }
}
