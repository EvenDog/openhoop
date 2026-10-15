// Fabric presets: woven matches the long-standing defaults, other fabrics change fills and cover satins only,
// applying to a whole design, and the worksheet note.
import XCTest
@testable import EmbroideryCore

final class FabricPresetTests: XCTestCase {
    private func shape(_ kind: StitchKind) -> RunObject {
        var o = RunObject(name: kind.title, nodes: [Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)].map { PathNode($0) })
        o.digitizing = DigitizingSettings(kind: kind); o.closed = kind == .fill
        return o
    }

    func testWovenIsTodaysDefaults() {
        var design = Design(); design.objects = [shape(.fill), shape(.satin), shape(.run)]
        XCTAssertEqual(design.fabric, .woven, "Designs without a fabric are woven")
        XCTAssertEqual(design.shapesNeedingFabric, 0, "Woven changes nothing in a design with default settings")
    }

    func testKnitChangesFillsAndSatins() {
        var design = Design(); design.fabricType = .knit
        let fill = design.withFabric(shape(.fill)).settings, satin = design.withFabric(shape(.satin)).settings
        XCTAssertEqual(fill.spacing, 0.45); XCTAssertEqual(fill.expansion, 0.35); XCTAssertEqual(fill.underlay, .edgeAndSparse); XCTAssertEqual(fill.underlaySpacing, 1.0)
        XCTAssertEqual(satin.expansion, 0.35); XCTAssertEqual(satin.underlay, .auto); XCTAssertEqual(satin.stretchyFabric, true)
        var manual = shape(.satin); manual.digitizing?.underlay = .center
        XCTAssertEqual(design.withFabric(manual).settings.underlay, .zigzag, "A chosen underlay gets the fabric's")
        let run = shape(.run)
        XCTAssertEqual(design.withFabric(run), run, "Running lines keep their settings")
    }

    func testWhatFabricsLeaveAlone() {
        var tack = shape(.satin); tack.digitizing?.spacing = 1.5; tack.digitizing?.underlay = .none
        XCTAssertFalse(FabricType.applies(to: tack), "Open zigzags such as appliqué tack-downs keep their spacing")
        var font = shape(.satin); font.digitizing?.relaxedChecks = true
        XCTAssertFalse(FabricType.applies(to: font))
        var letter = shape(.fill); letter.lettering = LetteringSpec(text: "A", fontKind: .system, font: "Helvetica", height: 10)
        XCTAssertFalse(FabricType.applies(to: letter), "Lettering is rebuilt from its font")
        XCTAssertFalse(FabricType.applies(to: shape(.run)))
        XCTAssertTrue(FabricType.applies(to: shape(.fill)))
    }

    func testApplyingToTheWholeDesignSkipsLockedShapes() {
        var design = Design(); design.objects = [shape(.fill), shape(.satin), shape(.fill), shape(.run)]
        design.objects[2].locked = true
        design.fabricType = .towel
        XCTAssertEqual(design.shapesNeedingFabric, 2)
        XCTAssertEqual(design.applyFabricToAll(), 2)
        XCTAssertEqual(design.objects[0].settings.spacing, 0.35)
        XCTAssertEqual(design.objects[2].settings.spacing, 0.4, "Locked shapes keep their settings")
        XCTAssertEqual(design.shapesNeedingFabric, 0)
    }

    func testFabricSavesAndTheWorksheetNamesTheStabilizer() throws {
        var design = Design(); design.fabricType = .knit; design.objects = [shape(.fill)]
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design)).fabricType, .knit)
        let summary = ProductionSummary(plan: try StitchEngine.compile(design), design: design)
        XCTAssertEqual(summary.fabric, .knit)
        XCTAssertTrue(summary.warnings.first?.contains("Cut-away") == true, "\(summary.warnings)")
    }
}

