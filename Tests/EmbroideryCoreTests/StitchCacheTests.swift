// The stitch cache: each object's stitches are remembered, so compiling again only works out the objects that
// changed. These tests check that remembered stitches are exactly what a fresh compile makes, and that a change
// (to an object, or to what's sewn on top of a cut-out fill) is always worked out again.
import XCTest
@testable import EmbroideryCore

final class StitchCacheTests: XCTestCase {
    override func setUp() { StitchCache.shared.clear() }

    private func square(_ name: String, center: Point, size: Double, cut: Bool = false) -> RunObject {
        let h = size / 2
        var o = RunObject(name: name, nodes: [Point(-h, -h), Point(h, -h), Point(h, h), Point(-h, h)].map { PathNode(center + $0) }, color: ThreadColor.palette[0])
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.cutOutOverlaps = cut ? true : nil
        return o
    }
    /// Compiles `design` from an empty cache, as if nothing had been remembered.
    private func coldCompile(_ design: Design) throws -> StitchPlan {
        StitchCache.shared.clear()
        return try StitchEngine.compile(design)
    }

    /// Every sew-out sheet compiles to the same stitches whether they're worked out or remembered.
    func testRememberedStitchesMatchFreshOnes() throws {
        let pack = SewOutPackTests()
        for design in [pack.satinSheet(), pack.fillSheet(), try pack.letteringSheet(), try pack.monogramSheet(), try pack.travelSheet()] {
            let fresh = try coldCompile(design)
            let stitched = design.objects.filter { $0.rawStitches == nil && $0.kind != .vector }.count + (design.bastingBox == nil ? 0 : 1)
            XCTAssertEqual(StitchCache.shared.count, stitched, "each stitched object is remembered once")
            XCTAssertEqual(try StitchEngine.compile(design), fresh)
            XCTAssertEqual(StitchCache.shared.count, stitched, "compiling again works nothing out afresh")
        }
    }

    /// Moving one object works out only that object again; the others come from the cache.
    func testEditingOneObjectRecomputesOnlyThatObject() throws {
        var design = Design()
        design.objects = [square("A", center: Point(-20, 0), size: 10), square("B", center: Point(0, 0), size: 10), square("C", center: Point(20, 0), size: 10)]
        _ = try StitchEngine.compile(design)
        XCTAssertEqual(StitchCache.shared.count, 3)
        design.objects[1].transform { $0 + Point(0, 5) }
        let warm = try StitchEngine.compile(design)
        XCTAssertEqual(StitchCache.shared.count, 4, "only the moved object was worked out again")
        XCTAssertEqual(warm, try coldCompile(design))
    }

    /// A fill that cuts out overlaps depends on what's sewn on top, so moving the top shape works the fill out again.
    func testCutOutFillFollowsWhatsOnTop() throws {
        var design = Design()
        design.objects = [square("Base", center: Point(0, 0), size: 40, cut: true), square("Top", center: Point(0, 0), size: 10)]
        _ = try StitchEngine.compile(design)
        design.objects[1].transform { $0 + Point(8, 0) }
        let warm = try StitchEngine.compile(design)
        XCTAssertEqual(StitchCache.shared.count, 4, "both the top shape and the fill under it were worked out again")
        XCTAssertEqual(warm, try coldCompile(design))
    }

    /// The cache never holds more than its limit, so memory can't keep growing during a long session.
    func testCacheStaysWithinItsLimit() throws {
        var design = Design()
        design.objects = (0...StitchCache.limit).map { i in
            RunObject(name: "Line \(i)", nodes: [PathNode(Point(Double(i % 40), 0)), PathNode(Point(Double(i % 40), 10 + Double(i) / 100))], color: ThreadColor.palette[0])
        }
        _ = try StitchEngine.compile(design)
        XCTAssertLessThanOrEqual(StitchCache.shared.count, StitchCache.limit)
    }
}
