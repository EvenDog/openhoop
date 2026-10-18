// Satin fill: stitches straight across a closed shape from edge to edge at the fill angle, zigzagging back and forth.
// Wide parts are split at steps measured from each stitch's left end, so no piece is longer than the split length.
import XCTest
@testable import EmbroideryCore

final class SatinFillTests: XCTestCase {
    /// An ellipse `width` × `height` mm as a satin fill without underlay, its stitches running across (angle 0).
    private func ellipse(_ width: Double, _ height: Double) -> RunObject {
        var object = RunObject(name: "Leaf", nodes: (0..<72).map { i in
            let a = Double(i) * .pi / 36
            return PathNode(Point(width / 2 * cos(a), height / 2 * sin(a)))
        })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        object.digitizing?.fillStyle = .satin; object.digitizing?.angle = 0; object.digitizing?.underlay = .none
        object.digitizing?.expansion = 0
        return object
    }
    private func stitches(_ object: RunObject) throws -> [(Point, Point)] {
        try AreaEngine.fill(object).sections.flatMap { section in zip(section.points, section.points.dropFirst()).map { ($0, $1) } }
    }

    func testNarrowShapeSewsWholeStitchesEdgeToEdge() throws {
        let narrow = ellipse(6, 20)
        let sewn = try stitches(narrow)
        // Nearly every stitch crosses the shape: about two per row (0.4 mm apart over 20 mm), none split.
        XCTAssertGreaterThan(sewn.count, 80)
        let ring = AreaGeometry.ring(narrow.nodes)
        for (a, b) in sewn {
            XCTAssertLessThanOrEqual(a.distance(to: b), 6.01)
            XCTAssertTrue(AreaGeometry.segmentInside(a, b, rings: [try AreaGeometry.offset([ring], by: 0.05)[0]]), "every stitch stays inside")
        }
        // The middle stitches reach from one edge to the other.
        XCTAssertGreaterThan(sewn.map { $0.0.distance(to: $0.1) }.max()!, 5.9)
    }

    func testWideShapeIsSplitFromTheLeftEdge() throws {
        let wide = ellipse(46, 70)
        let sewn = try stitches(wide)
        let longest = sewn.map { $0.0.distance(to: $0.1) }.max()!
        XCTAssertLessThanOrEqual(longest, DigitizingSettings.defaultSatinSplit + 0.001, "no piece longer than the split length")
        XCTAssertGreaterThan(sewn.map { $0.0.distance(to: $0.1) }.min()!, 0.3)
        // Across the middle row (y ≈ 0), the breaks sit 5.5 mm apart (± 0.3 mm) starting from the left edge at -23 mm.
        let middle = sewn.flatMap { [$0.0, $0.1] }.filter { abs($0.y) < 0.25 }.map(\.x).sorted()
        XCTAssertTrue(middle.contains { abs($0 - (-23 + 5.5)) <= 0.31 }, "a break 5.5 mm in from the left edge")
        XCTAssertTrue(middle.contains { abs($0 - (-23 + 11)) <= 0.31 }, "and the next 5.5 mm further on")
    }

    func testWithoutAutoSplitAWideShapeIsRefused() {
        var wide = ellipse(20, 30)
        wide.digitizing?.autoSplit = false
        XCTAssertThrowsError(try AreaEngine.fill(wide))
        wide.digitizing?.satinSplit = 10; wide.digitizing?.autoSplit = nil
        XCTAssertNoThrow(try AreaEngine.fill(wide), "on again (nil counts as on)")
    }

    func testAUShapeNeverStitchesAcrossItsGap() throws {
        // A U: two 6 mm arms joined at the bottom, with a 10 mm gap between them.
        var u = RunObject(name: "U", nodes: [Point(0, 0), Point(22, 0), Point(22, 30), Point(16, 30), Point(16, 6), Point(6, 6), Point(6, 30), Point(0, 30)].map { PathNode($0) })
        u.closed = true; u.digitizing = DigitizingSettings(kind: .fill)
        u.digitizing?.fillStyle = .satin; u.digitizing?.angle = 0; u.digitizing?.underlay = .none; u.digitizing?.expansion = 0
        let inside = try AreaGeometry.offset([AreaGeometry.ring(u.nodes)], by: 0.05)
        // Travel between sections included, no stitch crosses the gap. (Like tatami, the second arm is reached by a
        // trim and jump: no path inside the U joins the top of one arm to the bottom of the other.)
        let plan = try StitchEngine.compile({ var d = Design(); d.objects = [u]; return d }())
        for (a, b) in zip(plan.commands, plan.commands.dropFirst()) where a.op == .stitch && b.op == .stitch && a.point.distance(to: b.point) > 0.01 {
            XCTAssertTrue(AreaGeometry.segmentInside(a.point, b.point, rings: inside), "\(a.point) → \(b.point) leaves the U")
        }
    }

    func testSatinFillsSaveAndOlderFillsStillOpen() throws {
        let saved = try JSONEncoder().encode(ellipse(6, 20))
        XCTAssertEqual(try JSONDecoder().decode(RunObject.self, from: saved).settings.fillStyle, .satin)
        var design = Design(); design.objects = [ellipse(6, 20)]
        XCTAssertTrue(design.needsSchemaSix, "older versions can't read the new style")
        XCTAssertFalse(FillStyle.satin.usesStitchLength)
    }
}
