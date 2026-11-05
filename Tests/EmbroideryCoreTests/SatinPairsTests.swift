// Checks untangling hand-drawn satin columns: a pair clicked right-then-left is swapped back, so the column sews
// instead of being refused, and columns drawn correctly (sharp corners included) are left alone.
import XCTest
@testable import EmbroideryCore

final class SatinPairsTests: XCTestCase {
    /// A straight satin column 4 mm wide running right along y = 0, pairs every 5 mm: left rail on top (y = 2).
    /// `swapped` pairs are clicked right-then-left.
    func column(_ count: Int, swapped: Set<Int> = []) -> RunObject {
        var nodes: [PathNode] = []
        for i in 0..<count {
            let left = PathNode(Point(Double(i) * 5, 2)), right = PathNode(Point(Double(i) * 5, -2))
            nodes += swapped.contains(i) ? [right, left] : [left, right]
        }
        var object = RunObject(name: "Satin", nodes: nodes, color: ThreadColor.palette[0])
        object.digitizing = DigitizingSettings(kind: .satin)
        return object
    }
    func sews(_ object: RunObject) -> Bool {
        var design = Design(); design.objects = [object]
        return (try? StitchEngine.compile(design)) != nil
    }

    func testAPairClickedTheWrongWayIsSwappedBack() throws {
        let twisted = column(6, swapped: [3])
        XCTAssertFalse(sews(twisted), "Refused as it is")
        XCTAssertTrue(SatinPairs.isTangled(twisted))
        let fixed = try XCTUnwrap(SatinPairs.untangled(twisted.nodes, closed: false))
        XCTAssertEqual(fixed, column(6).nodes)
        var untangled = twisted; untangled.nodes = fixed
        XCTAssertTrue(sews(untangled))
        XCTAssertFalse(SatinPairs.isTangled(untangled))
    }

    /// The column's majority decides which side is left, so a wrong first pair is the one swapped.
    func testTheFirstPairCanBeTheWrongOne() throws {
        XCTAssertEqual(try XCTUnwrap(SatinPairs.untangled(column(5, swapped: [0]).nodes, closed: false)), column(5).nodes)
    }

    /// A column drawn right-then-left all the way is consistent: nothing to untangle.
    func testAConsistentColumnIsLeftAlone() {
        XCTAssertNil(SatinPairs.untangled(column(5).nodes, closed: false))
        XCTAssertNil(SatinPairs.untangled(column(5, swapped: Set(0..<5)).nodes, closed: false))
    }

    /// Round a sharp corner the stitches fan out, but each pair's left point stays on the left: not a twist.
    func testASharpCornerIsNotATwist() {
        // Along the x axis, then straight up (a left turn, so the left rail is on the inside of it).
        let points: [(Point, Point)] = [(Point(0, 2), Point(0, -2)), (Point(10, 2), Point(10, -2)), (Point(12, 2), Point(16, -2)),
                                        (Point(12, 4), Point(16, 4)), (Point(12, 14), Point(16, 14))]
        XCTAssertNil(SatinPairs.untangled(points.flatMap { [PathNode($0.0), PathNode($0.1)] }, closed: false))
    }

    /// Each point keeps its own curve handles when its pair is swapped.
    func testHandlesStayWithTheirPoints() throws {
        var twisted = column(4, swapped: [2])
        twisted.nodes[4].outHandle = Point(12, -4)   // pair 2 clicked right first: its first point is the right one
        let fixed = try XCTUnwrap(SatinPairs.untangled(twisted.nodes, closed: false))
        XCTAssertEqual(fixed[5].point, Point(10, -2)); XCTAssertEqual(fixed[5].outHandle, Point(12, -4))
    }

    /// Only a column the engine refuses is untangled: one that sews is never changed.
    func testOnlyRefusedColumnsAreUntangled() throws {
        XCTAssertEqual(try XCTUnwrap(SatinPairs.untangle(column(6, swapped: [3]))).nodes, column(6).nodes)
        XCTAssertNil(SatinPairs.untangle(column(6)))
    }

    /// Font satins fan and overlap on purpose and are never called tangled.
    func testFontSatinsAreNeverTangled() {
        var twisted = column(6, swapped: [3]); twisted.digitizing?.relaxedChecks = true
        XCTAssertFalse(SatinPairs.isTangled(twisted))
    }
}
