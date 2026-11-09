// Checks Make Redwork: touching running lines become one continuous bean line that leaves nothing out, lines that
// don't touch stay apart (grouped), only plain running lines are accepted, and the stretches the route sews a
// second time are sewn once, not three times. Also the file version that setting needs.
import XCTest
@testable import EmbroideryCore

final class RedworkTests: XCTestCase {
    private func line(_ from: Point, _ to: Point) -> RunObject { RunObject(name: "Line", nodes: [PathNode(from), PathNode(to)]) }
    /// A 20 mm square window with a cross through it: 6 lines that all touch, with four junctions where three meet.
    private func window() -> [RunObject] {
        var frame = RunObject(name: "Frame", nodes: ShapeGeometry.nodes(.rectangle, in: (Point(0, 0), Point(20, 20))))
        frame.closed = true
        return [frame, line(Point(10, 0), Point(10, 10)), line(Point(10, 10), Point(10, 20)), line(Point(0, 10), Point(10, 10)), line(Point(10, 10), Point(20, 10))]
    }

    func testTouchingLinesBecomeOneBeanLineThatLeavesNothingOut() throws {
        var design = Design(); design.objects = window()
        let before = design.objects.flatMap { RunningEngine.flatten($0.nodes, closed: $0.closed).flatMap { $0 } }
        let ids = try design.redwork(Set(design.objects.map(\.id)))
        XCTAssertEqual(ids.count, 1, "everything touches, so it's one line with no jumps")
        XCTAssertEqual(design.objects.count, 1)
        let redwork = design.objects[0]
        XCTAssertEqual(redwork.name, "Redwork"); XCTAssertEqual(redwork.settings.runPasses, 3); XCTAssertEqual(redwork.settings.retraceOnce, true)
        // Every point of the drawing is on the route.
        let route = RunningEngine.flatten(redwork.nodes, closed: redwork.closed).flatMap { $0 }
        for point in before {
            let gap = zip(route, route.dropFirst()).map { AreaGeometry.projection(point, $0.0, $0.1).distance(to: point) }.min()!
            XCTAssertLessThan(gap, 0.3, "\(point) is sewn")
        }
        XCTAssertNoThrow(try design.validate())
    }

    func testRetracedStretchesAreSewnOnce() throws {
        var design = Design(); design.objects = window()
        _ = try design.redwork(Set(design.objects.map(\.id)))
        let once = try RunningEngine.compile(design).stitchCount
        design.objects[0].digitizing?.retraceOnce = nil
        let bean = try RunningEngine.compile(design).stitchCount
        // Four junctions where three lines meet: pairing two of them up means sewing 20 mm (two 10 mm pieces) twice,
        // so 8 to 12 of its stitches (2.5 mm, or shorter where a curve node splits one) are sewn once instead of
        // three times, two fewer each.
        XCTAssertLessThan(once, bean)
        XCTAssertEqual(Double(bean - once), 20, accuracy: 4)
    }

    func testOnlyAStitchGoingBackOverTheLineCountsAsRetraced() {
        // Out 10 mm and straight back: the 4 stitches back are retraced, the 4 out aren't.
        let outAndBack = (0...4).map { Point(Double($0) * 2.5, 0) } + (0...3).reversed().map { Point(Double($0) * 2.5, 0.1) }
        XCTAssertEqual(RunningEngine.retraced(outAndBack), Set(5...8))
        // Crossing a line, or turning a sharp corner, isn't going back over it.
        let crossing = [Point(0, 0), Point(10, 0), Point(10, -5), Point(5, -5), Point(5, 5)]
        XCTAssertTrue(RunningEngine.retraced(crossing).isEmpty)
        let corner = [Point(0, 0), Point(10, 0), Point(0, 3)]
        XCTAssertTrue(RunningEngine.retraced(corner).isEmpty)
        // Bean ×3: the stitch back is sewn once, the stitch out three times.
        let sewn = try! RunningEngine.repeated([Point(0, 0), Point(2, 0), Point(0, 0)], passes: 3, retraceOnce: true)
        XCTAssertEqual(sewn.count, 1 + 3 + 1)
    }

    func testLinesThatDontTouchStayApartInOneGroup() throws {
        var design = Design(); design.objects = [line(Point(0, 0), Point(20, 0)), line(Point(10, 0), Point(10, 10)), line(Point(0, 30), Point(20, 30))]
        design.objects[0].color = ThreadColor("Red", 0xC0392B)
        let ids = try design.redwork(Set(design.objects.map(\.id)))
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(design.objects.map(\.name), ["Redwork 1", "Redwork 2"])
        XCTAssertEqual(Set(design.objects.map(\.groupID)).count, 1); XCTAssertNotNil(design.objects[0].groupID)
        XCTAssertTrue(design.objects.allSatisfy { $0.color.hex == 0xC0392B }, "the first line's thread")
    }

    func testOnlyPlainRunningLinesAreAccepted() {
        var design = Design(); design.objects = [line(Point(0, 0), Point(20, 0)), line(Point(10, 0), Point(10, 10))]
        let ids = Set(design.objects.map(\.id))
        XCTAssertTrue(design.canMakeRedwork(ids))
        XCTAssertFalse(design.canMakeRedwork([design.objects[0].id]), "one line has nothing to join")
        var styled = design; styled.objects[1].digitizing = DigitizingSettings(kind: .run); styled.objects[1].digitizing?.runStyle = .zigzag
        XCTAssertFalse(styled.canMakeRedwork(ids)); XCTAssertThrowsError(try styled.redwork(ids))
        var locked = design; locked.objects[1].locked = true
        XCTAssertFalse(locked.canMakeRedwork(ids))
        var fill = design; fill.objects[1].closed = true; fill.objects[1].digitizing = DigitizingSettings(kind: .fill)
        XCTAssertFalse(fill.canMakeRedwork(ids))
        var bean = design; bean.objects[1].digitizing = DigitizingSettings(kind: .run); bean.objects[1].digitizing?.runPasses = 5
        XCTAssertTrue(bean.canMakeRedwork(ids), "bean lines are running lines too")
    }

    func testItNeedsFileVersion24() throws {
        var design = Design(); design.objects = window()
        XCTAssertFalse(design.needsSchemaTwentyFour)
        _ = try design.redwork(Set(design.objects.map(\.id)))
        XCTAssertTrue(design.needsSchemaTwentyFour)
        design.schemaVersion = 24; XCTAssertNoThrow(try design.validate())
        let saved = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(saved.objects[0].settings.retraceOnce, true)
    }
}
