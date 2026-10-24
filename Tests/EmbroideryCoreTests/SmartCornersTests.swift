// Smart corners: sharp corners of satin lines and borders are mitred (or capped when very sharp) instead of rounded,
// reach right out to the point, keep sewing where rounding was refused, and can be turned on and off.
import XCTest
@testable import EmbroideryCore

final class SmartCornersTests: XCTestCase {
    /// A V-shaped running line whose legs (15 mm) meet at the origin with `angle` degrees between them, opening upward.
    private func vee(_ angle: Double) -> RunObject {
        let half = angle / 2 * .pi / 180
        return RunObject(name: "V", nodes: [Point(-15 * sin(half), 15 * cos(half)), Point(0, 0), Point(15 * sin(half), 15 * cos(half))].map { PathNode($0) })
    }
    private func stitches(_ object: RunObject) throws -> [Point] {
        var satin = object; satin.digitizing?.underlay = .none
        var design = Design(); design.objects = [satin]
        return try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point)
    }
    private func pairs(_ object: RunObject) -> [(Point, Point)] {
        stride(from: 0, to: object.nodes.count, by: 2).map { (object.nodes[$0].point, object.nodes[$0 + 1].point) }
    }

    func testAMitreReachesThePointWithStitchesSquareToEachLeg() throws {
        let satin = try SatinLine.column(from: vee(60), width: 4)
        XCTAssertEqual(satin.settings.smartCorners, true, "New satin lines get smart corners")
        // The corner's pair runs along the seam, from the inside corner (above) to the point (below).
        let corner = try XCTUnwrap(SmartCorners.corners(pairs(satin), closed: false).first)
        let seam = pairs(satin)[corner], point = Point(0, -2 / sin(30 * Double.pi / 180))
        XCTAssertEqual(min(seam.0.distance(to: point), seam.1.distance(to: point)), 0, accuracy: 1e-6)
        let sewn = try stitches(satin)
        XCTAssertLessThan(sewn.map { $0.distance(to: point) }.min()!, 0.5, "The stitches reach the point")
        // Rounded, the point is cut off.
        let rounded = try SatinLine.column(from: vee(60), width: 4, smartCorners: false)
        XCTAssertGreaterThan(try stitches(rounded).map { $0.distance(to: point) }.min()!, 1)
        // Beside the corner, the left leg's stitches across the column stay square to the leg (no fan round the corner).
        let leg = Point(sin(30 * Double.pi / 180), -cos(30 * Double.pi / 180))   // down the left leg
        let across = zip(sewn, sewn.dropFirst()).filter { a, b in a.x < -0.3 && b.x < 0.3 && a.y < 3 && a.distance(to: b) > 1.5 && abs(b.y - a.y) < 3 }
        XCTAssertGreaterThan(across.count, 5)
        for (a, b) in across {
            let d = (b - a) * (1 / a.distance(to: b))
            XCTAssertLessThan(abs(d.x * leg.x + d.y * leg.y), 0.4, "Stitches beside a mitre stay nearly square to the leg (satin zigzags slant a little)")
        }
        // The left leg is sewn first, up to the point: it crosses the seam (x = 0) by no more than half the overlap plus
        // pull compensation.
        let tip = sewn.indices.min { sewn[$0].distance(to: point) < sewn[$1].distance(to: point) }!
        XCTAssertLessThan(sewn[..<tip].map(\.x).max()!, 0.7)
    }

    func testVerySharpCornersSewThatRoundingRefused() throws {
        XCTAssertThrowsError(try SatinLine.column(from: vee(30), width: 4, smartCorners: false), "Rounded, a 4 mm satin can't turn a 30° corner")
        let satin = try SatinLine.column(from: vee(30), width: 4)
        XCTAssertGreaterThan(try stitches(satin).count, 150)
        // Its cap would need stitches over 8 mm, so it's a mitre.
        let p = pairs(satin), c = try XCTUnwrap(SmartCorners.corners(p, closed: false).first)
        XCTAssertEqual(SmartCorners.corner(previous: p[c - 1], pair: p[c], next: p[c + 1], spacing: 0.4).kind, .mitre)
    }

    func testANarrowerVerySharpCornerGetsACap() throws {
        let satin = try SatinLine.column(from: vee(30), width: 3)
        let p = pairs(satin), c = try XCTUnwrap(SmartCorners.corners(p, closed: false).first)
        let corner = SmartCorners.corner(previous: p[c - 1], pair: p[c], next: p[c + 1], spacing: 0.4)
        XCTAssertEqual(corner.kind, .cap)
        XCTAssertLessThanOrEqual(corner.cap.map { $0.0.distance(to: $0.1) }.max()!, SmartCorners.capMaximum)
        let sewn = try stitches(satin)
        // The cap's stitches run straight across the corner (level here), right down near the point.
        let level = zip(sewn, sewn.dropFirst()).filter { a, b in a.y < -2 && abs(a.y - b.y) < 0.05 && a.distance(to: b) > 0.5 }
        XCTAssertGreaterThan(level.count, 5)
        XCTAssertLessThan(sewn.map { $0.distance(to: corner.outer) }.min()!, 0.6)
    }

    func testAHairpinBesideAShortLegIsRoundedNotRefused() throws {
        // Lines a stress test found: the inside corner would sit further along than the short leg reaches.
        for (points, width) in [([Point(0, 0), Point(-3.6, -4), Point(14.6, 15.8), Point(21.1, 20.6)], 6.0), ([Point(0, 0), Point(-17.7, -2.8), Point(-3.8, -0.6)], 3.0)] {
            let line = RunObject(name: "Hairpin", nodes: points.map { PathNode($0) })
            let rounded = try SatinLine.column(from: line, width: width, smartCorners: false)
            let smart = try SatinLine.column(from: line, width: width)
            XCTAssertGreaterThan(try stitches(smart).count, 20)
            XCTAssertEqual(try stitches(smart).count, try stitches(rounded).count, "That corner is rounded, as before")
        }
    }

    func testCornersOf75DegreesOrMoreStayRounded() throws {
        let smart = try SatinLine.column(from: vee(90), width: 4), plain = try SatinLine.column(from: vee(90), width: 4, smartCorners: false)
        XCTAssertEqual(smart.nodes, plain.nodes)
        XCTAssertEqual(try stitches(smart), try stitches(plain))
    }

    func testBordersMitreAndCapTheirPoints() throws {
        var triangle = RunObject(name: "Tri", nodes: [Point(-12, -8), Point(12, -8), Point(0, 14)].map { PathNode($0) })
        triangle.closed = true; triangle.digitizing = DigitizingSettings(kind: .fill)
        let border = try SatinBorder.around(triangle, width: 3, color: .palette[0]).object
        XCTAssertEqual(SmartCorners.corners(pairs(border), closed: true).count, 3)
        XCTAssertLessThan(try stitches(border).map { $0.distance(to: Point(0, 14 + 1.5 / sin(28.6 * Double.pi / 180))) }.min()!, 0.6, "Out to the top point")
        // A star: its 43° points are capped, its inside corners (115°) rounded.
        let star = (0..<10).map { k -> Point in let r = k % 2 == 0 ? 16.0 : 7.0, a = Double(k) * .pi / 5 + .pi / 2; return Point(r * cos(a), r * sin(a)) }
        var starShape = RunObject(name: "Star", nodes: star.map { PathNode($0) }); starShape.closed = true; starShape.digitizing = DigitizingSettings(kind: .fill)
        let starBorder = try SatinBorder.around(starShape, width: 3, color: .palette[0]).object
        let p = pairs(starBorder), found = SmartCorners.corners(p, closed: true)
        XCTAssertEqual(found.count, 5)
        for c in found { XCTAssertEqual(SmartCorners.corner(previous: p[(c + p.count - 1) % p.count], pair: p[c], next: p[(c + 1) % p.count], spacing: 0.4).kind, .cap) }
        XCTAssertGreaterThan(try stitches(starBorder).count, 400)
        // With a start point, and with a start and end point, the border still sews from there.
        var started = border; started.entry = Point(5, -8)
        XCTAssertLessThan(try stitches(started).first!.distance(to: Point(5, -8)), 3)
        started.exit = Point(-5, -8)
        XCTAssertGreaterThan(try stitches(started).count, 400)
    }

    func testTurningSmartCornersOnAndOffAndChangingTheWidth() throws {
        let rounded = try SatinLine.column(from: vee(60), width: 4, smartCorners: false)
        XCTAssertNil(rounded.settings.smartCorners)
        // Turning them on finds the corner the rounding hid.
        let sharp = try SatinLine.rebuilt(rounded, width: 4, smartCorners: true)
        let direct = try SatinLine.column(from: vee(60), width: 4)
        XCTAssertEqual(sharp.settings.smartCorners, true)
        XCTAssertEqual(SmartCorners.corners(pairs(sharp), closed: false).count, 1)
        let corner = pairs(direct)[SmartCorners.corners(pairs(direct), closed: false).first!]
        let found = pairs(sharp)[SmartCorners.corners(pairs(sharp), closed: false).first!]
        XCTAssertEqual(found.0.distance(to: corner.0), 0, accuracy: 0.05); XCTAssertEqual(found.1.distance(to: corner.1), 0, accuracy: 0.05)
        // An even-width satin with smart corners still has a width, and changing it keeps the corner sharp.
        XCTAssertEqual(try XCTUnwrap(SatinLine.evenWidth(of: sharp)), 4, accuracy: 0.05)
        let wider = try SatinLine.rewidth(sharp, to: 5)
        XCTAssertEqual(SmartCorners.corners(pairs(wider), closed: false).count, 1)
        XCTAssertEqual(try XCTUnwrap(SatinLine.evenWidth(of: wider)), 5, accuracy: 0.05)
        // Off again: rounded, and the same as never having had them.
        let off = try SatinLine.rebuilt(sharp, width: 4, smartCorners: false)
        XCTAssertNil(off.settings.smartCorners)
        XCTAssertTrue(SmartCorners.corners(pairs(off), closed: false).isEmpty)
        // A border, off and on again.
        var square = RunObject(name: "Diamond", nodes: [Point(0, -10), Point(6, 0), Point(0, 10), Point(-6, 0)].map { PathNode($0) })
        square.closed = true; square.digitizing = DigitizingSettings(kind: .fill)
        let border = try SatinBorder.around(square, width: 3, color: .palette[0]).object
        XCTAssertEqual(SmartCorners.corners(pairs(border), closed: true).count, 2, "The diamond's two 62° points; its 118° sides stay round")
        let roundedBorder = try SatinLine.rebuilt(border, width: 3, smartCorners: false)
        XCTAssertTrue(SmartCorners.corners(pairs(roundedBorder), closed: true).isEmpty)
        XCTAssertEqual(SmartCorners.corners(pairs(try SatinLine.rebuilt(roundedBorder, width: 3, smartCorners: true)), closed: true).count, 2)
    }

    func testOlderSatinsAndFilesAreUnchanged() throws {
        // A satin without the setting (as in older files) sews its corner pair fanned, as before, even along a seam.
        var satin = try SatinLine.column(from: vee(60), width: 4)
        let smart = try stitches(satin)
        satin.digitizing?.smartCorners = nil
        XCTAssertNotEqual(try stitches(satin), smart)
        var design = Design(); design.objects = [satin]
        XCTAssertFalse(design.needsSchemaTen)
        design.objects[0].digitizing?.smartCorners = true
        XCTAssertTrue(design.needsSchemaTen)
        design.schemaVersion = 10
        XCTAssertNoThrow(try design.validate())
        // A satin line with the setting but no sharp corner sews the same in older versions, so it doesn't need version 10.
        design.objects = [try SatinLine.column(from: vee(90), width: 4)]
        XCTAssertEqual(design.objects[0].settings.smartCorners, true)
        XCTAssertFalse(design.needsSchemaTen)
    }
}
