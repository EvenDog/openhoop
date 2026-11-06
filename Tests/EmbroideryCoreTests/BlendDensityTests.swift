// Checks that row color blends (straight, wave, guided) are as dense as a tatami fill: Spacing at start is measured
// across two rows, as tatami spacing is. Blends saved before that sew as they did, and changing one in the dialog
// brings it up to date.
import XCTest
@testable import EmbroideryCore

final class BlendDensityTests: XCTestCase {
    let red = ThreadColor("Red", 0xff0000), blue = ThreadColor("Blue", 0x0000ff)

    /// A 30 × 30 mm square tatami fill in red, centered on 0, 0.
    func square() -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(-15, -15), Point(15, -15), Point(15, 15), Point(-15, 15)].map { PathNode($0) }, color: red)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    /// How many stitches `objects` sew between them, without underlay.
    func count(_ objects: [RunObject]) throws -> Int {
        try objects.map { object in
            var alone = object; alone.digitizing?.underlay = .none; alone.blendOf = nil
            var design = Design(); design.objects = [alone]
            return try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.count
        }.reduce(0, +)
    }

    func testRowBlendsAreAsDenseAsTatami() throws {
        let tatami = try count([square()])
        for shape in [BlendShape.straight, .wave] {
            let layers = ColorBlend.layers(of: square(), second: blue, direction: 0, shape: shape)
            XCTAssertEqual(layers.map { $0.settings.blendRowsPaired }, [true, true])
            XCTAssertEqual(Double(try count(layers)), Double(tatami), accuracy: Double(tatami) * 0.25, "\(shape) blend vs tatami")
        }
        XCTAssertNil(ColorBlend.layers(of: square(), second: blue, direction: 0, shape: .radial)[0].settings.blendRowsPaired, "radial rays aren't paired")
    }

    func testOlderBlendsSewAsTheyDidUntilChanged() throws {
        let older = ColorBlend.layers(of: square(), second: blue, direction: 0).map { layer -> RunObject in
            var layer = layer; layer.digitizing?.blendRowsPaired = nil; return layer
        }
        let new = try count(ColorBlend.layers(of: square(), second: blue, direction: 0))
        XCTAssertEqual(Double(try count(older)), Double(new) / 2, accuracy: Double(new) * 0.1, "an older blend keeps its rows Spacing at start apart")
        var design = Design(); design.objects = older
        design.editBlend(containing: older[0].id, second: blue, direction: 0, fade: .whole)
        XCTAssertEqual(design.objects.map { $0.settings.blendRowsPaired }, [true, true], "changed in the dialog, it takes the new density")
        XCTAssertTrue(design.needsSchemaNineteen)
    }
}
