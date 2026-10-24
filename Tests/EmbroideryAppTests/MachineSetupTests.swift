// Set Up Your Machine: its starting answers, what picking a brand changes, what it saves, and the Stop at Jumps
// reminder it turns on for machines that don't cut threads.
import XCTest
@testable import EmbroideryApp
@testable import EmbroideryCore

final class MachineSetupTests: XCTestCase {
    func testStartsWithAGuessAndPickingABrandPicksItsHoopAndFormat() {
        // Nothing saved yet: a Brother with the 4 × 4 in hoop, saving PES 6, not sure about thread cutting.
        var setup = MachineSetup(from: PreferenceData())
        XCTAssertEqual(setup.brand, .brother)
        XCTAssertEqual(setup.hoop.id, "Brother 4 × 4 in")
        XCTAssertEqual(setup.format, "pes6")
        XCTAssertNil(setup.cutsThreads)
        setup.choose(.janome)
        XCTAssertEqual(setup.hoop.brand, "Janome")
        XCTAssertEqual(setup.format, "jef")
        setup.choose(.viking)
        XCTAssertEqual(setup.format, "vp3")
        // Other keeps the hoop and format, and offers every hoop.
        setup.choose(.other)
        XCTAssertEqual(setup.hoop.brand, "Husqvarna Viking / Pfaff")
        XCTAssertEqual(setup.format, "vp3")
        XCTAssertEqual(MachineBrand.other.hoops.count, HoopPreset.all.count)
        // Someone already using a Janome hoop starts on Janome, with that hoop.
        var data = PreferenceData()
        data.newDesignHoop = HoopPreset.all.first { $0.id == "Janome RE20b" }!.hoop
        XCTAssertEqual(MachineSetup(from: data).brand, .janome)
        XCTAssertEqual(MachineSetup(from: data).hoop.id, "Janome RE20b")
    }

    func testTheAnswersAreSavedAndComeBack() {
        var setup = MachineSetup(from: PreferenceData())
        setup.choose(.janome); setup.hoop = MachineBrand.janome.hoops[2]; setup.cutsThreads = false
        var data = PreferenceData()
        setup.apply(to: &data)
        XCTAssertEqual(data.newDesignHoop, setup.hoop.hoop, "new designs start in it")
        XCTAssertEqual(data.exportFormat, "jef", "exports start in its format")
        XCTAssertEqual(data.cutsThreads, false)
        XCTAssertEqual(MachineSetup(from: data), setup, "and the welcome shows them next time")
    }

    func testExportRemindsAboutStopAtJumpsOnlyForAMachineThatDoesntCutThreads() throws {
        // Two lines in one thread, 20 mm apart: the first ends in a trim, which a machine without a cutter sews as a jump.
        var design = Design()
        design.objects = [Point(-20, 0), Point(10, 0)].enumerated().map { index, start in
            var line = RunObject(name: "Line \(index + 1)", nodes: [PathNode(start), PathNode(start + Point(10, 0))])
            line.digitizing = DigitizingSettings(kind: .run); return line
        }
        let plan = try StitchEngine.compile(design)
        let tip = try XCTUnwrap(MachineSetup.jumpStopTip(cutsThreads: false, design: design, plan: plan))
        XCTAssertTrue(tip.contains("1 part ends in a jump"), tip)
        XCTAssertNil(MachineSetup.jumpStopTip(cutsThreads: true, design: design, plan: plan))
        XCTAssertNil(MachineSetup.jumpStopTip(cutsThreads: nil, design: design, plan: plan), "not sure: no reminder")
        // Once Stop at Jumps is on, there's nothing to remind about.
        var stopped = design
        _ = stopped.addJumpStops(using: plan, in: nil)
        XCTAssertNil(MachineSetup.jumpStopTip(cutsThreads: false, design: stopped, plan: try StitchEngine.compile(stopped)))
    }
}
