// Checks monograms: the layouts place the initials as named, ornaments come in mirrored pairs, the border goes
// around everything, embroidery fonts keep to their sizes, and a monogram can be rebuilt where it was.
import XCTest
@testable import EmbroideryCore

final class MonogramTests: XCTestCase {
    private let fonts = EmbroideryFont.all(in: EmbroideryFontTests.directory)
    /// Small monograms keep the tests quick (a big satin border takes seconds to work out in a debug build).
    private func spec(_ layout: MonogramLayout, border: MonogramBorder = .none, ornament: MonogramOrnament = .none, height: Double = 24) -> MonogramSpec {
        MonogramSpec(initials: "ABC", fontKind: .system, font: "Helvetica-Bold", height: height, layout: layout, ornament: ornament, border: border)
    }
    private func box(_ objects: [RunObject]) -> (min: Point, max: Point) { MonogramSpec.box(objects)! }
    func testBigMiddleMakesTheMiddleInitialTallest() throws {
        let made = try spec(.bigMiddle).build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects
        let heights = made.map { box([$0]) }.sorted { $0.min.x < $1.min.x }.map { $0.max.y - $0.min.y }
        XCTAssertGreaterThan(heights.max()!, heights.min()! * 1.3, "the middle is clearly bigger")
        let all = box(made)
        XCTAssertEqual((all.min.x + all.max.x) / 2, 0, accuracy: 0.01, "centered")
        XCTAssertTrue(made.allSatisfy { $0.groupID == made[0].monogram?.id && $0.lettering == nil })
    }

    func testStackedAndSideBySideRunTheRightWay() throws {
        let side = box(try spec(.sideBySide).build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects)
        let stacked = box(try spec(.stacked).build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects)
        XCTAssertGreaterThan(side.max.x - side.min.x, (side.max.y - side.min.y) * 2, "a row is wide")
        XCTAssertGreaterThan(stacked.max.y - stacked.min.y, (stacked.max.x - stacked.min.x) * 2, "a stack is tall")
    }

    func testOrnamentsPairUpAndTheBorderGoesAroundEverything() throws {
        let made = try spec(.bigMiddle, border: .circle, ornament: .leaves, height: 10).build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects
        let leaves = made.filter { $0.name == "Leaf" }
        XCTAssertEqual(leaves.count, 2)
        XCTAssertEqual(box([leaves[0]]).max.x, -box([leaves[1]]).min.x, accuracy: 0.01, "mirrored either side")
        let border = try XCTUnwrap(made.last); XCTAssertEqual(border.name, "Monogram border"); XCTAssertEqual(border.kind, .satin)
        let inner = box(Array(made.dropLast()))
        let ring = AreaGeometry.ring(border.rail(1).count > 0 ? border.rail(1) : border.nodes)
        for corner in [inner.min, inner.max, Point(inner.min.x, inner.max.y), Point(inner.max.x, inner.min.y)] {
            XCTAssertTrue(AreaGeometry.contains(corner, rings: [ring]) || AreaGeometry.contains(corner, rings: [AreaGeometry.ring(border.rail(0))]), "the border is outside the monogram")
        }
        var design = Design(); design.objects = made
        XCTAssertGreaterThan(try RunningEngine.compile(design).stitchCount, 0, "it sews")
    }

    func testEveryLayoutBorderAndOrnamentBuilds() throws {
        // Each choice once (every combination would take minutes).
        for layout in MonogramLayout.allCases { XCTAssertNoThrow(try spec(layout, height: 10).build(color: ThreadColor.palette[0], embroideryFonts: fonts), "\(layout)") }
        for ornament in MonogramOrnament.allCases { XCTAssertNoThrow(try spec(.bigMiddle, ornament: ornament, height: 10).build(color: ThreadColor.palette[0], embroideryFonts: fonts), "\(ornament)") }
        for border in MonogramBorder.allCases { XCTAssertNoThrow(try spec(.bigMiddle, border: border, height: 10).build(color: ThreadColor.palette[0], embroideryFonts: fonts), "\(border)") }
    }

    func testRebuildingKeepsItsPlaceAndPosition() throws {
        var design = Design()
        let first = try spec(.sideBySide).build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects
        design.objects = first
        let id = first[0].monogram!.id
        design.move(Set(first.map(\.id)), by: Point(10, -5))
        var edited = try XCTUnwrap(design.objects[0].monogram); edited.initials = "XY"
        let rebuilt = try edited.build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects
        design.replaceMonogram(id, with: rebuilt)
        let center = box(design.objects)
        XCTAssertEqual((center.min.x + center.max.x) / 2, 10, accuracy: 0.01, "still where it was moved to")
        XCTAssertEqual(design.monogramObjects(id).count, rebuilt.count)
    }

    func testEditingAResizedRecoloredMonogramKeepsItsSizeAndColors() throws {
        var design = Design()
        design.objects = try spec(.sideBySide, border: .roundedRectangle, ornament: .dots, height: 12).build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects
        let id = design.objects[0].monogram!.id
        for i in design.objects.indices {
            design.objects[i].transform { $0 * 1.5 }   // resized to 150%
            if design.objects[i].name == "Monogram border" { design.objects[i].color = ThreadColor.palette[3] }
            if design.objects[i].name == "Dot" { design.objects[i].color = ThreadColor.palette[4] }
        }
        let group = UUID()
        for i in design.objects.indices { design.objects[i].groupID = group }   // grouped with something else
        let before = box(design.objects)
        let edited = try XCTUnwrap(design.objects[0].monogram?.asResized)
        XCTAssertEqual(edited.height, 18, "the height as it is now")
        design.replaceMonogram(id, with: try edited.build(color: ThreadColor.palette[0], embroideryFonts: fonts).objects)
        let after = box(design.objects)
        XCTAssertEqual(after.max.y - after.min.y, before.max.y - before.min.y, accuracy: 0.5, "rebuilt at the resized size")
        XCTAssertTrue(design.objects.filter { $0.name == "Monogram border" }.allSatisfy { $0.color == ThreadColor.palette[3] })
        XCTAssertTrue(design.objects.filter { $0.name == "Dot" }.allSatisfy { $0.color == ThreadColor.palette[4] })
        XCTAssertTrue(design.objects.filter { !["Monogram border", "Dot"].contains($0.name) }.allSatisfy { $0.color == ThreadColor.palette[0] })
        XCTAssertTrue(design.objects.allSatisfy { $0.groupID == group }, "still in the group it was put in")
    }

    func testEmbroideryFontsKeepToTheirSizes() throws {
        guard let font = fonts.first(where: { $0.heights.upperBound < 75 }) else { throw XCTSkip("No embroidery fonts in Resources") }
        var monogram = MonogramSpec(initials: "ABC", fontKind: .embroidery, font: font.folder.lastPathComponent, height: font.heights.upperBound + 5, layout: .bigMiddle)
        monogram.border = .none
        let result = try monogram.build(color: ThreadColor.palette[0], embroideryFonts: fonts)
        XCTAssertFalse(result.objects.isEmpty)
        XCTAssertTrue(result.notes.contains { $0.contains("digitized for letters") }, "the middle letter was brought down to the font's largest size, and it says so")
    }
}
