// Checks Settings › Designs and Grid & snap: older preferences keep today's behaviour, drawn objects start with the
// chosen stitch values (then the design's fabric values), new designs start with the chosen fabric and hoop, and the
// grid and Snap follow the chosen sizes in either unit. Preferences are changed in memory only, never saved.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class DesignsSettingsTests: XCTestCase {
    func testOlderPreferencesKeepTodaysBehaviour() throws {
        let old = try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(PreferenceData()))
        XCTAssertNil(old.gridSize); XCTAssertNil(old.snapSize); XCTAssertNil(old.newDesignFabric); XCTAssertNil(old.newDesignHoopPinned)
        XCTAssertNil(old.lineStitchLength); XCTAssertNil(old.fillStitchLength); XCTAssertNil(old.fillAngle); XCTAssertNil(old.satinPullPercent)
        var chosen = PreferenceData(); chosen.gridSize = .coarse; chosen.newDesignFabric = .knit; chosen.fillAngle = 30
        let reloaded = try JSONDecoder().decode(PreferenceData.self, from: JSONEncoder().encode(chosen))
        XCTAssertEqual(reloaded.gridSize, .coarse); XCTAssertEqual(reloaded.newDesignFabric, .knit); XCTAssertEqual(reloaded.fillAngle, 30)
    }

    func testGridAndSnapSizesInBothUnits() {
        XCTAssertEqual(LengthUnit.millimeters.gridSpacing(.normal), 10, "the normal grid is today's")
        XCTAssertEqual(LengthUnit.inches.gridSpacing(.normal), 12.7)
        XCTAssertEqual(LengthUnit.millimeters.snap(12.4), 12, "the normal snap is today's")
        XCTAssertEqual(LengthUnit.millimeters.snap(12.4, size: .fine), 12.5)
        XCTAssertEqual(LengthUnit.millimeters.snap(12.4, size: .coarse), 12)
        XCTAssertEqual(LengthUnit.inches.snap(12.4, size: .coarse), 12.7, accuracy: 1e-9, "0.5 in, on a 0.1 in step")
        XCTAssertEqual(GridSize.allCases.map(LengthUnit.millimeters.gridLabel), ["5 mm", "10 mm", "20 mm"])
        XCTAssertEqual(GridSize.allCases.map(LengthUnit.inches.snapLabel), ["0.025 in", "0.05 in", "0.1 in"])
    }

    /// A fill drawn with the Fill tool gets the stitch length and angle from Settings, and its row spacing from the
    /// design's fabric; without settings it keeps the built-in values.
    @MainActor func testDrawnObjectsStartWithTheChosenValues() {
        _ = NSApplication.shared
        let preferences = Preferences.shared, saved = preferences.data
        defer { preferences.data = saved }   // in memory only, never saved
        func drawFill(in state: EditorState) -> RunObject {
            state.tool = .fill
            state.draft = [Point(0, 0), Point(20, 0), Point(20, 20), Point(0, 20)].map { PathNode($0) }
            state.finishPath()
            guard let fill = state.design.objects.last else { XCTFail("no fill drawn: \(state.status) \(state.tool) \(state.draft.count)"); return RunObject(name: "", nodes: []) }
            return fill
        }
        preferences.data.fillStitchLength = nil; preferences.data.fillAngle = nil
        let first = DesignDocument()   // kept alive: its state only edits while the document exists
        var fill = drawFill(in: first.state)
        XCTAssertEqual(fill.stitchLength, 3); XCTAssertEqual(fill.settings.angle, 45)

        preferences.data.fillStitchLength = 3.5; preferences.data.fillAngle = 30
        let second = DesignDocument(), state = second.state
        state.edit("Fabric") { $0.fabricType = .knit }
        fill = drawFill(in: state)
        XCTAssertEqual(fill.stitchLength, 3.5); XCTAssertEqual(fill.settings.angle, 30)
        XCTAssertEqual(fill.settings.spacing, 0.45, "row spacing still comes from the knit fabric")

        preferences.data.lineStitchLength = 2; preferences.data.satinPullPercent = 5
        XCTAssertEqual(preferences.withNewObjectDefaults(RunObject(name: "Line", nodes: [])).stitchLength, 2)
        var satin = RunObject(name: "Satin", nodes: []); satin.digitizing = DigitizingSettings(kind: .satin)
        XCTAssertEqual(preferences.withNewObjectDefaults(satin).settings.pullPercent, 5)
    }

    /// New designs start with the fabric and hoop for new designs; a hoop picked in Settings isn't replaced when one
    /// design gets another hoop.
    @MainActor func testNewDesignsStartWithTheChosenFabricAndHoop() {
        let preferences = Preferences.shared, saved = preferences.data
        defer { preferences.data = saved }   // in memory only, never saved
        let big = Hoop(width: 130, height: 180, name: "Brother 5 × 7 in")
        preferences.data.newDesignFabric = .towel; preferences.data.newDesignHoop = big; preferences.data.newDesignHoopPinned = true
        var design = Design()
        preferences.startNewDesign(&design)
        XCTAssertEqual(design.fabric, .towel); XCTAssertEqual(design.hoop, big)
        preferences.rememberHoop(Hoop())   // another design changes its hoop: the picked one stays
        XCTAssertEqual(preferences.data.newDesignHoop, big)
        preferences.data.newDesignFabric = nil
        design = Design(); preferences.startNewDesign(&design)
        XCTAssertEqual(design.fabric, .woven, "no fabric chosen means woven, as before")
    }
}
