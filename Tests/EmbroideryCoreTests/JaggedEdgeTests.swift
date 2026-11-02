// Checks the jagged edge effect on satin columns and satin fills: that edge holes move in or out along their
// stitches by no more than the amount, that split points, underlay and section ends stay put, that a column can be
// jagged on one edge only, that it sews the same every time, and its file checks.
import XCTest
@testable import EmbroideryCore

final class JaggedEdgeTests: XCTestCase {
    /// A 4 mm satin column 20 mm long, with its usual underlay. Its middle is x = 2.
    func satin(_ jagged: JaggedEdge? = nil) -> RunObject {
        var o = RunObject(name: "Satin", nodes: [Point(0, 0), Point(4, 0), Point(0, 20), Point(4, 20)].map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: .satin); o.digitizing?.jaggedEdge = jagged
        return o
    }
    /// A 20 × 10 mm ellipse filled with `style`, stitches running across (angle 0), centered on the origin.
    func fill(_ style: FillStyle, _ jagged: JaggedEdge? = nil) -> RunObject {
        var o = RunObject(name: "Leaf", nodes: (0..<72).map { i in
            let a = Double(i) * .pi / 36
            return PathNode(Point(10 * cos(a), 5 * sin(a)))
        })
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill)
        o.digitizing?.fillStyle = style; o.digitizing?.angle = 0; o.digitizing?.underlay = .none; o.digitizing?.expansion = 0
        o.digitizing?.jaggedEdge = jagged
        return o
    }
    func jagged(amount: Double = 1, outward: Bool = false, side: HandStitch.Side? = nil, variant: Int = 1) -> JaggedEdge {
        var j = JaggedEdge(); j.amount = amount; j.outward = outward; j.side = side; j.variant = variant
        return j
    }
    /// The satin's own stitches, without its underlay or the short hidden runs to and from it.
    func top(_ object: RunObject) throws -> [Point] {
        try StitchEngine.fresh(object, under: []).sections.filter { !$0.underlay }.max { $0.points.count < $1.points.count }!.points
    }
    func points(_ object: RunObject) throws -> [Point] { try StitchEngine.fresh(object, under: []).sections.flatMap(\.points) }

    func testInShortensStitchesByNoMoreThanTheAmount() throws {
        let plain = try top(satin()), rough = try top(satin(jagged(amount: 1)))
        XCTAssertEqual(rough.count, plain.count)
        XCTAssertEqual(rough.first, plain.first, "the satin still starts where it did")
        XCTAssertEqual(rough.last, plain.last, "and ends there")
        for (p, r) in zip(plain, rough) {
            XCTAssertLessThanOrEqual(p.distance(to: r), 1.0001)
            XCTAssertLessThanOrEqual(abs(r.x - 2), abs(p.x - 2) + 0.0001, "moved in, toward the middle")
        }
        XCTAssertGreaterThan(zip(plain, rough).map { $0.distance(to: $1) }.max()!, 0.3, "holes really do move")
    }

    func testOutLengthensStitches() throws {
        let plain = try top(satin()), rough = try top(satin(jagged(amount: 1, outward: true)))
        for (p, r) in zip(plain, rough) {
            XCTAssertLessThanOrEqual(p.distance(to: r), 1.0001)
            XCTAssertGreaterThanOrEqual(abs(r.x - 2), abs(p.x - 2) - 0.0001, "moved out, away from the middle")
        }
        XCTAssertGreaterThan(zip(plain, rough).map { $0.distance(to: $1) }.max()!, 0.3)
    }

    func testSplitPointsInTheMiddleOfAStitchStayPut() {
        // Across to (10, 0.4) through a split at (5, 0), back to (0, 0.8), across again to (10, 1.2), then on to (10, 2).
        let points = [Point(0, 0), Point(5, 0), Point(10, 0.4), Point(0, 0.8), Point(10, 1.2), Point(10, 2)]
        var dice = FillStyles.Seeded(seed: 1)
        let moved = jagged(amount: 2).jagged(points, &dice)
        XCTAssertEqual(moved[1], points[1], "the needle carries straight on through a split")
        XCTAssertNotEqual(moved[2], points[2], "it turns back at an edge")
        XCTAssertNotEqual(moved[3], points[3])
        XCTAssertEqual(moved[4], points[4], "it carries on along the edge here, so this isn't a turn")
        XCTAssertEqual(moved.first, points.first); XCTAssertEqual(moved.last, points.last)
    }

    func testInNeverTakesMoreThanFortyPercentOffAStitch() {
        // 1 mm stitches with a 5 mm amount: each moves at most 0.4 mm.
        let points = [Point(0, 0), Point(1, 0.2), Point(0, 0.4), Point(1, 0.6), Point(0, 0.8)]
        var dice = FillStyles.Seeded(seed: 7)
        let moved = jagged(amount: 5).jagged(points, &dice)
        for k in 1..<points.count - 1 { XCTAssertLessThanOrEqual(moved[k].distance(to: points[k]), 0.4 * points[k - 1].distance(to: points[k]) + 0.0001) }
    }

    func testUnderlayIsLeftAlone() throws {
        let plain = try StitchEngine.fresh(satin(), under: []), rough = try StitchEngine.fresh(satin(jagged(amount: 2)), under: [])
        XCTAssertEqual(rough.sections.filter(\.underlay).map(\.points), plain.sections.filter(\.underlay).map(\.points))
    }

    func testOneSideLeavesTheOtherEdgeSmooth() throws {
        let plain = try top(satin())
        let leftEdge = plain.map(\.x).min()!, rightEdge = plain.map(\.x).max()!
        // One satin, so its random numbers (seeded from its id) are the same each time; only its Side changes.
        let base = satin(jagged(amount: 1))
        var leftOnly = base; leftOnly.digitizing?.jaggedEdge?.side = .left
        let left = try top(leftOnly), both = try top(base)
        // Holes on the right edge haven't moved; holes on the left have, just as with both edges jagged.
        for k in plain.indices {
            if plain[k].x == rightEdge { XCTAssertEqual(left[k], plain[k]) } else { XCTAssertEqual(left[k], both[k]) }
        }
        XCTAssertTrue(zip(plain, left).contains { $0.x == leftEdge && $0 != $1 }, "the left edge is jagged")
        var rightOnly = base; rightOnly.digitizing?.jaggedEdge?.side = .right
        let right = try top(rightOnly)
        XCTAssertTrue(zip(plain, right).allSatisfy { $0.x == leftEdge ? $0 == $1 : true })
        XCTAssertTrue(zip(plain, right).contains { $0.x == rightEdge && $0 != $1 })
    }

    func testSatinFillsGetItButOtherFillsDont() throws {
        let plain = try points(fill(.satin)), rough = try points(fill(.satin, jagged(amount: 1)))
        XCTAssertEqual(rough.count, plain.count)
        XCTAssertNotEqual(rough, plain)
        XCTAssertLessThanOrEqual(zip(plain, rough).map { $0.distance(to: $1) }.max()!, 1.0001)
        // A tatami fill keeps a jagged edge it was given while it was satin, but sews as if it had none.
        XCTAssertEqual(try points(fill(.tatami, jagged(amount: 1))), try points(fill(.tatami)))
    }

    func testSameEveryTimeAndVariantChangesIt() throws {
        let object = satin(jagged())
        XCTAssertEqual(try points(object), try points(object), "the same object sews the same")
        var other = object; other.digitizing?.jaggedEdge?.variant = 2
        XCTAssertNotEqual(try points(other), try points(object))
    }

    func testCheckedAndSavedAsVersionFifteen() throws {
        var design = Design(); design.objects = [satin(), fill(.satin)]
        XCTAssertFalse(design.needsSchemaFifteen)
        design.objects[1].digitizing?.jaggedEdge = jagged(amount: 2, outward: true)
        XCTAssertTrue(design.needsSchemaFifteen)
        let reread = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reread.objects[1].settings.jaggedEdge, jagged(amount: 2, outward: true))
        design.schemaVersion = 15
        XCTAssertNoThrow(try design.validate())
        var bad = design; bad.objects[1].digitizing?.jaggedEdge?.amount = 9
        XCTAssertThrowsError(try bad.validate())
    }
}
