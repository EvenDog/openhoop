// Fill styles: contour rings, radial rays and wave rows each cover the whole shape, stay inside it, sew in their
// own direction, and save with the project.
import XCTest
@testable import EmbroideryCore

final class FillStyleTests: XCTestCase {
    private func shape(_ points: [Point], holes: [[Point]] = [], style: FillStyle, center: Point? = nil) -> RunObject {
        var object = RunObject(name: "Shape", nodes: points.map { PathNode($0) }, color: .palette[0])
        object.closed = true; object.holes = holes.isEmpty ? nil : holes.map { $0.map { PathNode($0) } }
        object.digitizing = DigitizingSettings(kind: .fill); object.digitizing?.fillStyle = style
        object.digitizing?.radialCenter = center; object.stitchLength = 2.5
        return object
    }
    private func rectangle(_ w: Double, _ h: Double) -> [Point] { [Point(-w / 2, -h / 2), Point(w / 2, -h / 2), Point(w / 2, h / 2), Point(-w / 2, h / 2)] }
    private func circle(_ r: Double, center: Point = Point(0, 0), clockwise: Bool = false) -> [Point] {
        let points = (0..<72).map { center + Point(cos(Double($0) * .pi / 36), sin(Double($0) * .pi / 36)) * r }
        return clockwise ? points.reversed() : points
    }
    /// The top-layer stitches (travel runs included), as segments.
    private func topSegments(_ stitches: ObjectStitches) -> [(Point, Point)] {
        stitches.sections.filter { !$0.underlay }.flatMap { section in zip(section.points, section.points.dropFirst()).map { ($0, $1) } }
    }
    private func distance(_ p: Point, _ a: Point, _ b: Point) -> Double { p.distance(to: AreaGeometry.projection(p, a, b)) }

