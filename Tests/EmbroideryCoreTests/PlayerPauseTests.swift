// Where the stitch player pauses with "Pause at trims" on: trims, stops and thread changes, once per place.
import XCTest
@testable import EmbroideryCore

final class PlayerPauseTests: XCTestCase {
    private func line(_ name: String, y: Double, color: ThreadColor = .palette[0]) -> RunObject {
        RunObject(name: name, nodes: [PathNode(Point(-20, y)), PathNode(Point(20, y))], color: color)
    }
    private func plan(_ objects: [RunObject]) throws -> StitchPlan {
        var design = Design(); design.objects = objects
        return try StitchEngine.compile(design)
    }

    func testPausesOnceAfterEachTrimStopOrThreadChange() throws {
        var stopping = line("B", y: 0); stopping.stopAfter = true
        let sample = try plan([line("A", y: -10), stopping, line("C", y: 10), line("D", y: 20, color: .palette[1])])
        let pauses = sample.machinePauses
        // A trims; B trims then stops; C trims then changes thread. D's trim at the very end is left out.
        XCTAssertEqual(pauses.count, 3)
        for shown in pauses {
            XCTAssertTrue([.trim, .stop, .colorChange].contains(sample.commands[shown - 1].op), "Paused right after the event")
            XCTAssertFalse([.trim, .stop, .colorChange].contains(sample.commands[shown].op), "...and after the last of a run of them")
        }
        XCTAssertEqual(sample.commands[pauses[1] - 1].op, .stop)
        XCTAssertEqual(sample.commands[pauses[2] - 1].op, .colorChange)
    }

    func testNoPausesWithoutTrims() throws {
        var design = Design(); design.objects = [line("A", y: 0)]
        design.objects[0].trimAfter = false
        XCTAssertEqual(try StitchEngine.compile(design).machinePauses, [])
        XCTAssertEqual(StitchPlan().machinePauses, [])
    }
}
