// Checks Branching: objects are ordered nearest-next, share the first one's thread and a group, and sew without
// trims between them when they touch (travel runs inside their shapes), but still trim where they don't.
import XCTest
@testable import EmbroideryCore

final class BranchingTests: XCTestCase {
    private func square(_ name: String, at center: Point, color: ThreadColor) -> RunObject {
        var object = RunObject(name: name, nodes: [Point(-5, -5), Point(5, -5), Point(5, 5), Point(-5, 5)].map { PathNode(center + $0) }, color: color)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    private func trims(_ plan: StitchPlan) -> Int { plan.commands.filter { $0.op == .trim }.count }

    func testBranchedShapesThatTouchSewWithoutTrims() throws {
        var design = Design()
        // Overlapping squares in a row, in a jumbled sewing order and three threads.
        design.objects = [square("A", at: Point(0, 0), color: ThreadColor.palette[0]), square("C", at: Point(16, 0), color: ThreadColor.palette[1]),
                          square("B", at: Point(8, 0), color: ThreadColor.palette[2])]
        let separate = try RunningEngine.compile(design)
        let ids = try design.branch(Set(design.objects.map(\.id)), entry: nil, exit: nil)
        XCTAssertEqual(design.objects.map(\.name), ["A", "B", "C"], "each next is the nearest left")
        XCTAssertEqual(ids, design.objects.map(\.id))
        XCTAssertTrue(design.objects.allSatisfy { $0.color == ThreadColor.palette[0] && $0.groupID != nil && $0.branchID == design.objects[0].branchID })
        XCTAssertTrue(design.needsSchemaFive)
        let plan = try RunningEngine.compile(design)
        XCTAssertEqual(trims(plan), 1, "one trim at the very end, none between")
        XCTAssertGreaterThan(trims(separate), 1)
        XCTAssertEqual(plan.commands.filter { $0.op == .colorChange }.count, 0)
        XCTAssertEqual(plan.commands.filter { $0.op == .jump }.count, 1, "only the first jump, to the start")
    }

    func testBranchedLinesTravelAlongEachOther() throws {
        var design = Design()
        let trunk = RunObject(name: "Trunk", nodes: [PathNode(Point(0, 0)), PathNode(Point(30, 0))], color: ThreadColor.palette[0])
        let twig = RunObject(name: "Twig", nodes: [PathNode(Point(15, 0)), PathNode(Point(15, 12))], color: ThreadColor.palette[0])
        design.objects = [trunk, twig]
        _ = try design.branch(Set(design.objects.map(\.id)), entry: Point(0, 0), exit: nil)
        let plan = try RunningEngine.compile(design)
        XCTAssertEqual(trims(plan), 1)
        let stitches = plan.commands.filter { $0.op == .stitch }.map(\.point)
        XCTAssertLessThanOrEqual(zip(stitches, stitches.dropFirst()).map { $0.distance(to: $1) }.max() ?? 0, 3, "no long jump across: it travels back along the trunk")
    }

    /// Stitches edited by hand survive branching: that object keeps its start and end points, and the next object
    /// starts where the edited stitches finish.
    func testBranchingKeepsHandEditedStitches() throws {
        var design = Design()
        var edited = square("A", at: Point(0, 0), color: ThreadColor.palette[0])
        let handPlaced = [Point(-4, -4), Point(4, -4), Point(4, 4), Point(3, 2)]
        edited.stitchEdits = StitchEdits(sections: [.init(points: handPlaced)], signature: edited.stitchSignature)
        design.objects = [edited, square("B", at: Point(8, 0), color: ThreadColor.palette[1])]
        _ = try design.branch(Set(design.objects.map(\.id)), entry: Point(-4, -4), exit: nil)
        XCTAssertTrue(design.objects[0].hasCurrentStitchEdits, "the hand edits still apply")
        XCTAssertTrue(design.dropStaleStitchEdits().isEmpty)
        XCTAssertEqual(design.objects[1].entry, Point(3, 2), "the next object starts where the edited stitches finish")
    }

    /// A line in the middle of a branch has its old end point cleared, so it finishes at the end its start leaves.
    func testBranchingClearsOldEndPointsOnLinesAndSatins() throws {
        var design = Design()
        var trunk = RunObject(name: "Trunk", nodes: [PathNode(Point(0, 0)), PathNode(Point(30, 0))], color: ThreadColor.palette[0])
        trunk.exit = Point(0, 0)   // left from before: would turn the trunk around, away from the twig
        let twig = RunObject(name: "Twig", nodes: [PathNode(Point(30, 2)), PathNode(Point(30, 12))], color: ThreadColor.palette[0])
        design.objects = [trunk, twig]
        _ = try design.branch(Set(design.objects.map(\.id)), entry: Point(0, 0), exit: nil)
        XCTAssertNil(design.objects[0].exit)
        XCTAssertEqual(try RunningEngine.stitches(for: design.objects[0].sewingOrder()).last, Point(30, 0), "the trunk finishes beside the twig")
    }

    func testBranchedShapesFarApartStillTrim() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0), color: ThreadColor.palette[0]), square("Far", at: Point(40, 0), color: ThreadColor.palette[0])]
        _ = try design.branch(Set(design.objects.map(\.id)), entry: nil, exit: nil)
        let plan = try RunningEngine.compile(design)
        XCTAssertEqual(trims(plan), 2, "no route between them, so it trims (after tying off)")
    }

    func testPastedCopiesOfABranchAreTheirOwnBranch() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0), color: ThreadColor.palette[0]), square("B", at: Point(8, 0), color: ThreadColor.palette[0])]
        _ = try design.branch(Set(design.objects.map(\.id)), entry: nil, exit: nil)
        let original = try XCTUnwrap(design.objects[0].branchID)
        design.paste(design.copying(Set(design.objects.map(\.id))), offset: Point(3, -3))
        let copies = design.objects.suffix(2).map(\.branchID)
        XCTAssertEqual(Set(copies).count, 1, "the copies stay one branch")
        XCTAssertNotNil(copies[0]); XCTAssertNotEqual(copies[0], original, "but not the original's")
        XCTAssertEqual(trims(try RunningEngine.compile(design)), 2, "a trim after each branch: the copy doesn't travel on from the original")
    }

    func testABranchedFillWithNothingLeftToSewStillGetsTheThreadCut() throws {
        // B hands on from A in a branch, but everything in it is covered by C (sewn on top), so it sews nothing:
        // A must still tie off and trim before the jump to C.
        var design = Design()
        design.objects = [square("A", at: Point(0, 0), color: ThreadColor.palette[0]), square("B", at: Point(8, 0), color: ThreadColor.palette[0])]
        _ = try design.branch(Set(design.objects.map(\.id)), entry: nil, exit: nil)
        design.objects[1].digitizing?.cutOutOverlaps = true
        var cover = square("C", at: Point(30, 0), color: ThreadColor.palette[0]); cover.nodes = [Point(2, -7), Point(14, -7), Point(14, 7), Point(2, 7)].map { PathNode($0) }
        design.objects.append(cover)
        let plan = try RunningEngine.compile(design)
        let jump = try XCTUnwrap(plan.commands.lastIndex { $0.op == .jump })
        XCTAssertEqual(plan.commands[jump - 1].op, .trim, "the thread is cut before jumping to C")
        let (end, lock, back) = (plan.commands[jump - 4].point, plan.commands[jump - 3].point, plan.commands[jump - 2].point)
        XCTAssertEqual(back, end, "after a tie-off: out and back into the same hole")
        XCTAssertTrue((0.3...0.601).contains(lock.distance(to: end)), "a lock stitch up to 0.6 mm long")
    }
}
