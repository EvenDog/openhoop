// Checks wave color blends: the two layers are wave fills of the same shape whose rows spread apart like a straight
// blend's, the first thread solid on its side and the second on the other; the layers keep one wave size; and projects
// with them need file version 19.
import XCTest
@testable import EmbroideryCore

final class WaveBlendTests: XCTestCase {
    let red = ThreadColor("Red", 0xff0000), blue = ThreadColor("Blue", 0x0000ff)

    /// A 30 × 30 mm square tatami fill in red, centered on 0, 0.
    func square() -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(-15, -15), Point(15, -15), Point(15, 15), Point(-15, 15)].map { PathNode($0) }, color: red)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    /// x positions of every stitch each layer sews, without underlay.
    func xs(_ layers: [RunObject]) throws -> [[Double]] {
        try layers.map { layer in
            var alone = layer; alone.digitizing?.underlay = .none; alone.blendOf = nil
            var design = Design(); design.objects = [alone]
            return try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point.x)
        }
    }

    func testWaveLayersRunLikeAStraightBlend() throws {
        let layers = ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .wave)
        XCTAssertEqual(layers.map(\.settings.fillStyle), [.wave, .wave])
        XCTAssertEqual(layers.map { $0.settings.blendFromEdge }, [nil, nil], "a wave blend runs in a direction")
        XCTAssertEqual(ColorBlend.shape(of: layers[0]), .wave)
        let x = try xs(layers)
        XCTAssertGreaterThan(x[0].filter { $0 < -8 }.count, x[1].filter { $0 < -8 }.count * 3, "red solid on the left")
        XCTAssertGreaterThan(x[1].filter { $0 > 8 }.count, x[0].filter { $0 > 8 }.count * 3, "blue solid on the right")
    }

    /// The rows are spaced like a straight blend's (Spacing at start where solid, spreading out as each fades), so the
    /// two layers sew about as many stitches as a straight blend of the same shape.
    func testRowsAreSpacedLikeAStraightBlend() throws {
        let straight = try xs(ColorBlend.layers(of: square(), second: blue, direction: 0)).map(\.count).reduce(0, +)
        let wave = try xs(ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .wave)).map(\.count).reduce(0, +)
        XCTAssertEqual(Double(wave), Double(straight), accuracy: Double(straight) * 0.15, "\(wave) stitches vs \(straight) for a straight blend")
    }

    func testLayersKeepOneWaveSize() {
        var design = Design(); design.objects = ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .wave)
        let previous = design
        design.objects[1].digitizing?.waveHeight = 3; design.objects[1].digitizing?.waveLength = 12
        design.syncBlends(from: previous)
        XCTAssertEqual(design.objects[0].settings.waveHeight, 3); XCTAssertEqual(design.objects[0].settings.waveLength, 12)
    }

    func testWaveBlendsNeedFileVersion19AndComeApartLikeTheOthers() {
        var design = Design(); design.objects = ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .wave)
        XCTAssertTrue(design.needsSchemaNineteen)
        let previous = design
        design.objects[0].digitizing?.fillStyle = .tatami
        design.syncBlends(from: previous)
        XCTAssertNil(design.objects[1].blendOf)
        XCTAssertNil(design.objects[1].settings.blendFade, "the wave layer left behind sews whole")
    }
}
