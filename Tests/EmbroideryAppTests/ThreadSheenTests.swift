// Checks Thread View's sheen: a stitch running straight across the light from the top left shines most, one running
// towards it shines least, and the direction the needle travels makes no difference.
import XCTest
import AppKit
@testable import EmbroideryApp

final class ThreadSheenTests: XCTestCase {
    private let shiniest = DesignCanvas.sheenLevels - 1

    func testAStitchAcrossTheLightShinesMost() {
        // Top right to bottom left (y up) is square-on to a light from the top left.
        XCTAssertEqual(DesignCanvas.sheenLevel(along: CGVector(dx: 1, dy: 1)), shiniest)
        XCTAssertEqual(DesignCanvas.sheenLevel(along: CGVector(dx: -3, dy: -3)), shiniest)
    }

    func testAStitchTowardsTheLightIsDull() {
        XCTAssertEqual(DesignCanvas.sheenLevel(along: CGVector(dx: -1, dy: 1)), 0)
        XCTAssertEqual(DesignCanvas.sheenLevel(along: CGVector(dx: 2, dy: -2)), 0)
    }

    func testLevelsRiseAsAStitchTurnsAcrossTheLight() {
        // From pointing at the light (135°) round to square-on (45°), the level never drops.
        let levels = stride(from: 135.0, through: 45.0, by: -5).map { degrees -> Int in
            let angle = degrees * .pi / 180
            return DesignCanvas.sheenLevel(along: CGVector(dx: cos(angle), dy: sin(angle)))
        }
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertEqual(levels.first, 0); XCTAssertEqual(levels.last, shiniest)
        // Horizontal and vertical stitches sit in between.
        XCTAssertTrue((1..<shiniest).contains(DesignCanvas.sheenLevel(along: CGVector(dx: 1, dy: 0))))
        XCTAssertTrue((1..<shiniest).contains(DesignCanvas.sheenLevel(along: CGVector(dx: 0, dy: 1))))
    }

    func testAZeroLengthStitchIsDull() {
        XCTAssertEqual(DesignCanvas.sheenLevel(along: CGVector(dx: 0, dy: 0)), 0)
    }
}
