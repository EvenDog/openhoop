// Bézier handles: explicit handles shape curves, while nodes without handles must flatten exactly as before.
import XCTest
@testable import EmbroideryCore

final class BezierTests: XCTestCase {
    /// The control-point rule used before handles existed, kept here as the reference for old projects.
    private func legacyControls(_ nodes: [PathNode], closed: Bool, _ i: Int) -> (Point, Point, Point, Point) {
        let count = nodes.count, j = (i + 1) % count, a = nodes[i], b = nodes[j]
        let prev = nodes[i == 0 ? (closed ? count - 1 : 0) : i - 1].point
        let next = nodes[j + 1 < count ? j + 1 : (closed ? 0 : j)].point
        let c1 = a.smooth ? a.point + (b.point - prev) * (1.0 / 6) : a.point + (b.point - a.point) * (1.0 / 3)
        let c2 = b.smooth ? b.point - (next - a.point) * (1.0 / 6) : b.point - (b.point - a.point) * (1.0 / 3)
        return (a.point, c1, c2, b.point)
    }

    func testNodesWithoutHandlesKeepTheirExactCurve() {
        let shapes: [[PathNode]] = [
            [PathNode(Point(-25, -16)), PathNode(Point(0, -11), smooth: true), PathNode(Point(25, -16))],
            [Point(-25, 32), Point(0, 30), Point(25, 33), Point(10, 40)].map { PathNode($0, smooth: true) },
            [PathNode(Point(0, 0)), PathNode(Point(10, 3), smooth: true), PathNode(Point(4, 12)), PathNode(Point(-6, 7), smooth: true)]
        ]
        for nodes in shapes {
            for closed in [false, true] {
                for i in 0..<(closed ? nodes.count : nodes.count - 1) {
                    let new = RunningEngine.controls(nodes, closed: closed, segment: i), old = legacyControls(nodes, closed: closed, i)
                    XCTAssertEqual([new.0, new.1, new.2, new.3], [old.0, old.1, old.2, old.3], "segment \(i), closed \(closed)")
                }
            }
        }
    }

    func testExplicitHandlesShapeTheCurve() {
        // A cubic from (0,0) to (10,0) pulled up by both handles peaks at y = 7.5 halfway along.
        let nodes = [PathNode(Point(0, 0), smooth: true, outHandle: Point(0, 10)), PathNode(Point(10, 0), smooth: true, inHandle: Point(10, 10))]
        let points = RunningEngine.flatten(nodes).flatMap { $0 }
        let peak = points.max { $0.y < $1.y }!
        XCTAssertEqual(peak.y, 7.5, accuracy: 0.03)
        XCTAssertEqual(peak.x, 5, accuracy: 0.6)
        XCTAssertEqual(points.first, Point(0, 0)); XCTAssertEqual(points.last, Point(10, 0))
    }

    func testRunningStitchesFollowHandlesAndStayShort() throws {
        var object = RunObject(name: "Arch", nodes: [PathNode(Point(0, 0), smooth: true, outHandle: Point(0, 10)), PathNode(Point(10, 0), smooth: true, inHandle: Point(10, 10))])
        object.stitchLength = 2
        let stitches = try RunningEngine.stitches(for: object)
        XCTAssertGreaterThan(stitches.map(\.y).max()!, 7)
        for (a, b) in zip(stitches, stitches.dropFirst()) { XCTAssertLessThanOrEqual(a.distance(to: b), 2.00001) }
    }

    func testTransformMovesHandlesWithTheirNode() {
        var object = RunObject(name: "Arch", nodes: [PathNode(Point(1, 2), smooth: true, inHandle: Point(0, 5), outHandle: Point(3, 4))])
        object.transform { Point(-$0.x, $0.y) }   // mirror horizontally
        XCTAssertEqual(object.nodes[0].point, Point(-1, 2))
        XCTAssertEqual(object.nodes[0].inHandle, Point(0, 5))
        XCTAssertEqual(object.nodes[0].outHandle, Point(-3, 4))
    }

