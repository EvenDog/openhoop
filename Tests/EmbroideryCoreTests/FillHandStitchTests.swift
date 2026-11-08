// Hand stitch for fills: each needle hole inside a row moves a little at random, along the row and across it, so the
// rows look sewn by hand. The ends of rows, the underlay and the outline stay as they are; the same Variant always
// gives the same stitches; and a project with it is file version 22.
import XCTest
@testable import EmbroideryCore

final class FillHandStitchTests: XCTestCase {
    private func fill(_ hand: FillHandStitch?) -> RunObject {
        var object = RunObject(name: "Fill", nodes: ShapeGeometry.nodes(.ellipse, in: (Point(-20, -15), Point(20, 15))))
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill); object.stitchLength = 4
        object.digitizing?.fillHandStitch = hand
        return object
    }
    private func stitches(_ object: RunObject) throws -> ObjectStitches { try StitchEngine.fresh(object, under: []) }

    func testItMovesHolesInsideRowsButNotTheUnderlayOrTheShape() throws {
        let plain = try stitches(fill(nil)), hand = try stitches(fill(FillHandStitch()))
        XCTAssertEqual(plain.sections.count, hand.sections.count)
        var moved = 0
        for (a, b) in zip(plain.sections, hand.sections) {
            XCTAssertEqual(a.points.count, b.points.count, "no stitches added or taken away")
            if a.underlay { XCTAssertEqual(a.points, b.points, "underlay stays as it is"); continue }
            XCTAssertEqual(a.points.first, b.points.first); XCTAssertEqual(a.points.last, b.points.last)
            let shifted = zip(a.points, b.points).filter { $0.distance(to: $1) > 0.01 }.map(\.1)
            moved += shifted.count
            // (Row ends reach a little past the outline, for pull compensation; those don't move.)
            let rings = fill(nil).areaRings!
            XCTAssertTrue(shifted.allSatisfy { AreaGeometry.contains($0, rings: rings) }, "every moved hole stays inside the shape")
        }
        XCTAssertGreaterThan(moved, 100)
    }

    func testTheSameVariantSewsTheSameAndAnotherDoesNot() throws {
        // The same fill: the random numbers start from the object's id.
        let object = fill(FillHandStitch())
        var other = object; other.digitizing?.fillHandStitch?.variant = 2
        let once = try stitches(object).sections.flatMap(\.points)
        let again = try stitches(object).sections.flatMap(\.points)
        let changed = try stitches(other).sections.flatMap(\.points)
        XCTAssertEqual(once, again)
        XCTAssertNotEqual(once, changed)
    }

    func testStrongerMovesHolesFurther() throws {
        let plain = try stitches(fill(nil)).sections.filter { !$0.underlay }.flatMap(\.points)
        func average(_ strength: FillHandStitch.Strength) throws -> Double {
            var hand = FillHandStitch(); hand.strength = strength
            let points = try stitches(fill(hand)).sections.filter { !$0.underlay }.flatMap(\.points)
            return zip(plain, points).reduce(0) { $0 + $1.0.distance(to: $1.1) } / Double(plain.count)
        }
        let light = try average(.light), medium = try average(.medium), strong = try average(.strong)
        XCTAssertLessThan(light, medium); XCTAssertLessThan(medium, strong)
    }

    func testItNeedsFileVersion22AndOnlyFillsTakeIt() throws {
        var design = Design(); design.objects = [fill(FillHandStitch())]
        XCTAssertTrue(design.needsSchemaTwentyTwo)
        design.schemaVersion = 22; XCTAssertNoThrow(try design.validate())
        let saved = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(saved.objects[0].settings.fillHandStitch, FillHandStitch())
        design.objects[0].digitizing?.fillHandStitch?.variant = 11
        XCTAssertThrowsError(try design.validate(), "variants are 1–10")
        var line = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))])
        line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.fillHandStitch = FillHandStitch()
        design.objects = [line]
        XCTAssertThrowsError(try design.validate(), "only fills have a fill hand stitch")
        design.objects = [fill(nil)]
        XCTAssertFalse(design.needsSchemaTwentyTwo)
    }
}
