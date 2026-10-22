// Checks the steps Review Sewing Order walks through: one per object (lettering is one), each with where it starts
// and ends, and how the needle gets there from the step before.
import XCTest
@testable import EmbroideryCore

final class SewingReviewTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    /// A sews 2 stitches, trims and jumps to B (in the same thread); then a color change and an untrimmed jump to C;
    /// then D carries straight on from C with a plain stitch. The numbers are each command's index.
    private var plan: StitchPlan {
        var plan = StitchPlan()
        plan.commands = [
            StitchCommand(.stitch, Point(0, 0), thread: 0, objectID: a), StitchCommand(.stitch, Point(3, 0), thread: 0, objectID: a),   // 0–1
            StitchCommand(.trim, Point(3, 0), thread: 0, objectID: a), StitchCommand(.jump, Point(3, 4), thread: 0, objectID: b),       // 2–3
            StitchCommand(.stitch, Point(3, 4), thread: 0, objectID: b), StitchCommand(.stitch, Point(3, 8), thread: 0, objectID: b),   // 4–5
            StitchCommand(.colorChange, Point(3, 8), thread: 1, objectID: c), StitchCommand(.jump, Point(9, 8), thread: 1, objectID: c), // 6–7
            StitchCommand(.stitch, Point(9, 8), thread: 1, objectID: c),                                                                 // 8
            StitchCommand(.stitch, Point(10, 8), thread: 1, objectID: d), StitchCommand(.stitch, Point(12, 8), thread: 1, objectID: d), // 9–10
            StitchCommand(.end, Point(12, 8), thread: 1)                                                                                 // 11
        ]
        return plan
    }

    func testEachObjectIsAStepWithItsStartAndEnd() {
        let steps = Design().sewingSteps(plan: plan)
        XCTAssertEqual(steps.map(\.objects), [[a], [b], [c], [d]])
        XCTAssertEqual(steps.map(\.commands), [0..<2, 4..<6, 8..<9, 9..<11])
        XCTAssertEqual(steps.map(\.stitches), [2, 2, 1, 2])
        XCTAssertEqual(steps[1].start, Point(3, 4)); XCTAssertEqual(steps[1].end, Point(3, 8))
    }

    func testTravelSaysHowTheNeedleGetsToEachStep() throws {
        let steps = Design().sewingSteps(plan: plan)
        XCTAssertNil(steps[0].travel, "nothing comes before the first step")
        let toB = try XCTUnwrap(steps[1].travel)
        XCTAssertEqual(toB.from, Point(3, 0)); XCTAssertEqual(toB.length, 4, accuracy: 1e-9)
        XCTAssertTrue(toB.trimmed); XCTAssertTrue(toB.jumped); XCTAssertFalse(toB.colorChange)
        let toC = try XCTUnwrap(steps[2].travel)
        XCTAssertEqual(toC.length, 6, accuracy: 1e-9)
        XCTAssertFalse(toC.trimmed, "a jump with no trim"); XCTAssertTrue(toC.jumped); XCTAssertTrue(toC.colorChange)
        let toD = try XCTUnwrap(steps[3].travel)
        XCTAssertEqual(toD.length, 1, accuracy: 1e-9)
        XCTAssertFalse(toD.trimmed || toD.jumped || toD.colorChange || toD.stopped, "a plain stitch carries the thread across")
    }

    func testLetteringIsOneStep() throws {
        let ink = ThreadColor.palette[0]
        let spec = LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica-Bold", height: 12)
        var design = Design()
        let line = RunObject(name: "Line", nodes: [PathNode(Point(-20, 20)), PathNode(Point(20, 20))], color: ink)
        design.objects = try spec.build(color: ink, embroideryFonts: []).objects + [line]
        let steps = design.sewingSteps(plan: try RunningEngine.compile(design))
        let letters = design.letteringObjects(spec.id).map(\.id)
        XCTAssertGreaterThan(letters.count, 1)
        XCTAssertEqual(steps.map(\.objects), [letters, [line.id]])
    }

    func testLongMovesAndUntrimmedJumpsAreWarnedAbout() {
        func travel(_ length: Double, trimmed: Bool = true, jumped: Bool = true, colorChange: Bool = false) -> SewingTravel {
            SewingTravel(from: Point(0, 0), length: length, trimmed: trimmed, jumped: jumped, colorChange: colorChange, stopped: false)
        }
        XCTAssertNil(travel(14.9).warning(trimDistance: 3), "a short trimmed move")
        XCTAssertEqual(travel(18.6).warning(trimDistance: 3), .longMove(18.6))
        XCTAssertNil(travel(30, colorChange: true).warning(trimDistance: 3), "the machine starts afresh for a new thread")
        XCTAssertNil(travel(30, trimmed: false, colorChange: true).warning(trimDistance: 3))
        XCTAssertEqual(travel(6, trimmed: false).warning(trimDistance: 3), .untrimmedJump(6), "trimming would have cut it")
        XCTAssertNil(travel(2, trimmed: false).warning(trimDistance: 3), "shorter than the trim distance")
        XCTAssertEqual(travel(20, trimmed: false).warning(trimDistance: 3), .untrimmedJump(20), "the thread across matters more than the length")
        XCTAssertNil(travel(1, trimmed: false, jumped: false).warning(trimDistance: 3), "stitched across")
    }

    func testWarningsAreListedByStep() throws {
        // Three short lines across the hoop: the second 30 mm on from the first in the same thread, the third 30 mm on
        // again but in another thread.
        let ink = ThreadColor.palette[0], other = ThreadColor.palette[1]
        var design = Design()
        design.objects = [(-40.0, ink), (-10.0, ink), (20.0, other)].map { x, color in
            RunObject(name: "Line", nodes: [PathNode(Point(x, 0)), PathNode(Point(x + 10, 0))], color: color)
        }
        let warnings = design.sewingWarnings(design.sewingSteps(plan: try RunningEngine.compile(design)))
        XCTAssertEqual(Array(warnings.keys), [1], "only the long move in the same thread")
        guard case .longMove(let length)? = warnings[1] else { return XCTFail("a long move") }
        XCTAssertEqual(length, 20, accuracy: 0.5, "from the first line's end to the second's start")
    }
}
