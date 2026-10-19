// Row spacing for tatami, wave and guided fills is measured across two rows (from a row to the next one sewn the
// same way), so 0.40 mm lays rows 0.20 mm apart. Designs saved before this have those spacings doubled when they're
// opened, so they sew exactly as they did.
import XCTest
@testable import EmbroideryCore

final class RowSpacingTests: XCTestCase {
    private func square(style: FillStyle? = nil) -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(0, 0), Point(20, 0), Point(20, 20), Point(0, 20)].map { PathNode($0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        object.digitizing?.fillStyle = style; object.digitizing?.angle = 0; object.digitizing?.underlay = .none
        return object
    }

    func testPointFourLaysTatamiRowsPointTwoApart() throws {
        let object = square()
        XCTAssertEqual(object.settings.spacing, 0.4)
        // Level rows: the heights of the long sideways stitches, one per row.
        let points = try AreaEngine.fill(object).sections.flatMap(\.points)
        var heights = Set<Double>()
        for (a, b) in zip(points, points.dropFirst()) where abs(b.x - a.x) > 1 && abs(b.y - a.y) < 0.001 {
            heights.insert((a.y * 1000).rounded() / 1000)
        }
        let sorted = heights.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(gaps.reduce(0, +) / Double(gaps.count), 0.2, accuracy: 0.01)
    }

    func testOtherStitchesKeepTheirMeaning() {
        XCTAssertEqual(square(style: .contour).settings.rowGap, 0.4, "contour rings")
        XCTAssertEqual(square(style: .satin).settings.rowGap, 0.4, "satin fill")
        XCTAssertEqual(DigitizingSettings(kind: .satin).rowGap, DigitizingSettings(kind: .satin).spacing, "satin columns")
        XCTAssertEqual(square(style: .wave).settings.rowGap, 0.2)
    }

    func testOlderDesignsSewTheSameAfterOpening() throws {
        // As saved before: no spacingAcrossTwoRows, so its spacing is the gap from one row to the next.
        var tatami = square(); tatami.digitizing?.spacingAcrossTwoRows = nil
        var contour = square(style: .contour); contour.digitizing?.spacingAcrossTwoRows = nil
        contour.nodes = contour.nodes.map { PathNode($0.point + Point(30, 0)) }
        var old = Design(); old.objects = [tatami, contour]
        let saved = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(old))
        XCTAssertNil(saved.objects[0].settings.spacingAcrossTwoRows)
        let before = try StitchEngine.compile(saved).commands

        var opened = saved; opened.measureSpacingAcrossTwoRows()
        XCTAssertEqual(opened.objects[0].settings.spacing, 0.8, "the tatami's spacing doubles")
        XCTAssertEqual(opened.objects[1].settings.spacing, 0.4, "the contour's stays")
        XCTAssertTrue(opened.objects.allSatisfy { $0.settings.spacingAcrossTwoRows == true })
        XCTAssertEqual(try StitchEngine.compile(opened).commands, before, "the same stitches")
    }

    func testHandEditedStitchesSurviveOpening() throws {
        var object = square(); object.digitizing?.spacingAcrossTwoRows = nil
        let sections = try AreaEngine.fill(object).sections.map { StitchEdits.Section(points: $0.points, underlay: $0.underlay, joined: $0.joined) }
        object.stitchEdits = StitchEdits(sections: sections, signature: object.stitchSignature)
        XCTAssertTrue(object.hasCurrentStitchEdits)
        var design = Design(); design.objects = [object]
        design.measureSpacingAcrossTwoRows()
        XCTAssertTrue(design.objects[0].hasCurrentStitchEdits, "the hand edits still sew")
    }
}
