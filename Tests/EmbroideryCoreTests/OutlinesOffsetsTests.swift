// Outlines & Offsets: new outlines on a shape's edge and set distances outside or inside it, in the chosen stitch.
import XCTest
@testable import EmbroideryCore

final class OutlinesOffsetsTests: XCTestCase {
    private func square(size: Double, hole: Double? = nil) -> RunObject {
        func ring(_ s: Double) -> [PathNode] { let h = s / 2; return [Point(-h, -h), Point(h, -h), Point(h, h), Point(-h, h)].map { PathNode($0) } }
        var o = RunObject(name: "Square", nodes: ring(size), color: ThreadColor.palette[0])
        o.closed = true; o.digitizing = DigitizingSettings(kind: .fill)
        if let hole { o.holes = [ring(hole)] }
        return o
    }
    private func width(_ object: RunObject) -> Double { let xs = object.nodes.map(\.point.x); return xs.max()! - xs.min()! }
    private func options(edge: Bool = false, _ offsets: Double?..., holes: Bool = false, stitch: OpenShapeStitch = .running) -> OutlineOptions {
        var o = OutlineOptions(); o.edge = edge; o.offsets = offsets; o.holes = holes; o.stitch = stitch
        return o
    }

    func testEdgeOutlineAndAnOffsetOutside() throws {
        let made = try OutlinesOffsets.around(square(size: 20), options: OutlineOptions(), color: ThreadColor.palette[1])
        XCTAssertEqual(made.objects.map(\.name), ["Square outline", "Square offset 1"])
        XCTAssertTrue(made.objects.allSatisfy { $0.closed && $0.kind == .run && $0.color == ThreadColor.palette[1] })
        XCTAssertEqual(made.objects[0].nodes, square(size: 20).nodes, "The edge outline keeps the shape's own nodes")
        XCTAssertEqual(width(made.objects[1]), 26, accuracy: OutlinesOffsets.tolerance, "3 mm out on each side")
        XCTAssertLessThan(made.objects[1].nodes.count, 60, "Spare points along the straight sides are dropped")
    }

    func testOffsetInsideAndTooSmall() throws {
        XCTAssertEqual(width(try OutlinesOffsets.around(square(size: 20), options: options(-3), color: .palette[0]).objects[0]), 14, accuracy: 0.05)
        let gone = try OutlinesOffsets.around(square(size: 20), options: options(-15, 2), color: .palette[0])
        XCTAssertEqual(gone.objects.map(\.name), ["Square offset 2"])
        XCTAssertTrue(gone.warnings.contains { $0.contains("too small for an offset 15 mm inside") }, "\(gone.warnings)")
    }

    func testHolesAreOutlinedOnlyWhenAsked() throws {
        let shape = square(size: 40, hole: 10)
        let without = try OutlinesOffsets.around(shape, options: options(edge: true, 2), color: .palette[0]).objects
        XCTAssertEqual(without.map(\.name), ["Square outline", "Square offset 1"])
        let with = try OutlinesOffsets.around(shape, options: options(edge: true, 2, holes: true), color: .palette[0]).objects
        XCTAssertEqual(with.map(\.name), ["Square outline", "Square hole outline", "Square offset 1", "Square offset 1"])
        XCTAssertEqual(width(with[3]), 6, accuracy: 0.05, "Growing the shape shrinks its hole")
        // Going inside, the offset keeps clear of the hole.
        let inside = try OutlinesOffsets.around(shape, options: options(-2, holes: true), color: .palette[0]).objects
        XCTAssertEqual(inside.map(width).sorted(), [14, 36], accuracy: 0.05)
    }

    func testStitchesAndLargeOffsets() throws {
        let bean = try OutlinesOffsets.around(square(size: 20), options: options(25, stitch: .bean), color: .palette[0]).objects[0]
        XCTAssertEqual(bean.settings.runPasses, 3)
        XCTAssertEqual(width(bean), 70, accuracy: 0.05, "Offsets over 10 mm work too")
        XCTAssertEqual(try OutlinesOffsets.around(square(size: 20), options: options(3, stitch: .satin), color: .palette[0]).objects[0].kind, .satin)
        XCTAssertEqual(try OutlinesOffsets.around(square(size: 20), options: options(3, stitch: .zigzag), color: .palette[0]).objects[0].settings.runStyle, .zigzag)
    }

    func testSharpOrRoundedCorners() throws {
        let sharp = try OutlinesOffsets.around(square(size: 20), options: options(3), color: .palette[0]).objects[0]
        XCTAssertEqual(sharp.nodes.count, 4, "A square's offset is a square")
        XCTAssertTrue(sharp.nodes.contains { $0.point.distance(to: Point(13, 13)) < 0.01 })
        var rounded = options(3); rounded.sharpCorners = false
        let round = try OutlinesOffsets.around(square(size: 20), options: rounded, color: .palette[0]).objects[0]
        XCTAssertGreaterThan(round.nodes.map { $0.point.distance(to: Point(13, 13)) }.min()!, 1, "Rounded corners cut inside the square's corner")

        // A 20° tip: a true point 3 mm out would reach about 17 mm past it, so it's cut off flat 3 mm past it. A 40°
        // one stays pointed (3 mm / sin 20° ≈ 8.8 mm past it).
        let half = 30 * tan(10 * Double.pi / 180)
        var tip = square(size: 20); tip.nodes = [Point(-half, 0), Point(half, 0), Point(0, 30)].map { PathNode($0) }
        let around = try OutlinesOffsets.around(tip, options: options(3), color: .palette[0]).objects[0]
        let top = around.nodes.map(\.point.y).max()!
        XCTAssertEqual(top, 33, accuracy: 0.05)
        let wide = 30 * tan(20 * Double.pi / 180)
        tip.nodes = [Point(-wide, 0), Point(wide, 0), Point(0, 30)].map { PathNode($0) }
        let pointed = try OutlinesOffsets.around(tip, options: options(3), color: .palette[0]).objects[0]
        XCTAssertEqual(pointed.nodes.map(\.point.y).max()!, 30 + 3 / sin(20 * Double.pi / 180), accuracy: 0.05)
    }

    func testOnlyClosedShapes() {
        var line = square(size: 20); line.closed = false; line.digitizing = DigitizingSettings(kind: .run)
        XCTAssertThrowsError(try OutlinesOffsets.around(line, options: OutlineOptions(), color: .palette[0]))
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
