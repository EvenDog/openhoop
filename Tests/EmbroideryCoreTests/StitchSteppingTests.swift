// Checks stepping the stitch player: by stitches (skipping jumps and trims), and on to the next or back to the
// previous color, object and trim.
import XCTest
@testable import EmbroideryCore

final class StitchSteppingTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()
    /// Object A (3 stitches) and object B (2) in thread 0, a trim between them, then a color change and object C
    /// (3 stitches) in thread 1. The numbers are each command's index.
    private var plan: StitchPlan {
        var plan = StitchPlan()
        let p = Point(0, 0)
        plan.commands = [
            StitchCommand(.stitch, p, thread: 0, objectID: a), StitchCommand(.stitch, p, thread: 0, objectID: a), StitchCommand(.stitch, p, thread: 0, objectID: a),   // 0–2
            StitchCommand(.trim, p, thread: 0), StitchCommand(.jump, p, thread: 0),                                                                                   // 3–4
            StitchCommand(.stitch, p, thread: 0, objectID: b), StitchCommand(.stitch, p, thread: 0, objectID: b),                                                     // 5–6
            StitchCommand(.colorChange, p, thread: 1),                                                                                                                 // 7
            StitchCommand(.stitch, p, thread: 1, objectID: c), StitchCommand(.stitch, p, thread: 1, objectID: c), StitchCommand(.stitch, p, thread: 1, objectID: c)    // 8–10
        ]
        return plan
    }

    func testStitchStepsSkipJumpsAndTrims() {
        XCTAssertEqual(plan.position(after: .stitches(1), from: 0), 1)
        XCTAssertEqual(plan.position(after: .stitches(1), from: 3), 6, "past the trim and jump to B's first stitch")
        XCTAssertEqual(plan.position(after: .stitches(-1), from: 6), 5, "B's first stitch off")
        XCTAssertEqual(plan.position(after: .stitches(-1), from: 5), 2, "back over the jump and trim, leaving A's last stitch off")
        XCTAssertEqual(plan.position(after: .stitches(10), from: 0), 11, "stops at the end")
        XCTAssertEqual(plan.position(after: .stitches(-10), from: 11), 0, "stops at the start")
        XCTAssertEqual(plan.position(after: .end, from: 4), 11)
    }

    func testColorStepsGoToTheStartOfEachColor() {
        XCTAssertEqual(plan.position(after: .color(forward: true), from: 0), 8, "thread 1 starts at C's first stitch")
        XCTAssertEqual(plan.position(after: .color(forward: true), from: 8), 11, "no more colors: the end")
        XCTAssertEqual(plan.position(after: .color(forward: false), from: 10), 8, "back to the start of this color")
        XCTAssertEqual(plan.position(after: .color(forward: false), from: 8), 0, "from its start, back to the one before")
    }

    func testObjectStepsGoToTheStartOfEachObject() {
        XCTAssertEqual(plan.position(after: .object(forward: true), from: 1), 5)
        XCTAssertEqual(plan.position(after: .object(forward: true), from: 5), 8)
        XCTAssertEqual(plan.position(after: .object(forward: false), from: 9), 8)
        XCTAssertEqual(plan.position(after: .object(forward: false), from: 8), 5)
    }

    func testTrimStepsStopJustPastEachTrim() {
        XCTAssertEqual(plan.position(after: .trim(forward: true), from: 0), 4, "the trim at 3 shown, nothing after")
        XCTAssertEqual(plan.position(after: .trim(forward: true), from: 4), 11, "no more trims: the end")
        XCTAssertEqual(plan.position(after: .trim(forward: false), from: 9), 4)
        XCTAssertEqual(plan.position(after: .trim(forward: false), from: 4), 0)
    }

    func testAnEmptyPlanStaysPut() {
        XCTAssertEqual(StitchPlan().position(after: .stitches(1), from: 0), 0)
        XCTAssertEqual(StitchPlan().position(after: .color(forward: true), from: 0), 0)
    }
}
