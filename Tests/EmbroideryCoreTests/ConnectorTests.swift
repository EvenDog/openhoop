// Connectors: run connectors (running stitches to the next object, no trim or ties), "When far" tie-in and tie-off,
// and the design's tie stitches. Designs that don't use them sew exactly as before (the rest of the suite checks that).
import XCTest
@testable import EmbroideryCore

final class ConnectorTests: XCTestCase {
    /// Two straight running lines in one thread, the second starting `gap` mm after the first ends.
    private func twoLines(gap: Double) -> Design {
        var design = Design()
        let first = RunObject(name: "First", nodes: [Point(0, 0), Point(10, 0)].map { PathNode($0) })
        let second = RunObject(name: "Second", nodes: [Point(10 + gap, 0), Point(20 + gap, 0)].map { PathNode($0) })
        design.objects = [first, second]
        return design
    }
    private func plan(_ design: Design) throws -> StitchPlan { try StitchEngine.compile(design) }
    private func count(_ op: StitchOperation, _ design: Design) throws -> Int { try plan(design).commands.filter { $0.op == op }.count }

    func testARunConnectorSewsAcrossWithNoTrimOrTies() throws {
        var design = twoLines(gap: 20)
        XCTAssertEqual(try count(.trim, design), 2, "a jump trims (20 mm is far)")
        design.objects[0].connectorType = .run
        let commands = try plan(design).commands
        XCTAssertEqual(commands.filter { $0.op == .trim }.count, 1, "only the trim at the very end")
        XCTAssertEqual(commands.filter { $0.op == .jump }.count, 1, "only the jump to the design's start")
        // From the first line's end to the second line's start, stitches no longer than the run's 2 mm.
        let stitches = commands.filter { $0.op == .stitch }.map(\.point)
        let end = stitches.lastIndex(of: Point(10, 0))!, start = stitches.firstIndex(of: Point(30, 0))!
        XCTAssertGreaterThan(start, end + 5)
        for (a, b) in zip(stitches[end...start], stitches[(end + 1)...start]) { XCTAssertLessThanOrEqual(a.distance(to: b), 2.0001) }
        XCTAssertGreaterThan(stitches[start + 1].x, 30.7, "no tie-in after a run: the second line carries straight on")
        XCTAssertTrue(try plan(design).warnings.contains { $0.contains("run connector") }, "a 20 mm run may show")
    }

    func testARunFallsBackToAJumpWhereItCantSew() throws {
        var design = twoLines(gap: 20)
        design.objects[0].connectorType = .run
        design.objects[1].color = ThreadColor.palette[1]
        XCTAssertEqual(try count(.trim, design), 2, "another thread: tie off and trim as a jump would")
        XCTAssertEqual(try count(.colorChange, design), 1)
        design.objects[1].color = design.objects[0].color
        design.objects[0].stopAfter = true
        XCTAssertEqual(try count(.trim, design), 2, "a stop in between: no run")
        // A short run needs no warning.
        var close = twoLines(gap: 5); close.objects[0].connectorType = .run
        XCTAssertFalse(try plan(close).warnings.contains { $0.contains("run connector") })
    }

    func testWhenFarTieInSkipsShortUncutMoves() throws {
        var design = twoLines(gap: 0.5)
        design.objects[0].trimRule = .off   // the needle jumps on without cutting
        let always = try count(.stitch, design)
        design.objects[1].tieInRule = .whenFar
        XCTAssertEqual(try count(.stitch, design), always - 2, "0.5 mm is closer than the 1 mm tie distance")
        var far = twoLines(gap: 5); far.objects[0].trimRule = .off
        let farAlways = try count(.stitch, far)
        far.objects[1].tieInRule = .whenFar
        XCTAssertEqual(try count(.stitch, far), farAlways, "5 mm is far enough to tie in")
        // A cut thread always ties in, however close.
        var cut = twoLines(gap: 0.5); cut.objects[0].trimRule = .always
        let cutAlways = try count(.stitch, cut)
        cut.objects[1].tieInRule = .whenFar
        XCTAssertEqual(try count(.stitch, cut), cutAlways)
    }

