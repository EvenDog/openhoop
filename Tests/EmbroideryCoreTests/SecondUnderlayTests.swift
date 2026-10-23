// Underlay 1 and 2: satins and fills can have two underlay layers, such as a satin's center run followed by a
// zigzag, or a fill's edge run followed by tatami rows. They sew in that order, before the top stitches, each with
// its own inset, spacing, stitch length and (tatami) angle.
import XCTest
@testable import EmbroideryCore

final class SecondUnderlayTests: XCTestCase {
    /// A straight satin column 4 mm wide and 30 mm long, centered on the x axis.
    private func column(_ first: UnderlayStyle, _ second: UnderlayStyle?) -> RunObject {
        var o = RunObject(name: "Column", nodes: [Point(-15, 2), Point(-15, -2), Point(15, 2), Point(15, -2)].map { PathNode($0) })
        var s = DigitizingSettings(kind: .satin); s.underlay = first; s.secondUnderlay = second; o.digitizing = s
        return o
    }

    func testSatinSewsFirstUnderlayThenSecondThenTop() throws {
        let sections = try AreaEngine.satin(column(.center, .zigzag)).sections
        let under = sections.filter(\.underlay)
        guard under.count == 2 else { return XCTFail("Expected two underlay layers, got \(under.count)") }
        XCTAssertTrue(under[0].points.allSatisfy { abs($0.y) < 0.01 }, "The center run comes first")
        XCTAssertLessThan(under[1].points.map(\.y).min()!, -1, "Then the zigzag, which crosses the column")
        XCTAssertGreaterThan(under[1].points.map(\.y).max()!, 1)
        // The center run goes along the column; the zigzag comes back, ending where the top stitches begin.
        XCTAssertGreaterThan(under[0].points.last!.x, 13); XCTAssertGreaterThan(under[1].points.first!.x, 13)
        XCTAssertLessThan(under[1].points.last!.x, -13)
        XCTAssertFalse(sections.last!.underlay, "The top stitches come last")
        // Without a second underlay, only the first one sews.
        XCTAssertEqual(try AreaEngine.satin(column(.center, nil)).sections.filter(\.underlay).count, 1)
    }

    func testSecondUnderlayClearsWhenTheFirstIsOffOrTheSame() {
        var s = DigitizingSettings(kind: .satin)
        s.underlay = .center; s.secondUnderlay = .zigzag
        s.underlay = .edge
        XCTAssertEqual(s.secondUnderlay, .zigzag, "A different first underlay keeps the second")
        s.underlay = .zigzag
        XCTAssertNil(s.secondUnderlay, "The same style twice would just sew it again")
        s.secondUnderlay = .center
        s.underlay = .none
        XCTAssertNil(s.secondUnderlay, "No first underlay, no second (so U turns all underlay off)")
    }

    /// A 30 × 20 mm rectangle fill.
    private func patch(_ first: UnderlayStyle, _ second: UnderlayStyle?) -> RunObject {
        var o = RunObject(name: "Patch", nodes: [Point(0, 0), Point(30, 0), Point(30, 20), Point(0, 20)].map { PathNode($0) })
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.underlay = first; o.digitizing?.secondUnderlay = second
        return o
    }

