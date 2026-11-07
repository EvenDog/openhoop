// The built-in motifs: each one's stroke starts and ends on its baseline where copies join, stays in its box, and
// sews in a motif fill; the motifs added in file version 20 mark a design as needing that version.
import XCTest
@testable import EmbroideryCore

final class MotifShapesTests: XCTestCase {
    func testEveryMotifStartsAndEndsOnItsBaselineAndStaysInItsBox() {
        for motif in Motif.allCases {
            let stroke = Motifs.stroke(motif)
            XCTAssertEqual(stroke.first!, Point(0, 0), "\(motif) starts where the last copy ended")
            XCTAssertEqual(stroke.last!.x, 1, accuracy: 1e-9, "\(motif) ends where the next copy starts")
            XCTAssertEqual(stroke.last!.y, 0, accuracy: 1e-9, "\(motif)")
            XCTAssertTrue(stroke.allSatisfy { $0.x >= -1e-9 && $0.x <= 1 + 1e-9 && $0.y >= -0.5 && $0.y <= 1 + 1e-9 }, "\(motif) stays in its box")
        }
    }

    /// A 40 × 30 mm rectangle filled with each motif in 5 mm copies: whole motifs, all inside the rectangle.
    func testEveryMotifSewsAsAFill() throws {
        let box = [[Point(-0.01, -0.01), Point(40.01, -0.01), Point(40.01, 30.01), Point(-0.01, 30.01)]]
        for motif in Motif.allCases {
            var fill = RunObject(name: motif.title, nodes: [Point(0, 0), Point(40, 0), Point(40, 30), Point(0, 30)].map { PathNode($0) })
            fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
            fill.digitizing?.fillStyle = .motif; fill.digitizing?.motif = motif; fill.digitizing?.angle = 0; fill.digitizing?.expansion = 0
            let sections = try AreaEngine.fill(fill).sections
            XCTAssertGreaterThan(sections.count, 10, "\(motif): many motifs fit")
            XCTAssertTrue(sections.flatMap(\.points).allSatisfy { AreaGeometry.contains($0, rings: box) }, "\(motif) stays inside")
        }
    }

    func testNewerMotifsNeedFileVersionTwenty() throws {
        XCTAssertEqual(Motif.allCases.count, 22)
        XCTAssertEqual(Motif.addedInVersionTwenty.count, 16)
        XCTAssertEqual(Motif.pineTree.title, "Pine tree")
        var line = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(40, 0))])
        line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.runStyle = .motif
        var design = Design(); design.objects = [line]
        for motif in Motif.allCases {
            design.objects[0].digitizing?.motif = motif
            XCTAssertEqual(design.needsSchemaTwenty, Motif.addedInVersionTwenty.contains(motif), motif.title)
        }
        design.objects[0].digitizing?.motif = .snowflake
        let reread = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reread.objects[0].settings.motif, .snowflake, "saved and read back by name")
    }
}
