// Satin borders: a closed satin column centered on a shape's outside edge.
import XCTest
@testable import EmbroideryCore

final class SatinBorderTests: XCTestCase {
    private let thread = ThreadColor.palette[1]
    private func fill(_ points: [Point]) -> RunObject {
        var o = RunObject(name: "Patch", nodes: points.map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: .fill); o.closed = true
        return o
    }
    private let square = [Point(-20, -20), Point(20, -20), Point(20, 20), Point(-20, 20)]

    func testSquareBorderIsEvenAndCoversTheCorners() throws {
        let result = try SatinBorder.around(fill(square), width: 3, color: thread)
        let border = result.object
        XCTAssertTrue(border.closed); XCTAssertEqual(border.kind, .satin); XCTAssertEqual(border.color, thread)
        XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
        // Every edge pair is 3 mm wide (a little more where the corners are rounded) and centered on the edge.
        for i in stride(from: 0, to: border.nodes.count, by: 2) {
            let outside = border.nodes[i].point, inside = border.nodes[i + 1].point
            XCTAssertEqual(outside.distance(to: inside), 3, accuracy: 0.1)
            let middle = (outside + inside) * 0.5
            XCTAssertLessThan(max(abs(middle.x), abs(middle.y)), 20.01, "The column's middle never leaves the square")
        }
        // The square's corners are inside the satin's outer rail, so the fill's corners are covered.
        let outer = AreaGeometry.ring(stride(from: 0, to: border.nodes.count, by: 2).map { border.nodes[$0] })
        XCTAssertTrue(square.allSatisfy { AreaGeometry.contains($0, rings: [outer]) })
        // It sews all the way round in one piece.
        let stitches = try AreaEngine.satin(border)
        XCTAssertTrue(stitches.sections.dropFirst().allSatisfy(\.joined))
        let top = stitches.sections.last!.points
        XCTAssertLessThan(top.first!.distance(to: top[top.count - 2]), 0.6, "The column ends where it began")
        var design = Design(); design.objects = [border]
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 500)
        XCTAssertTrue(design.needsSchemaFive, "Older versions can't sew closed satin, so the file says so")
    }

    /// Big borders used to be too slow to plan travel for (about a second for an 80 mm circle, then the router gave
    /// up), so the needle trimmed and jumped between underlay and top stitches. Now they're joined like small ones.
    func testBigBorderSewsInOnePiece() throws {
        var circle = fill([]); circle.nodes = ShapeGeometry.nodes(.ellipse, in: (Point(-40, -40), Point(40, 40)))
        let stitches = try AreaEngine.satin(SatinBorder.around(circle, width: 3, color: thread).object)
        XCTAssertTrue(stitches.sections.dropFirst().allSatisfy(\.joined), "Travel runs, not trims, between the parts")
    }

    func testCurvesAndInsideCorners() throws {
        let circle = try SVGImporter.load(Data("<svg xmlns='http://www.w3.org/2000/svg' width='40mm' height='40mm' viewBox='0 0 40 40'><circle cx='20' cy='20' r='15'/></svg>".utf8)).objects[0]
        var round = circle; round.digitizing = DigitizingSettings(kind: .fill)
        XCTAssertTrue(try SatinBorder.around(round, width: 4, color: thread).warnings.isEmpty)
        // An L shape: one inside corner the border has to round.
        let l = fill([Point(0, 0), Point(30, 0), Point(30, 10), Point(10, 10), Point(10, 30), Point(0, 30)])
        XCTAssertNoThrow(try AreaEngine.satin(try SatinBorder.around(l, width: 3, color: thread).object))
    }

    func testSharpPointsAndNarrowShapesAreExplained() throws {
        // A thin spike pokes out past a rounded border.
        let spike = fill([Point(0, 0), Point(20, 0), Point(10, 40)])
        XCTAssertTrue(try SatinBorder.around(spike, width: 4, color: thread).warnings.contains { $0.contains("stick out") })
        // Too thin for the width, and a narrow neck the border can't follow.
        XCTAssertThrowsError(try SatinBorder.around(fill([Point(0, 0), Point(30, 0), Point(30, 1.5), Point(0, 1.5)]), width: 6, color: thread))
        let dumbbell = fill([Point(0, 0), Point(20, 0), Point(20, 9.5), Point(30, 9.5), Point(30, 0), Point(50, 0), Point(50, 20), Point(30, 20), Point(30, 10.5), Point(20, 10.5), Point(20, 20), Point(0, 20)])
        XCTAssertThrowsError(try SatinBorder.around(dumbbell, width: 4, color: thread)) { XCTAssertTrue($0.localizedDescription.contains("neck")) }
        XCTAssertThrowsError(try SatinBorder.around(fill(square), width: 12, color: thread))
        var open = fill(square); open.digitizing = nil; open.closed = false
        XCTAssertFalse(SatinBorder.canBorder(open))
    }

    func testStartPointAndConversion() throws {
        var border = try SatinBorder.around(fill(square), width: 3, color: thread).object
        border.entry = Point(20, 0)
        let first = border.sewingOrder().nodes
        XCTAssertLessThan(((first[0].point + first[1].point) * 0.5).distance(to: Point(20, 0)), 3, "Starts at the pair nearest the start point")
        XCTAssertEqual(first.count, border.nodes.count)
        let loops = border.runningOutlines()
        XCTAssertEqual(loops.count, 2, "Converting to running stitch gives the outside and inside rails")
        XCTAssertTrue(loops.allSatisfy(\.closed))
    }
}
