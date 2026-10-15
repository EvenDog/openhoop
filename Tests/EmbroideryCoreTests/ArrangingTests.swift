// Exact arranging: the box around a selection, moving by an exact amount, and turning by any angle.
import XCTest
@testable import EmbroideryCore

final class ArrangingTests: XCTestCase {
    private func square(_ name: String, at center: Point, size: Double = 10) -> RunObject {
        let h = size / 2
        var object = RunObject(name: name, nodes: [Point(-h, -h), Point(h, -h), Point(h, h), Point(-h, h)].map { PathNode(center + $0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }

    func testBoundsAndMovingLeaveOtherObjectsAlone() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0)), square("B", at: Point(20, 10)), square("C", at: Point(-30, 0))]
        let ids: Set = [design.objects[0].id, design.objects[1].id]
        let box = try XCTUnwrap(design.bounds(of: ids))
        XCTAssertEqual(box.min, Point(-5, -5)); XCTAssertEqual(box.max, Point(25, 15))
        design.move(ids, by: Point(5, -2))
        let moved = try XCTUnwrap(design.bounds(of: ids))
        XCTAssertEqual(moved.min, Point(0, -7)); XCTAssertEqual(moved.max, Point(30, 13))
        XCTAssertEqual(design.objects[2].nodes[0].point, Point(-35, -5), "Unselected objects stay put")
        XCTAssertNil(design.bounds(of: []))
    }

    func testTurningByAnyAngleTurnsEverythingThatBelongsToTheObject() throws {
        var object = square("Patch", at: Point(10, 0), size: 20)
        object.holes = [[Point(8, -2), Point(12, -2), Point(12, 2), Point(8, 2)].map { PathNode($0) }]
        object.entry = Point(0, -10)
        object.digitizing?.fillStyle = .radial; object.digitizing?.radialCenter = Point(15, 0)
        var design = Design(); design.objects = [object]
        let id: Set = [object.id]
        design.rotate(id, by: 90, around: Point(10, 0))
        let turned = design.objects[0]
        XCTAssertEqual(turned.nodes[0].point.x, 20, accuracy: 1e-9); XCTAssertEqual(turned.nodes[0].point.y, -10, accuracy: 1e-9)
        XCTAssertEqual(turned.entry!.x, 20, accuracy: 1e-9); XCTAssertEqual(turned.entry!.y, -10, accuracy: 1e-9)
        XCTAssertEqual(turned.settings.radialCenter!.x, 10, accuracy: 1e-9); XCTAssertEqual(turned.settings.radialCenter!.y, 5, accuracy: 1e-9)
        XCTAssertEqual(turned.holes![0][0].point.x, 12, accuracy: 1e-9); XCTAssertEqual(turned.holes![0][0].point.y, -2, accuracy: 1e-9)
        XCTAssertEqual(turned.settings.angle, 135, accuracy: 1e-9, "Fill rows turn with the shape")
        // An odd angle and back again returns to where it started; the fill still sews.
        design.rotate(id, by: 33.5, around: Point(3, 4)); design.rotate(id, by: -33.5, around: Point(3, 4))
        for (a, b) in zip(design.objects[0].allNodes, turned.allNodes) { XCTAssertEqual(a.point.distance(to: b.point), 0, accuracy: 1e-9) }
        XCTAssertEqual(design.objects[0].settings.angle, 135, accuracy: 1e-9)
        design.rotate(id, by: 200, around: Point(0, 0))
        XCTAssertEqual(design.objects[0].settings.angle, -25, accuracy: 1e-9, "Angles stay between -180° and 180°")
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100)
    }

    func testImportedStitchesTurnToo() {
        var object = RunObject(name: "Imported", nodes: [])
        object.rawStitches = RawStitchBlock(start: Point(1, 2), commands: [RawStitch(.stitch, Point(3, 4))], sourceFormat: "dst")
        var design = Design(); design.objects = [object]
        design.rotate([object.id], by: 180, around: Point(0, 0))
        XCTAssertEqual(design.objects[0].rawStitches!.start.x, -1, accuracy: 1e-9)
        XCTAssertEqual(design.objects[0].rawStitches!.commands[0].point.y, -4, accuracy: 1e-9)
    }

    func testSequenceBySelectionOrderSewsInClickOrderFromTheFirstPlace() {
        var design = Design()
        design.objects = ["A", "B", "C", "D", "E"].map { square($0, at: Point(0, 0)) }
        let id = Dictionary(uniqueKeysWithValues: design.objects.map { ($0.name, $0.id) })
        design.sequence([id["E"]!, id["B"]!, id["D"]!])   // clicked E, then B, then D
        XCTAssertEqual(design.objects.map(\.name), ["A", "E", "B", "D", "C"], "they start where B (the earliest) sewed")
        design.sequence([])
        XCTAssertEqual(design.objects.map(\.name), ["A", "E", "B", "D", "C"])
    }

    func testAlignLinesUpWithTheLastSelectedAndMovesGroupsAsOne() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0), size: 10), square("B", at: Point(30, 20), size: 4), square("C", at: Point(-20, 5), size: 6),
                          square("D", at: Point(-20, -20), size: 6)]
        let group = UUID(); design.objects[2].groupID = group; design.objects[3].groupID = group   // C and D are one group
        let (a, b, c, d) = (design.objects[0].id, design.objects[1].id, design.objects[2].id, design.objects[3].id)
        XCTAssertEqual(design.arrangeUnits([b, c, d, a]), [[b], [c, d], [a]])

        var left = design; left.align([b, c, d, a], .left)   // A was selected last: its left edge is at -5
        XCTAssertEqual(try XCTUnwrap(left.bounds(of: [b])).min.x, -5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(left.bounds(of: [c, d])).min.x, -5, accuracy: 1e-9)
        XCTAssertEqual(left.objects[3].nodes[0].point.y, -23, accuracy: 1e-9, "the group moved as one: D only slid across")
        XCTAssertEqual(left.objects[0].nodes, design.objects[0].nodes, "the last one selected stays put")

        var top = design; top.align([a, b], .top)   // B last: its top is at 22
        XCTAssertEqual(try XCTUnwrap(top.bounds(of: [a])).max.y, 22, accuracy: 1e-9)
        var centers = design; centers.align([b, a], .centers)
        let box = try XCTUnwrap(centers.bounds(of: [b]))
        XCTAssertEqual((box.min + box.max) * 0.5, Point(0, 0))

        var locked = design; locked.objects[1].locked = true; locked.align([b, a], .left)
        XCTAssertEqual(locked.objects[1].nodes, design.objects[1].nodes, "locked objects don't move")
    }

    func testSpaceEvenlyMakesEqualGapsAndKeepsTheOuterTwo() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0), size: 10), square("B", at: Point(12, 0), size: 4), square("C", at: Point(40, 3), size: 10)]
        let ids = design.objects.map(\.id)
        design.spaceEvenly(ids, across: true)   // A spans -5…5, C 35…45: 30 mm free minus B's 4 = 26, gaps of 13
        XCTAssertEqual(try XCTUnwrap(design.bounds(of: [ids[1]])).min.x, 18, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(design.bounds(of: [ids[2]])).min.x, 35, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(design.bounds(of: [ids[1]])).min.y, -2, accuracy: 1e-9, "spacing across doesn't move up or down")

        var two = Design(); two.objects = Array(design.objects.prefix(2))
        let before = two.objects; two.spaceEvenly(two.objects.map(\.id), across: true)
        XCTAssertEqual(two.objects, before, "two objects have nothing to space")
    }

    func testSkewLeansSidewaysAndFillRowsLeanAlong() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0), size: 10)]
        design.objects[0].digitizing?.angle = 90   // upright rows
        let id = design.objects[0].id
        design.skew([id], by: 45, around: Point(0, 0))
        for (point, expected) in zip(design.objects[0].nodes.map(\.point), [Point(-10, -5), Point(0, -5), Point(10, 5), Point(0, 5)]) {
            XCTAssertEqual(point.distance(to: expected), 0, accuracy: 1e-9, "the top slides right, the bottom left")
        }
        XCTAssertEqual(design.objects[0].settings.angle, 45, accuracy: 1e-9, "upright rows lean over by the same 45°")
        design.skew([id], by: -45, around: Point(0, 0))
        XCTAssertEqual(design.objects[0].nodes[2].point.x, 5, accuracy: 1e-9, "skewing back undoes it")
        XCTAssertEqual(design.objects[0].settings.angle, 90, accuracy: 1e-9)
    }
}
