// The Threads panel's library: which threads it shows for a chart name and a search.
import XCTest
@testable import EmbroideryApp
@testable import EmbroideryCore

final class ThreadLibraryTests: XCTestCase {
    private let charts = [ThreadChart(name: "Isacord Polyester", threads: [ThreadColor("Silky White", 0xFFFFFF, code: "0010"), ThreadColor("Black", 0x000000, code: "0020"), ThreadColor("Poppy", 0xE0241B, code: "1703")]),
                          ThreadChart(name: "Brother (machine palette)", threads: [ThreadColor("Red", 0xFF0000, code: "7")])]

    func testTheNamedChartShowsAndTheBasicColorsOtherwise() {
        XCTAssertEqual(ThreadLibrary.threads(chart: "Isacord Polyester", search: "", charts: charts).map(\.code), ["0010", "0020", "1703"])
        XCTAssertEqual(ThreadLibrary.threads(chart: nil, search: "", charts: charts), ThreadColor.palette, "no chart picked: the basic colors")
        XCTAssertEqual(ThreadLibrary.threads(chart: "Gone Brand", search: "", charts: charts), ThreadColor.palette, "a chart that's no longer there: the basic colors")
    }

    func testSearchMatchesNameOrNumber() {
        XCTAssertEqual(ThreadLibrary.threads(chart: "Isacord Polyester", search: "pop", charts: charts).map(\.name), ["Poppy"])
        XCTAssertEqual(ThreadLibrary.threads(chart: "Isacord Polyester", search: "002", charts: charts).map(\.name), ["Black"])
        XCTAssertTrue(ThreadLibrary.threads(chart: "Isacord Polyester", search: "zzz", charts: charts).isEmpty)
    }
}
