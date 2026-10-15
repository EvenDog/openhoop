// Second underlay: a satin can have two underlay layers (a first and a second underlay), such as a center
// run followed by a zigzag. They sew in that order, before the top stitches.
import XCTest
@testable import EmbroideryCore

final class SecondUnderlayTests: XCTestCase {
    /// A straight satin column 4 mm wide and 30 mm long, centered on the x axis.
    private func column(_ first: UnderlayStyle, _ second: UnderlayStyle?) -> RunObject {
        var o = RunObject(name: "Column", nodes: [Point(-15, 2), Point(-15, -2), Point(15, 2), Point(15, -2)].map { PathNode($0) })
        var s = DigitizingSettings(kind: .satin); s.underlay = first; s.secondUnderlay = second; o.digitizing = s
        return o
    }

    func testSatinSewsFirstUnderlayThenSecondThenTop() throws {
        let sections = try AreaEngine.satin(column(.center, .zigzag)).sections
        let under = sections.filter(\.underlay)
        guard under.count == 2 else { return XCTFail("Expected two underlay layers, got \(under.count)") }
        XCTAssertTrue(under[0].points.allSatisfy { abs($0.y) < 0.01 }, "The center run comes first")
        XCTAssertLessThan(under[1].points.map(\.y).min()!, -1, "Then the zigzag, which crosses the column")
        XCTAssertGreaterThan(under[1].points.map(\.y).max()!, 1)
        // The center run goes along the column; the zigzag comes back, ending where the top stitches begin.
        XCTAssertGreaterThan(under[0].points.last!.x, 13); XCTAssertGreaterThan(under[1].points.first!.x, 13)
        XCTAssertLessThan(under[1].points.last!.x, -13)
        XCTAssertFalse(sections.last!.underlay, "The top stitches come last")
        // Without a second underlay, only the first one sews.
        XCTAssertEqual(try AreaEngine.satin(column(.center, nil)).sections.filter(\.underlay).count, 1)
    }

    func testSecondUnderlayClearsWhenTheFirstIsOffOrTheSame() {
        var s = DigitizingSettings(kind: .satin)
        s.underlay = .center; s.secondUnderlay = .zigzag
        s.underlay = .edge
        XCTAssertEqual(s.secondUnderlay, .zigzag, "A different first underlay keeps the second")
        s.underlay = .zigzag
        XCTAssertNil(s.secondUnderlay, "The same style twice would just sew it again")
        s.secondUnderlay = .center
        s.underlay = .none
        XCTAssertNil(s.secondUnderlay, "No first underlay, no second (so U turns all underlay off)")
    }

    func testUnderlayInsetAppliesWhenEitherLayerRunsInsideTheEdge() {
        var s = DigitizingSettings(kind: .satin); s.underlay = .center
        XCTAssertFalse(s.usesUnderlayInset, "A center run ignores the inset")
        s.secondUnderlay = .zigzag
        XCTAssertTrue(s.usesUnderlayInset, "The zigzag uses it")
    }

    func testOnlySatinsAcceptASecondUnderlay() throws {
        var design = Design(); design.objects = [column(.edge, .zigzag)]
        XCTAssertNoThrow(try design.validate())
        // Styles a satin can't sew, the same style twice, or a second without a first.
        for (first, second) in [(UnderlayStyle.edge, UnderlayStyle.edgeAndSparse), (.zigzag, .zigzag), (.none, .center)] {
            var object = column(.center, nil); object.digitizing?.underlay = first; object.digitizing?.secondUnderlay = second
            design.objects = [object]
            XCTAssertThrowsError(try design.validate(), "\(first) then \(second)")
        }
        var fill = RunObject(name: "Fill", nodes: [Point(0, 0), Point(10, 0), Point(10, 10)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.secondUnderlay = .edge
        design.objects = [fill]
        XCTAssertThrowsError(try design.validate(), "Fills already have a two-layer choice (edge + sparse fill)")
    }

    func testOlderVersionsRefuseFilesWithASecondUnderlay() throws {
        var design = Design(); design.objects = [column(.center, .zigzag)]
        design.objects[0].digitizing?.shortStitches = nil; design.objects[0].digitizing?.autoSplit = nil; design.objects[0].digitizing?.pullPercent = nil
        XCTAssertTrue(design.needsSchemaFive, "An older version would sew only the first underlay")
        design.objects[0].digitizing?.secondUnderlay = nil
        XCTAssertFalse(design.needsSchemaFive)
        let old = try JSONDecoder().decode(DigitizingSettings.self, from: Data(#"{"kind":"satin","spacing":0.4,"expansion":0.2,"angle":45,"maximumSatin":10,"underlay":"center","inset":0.4,"underlaySpacing":1.2}"#.utf8))
        XCTAssertNil(old.secondUnderlay, "Files saved before the second underlay open with none")
    }
}
