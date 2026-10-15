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

    func testFillStartsAndEndsAtTheChosenCorners() throws {
        var fill = RunObject(name: "Block", nodes: [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)].map { PathNode($0) })
        fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.angle = 0; fill.digitizing?.underlay = .none; fill.closed = true
        let plain = try AreaEngine.fill(fill).sections
        XCTAssertLessThan(plain[0].points[0].distance(to: Point(-10, -10)), 1.5)
        fill.entry = Point(10, 10); fill.exit = Point(-10, -10)
        let sections = try AreaEngine.fill(fill).sections
        XCTAssertLessThan(sections.first!.points.first!.distance(to: Point(10, 10)), 1.5)
        XCTAssertLessThan(sections.last!.points.last!.distance(to: Point(-10, -10)), 1.5)
        XCTAssertEqual(sections.map(\.points.count).reduce(0, +), plain.map(\.points.count).reduce(0, +), "Only the order changes, not the stitches")
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
