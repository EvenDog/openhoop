// Break Apart: a fill's holes each get a fill of their own (the fill keeps its holes, so nothing is sewn twice),
// lettering and monograms become plain shapes, and objects that aren't composite are left alone.
import XCTest
@testable import EmbroideryCore

final class BreakApartTests: XCTestCase {
    /// A 40 × 30 mm fill with two square holes: one drawn counterclockwise, one clockwise.
    private func donut() -> RunObject {
        var fill = RunObject(name: "Panel", nodes: [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)].map { PathNode($0) }, color: ThreadColor.palette[2])
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.angle = 30
        fill.holes = [[Point(5, 5), Point(15, 5), Point(15, 15), Point(5, 15)].map { PathNode($0) },
                      [Point(25, 5), Point(25, 15), Point(35, 15), Point(35, 5)].map { PathNode($0) }]
        fill.entry = Point(1, 1)
        return fill
    }

    func testEachHoleGetsAFillOfItsOwnAndTheFillKeepsItsHoles() throws {
        var design = Design(); let fill = donut()
        var after = RunObject(name: "After", nodes: [PathNode(Point(50, 0)), PathNode(Point(60, 0))])
        after.digitizing = DigitizingSettings(kind: .run)
        design.objects = [fill, after]
        let result = design.breakApart([fill.id])
        XCTAssertEqual(result.holeFills.count, 2)
        XCTAssertEqual(design.objects.map(\.name), ["Panel", "Panel hole 1", "Panel hole 2", "After"], "the hole fills come right after the fill")
        XCTAssertEqual(design.objects[0].holes?.count, 2, "the fill keeps its holes")
        for (piece, hole) in zip(design.objects[1...2], fill.holes!) {
            XCTAssertEqual(Set(piece.nodes.map(\.point)), Set(hole.map(\.point)), "\(piece.name) is its hole")
            XCTAssertGreaterThan(AreaGeometry.area(AreaGeometry.ring(piece.nodes)), 0, "\(piece.name) runs counterclockwise")
            XCTAssertEqual(piece.color, fill.color); XCTAssertEqual(piece.settings.angle, 30); XCTAssertEqual(piece.kind, .fill)
            XCTAssertNil(piece.holes); XCTAssertNil(piece.entry, "the fill's start point belongs to the fill")
            XCTAssertTrue(result.holeFills.contains(piece.id))
        }
        XCTAssertNoThrow(try design.validate())
        let plan = try StitchEngine.compile(design)
        XCTAssertEqual(Set(plan.commands.compactMap(\.objectID)).count, 4, "all four sew")
    }

    func testGuidedAndRadialFillsGiveFillsOfTheirOwnShape() {
        var design = Design(); var fill = donut()
        fill.digitizing?.fillStyle = .guided; fill.digitizing?.radialCenter = Point(20, 20); fill.digitizing?.angleLines = [[Point(0, 0), Point(40, 30)]]
        design.objects = [fill]
        design.breakApart([fill.id])
        let piece = design.objects[1]
        XCTAssertEqual(piece.settings.fillStyle ?? .tatami, .tatami, "no guide line of its own, so plain tatami")
        XCTAssertNil(piece.settings.radialCenter); XCTAssertNil(piece.settings.angleLines)
    }

    func testLockedPlainAndUnholedObjectsAreLeftAlone() {
        var design = Design(); var locked = donut(); locked.locked = true
        var plain = donut(); plain.holes = nil
        design.objects = [locked, plain]
        let before = design
        XCTAssertTrue(design.breakApart([locked.id, plain.id]).isEmpty)
        XCTAssertEqual(design, before)
    }

    func testLetteringAndMonogramsBecomePlainShapes() throws {
        let fonts = EmbroideryFont.all(in: EmbroideryFontTests.directory)
        let monogram = try MonogramSpec(initials: "AB", fontKind: .system, font: "Helvetica-Bold", height: 20, layout: .sideBySide, ornament: .dots, border: .none)
            .build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects
        var design = Design(); design.objects = monogram
        let result = design.breakApart([monogram[0].id])
        XCTAssertEqual(result.monograms, 1)
        XCTAssertTrue(design.objects.allSatisfy { $0.monogram == nil && $0.groupID == monogram[0].groupID }, "every part, still grouped")
        XCTAssertTrue(result.holeFills.isEmpty, "a monogram's letters with holes keep them as they are")
    }
}
