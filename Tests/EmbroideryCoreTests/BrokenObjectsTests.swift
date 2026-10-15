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
}
