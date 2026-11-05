// Checks that stitch settings changed in Properties on lettering survive rebuilding it (new text, size, font...):
// changes every part of a stitch kind shares carry over to all the new letters; changes to single letters stay on
// those letters while their line's text is unchanged.
import XCTest
@testable import EmbroideryCore

final class LetteringSettingsTests: XCTestCase {
    private let ink = ThreadColor.palette[0]
    private var embroideryFonts: [EmbroideryFont] { EmbroideryFont.all(in: EmbroideryFontTests.directory) }

    /// A design holding `spec` freshly built.
    private func design(_ spec: LetteringSpec) throws -> Design {
        var design = Design(); design.objects = try spec.build(color: ink, embroideryFonts: embroideryFonts).objects
        return design
    }
    /// `design` with its lettering rebuilt from `spec`, as Properties does.
    private func rebuilt(_ design: Design, _ spec: LetteringSpec) throws -> Design {
        var next = design
        next.replaceLettering(spec.id, with: try spec.build(color: ink, embroideryFonts: embroideryFonts), embroideryFonts: embroideryFonts)
        return next
    }

    func testChangesOnEveryLetterCarryOverToNewText() throws {
        var spec = LetteringSpec(text: "HELLO", fontKind: .embroidery, font: "small_font", height: 8)
        var design = try design(spec)
        XCTAssertTrue(design.objects.contains { $0.kind == .satin })
        for i in design.objects.indices where design.objects[i].kind == .satin {
            design.objects[i].digitizing?.spacing = 0.3; design.objects[i].stitchLength = 3
        }
        spec.text = "HELLO WORLD"
        let next = try rebuilt(design, spec)
        let satins = next.objects.filter { $0.kind == .satin }
        XCTAssertGreaterThan(satins.count, design.objects.filter { $0.kind == .satin }.count, "New letters were added")
        XCTAssertTrue(satins.allSatisfy { $0.settings.spacing == 0.3 && $0.stitchLength == 3 }, "Every satin, new letters too, keeps the change")
        // Nothing else was changed: apart from those two, each part is as the font makes it.
        let fresh = try spec.build(color: ink, embroideryFonts: embroideryFonts).objects
        for (kept, made) in zip(next.objects, fresh) {
            var settings = kept.digitizing; if kept.kind == .satin { settings?.spacing = made.settings.spacing }
            XCTAssertEqual(settings, made.digitizing)
        }
    }

    func testAChangeToOneLetterStaysWhileItsLineIsUnchanged() throws {
        var spec = LetteringSpec(text: "HELLO", fontKind: .embroidery, font: "small_font", height: 8)
        var design = try design(spec)
        // The E's satins (its plain running parts have no stitch settings to change).
        for i in design.objects.indices where design.objects[i].letterKey == 1 && design.objects[i].kind == .satin { design.objects[i].digitizing?.spacing = 0.3 }
        // A new size keeps the text, so the E keeps its change and the other letters stay as the font makes them.
        spec.height = 10
        let resized = try rebuilt(design, spec)
        XCTAssertTrue(resized.objects.filter { $0.letterKey == 1 && $0.kind == .satin }.allSatisfy { $0.settings.spacing == 0.3 })
        XCTAssertTrue(resized.objects.filter { $0.letterKey != 1 }.allSatisfy { $0.settings.spacing != 0.3 })
        // New text could move letters along, so a change made to one letter isn't put on whatever letter is there now.
        spec.text = "JELLO"
        let retyped = try rebuilt(resized, spec)
        XCTAssertTrue(retyped.objects.allSatisfy { $0.settings.spacing != 0.3 })
    }

    /// The fill angle carries over as a turn from the font's own, since each letter's angle can differ (on an arc).
    func testAFillAngleCarriesOverAsATurn() throws {
        var spec = LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica-Bold", height: 12, shape: .archUp, radius: 40)
        var design = try design(spec)
        for i in design.objects.indices where design.objects[i].kind == .fill {
            let angle = design.objects[i].settings.angle
            design.objects[i].digitizing?.angle = Lettering.turned(angle, by: 30)
        }
        spec.text = "Hit"
        let next = try rebuilt(design, spec), fresh = try spec.build(color: ink, embroideryFonts: embroideryFonts).objects
        for (kept, made) in zip(next.objects, fresh) where made.kind == .fill {
            XCTAssertEqual(Lettering.turned(kept.settings.angle, by: -made.settings.angle), 30, accuracy: 0.01)
        }
    }

    /// Settings that belong to one letter's shape (stitch angle lines, a radial fill's center) aren't carried over.
    func testShapeBoundSettingsStayBehind() throws {
        var spec = LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica-Bold", height: 12)
        var design = try design(spec)
        for i in design.objects.indices where design.objects[i].kind == .fill {
            design.objects[i].digitizing?.radialCenter = Point(1, 1); design.objects[i].digitizing?.fillStyle = .radial
        }
        spec.height = 14
        let next = try rebuilt(design, spec)
        let fills = next.objects.filter { $0.kind == .fill }
        XCTAssertTrue(fills.allSatisfy { $0.settings.fillStyle == .radial }, "The fill style carries over")
        XCTAssertTrue(fills.allSatisfy { $0.settings.radialCenter == nil }, "The center was a point on the old letters")
    }
}
