// Moving and sizing the reference image by dragging it or its corners, and turning, flipping and skewing it.
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

    /// Points for comparing, rounded to 1e-6 mm so float noise doesn't matter.
    private func near(_ points: [Point]) -> [Point] { points.map { Point(($0.x * 1e6).rounded() / 1e6 + 0, ($0.y * 1e6).rounded() / 1e6 + 0) } }

    func testTurningAndFlippingMoveItsCornersAndComeBackPlain() {
        let turned = art.rotated(by: 90)
        XCTAssertEqual(near(turned.corners), [Point(20, -40), Point(20, 40), Point(-20, 40), Point(-20, -40)], "its own bottom-left is now bottom-right")
        XCTAssertEqual(near([turned.bounds.max]), [Point(20, 40)])
        XCTAssertTrue(turned.isTransformed)
        XCTAssertFalse(turned.rotated(by: 90).rotated(by: 90).rotated(by: 90).isTransformed, "four quarter turns are plain again")
        let flipped = art.flipped(horizontally: true)
        XCTAssertEqual(near(flipped.corners)[0], Point(40, -20), "its own left side is on the right")
        XCTAssertFalse(flipped.flipped(horizontally: true).isTransformed)
        XCTAssertEqual(near(art.flipped(horizontally: false).corners)[0], Point(-40, 20))
        // Going into its own frame and back lands on the same point, however it's been changed.
        let mixed = art.rotated(by: 30).skewed(by: 20).flipped(horizontally: true)
        XCTAssertEqual(mixed.place(mixed.local(Point(7, -3))).distance(to: Point(7, -3)), 0, accuracy: 1e-9)
        XCTAssertFalse(mixed.straightened.isTransformed)
    }

    func testHandlesTurnItAndLeanItAlongItsOwnSides() {
        // The top-right corner swung a quarter turn counterclockwise, to where the top-left of a 90° turn would be.
        let turn = art.turned(handle: 2, from: Point(40, 20), to: Point(-20, 40))
        XCTAssertEqual(turn.degrees, 90); XCTAssertEqual(near(turn.artwork.corners), near(art.rotated(by: 90).corners))
        // Shift's 15° steps: 37° becomes 30°.
        XCTAssertEqual(art.turned(handle: 2, from: Point(40, 20), to: art.rotated(by: 37).corners[2], step: 15).degrees, 30)
        // The top side dragged 40 mm right on a 40 mm tall image: 45°, its bottom side stays put.
        let lean = art.turned(handle: 6, from: Point(0, 20), to: Point(40, 20))
        XCTAssertEqual(lean.degrees, 45)
        XCTAssertEqual(near(lean.artwork.corners), [Point(-40, -20), Point(40, -20), Point(80, 20), Point(0, 20)])
        // The right side dragged up 80 mm on an 80 mm wide image: 45°, the left side stays put.
        let up = art.turned(handle: 5, from: Point(40, 0), to: Point(40, 80))
        XCTAssertEqual(near(up.artwork.corners), [Point(-40, -20), Point(40, 60), Point(40, 100), Point(-40, 20)])
        XCTAssertEqual(art.turned(handle: 6, from: Point(0, 20), to: Point(400, 20)).degrees, 60, "it leans no further than 60°")
        // On a turned image, the sides are its own: its top side (now on the left) slides up and down the canvas.
        let turned = art.rotated(by: 90), side = turned.turned(handle: 6, from: Point(-20, 0), to: Point(-20, 40))
        XCTAssertEqual(near(side.artwork.corners)[0], near(turned.corners)[0], "its own bottom side stays put")
        XCTAssertEqual(near(side.artwork.corners)[3], Point(-20, 0))
    }

    func testCornerResizeOfATurnedImageFollowsItsOwnSides() {
        let turned = art.rotated(by: 90)   // own top-right corner (40, 20) is at (-20, 40) on the canvas
        let bigger = turned.adjusted(corner: 2, from: Point(-20, 40), to: Point(-30, 60), free: true)
        XCTAssertEqual(bigger.width, 100, accuracy: 1e-9); XCTAssertEqual(bigger.height, 50, accuracy: 1e-9)
        XCTAssertEqual(near(bigger.corners)[0], near(turned.corners)[0], "its own bottom-left corner stays put")
    }
}
