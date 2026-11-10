// The stitch angle line Edit Nodes shows on a fill: where it sits, which fills get one, and what swinging it by an
// end does.
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

    /// A line moved off the middle still crosses the whole shape at the fill's angle, through where it was put, moves
    /// with the shape, and never counts as a change to the stitches.
    func testMovedLineCrossesTheShapeThroughItsNewCenter() throws {
        var object = rectangle(angle: 0)   // 40 × 20 mm, middle at (10, 5)
        object.digitizing?.angleLineCenter = Point(0, 12)
        let ends = try XCTUnwrap(StitchAngleLine.ends(of: object))
        XCTAssertEqual(ends.0.x, -12, accuracy: 1e-9); XCTAssertEqual(ends.1.x, 32, accuracy: 1e-9)
        XCTAssertEqual(ends.0.y, 12, accuracy: 1e-9); XCTAssertEqual(ends.1.y, 12, accuracy: 1e-9)
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

    /// Swinging the line by one end: the other end stays put, the line runs from it to the pointer, and the angle is
    /// that line's direction, to a tenth of a degree from 0 to 179.9, whichever way it points.
    func testSwingKeepsTheOtherEndPut() throws {
        func swung(from anchor: Point, to point: Point) -> RunObject {
            var object = rectangle(angle: 45); StitchAngleLine.swing(&object, from: anchor, to: point); return object
        }
        let anchor = Point(-12, 5)
        let flat = swung(from: anchor, to: Point(20, 5))
        XCTAssertEqual(flat.settings.angle, 0)
        let ends = try XCTUnwrap(StitchAngleLine.ends(of: flat))
        XCTAssertEqual(ends.0.x, -12, accuracy: 1e-9); XCTAssertEqual(ends.1.x, 20, accuracy: 1e-9, "ends at the pointer, not past the edge")
        XCTAssertEqual(ends.0.y, 5, accuracy: 1e-9); XCTAssertEqual(ends.1.y, 5, accuracy: 1e-9)
        // Up and to the right: 45°. Down and to the left gives the same, since a line points both ways.
        XCTAssertEqual(swung(from: anchor, to: Point(-2, 15)).settings.angle, 45, accuracy: 1e-9)
        XCTAssertEqual(swung(from: anchor, to: Point(-22, -5)).settings.angle, 45, accuracy: 1e-9)
        XCTAssertEqual(swung(from: anchor, to: Point(-22, 15)).settings.angle, 135, accuracy: 1e-9)
        XCTAssertEqual(swung(from: anchor, to: Point(-12, -20)).settings.angle, 90, accuracy: 1e-9)
        XCTAssertEqual(swung(from: anchor, to: Point(20, 5.3)).settings.angle, 0.5, accuracy: 1e-9, "a tenth of a degree, not a whole one")
        // Both ends land where the drag put them, whichever way the line points.
        let steep = swung(from: anchor, to: Point(-22, 15))
        let steepEnds = try XCTUnwrap(StitchAngleLine.ends(of: steep))
        XCTAssertEqual(Set([steepEnds.0, steepEnds.1].map { "\(($0.x * 1e6).rounded()),\(($0.y * 1e6).rounded())" }), ["-12000000.0,5000000.0", "-22000000.0,15000000.0"])
        // Right on top of the anchor changes nothing.
        let same = swung(from: anchor, to: Point(-11.5, 5))
        XCTAssertEqual(same.settings.angle, 45); XCTAssertNil(same.settings.angleLineLength)
        // Swinging never counts as a change to the stitches, except for the angle itself.
        var turnedOnly = rectangle(angle: 0); turnedOnly.digitizing?.angle = flat.settings.angle
        XCTAssertEqual(flat.stitchSignature, turnedOnly.stitchSignature)
    }

    /// A line dragged to a length keeps it when the shape moves, and stretches with it when the shape is resized.
    func testLengthStretchesWithTheShape() throws {
        var object = rectangle(angle: 45); StitchAngleLine.swing(&object, from: Point(0, 5), to: Point(10, 5))   // 10 mm, flat
        var moved = object; moved.transform { $0 + Point(3, 4) }
        XCTAssertEqual(try XCTUnwrap(moved.settings.angleLineLength), 10, accuracy: 1e-9)
        XCTAssertEqual(moved.settings.angleLineCenter, Point(8, 9))
        var wider = object; wider.transform { Point($0.x * 2, $0.y) }
        XCTAssertEqual(try XCTUnwrap(wider.settings.angleLineLength), 20, accuracy: 1e-9, "twice as wide, twice as long")
        var taller = object; taller.transform { Point($0.x, $0.y * 2) }
        XCTAssertEqual(try XCTUnwrap(taller.settings.angleLineLength), 10, accuracy: 1e-9, "a flat line isn't stretched by height")
    }
}
