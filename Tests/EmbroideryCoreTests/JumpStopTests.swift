// Stop at Jumps: Stop after on each object that ends in a jump, for machines without a thread cutter.
import XCTest
@testable import EmbroideryCore

final class JumpStopTests: XCTestCase {
    private func line(_ name: String, y: Double, from x: Double = -20, to end: Double = 20, color: ThreadColor = .palette[0]) -> RunObject {
        RunObject(name: name, nodes: [PathNode(Point(x, y)), PathNode(Point(end, y))], color: color)
    }
    private func design(_ objects: [RunObject]) -> Design { var design = Design(); design.objects = objects; return design }

    func testFindsObjectsThatJumpToTheNextInTheSameThread() throws {
        let objects = [line("A", y: -10), line("B", y: 0), line("C", y: 10)]
        let plan = try StitchEngine.compile(design(objects))
        XCTAssertEqual(plan.objectsEndingInJump, [objects[0].id, objects[1].id], "The last object has nowhere to jump to")
    }

    func testSkipsThreadChangesAndObjectsThatCarryStraightOn() throws {
        // A thread change pauses the machine already.
        let colors = [line("A", y: 0), line("B", y: 10, color: .palette[1])]
        XCTAssertEqual(try StitchEngine.compile(design(colors)).objectsEndingInJump, [])
        // The next object starts close by, so the thread isn't cut.
        let close = [line("A", y: 0, to: 0), line("B", y: 0, from: 0.5)]
        XCTAssertEqual(try StitchEngine.compile(design(close)).objectsEndingInJump, [])
    }

    func testAddingAndRemovingStops() throws {
        var placement = line("Placement", y: -10); placement.stopAfter = true   // a stop set by hand, as appliqué does
        var sample = design([placement, line("A", y: 0), line("B", y: 10), line("C", y: 20)])
        XCTAssertFalse(sample.hasJumpStops(in: nil))
        XCTAssertEqual(sample.addJumpStops(using: try StitchEngine.compile(sample), in: nil), 2, "A and B; Placement stops already")
        XCTAssertTrue(sample.hasJumpStops(in: nil))
        XCTAssertEqual(sample.objects.map(\.stopAfter), [true, true, true, false])
        XCTAssertEqual(ProductionSummary(plan: try StitchEngine.compile(sample), design: sample).stops, 3)

        XCTAssertEqual(sample.removeJumpStops(in: nil), 2)
        XCTAssertEqual(sample.objects.map(\.stopAfter), [true, false, false, false], "The hand-set stop stays")
        XCTAssertFalse(sample.hasJumpStops(in: nil))
    }

    func testOnlyTheChosenUnlockedObjects() throws {
        var locked = line("Locked", y: 10); locked.locked = true
        var sample = design([line("A", y: -10), line("B", y: 0), locked, line("D", y: 20)])
        let plan = try StitchEngine.compile(sample)
        let chosen: Set<UUID> = [sample.objects[1].id, sample.objects[2].id]
        XCTAssertEqual(sample.addJumpStops(using: plan, in: chosen), 1, "B only: A isn't chosen and Locked is locked")
        XCTAssertEqual(sample.objects.map(\.stopAfter), [false, true, false, false])
        XCTAssertFalse(sample.hasJumpStops(in: [sample.objects[0].id]))
        XCTAssertEqual(sample.removeJumpStops(in: [sample.objects[0].id]), 0)
        XCTAssertEqual(sample.removeJumpStops(in: chosen), 1)
    }

    func testTheMarkIsSavedWithTheDesign() throws {
        var sample = design([line("A", y: 0), line("B", y: 10)])
        _ = sample.addJumpStops(using: try StitchEngine.compile(sample), in: nil)
        var reopened = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(sample))
        XCTAssertEqual(reopened.objects[0].stopForJump, true)
        XCTAssertEqual(reopened.removeJumpStops(in: nil), 1, "Reopened, the button can still take its stop off")
    }
}
