// Thread charts: reading GIMP palettes (bundled and imported), finding the closest thread, and Match All.
import XCTest
@testable import EmbroideryCore

final class ThreadChartTests: XCTestCase {
    func testReadsInkStitchStyleChartWithCodes() throws {
        // Same layout as Ink/Stitch's charts: a prefixed name, tab-padded numbers, and the code as the last word.
        let text = "GIMP Palette\nName: Ink/Stitch: Test Polyester\nColumns: 4\n# RGB Value\t\tColor Name Number\n"
            + "183\t195\t197\t                Cool Mist   1610\n255 255 255\t       \t          White\t  0015\n"
        let chart = try ThreadChart.parse(text, fallbackName: "file")
        XCTAssertEqual(chart.name, "Test Polyester")
        XCTAssertEqual(chart.threads, [ThreadColor("Cool Mist", 0xB7C3C5, brand: "Test Polyester", code: "1610"),
                                       ThreadColor("White", 0xFFFFFF, brand: "Test Polyester", code: "0015")])
        XCTAssertEqual(chart.threads[0].chartLabel, "Test Polyester 1610")
    }

    func testReadsPlainPaletteWithoutCodes() throws {
        let chart = try ThreadChart.parse("GIMP Palette\n255 0 0 Red\n0 0 128 Navy Blue\n10 20 30\nnot a color line\n", fallbackName: "My Threads")
        XCTAssertEqual(chart.name, "My Threads", "Without a Name: line, the file name names the chart")
        XCTAssertEqual(chart.threads.map(\.name), ["Red", "Navy Blue", "#0A141E"])
        XCTAssertEqual(chart.threads.map(\.code), [nil, nil, nil], "Names without a number in the last word have no code")
    }

    func testRejectsFilesThatArentPalettes() {
        XCTAssertThrowsError(try ThreadChart.parse("hello\n255 0 0 Red\n", fallbackName: "x"))
        XCTAssertThrowsError(try ThreadChart.parse("GIMP Palette\nName: Empty\n", fallbackName: "x"))
        XCTAssertThrowsError(try ThreadChart.parse("GIMP Palette\n256 0 0 Too Red\n", fallbackName: "x"))
    }

    func testBundledMachineChartsLoad() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/ThreadCharts")
        let charts = ThreadChart.all(in: folder)
        XCTAssertEqual(charts.map(\.name), ["Brother (machine palette)", "Husqvarna Viking (machine palette)", "Janome (machine palette)"])
        let brother = try XCTUnwrap(charts.first)
        XCTAssertEqual(brother.threads.count, 64)
        XCTAssertEqual(brother.threads[4], ThreadColor("Red", 0xED171F, brand: "Brother (machine palette)", code: "5"))
    }

    func testNearestPutsExactMatchFirst() {
        let chart = ThreadChart(name: "T", threads: [ThreadColor("Black", 0x000000), ThreadColor("Red", 0xFF0000), ThreadColor("Dark Red", 0xC00000)])
        XCTAssertEqual(chart.nearest(to: 0xFF0000, count: 2).map(\.name), ["Red", "Dark Red"])
        XCTAssertEqual(chart.nearest(to: 0x200000).first?.name, "Black")
        XCTAssertEqual(ThreadChart.distance(0x123456, 0x123456), 0)
    }

    func testMatchAllKeepsSameColorsTogetherAndSkipsLocked() {
        let chart = ThreadChart(name: "T", threads: [ThreadColor("Red", 0xFF0000, brand: "T", code: "1"), ThreadColor("Blue", 0x0000FF, brand: "T", code: "2")])
        var design = Design()
        let coral = ThreadColor("Coral", 0xDC6552), ink = ThreadColor("Navy", 0x101060)
        design.objects = [RunObject(name: "A", nodes: [], color: coral), RunObject(name: "B", nodes: [], color: coral),
                          RunObject(name: "C", nodes: [], color: ink), RunObject(name: "D", nodes: [], color: ink)]
        design.objects[3].locked = true
        XCTAssertEqual(design.matchThreads(to: chart), 3)
        XCTAssertEqual(design.objects.map(\.color.name), ["Red", "Red", "Blue", "Navy"])
        XCTAssertEqual(design.objects[0].color.chartLabel, "T 1")
        XCTAssertEqual(design.matchThreads(to: chart), 0, "Matching again changes nothing")
    }

    func testThreadsWithoutBrandSaveAndLoadAsBefore() throws {
        let old = try JSONDecoder().decode(ThreadColor.self, from: Data(#"{"name":"Ocean","hex":1473664}"#.utf8))
        XCTAssertEqual(old, ThreadColor("Ocean", 0x167C80))
        XCTAssertNil(old.chartLabel)
        let saved = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        XCTAssertFalse(saved.contains("brand"), "Plain threads save exactly as they did before thread charts")
        let branded = ThreadColor("Red", 0xFF0000, brand: "Madeira Polyneon", code: "1747")
        XCTAssertEqual(try JSONDecoder().decode(ThreadColor.self, from: JSONEncoder().encode(branded)), branded)
    }
}
