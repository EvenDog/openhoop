// Checks motifs of one's own (Create Motif): lines are turned into a stroke from (0, 0) to (1, 0) whichever way they
// were drawn, several lines join into one, a closed shape gets runs in and out along its bottom, motif runs and fills
// sew the user's motif instead of a built-in one, and designs using one are saved as file version 14.
import XCTest
@testable import EmbroideryCore

final class CustomMotifTests: XCTestCase {
    /// A tent drawn left to right, 10 mm wide and 5 mm tall, starting at (20, 10).
    let tent = [Point(20, 10), Point(25, 15), Point(30, 10)]

    func testStrokeRunsFromZeroToOneWhicheverWayItWasDrawn() throws {
        let motif = try Motifs.make(from: [tent], name: "Tent")
        XCTAssertEqual(motif.name, "Tent")
        XCTAssertEqual(motif.stroke, [Point(0, 0), Point(0.5, 0.5), Point(1, 0)])
        // Drawn right to left it's the same motif: it still starts at the left end, and the tent still stands up.
        XCTAssertEqual(try Motifs.make(from: [tent.reversed()], name: "Tent").stroke, motif.stroke)
        // Drawn at a slant, the baseline from end to end is turned level.
        let turned = tent.map { AreaGeometry.rotate($0, degrees: 30) }
        for (a, b) in zip(try Motifs.make(from: [turned], name: "Tent").stroke, motif.stroke) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9); XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testSeveralLinesJoinIntoOneStroke() throws {
        // Two humps; the second was drawn backwards, so it's sewn from its nearer end.
        let first = [Point(0, 0), Point(5, 5), Point(10, 0)], second = [Point(20, 0), Point(15, 5), Point(10, 0)]
        let stroke = try Motifs.make(from: [first, second], name: "Humps").stroke
        XCTAssertEqual(stroke.count, 6)
        XCTAssertEqual(stroke.first!, Point(0, 0)); XCTAssertEqual(stroke.last!, Point(1, 0))
        XCTAssertEqual(stroke[3], Point(0.5, 0), "the second line starts where the first ended")
    }

    func testClosedShapeStartsAndEndsAlongItsBottom() throws {
        // A diamond drawn as a closed outline, starting from its top point.
        let diamond = [Point(5, 10), Point(10, 5), Point(5, 0), Point(0, 5), Point(5, 10)]
        let stroke = try Motifs.make(from: [diamond], name: "Diamond").stroke
        XCTAssertEqual(stroke.first!, Point(0, 0), "in from the bottom left corner")
        XCTAssertEqual(stroke.last!, Point(1, 0), "out to the bottom right")
        XCTAssertEqual(stroke[1], Point(0.5, 0), "the loop starts at its lowest point")
        XCTAssertEqual(stroke[stroke.count - 2], Point(0.5, 0), "and comes back to it")
        XCTAssertEqual(stroke.map(\.y).max()!, 1, accuracy: 1e-9, "scaled by its width")
    }

    func testNothingToMakeAMotifFromIsRefused() {
        XCTAssertThrowsError(try Motifs.make(from: [], name: "Empty"))
        XCTAssertThrowsError(try Motifs.make(from: [[Point(3, 3), Point(3, 3)]], name: "Dot"))
        // A closed shape with no width has no bottom to run along.
        XCTAssertThrowsError(try Motifs.make(from: [[Point(0, 0), Point(0, 10), Point(0, 0)]], name: "Stick"))
    }

    func testMotifRunAndFillSewTheUsersMotif() throws {
        let tentMotif = try Motifs.make(from: [tent], name: "Tent")
        var line = RunObject(name: "Line", nodes: [Point(0, 0), Point(30, 0)].map { PathNode($0) })
        line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.runStyle = .motif
        line.digitizing?.runWidth = 4; line.digitizing?.runSpacing = 1
        let hearts = try StitchEngine.fresh(line, under: []).sections.flatMap(\.points)
        line.digitizing?.customMotif = tentMotif
        let tents = try StitchEngine.fresh(line, under: []).sections.flatMap(\.points)
        XCTAssertNotEqual(tents, hearts)
        XCTAssertEqual(tents.map(\.y).max()!, 2, accuracy: 1e-9, "4 mm tents stand 2 mm tall")
        XCTAssertEqual(tents.filter { abs($0.y - 2) < 1e-9 }.count, 6, "six tents with 1 mm gaps fit in 30 mm")

        var fill = RunObject(name: "Fill", nodes: [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.fillStyle = .motif
        fill.digitizing?.angle = 0; fill.digitizing?.expansion = 0; fill.digitizing?.customMotif = tentMotif
        let sections = try AreaEngine.fill(fill).sections
        XCTAssertFalse(sections.isEmpty)
        // Each motif is one section, and a tent is half as tall as it is wide.
        let section = sections[0].points
        XCTAssertEqual(section.map(\.y).max()! - section.map(\.y).min()!, (section.map(\.x).max()! - section.map(\.x).min()!) / 2, accuracy: 1e-6)
    }

    func testCheckedAndSavedAsVersionFourteen() throws {
        var line = RunObject(name: "Line", nodes: [Point(0, 0), Point(30, 0)].map { PathNode($0) })
        line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.runStyle = .motif
        var design = Design(); design.objects = [line]
        XCTAssertFalse(design.needsSchemaFourteen)
        design.objects[0].digitizing?.customMotif = try Motifs.make(from: [tent], name: "Tent")
        XCTAssertTrue(design.needsSchemaFourteen)
        let reread = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reread.objects[0].settings.customMotif, design.objects[0].settings.customMotif)
        design.schemaVersion = 14
        XCTAssertNoThrow(try design.validate())
        var bad = design; bad.objects[0].digitizing?.customMotif?.stroke = [Point(0, 0)]
        XCTAssertThrowsError(try bad.validate(), "a motif needs at least two points")
        bad = design; bad.objects[0].digitizing?.customMotif?.stroke.append(Point(500, 0))
        XCTAssertThrowsError(try bad.validate(), "points far outside the motif's box")
        bad = design; bad.schemaVersion = 15
        XCTAssertThrowsError(try bad.validate(), "a newer file version is refused")
    }
}
