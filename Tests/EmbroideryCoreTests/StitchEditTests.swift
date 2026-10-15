// Checks Edit Stitch: edited stitches sew in place of fresh ones while they match their object, follow it when it's
// moved or turned, and are dropped once its shape or settings change.
import XCTest
@testable import EmbroideryCore

final class StitchEditTests: XCTestCase {
    private func line() -> RunObject {
        RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(20, 0))], color: ThreadColor.palette[0])
    }

    func testEditedStitchesSewWhileTheyMatch() throws {
        var design = Design()
        var object = line()
        let edited = [Point(0, 0), Point(5, 3), Point(10, 0), Point(20, 0)]   // one needle point pulled up 3 mm
        object.stitchEdits = StitchEdits(sections: [.init(points: edited)], signature: object.stitchSignature)
        design.objects = [object]
        XCTAssertTrue(design.needsSchemaFive)
        let stitches = try RunningEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point)
        XCTAssertTrue(stitches.contains(Point(5, 3)), "the edited point sews")

        // Renaming or recoloring doesn't change where the needle goes, so the edits stay.
        design.objects[0].name = "Renamed"; design.objects[0].color = ThreadColor.palette[3]
        XCTAssertTrue(design.objects[0].hasCurrentStitchEdits)
        XCTAssertTrue(design.dropStaleStitchEdits().isEmpty)
    }

    func testEditsFollowMovesAndTurnsButNotNewSettings() throws {
        var design = Design()
        var object = line()
        object.stitchEdits = StitchEdits(sections: [.init(points: [Point(0, 0), Point(5, 3), Point(20, 0)])], signature: object.stitchSignature)
        design.objects = [object]
        let id = object.id
        design.move([id], by: Point(10, 0))
        XCTAssertEqual(design.objects[0].stitchEdits?.sections[0].points[1], Point(15, 3), "moved with the object")
        design.rotate([id], by: 90, around: Point(0, 0))
        XCTAssertTrue(design.objects[0].hasCurrentStitchEdits, "turning keeps them")

        design.objects[0].stitchLength = 1.5   // a new setting: the edits no longer match
        XCTAssertFalse(design.objects[0].hasCurrentStitchEdits)
        XCTAssertEqual(design.dropStaleStitchEdits(), ["Line"])
        XCTAssertNil(design.objects[0].stitchEdits)
    }
}
