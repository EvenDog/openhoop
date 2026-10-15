// Adding a node on an edge as a corner (a click in Edit Nodes) or as a curve node (a right-click).
import XCTest
@testable import EmbroideryCore

final class NodeInsertTests: XCTestCase {
    private let square = [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)].map { PathNode($0) }

    /// A corner node lands exactly on the straight edge, and the shape doesn't change.
    func testCornerNodeOnAStraightEdge() {
        let (nodes, index) = RunningEngine.insertingNode(square, closed: true, segment: 0, near: Point(3, -9.6), smooth: false)
        XCTAssertEqual(index, 1); XCTAssertEqual(nodes[1].point.x, 3, accuracy: 1e-6); XCTAssertEqual(nodes[1].point.y, -10, accuracy: 1e-6)
        XCTAssertFalse(nodes[1].smooth); XCTAssertFalse(nodes[1].hasHandles)
    }

    /// A curve node on a straight edge leaves it straight until the node is dragged; then the edge bends smoothly
    /// through it instead of coming to a point.
    func testCurveNodeOnAStraightEdgeBendsOnlyWhenMoved() {
        var (nodes, index) = RunningEngine.insertingNode(square, closed: true, segment: 0, near: Point(0, -10), smooth: true)
        XCTAssertTrue(nodes[index].smooth); XCTAssertFalse(nodes[index].hasHandles, "an automatic curve")
        let bottom = RunningEngine.flatten(nodes, closed: true)[0] + RunningEngine.flatten(nodes, closed: true)[1]
        XCTAssertTrue(bottom.allSatisfy { abs($0.y + 10) < 1e-9 }, "still a straight edge")
        nodes[index].point = Point(0, -15)
        let bent = RunningEngine.flatten(nodes, closed: true)[0]
        XCTAssertTrue(bent.dropFirst().dropLast().contains { abs($0.y + 10) > 0.5 }, "the edge curves toward the moved node")
        // Smooth: the stitch line arrives at the node flat (heading the way it leaves), not at an angle.
        let arriving = bent[bent.count - 1] - bent[bent.count - 2], leaving = RunningEngine.flatten(nodes, closed: true)[1][1] - nodes[index].point
        XCTAssertEqual(atan2(arriving.y, arriving.x), atan2(leaving.y, leaving.x), accuracy: 0.15)
    }

    /// On a curved edge, a corner node drops its handles (the outline comes to a point there); a curve node keeps
    /// the curve's shape.
    func testNodesOnACurvedEdge() {
        var round = square; round[0].smooth = true; round[1].smooth = true
        let corner = RunningEngine.insertingNode(round, closed: true, segment: 0, near: Point(0, -11), smooth: false)
        XCTAssertFalse(corner.nodes[corner.index].smooth); XCTAssertFalse(corner.nodes[corner.index].hasHandles)
        let curve = RunningEngine.insertingNode(round, closed: true, segment: 0, near: Point(0, -11), smooth: true)
        XCTAssertTrue(curve.nodes[curve.index].smooth); XCTAssertTrue(curve.nodes[curve.index].hasHandles, "the split curve keeps its shape")
    }
}
