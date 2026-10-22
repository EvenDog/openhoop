// Checks multi-hooping: which hooping sews each object (letters, groups and branches stay whole), Auto Layout,
// the alignment marks both hoopings sew, and the stitch plan each hooping gets, shifted into its own hoop.
import XCTest
@testable import EmbroideryCore

final class MultiHoopingTests: XCTestCase {
    private func square(_ name: String, at center: Point, size: Double = 10) -> RunObject {
        let h = size / 2
        var object = RunObject(name: name, nodes: [Point(-h, -h), Point(h, -h), Point(h, h), Point(-h, h)].map { PathNode(center + $0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    /// A 100 mm hoop with two hoopings side by side, overlapping by 16 mm (from x = -8 to 8).
    private func twoHoopings(_ objects: [RunObject]) -> Design {
        var design = Design()
        design.objects = objects
        design.multiHooping = MultiHooping(hoopings: [Hooping(center: Point(-42, 0)), Hooping(center: Point(42, 0))])
        return design
    }

    func testEachObjectSewsInTheFirstHoopingThatHoldsAllOfIt() throws {
        let left = square("Left", at: Point(-60, 0)), right = square("Right", at: Point(60, 0)), middle = square("Middle", at: Point(0, 0))
        var long = RunObject(name: "Long line", nodes: [Point(-70, -30), Point(70, -30)].map { PathNode($0) })
        long.stitchLength = 3
        let design = twoHoopings([left, right, middle, long])
        let assignment = design.hoopingAssignment(plan: try StitchEngine.compile(design))
        XCTAssertEqual(assignment.objects, [[left.id, middle.id], [right.id]], "the middle fits both, so it goes to the first")
        XCTAssertEqual(assignment.unplaced, [long.id], "140 mm fits no 100 mm hooping")
        // Stitches closer than half a millimeter to a hooping's edge don't count as inside it.
        let atTheEdge = square("At the edge", at: Point(-42, 47), size: 5.6)
        let edged = twoHoopings([atTheEdge])
        XCTAssertEqual(edged.hoopingAssignment(plan: try StitchEngine.compile(edged)).unplaced, [atTheEdge.id])
        XCTAssertThrowsError(try design.hoopingPlans(plan: try StitchEngine.compile(design)), "nothing is saved while an object fits no hooping")
    }

    func testLettersGroupsAndBranchesStayWhole() throws {
        var a = square("A", at: Point(-60, 0)), b = square("B", at: Point(0, 0)), c = square("C", at: Point(30, 0)), d = square("D", at: Point(50, 0))
        a.groupID = UUID(); b.groupID = a.groupID
        c.branchID = UUID(); d.branchID = c.branchID
        let units = twoHoopings([a, b, c, d]).hoopingUnits
        XCTAssertEqual(units, [[a.id, b.id], [c.id, d.id]])

        // A word crosses the hoopings, but each letter's parts sew in one of them.
        var spec = LetteringSpec(text: "OpenHoop", fontKind: .embroidery, font: "venezia", height: 26)
        spec.anchor = Point(0, 2); spec.alongMarker = Point(10, 2); spec.upMarker = Point(0, 12)
        let letters = try spec.build(color: ThreadColor.palette[0], embroideryFonts: EmbroideryFont.all(in: EmbroideryFontTests.directory)).objects
        let design = twoHoopings(letters)
        let assignment = design.hoopingAssignment(plan: try StitchEngine.compile(design))
        XCTAssertEqual(assignment.unplaced, [])
        XCTAssertTrue(assignment.objects.allSatisfy { !$0.isEmpty }, "the word is split between the two hoopings")
        let hoopingOf = Dictionary(uniqueKeysWithValues: assignment.objects.enumerated().flatMap { index, ids in ids.map { ($0, index) } })
        for (key, parts) in Dictionary(grouping: letters, by: { $0.letterKey }) {
            XCTAssertEqual(Set(parts.map { hoopingOf[$0.id] }).count, 1, "letter \(String(describing: key)) is split between hoopings")
        }
    }

    func testAutoLayoutCoversTheDesignWithOverlappingHoopings() throws {
        var design = twoHoopings([square("Left", at: Point(-80, 0)), square("Right", at: Point(80, 0))])
        let wide = design.autoHoopings(plan: try StitchEngine.compile(design))
        XCTAssertEqual(wide.count, 2)
        XCTAssertEqual(wide[0].center.y, wide[1].center.y, accuracy: 0.001, "one row")
        XCTAssertLessThan(wide[0].center.x, wide[1].center.x, "left to right")
        XCTAssertGreaterThanOrEqual(design.hoop.width - (wide[1].center.x - wide[0].center.x), Design.hoopingOverlap)
        // The design's outermost stitches stay clear of the edges, so the machine files never round past them.
        let stitches = try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point)
        XCTAssertEqual(stitches.map(\.x).max()! + Design.hoopingLayoutMargin, wide[1].center.x + design.hoop.width / 2, accuracy: 0.001)
        design.multiHooping!.hoopings = wide
        XCTAssertNoThrow(try design.hoopingPlans(plan: try StitchEngine.compile(design)))

        design.objects = [square("Small", at: Point(5, 5))]
        let small = design.autoHoopings(plan: try StitchEngine.compile(design))
        XCTAssertEqual(small.count, 1)
        XCTAssertEqual(small[0].center.x, 5, accuracy: 0.5, "centered on the design")
    }

    func testEachHoopingGetsItsOwnPlanWithSharedAlignmentMarks() throws {
        let left = square("Left", at: Point(-60, 0)), right = square("Right", at: Point(60, 0))
        let design = twoHoopings([left, right])
        let plans = try design.hoopingPlans(plan: try StitchEngine.compile(design))
        XCTAssertEqual(plans.count, 2)
        for plan in plans { XCTAssertTrue(plan.outsidePoints.allSatisfy { design.hoop.contains($0) }, "every stitch fits the hoop") }
        let first = plans[0].commands.filter { $0.op == .stitch }, second = plans[1].commands.filter { $0.op == .stitch }
        XCTAssertTrue(first.contains { $0.objectID == left.id } && !first.contains { $0.objectID == right.id })
        XCTAssertTrue(second.contains { $0.objectID == right.id } && !second.contains { $0.objectID == left.id })

        // Hooping 1 ends with the marks; hooping 2 starts with them, then stops so they can be checked.
        let marksAfterLeft = first.drop { $0.objectID != left.id }.drop { $0.objectID == left.id }
        XCTAssertFalse(marksAfterLeft.isEmpty, "hooping 1 sews marks after its design")
        let marksBeforeRight = second.prefix { $0.objectID != right.id }
        XCTAssertFalse(marksBeforeRight.isEmpty, "hooping 2 sews marks before its design")
        let stop = try XCTUnwrap(plans[1].commands.firstIndex { $0.op == .stop }, "a stop after the marks")
        XCTAssertLessThan(stop, try XCTUnwrap(plans[1].commands.firstIndex { $0.objectID == right.id }))
        // Both hoopings sew the marks at the same place on the fabric (each plan is shifted by its own center).
        let markStitchesOne = Set(marksAfterLeft.map { roundedKey($0.point + Point(-42, 0)) })
        let markStitchesTwo = Set(marksBeforeRight.map { roundedKey($0.point + Point(42, 0)) })
        XCTAssertEqual(markStitchesOne, markStitchesTwo)
        XCTAssertTrue(marksBeforeRight.allSatisfy { abs($0.point.x + 42) <= 8.01 }, "the marks sit where the hoopings overlap")
        // The first stitch is a mark's middle, so stepping the machine to it shows where to line up.
        let spots = design.alignmentMarkSpots(between: design.multiHooping!.hoopings[0], and: design.multiHooping!.hoopings[1],
                                              avoiding: try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point))
        XCTAssertEqual(marksBeforeRight.first!.point.distance(to: spots[0] - Point(42, 0)), 0, accuracy: 0.01)

        var noMarks = design
        noMarks.multiHooping!.marks = nil
        let plain = try noMarks.hoopingPlans(plan: try StitchEngine.compile(noMarks))
        XCTAssertFalse(plain[1].commands.contains { $0.op == .stop }, "no marks, no stop")
        XCTAssertEqual(plain[1].commands.first { $0.op == .stitch }?.objectID, right.id)
    }

    private func roundedKey(_ p: Point) -> Point { Point((p.x * 100).rounded() / 100, (p.y * 100).rounded() / 100) }

    func testAlignmentMarksMoveClearOfTheDesign() throws {
        // A fill sits over the bottom end of the overlap, so the bottom mark moves up out of its way.
        let design = twoHoopings([square("Over the seam", at: Point(0, -42), size: 12), square("Left", at: Point(-60, 0)), square("Right", at: Point(60, 0))])
        let plan = try StitchEngine.compile(design)
        let stitches = plan.commands.filter { $0.op == .stitch }.map(\.point)
        let hoopings = design.multiHooping!.hoopings
        let spots = design.alignmentMarkSpots(between: hoopings[0], and: hoopings[1], avoiding: stitches)
        XCTAssertEqual(spots.count, 2)
        for spot in spots {
            XCTAssertTrue(stitches.allSatisfy { $0.distance(to: spot) >= Design.markClearance }, "\(spot) is on top of stitches")
            XCTAssertTrue(design.hoop.contains(spot - hoopings[0].center) && design.hoop.contains(spot - hoopings[1].center))
        }
        XCTAssertGreaterThan(abs(spots[0].y - spots[1].y), 50, "the two marks are far apart, so turning shows too")
    }

    func testAMiddleHoopingSewsMarksAtBothEndsAndTheWorksheetNamesThem() throws {
        var design = twoHoopings([square("Left", at: Point(-100, 0)), square("Middle", at: Point(0, 0)), square("Right", at: Point(100, 0))])
        design.multiHooping!.hoopings = [Hooping(center: Point(-84, 0)), Hooping(center: Point(0, 0)), Hooping(center: Point(84, 0))]
        let plans = try design.hoopingPlans(plan: try StitchEngine.compile(design))   // compiling checks every object's ID is its own
        XCTAssertEqual(plans.count, 3)
        let middle = plans[1].commands.filter { $0.op == .stitch }
        XCTAssertTrue(Design.isAlignmentMark(try XCTUnwrap(middle.first?.objectID)), "starts with the marks shared with hooping 1")
        XCTAssertTrue(Design.isAlignmentMark(try XCTUnwrap(middle.last?.objectID)), "ends with the marks for hooping 3")
        XCTAssertFalse(Design.isAlignmentMark(design.objects[0].id))
        let steps = ProductionSummary(plan: plans[1], design: design).steps
        XCTAssertEqual(steps.first?.parts, ["Alignment marks"])
        XCTAssertEqual(steps.first?.stopAfter, true, "the machine stops so the marks can be checked")
    }

    func testAWarningWhenAHoopingPutsAnObjectOnTop() throws {
        // Over sews before Under in the list, but Under fits hooping 1, so it now sews first, beneath Over.
        let over = square("Over", at: Point(10, 0)), under = square("Under", at: Point(2, 0), size: 8)
        let design = twoHoopings([over, under])
        let assignment = design.hoopingAssignment(plan: try StitchEngine.compile(design))
        XCTAssertEqual(assignment.objects, [[under.id], [over.id]])
        XCTAssertEqual(assignment.warnings, ["Over now sews on top of Under, because it's in a later hooping."])
    }

    func testMultiHoopedDesignsAreSavedAsVersionSeven() throws {
        var design = twoHoopings([square("Left", at: Point(-60, 0))])
        XCTAssertTrue(design.needsSchemaSeven)
        design.schemaVersion = 7
        XCTAssertNoThrow(try design.validate())
        let decoded = try JSONDecoder().decode(Design.self, from: try JSONEncoder().encode(design))
        XCTAssertEqual(decoded.multiHooping, design.multiHooping)
        design.multiHooping!.hoopings[0].center = Point(.infinity, 0)
        XCTAssertThrowsError(try design.validate())
        XCTAssertFalse(Design().needsSchemaSeven)
    }
}
