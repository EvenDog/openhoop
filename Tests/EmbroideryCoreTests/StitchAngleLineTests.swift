// The stitch angle line Edit Nodes shows on a fill: where it sits, which fills get one, and the angle a dragged end
// gives.
import XCTest
@testable import EmbroideryCore

final class StitchAngleLineTests: XCTestCase {
    /// A 40 × 20 mm rectangle fill centered on (10, 5).
    private func rectangle(angle: Double) -> RunObject {
        var object = RunObject(name: "Box", nodes: [Point(-10, -5), Point(30, -5), Point(30, 15), Point(-10, 15)].map { PathNode($0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill); object.digitizing?.angle = angle
        return object
    }

    /// The line runs through the middle of the shape at the fill's angle and reaches 2 mm past its edges.
    func testLineCrossesTheShapeAtItsAngle() throws {
        let flat = try XCTUnwrap(StitchAngleLine.ends(of: rectangle(angle: 0)))
        XCTAssertEqual(flat.0.x, -12, accuracy: 1e-9); XCTAssertEqual(flat.1.x, 32, accuracy: 1e-9)
        XCTAssertEqual(flat.0.y, 5, accuracy: 1e-9); XCTAssertEqual(flat.1.y, 5, accuracy: 1e-9)
        let upright = try XCTUnwrap(StitchAngleLine.ends(of: rectangle(angle: 90)))
        XCTAssertEqual(upright.0.x, 10, accuracy: 1e-9); XCTAssertEqual(upright.0.y, -7, accuracy: 1e-9); XCTAssertEqual(upright.1.y, 17, accuracy: 1e-9)
        // The default 45°: the line's direction is the fill's angle.
        let slanted = try XCTUnwrap(StitchAngleLine.ends(of: rectangle(angle: 45)))
        XCTAssertEqual(atan2(slanted.1.y - slanted.0.y, slanted.1.x - slanted.0.x) * 180 / .pi, 45, accuracy: 1e-9)
    }

    /// A line moved off the middle still crosses the whole shape at the fill's angle, through where it was put, turns
    /// around that point, moves with the shape, and never counts as a change to the stitches.
    func testMovedLineCrossesTheShapeThroughItsNewCenter() throws {
        var object = rectangle(angle: 0)   // 40 × 20 mm, middle at (10, 5)
        object.digitizing?.angleLineCenter = Point(0, 12)
        let ends = try XCTUnwrap(StitchAngleLine.ends(of: object))
        XCTAssertEqual(ends.0.x, -12, accuracy: 1e-9); XCTAssertEqual(ends.1.x, 32, accuracy: 1e-9)
        XCTAssertEqual(ends.0.y, 12, accuracy: 1e-9); XCTAssertEqual(ends.1.y, 12, accuracy: 1e-9)
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(0, 20)), 90, "turns around its own center")
        var moved = object; moved.transform { $0 + Point(5, 5) }
        XCTAssertEqual(moved.settings.angleLineCenter, Point(5, 17))
        XCTAssertEqual(object.stitchSignature, rectangle(angle: 0).stitchSignature, "hand-edited stitches are kept")
    }

    /// Only fills whose rows follow the angle get a line: tatami (unless angle lines steer it) and wave.
    func testOnlyFillsThatFollowTheAngleGetALine() {
        var object = rectangle(angle: 45)
        XCTAssertTrue(StitchAngleLine.applies(to: object))
        object.digitizing?.fillStyle = .wave; XCTAssertTrue(StitchAngleLine.applies(to: object))
        object.digitizing?.fillStyle = .contour; XCTAssertFalse(StitchAngleLine.applies(to: object))
        object.digitizing?.fillStyle = .radial; XCTAssertNil(StitchAngleLine.ends(of: object))
        object.digitizing?.fillStyle = nil; object.digitizing?.angleLines = [[Point(0, 0), Point(10, 10)]]
        XCTAssertFalse(StitchAngleLine.applies(to: object), "a turning fill shows its own angle lines instead")
        var line = rectangle(angle: 45); line.digitizing = nil
        XCTAssertFalse(StitchAngleLine.applies(to: line))
    }

    /// Dragging an end toward a point sets the angle from the middle to it, in whole degrees from 0 to 179: either
    /// end gives the same angle, because a line points both ways.
    func testDraggedEndGivesTheAngle() {
        let object = rectangle(angle: 45)   // middle at (10, 5)
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(20, 5)), 0)
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(20, 15)), 45)
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(0, -5)), 45, "the other end")
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(0, 15)), 135)
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(10, -10)), 90)
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(20, 5.3)), 2, "rounded to whole degrees")
        XCTAssertEqual(StitchAngleLine.angle(of: object, toward: Point(10, 5)), 45, "the middle itself keeps the angle")
    }
}
