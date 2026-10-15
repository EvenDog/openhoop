// One object that can't be sewn doesn't stop the rest from being shown with fresh stitches, and a shape check spots
// a satin with a rung crossing a rail.
import XCTest
@testable import EmbroideryCore

final class BrokenObjectsTests: XCTestCase {
    /// A satin column 20 mm long and 3 mm wide, rungs every 5 mm.
    private func satin(_ name: String, x: Double) -> RunObject {
        let rungs = stride(from: 0.0, through: 20, by: 5).flatMap { y in [PathNode(Point(x - 1.5, y)), PathNode(Point(x + 1.5, y))] }
        var object = RunObject(name: name, nodes: rungs); object.digitizing = DigitizingSettings(kind: .satin)
        return object
    }
    private func square(_ name: String, x: Double) -> RunObject {
        var object = RunObject(name: name, nodes: [Point(x - 5, -20), Point(x + 5, -20), Point(x + 5, -10), Point(x - 5, -10)].map { PathNode($0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }

    func testOneBrokenObjectLeavesTheRestShown() throws {
        var bad = satin("Bad satin", x: 0)
        bad.nodes[4].point = Point(3, 12)   // a left-rail point dragged across the right rail: its rung crosses the rail
        XCTAssertNotNil(StitchEngine.shapeProblem(bad))
        var design = Design(); design.objects = [square("Fill", x: -20), bad, satin("Good satin", x: 20)]
        XCTAssertThrowsError(try StitchEngine.compile(design), "the design as a whole can't be sewn")
        let shown = try StitchEngine.compileSkippingBroken(design)
        XCTAssertEqual(Array(shown.broken.keys), [bad.id])
        XCTAssertTrue(shown.broken[bad.id]!.hasPrefix("Bad satin: "))
        let drawn = Set(shown.plan.commands.compactMap(\.objectID))
        XCTAssertEqual(drawn, [design.objects[0].id, design.objects[2].id], "the fill and the good satin get stitches")
        var fixed = design; fixed.objects.remove(at: 1)
        XCTAssertEqual(shown.plan, try StitchEngine.compile(fixed), "exactly as if the broken one weren't there")
    }

    func testShapeCheck() {
        XCTAssertNil(StitchEngine.shapeProblem(satin("Satin", x: 0)))
        XCTAssertNil(StitchEngine.shapeProblem(square("Fill", x: 0)))
        var bowtie = square("Bowtie", x: 0); bowtie.nodes.swapAt(2, 3)   // its edges cross
        XCTAssertNotNil(StitchEngine.shapeProblem(bowtie))
    }

    /// Dragging a fill's nodes away from its stitch angle lines leaves them crossing nothing: the fill can't be sewn,
    /// and the quick check says so (found by the random design tests), agreeing with the full engine both ways.
    func testShapeCheckSpotsAngleLinesThatNoLongerCross() {
        var fill = square("Turning fill", x: 0)   // 10 × 10 mm, from y = -20 to -10
        fill.digitizing?.angleLines = [[Point(-3, -18), Point(3, -18)], [Point(-3, -12), Point(3, -11)]]
        XCTAssertNil(StitchEngine.shapeProblem(fill))
        XCTAssertNoThrow(try AreaEngine.fill(fill))
        // The whole shape dragged 30 mm to the right; the lines stay where they were, and their lines don't reach it.
        var moved = fill; moved.nodes = moved.nodes.map { var n = $0; n.point = n.point + Point(30, 30); return n }
        XCTAssertEqual(StitchEngine.shapeProblem(moved), "The stitch angle lines don't cross this fill. Draw them across it, or remove them.")
        XCTAssertThrowsError(try AreaEngine.fill(moved))
    }

    /// A contour fill narrower than its row spacing has no room for its first ring.
    func testShapeCheckSpotsAContourFillTooThinForItsSpacing() {
        var sliver = RunObject(name: "Sliver", nodes: [Point(0, 0), Point(20, 0), Point(20, 0.4), Point(0, 0.4)].map { PathNode($0) })
        sliver.closed = true; sliver.digitizing = DigitizingSettings(kind: .fill); sliver.digitizing?.fillStyle = .contour
        sliver.digitizing?.expansion = 0; sliver.digitizing?.spacing = 1.5
        XCTAssertEqual(StitchEngine.shapeProblem(sliver), "This fill is too small for the selected row spacing.")
        XCTAssertThrowsError(try AreaEngine.fill(sliver))
        sliver.digitizing?.spacing = 0.3   // narrow rows fit
        XCTAssertNil(StitchEngine.shapeProblem(sliver))
        XCTAssertNoThrow(try AreaEngine.fill(sliver))
    }
}
