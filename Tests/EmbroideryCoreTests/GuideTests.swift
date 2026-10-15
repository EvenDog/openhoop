// Guide lines: they snap points that come close, they're saved with the design, and a broken file can't hold
// unusable ones.
import XCTest
@testable import EmbroideryCore

final class GuideTests: XCTestCase {
    func testPointsCloseToAGuideLandOnIt() {
        let guides = [Guide(vertical: true, position: 10), Guide(vertical: true, position: 12), Guide(vertical: false, position: -5)]
        let near = Guide.snap(Point(11.8, -4.4), to: guides, reach: 1)
        XCTAssertEqual(near.x, 12, "the nearest vertical guide sets x")
        XCTAssertEqual(near.y, -5, "the horizontal guide sets y")
        let far = Guide.snap(Point(20, 3), to: guides, reach: 1)
        XCTAssertNil(far.x); XCTAssertNil(far.y)
    }

    func testGuidesAreSavedWithTheDesign() throws {
        var design = Design()
        design.guides = [Guide(vertical: true, position: 12.5), Guide(vertical: false, position: -3)]
        let reopened = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reopened.guides, design.guides)
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(Design())).guides, "a design without guides")
    }

    func testUnusableGuidesAreRefused() {
        var design = Design()
        design.guides = [Guide(vertical: true, position: .nan)]
        XCTAssertThrowsError(try design.validate())
        design.guides = Array(repeating: Guide(vertical: false, position: 0), count: Guide.limit + 1)
        XCTAssertThrowsError(try design.validate())
        design.guides = [Guide(vertical: false, position: 40)]
        XCTAssertNoThrow(try design.validate())
    }
}
