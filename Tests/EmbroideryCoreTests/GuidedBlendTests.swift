// Checks guided color blends: the two layers are guided fills following one guide line, the first thread solid on the
// guide's left side and the second on its right (or the other way round), spaced like a straight blend's rows; the
// layers keep one guide line; and projects with them need file version 19.
import XCTest
@testable import EmbroideryCore

final class GuidedBlendTests: XCTestCase {
    let red = ThreadColor("Red", 0xff0000), blue = ThreadColor("Blue", 0x0000ff)

    /// A 30 × 30 mm square guided fill in red, centered on 0, 0, whose guide runs left to right through the middle
    /// (so its left side is the top).
    func square() -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(-15, -15), Point(15, -15), Point(15, 15), Point(-15, 15)].map { PathNode($0) }, color: red)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        object.digitizing?.fillStyle = .guided; object.digitizing?.guideLine = [Point(-20, 0), Point(0, 3), Point(20, 0)]
        return object
    }
    /// y positions of every stitch each layer sews, without underlay.
    func ys(_ layers: [RunObject]) throws -> [[Double]] {
        try layers.map { layer in
            var alone = layer; alone.digitizing?.underlay = .none; alone.blendOf = nil
            var design = Design(); design.objects = [alone]
            return try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point.y)
        }
    }

    func testFirstThreadOnTheGuidesLeftAndSecondOnItsRight() throws {
        let layers = ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .guided)
        XCTAssertEqual(layers.map(\.settings.fillStyle), [.guided, .guided])
        XCTAssertEqual(layers.map { $0.settings.blendFromEdge }, [false, true])
        XCTAssertEqual(layers[1].settings.guideLine, layers[0].settings.guideLine, "both follow the same guide")
        let y = try ys(layers)
        XCTAssertGreaterThan(y[0].filter { $0 > 9 }.count, y[1].filter { $0 > 9 }.count * 3, "red solid at the top (the guide's left)")
        XCTAssertGreaterThan(y[1].filter { $0 < -9 }.count, y[0].filter { $0 < -9 }.count * 3, "blue solid at the bottom")
        let flipped = try ys(ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .guided, firstAtEdge: true))
        XCTAssertGreaterThan(flipped[0].filter { $0 < -9 }.count, flipped[1].filter { $0 < -9 }.count * 3, "flipped: red at the bottom")
    }

    func testRowsAreSpacedLikeAStraightBlend() throws {
        var plain = square(); plain.digitizing?.fillStyle = .tatami; plain.digitizing?.guideLine = nil
        let straight = try ys(ColorBlend.layers(of: plain, second: blue, direction: 90)).map(\.count).reduce(0, +)
        let guided = try ys(ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .guided)).map(\.count).reduce(0, +)
        XCTAssertEqual(Double(guided), Double(straight), accuracy: Double(straight) * 0.25, "\(guided) stitches vs \(straight) for a straight blend")
    }

    func testLayersKeepOneGuideLineAndNeedFileVersion19() {
        var design = Design(); design.objects = ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .guided)
        XCTAssertTrue(design.needsSchemaNineteen)
        let previous = design
        design.objects[1].digitizing?.guideLine = [Point(-20, -5), Point(20, 5)]
        design.syncBlends(from: previous)
        XCTAssertEqual(design.objects[0].settings.guideLine, [Point(-20, -5), Point(20, 5)], "redrawing either layer's guide moves both")
    }
}