    func testEachKindAcceptsItsOwnUnderlayTypes() throws {
        var design = Design(); design.objects = [column(.edge, .zigzag), patch(.edge, .tatami), patch(.tatami, .edge), patch(.tatami, nil)]
        XCTAssertNoThrow(try design.validate())
        // Types a satin can't sew, the same type twice, or a second without a first.
        for (first, second) in [(UnderlayStyle.edge, UnderlayStyle.edgeAndSparse), (.edge, .tatami), (.tatami, nil), (.zigzag, .zigzag), (.none, .center)] {
            var object = column(.center, nil); object.digitizing?.underlay = first; object.digitizing?.secondUnderlay = second
            design.objects = [object]
            XCTAssertThrowsError(try design.validate(), "satin \(first) then \(second.map { "\($0)" } ?? "nothing")")
        }
        // And the same for fills, which sew only edge runs and tatami rows (and Edge + sparse, in older files, alone).
        for (first, second) in [(UnderlayStyle.edge, UnderlayStyle.zigzag), (.center, nil), (.edge, .edge), (.none, .tatami), (.edgeAndSparse, .tatami)] {
            var object = patch(.edge, nil); object.digitizing?.underlay = first; object.digitizing?.secondUnderlay = second
            design.objects = [object]
            XCTAssertThrowsError(try design.validate(), "fill \(first) then \(second.map { "\($0)" } ?? "nothing")")
        }
        // Each layer's own numbers stay within what Properties offers.
        for change in [{ (s: inout DigitizingSettings) in s.secondInset = 4 }, { $0.secondSpacing = 0.1 }, { $0.underlayLength = 20 }, { $0.secondLength = 0.1 }, { $0.underlayAngle = 400 }] {
            var object = patch(.edge, .tatami); change(&object.digitizing!)
            design.objects = [object]
            XCTAssertThrowsError(try design.validate())
        }
    }

    func testEachLayerShowsOnlyTheSettingsItUses() {
        XCTAssertEqual([UnderlayStyle.center, .edge, .zigzag, .doubleZigzag, .tatami, .auto].map(\.usesInset), [false, true, true, true, true, true])
        XCTAssertEqual([UnderlayStyle.center, .edge, .zigzag, .doubleZigzag, .tatami, .auto].map(\.usesSpacing), [false, false, true, true, true, true])
        XCTAssertEqual([UnderlayStyle.center, .edge, .zigzag, .doubleZigzag, .tatami, .auto].map(\.usesLength), [true, true, false, false, true, false])
        XCTAssertEqual([UnderlayStyle.center, .edge, .zigzag, .doubleZigzag, .tatami, .auto].map(\.usesAngle), [false, false, false, false, true, false])
    }

    /// The underlay stitches of `object`, in sewing order.
    private func underlayPoints(_ object: RunObject) throws -> [Point] { try AreaEngine.fill(object).sections.filter(\.underlay).flatMap(\.points) }
    /// True for a point on the patch's outline 0.4 mm in (where its edge run sews).
    private func onInsetEdge(_ p: Point) -> Bool { [p.x - 0.4, 29.6 - p.x, p.y - 0.4, 19.6 - p.y].contains { abs($0) < 0.01 } }

    func testFillsSewAnEdgeRunThenTatamiRows() throws {
        let both = try underlayPoints(patch(.edge, .tatami))
        XCTAssertTrue(both.prefix(30).allSatisfy(onInsetEdge), "The edge run goes round first")
        XCTAssertFalse(both.suffix(30).allSatisfy(onInsetEdge), "Then the tatami rows cross the shape")
        // The other way round: rows first, then the outline.
        let rowsFirst = try underlayPoints(patch(.tatami, .edge))
        XCTAssertFalse(rowsFirst.prefix(30).allSatisfy(onInsetEdge)); XCTAssertTrue(rowsFirst.suffix(30).allSatisfy(onInsetEdge))
        XCTAssertLessThan(try underlayPoints(patch(.tatami, nil)).count, both.count, "No outline without an edge run")
    }

