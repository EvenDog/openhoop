// Checks test swatches (copies of an object with one setting stepped, in a grid that fits the hoop, named after their
// values) and the density map (a plain fill is fine; satins stacked three deep are too dense).
import XCTest
@testable import EmbroideryCore

final class SwatchAndDensityTests: XCTestCase {
    private func square(_ size: Double, at corner: Point = Point(0, 0)) -> RunObject {
        var object = RunObject(name: "Square", nodes: [Point(0, 0), Point(size, 0), Point(size, size), Point(0, size)].map { PathNode(corner + $0) })
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }

    func testSwatchesStepOneSettingInAGridThatFitsTheHoop() throws {
        let values = TestSwatches.values(start: 0.3, step: 0.05, count: 5)
        XCTAssertEqual(values, [0.3, 0.35, 0.4, 0.45, 0.5])
        let design = try TestSwatches.design(square(15, at: Point(30, 30)), setting: .rowSpacing, values: values, hoop: Hoop(width: 100, height: 100))
        XCTAssertEqual(design.objects.map(\.settings.spacing), values, "each copy gets its value, in sewing order")
        XCTAssertEqual(design.objects.map(\.name), ["Row spacing 0.3 mm", "Row spacing 0.35 mm", "Row spacing 0.4 mm", "Row spacing 0.45 mm", "Row spacing 0.5 mm"])
        XCTAssertEqual(Set(design.objects.map(\.id)).count, 5, "separate objects")
        let points = design.objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        XCTAssertTrue(points.allSatisfy { Hoop(width: 100, height: 100).contains($0, tolerance: -2) }, "the grid fits inside the hoop")
        // A 3 × 2 grid: the first row's copies sit side by side, the next row below.
        XCTAssertEqual(design.objects[1].nodes[0].point.x - design.objects[0].nodes[0].point.x, 19, accuracy: 1e-9, "15 mm wide, 4 mm apart")
        XCTAssertLessThan(design.objects[3].nodes[0].point.y, design.objects[0].nodes[0].point.y, "the second row is lower")
        XCTAssertNoThrow(try StitchEngine.compile(design))

        XCTAssertThrowsError(try TestSwatches.design(square(40), setting: .rowSpacing, values: values, hoop: Hoop(width: 100, height: 100)), "five 40 mm swatches don't fit")
        XCTAssertThrowsError(try TestSwatches.design(square(10), setting: .rowSpacing, values: [0.05], hoop: Hoop(width: 100, height: 100)), "out of range")
        XCTAssertEqual(SwatchSetting.available(for: .satin), [.rowSpacing, .compensation, .compensationPercent, .underlaySpacing])
    }

    func testDensityMapFlagsStackedSatinsButNotAPlainFill() throws {
        var design = Design(); design.objects = [square(20)]
        XCTAssertFalse(DensityMap.cells(try StitchEngine.compile(design)).contains { $0.level == .tooDense }, "an ordinary fill isn't too dense")
        let rungs = stride(from: 0.0, through: 20, by: 5).flatMap { y in [PathNode(Point(40, y)), PathNode(Point(44, y))] }
        var satin = RunObject(name: "Satin", nodes: rungs); satin.digitizing = DigitizingSettings(kind: .satin)
        design.objects = [satin, satin, satin].map { var copy = $0; copy.id = UUID(); return copy }
        let cells = DensityMap.cells(try StitchEngine.compile(design))
        XCTAssertGreaterThan(cells.filter { $0.level == .tooDense }.count, 20, "three satins on top of each other are too dense")
        XCTAssertTrue(cells.allSatisfy { $0.corner.x >= 39 && $0.corner.x <= 45 }, "only where the satins are")
    }
}
