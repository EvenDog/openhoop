// These tests exercise geometry and user-visible keyboard behavior, not UI snapshots.
import XCTest
@testable import EmbroideryCore

final class CoreTests: XCTestCase {
    func testRunningStitchesPreserveCornersAndLength() throws {
        let object = RunObject(name: "Corner", nodes: [Point(0, 0), Point(10, 0), Point(10, 7)].map { PathNode($0) })
        let stitches = try RunningEngine.stitches(for: object)
        XCTAssertTrue(stitches.contains(Point(10, 0)))
        XCTAssertEqual(stitches.last, Point(10, 7))
        for (a, b) in zip(stitches, stitches.dropFirst()) { XCTAssertLessThanOrEqual(a.distance(to: b), 2.50001) }
    }
    func testCurveSamplingDoesNotCutAcrossBend() throws {
        let object = RunObject(name: "Curve", nodes: [PathNode(Point(-10, 0)), PathNode(Point(0, 10), smooth: true), PathNode(Point(10, 0))])
        let stitches = try RunningEngine.stitches(for: object)
        XCTAssertTrue(stitches.contains(Point(0, 10)))
        XCTAssertGreaterThan(stitches.count, 10)
        XCTAssertTrue(stitches.allSatisfy(\.finite))
    }
    func testClosedRunReturnsToFirstPoint() throws {
        var object = Design.sample().objects[0]; object.tieIn = false; object.tieOut = false
        let stitches = try RunningEngine.stitches(for: object)
        XCTAssertEqual(stitches.first, stitches.last)
    }
    func testCommandsSeparateColorsAndObjects() throws {
        let plan = try RunningEngine.compile(Design.sample())
        XCTAssertEqual(plan.commands.filter { $0.op == .colorChange }.count, 2)
        XCTAssertEqual(plan.commands.filter { $0.op == .trim }.count, 3)
        XCTAssertEqual(plan.commands.last?.op, .end)
        XCTAssertGreaterThan(plan.stitchCount, 90)
    }
    func testHoopViolationReportedIncludingCurvedOvershoot() throws {
        var design = Design.sample(); design.hoop.width = 20
        XCTAssertTrue(try RunningEngine.compile(design).warnings.contains { $0.contains("beyond") })
    }
    func testOvalCornerIsOutside() { var hoop = Hoop(); hoop.oval = true; XCTAssertFalse(hoop.contains(Point(45, 45))); XCTAssertTrue(hoop.contains(Point(0, 49))) }
    func testInvalidNumericInputRejected() {
        var design = Design.sample(); design.objects[0].stitchLength = 0
        XCTAssertThrowsError(try RunningEngine.compile(design))
        design.objects[0].stitchLength = 2.5; design.objects[0].nodes[0].point.x = .nan
        XCTAssertThrowsError(try RunningEngine.compile(design))
    }
    func testDocumentRoundTrip() throws {
        var design = Design.sample(); design.cachedPlan = try RunningEngine.compile(design)
        let loaded = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(design, loaded)
    }
    func testDefaultShortcutProfileHasNoConflicts() throws { try ShortcutProfile().validate() }
    func testExcessiveSamplingRejectedBeforeAllocation() {
        var design = Design()
        var path = RunObject(name: "Oversized", nodes: (0..<100).map { PathNode(Point($0 % 2 == 0 ? -10000 : 10000, 0)) })
        path.stitchLength = 0.3; design.objects = [path]
        XCTAssertThrowsError(try RunningEngine.compile(design))
    }
    func testInvalidCachedPreviewRejected() {
        var design = Design(); var plan = StitchPlan()
        plan.commands = [.init(.stitch, Point(0, 0), thread: 999)]; design.cachedPlan = plan
        XCTAssertThrowsError(try design.validate())
    }
    func testPlainKeysDoNotOperateWhileTyping() {
        let profile = ShortcutProfile()
        for key in "abcdefghijklmnopqrstuvwxyz0123456789" { XCTAssertNil(profile.command(for: KeyBinding(String(key)), context: .text)) }
        XCTAssertEqual(profile.command(for: KeyBinding("n", 2), context: .canvas), .runTool)
        // Escape cancels a path being drawn, and otherwise means "done": back to Select with the whole design shown.
        XCTAssertEqual(profile.command(for: KeyBinding("escape"), context: .drawing), .cancelPath)
        XCTAssertEqual(profile.command(for: KeyBinding("escape"), context: .canvas), .done)
        XCTAssertEqual(profile.command(for: KeyBinding("s", 1), context: .text), .save)
    }
    func testDrawingAndSelectionDeleteAreSeparateContexts() {
        let profile = ShortcutProfile()
        XCTAssertEqual(profile.command(for: KeyBinding("delete"), context: .drawing), .removePoint)
        XCTAssertEqual(profile.command(for: KeyBinding("delete"), context: .canvas), .delete)
        XCTAssertTrue(profile.conflicts(KeyBinding("delete"), for: .removePoint).isEmpty)
    }
    func testConflictAndRepeatPolicies() {
        let profile = ShortcutProfile()
        XCTAssertEqual(profile.conflicts(KeyBinding("o"), for: .runTool), [.selectTool])
        XCTAssertNil(profile.command(for: KeyBinding("space"), context: .canvas, repeating: true))
        XCTAssertEqual(profile.command(for: KeyBinding("left"), context: .canvas, repeating: true), .nudgeLeft)
    }
    func testShortcutProfileRoundTripRetainsUnknownCommands() throws {
        var profile = ShortcutProfile(); profile.bindings["future.satin"] = [KeyBinding("s", 6)]
        let restored = try JSONDecoder().decode(ShortcutProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(profile, restored)
    }
}
