// Checks Scatter: copies land inside the area, clear of its edge and of each other, at sizes between the limits,
// turned or upright as asked; the same seed gives the same layout and another seed a new one; the area and the
// originals are used up; and what it refuses.
import XCTest
@testable import EmbroideryCore

final class ScatterTests: XCTestCase {
    /// A 4 × 2 mm filled tile centered on `center`, stitched at angle 0.
    func tile(_ center: Point = Point(80, 80), color: ThreadColor = ThreadColor.palette[0]) -> RunObject {
        var o = RunObject(name: "Tile", nodes: [Point(-2, -1), Point(2, -1), Point(2, 1), Point(-2, 1)].map { PathNode(center + $0) }, color: color)
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.angle = 0
        return o
    }
    /// A filled `size` mm square from the origin, as the area.
    func square(_ size: Double = 60) -> RunObject {
        var o = RunObject(name: "Area", nodes: [Point(0, 0), Point(size, 0), Point(size, size), Point(0, size)].map { PathNode($0) })
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill)
        return o
    }
    func scattered(_ settings: ScatterSettings = ScatterSettings(), area: RunObject? = nil) throws -> (design: Design, placed: Int) {
        let t = tile(), a = area ?? square()
        var design = Design(); design.objects = [t, a]
        let result = try design.scatter([t.id, a.id], inside: a.id, settings)
        return (design, result.placed)
    }
    func box(_ design: Design, _ object: RunObject) -> (min: Point, max: Point) { design.bounds(of: [object.id])! }

    func testCopiesLandInsideTheAreaAndApartAtTheirSizes() throws {
        var settings = ScatterSettings(); settings.copies = 30; settings.smallest = 50; settings.largest = 150; settings.gap = 1
        let (design, placed) = try scattered(settings)
        XCTAssertEqual(placed, 30, "plenty of room for 30 small tiles")
        XCTAssertEqual(design.objects.count, 30, "the area and the original are used up")
        XCTAssertFalse(design.objects.contains { $0.name == "Area" })
        XCTAssertEqual(Set(design.objects.map(\.groupID)).count, 1); XCTAssertNotNil(design.objects[0].groupID)
        let boxes = design.objects.map { box(design, $0) }
        for b in boxes { XCTAssertTrue(b.min.x >= 1 - 0.001 && b.min.y >= 1 - 0.001 && b.max.x <= 59.001 && b.max.y <= 59.001, "inside, a gap from the edge") }
        // The tile's area (8 mm²) scaled by the size squared: between 0.5² and 1.5² of it.
        for o in design.objects {
            let area = abs(AreaGeometry.ring(o.nodes).enumerated().reduce(0.0) { s, e in let r = AreaGeometry.ring(o.nodes); let n = r[(e.offset + 1) % r.count]; return s + e.element.x * n.y - n.x * e.element.y }) / 2
            XCTAssertGreaterThanOrEqual(area, 8 * 0.25 - 0.01); XCTAssertLessThanOrEqual(area, 8 * 2.25 + 0.01)
        }
        // Kept apart: no two copies' middles closer than the gap (their circles hold them, so they never touch).
        let middles = boxes.map { ($0.min + $0.max) * 0.5 }
        for i in middles.indices { for j in middles.indices where j > i { XCTAssertGreaterThan(middles[i].distance(to: middles[j]), 1) } }
        XCTAssertNoThrow(try RunningEngine.compile(design))
    }

    func testUprightKeepsTheRowsAndTheShape() throws {
        var settings = ScatterSettings(); settings.turns = false; settings.smallest = 100; settings.largest = 100
        let (design, _) = try scattered(settings)
        for o in design.objects {
            let b = box(design, o)
            XCTAssertEqual(b.max.x - b.min.x, 4, accuracy: 0.001); XCTAssertEqual(b.max.y - b.min.y, 2, accuracy: 0.001)
            XCTAssertEqual(o.settings.angle, 0, accuracy: 0.001)
        }
        settings.turns = true
        let turned = try scattered(settings).design
        XCTAssertTrue(turned.objects.contains { abs($0.settings.angle) > 1 }, "rows turn with the copies")
    }

    func testSameSeedSameLayoutAndShufflePicksAnother() throws {
        var settings = ScatterSettings()
        let one = try scattered(settings).design, again = try scattered(settings).design
        XCTAssertEqual(one.objects.map(\.nodes), again.objects.map(\.nodes))
        settings.seed += 1
        XCTAssertNotEqual(try scattered(settings).design.objects.map(\.nodes), one.objects.map(\.nodes))
    }

    func testFewerFitThanAskedWhenTheAreaIsSmall() throws {
        var settings = ScatterSettings(); settings.copies = 100; settings.smallest = 100; settings.largest = 100; settings.gap = 0.5
        let (design, placed) = try scattered(settings, area: square(15))
        XCTAssertLessThan(placed, 100)
        XCTAssertGreaterThan(placed, 0)
        XCTAssertEqual(design.objects.count, placed)
    }

    func testHolesStayEmpty() throws {
        var ring = square(60)
        ring.holes = [[Point(20, 20), Point(40, 20), Point(40, 40), Point(20, 40)].map { PathNode($0) }]
        var settings = ScatterSettings(); settings.copies = 40
        let (design, _) = try scattered(settings, area: ring)
        for o in design.objects {
            let b = box(design, o), m = (b.min + b.max) * 0.5
            XCTAssertFalse(m.x > 20 && m.x < 40 && m.y > 20 && m.y < 40, "nothing in the hole")
        }
    }

    func testSewnOneColorAtATimeNearestNext() throws {
        let a = tile(Point(80, 80), color: ThreadColor.palette[0]), b = tile(Point(80, 84), color: ThreadColor.palette[1]), area = square()
        var design = Design(); design.objects = [a, b, area]
        var settings = ScatterSettings(); settings.copies = 6
        try design.scatter([a.id, b.id, area.id], inside: area.id, settings)
        XCTAssertEqual(design.objects.prefix(6).map(\.color), Array(repeating: ThreadColor.palette[0], count: 6))
        XCTAssertEqual(design.objects.suffix(6).map(\.color), Array(repeating: ThreadColor.palette[1], count: 6))
    }

    func testRefusesWhatItCantDo() {
        let t = tile()
        var line = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(40, 0))]); line.digitizing = DigitizingSettings(kind: .run)
        var design = Design(); design.objects = [t, line]
        XCTAssertThrowsError(try design.scatter([t.id, line.id], inside: line.id, ScatterSettings()), "an open line has no inside")
        let tiny = square(3)
        design.objects = [t, tiny]
        XCTAssertThrowsError(try design.scatter([t.id, tiny.id], inside: tiny.id, ScatterSettings()), "nothing fits")
        var bad = ScatterSettings(); bad.smallest = 200; bad.largest = 100
        let area = square()
        design.objects = [t, area]
        XCTAssertThrowsError(try design.scatter([t.id, area.id], inside: area.id, bad))
    }
}
