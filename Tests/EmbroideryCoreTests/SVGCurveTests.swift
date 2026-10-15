// SVG import keeps curves as Bézier handles: exact for cubic and quadratic curves, a close fit for arcs.
import XCTest
@testable import EmbroideryCore

final class SVGCurveTests: XCTestCase {
    func load(_ body: String) throws -> SVGImportResult {
        try SVGImporter.load(Data("<svg xmlns='http://www.w3.org/2000/svg' width='40mm' height='40mm' viewBox='0 0 40 40'>\(body)</svg>".utf8))
    }

    func testCubicCurveKeepsItsExactControlPoints() throws {
        var parser = SVGPathParser("M0 0 C0 10 10 10 10 0 L20 0", matrix: SVGMatrix())
        let nodes = try parser.parse()[0].nodes
        XCTAssertEqual(nodes.map(\.point), [Point(0, 0), Point(10, 0), Point(20, 0)])
        XCTAssertEqual(nodes[0].outHandle, Point(0, 10)); XCTAssertEqual(nodes[1].inHandle, Point(10, 10))
        XCTAssertNil(nodes[1].outHandle, "The following straight line has no handle")
        XCTAssertFalse(nodes[1].smooth, "A curve meeting a line at an angle stays a corner")
    }

    func testCircleBecomesFourSmoothNodesOnTheTrueCircle() throws {
        let circle = try load("<circle cx='20' cy='20' r='15' fill='none' stroke='black'/>").objects[0]
        XCTAssertEqual(circle.nodes.count, 4); XCTAssertTrue(circle.closed)
        XCTAssertTrue(circle.nodes.allSatisfy { $0.smooth && $0.hasHandles })
        for p in circle.outlinePaths[0] { XCTAssertEqual(hypot(p.x, p.y), 15, accuracy: 0.03) }   // centered by the importer
    }

    func testCompoundFillKeepsCurvesAndItsHole() throws {
        let ring = "<path fill-rule='evenodd' d='M5 20 A15 15 0 1 0 35 20 A15 15 0 1 0 5 20 Z M12 20 A8 8 0 1 0 28 20 A8 8 0 1 0 12 20 Z'/>"
        let result = try load(ring)
        XCTAssertEqual(result.objects.count, 1); XCTAssertEqual(result.objects[0].holes?.count, 1)
        XCTAssertTrue(result.objects[0].nodes.contains(where: \.hasHandles))
        XCTAssertTrue(result.objects[0].holes![0].contains(where: \.hasHandles))
        XCTAssertLessThan(result.objects[0].nodes.count, 10, "Curves stay curves instead of hundreds of points")
        var fill = result.objects[0]; fill.digitizing = DigitizingSettings(kind: .fill)
        XCTAssertFalse(try AreaEngine.fill(fill).sections.isEmpty, "The curved outline sews as a fill")
    }

    func testOverlappingCurvedShapesFallBackToPointsWithANote() throws {
        let result = try load("<path d='M5 20 A10 10 0 1 0 25 20 A10 10 0 1 0 5 20 Z M15 20 A10 10 0 1 0 35 20 A10 10 0 1 0 15 20 Z'/>")
        XCTAssertEqual(result.objects.count, 1)
        XCTAssertFalse(result.objects[0].nodes.contains(where: \.hasHandles))
        XCTAssertTrue(result.warnings.contains { $0.contains("Bézier") })
    }

    func testImportedSizeIncludesCurveBulges() throws {
        // The nodes lie on y = 0, but the curve peaks 7.5 mm higher.
        let result = try load("<path d='M0 0 C0 10 10 10 10 0' fill='none' stroke='black'/>")
        XCTAssertEqual(result.height, 7.5, accuracy: 0.03); XCTAssertEqual(result.width, 10, accuracy: 0.001)
    }
}
