// Moving and sizing the reference image by dragging it or its corners.
import XCTest
@testable import EmbroideryCore

final class ArtworkTests: XCTestCase {
    private let art = Artwork(data: Data(), name: "logo.png", width: 80, height: 40)   // centered at 0,0

    func testDraggingMovesIt() {
        let moved = art.adjusted(corner: -1, from: Point(1, 1), to: Point(6, -2), free: false)
        XCTAssertEqual(moved.center, Point(5, -3)); XCTAssertEqual(moved.width, 80); XCTAssertEqual(moved.height, 40)
    }

    func testCornerResizeKeepsProportionsAndTheOppositeCorner() {
        // Top-right corner (40, 20) dragged right and down: the larger change (to the right) wins, proportions stay 2:1.
        let bigger = art.adjusted(corner: 2, from: Point(40, 20), to: Point(60, 10), free: false)
        XCTAssertEqual(bigger.width, 100, accuracy: 1e-9); XCTAssertEqual(bigger.height, 50, accuracy: 1e-9)
        XCTAssertEqual(bigger.corners[0], art.corners[0], "The bottom-left corner stays put")
        // Dragging a corner inward shrinks it.
        let smaller = art.adjusted(corner: 0, from: Point(-40, -20), to: Point(-20, -10), free: false)
        XCTAssertEqual(smaller.width, 60, accuracy: 1e-9); XCTAssertEqual(smaller.height, 30, accuracy: 1e-9)
        XCTAssertEqual(smaller.corners[2], art.corners[2], "The top-right corner stays put")
    }

    func testShiftStretchesAndSizeNeverCollapses() {
        let stretched = art.adjusted(corner: 2, from: Point(40, 20), to: Point(60, 10), free: true)
        XCTAssertEqual(stretched.width, 100, accuracy: 1e-9); XCTAssertEqual(stretched.height, 30, accuracy: 1e-9)
        // Dragging past the opposite corner stops at 2 mm instead of flipping the image.
        let tiny = art.adjusted(corner: 2, from: Point(40, 20), to: Point(-90, -90), free: false)
        XCTAssertGreaterThanOrEqual(min(tiny.width, tiny.height), 2 - 1e-9)
        XCTAssertEqual(tiny.width / tiny.height, 2, accuracy: 1e-9)
    }
}
