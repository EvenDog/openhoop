// Checks lettering on a line: the letters sit along the line (their baselines on it, centered on it), Put Lettering
// on Line turns the line into the lettering's guide, reshaping the guide rebuilds the letters along it (moving both
// together doesn't), and choosing another shape, copying, or a bad line behave as they should.
import XCTest
@testable import EmbroideryCore

final class LetteringOnLineTests: XCTestCase {
    private let ink = ThreadColor.palette[0]
    private var fonts: [EmbroideryFont] { EmbroideryFont.all(in: EmbroideryFontTests.directory) }

    private func distance(_ p: Point, to path: [Point]) -> Double {
        zip(path, path.dropFirst()).map { p.distance(to: AreaGeometry.projection(p, $0, $1)) }.min()!
    }
    /// The letters of `objects`, by letter key.
    private func letters(_ objects: [RunObject]) -> [[RunObject]] { Dictionary(grouping: objects) { $0.letterKey ?? 0 }.sorted { $0.key < $1.key }.map(\.value) }

    func testLettersSitAlongTheLine() throws {
        // A straight line: an ordinary row of letters with its baseline on the line, centered on it.
        // (Flat-bottomed letters: round ones like C dip a little below the baseline, as fonts draw them.)
        var spec = LetteringSpec(text: "HEF", fontKind: .system, font: "Helvetica-Bold", height: 10, shape: .onLine)
        spec.path = [Point(-30, 5), Point(30, 5)]
        let flat = try spec.build(color: ink, embroideryFonts: fonts).objects
        let points = flat.flatMap { $0.outlinePaths.flatMap { $0 } }
        XCTAssertEqual(points.map(\.y).min()!, 5, accuracy: 0.05, "the baseline is on the line")
        XCTAssertEqual((points.map(\.x).min()! + points.map(\.x).max()!) / 2, 0, accuracy: 0.05, "centered on the line")

        // A curve: every letter touches the line with its bottom and stands on its left (upper) side.
        spec.path = stride(from: -1.0, through: 1, by: 0.05).map { t in Point(40 * sin(t), 40 * cos(t) - 40) }
        let curved = try spec.build(color: ink, embroideryFonts: fonts).objects
        for letter in letters(curved) {
            let outline = letter.flatMap { $0.outlinePaths.flatMap { $0 } }
            XCTAssertLessThan(outline.map { distance($0, to: spec.path!) }.min()!, 0.6, "touches the line")
            XCTAssertTrue(outline.allSatisfy { $0.distance(to: Point(0, -40)) > 39.4 }, "stands outside the circle the line follows")
        }
        XCTAssertGreaterThan(letters(curved).count, 2)
        XCTAssertNoThrow(try { var d = Design(); d.objects = curved; _ = try StitchEngine.compile(d) }())

        // Several lines can't go on one line; nor can lettering with no line.
        var two = spec; two.text = "AB\nCD"
        XCTAssertThrowsError(try two.build(color: ink, embroideryFonts: fonts))
        var none = spec; none.path = nil
        XCTAssertThrowsError(try none.build(color: ink, embroideryFonts: fonts))
    }

    func testPutLetteringOnLineAndReshapeIt() throws {
        let spec = LetteringSpec(text: "Abc", fontKind: .embroidery, font: "small_font", height: 10)
        let word = try spec.build(color: ink, embroideryFonts: fonts).objects
        let line = RunObject(name: "Line", nodes: [Point(-40, -20), Point(0, -10), Point(40, -20)].map { PathNode($0) })
        var design = Design(); design.objects = word + [line]
        try design.putLettering(spec.id, onLine: line.id, embroideryFonts: fonts)
        let guide = try XCTUnwrap(design.objects.last)
        XCTAssertEqual(guide.id, line.id); XCTAssertEqual(guide.kind, .vector, "the line stops sewing"); XCTAssertEqual(guide.guideFor, spec.id)
        let placed = design.letteringObjects(spec.id)
        XCTAssertTrue(placed.allSatisfy { $0.lettering?.shape == .onLine && $0.groupID == guide.groupID }, "one group with the line")
        XCTAssertTrue(placed.flatMap { $0.outlinePaths.flatMap { $0 } }.allSatisfy { $0.y < 5 }, "moved down to the line")
        XCTAssertTrue(design.needsSchemaSix)
        XCTAssertFalse(try StitchEngine.compile(design).commands.contains { $0.objectID == guide.id }, "the line sews nothing")

        // Moving the letters and their line together leaves the letters as they are.
        var moved = design
        for i in moved.objects.indices { moved.objects[i].transform { $0 + Point(5, 3) } }
        let before = moved.objects.map(\.id)
        XCTAssertTrue(moved.syncGuides(embroideryFonts: fonts).isEmpty)
        XCTAssertEqual(moved.objects.map(\.id), before, "not rebuilt")

        // Reshaping the line rebuilds the letters along it.
        let index = design.objects.firstIndex { $0.id == line.id }!
        design.objects[index].nodes[1].point = Point(0, 10)
        XCTAssertTrue(design.syncGuides(embroideryFonts: fonts).isEmpty)
        let rebuilt = design.letteringObjects(spec.id)
        XCTAssertEqual(rebuilt.first?.lettering?.path, design.objects.first { $0.id == line.id }?.outlinePaths[0])
        XCTAssertGreaterThan(rebuilt.flatMap { $0.outlinePaths.flatMap { $0 } }.map(\.y).max()!, 12, "the letters rose with the line")

        // A copy of both: the copied line guides the copied lettering.
        var copied = design
        let ids = copied.paste(design.copying(Set(design.objects.map(\.id))), offset: Point(0, 30))
        let copiedGuide = try XCTUnwrap(copied.objects.first { ids.contains($0.id) && $0.kind == .vector })
        let copiedLettering = try XCTUnwrap(copied.objects.first { ids.contains($0.id) && $0.lettering != nil }?.lettering?.id)
        XCTAssertNotEqual(copiedLettering, spec.id); XCTAssertEqual(copiedGuide.guideFor, copiedLettering)

        // Straight takes the word off the line: the line is no longer its guide.
        var straight = rebuilt[0].lettering!; straight.shape = .straight
        design.replaceLettering(spec.id, with: try straight.build(color: ink, embroideryFonts: fonts))
        design.syncGuides(embroideryFonts: fonts)
        XCTAssertNil(design.objects.first { $0.id == line.id }?.guideFor)
    }

    func testBadLinesAreRefused() throws {
        let spec = LetteringSpec(text: "Abc", fontKind: .embroidery, font: "small_font", height: 10)
        var closed = RunObject(name: "Ring", nodes: [Point(0, 0), Point(10, 0), Point(5, 8)].map { PathNode($0) }); closed.closed = true
        var design = Design(); design.objects = try spec.build(color: ink, embroideryFonts: fonts).objects + [closed]
        XCTAssertThrowsError(try design.putLettering(spec.id, onLine: closed.id, embroideryFonts: fonts), "an outline isn't a line")
        var two = spec; two.text = "Ab\ncd"
        let line = RunObject(name: "Line", nodes: [PathNode(Point(-30, 0)), PathNode(Point(30, 0))])
        var lines = Design(); lines.objects = try two.build(color: ink, embroideryFonts: fonts).objects + [line]
        let unchanged = lines
        XCTAssertThrowsError(try lines.putLettering(two.id, onLine: line.id, embroideryFonts: fonts), "two lines of text")
        XCTAssertEqual(lines, unchanged, "nothing changed")
    }
}