    func testEachLayerSewsWithItsOwnNumbers() throws {
        // Changing Underlay 1's inset moves only Underlay 1's stitches.
        var satin = column(.edge, .zigzag), wider = satin; wider.digitizing?.setUnderlay(1, inset: 1)
        var a = try AreaEngine.satin(satin).sections.filter(\.underlay), b = try AreaEngine.satin(wider).sections.filter(\.underlay)
        XCTAssertNotEqual(a[0].points, b[0].points); XCTAssertEqual(a[1].points, b[1].points)
        // And Underlay 2's spacing only Underlay 2's.
        wider = satin; wider.digitizing?.setUnderlay(2, spacing: 3)
        b = try AreaEngine.satin(wider).sections.filter(\.underlay)
        XCTAssertEqual(a[0].points, b[0].points); XCTAssertNotEqual(a[1].points, b[1].points)
        // A fill's tatami rows turn with their own angle, measured from the fill's.
        // (Its rows' stitches are the long ones: the steps between rows are only the spacing, 1.2 mm.)
        var fill = patch(.edge, .tatami); fill.digitizing?.angle = 0
        func rowStitches() throws -> [(Point, Point)] { let rows = try AreaEngine.fill(fill).sections.filter(\.underlay)[1].points; return zip(rows, rows.dropFirst()).filter { $0.distance(to: $1) > 1.3 } }
        XCTAssertTrue(try rowStitches().allSatisfy { abs($0.x - $1.x) < 0.01 }, "90° from a 0° fill: up and down")
        fill.digitizing?.setUnderlay(2, angle: 0)
        XCTAssertTrue(try rowStitches().allSatisfy { abs($0.y - $1.y) < 0.01 }, "0° from a 0° fill: along it")
        // The stitch length sets how long the edge run's stitches are.
        fill.digitizing?.setUnderlay(1, length: 1)
        let ring = try AreaEngine.fill(fill).sections[0].points
        XCTAssertLessThanOrEqual(zip(ring, ring.dropFirst()).map { $0.distance(to: $1) }.max()!, 1.0001)
    }

    func testNewLayersStartWithUnderlayOnesNumbersButKeepTheirOwn() {
        var s = DigitizingSettings(kind: .satin); s.underlay = .edge; s.inset = 0.7; s.underlaySpacing = 2
        s.secondUnderlay = .zigzag
        XCTAssertEqual(s.underlayLayer(2)?.inset, 0.7); XCTAssertEqual(s.underlayLayer(2)?.spacing, 2)
        s.inset = 0.2; s.underlaySpacing = 1
        XCTAssertEqual(s.underlayLayer(2)?.inset, 0.7, "Underlay 2's numbers are its own once it's chosen")
        s.secondLength = 3; s.secondUnderlay = .center
        XCTAssertNil(s.secondLength, "A new type starts with its own stitch length")
        XCTAssertEqual(s.underlayLayer(2)?.stitchLength, 2, "A center run's starts at its spacing, as it always sewed")
    }

    func testOlderFilesOpenSewingAsBefore() throws {
        // A fill's Edge + sparse becomes an edge run then tatami rows, with the same numbers.
        var old = patch(.edge, nil); old.digitizing?.underlay = .edgeAndSparse; old.digitizing?.inset = 0.8; old.digitizing?.underlaySpacing = 2
        // A satin's second underlay, before it had numbers of its own, shared Underlay 1's.
        var satin = column(.center, .zigzag); satin.digitizing?.secondInset = nil; satin.digitizing?.secondSpacing = nil; satin.digitizing?.inset = 0.6
        var design = Design(); design.objects = [old, satin]
        let before = try StitchEngine.compile(design)
        design.splitEdgeAndSparse()
        XCTAssertEqual(design.objects[0].settings.underlay, .edge); XCTAssertEqual(design.objects[0].settings.secondUnderlay, .tatami)
        XCTAssertEqual(design.objects[0].settings.underlayLayer(2)?.inset, 0.8); XCTAssertEqual(design.objects[0].settings.underlayLayer(2)?.spacing, 2)
        XCTAssertEqual(design.objects[1].settings.secondInset, 0.6)
        XCTAssertEqual(try StitchEngine.compile(design).commands, before.commands)
        XCTAssertNoThrow(try design.validate())
    }

    func testDoubleZigzagGoesDownTheColumnAndBackCrossingItself() throws {
        let single = try AreaEngine.satin(column(.zigzag, nil)).sections.filter(\.underlay)[0].points
        let double = try AreaEngine.satin(column(.doubleZigzag, nil)).sections.filter(\.underlay)[0].points
        XCTAssertLessThan(double.first!.x, -13); XCTAssertGreaterThan(double.map(\.x).max()!, 13)
        XCTAssertLessThan(double.last!.x, -13, "It comes back to where the top stitches begin")
        XCTAssertEqual(Array(double.prefix(single.count)), single, "Its first pass is the zigzag")
        // The way back touches each rung at its other end, so every rung's two ends both get a needle point.
        let left = double.filter { $0.y > 1 }.map { ($0.x * 10).rounded() }, right = double.filter { $0.y < -1 }.map { ($0.x * 10).rounded() }
        XCTAssertEqual(Set(left), Set(right), "Both edges at every rung: the passes cross in X's")
        // As Underlay 2 after a center run (which ends at the far end), it starts and finishes there.
        let after = try AreaEngine.satin(column(.center, .doubleZigzag)).sections.filter(\.underlay)
        XCTAssertGreaterThan(after[1].points.first!.x, 13); XCTAssertGreaterThan(after[1].points.last!.x, 13)
    }

