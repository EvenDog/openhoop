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

    /// Every fill (or none) with every outline (or none): a fill alone, an outline alone, or the fill then the
    /// outline on its edge, grouped. Each one sews.
    func testClosedShapeGetsThePickedFillAndOutline() throws {
        let nodes = ShapeGeometry.nodes(.ellipse, in: box)
        for fill in [nil] + FillStyle.allCases {
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

    /// The shape tools are on ⌥ keys that no other command uses.
    func testShapeToolKeys() {
        let profile = ShortcutProfile()
        let keys: [(KeyBinding, CommandID)] = [(.init("o", 4), .openShapeTool), (.init("s", 4), .closedShapeTool),
                                               (.init("r", 4), .rectangleTool), (.init("j", 4), .ellipseTool), (.init("b", 4), .basicShapeTool)]
        for (key, command) in keys { XCTAssertEqual(profile.command(for: key, context: .canvas), command, key.display) }
        XCTAssertNoThrow(try profile.validate())
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

