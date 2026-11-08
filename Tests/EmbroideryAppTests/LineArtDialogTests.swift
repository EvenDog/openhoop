// The Line Art dialog's size note: how big the drawing comes out, and a warning, with a width that fits, when it's
// too big for the design's hoop.
import XCTest
@testable import EmbroideryApp
@testable import EmbroideryCore

final class LineArtDialogTests: XCTestCase {
    /// The flower at the starting 60 mm is about twice as tall as wide, so it overflows a 100 × 100 mm hoop; the note
    /// says so and names the widest size (in steps of 5 mm) that fits, and that width really does fit.
    func testTooTallForTheHoopSaysWhatFits() {
        let hoop = Hoop(width: 100, height: 100)
        let lines = LineArt.objects(.flower, size: 60, bean: false, color: .palette[0])
        let note = LineArtView.sizeNote(lines, size: 60, hoop: hoop, unit: .millimeters)
        XCTAssertFalse(note.fits)
        XCTAssertTrue(note.text.contains("Too big for the 100 mm × 100 mm hoop"), note.text)
        let fitting = try! XCTUnwrap(note.fittingWidth)
        XCTAssertEqual(fitting.truncatingRemainder(dividingBy: 5), 0)
        XCTAssertTrue(note.text.contains("\(Int(fitting)) mm wide fits"), note.text)
        let smaller = LineArt.objects(.flower, size: fitting, bean: false, color: .palette[0])
        XCTAssertTrue(LineArtView.sizeNote(smaller, size: fitting, hoop: hoop, unit: .millimeters).fits)
        XCTAssertFalse(LineArtView.sizeNote(LineArt.objects(.flower, size: fitting + 5, bean: false, color: .palette[0]), size: fitting + 5, hoop: hoop, unit: .millimeters).fits)
    }

    /// A drawing that fits gets the plain note, with no warning.
    func testAFittingDrawingGetsThePlainNote() {
        let lines = LineArt.objects(.heartDivider, size: 60, bean: false, color: .palette[0])
        let note = LineArtView.sizeNote(lines, size: 60, hoop: Hoop(width: 100, height: 100), unit: .millimeters)
        XCTAssertTrue(note.fits); XCTAssertNil(note.fittingWidth)
        XCTAssertTrue(note.text.hasPrefix("About 60 mm × "), note.text)
        XCTAssertFalse(note.text.contains("Too big"))
    }
}
