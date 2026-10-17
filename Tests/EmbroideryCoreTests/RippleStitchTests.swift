// Checks ripple lines: a closed shape spirals in toward its target in one unbroken line, an open line is sewn there
// and back with each copy smaller, the default target sits off a straight line (whichever way it's drawn), and a
// moved target and the line count change the stitches.
import XCTest
@testable import EmbroideryCore

final class RippleStitchTests: XCTestCase {
    private func ripple(_ path: [Point], closed: Bool, target: Point? = nil, lines: Int = 5) -> [Point] {
        RunningStyles.stitches(.ripple, along: path, closed: closed, width: 0, spacing: 0, length: 2.5, target: target, lines: lines)!
    }

    func testAClosedShapeSpiralsIn() {
        let square = [Point(0, 0), Point(20, 0), Point(20, 20), Point(0, 20), Point(0, 0)]
        let points = ripple(square, closed: true)
        XCTAssertEqual(points.first!, Point(0, 0), "starts on the outline")
        let center = Point(10, 10)
        XCTAssertEqual(points.last!.distance(to: center), Point(0, 0).distance(to: center) / 5, accuracy: 0.01, "ends on the smallest ring, a fifth of the size")
        XCTAssertTrue(points.allSatisfy { $0.x >= -1e-9 && $0.x <= 20 + 1e-9 && $0.y >= -1e-9 && $0.y <= 20 + 1e-9 }, "inside the shape")
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.distance(to: $1) <= 2.81 }, "stitches about the stitch length")
        // Each lap round is a little smaller: the farthest point from the middle shrinks lap by lap.
        let laps = stride(from: 0, to: points.count, by: max(1, points.count / 8)).map { points[$0].distance(to: center) }
        XCTAssertGreaterThan(laps.first!, laps.last!)
    }

    func testAnOpenLineIsSewnThereAndBack() {
        let line = [Point(0, 0), Point(30, 0)]
        let target = RunningStyles.rippleTarget(line, closed: false)
        XCTAssertEqual(target.x, 15, accuracy: 1e-9); XCTAssertEqual(abs(target.y), 15, accuracy: 1e-9, "off to one side of a straight line")
        XCTAssertEqual(RunningStyles.rippleTarget(line.reversed(), closed: false), target, "whichever way it's drawn")
        let points = ripple(line, closed: false)
        XCTAssertEqual(points.first!, Point(0, 0))
        // The second copy, four fifths the size (5 lines), is sewn backwards: it starts by the first one's end.
        let secondStart = target + (Point(30, 0) - target) * 0.8
        XCTAssertTrue(points.contains { $0.distance(to: secondStart) < 1e-6 }, "the next copy starts at its end nearest the last one's end")
        XCTAssertEqual(points.last!.distance(to: target), Point(0, 0).distance(to: target) / 5, accuracy: 1e-6, "the smallest copy is a fifth of the size")

        // A curved line's copies shrink toward the middle of its points.
        let arc = stride(from: 0.0, through: Double.pi, by: .pi / 20).map { Point(10 * cos($0), 10 * sin($0)) }
        XCTAssertEqual(RunningStyles.rippleTarget(arc, closed: false).x, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(RunningStyles.rippleTarget(arc, closed: false).y, 3)
    }

    func testRippleObjectsSewAndTheirSettingsCount() throws {
        var ring = RunObject(name: "Ring", nodes: [Point(0, 0), Point(30, 0), Point(30, 20), Point(0, 20)].map { PathNode($0) })
        ring.closed = true; ring.digitizing = DigitizingSettings(kind: .run); ring.digitizing?.runStyle = .ripple
        var design = Design(); design.objects = [ring]
        let plain = try StitchEngine.compile(design).commands.filter { $0.op == .stitch }
        XCTAssertTrue(design.needsSchemaSix)
        design.objects[0].digitizing?.rippleLines = 20
        XCTAssertGreaterThan(try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.count, plain.count, "more lines, more stitches")
        design.objects[0].digitizing?.radialCenter = Point(5, 5)
        XCTAssertEqual(try StitchEngine.compile(design).commands.last { $0.op == .stitch }!.point.distance(to: Point(5, 5)), Point(0, 0).distance(to: Point(5, 5)) / 20, accuracy: 0.05, "it shrinks toward the moved target")
        var moved = design.objects[0]; moved.transform { $0 + Point(10, 0) }
        XCTAssertEqual(moved.settings.radialCenter, Point(15, 5), "the target moves with the line")
        design.objects[0].digitizing?.rippleLines = 100
        XCTAssertThrowsError(try design.validate(), "too many lines")
    }
}
