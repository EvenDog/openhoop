// Checks the hand stitch effect on running lines and satins: how far it moves needle holes, how many passes Count
// adds, that it leaves underlay and section ends alone, that it sews the same every time, and its file checks.
import XCTest
@testable import EmbroideryCore

final class HandStitchTests: XCTestCase {
    /// A 40 mm straight running line with 2.5 mm stitches.
    func line(_ hand: HandStitch? = nil) -> RunObject {
        var o = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(40, 0))])
        o.stitchLength = 2.5; o.digitizing = DigitizingSettings(kind: .run); o.digitizing?.handStitch = hand
        return o
    }
    /// A 4 mm satin column 20 mm long, with its usual underlay.
    func satin(_ hand: HandStitch? = nil) -> RunObject {
        var o = RunObject(name: "Satin", nodes: [Point(0, 0), Point(4, 0), Point(0, 20), Point(4, 20)].map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: .satin); o.digitizing?.handStitch = hand
        return o
    }
    func hand(length: Int = 2, angle: Int = 2, count: Int = 1, random: Int = 1, variant: Int = 1) -> HandStitch {
        var h = HandStitch(); h.length = length; h.angle = angle; h.count = count; h.random = random; h.variant = variant
        return h
    }
    func points(_ object: RunObject) throws -> [Point] { try StitchEngine.fresh(object, under: []).sections.flatMap(\.points) }

    func testNoRoughnessAndOnePassChangesNothing() throws {
        XCTAssertEqual(try points(line(hand(length: 0, angle: 0))), try points(line()))
        XCTAssertEqual(try points(satin(hand(length: 0, angle: 0))), try points(satin()))
    }

    func testRoughnessMovesHolesOnlyAsFarAsItSays() throws {
        let plain = try points(line()), rough = try points(line(hand(length: 5, angle: 5)))
        XCTAssertEqual(rough.count, plain.count)
        XCTAssertEqual(rough.first, plain.first, "the line still starts where it did")
        XCTAssertEqual(rough.last, plain.last, "and ends there")
        // Each hole moves at most a fifth of a stitch along and tan(10°)/2 of a stitch across.
        let stitch = plain[0].distance(to: plain[1])
        let moves = zip(plain, rough).map { abs($1.x - $0.x) }, sideways = zip(plain, rough).map { abs($1.y - $0.y) }
        XCTAssertLessThanOrEqual(moves.max()!, 0.2 * stitch + 0.0001)
        XCTAssertLessThanOrEqual(sideways.max()!, tan(10 * Double.pi / 180) / 2 * stitch + 0.0001)
        XCTAssertGreaterThan(moves.max()!, 0.05, "holes really do move")
        XCTAssertGreaterThan(sideways.max()!, 0.05)
    }

    func testCountSewsEachStitchOverInNewHoles() throws {
        let plain = try points(line()), twice = try points(line(hand(count: 2)))
        // Each stitch: forward, then back and forward again.
        XCTAssertEqual(twice.count, 1 + (plain.count - 1) * 3)
        XCTAssertEqual(twice.last, plain.last)
        XCTAssertEqual(try points(line(hand(count: 3))).count, 1 + (plain.count - 1) * 5)
        // With Random at 5, some stitches get a pass more or fewer.
        let uneven = try points(line(hand(count: 2, random: 5)))
        XCTAssertNotEqual(uneven.count, twice.count)
    }

    func testSatinUnderlayIsLeftAlone() throws {
        let plain = try StitchEngine.fresh(satin(), under: []), rough = try StitchEngine.fresh(satin(hand(length: 5, angle: 5, count: 2)), under: [])
        XCTAssertEqual(rough.sections.filter(\.underlay).map(\.points), plain.sections.filter(\.underlay).map(\.points))
        XCTAssertNotEqual(rough.sections.filter { !$0.underlay }.map(\.points), plain.sections.filter { !$0.underlay }.map(\.points))
    }

    func testSameEveryTimeAndVariantChangesIt() throws {
        let object = satin(hand())
        XCTAssertEqual(try points(object), try points(object), "the same object sews the same")
        var other = object; other.digitizing?.handStitch?.variant = 2
        XCTAssertNotEqual(try points(other), try points(object))
    }

    func testCheckedAndSavedAsVersionThirteen() throws {
        var design = Design(); design.objects = [line(), satin()]
        XCTAssertFalse(design.needsSchemaThirteen)
        design.objects[1].digitizing?.handStitch = hand(count: 2)
        XCTAssertTrue(design.needsSchemaThirteen)
        let reread = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reread.objects[1].settings.handStitch, hand(count: 2))
        design.schemaVersion = 13
        XCTAssertNoThrow(try design.validate())
        var bad = design; bad.objects[1].digitizing?.handStitch?.length = 6
        XCTAssertThrowsError(try bad.validate())
    }
}
