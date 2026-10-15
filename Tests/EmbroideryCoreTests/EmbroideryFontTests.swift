// Embroidery fonts: the bundled Ink/Stitch fonts load, are permissively licensed, lay out and sew; satin columns
// with rails and rungs convert into this app's edge pairs; font satins use the relaxed checks.
import XCTest
@testable import EmbroideryCore

final class EmbroideryFontTests: XCTestCase {
    /// The fonts bundled with the app, straight from the repository's Resources folder.
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/EmbroideryFonts")
    private var fonts: [EmbroideryFont] { EmbroideryFont.all(in: Self.directory) }
    private func font(_ folder: String) throws -> EmbroideryFont { try EmbroideryFont(folder: Self.directory.appendingPathComponent(folder)) }

    func testBundledFontsAreAllPermissivelyLicensed() {
        XCTAssertEqual(fonts.count, 18)
        for font in fonts {
            let license = font.licenseText.uppercased()
            XCTAssertTrue(license.contains("OPEN FONT LICENSE") || license.contains("PUBLIC DOMAIN"), font.name)
            for restricted in ["BY-NC", "NON-COMMERCIAL", "BY-SA", "SHAREALIKE", "BY-ND", "GNU GENERAL PUBLIC"] {
                XCTAssertFalse(license.contains(restricted), "\(font.name) mentions \(restricted)")
            }
            XCTAssertLessThan(font.heights.lowerBound, font.heights.upperBound, font.name)
        }
    }

    func testEveryBundledFontSews() throws {
        for font in fonts {
            let result = try font.shapes(text: "Hag 5", height: font.heights.lowerBound + (font.heights.upperBound - font.heights.lowerBound) / 3, color: .palette[0])
            XCTAssertTrue(result.objects.contains { $0.kind == .satin }, "\(font.name) makes satin")
            XCTAssertFalse(result.warnings.contains { $0.contains("couldn't be converted") }, "\(font.name): \(result.warnings)")
            var design = Design(); design.objects = result.objects
            XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 50, font.name)
            XCTAssertEqual(Set(result.objects.map(\.groupID)).count, 1, "One group")
        }
    }

    func testCapitalHeightSpacingAndPlacement() throws {
        let small = try font("small_font")
        let h = try small.shapes(text: "H", height: 8, color: .palette[0])
        XCTAssertEqual(h.height, 8, accuracy: 0.4, "The reference capital comes out the chosen height")
        let pair = try small.shapes(text: "HH", height: 8, color: .palette[0]), spaced = try small.shapes(text: "H H", height: 8, color: .palette[0])
        XCTAssertGreaterThan(pair.width, 2 * h.width, "Letters don't overlap")
        XCTAssertGreaterThan(spaced.width, pair.width, "A space adds the font's word spacing")
        let points = pair.objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        XCTAssertEqual(points.map(\.x).min()! + points.map(\.x).max()!, 0, accuracy: 0.01, "Centered on the hoop")
    }

    func testSizesAndCharactersTheFontCantDo() throws {
        let small = try font("small_font")
        XCTAssertThrowsError(try small.shapes(text: "Hi", height: small.heights.upperBound + 5, color: .palette[0])) { error in
            XCTAssertTrue(error.localizedDescription.contains("digitized for"))
        }
        // Characters the font doesn't have are named in a note (this font draws its placeholder glyph instead).
        let result = try small.shapes(text: "H☃", height: 8, color: .palette[0])
        XCTAssertTrue(result.warnings.contains { $0.contains("☃") }, "\(result.warnings)")
    }

    func testTrimsOnlyBetweenDistantParts() throws {
        let result = try font("caffeine_tiny").shapes(text: "Ho", height: 6, color: .palette[0])
        XCTAssertTrue(result.objects.last!.trimAfter)
        XCTAssertTrue(result.objects.dropLast().contains { !$0.trimAfter }, "Parts that sew on from each other aren't trimmed")
    }

    // MARK: Converting satin columns

    private func subpath(_ points: [Point]) -> SVGSubpath { SVGSubpath(points: points, closed: false, nodes: points.map { PathNode($0) }) }

    func testRailsAndRungsBecomeEdgePairs() throws {
        // Two rails 10 mm long and 2 mm apart, plus a rung, listed rung first: the rung is recognized because it
        // crosses both rails.
        let left = subpath([Point(0, 0), Point(0, 10)]), right = subpath([Point(2, 0), Point(2, 10)]), rung = subpath([Point(-0.2, 4), Point(2.2, 6)])
        let nodes = try XCTUnwrap(SatinConversion.nodes([rung, left, right], reverse: "automatic", swap: false))
        XCTAssertEqual(nodes.count % 2, 0)
        for i in stride(from: 0, to: nodes.count, by: 2) { XCTAssertEqual(nodes[i].point.x, 0); XCTAssertEqual(nodes[i + 1].point.x, 2) }
        // The rung's crossing points (left at y ≈ 4.17, right at ≈ 5.83) are sewn together.
        XCTAssertTrue(stride(from: 0, to: nodes.count, by: 2).contains { abs(nodes[$0].point.y - 4.1667) < 0.01 && abs(nodes[$0 + 1].point.y - 5.8333) < 0.01 })
        XCTAssertLessThanOrEqual(nodes.count / 2, 25, "About every 0.5 mm")
    }

    func testOppositeRailsAreTurnedAround() throws {
        let left = subpath([Point(0, 0), Point(0, 10)]), right = subpath([Point(2, 10), Point(2, 0)])
        let nodes = try XCTUnwrap(SatinConversion.nodes([left, right], reverse: "automatic", swap: false))
        XCTAssertEqual(nodes[1].point, Point(2, 0), "The second rail is reversed to run the same way")
        let kept = try XCTUnwrap(SatinConversion.nodes([left, right], reverse: "none", swap: false))
        XCTAssertEqual(kept[1].point, Point(2, 10), "\"Don't reverse\" is respected")
        let swapped = try XCTUnwrap(SatinConversion.nodes([left, subpath([Point(2, 0), Point(2, 10)])], reverse: "automatic", swap: true))
        XCTAssertEqual(swapped[0].point.x, 2, "Swap rails puts the second rail first")
    }

    func testWithoutRungsMatchingNodesAreSewnTogether() throws {
        // A bend: both rails have a middle node, which pair up even though the rails are different lengths.
        let left = subpath([Point(0, 0), Point(0, 10), Point(10, 10)]), right = subpath([Point(2, 0), Point(2, 8), Point(10, 8)])
        let nodes = try XCTUnwrap(SatinConversion.nodes([left, right], reverse: "automatic", swap: false))
        XCTAssertTrue(stride(from: 0, to: nodes.count, by: 2).contains { nodes[$0].point == Point(0, 10) && nodes[$0 + 1].point == Point(2, 8) })
    }

    func testFontSatinsUseRelaxedChecks() throws {
        // A column that fans out from a point, as many font letters do: hand-drawn satins reject it, font satins sew it.
        var fan = RunObject(name: "Fan", nodes: [Point(0, 0), Point(0, 0), Point(-1, 5), Point(1, 5), Point(-1, 10), Point(1, 10)].map { PathNode($0) })
        fan.digitizing = DigitizingSettings(kind: .satin)
        XCTAssertThrowsError(try AreaEngine.satin(fan))
        fan.digitizing?.relaxedChecks = true
        XCTAssertGreaterThan(try AreaEngine.satin(fan).sections.last!.points.count, 20)
        var design = Design(); design.objects = [fan]
        XCTAssertTrue(design.needsSchemaFive, "Older versions would reject relaxed satins, so the file says so")
    }
}
