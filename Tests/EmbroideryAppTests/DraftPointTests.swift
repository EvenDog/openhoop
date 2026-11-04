// Drawing: a click on the point just placed changes its type instead of adding a second point on the same spot.
import XCTest
import EmbroideryCore
@testable import EmbroideryApp

final class DraftPointTests: XCTestCase {
    @MainActor func testClickingTheLastPointAgainChangesItsType() {
        let state = EditorState()
        state.addDraftPoint(Point(0, 0), smooth: false, reach: 0.5)
        state.addDraftPoint(Point(10, 0), smooth: false, reach: 0.5)
        state.addDraftPoint(Point(10.2, 0.1), smooth: true, reach: 0.5)   // a right-click on the point just placed
        XCTAssertEqual(state.draft.count, 2, "no second point on the same spot")
        XCTAssertTrue(state.draft[1].smooth, "it became a curve point")
        XCTAssertEqual(state.draft[1].point, Point(10, 0), "and stayed where it was")
        state.addDraftPoint(Point(10, 0), smooth: false, reach: 0.5)   // a left-click there makes it a corner again
        XCTAssertEqual(state.draft.count, 2); XCTAssertFalse(state.draft[1].smooth)
        state.addDraftPoint(Point(10, 10), smooth: true, reach: 0.5)
        XCTAssertEqual(state.draft.count, 3, "a click elsewhere adds a point")
    }
}
