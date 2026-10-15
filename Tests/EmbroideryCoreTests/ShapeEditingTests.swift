// Checks Weld, Knife and Smooth Shapes: welding overlapping shapes into one fill with the topmost one's settings,
// cutting fills, lines and satins along a knife line, and thinning nodes without moving the outline much.
import XCTest
@testable import EmbroideryCore

final class ShapeEditingTests: XCTestCase {
    private func square(_ name: String, at center: Point, size: Double = 10) -> RunObject {
        let h = size / 2
        var object = RunObject(name: name, nodes: [Point(-h, -h), Point(h, -h), Point(h, h), Point(-h, h)].map { PathNode(center + $0) }, color: ThreadColor.palette[0])
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    private func area(_ object: RunObject) -> Double {
        abs(AreaGeometry.area(AreaGeometry.ring(object.nodes))) - (object.holes ?? []).map { abs(AreaGeometry.area(AreaGeometry.ring($0))) }.reduce(0, +)
    }
    /// A satin column 4 mm wide running 20 mm along x, with five rungs.
    private func satin() -> RunObject {
        var object = RunObject(name: "Column", nodes: stride(from: 0.0, through: 20, by: 5).flatMap { [PathNode(Point($0, 2)), PathNode(Point($0, -2))] }, color: ThreadColor.palette[2])
        object.digitizing = DigitizingSettings(kind: .satin)
        return object
    }

    func testWeldMergesOverlapsWithTheTopmostSettingsInItsPlace() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0)), square("Other", at: Point(40, 40)), square("B", at: Point(5, 0))]
        design.objects[0].digitizing?.angle = 10; design.objects[2].digitizing?.angle = 30; design.objects[2].color = ThreadColor.palette[3]
        let ids = try design.weld([design.objects[0].id, design.objects[2].id])
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(design.objects.map(\.name), ["Other", "B"], "the weld sews where B, the topmost, sewed")
        let welded = design.objects[1]
        XCTAssertEqual(welded.id, ids[0])
        XCTAssertEqual(welded.settings.angle, 30); XCTAssertEqual(welded.color, ThreadColor.palette[3])
        XCTAssertEqual(area(welded), 150, accuracy: 0.05, "two 10 × 10 squares overlapping by half")
        XCTAssertLessThanOrEqual(welded.nodes.count, 8, "straight edges don't keep extra nodes")
        XCTAssertGreaterThan(try RunningEngine.compile(design).stitchCount, 0, "the welded fill sews")
    }

    func testWeldKeepsPartsThatDontTouchSeparate() throws {
        var design = Design()
        design.objects = [square("A", at: Point(0, 0)), square("B", at: Point(30, 0), size: 6)]
        let ids = try design.weld(Set(design.objects.map(\.id)))
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(design.objects.map(area).map { ($0 * 10).rounded() / 10 }, [100, 36], "largest first")
    }

    func testWeldingASatinOnTopGivesAFillInItsColor() throws {
        var design = Design()
        design.objects = [square("Patch", at: Point(10, 0)), satin()]
        let ids = try design.weld(Set(design.objects.map(\.id)))
        XCTAssertEqual(ids.count, 1)
        let welded = design.objects[0]
        XCTAssertEqual(welded.kind, .fill); XCTAssertEqual(welded.color, ThreadColor.palette[2])
        XCTAssertEqual(area(welded), 100 + 20 * 4 - 10 * 4, accuracy: 0.05, "the column overlaps the patch's left half")
    }

    func testKnifeSplitsAFillKeepingItsSettings() throws {
        var design = Design()
        design.objects = [square("Leaf", at: Point(0, 0))]
        design.objects[0].digitizing?.angle = 45
        let pieces = try design.cut([design.objects[0].id], along: [Point(-2, -8), Point(2, 8)])
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(design.objects.map(\.name), ["Leaf", "Leaf 2"])
        XCTAssertEqual(design.objects.map(\.settings.angle), [45, 45])
        XCTAssertEqual(design.objects.map(area).reduce(0, +), 100, accuracy: 0.05, "nothing is lost but the hairline cut")
        XCTAssertEqual(area(design.objects[0]), 50, accuracy: 0.05, "the line runs through the middle")
        XCTAssertGreaterThan(try RunningEngine.compile(design).stitchCount, 0, "both pieces sew")

        var missed = Design(); missed.objects = [square("Leaf", at: Point(0, 0))]
        XCTAssertTrue(try missed.cut([missed.objects[0].id], along: [Point(-2, -8), Point(0, 0)]).isEmpty, "a line that stops inside doesn't cut")
        XCTAssertEqual(missed.objects.count, 1)
    }

    func testKnifeThenWeldPutsTheShapeBackTogether() throws {
        var design = Design()
        design.objects = [square("Leaf", at: Point(0, 0))]
        let pieces = try design.cut([design.objects[0].id], along: [Point(-8, -3), Point(8, 3)])
        let welded = try design.weld(Set(pieces))
        XCTAssertEqual(welded.count, 1)
        XCTAssertEqual(area(design.objects[0]), 100, accuracy: 0.05)
    }

    func testKnifeCutsLinesWhereItCrossesThem() throws {
        var design = Design()
        design.objects = [RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(30, 0))], color: ThreadColor.palette[0])]
        let pieces = try design.cut([design.objects[0].id], along: [Point(10, -5), Point(10, 5), Point(20, 5), Point(20, -5)])
        XCTAssertEqual(pieces.count, 3)
        let ends = design.objects.map { $0.nodes.map { ($0.point.x * 1000).rounded() / 1000 } }
        XCTAssertEqual(ends, [[0, 10], [10, 20], [20, 30]])
    }

    func testKnifeThroughANodeLeavesNoStub() throws {
        let line = RunObject(name: "Line", nodes: [Point(0, 0), Point(10, 0), Point(20, 0)].map { PathNode($0) }, color: ThreadColor.palette[0])
        for knife in [[Point(10, -5), Point(10, 5)], [Point(3, -5), Point(5, 0), Point(7, 5)]] {   // through a node; a corner on the line
            var design = Design(); design.objects = [line]
            XCTAssertEqual(try design.cut([line.id], along: knife).count, 2, "\(knife)")
            for piece in design.objects {
                let points = piece.nodes.map(\.point)
                XCTAssertGreaterThan(zip(points, points.dropFirst()).map { $0.distance(to: $1) }.min() ?? 0, 0.01, "\(knife): no zero-length stretch in \(points)")
            }
        }
    }

    func testKnifeCutsASatinAcrossItsColumn() throws {
        var design = Design()
        design.objects = [satin()]
        let pieces = try design.cut([design.objects[0].id], along: [Point(7, -5), Point(7, 5)])
        XCTAssertEqual(pieces.count, 2)
        for piece in design.objects { XCTAssertEqual(piece.nodes.count % 2, 0); XCTAssertEqual(piece.kind, .satin) }
        for (point, expected) in zip(design.objects[0].nodes.suffix(2).map(\.point) + design.objects[1].nodes.prefix(2).map(\.point), [Point(7, 2), Point(7, -2), Point(7, 2), Point(7, -2)]) {
            XCTAssertEqual(point.distance(to: expected), 0, accuracy: 1e-6, "the first piece ends with a rung on the cut, and the second starts there")
        }

        // A slanted cut crosses the rails in different places: the shorter side gets a node so the rungs pair up.
        var slanted = Design(); slanted.objects = [satin()]
        XCTAssertEqual(try slanted.cut([slanted.objects[0].id], along: [Point(3, -5), Point(7, 5)]).count, 2)
        for piece in slanted.objects { XCTAssertEqual(piece.rail(0).count, piece.rail(1).count) }
        XCTAssertGreaterThan(try RunningEngine.compile(slanted).stitchCount, 0, "both pieces sew")
    }

    func testKnifeOpensABorderAndCutsItInTwo() throws {
        // A square border: an outer and an inner loop, rung by rung.
        let outer = [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)], inner = outer.map { $0 * 0.7 }
        var border = RunObject(name: "Border", nodes: zip(outer, inner).flatMap { [PathNode($0), PathNode($1)] }, color: ThreadColor.palette[1])
        border.digitizing = DigitizingSettings(kind: .satin); border.closed = true
        var once = Design(); once.objects = [border]
        XCTAssertEqual(try once.cut([border.id], along: [Point(0, 5), Point(0, 15)]).count, 1, "one cut opens the ring")
        XCTAssertFalse(once.objects[0].closed)
        var twice = Design(); twice.objects = [border]
        XCTAssertEqual(try twice.cut([border.id], along: [Point(0, 15), Point(0, -15)]).count, 2)
        XCTAssertGreaterThan(try RunningEngine.compile(twice).stitchCount, 0, "both pieces sew")
    }

    func testKnifeCutNearABordersStartKeepsItsRungsAcrossTheColumn() throws {
        // The cut crosses the outer loop in its last stretch and the inner loop in its first: the pieces must still
        // pair each outer point with the inner point across from it, not with one round the other side of the hole.
        let outer = [Point(-10, -10), Point(10, -10), Point(10, 10), Point(-10, 10)], inner = outer.map { $0 * 0.7 }
        var border = RunObject(name: "Border", nodes: zip(outer, inner).flatMap { [PathNode($0), PathNode($1)] }, color: ThreadColor.palette[1])
        border.digitizing = DigitizingSettings(kind: .satin); border.closed = true
        var design = Design(); design.objects = [border]
        XCTAssertEqual(try design.cut([border.id], along: [Point(-11, -9.5), Point(-5, -6), Point(12, 0)]).count, 2)
        for piece in design.objects {
            let rungs = zip(piece.rail(0), piece.rail(1)).map { $0.point.distance(to: $1.point) }
            XCTAssertLessThan(rungs.max() ?? 0, 6, "\(piece.name): rungs stay about the column's width (3 to 4.3 mm)")
        }
    }

    func testKnifePiecesKeepOnlyTheStitchAnglesThatReachThem() throws {
        var design = Design()
        design.objects = [square("Turning", at: Point(0, 0), size: 20)]
        design.objects[0].digitizing?.angleLines = [[Point(3, -12), Point(4, 12)], [Point(6, -12), Point(5, 12)]]
        XCTAssertEqual(try design.cut([design.objects[0].id], along: [Point(-2, -15), Point(-2, 15)]).count, 2)
        let left = try XCTUnwrap(design.objects.first { $0.nodes.allSatisfy { $0.point.x < -1 } })
        let right = try XCTUnwrap(design.objects.first { $0.nodes.allSatisfy { $0.point.x > -3 } })
        XCTAssertEqual(right.settings.angleLines?.count, 2, "both lines cross the right piece")
        XCTAssertNil(left.settings.angleLines, "neither line reaches the left piece")
        XCTAssertEqual(left.settings.angle, atan2(24, 1) * 180 / .pi, accuracy: 0.001, "so it sews straight, along the nearest line")
        XCTAssertGreaterThan(try RunningEngine.compile(design).stitchCount, 0, "the design still sews")
    }

    func testSmoothShapesDropsNodesThatBarelyShapeTheOutline() {
        var design = Design()
        var circle = RunObject(name: "Circle", nodes: (0..<200).map { i in let a = Double(i) / 200 * 2 * .pi; return PathNode(Point(10 * cos(a), 10 * sin(a))) }, color: ThreadColor.palette[0])
        circle.closed = true; circle.digitizing = DigitizingSettings(kind: .fill)
        var square = square("Square", at: Point(40, 0))
        square.nodes.insert(PathNode(Point(40, -5)), at: 1)   // an extra node in the middle of the bottom edge
        design.objects = [circle, square]
        let removed = design.smoothShapes(Set(design.objects.map(\.id)))
        XCTAssertGreaterThan(removed, 150)
        XCTAssertEqual(design.objects[1].nodes.count, 4, "only the corners matter on a square")
        let outline = AreaGeometry.ring(design.objects[0].nodes)
        for i in 0..<200 {
            let a = Double(i) / 200 * 2 * .pi, p = Point(10 * cos(a), 10 * sin(a))
            let gap = zip(outline, outline.dropFirst() + outline.prefix(1)).map { p.distance(to: AreaGeometry.projection(p, $0, $1)) }.min()!
            XCTAssertLessThanOrEqual(gap, 0.2 + 1e-9)
        }
    }

    /// Smoothing an outline and its holes separately could leave a hole crossing the outline (each moves up to
    /// 0.2 mm). A fill that would end up broken like that is left as it was.
    func testSmoothShapesNeverPushesAHoleOverTheEdge() throws {
        var design = Design()
        var fill = RunObject(name: "Fill", nodes: [Point(0, 0), Point(10, -0.15), Point(20, 0), Point(20, 20), Point(0, 20)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        fill.holes = [[Point(5, 5), Point(15, 5), Point(10, -0.1)].map { PathNode($0) }]   // its point reaches into the dip in the bottom edge
        XCTAssertNoThrow(try AreaGeometry.validate(([fill.nodes] + fill.holes!).map { AreaGeometry.ring($0) }), "valid to begin with")
        var square = square("Square", at: Point(40, 0))
        square.nodes.insert(PathNode(Point(40, -5)), at: 1)
        design.objects = [fill, square]
        XCTAssertEqual(design.smoothShapes(Set(design.objects.map(\.id))), 1, "only the square's extra node goes")
        XCTAssertEqual(design.objects[0], fill, "the fill is left as it was")
        XCTAssertGreaterThan(try RunningEngine.compile(design).stitchCount, 0, "the design still sews")
    }
}
