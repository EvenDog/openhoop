// Checks the shape tools: a drag gives a box of the right size (even with ⌘, centered with ⇧), every shape fills its
// box and sews, curves match true circles, and Open/Closed Shape put the picked stitch on what's drawn.
import XCTest
@testable import EmbroideryCore

final class ShapeTests: XCTestCase {
    private let box = (min: Point(-20, -10), max: Point(20, 10))   // 40 × 20 mm
    /// The shape's outline as flat points, closed.
    private func outline(_ nodes: [PathNode]) -> [Point] { RunningEngine.flatten(nodes, closed: true).flatMap { $0 } }
    private func bounds(_ points: [Point]) -> (min: Point, max: Point) {
        (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
    }
    private func assertNear(_ a: Point, _ b: Point, _ tolerance: Double = 0.01, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(a.distance(to: b), tolerance, "\(a) vs \(b)", file: file, line: line)
    }

    func testDragBoxFromACornerEvenAndFromTheCenter() {
        let plain = ShapeGeometry.box(from: Point(10, 10), to: Point(0, 40), even: false, fromCenter: false)
        assertNear(plain.min, Point(0, 10)); assertNear(plain.max, Point(10, 40))
        // ⌘: the longer side wins, so the 10 × 30 drag becomes 30 × 30, still growing toward the pointer.
        let even = ShapeGeometry.box(from: Point(10, 10), to: Point(0, 40), even: true, fromCenter: false)
        assertNear(even.min, Point(-20, 10)); assertNear(even.max, Point(10, 40))
        // ⇧: the start is the middle.
        let centered = ShapeGeometry.box(from: Point(0, 0), to: Point(5, -3), even: false, fromCenter: true)
        assertNear(centered.min, Point(-5, -3)); assertNear(centered.max, Point(5, 3))
    }

    func testRectangleCornersAndRoundedCorners() {
        let square = ShapeGeometry.nodes(.rectangle, in: box)
        XCTAssertEqual(square.map(\.point), [Point(-20, -10), Point(20, -10), Point(20, 10), Point(-20, 10)])
        var settings = ShapeSettings(); settings.cornerRadius = 4
        let rounded = ShapeGeometry.nodes(.rectangle, in: box, settings: settings)
        XCTAssertEqual(rounded.count, 8)
        let flat = outline(rounded), edges = bounds(flat)
        assertNear(edges.min, box.min); assertNear(edges.max, box.max)
        // Each corner curve stays 4 mm from its circle's center (kappa curves are within 0.03% of a circle).
        let cornerCenter = Point(16, 6)
        for p in flat where p.x > 16.01 && p.y > 6.01 { XCTAssertEqual(p.distance(to: cornerCenter), 4, accuracy: 0.01) }
        // A radius larger than the shape allows is limited, so no side shrinks to nothing.
        settings.cornerRadius = 20
        let limited = ShapeGeometry.nodes(.rectangle, in: box, settings: settings)
        for (a, b) in zip(limited, limited.dropFirst()) { XCTAssertGreaterThan(a.point.distance(to: b.point), 0.05) }
    }

    func testEllipseFollowsTheTrueEllipse() {
        let nodes = ShapeGeometry.nodes(.ellipse, in: box)
        XCTAssertEqual(nodes.count, 4)
        let flat = outline(nodes), edges = bounds(flat)
        assertNear(edges.min, box.min, 0.05); assertNear(edges.max, box.max, 0.05)
        // (x/20)² + (y/10)² = 1 on a true ellipse; the curves stay within 0.1 mm of it.
        for p in flat { XCTAssertEqual(sqrt(pow(p.x / 20, 2) + pow(p.y / 10, 2)), 1, accuracy: 0.1 / 10) }
    }

    func testPolygonsAndStarsFillTheBoxOrKeepTheirProportions() {
        var settings = ShapeSettings(); settings.polygonSides = 6; settings.starPoints = 5
        let hexagon = ShapeGeometry.nodes(.polygon, in: box, settings: settings)
        XCTAssertEqual(hexagon.count, 6)
        let stretched = bounds(hexagon.map(\.point)); assertNear(stretched.min, box.min); assertNear(stretched.max, box.max)
        let star = ShapeGeometry.nodes(.star, in: box, settings: settings)
        XCTAssertEqual(star.count, 10)
        assertNear(star[0].point, Point(0, 10))   // the first point is at the top, in the middle
        // Kept in proportion (⌘), a 5-point star in the 40 × 20 box is narrower than the box and centered in it.
        let even = bounds(ShapeGeometry.nodes(.star, in: box, settings: settings, keepProportions: true).map(\.point))
        XCTAssertEqual(even.max.y - even.min.y, 20, accuracy: 0.01)
        XCTAssertLessThan(even.max.x - even.min.x, 22)
        XCTAssertEqual(even.min.x + even.max.x, 0, accuracy: 0.01)
    }

    func testEveryShapeSewsAsAFillInsideItsBox() throws {
        for shape in BasicShape.allCases {
            let nodes = ShapeGeometry.nodes(shape, in: box)
            let edges = bounds(outline(nodes))
            XCTAssertGreaterThan(edges.min.x, box.min.x - 0.05, shape.title); XCTAssertLessThan(edges.max.x, box.max.x + 0.05, shape.title)
            XCTAssertGreaterThan(edges.min.y, box.min.y - 0.05, shape.title); XCTAssertLessThan(edges.max.y, box.max.y + 0.05, shape.title)
            let object = try ShapeStitching.closedShape(nodes, fill: .tatami, outline: nil, name: shape.title, color: .palette[0])[0]
            XCTAssertFalse(try AreaEngine.fill(object).sections.isEmpty, shape.title)
        }
    }

    /// The Basic Shapes picture grid offers every shape except Rectangle and Ellipse (which have tools of their own),
    /// each once, under a different name. Drawn small and kept in proportion, each one still sews as a fill with a
    /// running outline, and a picked shape is remembered.
    func testBasicShapesGridOffersEveryShapeAndEachSewsSmall() throws {
        XCTAssertEqual(Set(BasicShape.basicChoices), Set(BasicShape.allCases).subtracting([.rectangle, .ellipse]))
        XCTAssertEqual(BasicShape.basicChoices.count, BasicShape.allCases.count - 2, "no shape is in two groups")
        XCTAssertEqual(Set(BasicShape.allCases.map(\.title)).count, BasicShape.allCases.count, "every shape has its own name")
        let small = (min: Point(0, 0), max: Point(12, 12))
        for shape in BasicShape.basicChoices {
            let nodes = ShapeGeometry.nodes(shape, in: small, keepProportions: true)
            XCTAssertGreaterThanOrEqual(nodes.count, 3, shape.title)   // finishing a dragged shape needs 3 nodes
            let holes = ShapeGeometry.holes(shape, around: nodes)
            XCTAssertEqual(holes.count, shape.isFrame ? 1 : 0, shape.title)
            let made = try ShapeStitching.closedShape(nodes, holes: holes, fill: .tatami, outline: .running, name: shape.title, color: .palette[0])
            XCTAssertFalse(try AreaEngine.fill(made[0]).sections.isEmpty, shape.title)
            XCTAssertFalse(try StitchEngine.fresh(made[1], under: []).sections.isEmpty, shape.title)
            var picked = ShapeSettings(); picked.basicShape = shape
            XCTAssertEqual(try JSONDecoder().decode(ShapeSettings.self, from: JSONEncoder().encode(picked)).basicShape, shape)
        }
    }

    /// A frame leaves its middle open: the hole sits the band width in from the outside edge all round (from the
    /// scallops' valleys for the scalloped frame), no fill stitch lands in it, and an outline goes round both edges,
    /// all grouped. A band too wide for the frame leaves no hole; a saved band width is kept in range.
    func testFramesLeaveTheirMiddleOpen() throws {
        var settings = ShapeSettings(); settings.frameWidth = 3
        for shape in BasicShape.allCases where shape.isFrame {
            let nodes = ShapeGeometry.nodes(shape, in: box, settings: settings)
            let holes = ShapeGeometry.holes(shape, around: nodes, settings: settings)
            XCTAssertEqual(holes.count, 1, shape.title)
            let hole = bounds(outline(holes[0]))
            if shape == .scallopFrame {
                XCTAssertGreaterThan(hole.min.x, box.min.x + 3, shape.title); XCTAssertLessThan(hole.max.y, box.max.y - 3, shape.title)
            } else {
                assertNear(hole.min, box.min + Point(3, 3), 0.05); assertNear(hole.max, box.max - Point(3, 3), 0.05)
            }
            let made = try ShapeStitching.closedShape(nodes, holes: holes, fill: .tatami, outline: .running, name: shape.title, color: .palette[0])
            XCTAssertEqual(made.map(\.name), [shape.title, "\(shape.title) outline", "\(shape.title) inner outline"])
            XCTAssertEqual(Set(made.compactMap(\.groupID)).count, 1, shape.title); XCTAssertEqual(made.compactMap(\.groupID).count, 3, shape.title)
            XCTAssertEqual(made[2].nodes, holes[0], shape.title)
            // Nothing sewn well inside the hole (1 mm in from its edge, where the fill's edge stitches can't reach).
            let stitches = try AreaEngine.fill(made[0]).sections.flatMap(\.points)
            XCTAssertFalse(stitches.isEmpty, shape.title)
            let deepInside = (min: hole.min + Point(1, 1), max: hole.max - Point(1, 1))
            let middle = (deepInside.min + deepInside.max) * 0.5, reach = (deepInside.max - deepInside.min) * 0.5
            XCTAssertFalse(stitches.contains { pow(($0.x - middle.x) / reach.x, 2) + pow(($0.y - middle.y) / reach.y, 2) < 1 }, shape.title)
        }
        var wide = ShapeSettings(); wide.frameWidth = 10   // the box is 20 mm tall: nothing left for a hole
        XCTAssertTrue(ShapeGeometry.holes(.ring, around: ShapeGeometry.nodes(.ring, in: box), settings: wide).isEmpty)
        XCTAssertTrue(ShapeGeometry.holes(.heart, around: ShapeGeometry.nodes(.heart, in: box)).isEmpty, "only frames have holes")
        let saved = try JSONDecoder().decode(ShapeSettings.self, from: Data(#"{"frameWidth": 99}"#.utf8))
        XCTAssertEqual(saved.frameWidth, ShapeSettings.frameWidthRange.upperBound)
    }

    /// With Open middle on, any Basic Shapes shape becomes a frame: its hole is the outline shrunk evenly inward, so
    /// every point of the hole's edge is at least the band width from the outside edge, and the nearest ones exactly
    /// that. The fill sews round the hole. Off (the default), or for the Rectangle and Ellipse tools, there's no hole;
    /// a band too wide leaves none either. The choice is saved, and older preferences without it read as off.
    func testOpenMiddleMakesAnyShapeAFrame() throws {
        var settings = ShapeSettings(); settings.openMiddle = true; settings.frameWidth = 3
        let square = (min: Point(-20, -20), max: Point(20, 20))
        /// How far `p` is from the closed outline `ring` (from its nearest edge).
        func distance(_ p: Point, to ring: [Point]) -> Double {
            ring.indices.map { i -> Double in
                let a = ring[i], b = ring[(i + 1) % ring.count], ab = b - a
                let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / (ab.x * ab.x + ab.y * ab.y)))
                return hypot(p.x - (a.x + ab.x * t), p.y - (a.y + ab.y * t))
            }.min()!
        }
        for shape in BasicShape.basicChoices where !shape.isFrame {
            let nodes = ShapeGeometry.nodes(shape, in: square, settings: settings, keepProportions: true)
            let holes = ShapeGeometry.holes(shape, around: nodes, settings: settings)
            XCTAssertFalse(holes.isEmpty, "\(shape.title) has an open middle")
            let edge = outline(nodes)
            let gaps = holes.flatMap { $0.map { distance($0.point, to: edge) } }
            XCTAssertGreaterThan(gaps.min() ?? 0, 2.95, "\(shape.title): the band is never thinner than its width")
            XCTAssertEqual(gaps.min() ?? 0, 3, accuracy: 0.05, "\(shape.title): the band is its width")
        }
        for shape in [BasicShape.heart, .star, .shield, .polygon] {
            let nodes = ShapeGeometry.nodes(shape, in: square, settings: settings, keepProportions: true)
            let holes = ShapeGeometry.holes(shape, around: nodes, settings: settings)
            let made = try ShapeStitching.closedShape(nodes, holes: holes, fill: .tatami, outline: .running, name: shape.title, color: .palette[0])
            XCTAssertEqual(made.map(\.name), [shape.title, "\(shape.title) outline", "\(shape.title) inner outline"])
            XCTAssertFalse(try AreaEngine.fill(made[0]).sections.flatMap(\.points).isEmpty, shape.title)
        }
        let heart = ShapeGeometry.nodes(.heart, in: square)
        XCTAssertTrue(ShapeGeometry.holes(.heart, around: heart).isEmpty, "off by default")
        XCTAssertTrue(ShapeGeometry.holes(.rectangle, around: ShapeGeometry.nodes(.rectangle, in: square), settings: settings).isEmpty, "the Rectangle tool")
        var wide = settings; wide.frameWidth = 20   // 40 mm across: nothing left in the middle
        XCTAssertTrue(ShapeGeometry.holes(.heart, around: heart, settings: wide).isEmpty)
        XCTAssertFalse(try JSONDecoder().decode(ShapeSettings.self, from: Data("{}".utf8)).openMiddle)
        XCTAssertTrue(try JSONDecoder().decode(ShapeSettings.self, from: JSONEncoder().encode(settings)).openMiddle)
    }

    /// Every fill (or none) with every outline (or none): a fill alone, an outline alone, or the fill then the
    /// outline on its edge, grouped. Each one sews.
    func testClosedShapeGetsThePickedFillAndOutline() throws {
        let nodes = ShapeGeometry.nodes(.ellipse, in: box)
        for fill in [nil] + FillStyle.forNewShapes {
            for outline in [nil] + OpenShapeStitch.allCases where fill != nil || outline != nil {
                let label = "\(fill?.title ?? "no") fill, \(outline?.title ?? "no") outline"
                let made = try ShapeStitching.closedShape(nodes, fill: fill, outline: outline, satinWidth: 3, name: "Shape", color: .palette[0])
                XCTAssertEqual(made.count, fill != nil && outline != nil ? 2 : 1, label)
                if let fill {
                    XCTAssertEqual(made[0].kind, .fill, label); XCTAssertTrue(made[0].closed, label)
                    XCTAssertEqual(made[0].settings.fillStyle ?? .tatami, fill, label)
                    XCTAssertFalse(try AreaEngine.fill(made[0]).sections.isEmpty, label)
                }
                if let outline {
                    let edge = made.last!
                    XCTAssertEqual(edge.kind, outline == .satin ? .satin : .run, label)
                    XCTAssertEqual(edge.settings.runPasses ?? 1, outline == .bean ? 3 : 1, label)
                    XCTAssertFalse(try StitchEngine.fresh(edge, under: []).sections.isEmpty, label)
                }
                if made.count == 2 {
                    XCTAssertNotNil(made[0].groupID, label); XCTAssertEqual(made[0].groupID, made[1].groupID, label)
                    XCTAssertNotEqual(made[0].id, made[1].id, label)
                    XCTAssertEqual(made[1].name, "Shape outline", label)
                } else { XCTAssertNil(made[0].groupID, label) }
            }
        }
    }

    /// A satin outline sits centered on the shape's edge: half the width outside it, half inside.
    func testSatinOutlineIsCenteredOnTheEdge() throws {
        let made = try ShapeStitching.closedShape(ShapeGeometry.nodes(.ellipse, in: box), fill: .tatami, outline: .satin, satinWidth: 4, name: "Circle", color: .palette[0])
        let xs = made[1].nodes.map(\.point.x)
        XCTAssertEqual(xs.max()! - xs.min()!, (box.max.x - box.min.x) + 4, accuracy: 0.3)
        // Too small for the satin: says why instead of making a broken column.
        let tiny = ShapeGeometry.nodes(.ellipse, in: (Point(0, 0), Point(1, 1)))
        XCTAssertThrowsError(try ShapeStitching.closedShape(tiny, fill: nil, outline: .satin, satinWidth: 8, name: "Dot", color: .palette[0]))
    }

    /// Turning both the fill and the outline off isn't possible: the other one comes back on.
    func testFillAndOutlineAreNeverBothOff() {
        var settings = ShapeSettings()
        XCTAssertEqual(settings.closedFill, .tatami); XCTAssertNil(settings.closedOutline)
        XCTAssertEqual(settings.closedSummary, "Tatami fill")
        settings.closedFill = nil
        XCTAssertEqual(settings.closedOutline, .running, "no fill and no outline: the outline comes on")
        XCTAssertEqual(settings.closedSummary, "Running outline")
        settings.closedOutline = .satin; settings.closedFill = .contour
        XCTAssertEqual(settings.closedSummary, "Contour fill + satin outline")
        settings.closedFill = nil; settings.closedOutline = nil
        XCTAssertEqual(settings.closedFill, .tatami, "no outline and no fill: the fill comes on")
    }

    /// Choices saved by older versions (one closed-shape stitch) are read as a fill or a running outline, and a
    /// file saying both are off falls back to a tatami fill.
    func testOlderClosedShapeChoiceIsReadAsFillAndOutline() throws {
        func read(_ json: String) throws -> ShapeSettings { try JSONDecoder().decode(ShapeSettings.self, from: Data(json.utf8)) }
        let outline = try read(#"{"closedStitch": "outline"}"#)
        XCTAssertNil(outline.closedFill); XCTAssertEqual(outline.closedOutline, .running)
        let radial = try read(#"{"closedStitch": "radial"}"#)
        XCTAssertEqual(radial.closedFill, .radial); XCTAssertNil(radial.closedOutline)
        let onlyOutline = try read(#"{"closedOutline": "bean"}"#)
        XCTAssertNil(onlyOutline.closedFill, "a newer file without a fill means no fill"); XCTAssertEqual(onlyOutline.closedOutline, .bean)
        let neither = try read(#"{"closedFill": "laser", "closedOutline": "glitter"}"#)
        XCTAssertEqual(neither.closedFill, .tatami); XCTAssertNil(neither.closedOutline)
        var both = ShapeSettings(); both.closedOutline = .satin; both.closedFill = nil
        XCTAssertEqual(try JSONDecoder().decode(ShapeSettings.self, from: JSONEncoder().encode(both)), both)
    }

    func testOpenShapeGetsRunningBeanOrSatin() throws {
        let line = [PathNode(Point(-20, 0)), PathNode(Point(0, 8), smooth: true), PathNode(Point(20, 0))]
        let running = try ShapeStitching.openShape(line, stitch: .running, satinWidth: 3, name: "Line", color: .palette[0])
        XCTAssertEqual(running.kind, .run); XCTAssertFalse(running.closed)
        let bean = try ShapeStitching.openShape(line, stitch: .bean, satinWidth: 3, name: "Line", color: .palette[0])
        XCTAssertEqual(bean.settings.runPasses, 3); XCTAssertEqual(bean.stitchTitle, "Bean")
        let satin = try ShapeStitching.openShape(line, stitch: .satin, satinWidth: 3, name: "Line", color: .palette[0])
        XCTAssertEqual(satin.kind, .satin)
        XCTAssertFalse(try AreaEngine.satin(satin).sections.isEmpty)
        // A line too short for a satin says why instead of making a broken column.
        let stub = [PathNode(Point(0, 0)), PathNode(Point(0.3, 0))]
        XCTAssertThrowsError(try ShapeStitching.openShape(stub, stitch: .satin, satinWidth: 3, name: "Stub", color: .palette[0]))
    }

    /// Every line style can be picked before drawing, not just in Properties after (Ripple aside: it repeats a
    /// closed outline inward, so it's no choice for a new open line). A new line or outline gets the style itself.
    func testShapeToolsOfferEveryLineStyle() throws {
        let offered = Set(OpenShapeStitch.allCases.compactMap(\.runStyle))
        XCTAssertEqual(offered, Set(RunStyle.allCases).subtracting([.running, .ripple]))
        let line = [PathNode(Point(-20, 0)), PathNode(Point(0, 8), smooth: true), PathNode(Point(20, 0))]
        let square = ShapeGeometry.nodes(.rectangle, in: (Point(-10, -10), Point(10, 10)))
        for stitch in OpenShapeStitch.allCases {
            guard let style = stitch.runStyle else { continue }
            let open = try ShapeStitching.openShape(line, stitch: stitch, satinWidth: 3, name: "Line", color: .palette[0])
            XCTAssertEqual(open.settings.runStyle, style, stitch.title)
            let edge = try XCTUnwrap(ShapeStitching.closedShape(square, fill: nil, outline: stitch, name: "Square", color: .palette[0]).first)
            XCTAssertEqual(edge.settings.runStyle, style, stitch.title)
            var design = Design(); design.objects = [open, edge]
            XCTAssertGreaterThan(try RunningEngine.compile(design).stitchCount, 20, stitch.title)
        }
    }

    /// The shape tools are on ⌥ keys that no other command uses.
    func testShapeToolKeys() {
        let profile = ShortcutProfile()
        let keys: [(KeyBinding, CommandID)] = [(.init("o", 4), .openShapeTool), (.init("s", 4), .closedShapeTool),
                                               (.init("o", 6), .freehandOpenTool), (.init("s", 6), .freehandClosedTool),
                                               (.init("r", 4), .rectangleTool), (.init("j", 4), .ellipseTool), (.init("b", 4), .basicShapeTool)]
        for (key, command) in keys { XCTAssertEqual(profile.command(for: key, context: .canvas), command, key.display) }
        XCTAssertNoThrow(try profile.validate())
    }

    /// A freehand stroke (hundreds of points a fraction of a millimeter apart) becomes a few smooth nodes whose curve
    /// stays within the tolerance of the stroke. A closed stroke loses the tail that came back to its start, since the
    /// shape closes itself; a nearly straight stroke is just its two ends; a lone point is handed back as it is.
    func testFreehandStrokeSmoothsToFewNodes() throws {
        let circle = (0...400).map { Point(20 * cos(Double($0) / 400 * 2 * .pi), 20 * sin(Double($0) / 400 * 2 * .pi)) }   // ends where it began
        let nodes = FreehandStroke.nodes(circle, closed: true)
        XCTAssertGreaterThanOrEqual(nodes.count, 3); XCTAssertLessThan(nodes.count, 40, "\(nodes.count) nodes")
        XCTAssertTrue(nodes.allSatisfy(\.smooth))
        XCTAssertGreaterThan(try XCTUnwrap(nodes.last).point.distance(to: nodes[0].point), 1, "the tail back at the start is dropped")
        let slack = FreehandStroke.tolerance + 0.15   // the reducer's tolerance, plus the straight-line thinning before it
        for p in RunningEngine.flatten(nodes, closed: true).flatMap({ $0 }) {
            XCTAssertEqual(p.distance(to: Point(0, 0)), 20, accuracy: slack, "the curve hugs the stroke")
        }
        let line = (0...100).map { Point(Double($0) * 0.5, 0.02 * sin(Double($0))) }   // nearly straight, with pointer wobble
        XCTAssertEqual(FreehandStroke.nodes(line, closed: false).count, 2)
        XCTAssertEqual(FreehandStroke.nodes([Point(0, 0)], closed: false).count, 1)
    }

    func testShapeSettingsSurviveSaving() throws {
        var settings = ShapeSettings(); settings.closedFill = .contour; settings.closedOutline = .bean; settings.basicShape = .heart; settings.cornerRadius = 2.5
        XCTAssertEqual(try JSONDecoder().decode(ShapeSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    /// The shape choices live in the preferences file, so reading them never fails: missing, unknown or out-of-range
    /// values fall back to defaults or are clamped, and a normal save reads back unchanged.
    func testSavedShapeChoicesAreReadForgivingly() throws {
        func read(_ json: String) throws -> ShapeSettings { try JSONDecoder().decode(ShapeSettings.self, from: Data(json.utf8)) }
        var chosen = ShapeSettings(); chosen.closedFill = .wave; chosen.basicShape = .polygon; chosen.polygonSides = 8; chosen.cornerRadius = 2.5
        XCTAssertEqual(try JSONDecoder().decode(ShapeSettings.self, from: JSONEncoder().encode(chosen)), chosen)
        XCTAssertEqual(try read("{}"), ShapeSettings(), "an older file without these keys")
        let odd = try read(#"{"openStitch": "laser", "basicShape": "rectangle", "polygonSides": -1, "starPoints": 99, "starInner": 7, "cornerRadius": -3, "brandNewSetting": true}"#)
        XCTAssertEqual(odd.openStitch, ShapeSettings().openStitch, "an unknown stitch falls back")
        XCTAssertEqual(odd.basicShape, ShapeSettings().basicShape, "the Basic Shapes tool doesn't draw rectangles")
        XCTAssertEqual(odd.polygonSides, 3); XCTAssertEqual(odd.starPoints, 12); XCTAssertEqual(odd.starInner, 0.8); XCTAssertEqual(odd.cornerRadius, 0)
        XCTAssertFalse(ShapeGeometry.nodes(.polygon, in: box, settings: odd).isEmpty, "clamped sides still draw a shape")
    }
}


final class StitchNameTests: XCTestCase {
    /// A line named for its stitch follows a new stitch, keeping its number; a typed name, or one with words after
    /// the number, stays; changing anything else leaves the name alone.
    func testNamesFollowTheStitchUntilTyped() {
        func line(_ name: String, _ style: RunStyle?) -> RunObject {
            var object = RunObject(name: name, nodes: [Point(0, 0), Point(10, 0)].map { PathNode($0) })
            object.digitizing = DigitizingSettings(kind: .run); object.digitizing?.runStyle = style
            return object
        }
        var before = Design()
        before.objects = [line("Zigzag 2", .zigzag), line("Zigzag border", .zigzag), line("Zigzag 3 outline", .zigzag), line("Zigzag 4", .zigzag)]
        var after = before
        for i in 0..<3 { after.objects[i].digitizing?.runStyle = .ripple }
        after.objects[3].digitizing?.runWidth = 3
        after.renameAfterStitches(from: before)
        XCTAssertEqual(after.objects.map(\.name), ["Ripple 2", "Zigzag border", "Zigzag 3 outline", "Zigzag 4"])
        // Back to plain running stitch, and a tatami fill made a contour fill.
        var plain = after; plain.objects[0].digitizing?.runStyle = nil
        var fill = RunObject(name: "Tatami Fill 5", nodes: [Point(0, 0), Point(10, 0), Point(10, 10)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        plain.objects.append(fill)
        plain.renameAfterStitches(from: after)
        var contour = plain; contour.objects[4].digitizing?.fillStyle = .contour
        contour.renameAfterStitches(from: plain)
        XCTAssertEqual(contour.objects[0].name, "Running 2")
        XCTAssertEqual(contour.objects[4].name, "Contour Fill 5")
    }

    func testPickingAShapeToolStartsWithTatamiAndNoOutline() {
        var settings = ShapeSettings(); settings.closedFill = .contour; settings.closedOutline = .satin
        settings.startFresh()
        XCTAssertEqual(settings.closedFill, .tatami, "not the fill picked last time")
        XCTAssertNil(settings.closedOutline)
        // Outline only last time: back to a tatami fill too.
        settings.closedOutline = .bean; settings.closedFill = nil
        settings.startFresh()
        XCTAssertEqual(settings.closedFill, .tatami); XCTAssertNil(settings.closedOutline)
    }

    func testSewSwitchesBetweenFillOutlineAndBoth() {
        var settings = ShapeSettings()
        XCTAssertEqual(settings.closedSew, .fill)
        settings.closedSew = .outline
        XCTAssertNil(settings.closedFill); XCTAssertEqual(settings.closedOutline, .running, "a fresh outline is running stitch")
        settings.closedOutline = .satin
        settings.closedSew = .both
        XCTAssertEqual(settings.closedFill, .tatami); XCTAssertEqual(settings.closedOutline, .satin, "the outline picked stays")
        XCTAssertEqual(settings.closedSew, .both)
        settings.closedFill = .wave
        settings.closedSew = .fill
        XCTAssertEqual(settings.closedFill, .wave, "the fill picked stays"); XCTAssertNil(settings.closedOutline)
        XCTAssertEqual(ShapeSettings.Sew.allCases.map(\.title), ["Fill", "Outline", "Both"])
    }
}
