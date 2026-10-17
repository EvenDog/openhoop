// Checks guided fills: rows follow the guide line and stay evenly spaced (each row is a whole number of spacings
// from the guide), a looping guide is refused, and a line turned into a guide stays linked to its fill through
// edits, copying and deleting.
import XCTest
@testable import EmbroideryCore

final class GuidedFillTests: XCTestCase {
    private func rectangle(_ width: Double, _ height: Double) -> RunObject {
        var object = RunObject(name: "Fill", nodes: [Point(0, 0), Point(width, 0), Point(width, height), Point(0, height)].map { PathNode($0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    private func distance(_ p: Point, to path: [Point]) -> Double {
        zip(path, path.dropFirst()).map { p.distance(to: AreaGeometry.projection(p, $0, $1)) }.min()!
    }
    /// An arch reaching well past both sides of the shape (so every part of the shape is nearest the arch itself,
    /// not its straight extensions), 7 mm high in the middle.
    private let arch = stride(from: -10.0, through: 40, by: 1).map { x in Point(x, 5 + 7 * (1 - pow((x - 15) / 17, 2))) }

    func testRowsFollowTheGuideEvenlySpaced() throws {
        let region = [AreaGeometry.ring(rectangle(30, 20).nodes)]
        let rows = try GuidedFill.rows(in: region, guide: arch, spacing: 0.5, length: 3)
        XCTAssertGreaterThan(rows.count, 35, "rows reach right across the shape")
        for row in rows {
            for point in row {
                XCTAssertTrue(AreaGeometry.contains(point, rings: (try? AreaGeometry.offset(region, by: 0.01)) ?? region), "inside the shape")
                // Each row is a whole number of spacings from the guide.
                let d = distance(point, to: arch) / 0.5
                XCTAssertEqual(d, d.rounded(), accuracy: 0.1, "\(point) is \(d) spacings from the guide")
            }
            XCTAssertTrue(zip(row, row.dropFirst()).allSatisfy { $0.distance(to: $1) <= 3.31 }, "stitches no longer than the stitch length (the last one up to 0.3 mm over)")
        }
        // The row just above the arch bends like it: higher in the middle than at the sides.
        func middle(_ row: [Point]) -> Point { row.min { abs($0.x - 15) < abs($1.x - 15) }! }
        let above = try XCTUnwrap(rows.filter { row in row.contains { $0.x < 1 } && row.contains { $0.x > 29 } && middle(row).y > 12.2 }.min { middle($0).y < middle($1).y })
        let side = above.min { abs($0.x - 1) < abs($1.x - 1) }!
        XCTAssertGreaterThan(middle(above).y - side.y, 3, "the row arches")
    }

    func testAStraightGuideMakesStraightRows() throws {
        let region = [AreaGeometry.ring(rectangle(20, 20).nodes)]
        // A short guide in the middle: it's carried straight on to the edges.
        let rows = try GuidedFill.rows(in: region, guide: [Point(8, 10), Point(12, 10)], spacing: 0.4, length: 3)
        XCTAssertGreaterThanOrEqual(rows.count, 49)
        for row in rows {
            XCTAssertEqual(row.map(\.y).max()! - row.map(\.y).min()!, 0, accuracy: 0.02, "level")
            XCTAssertEqual(row.map(\.x).max()! - row.map(\.x).min()!, 20, accuracy: 0.05, "from edge to edge")
            let level = (row[0].y - 10) / 0.4
            XCTAssertEqual(level, level.rounded(), accuracy: 0.05)
        }
    }

    func testBadGuidesAreRefused() {
        let region = [AreaGeometry.ring(rectangle(20, 20).nodes)]
        let loop = [Point(2, 2), Point(18, 2), Point(18, 18), Point(10, 18), Point(10, 0)]
        XCTAssertThrowsError(try GuidedFill.rows(in: region, guide: loop, spacing: 0.4, length: 3), "a guide crossing itself")
        XCTAssertThrowsError(try GuidedFill.rows(in: region, guide: [Point(5, 5), Point(5.3, 5)], spacing: 0.4, length: 3), "too short")
        var fill = rectangle(20, 20); fill.digitizing?.fillStyle = .guided
        var design = Design(); design.objects = [fill]
        XCTAssertThrowsError(try StitchEngine.compile(design), "a guided fill with no guide") { error in
            XCTAssertTrue(error.localizedDescription.contains("Use Line as Fill Guide"))
        }
        XCTAssertNotNil(StitchEngine.shapeProblem(fill), "flagged as can't be sewn")
    }

    func testALineBecomesTheFillsGuideAndStaysLinked() throws {
        var fill = rectangle(30, 20); fill.digitizing?.fillStyle = .contour
        let line = RunObject(name: "Line", nodes: arch.enumerated().filter { $0.offset % 4 == 0 }.map { PathNode($0.element) })
        let other = RunObject(name: "Other", nodes: [PathNode(Point(0, 30)), PathNode(Point(10, 30))])
        var design = Design(); design.objects = [line, fill, other]
        XCTAssertThrowsError(try design.useAsFillGuide(line: other.id, fill: line.id), "the fill must be a fill")
        try design.useAsFillGuide(line: line.id, fill: fill.id)
        XCTAssertEqual(design.objects.map(\.id), [fill.id, line.id, other.id], "the guide goes just after its fill")
        let guide = design.objects[1]
        XCTAssertEqual(guide.kind, .vector, "it stops sewing"); XCTAssertEqual(guide.guideFor, fill.id)
        XCTAssertNotNil(guide.groupID); XCTAssertEqual(guide.groupID, design.objects[0].groupID, "they move together")
        XCTAssertEqual(design.objects[0].settings.fillStyle, .guided)
        XCTAssertEqual(design.objects[0].settings.guideLine, guide.outlinePaths[0])
        XCTAssertTrue(design.needsSchemaSix)
        let plan = try StitchEngine.compile(design)
        XCTAssertFalse(plan.warnings.contains { $0.contains("unstitched") }, "a guide isn't an unstitched outline left out")
        XCTAssertFalse(plan.commands.contains { $0.objectID == guide.id }, "and sews nothing")

        // Reshaping the guide reshapes the fill's rows.
        design.objects[1].nodes[3].point.y += 4; design.syncGuides()
        XCTAssertEqual(design.objects[0].settings.guideLine, design.objects[1].outlinePaths[0])

        // Copied together, the copies are linked to each other; a guide copied alone is just a line.
        var copied = design
        let pasted = copied.paste(design.copying([fill.id, line.id]), offset: Point(40, 0))
        XCTAssertEqual(copied.objects.first { $0.id == pasted[1] }?.guideFor, pasted[0])
        _ = copied.paste(design.copying([line.id]))
        XCTAssertNil(copied.objects.last?.guideFor)

        // Without its guide, the fill keeps the last path; without its fill, the guide is unlinked.
        var noGuide = design; noGuide.objects.remove(at: 1); noGuide.syncGuides()
        XCTAssertEqual(noGuide.objects[0].settings.guideLine, design.objects[1].outlinePaths[0])
        XCTAssertNoThrow(try StitchEngine.compile(noGuide))
        var noFill = design; noFill.objects.remove(at: 0); noFill.syncGuides()
        XCTAssertNil(noFill.objects[0].guideFor)

        // Moving the fill moves its stored guide with it.
        var moved = design.objects[0]; moved.transform { $0 + Point(5, 0) }
        XCTAssertEqual(moved.settings.guideLine?.first, design.objects[0].settings.guideLine.map { $0[0] + Point(5, 0) })

        var closed = other; closed.id = UUID(); closed.closed = true; closed.nodes.append(PathNode(Point(5, 35)))
        design.objects.append(closed)
        XCTAssertThrowsError(try design.useAsFillGuide(line: closed.id, fill: fill.id), "an outline can't be a guide")
    }
}
