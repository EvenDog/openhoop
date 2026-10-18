// Checks turning fills (stitch angles): stitches run along each angle line, turn between lines, cover the whole
// shape, and the lines move with the shape.
import XCTest
@testable import EmbroideryCore

final class TurningFillTests: XCTestCase {
    /// A wide L: an arm going up on the left and one going right along the bottom, 10 mm wide.
    private func elbow() -> RunObject {
        var object = RunObject(name: "Elbow", nodes: [Point(0, 0), Point(40, 0), Point(40, 10), Point(10, 10), Point(10, 40), Point(0, 40)].map { PathNode($0) }, color: ThreadColor.palette[0])
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        object.digitizing?.angleLines = [[Point(-2, 30), Point(12, 30)], [Point(30, -2), Point(30, 12)]]   // across each arm
        return object
    }
    /// The direction (0…180°) of the stitch nearest `p`, counting only full-length stitches (not the short steps
    /// from one row to the next).
    private func stitchDirection(near p: Point, in rows: [[Point]]) -> Double {
        let stitches = rows.flatMap { zip($0, $0.dropFirst()).filter { $0.distance(to: $1) >= 1.5 } }
        let (a, b) = stitches.min { AreaGeometry.projection(p, $0.0, $0.1).distance(to: p) < AreaGeometry.projection(p, $1.0, $1.1).distance(to: p) }!
        let degrees = (atan2(b.y - a.y, b.x - a.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 180)
        return degrees > 179.5 ? degrees - 180 : degrees   // 180° is the same direction as 0°
    }

    func testStitchesFollowEachAngleLineAndTurnBetween() throws {
        let object = elbow()
        let region = [AreaGeometry.ring(object.nodes)]
        let rows = try TurningFill.rows(in: region, angleLines: object.settings.angleLines!, spacing: 0.5, length: 3, start: nil)
        XCTAssertEqual(stitchDirection(near: Point(5, 35), in: rows), 0, accuracy: 3, "across the upright arm: level, like its angle line")
        XCTAssertEqual(stitchDirection(near: Point(35, 5), in: rows), 90, accuracy: 3, "across the lower arm: upright, like its angle line")
        XCTAssertEqual(stitchDirection(near: Point(7, 7), in: rows), 45, accuracy: 20, "turning half way at the bend")
        // Every part of the shape has a row within a row spacing of it.
        for p in [Point(1, 39), Point(5, 20), Point(5, 5), Point(20, 5), Point(39, 1), Point(39, 9)] {
            let nearest = rows.flatMap { zip($0, $0.dropFirst()).map { AreaGeometry.projection(p, $0, $1).distance(to: p) } }.min()!
            XCTAssertLessThanOrEqual(nearest, 0.6, "\(p) is covered")
        }
    }

    func testTurningFillSewsAndItsLinesMoveWithIt() throws {
        var design = Design()
        design.objects = [elbow()]
        XCTAssertTrue(design.needsSchemaFive, "an older version would sew straight rows")
        XCTAssertGreaterThan(try RunningEngine.compile(design).stitchCount, 0)
        design.move([design.objects[0].id], by: Point(5, 5))
        XCTAssertEqual(design.objects[0].settings.angleLines?[0], [Point(3, 35), Point(17, 35)])
        design.objects[0].digitizing?.angleLines = [[Point(100, 100), Point(110, 100)]]   // nowhere near the fill
        XCTAssertThrowsError(try RunningEngine.compile(design))
    }

    /// A real case: one short line clipping a corner of the shape still sets the direction for the whole fill.
    func testOneLineAcrossACornerFillsTheWholeShape() throws {
        let ring = [Point(0, 0), Point(20, 0), Point(20, 30), Point(0, 30)]
        let rows = try TurningFill.rows(in: [ring], angleLines: [[Point(-2, 26), Point(4, 32)]], spacing: 0.5, length: 3, start: nil)
        for p in [Point(1, 1), Point(10, 15), Point(19, 29), Point(19, 1), Point(1, 29)] {
            let nearest = rows.flatMap { zip($0, $0.dropFirst()).map { AreaGeometry.projection(p, $0, $1).distance(to: p) } }.min()!
            XCTAssertLessThanOrEqual(nearest, 0.6, "\(p) is covered")
        }
        XCTAssertEqual(stitchDirection(near: Point(10, 15), in: rows), 45, accuracy: 1)
    }

    /// With several lines, the parts beyond the first and last lines are filled right out to the edge too.
    func testThePartsBeyondTheEndLinesAreFilled() throws {
        let object = elbow()
        var lines = object.settings.angleLines!
        lines[0] = [Point(-2, 20), Point(12, 20)]; lines[1] = [Point(20, -2), Point(20, 12)]   // leaves long arms beyond each line
        let rows = try TurningFill.rows(in: [AreaGeometry.ring(object.nodes)], angleLines: lines, spacing: 0.5, length: 3, start: nil)
        for p in [Point(1, 39), Point(9, 39), Point(5, 30), Point(39, 1), Point(39, 9), Point(30, 5)] {
            let nearest = rows.flatMap { zip($0, $0.dropFirst()).map { AreaGeometry.projection(p, $0, $1).distance(to: p) } }.min()!
            XCTAssertLessThanOrEqual(nearest, 0.6, "\(p) is covered")
        }
    }

    /// A ring (a shape with a hole) with lines from its outside edge to the hole's: the stitches turn all the way
    /// round, from the last line back to the first, rather than leaving the stretch between them unsewn.
    func testOnARingTheStitchesTurnAllTheWayRound() throws {
        func circle(_ r: Double, clockwise: Bool) -> [Point] {
            (0..<72).map { k in let a = Double(clockwise ? -k : k) / 72 * 2 * .pi; return Point(r * cos(a), r * sin(a)) }
        }
        func radial(_ degrees: Double) -> [Point] { let a = degrees * .pi / 180; return [Point(8 * cos(a), 8 * sin(a)), Point(22 * cos(a), 22 * sin(a))] }
        for angles in [[0.0, 90, 180, 270], [0, 180], [10, 60, 200]] {
            let rows = try TurningFill.rows(in: [circle(20, clockwise: false), circle(10, clockwise: true)], angleLines: angles.map(radial), spacing: 0.5, length: 3, start: nil)
            for degrees in stride(from: 0.0, to: 360, by: 5) {
                let a = degrees * .pi / 180
                for r in [11.0, 15, 19] {
                    let p = Point(r * cos(a), r * sin(a))
                    let nearest = rows.flatMap { zip($0, $0.dropFirst()).map { AreaGeometry.projection(p, $0, $1).distance(to: p) } }.min()!
                    XCTAssertLessThanOrEqual(nearest, 0.6, "lines at \(angles): \(degrees)° is covered")
                }
                let p = Point(15 * cos(a), 15 * sin(a))
                XCTAssertEqual(stitchDirection(near: p, in: rows), degrees.truncatingRemainder(dividingBy: 180), accuracy: 6, "lines at \(angles): stitches run across the ring at \(degrees)°")
            }
        }
    }

    func testCuttingOutOverlapsKeepsEachPiecesOwnLines() throws {
        // A bar sewn on top across the elbow's corner splits it in two; each piece turns by its own arm's line.
        var elbow = elbow(); elbow.digitizing?.cutOutOverlaps = true
        var bar = RunObject(name: "Bar", nodes: [Point(-2, 12), Point(14, -2), Point(16, 0), Point(0, 14)].map { PathNode($0) }, color: ThreadColor.palette[1])
        bar.closed = true; bar.digitizing = DigitizingSettings(kind: .fill)
        var design = Design(); design.objects = [elbow, bar]
        let plan = try RunningEngine.compile(design)
        XCTAssertFalse(plan.warnings.contains { $0.contains("couldn't be cut out") }, "\(plan.warnings)")
    }

    /// A shape with a notch between an upright arm and a triangle (drawn in the app, 2026-10-17), with two angle
    /// lines. Many in-between lines cross the notch, and the in-between lines sweep back over ground they already
    /// covered as their ends go up the arm and down the notch. The rows used to be sewn in line order, so the needle
    /// travelled round the notch after almost every row (44 moves over 3 mm, 592 mm), and later rows were sewn again
    /// on top of earlier ones at another angle (827 crossing rows). Now only uncovered ground is sewn, in streams
    /// that are each finished in one go.
    func testRowsSplitByANotchAreSewnOnceAndOneAreaAtATime() throws {
        let points = [(-26.51, 28.28), (-23.33, 39.93), (-9.1, 24.42), (-19.1, 11.36), (-37.69, 15.71), (-39.45, 29.28),
                      (-30.44, 26.92), (-30.91, 37.79), (-28.02, 39.76), (-26.37, 36.73), (-27.08, 35.16)]
        let smooth = [false, false, false, false, false, true, false, false, true, true, false]
        var object = RunObject(name: "Notch", nodes: zip(points, smooth).map { PathNode(Point($0.0.0, $0.0.1), smooth: $0.1) }, color: ThreadColor.palette[0])
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        let lines = [[Point(-35.0, 36.08), Point(-34.81, 10.28)], [Point(-26.15, 33.91), Point(-14.37, 34.18)]]
        let region = try AreaGeometry.offset([AreaGeometry.ring(object.nodes)], by: 0.2)
        let streams = try TurningFill.rows(in: region, angleLines: lines, spacing: 0.4, length: 3, start: nil)
        XCTAssertLessThanOrEqual(streams.count, 12, "a few areas, each sewn in one go")
        // No stitch crosses another part-way along both (a stitch laid over earlier ones at another angle).
        let stitches = streams.flatMap { zip($0, $0.dropFirst()).map { ($0, $1) } }.filter { $0.0.distance(to: $0.1) > 0.01 }
        func crosses(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Bool {
            let d1 = AreaGeometry.cross(b - a, c - a), d2 = AreaGeometry.cross(b - a, d - a)
            let d3 = AreaGeometry.cross(d - c, a - c), d4 = AreaGeometry.cross(d - c, b - c)
            return d1 * d2 < -1e-9 && d3 * d4 < -1e-9
        }
        var crossings = 0
        for i in stitches.indices { for j in stitches.indices where j > i && crosses(stitches[i].0, stitches[i].1, stitches[j].0, stitches[j].1) { crossings += 1 } }
        // The compiled design had over 1,000 crossing pairs before; what is left are grazes where a fan of rows narrows.
        XCTAssertLessThanOrEqual(crossings, 40, "the odd graze where rows meet, not rows sewn over rows")
        // Still every part of the shape gets thread: points all over it have a stitch within a row spacing or so.
        for p in [Point(-36, 20), Point(-29, 38), Point(-28, 20), Point(-15, 20), Point(-12, 25), Point(-22, 36), Point(-20, 14)] {
            let nearest = stitches.map { AreaGeometry.projection(p, $0.0, $0.1).distance(to: p) }.min()!
            XCTAssertLessThanOrEqual(nearest, 0.6, "\(p) is covered")
        }
    }
}
