// Checks the Light / Dark / Match system choice in Settings › General.
import XCTest
import AppKit
@testable import EmbroideryApp

final class AppearanceTests: XCTestCase {
    func testEachChoiceGivesItsAppearanceAndMatchSystemFollowsTheMac() {
        XCTAssertNil(AppAppearance.system.nsAppearance, "nil lets the windows follow the Mac's setting")
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
    }

    @MainActor func testOlderPreferencesMatchTheSystemAndTheChoiceIsRemembered() throws {
        let old = try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(PreferenceData()))
        XCTAssertNil(old.appearance)
        var dark = PreferenceData(); dark.appearance = .dark
        XCTAssertEqual(try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(dark)).appearance, .dark)
    }
}
