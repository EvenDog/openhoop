// Checks the stitches that hold the fabric: the basting box (sewn first, around the design, in the first thread,
// inside the hoop) and laydown (open fills under the design, joined across gaps, with crossed layers).
import XCTest
@testable import EmbroideryCore

final class FabricHoldingTests: XCTestCase {
    private func square(_ name: String, at center: Point, size: Double = 10, color: ThreadColor = ThreadColor.palette[0]) -> RunObject {
        let h = size / 2
        var object = RunObject(name: name, nodes: [Point(-h, -h), Point(h, -h), Point(h, h), Point(-h, h)].map { PathNode(center + $0) }, color: color)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }

    func testBastingBoxSewsFirstAroundTheDesignInTheFirstThread() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0), color: ThreadColor.palette[1]), square("B", at: Point(20, 0), color: ThreadColor.palette[2])]
        XCTAssertNil(design.bastingBox, "off unless switched on")
        design.basting = 5
        let box = try XCTUnwrap(design.bastingBox)
        XCTAssertEqual(box.nodes.map(\.point), [Point(-10, -10), Point(30, -10), Point(30, 10), Point(-10, 10)])
        XCTAssertEqual(box.color, ThreadColor.palette[1])
        XCTAssertTrue(design.needsSchemaFive, "an older version would leave the box out")

        let plan = try RunningEngine.compile(design)
        XCTAssertEqual(plan.commands.first { $0.op == .stitch }?.objectID, Design.bastingID, "the box sews before anything else")
        XCTAssertEqual(plan.threads.first, ThreadColor.palette[1])
        XCTAssertEqual(plan.commands.filter { $0.op == .colorChange }.count, 1, "no extra color change for the box")
        let boxStitches = plan.commands.filter { $0.objectID == Design.bastingID && $0.op == .stitch }.map(\.point)
        XCTAssertGreaterThan(zip(boxStitches, boxStitches.dropFirst()).map { $0.distance(to: $1) }.max() ?? 0, 4, "long basting stitches")
    }

    func testBastingBoxStaysInsideTheHoop() throws {
        var design = Design()
        design.hoop = Hoop(width: 50, height: 50)
        design.objects = [square("Big", at: Point(0, 0), size: 46)]
        design.basting = 10
        XCTAssertTrue(try XCTUnwrap(design.bastingBox).nodes.allSatisfy { design.hoop.contains($0.point) }, "cut back to the hoop's edge")
        design.hoop = Hoop(width: 60, height: 60, oval: true)
        design.objects = [square("Small", at: Point(0, 0), size: 20)]
        let corners = try XCTUnwrap(design.bastingBox).nodes.map(\.point)
        XCTAssertTrue(corners.allSatisfy { design.hoop.contains($0) }, "a smaller margin on an oval hoop")
        XCTAssertGreaterThan(corners[2].x, 10, "but still outside the design")
    }

    func testLaydownJoinsCloseShapesWithCrossedLayersUnderneath() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0)), square("B", at: Point(12, 0)), square("Far", at: Point(60, 0))]
        var settings = LaydownSettings(); settings.offset = 2
        let laydown = try design.laydown(under: [], settings: settings, color: ThreadColor.palette[4])
        XCTAssertEqual(laydown.count, 4, "A and B join (2 mm gap, grown 2 mm each), Far gets its own; two layers each")
        XCTAssertEqual(Set(laydown.map(\.groupID)).count, 1)
        XCTAssertEqual(laydown.map(\.settings.angle), [45, 135, 45, 135])
        XCTAssertTrue(laydown.allSatisfy { $0.settings.underlay == UnderlayStyle.none && $0.settings.spacing == 4 && $0.settings.rowGap == 2 && $0.color == ThreadColor.palette[4] })
        let joined = AreaGeometry.ring(laydown[0].nodes)
        XCTAssertTrue(AreaGeometry.contains(Point(6, 0), rings: [joined]), "the gap between A and B is covered")
        XCTAssertTrue(AreaGeometry.contains(Point(-6.5, 0), rings: [joined]), "it reaches 2 mm past the edge")
        XCTAssertFalse(AreaGeometry.contains(Point(-7.5, 0), rings: [joined]))

        var under = design
        under.addLaydown(try design.laydown(under: [design.objects[1].id], settings: settings, color: ThreadColor.palette[4]), under: [design.objects[1].id])
        XCTAssertEqual(under.objects.map(\.name), ["A", "Laydown 1", "Laydown 2", "B", "Far"], "under the selection, it sews just before it")
        XCTAssertGreaterThan(try RunningEngine.compile(under).stitchCount, 0)
    }
}
