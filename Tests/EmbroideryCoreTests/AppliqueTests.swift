// Appliqué: placement line, stop, tack-down, stop, satin edge, grouped, from a fill or closed outline.
import XCTest
@testable import EmbroideryCore

final class AppliqueTests: XCTestCase {
    private let thread = ThreadColor.palette[1]
    private func fill(_ points: [Point]) -> RunObject {
        var o = RunObject(name: "Patch", nodes: points.map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: .fill); o.closed = true
        return o
    }
    private let square = [Point(-20, -20), Point(20, -20), Point(20, 20), Point(-20, 20)]

    func testThreePartsInOrderWithStopsBetween() throws {
        let result = try Applique.make(from: fill(square), coverWidth: 3.5, tackDown: .zigzag, color: thread)
        let parts = result.objects
        XCTAssertEqual(parts.map(\.name), ["Patch · placement", "Patch · tack-down", "Patch · satin edge"])
        XCTAssertEqual(parts.map(\.kind), [.run, .satin, .satin])
        XCTAssertEqual(parts.map(\.stopAfter), [true, true, false], "Stop to lay the fabric, stop to trim it")
        XCTAssertEqual(Set(parts.map(\.groupID)).count, 1); XCTAssertNotNil(parts[0].groupID)
        XCTAssertTrue(parts.allSatisfy { $0.color == thread && $0.closed })
        XCTAssertEqual(parts[0].nodes.map(\.point), square, "The placement line runs on the shape's edge")
        XCTAssertEqual(parts[1].settings.spacing, 1.5, "The tack-down is an open zigzag")
        XCTAssertEqual(parts[1].settings.underlay, .none)
        XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    }

    func testItSewsWithTwoStops() throws {
        var design = Design()
        design.objects = try Applique.make(from: fill(square), coverWidth: 3.5, tackDown: .zigzag, color: thread).objects
        XCTAssertNoThrow(try design.validate())
        let plan = try StitchEngine.compile(design)
        XCTAssertEqual(plan.commands.filter { $0.op == .stop }.count, 2)
        XCTAssertGreaterThan(plan.stitchCount, 300)
        // The satin edge is wider than the zigzag tack-down, so it covers it.
        let tack = design.objects[1].nodes, edge = design.objects[2].nodes
        XCTAssertLessThan(tack[0].point.distance(to: tack[1].point), edge[0].point.distance(to: edge[1].point))
    }

    func testRunningTackDownFollowsThePlacementLine() throws {
        let parts = try Applique.make(from: fill(square), coverWidth: 3, tackDown: .running, color: thread).objects
        XCTAssertEqual(parts[1].kind, .run)
        XCTAssertEqual(parts[1].nodes, parts[0].nodes)
        XCTAssertNotEqual(parts[1].id, parts[0].id)
    }

    func testOpenLinesWidthsAndHoles() throws {
        var line = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))])
        line.digitizing = DigitizingSettings(kind: .run)
        XCTAssertThrowsError(try Applique.make(from: line, coverWidth: 3.5, tackDown: .zigzag, color: thread))
        XCTAssertThrowsError(try Applique.make(from: fill(square), coverWidth: 9, tackDown: .zigzag, color: thread))
        var holed = fill(square); holed.holes = [[Point(-5, -5), Point(5, -5), Point(5, 5)].map { PathNode($0) }]
        let result = try Applique.make(from: holed, coverWidth: 3.5, tackDown: .zigzag, color: thread)
        XCTAssertTrue(result.warnings.contains { $0.contains("holes") })
    }
}
