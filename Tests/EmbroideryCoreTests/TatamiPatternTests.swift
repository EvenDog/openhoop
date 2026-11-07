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
        for pattern in TatamiPattern.library where pattern.picture == nil {
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

    /// The 18 patterns added in file version 20 mark a design as needing it; the first 26 don't.
    func testNewerPatternsNeedFileVersionTwenty() throws {
        XCTAssertEqual(TatamiPattern.library.count, 56)
        XCTAssertEqual(TatamiPattern.addedInVersionTwenty.count, 18)
        XCTAssertEqual(Set(TatamiPattern.library.dropLast(12).suffix(18).map(\.id)), TatamiPattern.addedInVersionTwenty, "they come after the first 26")
        var fill = RunObject(name: "Fill", nodes: square.map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        var design = Design(); design.objects = [fill]
        for pattern in TatamiPattern.library {
            design.objects[0].digitizing?.tatamiPattern = pattern.id
            XCTAssertEqual(design.needsSchemaTwenty, TatamiPattern.addedInVersionTwenty.contains(pattern.id), pattern.name)
        }
        design.objects[0].digitizing?.tatamiPattern = "woodGrain"
        design.schemaVersion = 20
        XCTAssertNoThrow(try design.validate())
    }

    /// The row patterns' holes are where they always were: each row's start, then a stitch length apart.
    func testRowPatternHolesAreUnchanged() {
        for pattern in TatamiPattern.library where pattern.picture == nil {
            for row in 0..<40 {
                let lo = Double(row) * 0.37 - 5, hi = lo + 23.3
                var expected: [Double] = [], x = floor(lo / 3) * 3 + pattern.offset(row: row) * 3
                while x <= lo + 0.00001 { x += 3 }
                while x < hi - 0.00001 { expected.append(x); x += 3 }
                XCTAssertEqual(pattern.holes(row: row, y: Double(row) * 0.2, from: lo, to: hi, length: 3), expected, "\(pattern.name), row \(row)")
            }
        }
    }

    /// The 12 picture patterns come last, are the ones marked as version 21, and need it; the others don't.
    func testPicturePatternsNeedFileVersionTwentyOne() throws {
        let pictures = TatamiPattern.library.filter { $0.picture != nil }
        XCTAssertEqual(pictures.count, 12)
        XCTAssertEqual(Set(TatamiPattern.library.suffix(12).map(\.id)), TatamiPattern.addedInVersionTwentyOne, "the pictures come last in the menu")
        XCTAssertEqual(Set(pictures.map(\.id)), TatamiPattern.addedInVersionTwentyOne)
        var fill = RunObject(name: "Fill", nodes: square.map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        var design = Design(); design.objects = [fill]
        for pattern in TatamiPattern.library {
            design.objects[0].digitizing?.tatamiPattern = pattern.id
            XCTAssertEqual(design.needsSchemaTwentyOne, pattern.picture != nil, pattern.name)
            XCTAssertFalse(design.needsSchemaTwenty && pattern.picture != nil, "\(pattern.name) needs 21, not 20")
        }
        design.objects[0].digitizing?.tatamiPattern = "hearts"
        design.schemaVersion = 21
        XCTAssertNoThrow(try design.validate())
    }

    /// A picture's holes: one wherever the row crosses an outline, no stitch longer than the stitch length, and none
    /// shorter than 0.15 of it, over many rows of every picture at two sizes.
    func testPictureHolesTraceTheOutlinesWithinTheStitchLength() {
        for pattern in TatamiPattern.library {
            guard let picture = pattern.picture else { continue }
            for size in [picture.defaultSize, 4.5] {
                for row in 0..<150 {
                    let y = Double(row) * 0.2 + 0.1, lo = -7.3, hi = 31.1
                    let holes = pattern.holes(row: row, y: y, from: lo, to: hi, length: 3, size: size)
                    let marks = picture.crossings(y: y, from: lo + 0.00001, to: hi - 0.00001, width: size, minimumGap: 0.45)
                    for mark in marks { XCTAssertTrue(holes.contains(mark), "\(pattern.name) row \(row): a hole on the outline at \(mark)") }
                    let all = [lo] + holes + [hi]
                    for (a, b) in zip(all, all.dropFirst()) {
                        XCTAssertLessThanOrEqual(b - a, 3.00001, "\(pattern.name) row \(row): no stitch over 3 mm")
                        if a != lo && b != hi { XCTAssertGreaterThanOrEqual(b - a, 0.45 - 0.00001, "\(pattern.name) row \(row): no tiny stitch") }
                    }
                }
            }
        }
    }

    /// Each picture changes the stitches from Smooth's, and its Shape size (Pattern size in the file) changes them again.
    func testPicturesAndTheirSizeChangeTheStitches() throws {
        var fill = RunObject(name: "Fill", nodes: square.map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill); fill.stitchLength = 3
        var design = Design(); design.objects = [fill]
        let smooth = try StitchEngine.compile(design).commands.map(\.point)
        for pattern in TatamiPattern.library where pattern.picture != nil {
            design.objects[0].digitizing?.tatamiPattern = pattern.id
            design.objects[0].digitizing?.patternSize = nil
            let picture = try StitchEngine.compile(design).commands.map(\.point)
            XCTAssertNotEqual(picture, smooth, pattern.name)
            design.objects[0].digitizing?.patternSize = 14
            XCTAssertNotEqual(try StitchEngine.compile(design).commands.map(\.point), picture, "\(pattern.name): Shape size")
        }
    }
}
