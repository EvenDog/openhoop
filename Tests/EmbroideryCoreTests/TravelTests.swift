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
        // A "U" with 6 mm arms: rows split into two arms, which used to need a trim between them. One arm is sewn
        // there and back (the needle travels up it while it's bare, then sews it back down over that run), then the
        // other arm, so no travel crosses sewn rows.
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

    /// Sections where two branches join (an L: the bar and the top of the upright meet the rest past the inside
    /// corner): the needle sews the bar, travels out through the bare top of the upright, sews it back to the
    /// corner, then carries on. Nothing is left to reach later over sewn rows.
    func testSweepSewsTheBranchThatJoinsThereAndBack() {
        let bar = [Point(0, 0), Point(1, 0)], top = [Point(0, 5), Point(1, 5)], rest = [Point(0, 9), Point(1, 9)]
        let swept = AreaEngine.sweepOrder([bar, top, rest], links: [(0, 2), (1, 2)], lastRows: [10, 10, 20])
        XCTAssertEqual(swept.rows, [bar, top, rest], "the top of the upright is sewn toward the corner, before the rest")
        XCTAssertEqual(swept.covered, [1], "reached by travel through itself")
    }

    /// Where the shape splits (a U's arms), the arm that doesn't lead on is sewn there and back: travel up it,
    /// sew it back down, then up the other arm.
    func testSweepSewsTheBranchThatSplitsOffThereAndBack() {
        let base = [Point(0, 0), Point(1, 0)], left = [Point(0, 5), Point(0, 6)], right = [Point(9, 5), Point(9, 6)]
        let swept = AreaEngine.sweepOrder([base, left, right], links: [(0, 1), (0, 2)], lastRows: [4, 10, 12])
        XCTAssertEqual(swept.rows, [base, left.reversed(), right], "the left arm sewn from its far end back to the base")
        XCTAssertEqual(swept.covered, [1])
    }

    /// Round a hole the rows split and join again. The side that rejoins isn't sewn there and back from the split
    /// (that would end the fill back at the split); the needle goes up one side and sews the other there and back
    /// from where they join, then carries on to the last row.
    func testSweepAroundAHoleFinishesAtTheLastRow() {
        let below = [Point(0, 0), Point(1, 0)], left = [Point(0, 5), Point(0, 6)], right = [Point(9, 5), Point(9, 6)], above = [Point(0, 9), Point(1, 9)]
        let swept = AreaEngine.sweepOrder([below, left, right, above], links: [(0, 1), (0, 2), (1, 3), (2, 3)], lastRows: [4, 8, 8, 12])
        XCTAssertEqual(swept.rows.first, below)
        XCTAssertEqual(swept.rows.last, above, "it finishes at the last row")
        XCTAssertEqual(Set(swept.rows.dropFirst().dropLast().map { $0.map(\.x) }), [[0, 0], [9, 9]], "both sides sewn once each")
        XCTAssertEqual(swept.covered.count, 1, "one side reached by travel through itself")
    }

    /// A real L-shaped fill at 45°, whose rows meet the inside corner: every travel run in its top layer ends up
    /// under rows sewn after it (none left on top, as a run up the outside edge over sewn rows once was).
    func testTravelInAnLShapedFillIsAllCovered() throws {
        let l = fill([Point(0, -16), Point(10, -16), Point(10, 0), Point(50, 0), Point(50, 6), Point(0, 6)])   // rows past the corner cross the notch
        var object = l; object.digitizing?.angle = 45; object.digitizing?.underlay = UnderlayStyle.none
        let sections = try AreaEngine.fill(object).sections
        XCTAssertTrue(sections.dropFirst().allSatisfy(\.joined), "no trims")
        // Travel runs are the stitches that don't lie along the rows (45°); each must have rows sewn over it later.
        let stitches = sections.flatMap { zip($0.points, $0.points.dropFirst()).map { ($0, $1) } }
        func distance(_ p: Point, _ a: Point, _ b: Point) -> Double {
            let d = b - a, t = max(0, min(1, ((p - a).x * d.x + (p - a).y * d.y) / max(1e-12, d.x * d.x + d.y * d.y)))
            return p.distance(to: a + d * t)
        }
        var shown = 0.0
        for (index, stitch) in stitches.enumerated() {
            let d = stitch.1 - stitch.0, angle = abs(atan2(d.y, d.x) * 180 / .pi).truncatingRemainder(dividingBy: 180)
            guard abs(angle - 45) > 10 else { continue }   // a row
            let middle = (stitch.0 + stitch.1) * 0.5
            if !stitches[(index + 1)...].contains(where: { distance(middle, $0.0, $0.1) < 0.25 }) { shown += stitch.0.distance(to: stitch.1) }
        }
        XCTAssertLessThan(shown, 3, "travel left on top: \(shown) mm")
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

    func testQuickInsideTestAgreesWithTheFullOne() throws {
        // Routing asks "is this inside?" through InsideTest, which only looks at edges near the question. It must
        // answer exactly as AreaGeometry does, including for points on or a hair off the edge and lines along it.
        let comb = [Point(0, 0), Point(40, 0), Point(40, 30), Point(30, 30), Point(30, 10), Point(25, 10), Point(25, 30),
                    Point(15, 30), Point(15, 10), Point(10, 10), Point(10, 30), Point(0, 30)]
        let hole = [Point(3, 3), Point(37, 3), Point(37, 6), Point(3, 6)]
        let shapes = [[comb, hole], try AreaGeometry.offset([comb, hole], by: 0.01), [comb, [Point(1, 1), Point(2, 2)]]]
        for rings in shapes {
            let quick = InsideTest(rings)
            var points = rings.flatMap { $0 }
            for ring in rings { for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count], middle = (a + b) * 0.5
                points += [middle, middle + Point(0.000004, 0.000004), middle + Point(0.00002, -0.00002), a + Point(0, 0.0005)]
            } }
            for x in stride(from: -2.0, through: 42, by: 2.75) { for y in stride(from: -2.0, through: 32, by: 2.5) { points.append(Point(x, y)) } }
            for p in points { XCTAssertEqual(quick.contains(p), AreaGeometry.contains(p, rings: rings), "\(p)") }
            for (i, a) in points.enumerated() where i % 3 == 0 { for (j, b) in points.enumerated() where j % 7 == 1 {
                XCTAssertEqual(quick.segmentInside(a, b), AreaGeometry.segmentInside(a, b, rings: rings), "\(a) -> \(b)")
            } }
        }
    }
}
