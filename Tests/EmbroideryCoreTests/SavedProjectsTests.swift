// Opens every project saved in this checkout (the sew-out pack in docs/sewout and the sample projects in dist) and
// checks that each still opens, passes the safety checks, comes back unchanged after a save and reopen, and can be
// sewn. These are files made by earlier versions of the app, so this catches a change that breaks older projects.
import XCTest
@testable import EmbroideryCore

final class SavedProjectsTests: XCTestCase {
    /// The repository's top folder (three levels up from this file: Tests/EmbroideryCoreTests/<this file>).
    private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every project's design.json in docs/sewout and dist. Either folder may be missing (dist only exists after a
    /// build), so this can be empty.
    private func projectFiles() -> [URL] {
        ["docs/sewout", "dist"].flatMap { folder -> [URL] in
            let directory = repository.appendingPathComponent(folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.filter { $0.hasSuffix(".stitchproj") }.sorted()
                .map { directory.appendingPathComponent($0).appendingPathComponent("design.json") }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func testEverySavedProjectOpensSavesAndSews() throws {
        let files = projectFiles()
        try XCTSkipIf(files.isEmpty, "This checkout has no saved projects to open.")
        for file in files {
            let name = file.deletingLastPathComponent().lastPathComponent
            let design: Design
            do { design = try JSONDecoder().decode(Design.self, from: Data(contentsOf: file)) }
            catch { XCTFail("\(name) doesn't open: \(error)"); continue }
            XCTAssertNoThrow(try design.validate(), "\(name) fails the safety checks")

            // Saving and reopening must give back exactly the same design.
            let reopened = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
            XCTAssertEqual(reopened, design, "\(name) changes when it's saved and opened again")

            // It can be sewn. If not, name the objects to blame rather than just the file.
            do {
                let plan = try StitchEngine.compile(design)
                // The stitch count saved in the file (from the version that saved it) next to today's, for the log.
                // Different counts aren't a failure: the engine has improved since some of these were saved.
                let saved = design.cachedPlan.map { String($0.stitchCount) } ?? "none saved"
                print("SavedProjects: \(name): \(design.objects.count) objects, \(plan.stitchCount) stitches now, \(saved) in the file, engine \(design.engineVersion)")
            } catch {
                let broken = (try? StitchEngine.compileSkippingBroken(design))?.broken.values.sorted() ?? []
                XCTFail("\(name) can't be sewn: \(broken.isEmpty ? error.localizedDescription : broken.joined(separator: "; "))")
            }
        }
    }
}
