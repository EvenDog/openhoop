// Checks color blends: one fill becomes two gradient fills of the same shape, each color solid at its own end, and
// the blend runs the way it was asked to.
import XCTest
@testable import EmbroideryCore

final class ColorBlendTests: XCTestCase {
    let red = ThreadColor("Red", 0xff0000), blue = ThreadColor("Blue", 0x0000ff)

    /// A 30 × 30 mm square tatami fill in red, centered on 0, 0.
    func square() -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(-15, -15), Point(15, -15), Point(15, 15), Point(-15, 15)].map { PathNode($0) }, color: red)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    /// How many of `object`'s stitches (without underlay, so only its gradient rows count) fall on each side of 0
    /// along `axis`.
    func stitchesEachSide(_ object: RunObject, axis: KeyPath<Point, Double>) throws -> (low: Int, high: Int) {
        var alone = object; alone.digitizing?.underlay = .none
        var design = Design(); design.objects = [alone]
        let points = try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point)
        return (points.filter { $0[keyPath: axis] < 0 }.count, points.filter { $0[keyPath: axis] > 0 }.count)
    }

    func testBlendIsTwoGradientLayersOfTheSameShape() {
        let fill = square(), layers = ColorBlend.layers(of: fill, second: blue, direction: 0)
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers.map(\.color), [red, blue], "The shape's own thread first, then the second color on top")
        XCTAssertEqual(layers[0].id, fill.id, "The bottom layer is the fill itself, so its place in the sewing order stays")
        XCTAssertNotEqual(layers[1].id, fill.id)
        XCTAssertTrue(layers.allSatisfy { $0.settings.fillStyle == .gradient && $0.nodes == fill.nodes })
        XCTAssertEqual(layers[0].settings.underlay, fill.settings.underlay)
        XCTAssertEqual(layers[1].settings.underlay, UnderlayStyle.none, "The bottom layer's underlay covers both")
        XCTAssertNotNil(layers[0].groupID); XCTAssertEqual(layers[0].groupID, layers[1].groupID)
        var design = Design(); design.objects = layers
        XCTAssertNoThrow(try design.validate())
    }

    func testLeftToRightBlend() throws {
        let layers = ColorBlend.layers(of: square(), second: blue, direction: 0)
        let red = try stitchesEachSide(layers[0], axis: \.x), blue = try stitchesEachSide(layers[1], axis: \.x)
        XCTAssertGreaterThan(red.low, red.high * 2, "Red is solid on the left, where the blend starts")
        XCTAssertGreaterThan(blue.high, blue.low * 2, "Blue is solid on the right, where it ends")
    }

    func testBottomToTopBlend() throws {
        let layers = ColorBlend.layers(of: square(), second: blue, direction: 90)
        let red = try stitchesEachSide(layers[0], axis: \.y)
        XCTAssertGreaterThan(red.low, red.high * 2, "Red is solid at the bottom")
    }

    func testAnglesStayInRange() {
        for direction in stride(from: -360.0, through: 720, by: 45) {
            XCTAssertTrue((-180...180).contains(ColorBlend.angle(for: direction)), "\(direction)°")
        }
    }

    func testOnlyPlainFillsCanBlend() {
        XCTAssertTrue(ColorBlend.canBlend(square()))
        var line = square(); line.digitizing = DigitizingSettings(kind: .run)
        var locked = square(); locked.locked = true
        XCTAssertFalse(ColorBlend.canBlend(line)); XCTAssertFalse(ColorBlend.canBlend(locked))
    }

    func testBlendKeepsAnExistingGroup() {
        var fill = square(); let group = UUID(); fill.groupID = group
        XCTAssertEqual(Set(ColorBlend.layers(of: fill, second: blue, direction: 0).map(\.groupID)), [group])
    }
}
