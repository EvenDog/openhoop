// Bean stitch: running stitch sewn back and forth 3 or 5 times per stitch, saved with the project.
import XCTest
@testable import EmbroideryCore

final class BeanStitchTests: XCTestCase {
    private func line(passes: Int?) -> RunObject {
        var object = RunObject(name: "Line", nodes: [PathNode(Point(-20, 0)), PathNode(Point(20, 0))])
        object.digitizing = DigitizingSettings(kind: .run); object.digitizing?.runPasses = passes; object.stitchLength = 2.5
        return object
    }

    func testEachStitchGoesForwardBackForward() throws {
        let a = Point(0, 0), b = Point(1, 0), c = Point(2, 0)
        XCTAssertEqual(try RunningEngine.repeated([a, b, c], passes: 3), [a, b, a, b, c, b, c])
        XCTAssertEqual(try RunningEngine.repeated([a, b, c], passes: 5), [a, b, a, b, a, b, c, b, c, b, c])
        XCTAssertEqual(try RunningEngine.repeated([a, b, c], passes: 1), [a, b, c])
        XCTAssertEqual(try RunningEngine.repeated([], passes: 3), [])
    }

    func testBeanStitchTriplesTheStitchesAndEndsInTheSamePlace() throws {
        let single = line(passes: nil), bean = line(passes: 3)
        let points = try RunningEngine.stitches(for: single).count
        var design = Design(); design.objects = [single]
        let plainPlan = try StitchEngine.compile(design)
        design.objects = [bean]
        let beanPlan = try StitchEngine.compile(design)
        XCTAssertEqual(beanPlan.stitchCount - plainPlan.stitchCount, 2 * (points - 1), "Each stitch is sewn twice more")
        XCTAssertEqual(beanPlan.commands.last?.point, plainPlan.commands.last?.point)
        XCTAssertEqual(bean.stitchTitle, "Bean")
        XCTAssertEqual(single.stitchTitle, "Running")
    }

    func testPassesSaveNeedTheNewerFileAndAreChecked() throws {
        var design = Design(); design.objects = [line(passes: 3)]
        XCTAssertTrue(design.needsSchemaFive, "Older versions would sew bean stitch as a single line, so they must refuse the file")
        let reloaded = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(reloaded.objects[0].settings.runPasses, 3)
        design.objects = [line(passes: nil)]
        XCTAssertFalse(design.needsSchemaFive)
        design.objects = [line(passes: 2)]
        XCTAssertThrowsError(try design.validate())
    }
}
