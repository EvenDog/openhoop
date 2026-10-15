// The production worksheet's numbers: thread steps in sewing order, stops, trims, size and the time estimate.
import XCTest
@testable import EmbroideryCore

final class ProductionSummaryTests: XCTestCase {
    private func line(_ name: String, from a: Point, to b: Point, color: ThreadColor) -> RunObject {
        RunObject(name: name, nodes: [PathNode(a), PathNode(b)], color: color)
    }

    func testStepsFollowThreadChangesAndStops() throws {
        let ocean = ThreadColor.palette[0], coral = ThreadColor.palette[1]
        var design = Design()
        var placement = line("Placement", from: Point(-20, 0), to: Point(20, 0), color: ocean)
        placement.stopAfter = true   // the machine stops so the fabric can be laid, then carries on in the same thread
        design.objects = [placement, line("Tack down", from: Point(-20, 5), to: Point(20, 5), color: ocean),
                          line("Border", from: Point(-20, 10), to: Point(20, -10), color: coral),
                          line("Detail", from: Point(0, -10), to: Point(10, -10), color: ocean)]
        let plan = try StitchEngine.compile(design)
        let summary = ProductionSummary(plan: plan, design: design)

        XCTAssertEqual(summary.steps.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(summary.steps.map(\.color), [ocean, ocean, coral, ocean], "Going back to a color is a new step")
        XCTAssertEqual(summary.steps.map(\.parts), [["Placement"], ["Tack down"], ["Border"], ["Detail"]])
        XCTAssertEqual(summary.steps.map(\.stopAfter), [true, false, false, false])
        XCTAssertEqual(summary.steps.map(\.stitches).reduce(0, +), plan.stitchCount)
        XCTAssertEqual(summary.stitchCount, plan.stitchCount)
        XCTAssertEqual(summary.stops, 1)
        XCTAssertEqual(summary.threadChanges, 2)
        XCTAssertEqual(summary.trims, 4, "Every object trims after itself by default")
        XCTAssertEqual(summary.width, 40, accuracy: 0.01)
        XCTAssertEqual(summary.height, 20, accuracy: 0.01)
        // Each object's own stitches, which add up to the whole design.
        let counts = plan.stitchCountsByObject
        XCTAssertEqual(Set(counts.keys), Set(design.objects.map(\.id)))
        XCTAssertEqual(counts.values.reduce(0, +), plan.stitchCount)
        XCTAssertEqual(counts[design.objects[0].id], summary.steps[0].stitches)
    }

    func testObjectsInOneThreadShareAStep() throws {
        var design = Design()
        design.objects = [line("Left", from: Point(-10, 0), to: Point(0, 0), color: .palette[2]),
                          line("Right", from: Point(1, 0), to: Point(10, 0), color: .palette[2])]
        let summary = ProductionSummary(plan: try StitchEngine.compile(design), design: design)
        XCTAssertEqual(summary.steps.count, 1)
        XCTAssertEqual(summary.steps[0].parts, ["Left", "Right"])
        XCTAssertEqual(summary.threadChanges, 0)
    }

    func testLetteringIsListedOnceByItsText() throws {
        let spec = LetteringSpec(text: "TEAM\nCAPTAIN", fontKind: .system, font: "Helvetica-Bold", height: 8)
        var design = Design()
        design.objects = try spec.build(color: .palette[0], embroideryFonts: []).objects
        XCTAssertGreaterThan(design.objects.count, 5)
        let summary = ProductionSummary(plan: try StitchEngine.compile(design), design: design)
        XCTAssertEqual(summary.steps.map(\.parts), [["Lettering “TEAM / CAPTAIN”"]])
    }

    func testSewingTimeEstimate() throws {
        var summary = ProductionSummary(plan: StitchPlan(), design: Design())
        XCTAssertEqual(summary.steps, [])
        XCTAssertEqual(summary.width, 0)
        summary.stitchCount = 6000; summary.trims = 12; summary.threadChanges = 2; summary.stops = 1
        // 6,000 stitches at 600 per minute is 10 minutes; 12 trims × 5 s is 1 minute; 3 pauses × 1 minute.
        XCTAssertEqual(summary.sewingMinutes(speed: 600), 14, accuracy: 0.0001)
        XCTAssertEqual(summary.sewingMinutes(speed: 1200), 9, accuracy: 0.0001)
        XCTAssertEqual(ProductionSummary.duration(0.4), "under 1 min")
        XCTAssertEqual(ProductionSummary.duration(14.2), "14 min")
        XCTAssertEqual(ProductionSummary.duration(65), "1 h 05 min")
    }
}
