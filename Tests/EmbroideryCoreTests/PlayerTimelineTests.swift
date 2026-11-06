// Checks the stitch player's timeline: its color and object runs, its trim and stop marks, and which run the
// player is in at a given position, matching where Next Color and Next Object land.
import XCTest
@testable import EmbroideryCore

final class PlayerTimelineTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()
    /// A jump to the start, object A (2 stitches) in thread 0, a trim, object B (2) in thread 0, a stop, a color
    /// change, object C (2) in thread 1, then a trim at the very end. The numbers are each command's index.
    private var plan: StitchPlan {
        var plan = StitchPlan()
        let p = Point(0, 0)
        plan.commands = [
            StitchCommand(.jump, p, thread: 0),                                                                         // 0
            StitchCommand(.stitch, p, thread: 0, objectID: a), StitchCommand(.stitch, p, thread: 0, objectID: a),      // 1–2
            StitchCommand(.trim, p, thread: 0),                                                                         // 3
            StitchCommand(.stitch, p, thread: 0, objectID: b), StitchCommand(.stitch, p, thread: 0, objectID: b),      // 4–5
            StitchCommand(.stop, p, thread: 0), StitchCommand(.colorChange, p, thread: 1),                              // 6–7
            StitchCommand(.stitch, p, thread: 1, objectID: c), StitchCommand(.stitch, p, thread: 1, objectID: c),      // 8–9
            StitchCommand(.trim, p, thread: 1)                                                                          // 10
        ]
        return plan
    }

    func testRunsCoverTheTimelineAndSplitWhereTheStepsLand() {
        let timeline = plan.timeline
        XCTAssertEqual(timeline.length, 11)
        XCTAssertEqual(timeline.colors.map { [$0.start, $0.end, $0.thread] }, [[0, 8, 0], [8, 11, 1]], "two colors; the first takes in the jump before it")
        XCTAssertEqual(timeline.objects.map { [$0.start, $0.end] }, [[0, 4], [4, 8], [8, 11]])
        XCTAssertEqual(timeline.objects.map(\.objectID), [a, b, c])
        // The runs start exactly where Next Color and Next Object land.
        XCTAssertEqual(timeline.colors[1].start, plan.position(after: .color(forward: true), from: 0))
        XCTAssertEqual(timeline.objects[1].start, plan.position(after: .object(forward: true), from: 0))
        XCTAssertEqual(timeline.trims, [4], "the trim at the very end isn't a pause")
        XCTAssertEqual(timeline.stops, [7])
    }

    func testTheRunAtAPositionIsTheOneSewingNext() {
        let colors = plan.timeline.colors
        XCTAssertEqual(PlayerTimeline.index(at: 0, in: colors), 0, "nothing sewn yet: the first color is next")
        XCTAssertEqual(PlayerTimeline.index(at: 7, in: colors), 0, "still before the color change")
        XCTAssertEqual(PlayerTimeline.index(at: 8, in: colors), 1, "where Next Color lands, the new color shows")
        XCTAssertEqual(PlayerTimeline.index(at: 11, in: colors), 1, "the end: the last color")
        XCTAssertNil(PlayerTimeline.index(at: 0, in: []))
    }

    func testAPlanWithNoStitchesHasAnEmptyTimeline() {
        var empty = StitchPlan(); empty.commands = [StitchCommand(.jump, Point(0, 0), thread: 0)]
        XCTAssertEqual(empty.timeline.length, 1)
        XCTAssertTrue(empty.timeline.colors.isEmpty); XCTAssertTrue(empty.timeline.trims.isEmpty)
    }
}
