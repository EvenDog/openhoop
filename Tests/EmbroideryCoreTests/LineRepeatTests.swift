// Checks copies along a line: where the copies sit and which way they face, that reshaping the guide (or changing a
// setting) builds them again from the first copy while moving everything together doesn't, what pasting and
// deleting do to the link, the sewing order, and the file checks.
import XCTest
@testable import EmbroideryCore

final class LineRepeatTests: XCTestCase {
    /// A 4 mm wide, 2 mm tall filled rectangle centered on `center`, stitched at angle 0.
    func tile(_ center: Point = Point(0, 20), color: ThreadColor = ThreadColor.palette[0]) -> RunObject {
        var o = RunObject(name: "Tile", nodes: [Point(-2, -1), Point(2, -1), Point(2, 1), Point(-2, 1)].map { PathNode(center + $0) }, color: color)
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.angle = 0
        return o
    }
    /// An open running line through `points`.
    func line(_ points: [Point]) -> RunObject {
        var o = RunObject(name: "Line", nodes: points.map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: .run)
        return o
    }
    /// A design with a tile and a 40 mm line along the x axis, made into `copies` copies along the line.
    func repeated(_ copies: Int = 5, _ setup: (inout LineRepeat) -> Void = { _ in }) throws -> (design: Design, id: UUID) {
        let tile = tile(), line = line([Point(0, 0), Point(40, 0)])
        var design = Design(); design.objects = [tile, line]
        let id = try design.repeatAlongLine([tile.id, line.id], line: line.id, copies: copies)
        design.setLineRepeat(id, setup)
        design.syncGuides()
        return (design, id)
    }
    func copies(_ design: Design) -> [RunObject] { design.objects.filter { $0.repeatCopy != nil } }
    func box(_ design: Design, _ object: RunObject) -> (min: Point, max: Point) { design.bounds(of: [object.id])! }
    func middle(_ design: Design, _ object: RunObject) -> Point { let b = box(design, object); return (b.min + b.max) * 0.5 }

    func testCopiesSitEvenlyAlongTheLineFromEndToEnd() throws {
        let (design, id) = try repeated()
        let made = copies(design)
        XCTAssertEqual(made.count, 5)
        for (k, copy) in made.enumerated() {
            XCTAssertEqual(middle(design, copy).x, Double(k) * 10, accuracy: 0.001)
            XCTAssertEqual(middle(design, copy).y, 0, accuracy: 0.001, "centered on the line")
            XCTAssertEqual(copy.name, "Tile \(k + 1)")
        }
        let guide = try XCTUnwrap(design.objects.first { $0.lineRepeat != nil })
        XCTAssertEqual(guide.kind, .vector, "the line no longer sews")
        XCTAssertEqual(guide.guideFor, id)
        XCTAssertEqual(Set(design.objects.map(\.groupID)).count, 1, "copies and guide are one group")
        XCTAssertNotNil(design.objects.first?.groupID)
        XCTAssertTrue(design.needsSchemaSixteen)
        XCTAssertNoThrow(try RunningEngine.compile(design))
    }

    func testOneCopySitsInTheMiddle() throws {
        let (design, _) = try repeated(1)
        XCTAssertEqual(middle(design, copies(design)[0]).x, 20, accuracy: 0.001)
    }

    func testCopiesTurnWithTheLineUnlessToldNotTo() throws {
        let tile = tile(), up = line([Point(0, 0), Point(0, 40)])
        var design = Design(); design.objects = [tile, up]
        try design.repeatAlongLine([tile.id, up.id], line: up.id, copies: 3)
        // Up the line, the 4 × 2 tile turns to stand 2 wide and 4 tall, and its rows turn with it.
        let turned = copies(design)[1], b = box(design, turned)
        XCTAssertEqual(b.max.x - b.min.x, 2, accuracy: 0.001); XCTAssertEqual(b.max.y - b.min.y, 4, accuracy: 0.001)
        XCTAssertEqual(abs(turned.settings.angle), 90, accuracy: 0.001)
        let id = turned.repeatCopy!.id
        design.setLineRepeat(id) { $0.turnsWithLine = false }; design.syncGuides()
        let upright = copies(design)[1], c = box(design, upright)
        XCTAssertEqual(c.max.x - c.min.x, 4, accuracy: 0.001)
        XCTAssertEqual(upright.settings.angle, 0, accuracy: 0.001)
    }

