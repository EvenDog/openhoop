// The updater's setup: the app names its update feed and key and checks by itself, the feed on the website is valid
// and every release in it is signed, and the updater stays off outside the app bundle (in tests).
import XCTest
import EmbroideryCore
@testable import EmbroideryApp

final class UpdatesTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testTheAppNamesItsFeedAndKeyAndChecksByItself() throws {
        let info = try XCTUnwrap(NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist")))
        XCTAssertEqual(info["SUFeedURL"] as? String, "https://openhoop.app/appcast.xml")
        let key = try XCTUnwrap(info["SUPublicEDKey"] as? String)
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32, "an Ed25519 public key is 32 bytes")
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
    }

    func testEveryReleaseInTheFeedIsSignedAndOnGitHub() throws {
        let feed = try XMLDocument(contentsOf: root.appendingPathComponent("website/appcast.xml"))
        let enclosures = try feed.nodes(forXPath: "//item/enclosure").compactMap { $0 as? XMLElement }
        XCTAssertFalse(enclosures.isEmpty)
        for enclosure in enclosures {
            let url = try XCTUnwrap(enclosure.attribute(forName: "url")?.stringValue)
            XCTAssertTrue(url.hasPrefix("https://github.com/EvenDog/openhoop/releases/download/v"), url)
            XCTAssertEqual(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue.flatMap { Data(base64Encoded: $0) }?.count, 64, "an Ed25519 signature is 64 bytes")
            XCTAssertGreaterThan(Int(enclosure.attribute(forName: "length")?.stringValue ?? "") ?? 0, 0)
        }
        let builds = try feed.nodes(forXPath: "//item/*[local-name()='version']").compactMap { Int($0.stringValue ?? "") }
        XCTAssertEqual(builds, builds.sorted(by: >), "newest first, each build once")
        XCTAssertEqual(Set(builds).count, builds.count)
    }

    @MainActor func testTheUpdaterStaysOffOutsideTheAppBundle() {
        Updates.start()
        XCTAssertNil(Updates.controller)
        XCTAssertNil(Updates.menuItem())
    }
}
