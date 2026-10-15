// Lettering: typed text becomes grouped fill or outline shapes, using fonts that ship with every Mac.
import XCTest
@testable import EmbroideryCore

final class LetteringTests: XCTestCase {
    private let ink = ThreadColor.palette[0]

    func testCapitalLettersAreTheChosenHeightAndCentered() throws {
        let result = try Lettering.shapes(text: "H", fontName: "Helvetica", height: 20, stitch: .fill, color: ink)
        XCTAssertEqual(result.objects.count, 1)
        XCTAssertEqual(result.height, 20, accuracy: 0.05, "Letter height is the height of a capital")
        let points = result.objects[0].outlinePaths.flatMap { $0 }
        XCTAssertEqual(points.map(\.y).max()! + points.map(\.y).min()!, 0, accuracy: 0.01, "Centered on the hoop")
        XCTAssertEqual(points.map(\.x).max()! + points.map(\.x).min()!, 0, accuracy: 0.01)
    }

    func testLettersWithHolesAndSeparateParts() throws {
        let result = try Lettering.shapes(text: "Oi", fontName: "Helvetica", height: 15, stitch: .fill, color: ink)
        // "O" is one fill with a hole; "i" is a stem and a separate dot.
        XCTAssertEqual(result.objects.map(\.name), ["Letter O", "Letter i", "Letter i (part 2)"])
        XCTAssertEqual(result.objects[0].holes?.count, 1)
        XCTAssertTrue(result.objects.allSatisfy { $0.kind == .fill && $0.closed })
        XCTAssertTrue(result.objects[0].nodes.contains(where: \.hasHandles), "The font's curves are kept as Bézier handles")
        XCTAssertEqual(Set(result.objects.map(\.groupID)).count, 1, "All letters are one group")
        XCTAssertNotNil(result.objects[0].groupID)
    }

    func testOutlineMakesARunningLineForEveryEdge() throws {
        let result = try Lettering.shapes(text: "O", fontName: "Helvetica", height: 15, stitch: .outline, color: ink)
        XCTAssertEqual(result.objects.count, 2, "Outside edge and the hole's edge")
        XCTAssertTrue(result.objects.allSatisfy { $0.kind == .run && $0.closed })
    }

    func testLetteringSews() throws {
        var design = Design()
        design.objects = try Lettering.shapes(text: "Hi 5", fontName: "Helvetica-Bold", height: 12, stitch: .fill, color: ink).objects
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100)
    }

    func testLettersWhoseCurvesNearlyTouchFallBackToPoints() throws {
        // American Typewriter's bold "z" nearly touches itself once rebuilt as curves; it should still be made.
        let result = try Lettering.shapes(text: "z", fontName: "AmericanTypewriter-Bold", height: 12, stitch: .fill, color: ink)
        XCTAssertEqual(result.objects.count, 1)
        XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
        XCTAssertFalse(result.objects[0].nodes.contains(where: \.hasHandles))
    }

    func testProblemsAreExplained() throws {
        XCTAssertThrowsError(try Lettering.shapes(text: "  ", fontName: "Helvetica", height: 12, stitch: .fill, color: ink))
        XCTAssertThrowsError(try Lettering.shapes(text: "Hi", fontName: "No-Such-Font-Here", height: 12, stitch: .fill, color: ink))
        XCTAssertThrowsError(try Lettering.shapes(text: "Hi", fontName: "Helvetica", height: 500, stitch: .fill, color: ink))
        XCTAssertThrowsError(try Lettering.shapes(text: "two\nlines", fontName: "Helvetica", height: 12, stitch: .fill, color: ink))
        let small = try Lettering.shapes(text: "a", fontName: "Helvetica", height: 6, stitch: .fill, color: ink)
        XCTAssertTrue(small.warnings.contains { $0.contains("10 mm") }, "Small fill letters get a warning")
    }
}