    func testAboveBelowAlternateAndMirrored() throws {
        let above = try repeated(3) { $0.placement = .above }
        XCTAssertTrue(copies(above.design).allSatisfy { abs(box(above.design, $0).min.y) < 0.001 }, "resting on the line")
        let below = try repeated(3) { $0.placement = .below }
        XCTAssertTrue(copies(below.design).allSatisfy { abs(box(below.design, $0).max.y) < 0.001 }, "hanging from it")
        let alternate = try repeated(3) { $0.placement = .alternate; $0.mirrorsEveryOther = true }
        let sides = copies(alternate.design).map { middle(alternate.design, $0).y }
        XCTAssertEqual(sides[0], 1, accuracy: 0.001); XCTAssertEqual(sides[1], -1, accuracy: 0.001); XCTAssertEqual(sides[2], 1, accuracy: 0.001)
        // The mirrored copy's markers face the other way: its up points down.
        let mirrored = copies(alternate.design)[1].repeatCopy!
        XCTAssertLessThan(mirrored.up.y, mirrored.anchor.y)
    }

    func testReshapingTheLineMovesTheCopies() throws {
        var (design, _) = try repeated(3)
        let g = design.objects.firstIndex { $0.lineRepeat != nil }!
        design.objects[g].nodes[1] = PathNode(Point(40, 40))   // the line now climbs at 45°
        design.syncGuides()
        let made = copies(design)
        XCTAssertEqual(made.count, 3)
        XCTAssertEqual(middle(design, made[2]).x, 40, accuracy: 0.001); XCTAssertEqual(middle(design, made[2]).y, 40, accuracy: 0.001)
        XCTAssertEqual(made[1].settings.angle, 45, accuracy: 0.001, "rows turn with the line")
    }

    /// A spacing fills the line end to end with as many copies as fit (the gap rounded to fit), keeps doing so when
    /// the line is reshaped, and typing a number of copies goes back to that number.
    func testSpacingFillsTheLineWithAsManyCopiesAsFit() throws {
        var (design, id) = try repeated(5) { $0.spacing = 4 }
        var made = copies(design)
        XCTAssertEqual(made.count, 11, "40 mm at 4 mm apart, end to end")
        XCTAssertEqual(middle(design, made[0]).x, 0, accuracy: 0.001); XCTAssertEqual(middle(design, made[10]).x, 40, accuracy: 0.001)
        XCTAssertEqual(design.repeatSpacing(id)!, 4, accuracy: 0.001)
        XCTAssertEqual(design.objects.first { $0.lineRepeat != nil }?.lineRepeat?.copies, 11, "saved too, for older versions")
        // 6 mm doesn't divide 40: 40 / 6 rounds to 7 gaps, so 8 copies about 5.7 mm apart, still end to end.
        design.setLineRepeat(id) { $0.spacing = 6 }; design.syncGuides()
        made = copies(design)
        XCTAssertEqual(made.count, 8)
        XCTAssertEqual(middle(design, made[7]).x, 40, accuracy: 0.001)
        // Stretch the line to 80 mm: 80 / 6 rounds to 13 gaps at the same spacing, so 14 copies.
        let g = design.objects.firstIndex { $0.lineRepeat != nil }!
        design.objects[g].nodes[1] = PathNode(Point(80, 0)); design.syncGuides()
        XCTAssertEqual(copies(design).count, 14)
        // Typing Copies goes back to a fixed number.
        design.setLineRepeat(id) { $0.copies = 3; $0.spacing = nil }; design.syncGuides()
        XCTAssertEqual(copies(design).count, 3)
        XCTAssertEqual(design.repeatSpacing(id)!, 40, accuracy: 0.001)
        // Very close copies stop at 200.
        XCTAssertEqual(LineRepeat.copiesFitting(length: 1000, spacing: 2), 200)
        var bad = design; bad.setLineRepeat(id) { $0.spacing = 0.5 }
        XCTAssertThrowsError(try bad.validate(), "spacing is 2–50 mm")
    }

    func testMovingEverythingTogetherBuildsNothingAgain() throws {
        var (design, _) = try repeated(3)
        let before = design.objects.map(\.id)
        for i in design.objects.indices { design.objects[i].transform { $0 + Point(5, 7) } }
        design.syncGuides()
        XCTAssertEqual(design.objects.map(\.id), before, "the same objects, just moved")
    }

