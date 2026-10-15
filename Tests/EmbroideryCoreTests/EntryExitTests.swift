// Start (entry) and end (exit) points: the stitch engine reorders running, satin and fill stitches to match them.
import XCTest
@testable import EmbroideryCore

final class EntryExitTests: XCTestCase {
    private func line() -> RunObject { RunObject(name: "Line", nodes: [Point(0, 0), Point(10, 0), Point(20, 0)].map { PathNode($0) }) }

    func testOpenRunningPathStartsAtTheNearerEnd() throws {
        var object = line()
        XCTAssertEqual(try RunningEngine.stitches(for: object.sewingOrder()).first, Point(0, 0))
        object.entry = Point(19, 1)
        let stitches = try RunningEngine.stitches(for: object.sewingOrder())
        XCTAssertEqual(stitches.first, Point(20, 0)); XCTAssertEqual(stitches.last, Point(0, 0))
    }

    func testClosedOutlineStartsAtTheNearestPointOnTheLine() throws {
        var square = RunObject(name: "Square", nodes: [Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)].map { PathNode($0) })
        square.closed = true
        for (entry, start) in [(Point(9, 11), Point(9, 10)), (Point(5, -1), Point(5, 0)), (Point(10.2, 10.3), Point(10, 10))] {
            square.entry = entry
            let stitches = try RunningEngine.stitches(for: square.sewingOrder())
            XCTAssertEqual(stitches.first!.distance(to: start), 0, accuracy: 0.2, "entry \(entry)")
            XCTAssertEqual(stitches.last!.distance(to: start), 0, accuracy: 0.2, "closed outlines finish where they start")
            // Every original corner is still sewn.
            for corner in square.nodes.map(\.point) { XCTAssertTrue(stitches.contains(corner)) }
        }
        XCTAssertEqual(square.nodes.count, 4, "The object's own nodes are never changed")
    }

    func testCurvedOutlineSplitKeepsItsShape() throws {
        var circle = try SVGImporter.load(Data("<svg xmlns='http://www.w3.org/2000/svg' width='40mm' height='40mm' viewBox='0 0 40 40'><circle cx='20' cy='20' r='15' fill='none' stroke='black'/></svg>".utf8)).objects[0]
        circle.digitizing = nil; circle.entry = Point(10, 12)
        let ordered = circle.sewingOrder()
        XCTAssertEqual(ordered.nodes.count, 5, "One node added where sewing starts")
        XCTAssertEqual(ordered.nodes[0].point.distance(to: Point(10, 12) * (15 / hypot(10, 12))), 0, accuracy: 0.3)
        for p in RunningEngine.flatten(ordered.nodes, closed: true).flatMap({ $0 }) { XCTAssertEqual(hypot(p.x, p.y), 15, accuracy: 0.03) }
    }

    func testSatinSewsFromTheEndNearestTheStart() throws {
        var satin = Design.stitchSampler().objects[1]   // the "Satin ribbon", drawn from x = -25 to x = 25
        XCTAssertLessThan(try AreaEngine.satin(satin.sewingOrder()).sections[0].points[0].x, 0)
        satin.entry = Point(26, 35)
        XCTAssertGreaterThan(try AreaEngine.satin(satin.sewingOrder()).sections[0].points[0].x, 20)
        // An edge-run underlay starts at that end too, not wherever its outline happens to begin.
        satin.digitizing?.underlay = .edge
        XCTAssertGreaterThan(try AreaEngine.satin(satin.sewingOrder()).sections[0].points[0].x, 20)
        satin.entry = nil
        XCTAssertLessThan(try AreaEngine.satin(satin.sewingOrder()).sections[0].points[0].x, -20)
    }

    /// A fill's first stitch is exactly on its start point and its last exactly on its end point. A point outside the
    /// shape (or in a hole) moves to the nearest place just inside its edge. The fill is sewn toward the end point,
    /// so its last row passes right beside it and the final step to it doesn't cross the finished fill.
    func testFillStartsAndEndsExactlyAtItsPoints() throws {
        for underlay in [UnderlayStyle.none, .edge] {
            for (entry, exit) in [(Point(0, 0), Point(9, 9)), (Point(-9, 5), Point(9, -5)), (Point(3, -9), Point(-3, 9)), (Point(-5, 0), Point(0, 0)), (Point(30, 0), Point(0, -40))] {
                var fill = RunObject(name: "Block", nodes: [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)].map { PathNode($0) })
                fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.angle = 0; fill.digitizing?.underlay = underlay; fill.closed = true
                fill.entry = entry; fill.exit = exit
                // Points outside the 20 mm square land just inside its edge (0.25 mm in).
                func inside(_ p: Point) -> Point { Point(min(max(p.x, -9.75), 9.75), min(max(p.y, -9.75), 9.75)) }
                let sections = try AreaEngine.fill(fill).sections
                let label = "underlay \(underlay), entry \(entry), exit \(exit)"
                XCTAssertEqual(sections.first!.points.first!.distance(to: inside(entry)), 0, accuracy: 0.01, "starts on the start point: \(label)")
                XCTAssertEqual(sections.last!.points.last!.distance(to: inside(exit)), 0, accuracy: 0.01, "ends on the end point: \(label)")
                // The last step to the end point runs along the last row (rows are level here, at angle 0), within a row
                // spacing of the end point's height, so it doesn't cross the finished fill.
                let lastStep = try XCTUnwrap(sections.last)
                XCTAssertTrue(lastStep.joined, label)
                XCTAssertLessThanOrEqual(lastStep.points.map { abs($0.y - inside(exit).y) }.max()!, fill.settings.spacing + 0.01, "the last step runs beside the last row: \(label)")
                XCTAssertGreaterThan(try RunningEngine.compile({ var d = Design(); d.objects = [fill]; return d }()).stitchCount, 0)
            }
        }
    }

    func testPointsMoveWithTheObjectSaveAsSchemaFiveAndValidate() throws {
        var object = line(); object.entry = Point(2, 3); object.exit = Point(4, 5)
        object.transform { Point(-$0.x, $0.y) }
        XCTAssertEqual(object.entry, Point(-2, 3)); XCTAssertEqual(object.exit, Point(-4, 5))
        var design = Design(); design.objects = [line()]
        XCTAssertFalse(design.needsSchemaFive)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(design), as: UTF8.self).contains("entry"), "Unset points are not saved")
        design.objects[0].exit = Point(1, 1)
        XCTAssertTrue(design.needsSchemaFive)
        design.objects[0].entry = Point(.nan, 0)
        XCTAssertThrowsError(try design.validate())
    }
}

