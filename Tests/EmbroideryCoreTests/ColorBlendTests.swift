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

    // MARK: The two layers stay in step

    /// A design holding one left-to-right blend of the square.
    func blended() -> Design {
        var design = Design(); design.objects = ColorBlend.layers(of: square(), second: blue, direction: 0)
        return design
    }
    /// `design` after `change`, then synced as the app does after every edit.
    func edited(_ design: Design, _ change: (inout Design) -> Void) -> Design {
        var next = design; change(&next); next.syncBlends(from: design); return next
    }

    func testTheSecondLayerIsLinkedToTheFirst() {
        let design = blended()
        XCTAssertEqual(design.objects[1].blendOf, design.objects[0].id)
        XCTAssertNil(design.objects[0].blendOf)
        XCTAssertEqual(design.blend(containing: design.objects[0].id)?.top, 1)
        XCTAssertEqual(design.blend(containing: design.objects[1].id)?.base, 0)
        XCTAssertFalse(ColorBlend.canBlend(design.objects[1]), "A layer of a blend is edited, not blended again")
        XCTAssertTrue(design.needsSchemaSeventeen)
    }

    func testReshapingEitherLayerReshapesTheOther() {
        let design = blended()
        let topMoved = edited(design) { $0.objects[1].nodes[2].point = Point(25, 20) }
        XCTAssertEqual(topMoved.objects[0].nodes, topMoved.objects[1].nodes, "The first layer follows the second")
        XCTAssertEqual(topMoved.objects[0].nodes[2].point, Point(25, 20))
        let baseMoved = edited(design) { $0.objects[0].holes = [[Point(-5, -5), Point(5, -5), Point(5, 5)].map { PathNode($0) }] }
        XCTAssertEqual(baseMoved.objects[1].holes, baseMoved.objects[0].holes, "The second layer follows the first")
        let bothMoved = edited(design) { design in for i in 0..<2 { design.objects[i].transform { $0 + Point(10, 0) } } }
        XCTAssertEqual(bothMoved.objects[0].nodes, bothMoved.objects[1].nodes)
        XCTAssertEqual(bothMoved.objects[0].nodes[0].point, Point(-5, -15))
    }

    func testTurningEitherLayerKeepsThemOpposite() {
        let design = blended()
        let topTurned = edited(design) { $0.objects[1].digitizing?.angle = 30 }
        XCTAssertEqual(topTurned.objects[1].settings.angle, 30)
        XCTAssertEqual(topTurned.objects[0].settings.angle, -150)
        // Typing an angle with both layers selected gives both the same one: the second turns back to face the first.
        let bothTurned = edited(design) { design in for i in 0..<2 { design.objects[i].digitizing?.angle = 30 } }
        XCTAssertEqual(bothTurned.objects[0].settings.angle, 30)
        XCTAssertEqual(bothTurned.objects[1].settings.angle, -150)
    }

    func testEachLayerKeepsItsOwnSpacing() {
        let next = edited(blended()) { $0.objects[1].digitizing?.gradientEnd = 4 }
        XCTAssertEqual(next.objects[1].settings.gradientEnd, 4)
        XCTAssertEqual(next.objects[0].settings.gradientEnd, ColorBlend.sparsest, "So one color can reach further than the other")
    }

    func testABlendComesApartWhenALayerIsNoLongerAGradient() {
        let design = blended()
        let restyled = edited(design) { $0.objects[0].digitizing?.fillStyle = .tatami }
        XCTAssertNil(restyled.objects[1].blendOf)
        let deleted = edited(design) { $0.objects.remove(at: 0) }
        XCTAssertNil(deleted.objects[0].blendOf)
        XCTAssertNotNil(deleted.objects[0].settings.blendFade, "It keeps its fade, so it sews as it did")
    }

    func testEditingABlend() {
        var design = blended()
        design.editBlend(containing: design.objects[1].id, second: red, direction: 90, fade: BlendFade(start: 0.2, middle: 0.4, end: 0.9))
        XCTAssertEqual(design.objects[0].settings.blendFade, BlendFade(start: 0.2, middle: 0.4, end: 0.9))
        XCTAssertEqual(design.objects[1].settings.blendFade, BlendFade(start: 0.2, middle: 0.4, end: 0.9).mirrored)
        XCTAssertEqual(design.objects[1].color, red)
        XCTAssertEqual(ColorBlend.direction(of: design.objects[0]), 90)
        XCTAssertEqual(design.objects[1].settings.angle, ColorBlend.angle(for: 270))
    }

    func testEditingABlendsFirstThread() {
        var design = blended()
        let green = ThreadColor("Green", 0x00aa00)
        design.editBlend(containing: design.objects[1].id, first: green, second: blue, direction: 0, fade: .whole)
        XCTAssertEqual(design.objects.map(\.color), [green, blue])
        design.editBlend(containing: design.objects[0].id, second: red, direction: 0, fade: .whole)
        XCTAssertEqual(design.objects[0].color, green, "No first thread given keeps the one it has")
    }

    func testDirectionReadsBackAsMade() {
        for direction in stride(from: 0.0, to: 360, by: 45) {
            XCTAssertEqual(ColorBlend.direction(of: ColorBlend.layers(of: square(), second: blue, direction: direction)[0]), direction, accuracy: 1e-9)
        }
    }

    /// Copy and paste (and Duplicate) give the copies new ids: the copied second layer must lie on the copied first,
    /// not on the original.
    func testACopiedBlendLinksToItsOwnCopy() {
        var design = blended()
        let pasted = design.paste(ObjectClipboard(objects: design.objects))
        XCTAssertEqual(design.objects[3].blendOf, pasted[0])
        // The second layer copied on its own is just a gradient fill.
        let alone = design.paste(ObjectClipboard(objects: [design.objects[1]]))
        XCTAssertNil(design.objects.first { $0.id == alone[0] }?.blendOf)
    }

    func testRemoveOverlapsLeavesABlendsLayersAlone() throws {
        let design = blended()
        XCTAssertNil(try OverlapCutout.pieces(of: design.objects[0], under: [design.objects[1]]), "The second layer doesn't cut the first away")
    }

    // MARK: Where the colors mix

    /// x positions of every stitch the layers sew, without underlay (so only their gradient rows count).
    func stitchXs(_ layers: [RunObject]) throws -> [Double] {
        var design = Design()
        design.objects = layers.map { var layer = $0; layer.digitizing?.underlay = .none; layer.blendOf = nil; return layer }
        return try StitchEngine.compile(design).commands.filter { $0.op == .stitch }.map(\.point.x)
    }
    /// How many of `xs` fall in each 10 mm band across the 30 mm square: left, middle, right.
    func bands(_ xs: [Double]) -> [Int] { [xs.filter { $0 < -5 }.count, xs.filter { abs($0) <= 5 }.count, xs.filter { $0 > 5 }.count] }

    /// The two layers together cover the fabric about once everywhere: the middle of the blend has about as many
    /// stitches as its ends. Before fades, each layer thinned out evenly from 0.4 to 2.5 mm across the whole shape, and
    /// the middle came out much thinner.
    func testABlendCoversTheFabricEvenly() throws {
        let even = bands(try stitchXs(ColorBlend.layers(of: square(), second: blue, direction: 0)))
        XCTAssertEqual(Double(even[1]), Double(even[0] + even[2]) / 2, accuracy: Double(even[0]) * 0.2, "\(even)")
        let old = ColorBlend.layers(of: square(), second: blue, direction: 0).map { layer -> RunObject in
            var layer = layer; layer.digitizing?.blendFade = nil; layer.digitizing?.gradientEnd = nil; return layer
        }
        let thin = bands(try stitchXs(old))
        XCTAssertLessThan(Double(thin[1]), Double(thin[0] + thin[2]) / 2 * 0.75, "Without a fade the middle is thin: \(thin)")
    }

    /// Past the end of its fade a color sews nothing, so the other is pure; before its start it's solid.
    func testPastItsFadeAColorSewsNothing() throws {
        let layers = ColorBlend.layers(of: square(), second: blue, direction: 0, fade: BlendFade(start: 0.3, middle: 0.5, end: 0.7))
        let red = try stitchXs([layers[0]]), blue = try stitchXs([layers[1]])
        XCTAssertTrue(red.allSatisfy { $0 < 6.5 }, "Red ends 70% of the way across (x = 6)")
        XCTAssertTrue(blue.allSatisfy { $0 > -6.5 }, "Blue starts 30% of the way across (x = -6)")
        XCTAssertGreaterThan(red.filter { $0 < -6 }.count, red.filter { $0 > -6 }.count, "Red is solid at the left")
    }

    func testFadeCoverage() {
        let fade = BlendFade(start: 0.2, middle: 0.5, end: 0.6)
        XCTAssertEqual(fade.coverage(at: 0.1), 1); XCTAssertEqual(fade.coverage(at: 0.5), 0.5); XCTAssertEqual(fade.coverage(at: 0.7), 0)
        for t in stride(from: 0.0, through: 1, by: 0.05) {
            XCTAssertEqual(fade.coverage(at: t) + fade.mirrored.coverage(at: 1 - t), 1, accuracy: 1e-9, "Mirrored layers add up to one at \(t)")
        }
        XCTAssertTrue(BlendFade.whole.isValid)
        XCTAssertFalse(BlendFade(start: 0.5, middle: 0.5, end: 0.9).isValid)
        XCTAssertFalse(BlendFade(start: -0.1, middle: 0.5, end: 0.9).isValid)
    }

    func testFadesStayMirrored() {
        let design = blended()
        let topChanged = edited(design) { $0.objects[1].digitizing?.blendFade = BlendFade(start: 0.1, middle: 0.3, end: 0.5) }
        XCTAssertEqual(topChanged.objects[0].settings.blendFade, BlendFade(start: 0.1, middle: 0.3, end: 0.5).mirrored)
        let baseChanged = edited(design) { $0.setBlendFade(containing: $0.objects[0].id, BlendFade(start: 0.4, middle: 0.6, end: 0.8)) }
        XCTAssertEqual(baseChanged.objects[1].settings.blendFade, BlendFade(start: 0.4, middle: 0.6, end: 0.8).mirrored)
    }

    func testBlendKeepsAnExistingGroup() {
        var fill = square(); let group = UUID(); fill.groupID = group
        XCTAssertEqual(Set(ColorBlend.layers(of: fill, second: blue, direction: 0).map(\.groupID)), [group])
    }
}