    func testChangesToTheFirstCopyCarryOverWhenBuiltAgain() throws {
        var (design, id) = try repeated(3)
        let red = ThreadColor.palette[1]
        let first = design.objects.firstIndex { $0.repeatCopy?.index == 0 }!
        design.objects[first].color = red
        design.objects[first].transform { Point($0.x * 2, $0.y) }   // stretched to twice as wide (8 × 2)
        design.setLineRepeat(id) { $0.copies = 4 }; design.syncGuides()
        let made = copies(design)
        XCTAssertEqual(made.count, 4)
        XCTAssertTrue(made.allSatisfy { $0.color == red })
        XCTAssertTrue(made.allSatisfy { let b = box(design, $0); return abs(b.max.x - b.min.x - 8) < 0.001 })
        XCTAssertEqual(middle(design, made[0]).x, 0, accuracy: 0.001, "still from end to end")
    }

    func testDeletingTheGuideOrAllTheCopiesUnlinksTheRest() throws {
        var noGuide = try repeated(3).design
        noGuide.objects.removeAll { $0.lineRepeat != nil }; noGuide.syncGuides()
        XCTAssertTrue(noGuide.objects.allSatisfy { $0.repeatCopy == nil }, "ordinary objects now")
        XCTAssertEqual(noGuide.objects.count, 3)
        var noCopies = try repeated(3).design
        noCopies.objects.removeAll { $0.repeatCopy != nil }; noCopies.syncGuides()
        XCTAssertNil(noCopies.objects[0].lineRepeat); XCTAssertNil(noCopies.objects[0].guideFor)
        XCTAssertFalse(noCopies.needsSchemaSixteen)
    }

    func testPastingWithTheGuideMakesASeparateSet() throws {
        var (design, id) = try repeated(3)
        let pasted = design.paste(ObjectClipboard(objects: design.objects), offset: Point(0, 30))
        design.syncGuides()
        let other = try XCTUnwrap(design.objects.first { pasted.contains($0.id) && $0.lineRepeat != nil }?.lineRepeat?.id)
        XCTAssertNotEqual(other, id)
        XCTAssertEqual(design.objects.filter { $0.repeatCopy?.id == other }.count, 3)
        XCTAssertEqual(design.objects.filter { $0.repeatCopy?.id == id }.count, 3)
        // A copy pasted on its own is just an object.
        let alone = design.paste(ObjectClipboard(objects: [copies(design)[0]]), offset: Point(0, -30))
        design.syncGuides()
        XCTAssertNil(design.objects.first { $0.id == alone[0] }?.repeatCopy)
    }

    func testSewnOneColorAtATimeAlongTheLine() throws {
        let a = tile(Point(0, 20), color: ThreadColor.palette[0]), b = tile(Point(0, 24), color: ThreadColor.palette[1]), l = line([Point(0, 0), Point(40, 0)])
        var design = Design(); design.objects = [a, b, l]
        try design.repeatAlongLine([a.id, b.id, l.id], line: l.id, copies: 3)
        XCTAssertEqual(design.objects.compactMap { $0.repeatCopy.map { "\($0.name) \($0.index)" } }, ["Tile 0", "Tile 1", "Tile 2", "Tile 0", "Tile 1", "Tile 2"])
        XCTAssertEqual(design.objects.prefix(3).map(\.color), Array(repeating: ThreadColor.palette[0], count: 3))
        XCTAssertNotNil(design.objects.last?.lineRepeat, "the guide comes last")
    }

    func testBreakApart() throws {
        var (design, id) = try repeated(3)
        design.breakApartRepeat(id); design.syncGuides()
        XCTAssertFalse(design.needsSchemaSixteen)
        XCTAssertEqual(design.objects.count, 4, "the copies and the line stay")
    }

    func testRefusesWhatItCantDo() {
        let t = tile(), l = line([Point(0, 0), Point(40, 0)])
        var design = Design(); design.objects = [t, l]
        XCTAssertThrowsError(try design.repeatAlongLine([l.id], line: l.id), "no shapes to repeat")
        var closed = l; closed.closed = true; closed.nodes.append(PathNode(Point(20, 20)))
        design.objects = [t, closed]
        XCTAssertThrowsError(try design.repeatAlongLine([t.id, closed.id], line: closed.id), "a closed outline isn't a line")
    }

    func testCheckedAndSavedAsVersionSixteen() throws {
        var (design, id) = try repeated(3)
        let reread = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reread, design)
        design.schemaVersion = 16
        XCTAssertNoThrow(try design.validate())
        var bad = design; bad.setLineRepeat(id) { $0.copies = 0 }
        XCTAssertThrowsError(try bad.validate())
    }
}
