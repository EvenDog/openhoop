// Travel runs: sections of one object are joined by stitches inside the shape instead of trims and jumps.
import XCTest
@testable import EmbroideryCore

final class TravelTests: XCTestCase {
    private func fill(_ points: [Point], holes: [[Point]] = []) -> RunObject {
        var o = RunObject(name: "Fill", nodes: points.map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.angle = 0; o.digitizing?.expansion = 0; o.closed = true
        o.holes = holes.isEmpty ? nil : holes.map { $0.map { PathNode($0) } }
        return o
    }
    private func ops(_ object: RunObject) throws -> [StitchOperation] {
        var design = Design(); design.objects = [object]
        return try StitchEngine.compile(design).commands.map(\.op)
    }

    func testConcaveFillSewsWithoutTrims() throws {
        // A "U" with 6 mm arms: rows split into two arms, which used to need a trim between them. The run back from
        // the top of the left arm to the bottom of the right one is about 32 mm. (Past 40 mm over sewn fill, a
        // larger U gets a trim there instead.)
        let u = fill([Point(0, 0), Point(22, 0), Point(22, 20), Point(16, 20), Point(16, 10), Point(6, 10), Point(6, 20), Point(0, 20)])
        let result = try AreaEngine.fill(u)
        XCTAssertGreaterThan(result.sections.count, 2)
        XCTAssertTrue(result.sections.dropFirst().allSatisfy(\.joined))
        XCTAssertFalse(result.warnings.contains { $0.contains("trim") })
        let commands = try ops(u)
        XCTAssertEqual(commands.filter { $0 == .trim }.count, 1, "Only the trim after the object")
        XCTAssertEqual(commands.filter { $0 == .jump }.count, 1, "Only the jump to the object's start")
        // Every stitch, travel included, stays inside the U and is a sensible length.
        let ring = AreaGeometry.ring(u.nodes)
        for section in result.sections { for (a, b) in zip(section.points, section.points.dropFirst()) {
            XCTAssertTrue(AreaGeometry.segmentInside(a, b, rings: [ring]), "\(a) -> \(b)")
            XCTAssertLessThanOrEqual(a.distance(to: b), 3.0001)
        } }
    }

    func testSectionsAreReorderedToShortenTravel() throws {
        // Rows sewn left to right at 0, 70 and 35 mm along a strip: in row order the needle runs 60 mm to the second
        // and 45 mm back to the third, both over the 40 mm limit, so both need trims. Reordered it goes 0 → 35 → 70
        // with 25 mm runs.
        let strip = [Point(0, 0), Point(100, 0), Point(100, 10), Point(0, 10)]
        let router = try XCTUnwrap(TravelRouter(edges: [strip], bounds: [strip]))
        func section(_ x: Double) -> StitchSection { StitchSection([Point(x, 5), Point(x + 10, 5)]) }
        let sections = [section(0), section(70), section(35)]
        XCTAssertEqual(router.join(sections).filter { !$0.joined }.count, 3, "Row order: two trims (plus the first section)")
        let ordered = router.ordered(sections, keepingLast: false)
        XCTAssertEqual(ordered.map { $0.points.map(\.x).min()! }, [0, 35, 70])
        XCTAssertEqual(ordered[0].points, sections[0].points, "The first section stays first")
        XCTAssertEqual(router.join(ordered).filter { !$0.joined }.count, 1, "No trims after reordering")
        XCTAssertEqual(router.ordered(sections, keepingLast: true).last!.points, sections[2].points, "An end point keeps the last section last")
    }

    func testTravelGoesAroundHoles() throws {
        let outline = [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)], hole = [Point(10, 8), Point(30, 8), Point(30, 22), Point(10, 22)]
        let router = try XCTUnwrap(TravelRouter(edges: [outline, hole], bounds: [outline, hole]))
        let path = try XCTUnwrap(router.route(from: Point(5, 15), to: Point(35, 15)))
        for (a, b) in zip(path, path.dropFirst()) { XCTAssertTrue(AreaGeometry.segmentInside(a, b, rings: [outline, hole])) }
        XCTAssertGreaterThan(AreaGeometry.pathLength(path), 30, "It can't go straight through the hole")
        XCTAssertEqual(path.first, Point(5, 15)); XCTAssertEqual(path.last, Point(35, 15))
    }

    /// A router remembers what each route end can see (it's asked about the same section ends many times). Routes it
    /// has partly worked out before come out exactly as a brand-new router finds them.
    func testRememberedSightLinesGiveTheSameRoutes() throws {
        let outline = [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)], hole = [Point(10, 8), Point(30, 8), Point(30, 22), Point(10, 22)]
        let used = try XCTUnwrap(TravelRouter(edges: [outline, hole], bounds: [outline, hole]))
        let ends = [Point(5, 15), Point(35, 15), Point(20, 3), Point(20, 27), Point(2, 2)]
        for a in ends { for b in ends { _ = used.route(from: a, to: b) } }   // every end is now remembered
        for a in ends { for b in ends {
            let fresh = try XCTUnwrap(TravelRouter(edges: [outline, hole], bounds: [outline, hole]))
            XCTAssertEqual(used.route(from: a, to: b), fresh.route(from: a, to: b))
        } }
    }

    func testVisibleTravelIsLimitedButCoveredTravelMayBeLonger() throws {
        let strip = [Point(0, 0), Point(200, 0), Point(200, 10), Point(0, 10)]
        let router = try XCTUnwrap(TravelRouter(edges: [strip], bounds: [strip]))
        let first = StitchSection([Point(1, 5), Point(2, 5)]), far = StitchSection([Point(150, 5), Point(151, 5)])
        XCTAssertFalse(router.join([first, far]).last!.joined, "A 148 mm run over sewn fill would show; trim instead")
        var underlay = first; underlay.underlay = true
        let joined = router.join([underlay, far])
        XCTAssertTrue(joined.last!.joined, "Before the top layer the run is covered, so it is sewn")
        XCTAssertTrue(joined.dropFirst().allSatisfy { zip($0.points, $0.points.dropFirst()).allSatisfy { $0.distance(to: $1) <= 2.5 } })
        // Travel between two underlay passes doesn't count as top layer: the run to the top layer is still covered.
        var secondUnderlay = StitchSection([Point(60, 5), Point(61, 5)]); secondUnderlay.underlay = true
        XCTAssertTrue(router.join([underlay, secondUnderlay, far]).last!.joined, "The top layer still covers this run")
    }

    func testSatinTravelsBackAfterItsUnderlay() throws {
        let satin = Design.stitchSampler().objects[1]
        let sections = try AreaEngine.satin(satin).sections
        XCTAssertTrue(sections.first!.underlay)
        XCTAssertTrue(sections.dropFirst().allSatisfy(\.joined), "Underlay, travel back and top sew as one run")
        XCTAssertEqual(try ops(satin).filter { $0 == .trim }.count, 1)
    }

    func testLetteringSewsWithoutTrims() throws {
        for letter in try Lettering.shapes(text: "BEAKS", fontName: "Helvetica-Bold", height: 15, stitch: .fill, color: ThreadColor.palette[0]).objects {
            XCTAssertEqual(try ops(letter).filter { $0 == .trim }.count, 1, letter.name)
        }
    }
}
