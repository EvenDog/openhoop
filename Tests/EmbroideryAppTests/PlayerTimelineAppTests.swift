// Checks that the stitch player's timeline follows the design's stitch plan: worked out once per plan, and
// worked out again when the plan changes (an edit, say).
import XCTest
import EmbroideryCore
@testable import EmbroideryApp

final class PlayerTimelineAppTests: XCTestCase {
    @MainActor func testTheTimelineFollowsThePlan() {
        let state = EditorState()
        var plan = StitchPlan()
        plan.commands = [StitchCommand(.stitch, Point(0, 0), thread: 0), StitchCommand(.stitch, Point(1, 0), thread: 1)]
        state.plan = plan
        XCTAssertEqual(state.playerTimeline.colors.count, 2)
        plan.commands.append(StitchCommand(.stitch, Point(2, 0), thread: 2))
        state.plan = plan
        XCTAssertEqual(state.playerTimeline.colors.count, 3, "a new plan gives a new timeline")
        XCTAssertEqual(state.playerTimeline.length, 3)
    }
}
