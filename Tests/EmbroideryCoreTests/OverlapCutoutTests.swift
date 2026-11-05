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

    /// A fill leaves out only the shapes it recorded (what was on top when cutting out was switched on): a shape added
    /// on top of it later doesn't cut it. A fill that recorded nothing (made in code) still cuts out everything after it.
    func testOnlyTheRecordedShapesOnTopCutTheFill() throws {
        var base = square("Base", center: Point(0, 0), size: 40, cut: true)
        let top = square("Top", center: Point(0, 0), size: 20), later = square("Later", center: Point(14.5, -14.5), size: 9)
        base.digitizing?.overlapCutters = [top.id]
        var design = Design(); design.objects = [base, top, later]
        XCTAssertEqual(design.overlapsOnTop(of: base.id), [top.id, later.id], "both cover part of it now")
        /// True when Base has a stitch within 2 mm of `point` (well inside a cut, where no edge stitch reaches).
        func sewsNear(_ point: Point, _ design: Design) throws -> Bool {
            try StitchEngine.compile(design).commands.contains { $0.objectID == base.id && $0.op == .stitch && abs($0.point.x - point.x) < 2 && abs($0.point.y - point.y) < 2 }
        }
        XCTAssertFalse(try sewsNear(Point(0, 0), design), "the recorded shape cuts it")
        XCTAssertTrue(try sewsNear(Point(14.5, -14.5), design), "the shape added later doesn't")
        design.objects[0].digitizing?.overlapCutters = nil
        XCTAssertFalse(try sewsNear(Point(14.5, -14.5), design), "recording nothing: everything sewn after cuts it")
    }

    /// Projects from before fills recorded their shapes on top are brought up to date when opened: each cutting fill
    /// records what overlaps it now, so it sews the same. Recording needs file version 18. A copied fill is cut by the
    /// copies of its shapes, and forgets the ones not copied with it.
    func testOlderProjectsRecordWhatsOnTopAndCopiesFollow() throws {
        let base = square("Base", center: Point(0, 0), size: 40, cut: true), top = square("Top", center: Point(0, 0), size: 20)
        let apart = square("Apart", center: Point(60, 0), size: 10)
        var design = Design(); design.objects = [base, top, apart]
        XCTAssertFalse(design.needsSchemaEighteen)
        let before = try StitchEngine.compile(design)
        design.recordOverlapCutters()
        XCTAssertEqual(design.objects[0].settings.overlapCutters, [top.id], "only what overlaps it")
        XCTAssertNil(design.objects[1].settings.overlapCutters, "fills that don't cut out record nothing")
        XCTAssertEqual(try StitchEngine.compile(design).commands, before.commands, "it sews exactly as before")
        XCTAssertTrue(design.needsSchemaEighteen)
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design)).objects[0].settings.overlapCutters, [top.id])

        let baseCopy = UUID(), topCopy = UUID()
        var copied = design.objects[0]; copied.id = baseCopy
        var copiedTop = design.objects[1]; copiedTop.id = topCopy
        design.objects += [copied, copiedTop]
        design.relinkCopiedGuides([base.id: baseCopy, top.id: topCopy])
        XCTAssertEqual(design.objects[3].settings.overlapCutters, [topCopy], "the copy is cut by the copied shape")
        design.relinkCopiedGuides([base.id: baseCopy])   // as if the fill was copied alone
        XCTAssertEqual(design.objects[3].settings.overlapCutters, [], "shapes not copied with it are forgotten")
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
