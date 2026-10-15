// Checks the canvas zooms: zooming to a box frames it in the middle of the canvas, and zooming around a point keeps
// that point still on screen (as the Zoom Box tool's click does).
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ZoomTests: XCTestCase {
    @MainActor private func canvas() -> DesignCanvas {
        _ = NSApplication.shared
        let canvas = DesignCanvas(state: EditorState())
        canvas.setFrameSize(NSSize(width: 800, height: 600))
        return canvas
    }

    @MainActor func testZoomToBoxFramesItInTheMiddle() {
        let canvas = canvas()
        canvas.zoom(to: (Point(10, 20), Point(30, 30)))   // 20 × 10 mm: the width decides, (800 - 100) / 20 = 35
        XCTAssertEqual(canvas.state.zoom, 35, accuracy: 0.0001)
        let middle = canvas.screen(Point(20, 25))
        XCTAssertEqual(middle.x, 400, accuracy: 0.0001); XCTAssertEqual(middle.y, 300, accuracy: 0.0001)
        let corner = canvas.screen(Point(10, 20))
        XCTAssertEqual(corner.x, 50, accuracy: 0.0001, "50 points of room on each side")

        canvas.zoom(to: (Point(0, 0), Point(0.1, 0.1)))   // a tiny box stops at the 60× limit
        XCTAssertEqual(canvas.state.zoom, 60)
    }

    @MainActor func testZoomingAroundAPointKeepsItStill() {
        let canvas = canvas()
        canvas.setZoom(5)
        let anchor = CGPoint(x: 600, y: 150), spot = canvas.model(anchor)
        canvas.setZoom(10, keeping: anchor)
        XCTAssertEqual(canvas.state.zoom, 10)
        let after = canvas.screen(spot)
        XCTAssertEqual(after.x, anchor.x, accuracy: 0.0001); XCTAssertEqual(after.y, anchor.y, accuracy: 0.0001)
        canvas.setZoom(1000)
        XCTAssertEqual(canvas.state.zoom, 60, "zoom stays within its limits")
    }
}
