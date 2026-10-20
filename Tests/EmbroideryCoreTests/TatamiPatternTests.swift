// Tatami patterns: each row's needle holes start where its pattern says, Smooth stays the classic quarter stagger,
// and a design naming a pattern is checked and marked as needing this version.
import XCTest
@testable import EmbroideryCore

final class TatamiPatternTests: XCTestCase {
    private let square = [Point(0, 0), Point(30, 0), Point(30, 20), Point(0, 20)]

    /// Where each row's inner holes fall, as a fraction of the 3 mm stitch, row by row from the first sewn (the bottom).
    /// Points near the sides are left out: the steps between rows run along them, and the end holes can shift to
    /// avoid slivers. A sewn section holds many rows, so rows are told apart by their height (0.2 mm apart).
    private func starts(_ pattern: TatamiPattern) throws -> [[Double]] {
        let points = try AreaEngine.rows(in: [square], angle: 0, spacing: 0.2, length: 3, pattern: pattern).joined()
        var rows: [Int: [Double]] = [:]
        for point in points where point.x > 3.5 && point.x < 26.5 {
            let fraction = (point.x / 3).truncatingRemainder(dividingBy: 1)
            rows[Int(point.y / 0.2), default: []].append(fraction > 0.9999 ? 0 : fraction)
        }
        return rows.keys.sorted().map { rows[$0]! }
    }

    func testEachRowStartsWhereItsPatternSays() throws {
        for pattern in TatamiPattern.library {
            for (index, row) in try starts(pattern).enumerated() {
                for fraction in row { XCTAssertEqual(fraction, pattern.offset(row: index), accuracy: 0.0001, "\(pattern.name), row \(index)") }
            }
        }
    }

    func testSmoothIsTheClassicQuarterStagger() throws {
        XCTAssertEqual(TatamiPattern.of(DigitizingSettings(kind: .fill)), .smooth, "no pattern named: Smooth")
        XCTAssertEqual((0..<8).map { TatamiPattern.smooth.offset(row: $0) }, [0, 0.25, 0.5, 0.75, 0, 0.25, 0.5, 0.75])
    }

    func testPatternsAreDistinctAndInRange() {
        XCTAssertEqual(Set(TatamiPattern.library.map(\.id)).count, TatamiPattern.library.count, "ids are unique")
        for pattern in TatamiPattern.library {
            XCTAssertTrue((0..<200).allSatisfy { (0..<1).contains(pattern.offset(row: $0)) }, pattern.name)
        }
        let scattered = try! XCTUnwrap(TatamiPattern.named("scattered"))
        XCTAssertGreaterThan(Set((0..<64).map { scattered.offset(row: $0) }).count, 4, "scattered uses many starts")
    }

    func testADesignNamingAPatternIsCheckedAndMarked() throws {
        var fill = RunObject(name: "Fill", nodes: square.map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        var design = Design(); design.objects = [fill]
        XCTAssertFalse(design.needsSchemaSix)
        design.objects[0].digitizing?.tatamiPattern = "zigzag"
        XCTAssertNoThrow(try design.validate())
        XCTAssertTrue(design.needsSchemaSix, "older versions refuse it instead of sewing it plain")
        let zigzag = try StitchEngine.compile(design)
        design.objects[0].digitizing?.tatamiPattern = nil
        XCTAssertNotEqual(try StitchEngine.compile(design).commands.map(\.point), zigzag.commands.map(\.point), "the pattern changes the stitches")
        design.objects[0].digitizing?.tatamiPattern = "no such pattern"
        XCTAssertThrowsError(try design.validate())
    }
}
