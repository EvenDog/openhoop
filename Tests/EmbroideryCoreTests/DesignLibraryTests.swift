// Checks how the Design Library finds design files in a folder, and how it searches and orders them.
import XCTest
@testable import EmbroideryCore

final class DesignLibraryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func makeFile(_ path: String) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
    }

    func testFindsProjectsAndMachineFilesInSubfolders() throws {
        try makeFile("Rose.PES")
        try makeFile("Flowers/Daisy.dst")
        try makeFile("Flowers/Deep/Tulip.jef")
        try makeFile("Sun.stitchproj/design.json")
        try makeFile("notes.txt")
        try makeFile(".hidden.pes")
        let found = DesignLibrary.files(in: folder)
        XCTAssertEqual(Set(found.map(\.name)), ["Rose", "Daisy", "Tulip", "Sun"], "machine files at any depth and projects, nothing else")
        XCTAssertEqual(found.first { $0.name == "Rose" }?.format, .pes, "capital extensions count too")
        XCTAssertNil(found.first { $0.name == "Sun" }?.format, "a project has no machine format")
    }

    func testDoesNotLookInsideProjects() throws {
        // A project is a folder; a machine file kept inside one belongs to the project, not the library.
        try makeFile("Sun.stitchproj/design.json")
        try makeFile("Sun.stitchproj/Exports/Sun.pes")
        XCTAssertEqual(DesignLibrary.files(in: folder).map(\.name), ["Sun"])
    }

    func testMissingFolderFindsNothing() {
        XCTAssertTrue(DesignLibrary.files(in: folder.appendingPathComponent("gone")).isEmpty)
    }

    func testSearchIgnoresCapitalsAndSortsLikeFinder() {
        let day = Date(timeIntervalSince1970: 1_000_000)
        let files = [("Rose 10", 3), ("rose 2", 1), ("Daisy", 2)].map {
            LibraryFile(url: URL(fileURLWithPath: "/d/\($0.0).pes"), format: .pes, modified: day.addingTimeInterval(Double($0.1)))
        }
        XCTAssertEqual(DesignLibrary.matching(files, search: "ROSE", sort: .name).map(\.name), ["rose 2", "Rose 10"])
        XCTAssertEqual(DesignLibrary.matching(files, search: " ", sort: .newest).map(\.name), ["Rose 10", "Daisy", "rose 2"])
    }
}
