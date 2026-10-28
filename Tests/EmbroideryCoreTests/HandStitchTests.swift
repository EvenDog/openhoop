// Checks the hand stitch effect on running lines and satins: how far it moves needle holes, how many passes Count
// adds, that it leaves underlay and section ends alone, that a satin can have it on one edge only, that it sews the
// same every time, and its file checks.
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

    /// The satin's own stitches, without its underlay or the short hidden runs to and from it. Its left edge
    /// (sewing up the screen) is x = 0, less compensation; its right x = 4, plus compensation.
    func top(_ object: RunObject) throws -> [Point] {
        try StitchEngine.fresh(object, under: []).sections.filter { !$0.underlay }.max { $0.points.count < $1.points.count }!.points
    }

    func testOneSideLeavesTheOtherEdgeCrisp() throws {
        let plain = try top(satin())
        let leftEdge = plain.map(\.x).min()!, rightEdge = plain.map(\.x).max()!
        // One satin, so its random numbers are the same each time; only its Side changes.
        let both = satin(hand(length: 5, angle: 5))
        var left = both; left.digitizing?.handStitch?.side = .left
        let rough = try top(left), bothRough = try top(both)
        XCTAssertEqual(rough.count, plain.count)
        // Holes on the right edge haven't moved; holes on the left have, just as with the effect on both edges.
        for k in plain.indices {
            if plain[k].x == rightEdge { XCTAssertEqual(rough[k], plain[k]) } else { XCTAssertEqual(rough[k], bothRough[k]) }
        }
        XCTAssertTrue(zip(plain, rough).contains { $0.x == leftEdge && $0 != $1 }, "the left edge is rough")
        // Right is the mirror image.
        var right = both; right.digitizing?.handStitch?.side = .right
        let mirrored = try top(right)
        XCTAssertTrue(zip(plain, mirrored).allSatisfy { $0.x == leftEdge ? $0 == $1 : true })
        XCTAssertTrue(zip(plain, mirrored).contains { $0.x == rightEdge && $0 != $1 })
    }

    func testLeftComesFromTheShapeNotTheDrawingOrder() throws {
        var left = hand(length: 5, angle: 5); left.side = .left
        // The same column with each pair's points drawn right first: the left edge (x = 0) is still the rough one.
        var swapped = satin(left)
        swapped.nodes = [Point(4, 0), Point(0, 0), Point(4, 20), Point(0, 20)].map { PathNode($0) }
        let rightEdge = try top(satin()).map(\.x).max()!
        XCTAssertTrue(try top(swapped).filter { $0.x > 2 }.allSatisfy { $0.x == rightEdge }, "the right edge stays straight")
        // Sewn the other way (down the screen), left is the other edge.
        var downward = satin(left)
        downward.nodes = [Point(0, 20), Point(4, 20), Point(0, 0), Point(4, 0)].map { PathNode($0) }
        let leftEdge = try top(satin()).map(\.x).min()!
        XCTAssertTrue(try top(downward).filter { $0.x < 2 }.allSatisfy { $0.x == leftEdge }, "the x = 0 edge stays straight")
    }

    func testCountOnTheCrispEdgeSlidesAlongItIntoNewHoles() throws {
        let plain = try top(satin()), rightEdge = plain.map(\.x).max()!
        let original = plain.filter { $0.x > 2 }
        for angle in [0, 5] {
            var h = hand(length: 5, angle: angle, count: 3); h.side = .left
            let crispHoles = try top(satin(h)).filter { $0.x > 2 }
            XCTAssertTrue(crispHoles.allSatisfy { abs($0.x - rightEdge) < 1e-9 }, "every pass stays on the right edge (angle \(angle))")
            // A hole sewn over again isn't the same hole: an extra pass lands at least 0.1 mm from every original hole.
            let extra = crispHoles.filter { !original.contains($0) }
            XCTAssertTrue(original.allSatisfy { crispHoles.contains($0) }, "the original holes are still sewn")
            XCTAssertTrue(extra.allSatisfy { e in original.allSatisfy { e.distance(to: $0) > 0.1 - 1e-9 } }, "angle \(angle)")
        }
    }

    func testOldFilesWithoutSideReadAsBothEdges() throws {
        let saved = try JSONEncoder().encode(hand(count: 2))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("side"))
        XCTAssertNil(try JSONDecoder().decode(HandStitch.self, from: saved).side)
        var h = hand(); h.side = .right
        XCTAssertEqual(try JSONDecoder().decode(HandStitch.self, from: JSONEncoder().encode(h)).side, .right)
    }
}
