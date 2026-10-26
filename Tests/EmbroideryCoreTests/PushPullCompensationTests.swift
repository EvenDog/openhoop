// Checks fill compensation: straight rows grow only at their ends (pull), push compensation pulls in the edges the
// rows run along, and fills whose stitches turn still grow evenly all round.
import XCTest
@testable import EmbroideryCore

final class PushPullCompensationTests: XCTestCase {
    /// A 30 × 20 mm tatami rectangle with rows at `angle`, `pull` and `push` mm of compensation and no underlay.
    func rectangle(angle: Double, pull: Double, push: Double? = nil, style: FillStyle = .tatami) -> RunObject {
        var o = RunObject(name: "Fill", nodes: [Point(0, 0), Point(30, 0), Point(30, 20), Point(0, 20)].map { PathNode($0) })
        o.closed = true; o.stitchLength = 3
        o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.underlay = .none; o.digitizing?.fillStyle = style
        o.digitizing?.angle = angle; o.digitizing?.expansion = pull; o.digitizing?.pushCompensation = push
        return o
    }
    /// The smallest box holding every stitch of `object`.
    func bounds(_ object: RunObject) throws -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let points = try AreaEngine.fill(object).sections.flatMap(\.points)
        return (points.map(\.x).min()!, points.map(\.x).max()!, points.map(\.y).min()!, points.map(\.y).max()!)
    }

    func testPullLengthensStraightRowsOnlyAtTheirEnds() throws {
        let across = try bounds(rectangle(angle: 0, pull: 0.5))
        XCTAssertEqual(across.minX, -0.5, accuracy: 0.03, "rows along x reach past the left edge")
        XCTAssertEqual(across.maxX, 30.5, accuracy: 0.03)
        XCTAssertGreaterThan(across.minY, -0.03, "the edges the rows run along don't grow")
        XCTAssertLessThan(across.maxY, 20.03)
        let upright = try bounds(rectangle(angle: 90, pull: 0.5))
        XCTAssertEqual(upright.minY, -0.5, accuracy: 0.03, "rows along y reach past the bottom edge")
        XCTAssertEqual(upright.maxY, 20.5, accuracy: 0.03)
        XCTAssertGreaterThan(upright.minX, -0.03)
        XCTAssertLessThan(upright.maxX, 30.03)
    }

    func testPushPullsInTheEdgesTheRowsRunAlong() throws {
        let pushed = try bounds(rectangle(angle: 0, pull: 0.5, push: 0.5))
        XCTAssertGreaterThan(pushed.minY, 0.47, "the bottom edge moves in")
        XCTAssertLessThan(pushed.maxY, 19.53, "and so does the top")
        XCTAssertEqual(pushed.maxX - pushed.minX, 31, accuracy: 0.06, "the row ends still grow")
    }

    func testFillsWhoseStitchesTurnGrowEvenly() throws {
        let contour = try bounds(rectangle(angle: 0, pull: 0.5, style: .contour))
        // Its first ring is half a row spacing (0.2 mm) inside the grown outline.
        XCTAssertEqual(contour.minX, -0.3, accuracy: 0.03)
        XCTAssertEqual(contour.minY, -0.3, accuracy: 0.03, "a contour fill grows across as much as along")
        XCTAssertFalse(rectangle(angle: 0, pull: 0, style: .contour).settings.hasStraightRows)
        XCTAssertTrue(rectangle(angle: 0, pull: 0, style: .satin).settings.hasStraightRows)
    }

    func testPushIsCheckedAndSavedAsVersionTwelve() throws {
        var design = Design(); design.objects = [rectangle(angle: 0, pull: 0.2)]
        XCTAssertFalse(design.needsSchemaTwelve, "pull alone sews in older versions too")
        design.objects[0].digitizing?.pushCompensation = 0.2
        XCTAssertTrue(design.needsSchemaTwelve)
        let reread = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reread.objects[0].settings.pushCompensation, 0.2)
        design.schemaVersion = 12
        XCTAssertNoThrow(try design.validate())
        var tooMuch = design; tooMuch.objects[0].digitizing?.pushCompensation = 3
        XCTAssertThrowsError(try tooMuch.validate())
    }
}
