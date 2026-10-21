// Cutting out overlaps: a fill leaves out what's sewn on top of it (tucking 1 mm under the edge), only when asked.
import XCTest
@testable import EmbroideryCore

final class OverlapCutoutTests: XCTestCase {
    private func square(_ name: String, center: Point, size: Double, cut: Bool = false) -> RunObject {
        let h = size / 2
        var o = RunObject(name: name, nodes: [Point(-h, -h), Point(h, -h), Point(h, h), Point(-h, h)].map { PathNode(center + $0) })
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.cutOutOverlaps = cut ? true : nil
        return o
    }
    private func bar(width: Double) -> RunObject {
        // A satin bar across the middle, 50 mm long.
        var o = RunObject(name: "Bar", nodes: [Point(-25, width / 2), Point(-25, -width / 2), Point(25, width / 2), Point(25, -width / 2)].map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: .satin)
        return o
    }

    func testCoveredMiddleBecomesAHoleTuckedUnderTheEdge() throws {
        let base = square("Base", center: Point(0, 0), size: 40, cut: true), top = square("Top", center: Point(0, 0), size: 20)
        let pieces = try XCTUnwrap(OverlapCutout.pieces(of: base, under: [top]))
        XCTAssertEqual(pieces.count, 1); XCTAssertEqual(pieces[0].count, 2, "The covered middle becomes a hole")
        let hole = pieces[0][1]
        XCTAssertEqual(hole.map(\.x).max()! - hole.map(\.x).min()!, 18, accuracy: 0.05, "The fill tucks 1 mm under each edge")
    }

    /// A shape on top cuts the fill in two. The start and end points each stay on the piece they were put on, so the
    /// fill starts and ends exactly on them, whichever piece the cut happens to list first.
    func testStartAndEndPointsStayOnTheirPieces() throws {
        var top = square("Top", center: Point(0, 0), size: 6); top.nodes = [Point(-3, -8), Point(3, -8), Point(3, 8), Point(-3, 8)].map { PathNode($0) }
        for (entry, exit) in [(Point(15, 0), Point(-15, 0)), (Point(-15, 0), Point(15, 0)), (Point(15, 2), Point(15, -2)), (Point(30, 0), Point(-30, 0))] {
            var base = square("Base", center: Point(0, 0), size: 40, cut: true)
            base.nodes = [Point(-20, -5), Point(20, -5), Point(20, 5), Point(-20, 5)].map { PathNode($0) }
            base.entry = entry; base.exit = exit
            let sections = try XCTUnwrap(OverlapCutout.fill(base, under: [top])).sections
            // Points off the fill land just inside its edge (0.25 mm in).
            func inside(_ p: Point) -> Point { Point(min(max(p.x, -19.75), 19.75), p.y) }
            XCTAssertEqual(sections.first!.points.first!.distance(to: inside(entry)), 0, accuracy: 0.01, "starts on the start point: \(entry)")
            // Both points on the right piece: the right piece sews first, so the end goes to the left piece's nearest edge.
            let end = entry.x > 0 && exit.x > 0 ? Point(-2.25, exit.y) : inside(exit)
            XCTAssertEqual(sections.last!.points.last!.distance(to: end), 0, accuracy: 0.01, "ends on the end point: \(exit)")
        }
    }

    func testStitchesStayOutOfTheCoveredAreaOnlyWhenAsked() throws {
        var design = Design(); design.objects = [square("Base", center: Point(0, 0), size: 40, cut: true), square("Top", center: Point(0, 0), size: 20)]
        let cutPlan = try StitchEngine.compile(design)
        design.objects[0].digitizing?.cutOutOverlaps = nil
        let wholePlan = try StitchEngine.compile(design)
        let baseID = design.objects[0].id
        func baseStitches(_ plan: StitchPlan) -> [Point] { plan.commands.filter { $0.objectID == baseID && $0.op == .stitch }.map(\.point) }
        XCTAssertLessThan(baseStitches(cutPlan).count, baseStitches(wholePlan).count)
        XCTAssertFalse(baseStitches(cutPlan).contains { abs($0.x) < 8 && abs($0.y) < 8 }, "Nothing sews well inside the top shape")
        XCTAssertTrue(baseStitches(wholePlan).contains { abs($0.x) < 8 && abs($0.y) < 8 })
    }

    func testOnlyShapesSewnOnTopCount() throws {
        let base = square("Base", center: Point(0, 0), size: 40, cut: true)
        XCTAssertNil(try OverlapCutout.pieces(of: base, under: [square("Elsewhere", center: Point(60, 0), size: 10)]), "No overlap: sews as drawn")
        var design = Design(); design.objects = [square("Under", center: Point(0, 0), size: 20), base]
        let plan = try StitchEngine.compile(design)
        XCTAssertTrue(plan.commands.contains { $0.objectID == base.id && $0.op == .stitch && abs($0.point.x) < 5 && abs($0.point.y) < 5 }, "A shape sewn before doesn't cut it")
    }

    func testSatinAcrossSplitsTheFillAndThinOnesDont() throws {
        let base = square("Base", center: Point(0, 0), size: 40, cut: true)
        XCTAssertEqual(try OverlapCutout.pieces(of: base, under: [bar(width: 6)])?.count, 2)
        XCTAssertNil(try OverlapCutout.pieces(of: base, under: [bar(width: 1.5)]), "A column thinner than the tuck covers nothing")
    }

    func testFullyCoveredFillDoesntSew() throws {
        var design = Design(); design.objects = [square("Base", center: Point(0, 0), size: 10, cut: true), square("Top", center: Point(0, 0), size: 20)]
        let plan = try StitchEngine.compile(design)
        XCTAssertFalse(plan.commands.contains { $0.objectID == design.objects[0].id && $0.op == .stitch })
        XCTAssertTrue(plan.warnings.contains { $0.contains("completely covered") }, "\(plan.warnings)")
    }

    func testTheSettingSavesAndNeedsTheNewerFile() throws {
        var design = Design(); design.objects = [square("Base", center: Point(0, 0), size: 40, cut: true)]
        XCTAssertTrue(design.needsSchemaFive)
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design)).objects[0].settings.cutOutOverlaps, true)
        XCTAssertNil(DigitizingSettings(kind: .fill).cutOutOverlaps, "Off unless switched on")
    }

    func testRemoveOverlapsFindsFillsWithSomethingOnTop() {
        // Base has Top sewn over it; Top has nothing after it; Apart is sewn last but touches nothing.
        let base = square("Base", center: Point(0, 0), size: 40), top = square("Top", center: Point(0, 0), size: 20)
        var lockedBase = square("Locked", center: Point(0, 0), size: 40); lockedBase.locked = true
        let apart = square("Apart", center: Point(60, 0), size: 10)
        var design = Design(); design.objects = [base, lockedBase, top, apart]
        let all = Set(design.objects.map(\.id))
        XCTAssertEqual(design.fillsWithOverlaps(among: all), [base.id], "locked fills and fills with nothing on top are left out")
        XCTAssertEqual(design.fillsWithOverlaps(among: [top.id, apart.id]), [])
        // Only shapes sewn after a fill count: with Top sewn first, nothing covers Base.
        design.objects = [top, base]
        XCTAssertEqual(design.fillsWithOverlaps(among: all), [top.id])
    }
}
