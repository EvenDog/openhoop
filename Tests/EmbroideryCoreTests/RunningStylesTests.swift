// Checks the line stitch styles (zigzag, blanket, back stitch, stem stitch) and the stipple fill: each stays on or
// beside its line or inside its shape, at the sizes chosen; stipple never crosses itself, covers the shape, and sews
// the same way every time; and designs using them are saved as file version 6.
import XCTest
@testable import EmbroideryCore

final class RunningStylesTests: XCTestCase {
    /// A straight 30 mm line along the x axis with `style`.
    private func line(_ style: RunStyle, width: Double? = nil, spacing: Double? = nil) -> RunObject {
        var object = RunObject(name: "Line", nodes: [Point(0, 0), Point(30, 0)].map { PathNode($0) })
        object.digitizing = DigitizingSettings(kind: .run); object.digitizing?.runStyle = style
        object.digitizing?.runWidth = width; object.digitizing?.runSpacing = spacing
        return object
    }
    private func stitches(_ object: RunObject) throws -> [Point] { try StitchEngine.fresh(object, under: []).sections.flatMap(\.points) }

    func testZigzagSwingsSideToSideAtItsWidth() throws {
        let points = try stitches(line(.zigzag, width: 2, spacing: 1.5))
        XCTAssertTrue(points.allSatisfy { abs(abs($0.y) - 1) < 1e-9 }, "every point is half the width from the line")
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { ($0.y > 0) != ($1.y > 0) }, "alternately left and right")
        XCTAssertEqual(points.count, 21, "a point every 1.5 mm along 30 mm")
        XCTAssertEqual(points.first!.x, 0, accuracy: 1e-9); XCTAssertEqual(points.last!.x, 30, accuracy: 1e-9)
    }

    func testBlanketProngsPointIntoAClosedShape() throws {
        var square = RunObject(name: "Square", nodes: [Point(0, 0), Point(30, 0), Point(30, 30), Point(0, 30)].map { PathNode($0) })
        square.closed = true; square.digitizing = DigitizingSettings(kind: .run); square.digitizing?.runStyle = .blanket
        let points = try stitches(square)
        let inside = points.allSatisfy { $0.x >= -1e-9 && $0.x <= 30 + 1e-9 && $0.y >= -1e-9 && $0.y <= 30 + 1e-9 }
        XCTAssertTrue(inside, "the prongs point into the shape")
        // A prong goes out and straight back to the same point: base, tip, base.
        let prongs = points.indices.dropFirst().dropLast().filter { points[$0 - 1] == points[$0 + 1] }.map { (base: points[$0 - 1], tip: points[$0]) }
        XCTAssertEqual(prongs.count, 40, "a prong every 3 mm round 120 mm")
        XCTAssertTrue(prongs.allSatisfy { abs($0.base.distance(to: $0.tip) - 2.5) < 1e-6 }, "each prong 2.5 mm long")
        // Drawn the other way round, the prongs still point inside.
        square.nodes.reverse()
        XCTAssertTrue(try stitches(square).allSatisfy { $0.x >= -1e-9 && $0.x <= 30 + 1e-9 && $0.y >= -1e-9 && $0.y <= 30 + 1e-9 })
    }

    func testBackStitchGoesForwardTwoAndBackOne() throws {
        var object = line(.backStitch); object.stitchLength = 2.5
        let points = try stitches(object), xs = points.map(\.x)
        XCTAssertTrue(points.allSatisfy { abs($0.y) < 1e-9 }, "back stitch stays on the line")
        XCTAssertEqual(Array(xs.prefix(5)), [0, 5, 2.5, 7.5, 5], "forward two, back one")
        XCTAssertEqual(xs.last!, 30, accuracy: 1e-9)

        var stem = line(.stemStitch, width: 1); stem.stitchLength = 2.5
        let rope = try stitches(stem)
        XCTAssertTrue(rope.allSatisfy { abs($0.y) <= 0.5 + 1e-9 }, "stem stitch stays within its width")
        XCTAssertTrue(rope.dropFirst().dropLast().allSatisfy { abs(abs($0.y) - 0.5) < 1e-9 }, "each stitch slants across the line")
    }

    /// A 40 × 30 mm stipple fill: inside the shape, never crossing itself, covering it, and the same every time.
    func testStippleWandersWithoutCrossingAndCoversTheShape() throws {
        var fill = RunObject(name: "Stipple", nodes: [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.fillStyle = .stipple; fill.stitchLength = 2.5
        let sections = try AreaEngine.fill(fill).sections
        XCTAssertFalse(sections.contains(where: \.underlay), "stipple has no underlay")
        let points = sections.flatMap(\.points)
        let shape = [[Point(-0.5, -0.5), Point(40.5, -0.5), Point(40.5, 30.5), Point(-0.5, 30.5)]]
        XCTAssertTrue(points.allSatisfy { AreaGeometry.contains($0, rings: shape) }, "every stitch inside the shape")
        // No two stitches of the line cross (ones sharing a needle hole only touch there, so they're skipped).
        let top = sections.filter { !$0.joined || $0.points.count > 20 }.flatMap(\.points)
        let segments = Array(zip(top, top.dropFirst()))
        var crossings = 0
        for i in segments.indices { for j in (i + 2)..<max(i + 2, min(segments.count, i + 400)) {
            let shared = [segments[j].0, segments[j].1].contains { $0 == segments[i].0 || $0 == segments[i].1 }   // the loop closing on its first hole
            if !shared && AreaGeometry.intersects(segments[i].0, segments[i].1, segments[j].0, segments[j].1) { crossings += 1 }
        } }
        XCTAssertEqual(crossings, 0, "the line never crosses itself")
        // Covered: every point of the shape, 3 mm in from its edge, is within 3 mm of a stitch.
        var gaps = 0
        for x in stride(from: 3.0, through: 37, by: 1) { for y in stride(from: 3.0, through: 27, by: 1) {
            if !points.contains(where: { $0.distance(to: Point(x, y)) < 3 }) { gaps += 1 }
        } }
        XCTAssertEqual(gaps, 0, "no bare patches")
        XCTAssertEqual(try AreaEngine.fill(fill).sections.flatMap(\.points), points, "the same shape always sews the same way")
    }

    func testNewStitchesSaveAsVersionSixAndOldDesignsDont() {
        var design = Design(); design.objects = [RunObject(name: "Plain", nodes: [Point(0, 0), Point(10, 0)].map { PathNode($0) })]
        XCTAssertFalse(design.needsSchemaSix)
        design.objects.append(line(.zigzag))
        XCTAssertTrue(design.needsSchemaSix)
        design.objects = [RunObject(name: "Fill", nodes: [Point(0, 0), Point(10, 0), Point(10, 10)].map { PathNode($0) })]
        design.objects[0].closed = true; design.objects[0].digitizing = DigitizingSettings(kind: .fill); design.objects[0].digitizing?.fillStyle = .stipple
        XCTAssertTrue(design.needsSchemaSix)
        design.schemaVersion = 6
        XCTAssertNoThrow(try design.validate())
    }
}