final class AutoStartTests: XCTestCase {
    func testAutoStartPointsShortenTravel() throws {
        var design = Design()
        // Line A ends at x = 30; line B is drawn from far left to near A's end, so it should be sewn backwards.
        design.objects = [RunObject(name: "A", nodes: [Point(0, 0), Point(30, 0)].map { PathNode($0) }),
                          RunObject(name: "B", nodes: [Point(-30, 10), Point(28, 10)].map { PathNode($0) })]
        let before = StitchEngine.travelLength(try StitchEngine.compile(design))
        let optimized = try StitchEngine.autoStartPoints(design)
        XCTAssertNil(optimized.objects[0].entry, "The first object keeps its own start")
        XCTAssertEqual(optimized.objects[1].entry, Point(30, 0))
        let after = StitchEngine.travelLength(try StitchEngine.compile(optimized))
        XCTAssertLessThan(after, before)
        XCTAssertEqual(after, hypot(2, 10), accuracy: 0.01)
    }

    func testLockedAndUnstitchedObjectsAreLeftAlone() throws {
        var design = Design.sample()
        design.objects[1].locked = true
        let optimized = try StitchEngine.autoStartPoints(design)
        XCTAssertNil(optimized.objects[1].entry)
        XCTAssertNotNil(optimized.objects[2].entry)
    }
}