    func testWhenFarTieOffComesOffBeforeAShortUncutMove() throws {
        var design = twoLines(gap: 0.5)
        design.objects[0].trimRule = .off
        let always = try count(.stitch, design)
        design.objects[0].tieOutRule = .whenFar
        XCTAssertEqual(try count(.stitch, design), always - 2)
        design.objects[0].trimRule = .always
        let trimmed = try count(.stitch, design)
        design.objects[0].tieOutRule = .always
        XCTAssertEqual(try count(.stitch, design), trimmed, "before a trim the tie-off stays")
        XCTAssertEqual(design.objects[0].tieOutRule, .always)
        design.objects[0].tieOutRule = .off
        XCTAssertFalse(design.objects[0].tieOut)
    }

    func testTieStitchCountAndLength() throws {
        var design = Design()
        design.objects = [RunObject(name: "Line", nodes: [Point(0, 0), Point(10, 0)].map { PathNode($0) })]
        let firstStitches = { (design: Design) throws -> [Point] in Array(try self.plan(design).commands.filter { $0.op == .stitch }.map(\.point).prefix(8)) }
        XCTAssertEqual(try firstStitches(design).filter { $0 == Point(0.6, 0) }.count, 1, "one 0.6 mm tie by default")
        design.tieCount = 3
        XCTAssertEqual(try firstStitches(design).filter { $0 == Point(0.6, 0) }.count, 3)
        design.tieCount = nil; design.tieLength = 1
        XCTAssertTrue(try firstStitches(design).contains(Point(1, 0)))
    }

    func testBetweenLettersSetsEveryPartButTheLast() throws {
        let fonts = EmbroideryFont.all(in: EmbroideryFontTests.directory), ink = ThreadColor.palette[0]
        for kind in [LetteringSpec.FontKind.embroidery, .system] {
            var spec = LetteringSpec(text: "Abc", fontKind: kind, font: kind == .embroidery ? "small_font" : "Helvetica-Bold", height: 12)
            let plain = try spec.build(color: ink, embroideryFonts: fonts).objects
            spec.betweenLetters = .run
            let running = try spec.build(color: ink, embroideryFonts: fonts).objects
            XCTAssertEqual(running.count, plain.count)
            XCTAssertTrue(running.dropLast().allSatisfy { $0.connectorType == .run && $0.trimRule == .off }, "\(kind)")
            XCTAssertEqual(running.last?.connectorType, .jump, "the last part trims as before")
            XCTAssertEqual(running.last?.trimRule, plain.last?.trimRule)
            XCTAssertTrue(spec.matchesFreshBuild(running, embroideryFonts: fonts), "still live lettering")
            spec.betweenLetters = .always
            XCTAssertTrue(try spec.build(color: ink, embroideryFonts: fonts).objects.allSatisfy { $0.trimRule == .always || $0.trimRule == plain.last?.trimRule })
            spec.betweenLetters = .jump
            XCTAssertTrue(try spec.build(color: ink, embroideryFonts: fonts).objects.dropLast().allSatisfy { $0.trimRule == .off })
            var design = Design(); design.objects = running
            XCTAssertNoThrow(try StitchEngine.compile(design))
            XCTAssertTrue(design.needsSchemaEleven)
        }
    }

    func testSettingsAreCheckedAndSavedAsVersionEleven() throws {
        var design = twoLines(gap: 5)
        XCTAssertFalse(design.needsSchemaEleven)
        design.objects[0].connectorType = .run
        XCTAssertTrue(design.needsSchemaEleven)
        XCTAssertNil(twoLines(gap: 5).objects[0].connector, "Jump is stored as nothing")
        let reread = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reread.objects[0].connectorType, .run)
        design.schemaVersion = 11
        XCTAssertNoThrow(try design.validate())
        for change in [{ (d: inout Design) in d.tieCount = 4 }, { $0.tieLength = 2 }, { $0.runConnectorLength = 0.5 }, { $0.tieDistance = 0 }] {
            var bad = design; change(&bad)
            XCTAssertThrowsError(try bad.validate())
        }
    }
}