    func testReversedRailTracesTheSameCurveBackwards() {
        let rail = [PathNode(Point(0, 0), smooth: true, outHandle: Point(2, 6)), PathNode(Point(10, 0), smooth: true, inHandle: Point(7, -5), outHandle: Point(13, 5)), PathNode(Point(20, 2))]
        let forward = RunningEngine.flatten(rail).flatMap { $0 }
        let backward = RunningEngine.flatten(rail.reversed().map(\.reversedDirection)).flatMap { $0 }
        // Same curve, opposite direction: every backward point lies on the forward polyline.
        for p in backward {
            let nearest = zip(forward, forward.dropFirst()).map { p.distance(to: AreaGeometry.projection(p, $0, $1)) }.min()!
            XCTAssertLessThan(nearest, 0.03)
        }
    }

    func testCornerRemovesHandlesAndOldNodesDecode() throws {
        var node = PathNode(Point(1, 1), smooth: true, inHandle: Point(0, 0), outHandle: Point(2, 2))
        node.toggleSmooth()
        XCTAssertFalse(node.smooth); XCTAssertFalse(node.hasHandles)
        let old = try JSONDecoder().decode(PathNode.self, from: Data(#"{"point":{"x":1,"y":2},"smooth":true}"#.utf8))
        XCTAssertEqual(old, PathNode(Point(1, 2), smooth: true))
        let encoded = String(decoding: try JSONEncoder().encode(PathNode(Point(1, 2))), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Handle"), "Nodes without handles must save exactly as before")
    }

    func testSchemaAndHandleValidation() throws {
        var design = Design()
        design.objects = [RunObject(name: "Arch", nodes: [PathNode(Point(0, 0), smooth: true, outHandle: Point(0, 10)), PathNode(Point(10, 0))])]
        XCTAssertTrue(design.usesHandles)
        design.schemaVersion = 5; XCTAssertNoThrow(try design.validate())
        design.schemaVersion = 15; XCTAssertThrowsError(try design.validate(), "a file version from the future is refused")
        design.schemaVersion = 5; design.objects[0].nodes[0].outHandle = Point(.infinity, 0)
        XCTAssertThrowsError(try design.validate())
        XCTAssertFalse(Design.sample().usesHandles)
    }
}

final class PenDrawingTests: XCTestCase {
    func testDraggingANewNodePullsSymmetricHandles() {
        var node = PathNode(Point(10, 10))
        node.pullHandles(toward: Point(14, 13))
        XCTAssertTrue(node.smooth)
        XCTAssertEqual(node.outHandle, Point(14, 13)); XCTAssertEqual(node.inHandle, Point(6, 7))
    }
}

final class InsertNodeTests: XCTestCase {
    func testInsertingOnACurveKeepsItsShape() {
        let arch = [PathNode(Point(0, 0), smooth: true, outHandle: Point(0, 10)), PathNode(Point(10, 0), smooth: true, inHandle: Point(10, 10)), PathNode(Point(20, 5), smooth: true)]
        let before = RunningEngine.flatten(arch).flatMap { $0 }
        let (after, index) = RunningEngine.insertingNode(arch, closed: false, segment: 0, near: Point(5, 8))
        XCTAssertEqual(after.count, 4); XCTAssertEqual(after[index].point.y, 7.5, accuracy: 0.05)
        for p in RunningEngine.flatten(after).flatMap({ $0 }) {
            let gap = zip(before, before.dropFirst()).map { p.distance(to: AreaGeometry.projection(p, $0, $1)) }.min()!
            XCTAssertLessThan(gap, 0.03, "The curve, including the automatic curve after node 2, must not move")
        }
    }

    func testInsertingOnAStraightEdgeAddsAPlainCorner() {
        let line = [PathNode(Point(0, 0)), PathNode(Point(10, 0))]
        let (after, index) = RunningEngine.insertingNode(line, closed: false, segment: 0, near: Point(4, 1))
        XCTAssertFalse(after[index].smooth); XCTAssertFalse(after[index].hasHandles)
        XCTAssertEqual(after[index].point.x, 4, accuracy: 0.2); XCTAssertEqual(after[index].point.y, 0, accuracy: 1e-9)
    }
}