    /// Every top stitch stays inside the compensated shape, and every point of the shape is close to a stitch.
    private func assertCoversAndStaysInside(_ object: RunObject, file: StaticString = #filePath, line: UInt = #line) throws {
        let stitches = try AreaEngine.fill(object)
        let segments = topSegments(stitches)
        XCTAssertFalse(segments.isEmpty, file: file, line: line)
        let original = ([object.nodes] + (object.holes ?? [])).map { AreaGeometry.ring($0) }
        let bounds = try AreaGeometry.offset(original, by: object.settings.expansion + 0.05)
        let outside = segments.filter { !AreaGeometry.segmentInside($0.0, $0.1, rings: bounds) }.count
        XCTAssertEqual(outside, 0, "stitches outside the shape", file: file, line: line)
        // Grid points well inside the shape, each within 0.6 mm of a stitch (rows are 0.4 mm apart).
        let inside = try AreaGeometry.offset(original, by: -0.3)
        let all = original.flatMap { $0 }
        var gaps = 0, checked = 0
        for x in stride(from: all.map(\.x).min()!, through: all.map(\.x).max()!, by: 0.7) {
            for y in stride(from: all.map(\.y).min()!, through: all.map(\.y).max()!, by: 0.7) where AreaGeometry.contains(Point(x, y), rings: inside) {
                checked += 1
                if !segments.contains(where: { distance(Point(x, y), $0.0, $0.1) <= 0.6 }) { gaps += 1 }
            }
        }
        XCTAssertGreaterThan(checked, 50, file: file, line: line)
        XCTAssertEqual(gaps, 0, "uncovered spots", file: file, line: line)
        var design = Design(); design.objects = [object]
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100, file: file, line: line)
    }

    func testContourFollowsTheOutline() throws {
        let object = shape(rectangle(30, 20), style: .contour)
        try assertCoversAndStaysInside(object)
        // After the underlay (and short travel runs inside the shape), the whole top layer is one spiral.
        let top = try AreaEngine.fill(object).sections.filter { !$0.underlay && $0.points.count > 40 }
        XCTAssertEqual(top.count, 1, "A rectangle sews as one spiral")
        // The first ring runs right along the drawn edge: the fill is grown 0.2 mm for pull compensation, and the
        // first ring sits half a row (0.2 mm) inside that.
        let first = top[0].points.prefix(10)
        XCTAssertTrue(first.allSatisfy { abs(abs($0.x) - 15) < 0.3 || abs(abs($0.y) - 10) < 0.3 })
    }

    func testContourAroundAHoleAndAcrossTwoLobes() throws {
        try assertCoversAndStaysInside(shape(circle(12), holes: [circle(4, clockwise: true)], style: .contour))
        // A dumbbell: two squares joined by a narrow neck. Once the rings no longer fit through the neck, each lobe
        // finishes separately; the fill still sews without any trims (travel runs inside the shape join the lobes).
        let dumbbell = [Point(-20, -8), Point(-4, -8), Point(-4, -1), Point(4, -1), Point(4, -8), Point(20, -8), Point(20, 8), Point(4, 8), Point(4, 1), Point(-4, 1), Point(-4, 8), Point(-20, 8)]
        let object = shape(dumbbell, style: .contour)
        try assertCoversAndStaysInside(object)
        var design = Design(); design.objects = [object]
        XCTAssertEqual(try StitchEngine.compile(design).commands.filter { $0.op == .trim }.count, 1, "Only the trim after the object")
    }

    func testContourStartsAtTheStartPoint() throws {
        var object = shape(rectangle(30, 20), style: .contour)
        object.entry = Point(15, 3)
        let first = try AreaEngine.fill(object).sections.last!.points[0]   // the spiral comes last, after the underlay
        XCTAssertLessThan(first.distance(to: Point(15, 3)), 2)
    }

    func testRadialRaysFanFromTheCenter() throws {
        let object = shape(circle(15), style: .radial)
        try assertCoversAndStaysInside(object)
        let segments = topSegments(try AreaEngine.fill(object)).filter { $0.0.distance(to: $0.1) > 1 }
        // Long stitches point straight out from the center.
        let radial = segments.filter { a, b in
            let direction = (b - a) * (1 / a.distance(to: b)), out = ((a + b) * 0.5) * (1 / max(0.001, ((a + b) * 0.5).distance(to: Point(0, 0))))
            return abs(direction.x * out.x + direction.y * out.y) > 0.97
        }
        XCTAssertGreaterThan(Double(radial.count) / Double(segments.count), 0.9)
        // The middle doesn't pile up: few stitches end within 1 mm of the center.
        let points = try AreaEngine.fill(object).sections.filter { !$0.underlay }.flatMap(\.points)
        XCTAssertLessThan(points.filter { $0.distance(to: Point(0, 0)) < 1 }.count, 80)
    }

    func testRadialStarSewsInOnePass() throws {
        // A six-pointed star: near the center, where its edge dips in, some rays stop short of the shape. The rays
        // around them still sew as one continuous pass, with no trims inside the shape.
        let star = (0..<12).map { i in Point(cos(Double(i) * .pi / 6), sin(Double(i) * .pi / 6)) * (i % 2 == 0 ? 16 : 11.5) }
        var object = shape(star, style: .radial)
        object.nodes = object.nodes.map { PathNode($0.point, smooth: true) }
        try assertCoversAndStaysInside(object)
        var design = Design(); design.objects = [object]
        XCTAssertEqual(try StitchEngine.compile(design).commands.filter { $0.op == .trim }.count, 1, "Only the trim after the object")
        XCTAssertFalse(try AreaEngine.fill(object).warnings.contains { $0.contains("trim") })
    }

    func testRadialAroundAHoleAndFromAChosenCenter() throws {
        try assertCoversAndStaysInside(shape(circle(14), holes: [circle(5, clockwise: true)], style: .radial))
        // A center off to one side (and a center outside a crescent-like shape still works).
        try assertCoversAndStaysInside(shape(rectangle(30, 20), style: .radial, center: Point(-10, 5)))
        try assertCoversAndStaysInside(shape(rectangle(20, 10), style: .radial, center: Point(0, -15)))
    }

    func testWaveRowsRipple() throws {
        var object = shape(rectangle(30, 20), style: .wave)
        object.digitizing?.angle = 0; object.digitizing?.waveHeight = 3; object.digitizing?.waveLength = 10
        try assertCoversAndStaysInside(object)
        // With level rows, a straight row's stitches share one height; wavy rows rise and fall by the wave height.
        // Look at a row from the middle of the main section (the edge rows of a wave are partial ripples).
        func middleRow(_ object: RunObject) throws -> [Point] {
            let main = try AreaEngine.fill(object).sections.filter { !$0.underlay }.max { $0.points.count < $1.points.count }!.points
            // A row's left end, mid-height, where the row heads right.
            let start = main.indices.dropLast().first { abs(main[$0].x + 14.5) < 1.3 && abs(main[$0].y) < 1 && main[$0 + 1].x > main[$0].x + 1 }!
            return Array(main[start...].prefix(10))   // about 25 mm of that row
        }
        let wavy = try middleRow(object)
        XCTAssertGreaterThan(wavy.map(\.y).max()! - wavy.map(\.y).min()!, 2.5)
        var tatami = object; tatami.digitizing?.fillStyle = nil
        let straight = try middleRow(tatami)
        XCTAssertLessThan(straight.map(\.y).max()! - straight.map(\.y).min()!, 0.001)
        // The partial ripples along the edges are joined by travel runs inside the shape: no extra trims.
        var design = Design(); design.objects = [object]
        XCTAssertEqual(try StitchEngine.compile(design).commands.filter { $0.op == .trim }.count, 1)
    }

    func testStylesSaveAndCenterMovesWithTheShape() throws {
        var object = shape(rectangle(20, 20), style: .radial, center: Point(2, 3))
        object.transform { Point(-$0.y, $0.x) + Point(10, 0) }
        XCTAssertEqual(object.settings.radialCenter, Point(7, 2))
        var design = Design(); design.objects = [object]
        XCTAssertTrue(design.needsSchemaFive, "Older versions would sew it as straight rows")
        let reopened = try JSONDecoder().decode(Design.self, from: try JSONEncoder().encode(design))
        XCTAssertEqual(reopened.objects[0].settings.fillStyle, .radial)
        XCTAssertEqual(reopened.objects[0].settings.radialCenter, Point(7, 2))
        design.objects[0].digitizing?.fillStyle = .tatami; design.objects[0].digitizing?.radialCenter = nil
        XCTAssertFalse(design.needsSchemaFive)
    }

    /// A damaged file or paste with extreme fill style values is refused when it's read, before the fill engines
    /// could overflow (a far-off radial center) or run for ages (a microscopic wave).
    func testExtremeFillStyleValuesAreRefused() {
        var design = Design(); design.objects = [shape(rectangle(20, 20), style: .radial, center: Point(5, 5))]
        XCTAssertNoThrow(try design.validate())
        for center in [Point(1e300, 0), Point(.nan, 0), Point(0, 20_000)] {
            design.objects[0].digitizing?.radialCenter = center
            XCTAssertThrowsError(try design.validate(), "radial center \(center)")
        }
        design.objects = [shape(rectangle(20, 20), style: .wave)]
        design.objects[0].digitizing?.waveHeight = 3; design.objects[0].digitizing?.waveLength = 10
        XCTAssertNoThrow(try design.validate())
        for (height, length) in [(3.0, 1e-12), (3.0, 1000), (0, 10), (.infinity, 10)] {
            design.objects[0].digitizing?.waveHeight = height; design.objects[0].digitizing?.waveLength = length
            XCTAssertThrowsError(try design.validate(), "wave \(height) × \(length)")
        }
    }

    /// Radial rays join on points worked out two different ways, which come out a hair apart; they used to be sewn
    /// as two stitches in the same hole (4–15% of all radial stitches).
    func testRadialNeverSewsTheSameHoleTwiceInARow() throws {
        for (shape, size) in [(BasicShape.ellipse, 30.0), (.heart, 8), (.rectangle, 80), (.star, 30)] {
            let outline = AreaGeometry.ring(ShapeGeometry.nodes(shape, in: (Point(-size / 2, -size / 2), Point(size / 2, size / 2))))
            let sections = try FillStyles.radial(in: [outline], center: Point(0, 0), spacing: 0.4, length: 3, start: nil)
            let repeats = sections.map { section in zip(section, section.dropFirst()).filter { $0.distance(to: $1) < 0.000001 }.count }.reduce(0, +)
            XCTAssertEqual(repeats, 0, "\(shape) \(size) mm")
        }
    }

    /// On round shapes, contour rings spiral into each other instead of stepping across at the end of each lap, so
    /// there's no seam: the needle never drops a whole row inward in one stitch. Shapes with sharp corners keep the
    /// step (spiralling bends the laps across each other near corners).
    func testContourSpiralsOnRoundShapesWithoutASeam() throws {
        func inwardSteps(_ sections: [[Point]], center: Point) -> Int {
            sections.map { s in zip(s, s.dropFirst()).filter { $0.distance(to: center) - $1.distance(to: center) > 0.3 }.count }.reduce(0, +)
        }
        let circle = circle(15)
        let round = try FillStyles.contour(in: [circle], spacing: 0.4, length: 3, start: nil)
        XCTAssertEqual(round.count, 1)
        XCTAssertEqual(inwardSteps(round, center: Point(0, 0)), 0, "no lap ends with a step inward")
        let flat = round[0].map { $0.distance(to: Point(0, 0)) }
        XCTAssertLessThan(flat.last!, 1.5, "it still reaches the middle")
        XCTAssertTrue(round[0].allSatisfy { AreaGeometry.contains($0, rings: [circle]) })
        XCTAssertTrue(zip(round[0], round[0].dropFirst()).allSatisfy { $0.distance(to: $1) <= 3.0001 }, "no stitch over the stitch length")
        let star = AreaGeometry.ring(ShapeGeometry.nodes(.star, in: (Point(-15, -15), Point(15, 15))))
        XCTAssertGreaterThan(inwardSteps(try FillStyles.contour(in: [star], spacing: 0.4, length: 3, start: nil), center: Point(0, 0)), 5, "a star keeps its steps")
    }

    /// A round wave fill has small pieces along its edge. Some near the start used to be skipped (a big section
    /// started nearer) and left for last, when the needle was across the shape: a long jump and an extra trim.
    func testWaveFillLeavesNoStrayPieceForLast() throws {
        var object = try ShapeStitching.closedShape(ShapeGeometry.nodes(.ellipse, in: (Point(-15, -15), Point(15, 15))), fill: .wave, outline: nil, name: "Wave", color: .palette[0])[0]
        object.digitizing?.underlay = .none; object.digitizing?.waveLength = 6
        let result = try AreaEngine.fill(object)
        XCTAssertFalse(result.warnings.contains { $0.contains("trim") }, "\(result.warnings)")
        XCTAssertTrue(result.sections.dropFirst().allSatisfy(\.joined), "every section carries on from the one before")
    }

    /// Rings with sharp corners don't spiral: the needle steps across from one ring to the next. That step used to skip
    /// the next ring's first point, so with long stitches one stitch reached past the machine's 12.1 mm limit (found by
    /// the random design tests). Every stitch is now at most the stitch length.
    func testContourStepsBetweenRingsAreNeverLongerThanAStitch() throws {
        for length in [3.0, 7.0, 10.0] {
            let sections = try FillStyles.contour(in: [rectangle(40, 30)], spacing: 2, length: length, start: nil)
            let longest = sections.flatMap { zip($0, $0.dropFirst()).map { $0.distance(to: $1) } }.max() ?? 0
            XCTAssertLessThanOrEqual(longest, length + 0.0001, "stitch length \(length)")
        }
    }
}
