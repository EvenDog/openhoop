// Checks hoops of your own: how their names are tidied and kept unique, and that preferences without them still load.
import XCTest
@testable import EmbroideryApp
import EmbroideryCore

final class MyHoopsTests: XCTestCase {
    @MainActor func testNamesAreTrimmedAndKeptUnique() {
        XCTAssertEqual(Preferences.uniqueHoopName("  Magnetic 5 × 5 ", among: []), "Magnetic 5 × 5")
        XCTAssertNil(Preferences.uniqueHoopName("   ", among: []), "an empty name isn't saved")
        XCTAssertEqual(Preferences.uniqueHoopName("My hoop", among: ["My hoop"]), "My hoop 2")
        XCTAssertEqual(Preferences.uniqueHoopName("My hoop", among: ["My hoop", "My hoop 2"]), "My hoop 3")
        XCTAssertEqual(Preferences.uniqueHoopName("Brother 4 × 4 in", among: []), "Brother 4 × 4 in 2", "a built-in hoop's name stays the built-in hoop's")
    }

    func testMyHoopsSaveAndOlderPreferencesLoad() throws {
        let old = try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(PreferenceData()))
        XCTAssertNil(old.myHoops)
        var data = PreferenceData(); data.myHoops = [Hoop(width: 130, height: 130, oval: true, name: "Round 5")]
        XCTAssertEqual(try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(data)).myHoops, data.myHoops)
    }
}
