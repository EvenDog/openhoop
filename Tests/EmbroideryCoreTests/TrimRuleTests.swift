// Trim after "When far" (the default): the thread is cut after an object only when the next one in the same thread
// starts at least the design's trim distance away. Closer than that, a plain stitch carries the thread across, with
// no tie-off, trim, jump or tie-in. "Always" and "Off" keep their old meaning.
import XCTest
@testable import EmbroideryCore

final class TrimRuleTests: XCTestCase {
    /// Two straight running lines in one thread, the second starting `gap` mm after the first ends.
    private func twoLines(gap: Double) -> Design {
        var design = Design()
        let first = RunObject(name: "First", nodes: [Point(0, 0), Point(10, 0)].map { PathNode($0) })
        let second = RunObject(name: "Second", nodes: [Point(10 + gap, 0), Point(20 + gap, 0)].map { PathNode($0) })
        design.objects = [first, second]
        return design
    }
    private func count(_ op: StitchOperation, _ design: Design) throws -> Int { try StitchEngine.compile(design).commands.filter { $0.op == op }.count }

    func testWhenFarTrimsOnlyBeforeAFarStart() throws {
        // 2 mm apart: only the trim at the very end, and no jump after the first one (to the design's start).
        let close = twoLines(gap: 2)
        XCTAssertEqual(close.objects[0].trimRule, .whenFar, "new objects trim when far")
        XCTAssertEqual(try count(.trim, close), 1)
        XCTAssertEqual(try count(.jump, close), 1)
        // The first line's end goes straight to the second line's start: no lock stitches in between.
        let commands = try StitchEngine.compile(close).commands
        let end = commands.firstIndex { $0.op == .stitch && $0.point == Point(10, 0) }!
        XCTAssertEqual(commands[end + 1].point, Point(12, 0))

        // 10 mm apart: the first line trims too.
        XCTAssertEqual(try count(.trim, twoLines(gap: 10)), 2)
    }

    func testAlwaysOffAndTheDesignsDistance() throws {
        var design = twoLines(gap: 2)
        design.objects[0].trimRule = .always
        XCTAssertEqual(try count(.trim, design), 2, "Always trims however close")
        design.objects[0].trimRule = .off
        XCTAssertEqual(try count(.trim, design), 1, "Off never trims")

        // A smaller trim distance makes a 2 mm jump far enough to trim.
        design.objects[0].trimRule = .whenFar; design.trimDistance = 1.5
        XCTAssertEqual(try count(.trim, design), 2)
        design.trimDistance = 30
        XCTAssertThrowsError(try design.validate(), "distances beyond 20 mm are refused")
    }

    func testAColorChangeAlwaysTrims() throws {
        var design = twoLines(gap: 2)
        design.objects[1].color = ThreadColor.palette[1]
        XCTAssertEqual(try count(.trim, design), 2)
    }

    func testOlderFilesTrimWhenFar() throws {
        // An object saved before trimAlways existed has trimAfter on and no trimAlways: it reads as "When far".
        var object = twoLines(gap: 2).objects[0]
        object.trimAfter = true; object.trimAlways = nil
        let saved = try JSONEncoder().encode(object)
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("trimAlways"))
        XCTAssertEqual(try JSONDecoder().decode(RunObject.self, from: saved).trimRule, .whenFar)
    }
}
