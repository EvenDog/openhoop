// Auto underlay and width-aware compensation for satins: Auto picks the underlay from the column's average width
// each time it sews, and each stitch gets the base compensation plus a share of its own width.
import XCTest
@testable import EmbroideryCore

final class AutoSatinTests: XCTestCase {
    /// A straight satin column `width` mm wide and 30 mm long, centered on the x axis, on default (new) settings.
    private func column(_ width: Double, _ change: (inout DigitizingSettings) -> Void = { _ in }) -> RunObject {
        var o = RunObject(name: "Column", nodes: [Point(-15, width / 2), Point(-15, -width / 2), Point(15, width / 2), Point(15, -width / 2)].map { PathNode($0) })
        var s = DigitizingSettings(kind: .satin); change(&s); o.digitizing = s
        return o
    }

    func testNewSatinsStartOnAutoWithWidthCompensation() {
        let satin = DigitizingSettings(kind: .satin)
        XCTAssertEqual(satin.underlay, .auto)
        XCTAssertEqual(satin.pullPercent, DigitizingSettings.defaultPullPercent)
        XCTAssertNotEqual(DigitizingSettings(kind: .fill).underlay, .auto, "Fills keep their own underlay")
        XCTAssertNil(DigitizingSettings(kind: .fill).pullPercent)
    }

    func testAutoRulePicksUnderlayByWidth() {
        func rule(_ width: Double, stretchy: Bool = false) -> [UnderlayStyle?] {
            let picked = DigitizingSettings.autoUnderlay(width: width, stretchy: stretchy); return [picked.first, picked.second]
        }
        XCTAssertEqual(rule(1.5), [.center, nil])
        XCTAssertEqual(rule(3), [.edge, nil])
        XCTAssertEqual(rule(5), [.edge, .zigzag])
        // Knit and towel get one step more support, where the column has room for it.
        XCTAssertEqual(rule(3, stretchy: true), [.edge, .zigzag])
        XCTAssertEqual(rule(1.5, stretchy: true), [.center, nil], "Too narrow for an edge run")
    }

    func testAutoUnderlayFollowsTheShape() throws {
        func underlay(_ width: Double) throws -> [StitchSection] { try AreaEngine.satin(column(width)).sections.filter(\.underlay) }
        let narrow = try underlay(1.5)
        XCTAssertEqual(narrow.count, 1); XCTAssertTrue(narrow[0].points.allSatisfy { abs($0.y) < 0.01 }, "A center run")
        let medium = try underlay(3)
        XCTAssertEqual(medium.count, 1); XCTAssertGreaterThan(medium[0].points.map(\.y).max()!, 0.5, "An edge run, around the inside of the edge")
        XCTAssertEqual(try underlay(5).count, 2, "Edge run then zigzag")
        XCTAssertFalse(try AreaEngine.satin(column(1.5)).warnings.contains { $0.contains("omitted") })
    }

    func testCompensationGrowsWithWidth() throws {
        // The top stitches' length: the column's width plus compensation on both sides.
        func stitchLength(_ width: Double, _ change: (inout DigitizingSettings) -> Void) throws -> Double {
            let top = try AreaEngine.satin(column(width) { $0.underlay = .none; $0.expansion = 0.2; $0.autoSplit = nil; $0.shortStitches = nil; change(&$0) }).sections.last!.points
            return top[0].distance(to: top[1])
        }
        XCTAssertEqual(try stitchLength(4) { $0.pullPercent = nil }, 4 + 2 * 0.2, accuracy: 0.001, "Without a percentage: the base only")
        XCTAssertEqual(try stitchLength(4) { $0.pullPercent = 5 }, 4 + 2 * (0.2 + 0.2), accuracy: 0.001, "5% of 4 mm is 0.2 mm more each side")
        XCTAssertEqual(try stitchLength(8) { $0.pullPercent = 5 }, 8 + 2 * (0.2 + 0.4), accuracy: 0.001)
    }

    func testAutoAndPercentRulesAndOlderFiles() throws {
        var s = DigitizingSettings(kind: .satin)
        s.underlay = .center; s.secondUnderlay = .zigzag; s.underlay = .auto
        XCTAssertNil(s.secondUnderlay, "Auto picks the second underlay itself")
        XCTAssertTrue(s.usesUnderlayInset, "Auto may pick an edge run")

        var design = Design(); design.objects = [column(3)]
        XCTAssertNoThrow(try design.validate())
        XCTAssertTrue(design.needsSchemaFive, "An older version can't sew Auto or the percentage")
        for change in [{ (s: inout DigitizingSettings) in s.pullPercent = 50 }, { $0.pullPercent = -1 }] {
            var object = column(3); change(&object.digitizing!); design.objects = [object]
            XCTAssertThrowsError(try design.validate())
        }
        var fill = RunObject(name: "Fill", nodes: [Point(0, 0), Point(10, 0), Point(10, 10)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.digitizing?.underlay = .auto
        design.objects = [fill]
        XCTAssertThrowsError(try design.validate(), "Auto is for satins only")

        let old = try JSONDecoder().decode(DigitizingSettings.self, from: Data(#"{"kind":"satin","spacing":0.4,"expansion":0.2,"angle":45,"maximumSatin":10,"underlay":"center","inset":0.4,"underlaySpacing":1.2}"#.utf8))
        XCTAssertNil(old.pullPercent, "Older satins keep their fixed compensation")
        XCTAssertNil(old.stretchyFabric)
    }

    func testFabricNudgesAutoAndSetsManualUnderlay() {
        var auto = column(3).settings, manual = column(3) { $0.underlay = .center }.settings
        FabricType.knit.apply(to: &auto); FabricType.knit.apply(to: &manual)
        XCTAssertEqual(auto.underlay, .auto, "Auto satins stay on Auto…")
        XCTAssertEqual(auto.stretchyFabric, true, "…with one step more support on a stretchy fabric")
        XCTAssertEqual(manual.underlay, .zigzag, "A manual underlay gets the fabric's, as before")
        FabricType.woven.apply(to: &auto)
        XCTAssertNil(auto.stretchyFabric)
    }

    func testBordersAndAppliqueUseAutoButFontsAndTackDownsDont() throws {
        var circle = RunObject(name: "Circle", nodes: ShapeGeometry.nodes(.ellipse, in: (Point(-8, -8), Point(8, 8))))
        circle.closed = true; circle.digitizing = DigitizingSettings(kind: .fill)
        let ink = ThreadColor.palette[0]
        XCTAssertEqual(try SatinBorder.around(circle, width: 3, color: ink).object.settings.underlay, .auto)
        let parts = try Applique.make(from: circle, coverWidth: 3, tackDown: .zigzag, color: ink).objects
        XCTAssertEqual(parts[2].settings.underlay, .auto, "The cover satin")
        XCTAssertEqual(parts[1].settings.underlay, .none, "The tack-down zigzag holds the fabric; it isn't a cover satin")
        XCTAssertNil(parts[1].settings.pullPercent)
        let font = try XCTUnwrap(EmbroideryFont.all(in: EmbroideryFontTests.directory).first)
        let letters = try font.shapes(text: "A", height: font.heights.lowerBound, color: ink).objects.filter { $0.kind == .satin }
        XCTAssertFalse(letters.isEmpty)
        XCTAssertTrue(letters.allSatisfy { $0.settings.underlay != .auto && $0.settings.pullPercent == nil }, "Fonts keep their designer's settings")
    }
}
