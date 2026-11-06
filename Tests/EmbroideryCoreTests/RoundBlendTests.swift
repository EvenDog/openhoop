// Checks radial and contour color blends: the two layers are radial (or contour) fills of the same shape, the first
// color in the middle and the second at the edge (or the other way round), they fill the shape between them, the blend
// can change kind, and projects with them need file version 19.
import XCTest
@testable import EmbroideryCore

final class RoundBlendTests: XCTestCase {
    let red = ThreadColor("Red", 0xff0000), blue = ThreadColor("Blue", 0x0000ff)

    /// A circle of radius 20 mm (48 points) as a red tatami fill, centered on 0, 0.
    func disc() -> RunObject {
        let ring = (0..<48).map { Point(20 * cos(Double($0) * .pi / 24), 20 * sin(Double($0) * .pi / 24)) }
        var object = RunObject(name: "Disc", nodes: ring.map { PathNode($0) }, color: red)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    /// Distances from the center of every stitch each layer sews, without underlay.
    func distances(_ layers: [RunObject]) throws -> [[Double]] {
        try layers.map { layer in
            var alone = layer; alone.digitizing?.underlay = .none; alone.blendOf = nil
            var design = Design(); design.objects = [alone]
            return try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map { hypot($0.point.x, $0.point.y) }
        }
    }
    func share(_ values: [Double], _ range: ClosedRange<Double>) -> Int { values.filter { range.contains($0) }.count }

    func testRadialLayersAreRadialFillsWithOppositeSolidSides() {
        let layers = ColorBlend.layers(of: disc(), second: blue, direction: 0, shape: .radial)
        XCTAssertEqual(layers.map(\.settings.fillStyle), [.radial, .radial])
        XCTAssertEqual(layers.map { $0.settings.blendFromEdge }, [false, true], "first color in the middle, second at the edge")
        XCTAssertEqual(layers[1].blendOf, layers[0].id)
        XCTAssertEqual(ColorBlend.shape(of: layers[0]), .radial)
        let flipped = ColorBlend.layers(of: disc(), second: blue, direction: 0, shape: .contour, firstAtEdge: true)
        XCTAssertEqual(flipped.map { $0.settings.blendFromEdge }, [true, false])
        XCTAssertEqual(flipped.map(\.settings.fillStyle), [.contour, .contour])
    }

    func testRadialBlendIsFirstColorInTheMiddleAndSecondAtTheEdge() throws {
        let d = try distances(ColorBlend.layers(of: disc(), second: blue, direction: 0, shape: .radial))
        XCTAssertGreaterThan(share(d[0], 0...5), share(d[1], 0...5) * 3, "the middle is mostly red")
        XCTAssertGreaterThan(share(d[1], 15...21), share(d[0], 15...21) * 3, "the edge is mostly blue")
        // Fills reach 0.2 mm past their outline (pull compensation), as a plain radial fill does.
        XCTAssertTrue(d[0].allSatisfy { $0 < 20.25 } && d[1].allSatisfy { $0 < 20.25 }, "nothing outside the disc")
    }

    /// Contour blends measure by area: half and half on the Mix bar is where half the disc's area is each side, about
    /// 14 mm out (20 / √2), not halfway in at 10 mm.
    func testContourBlendRunsFromTheEdgeWhenAskedAndMixesByArea() throws {
        let d = try distances(ColorBlend.layers(of: disc(), second: blue, direction: 0, shape: .contour, firstAtEdge: true))
        XCTAssertGreaterThan(share(d[0], 18...21), share(d[1], 18...21) * 3, "red rings at the edge")
        XCTAssertGreaterThan(share(d[1], 0...7), share(d[0], 0...7) * 3, "blue rings in the middle")
        let red = Double(share(d[0], 12...16)), blue = Double(share(d[1], 12...16))
        XCTAssertEqual(red / (red + blue), 0.5, accuracy: 0.2, "about half and half around 14 mm")
    }

    /// Between them the two layers fill the disc about as densely as one plain fill: each ray changes color at one
    /// point, and the rings of one layer fill the gaps in the other's.
    func testTheTwoLayersCoverTheShapeOnce() throws {
        for shape in [BlendShape.radial, .contour] {
            var plain = disc(); plain.digitizing?.fillStyle = shape.fillStyle
            let alone = try distances([plain])[0].count
            let both = try distances(ColorBlend.layers(of: disc(), second: blue, direction: 0, shape: shape)).map(\.count).reduce(0, +)
            XCTAssertEqual(Double(both), Double(alone), accuracy: Double(alone) * 0.35, "\(shape): \(both) stitches vs \(alone) for one fill")
        }
    }

    func testEditingChangesTheKindOfBlend() {
        var design = Design(); design.objects = ColorBlend.layers(of: disc(), second: blue, direction: 0)
        design.editBlend(containing: design.objects[0].id, second: blue, direction: 0, fade: .whole, shape: .contour, firstAtEdge: true)
        XCTAssertEqual(design.objects.map(\.settings.fillStyle), [.contour, .contour])
        XCTAssertEqual(design.objects.map { $0.settings.blendFromEdge }, [true, false])
        design.editBlend(containing: design.objects[0].id, second: blue, direction: 90, fade: .whole, shape: .straight)
        XCTAssertEqual(design.objects.map(\.settings.fillStyle), [.gradient, .gradient])
        XCTAssertEqual(design.objects.map { $0.settings.blendFromEdge }, [nil, nil])
    }

    func testLayersKeepOneCenterAndComeApartWhenAStyleChanges() {
        var design = Design(); design.objects = ColorBlend.layers(of: disc(), second: blue, direction: 0, shape: .radial)
        var previous = design
        design.objects[1].digitizing?.radialCenter = Point(3, 4)
        design.syncBlends(from: previous)
        XCTAssertEqual(design.objects[0].settings.radialCenter, Point(3, 4), "moving the second layer's center moves the first's")
        previous = design
        design.objects[0].digitizing?.fillStyle = .tatami
        design.syncBlends(from: previous)
        XCTAssertNil(design.objects[1].blendOf, "a layer in another style ends the blend")
        XCTAssertNil(design.objects[1].settings.blendFade, "and the radial layer left behind sews whole")
    }

    func testRoundBlendsNeedFileVersion19() throws {
        var design = Design(); design.objects = ColorBlend.layers(of: disc(), second: blue, direction: 0)
        XCTAssertFalse(design.needsSchemaNineteen, "a straight blend still opens in older versions")
        design.objects = ColorBlend.layers(of: disc(), second: blue, direction: 0, shape: .radial)
        XCTAssertTrue(design.needsSchemaNineteen)
        design.schemaVersion = 19
        XCTAssertNoThrow(try design.validate())
    }

    func testFadeExtentIsTheInverseOfCoverage() {
        let fade = BlendFade(start: 0.2, middle: 0.5, end: 0.6)
        for share in [0.1, 0.3, 0.5, 0.7, 0.9] {
            XCTAssertEqual(fade.coverage(at: fade.extent(covering: share)), share, accuracy: 1e-9)
        }
        XCTAssertEqual(fade.extent(covering: 1), 0.2); XCTAssertEqual(fade.extent(covering: 0), 0.6)
    }
}
