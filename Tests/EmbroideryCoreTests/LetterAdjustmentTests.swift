// Checks lettering's letter spacing and letter nudges: spacing widens the word evenly, a nudge moves just that letter
// (the others stay exactly where they were, on straight and arched baselines alike), every part knows its letter,
// and lettering using them is saved as file version 6.
import XCTest
@testable import EmbroideryCore

final class LetterAdjustmentTests: XCTestCase {
    private let ink = ThreadColor.palette[0]
    private var fonts: [EmbroideryFont] { EmbroideryFont.all(in: EmbroideryFontTests.directory) }

    private func box(_ objects: [RunObject]) -> (min: Point, max: Point) {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        return (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
    }
    /// The parts of letter `key`.
    private func letter(_ key: Int, _ objects: [RunObject]) -> [RunObject] { objects.filter { $0.letterKey == key } }

    func testEveryPartKnowsItsLetter() throws {
        for kind in [LetteringSpec.FontKind.embroidery, .system] {
            let spec = LetteringSpec(text: "Abc", fontKind: kind, font: kind == .embroidery ? "small_font" : "Helvetica-Bold", height: 12)
            let objects = try spec.build(color: ink, embroideryFonts: fonts).objects
            XCTAssertTrue(objects.allSatisfy { $0.letterKey != nil }, "\(kind)")
            XCTAssertEqual(Set(objects.compactMap(\.letterKey)), [0, 1, 2], "\(kind): three letters")
        }
        var two = LetteringSpec(text: "Ab\ncd", fontKind: .system, font: "Helvetica-Bold", height: 10)
        two.alignment = .left
        XCTAssertEqual(Set(try two.build(color: ink, embroideryFonts: fonts).objects.compactMap(\.letterKey)), [0, 1, 1000, 1001], "line × 1000 + place")
    }

    func testLetterSpacingWidensTheWordEvenly() throws {
        var spec = LetteringSpec(text: "Abc", fontKind: .embroidery, font: "small_font", height: 12)
        let plain = try spec.build(color: ink, embroideryFonts: fonts).objects
        spec.letterSpacing = 2
        let spaced = try spec.build(color: ink, embroideryFonts: fonts).objects
        let width = { (objects: [RunObject]) -> Double in let b = self.box(objects); return b.max.x - b.min.x }
        XCTAssertEqual(width(spaced) - width(plain), 4, accuracy: 1e-6, "2 mm more between each of the three letters")
    }

    /// A nudge moves only its letter, by a share of the height, after everything else is placed.
    func testNudgingOneLetterLeavesTheOthersAlone() throws {
        for shape in [LetteringShape.straight, .archUp] {
            var spec = LetteringSpec(text: "Abc", fontKind: .embroidery, font: "small_font", height: 12, shape: shape, radius: 60)
            let plain = try spec.build(color: ink, embroideryFonts: fonts).objects
            spec.letterOffsets = [1: Point(0, 0.25)]
            let nudged = try spec.build(color: ink, embroideryFonts: fonts).objects
            for key in [0, 2] {
                XCTAssertEqual(box(letter(key, nudged)).min.x, box(letter(key, plain)).min.x, accuracy: 1e-9, "\(shape): letter \(key) didn't move")
                XCTAssertEqual(box(letter(key, nudged)).min.y, box(letter(key, plain)).min.y, accuracy: 1e-9)
            }
            let moved = box(letter(1, nudged)).min, before = box(letter(1, plain)).min
            XCTAssertEqual(moved.distance(to: before), 3, accuracy: 0.05, "\(shape): letter 1 moved a quarter of 12 mm")
        }
        var design = Design()
        var spec = LetteringSpec(text: "Abc", fontKind: .embroidery, font: "small_font", height: 12)
        design.objects = try spec.build(color: ink, embroideryFonts: fonts).objects
        XCTAssertFalse(design.needsSchemaSix, "plain lettering saves as before")
        spec.letterOffsets = [0: Point(0.1, 0)]
        design.objects = try spec.build(color: ink, embroideryFonts: fonts).objects
        XCTAssertTrue(design.needsSchemaSix)
    }

    /// The lettering's start and end: on its first and last letter, kept through a rebuild and a move, not counted as
    /// a hand edit, and Auto Start Points gives only the first letter one.
    func testLetteringStartAndEndBelongToTheWord() throws {
        var spec = LetteringSpec(text: "Abc", fontKind: .embroidery, font: "small_font", height: 12)
        var design = Design()
        design.objects = try spec.build(color: ink, embroideryFonts: fonts).objects
        design.setLetteringStart(spec.id, Point(-20, 0)); design.setLetteringEnd(spec.id, Point(20, 0))
        XCTAssertEqual(design.objects.first?.entry, Point(-20, 0)); XCTAssertEqual(design.objects.last?.exit, Point(20, 0))
        XCTAssertTrue(design.objects.dropFirst().allSatisfy { $0.entry == nil } && design.objects.dropLast().allSatisfy { $0.exit == nil }, "only the first letter starts, only the last ends")
        spec = design.objects[0].lettering!
        XCTAssertTrue(spec.matchesFreshBuild(design.objects, embroideryFonts: fonts), "a start and end aren't a hand edit")
        spec.text = "Abcd"
        let rebuilt = try spec.build(color: ink, embroideryFonts: fonts).objects
        XCTAssertEqual(rebuilt.first?.entry, Point(-20, 0)); XCTAssertEqual(rebuilt.last?.exit, Point(20, 0), "kept when the text changes")
        var moved = rebuilt[0]; moved.transform { $0 + Point(5, 0) }
        XCTAssertEqual(moved.lettering?.entry, Point(-15, 0), "they move with the letters")

        var square = RunObject(name: "Square", nodes: [Point(-40, -40), Point(-30, -40), Point(-30, -30), Point(-40, -30)].map { PathNode($0) })
        square.closed = true; square.digitizing = DigitizingSettings(kind: .fill)
        var withSquare = Design(); withSquare.objects = [square] + (try LetteringSpec(text: "Abc", fontKind: .embroidery, font: "small_font", height: 12).build(color: ink, embroideryFonts: fonts).objects)
        let started = try StitchEngine.autoStartPoints(withSquare)
        XCTAssertNotNil(started.objects[1].entry, "the word's first letter gets a start point")
        XCTAssertTrue(started.objects.dropFirst(2).allSatisfy { $0.entry == nil }, "its other letters don't")
        XCTAssertEqual(started.objects[1].lettering?.entry, started.objects[1].entry, "and its recipe keeps it")
    }
}
