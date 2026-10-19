// A design's thread palette: the basic colors until it's changed, every used thread always in it, adding and
// removing threads, and older files without a palette opening unchanged.
import XCTest
@testable import EmbroideryCore

final class ThreadPaletteTests: XCTestCase {
    private let poppy = ThreadColor("Poppy", 0xE0241B, brand: "Isacord Polyester", code: "1703")
    private let navy = ThreadColor("Navy", 0x1C2A4A, brand: "Isacord Polyester", code: "3355")

    private func design(colors: [ThreadColor]) -> Design {
        var design = Design()
        design.objects = colors.enumerated().map { i, color in
            RunObject(name: "Line \(i)", nodes: [Point(0, Double(i)), Point(10, Double(i))].map { PathNode($0) }, color: color)
        }
        return design
    }

    func testANewDesignShowsTheBasicColorsAndAnyThreadItUses() {
        XCTAssertEqual(Design().paletteThreads, ThreadColor.palette)
        // An older file: no palette saved, its objects sewn in a chart thread and a basic one.
        let older = design(colors: [poppy, ThreadColor.palette[0], poppy])
        XCTAssertNil(older.palette)
        XCTAssertEqual(older.paletteThreads, ThreadColor.palette + [poppy], "the basic colors, then each thread used, once")
        XCTAssertEqual(older.usedThreads, [poppy, ThreadColor.palette[0]], "in sewing order")
    }

    func testAddingKeepsOrderAndNeverDuplicates() {
        var palette = Design()
        palette.addToPalette(poppy); palette.addToPalette(navy); palette.addToPalette(poppy)
        XCTAssertEqual(palette.paletteThreads, ThreadColor.palette + [poppy, navy])
    }

    func testAThreadInUseCantBeRemovedAndUnusedOnesCan() {
        var palette = design(colors: [poppy])
        palette.addToPalette(navy)
        palette.removeFromPalette(poppy)
        XCTAssertTrue(palette.paletteThreads.contains(poppy), "an object still sews in it")
        palette.removeFromPalette(navy)
        XCTAssertFalse(palette.paletteThreads.contains(navy))
        palette.addToPalette(navy)
        palette.removeUnusedFromPalette()
        XCTAssertEqual(palette.paletteThreads, [poppy], "only the thread the design sews in is left")
    }

    func testThePaletteIsSavedAndADamagedOneIsRefused() throws {
        var saved = design(colors: [poppy])
        saved.addToPalette(navy)
        let reopened = try JSONDecoder().decode(Design.self, from: try JSONEncoder().encode(saved))
        XCTAssertEqual(reopened.paletteThreads, saved.paletteThreads)
        XCTAssertNoThrow(try reopened.validate())
        var damaged = Design(); damaged.palette = [ThreadColor("Bad", 0x1000000)]
        XCTAssertThrowsError(try damaged.validate())
    }
}
