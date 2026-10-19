// The Pro Threads panel's In Sewing Order list: as tall as its steps need until its bar is dragged, then as tall as
// it was dragged to, and remembered (an older preferences file has no height, so the list fits its steps).
import XCTest
@testable import EmbroideryApp

final class ThreadStepsHeightTests: XCTestCase {
    func testTheListFitsItsStepsUntilDragged() {
        XCTAssertEqual(ProThreads.stepsHeight(dragged: nil, steps: 1), 44, "room for two steps at least")
        XCTAssertEqual(ProThreads.stepsHeight(dragged: nil, steps: 5), 104)
        XCTAssertEqual(ProThreads.stepsHeight(dragged: nil, steps: 30), 164, "eight steps at most")
        XCTAssertEqual(ProThreads.stepsHeight(dragged: 0, steps: 5), 0, "dragged all the way down")
        XCTAssertEqual(ProThreads.stepsHeight(dragged: 400, steps: 5), 400)
    }

    func testTheDraggedHeightIsRemembered() throws {
        let old = try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(PreferenceData()))
        XCTAssertNil(old.threadStepsHeight)
        var dragged = PreferenceData(); dragged.threadStepsHeight = 120
        XCTAssertEqual(try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(dragged)).threadStepsHeight, 120)
    }
}