    func testFillsCanCrossTwoTatamiUnderlays() throws {
        var fill = patch(.tatami, .tatami); fill.digitizing?.angle = 0
        XCTAssertEqual(fill.settings.secondUnderlay, .tatami, "Tatami twice is allowed on fills")
        XCTAssertEqual(fill.settings.underlayLayer(1)?.angle, 90); XCTAssertEqual(fill.settings.underlayLayer(2)?.angle, 0, "Square to Underlay 1")
        var design = Design(); design.objects = [fill]
        XCTAssertNoThrow(try design.validate()); XCTAssertTrue(design.needsSchemaEight)
        // Its stitches run both ways: up and down (Underlay 1), then along the fill (Underlay 2).
        let points = try underlayPoints(fill), long = zip(points, points.dropFirst()).filter { $0.distance(to: $1) > 1.3 }
        XCTAssertTrue(long.contains { abs($0.x - $1.x) < 0.01 }); XCTAssertTrue(long.contains { abs($0.y - $1.y) < 0.01 })
        // Making Underlay 1 tatami under a tatami Underlay 2 crosses them too, from Underlay 1's own angle.
        var s = DigitizingSettings(kind: .fill); s.underlayAngle = 60; s.underlay = .tatami
        XCTAssertEqual(s.secondUnderlay, .tatami); XCTAssertEqual(s.secondAngle, -30)
        // Satins still refuse the same type twice.
        var satin = DigitizingSettings(kind: .satin); satin.underlay = .doubleZigzag; satin.secondUnderlay = .zigzag
        satin.underlay = .zigzag
        XCTAssertNil(satin.secondUnderlay)
    }

    func testOlderVersionsRefuseFilesWithTheirOwnUnderlayNumbers() {
        var design = Design(); design.objects = [column(.center, .zigzag)]
        XCTAssertFalse(design.needsSchemaEight, "Two satin layers sharing their numbers sew the same in version 7")
        design.objects[0].digitizing?.setUnderlay(2, spacing: 3)
        XCTAssertTrue(design.needsSchemaEight)
        design.objects = [column(.edge, nil)]; design.objects[0].digitizing?.setUnderlay(1, length: 3)
        XCTAssertTrue(design.needsSchemaEight)
        design.objects = [patch(.edge, nil)]
        XCTAssertFalse(design.needsSchemaEight, "An edge run alone sews the same")
        design.objects = [patch(.edge, .tatami)]
        XCTAssertTrue(design.needsSchemaEight, "Version 7 can't read a fill's Underlay 2")
        design.objects = [column(.doubleZigzag, nil)]
        XCTAssertTrue(design.needsSchemaEight, "Version 7 can't read a double zigzag")
    }

    func testOlderVersionsRefuseFilesWithASecondUnderlay() throws {
        var design = Design(); design.objects = [column(.center, .zigzag)]
        design.objects[0].digitizing?.shortStitches = nil; design.objects[0].digitizing?.autoSplit = nil; design.objects[0].digitizing?.pullPercent = nil
        XCTAssertTrue(design.needsSchemaFive, "An older version would sew only the first underlay")
        design.objects[0].digitizing?.secondUnderlay = nil
        XCTAssertFalse(design.needsSchemaFive)
        let old = try JSONDecoder().decode(DigitizingSettings.self, from: Data(#"{"kind":"satin","spacing":0.4,"expansion":0.2,"angle":45,"maximumSatin":10,"underlay":"center","inset":0.4,"underlaySpacing":1.2}"#.utf8))
        XCTAssertNil(old.secondUnderlay, "Files saved before the second underlay open with none")
    }
}
