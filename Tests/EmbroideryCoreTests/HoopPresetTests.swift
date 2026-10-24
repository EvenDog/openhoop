// Hoop presets: the list itself, recognizing a preset hoop (also turned sideways), and what makes a hoop custom.
import XCTest
@testable import EmbroideryCore

final class HoopPresetTests: XCTestCase {
    func testPresetsAreUprightUniqueAndSane() {
        XCTAssertEqual(Set(HoopPreset.all.map(\.id)).count, HoopPreset.all.count, "Every preset has its own name")
        for preset in HoopPreset.all {
            XCTAssertLessThanOrEqual(preset.width, preset.height, "\(preset.id) is listed upright")
            XCTAssertTrue((50...400).contains(preset.width) && (50...400).contains(preset.height), preset.id)
        }
        XCTAssertEqual(HoopPreset.brands, ["Brother", "Janome", "Husqvarna Viking / Pfaff"])
    }

    func testPresetHoopIsRecognizedEitherWayRound() throws {
        let fiveBySeven = try XCTUnwrap(HoopPreset.all.first { $0.id == "Brother 5 × 7 in" })
        let hoop = fiveBySeven.hoop
        XCTAssertEqual(hoop.preset, fiveBySeven)
        XCTAssertEqual(hoop.label, "Brother 5 × 7 in · 130 × 180 mm")
        XCTAssertFalse(hoop.isSideways)
        let sideways = hoop.turned
        XCTAssertEqual(sideways.width, 180); XCTAssertEqual(sideways.height, 130)
        XCTAssertTrue(sideways.isSideways)
        XCTAssertEqual(sideways.label, "Brother 5 × 7 in · 180 × 130 mm (sideways)")
        XCTAssertEqual(sideways.turned, hoop, "Turning twice puts it back")
    }

    func testSizeNamedHoopsDontRepeatTheirSize() throws {
        let viking = try XCTUnwrap(HoopPreset.all.first { $0.id == "Husqvarna Viking / Pfaff 150 × 240 mm" })
        XCTAssertEqual(viking.menuTitle, "150 × 240 mm")
        XCTAssertEqual(viking.hoop.label, "Husqvarna Viking / Pfaff · 150 × 240 mm")
        XCTAssertEqual(viking.hoop.turned.label, "Husqvarna Viking / Pfaff · 240 × 150 mm (sideways)")
    }

    func testChangedSizeOrShapeIsCustom() throws {
        var hoop = try XCTUnwrap(HoopPreset.all.first).hoop
        hoop.width = 110
        XCTAssertNil(hoop.preset)
        XCTAssertEqual(hoop.label, "Custom · 110 × 100 mm")
        let oval = Hoop(width: 100, height: 100, oval: true, name: "Brother 4 × 4 in")
        XCTAssertNil(oval.preset, "Preset hoops are rectangular")
        XCTAssertEqual(Hoop().label, "Custom · 100 × 100 mm", "Designs from before presets have no hoop name")
    }

    func testAHoopOfYourOwnShowsItsName() {
        let magnetic = Hoop(width: 130, height: 130, name: "Magnetic 5 × 5")
        XCTAssertNil(magnetic.preset)
        XCTAssertEqual(magnetic.ownName, "Magnetic 5 × 5")
        XCTAssertEqual(magnetic.label, "Magnetic 5 × 5 · 130 × 130 mm")
        XCTAssertEqual(Hoop(width: 100, height: 140, oval: true, name: "Round").turned.label, "Round · 140 × 100 mm (oval)", "turning keeps the name")
        XCTAssertNil(Hoop(width: 110, height: 100, name: "Brother 4 × 4 in").ownName, "a preset's name on another size isn't a hoop of your own")
        XCTAssertNil(Hoop(width: 110, height: 100, name: "").ownName)
    }

    func testHoopNameSavesAndOlderProjectsLoad() throws {
        let old = try JSONDecoder().decode(Hoop.self, from: Data(#"{"width":100,"height":100,"oval":false}"#.utf8))
        XCTAssertNil(old.name)
        let named = HoopPreset.all[1].hoop
        XCTAssertEqual(try JSONDecoder().decode(Hoop.self, from: JSONEncoder().encode(named)), named)
        var design = Design(); design.hoop = named
        XCTAssertNoThrow(try design.validate())
    }
}
