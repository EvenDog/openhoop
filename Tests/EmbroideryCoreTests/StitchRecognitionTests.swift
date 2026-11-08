// Recognize Objects on five real machine files, digitized by other people in three programs (Tests/Fixtures/resize,
// see its README): each comes back as the fills and satin columns it was made of, all of them sew, and at 150% they
// keep their density instead of stretching their stitches. Also: a stop in the stitches stays, and a block with
// nothing to recognize is left alone.
import XCTest
@testable import EmbroideryCore

final class StitchRecognitionTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/resize")

    /// A fixture as an import makes it: one imported stitch block per thread, in a 200 mm hoop.
    private func imported(_ name: String) throws -> Design {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixtures.appendingPathComponent("\(name).json"))) as! [String: Any]
        var plan = StitchPlan()
        plan.threads = (json["threads"] as! [[String: Any]]).map { ThreadColor($0["name"] as! String, $0["hex"] as! Int) }
        plan.commands = (json["commands"] as! [[Any]]).map { c in
            StitchCommand(StitchOperation(rawValue: c[0] as! String)!, Point((c[1] as! NSNumber).doubleValue, (c[2] as! NSNumber).doubleValue), thread: c[3] as! Int)
        }
        var design = Design()
        design.hoop = Hoop(width: 200, height: 200)
        design.objects = try MachineImport.objects(from: plan, format: "pes", name: name)
        return design
    }

    /// The fixture with every imported block recognized, and what was found.
    private func recognized(_ name: String) throws -> (design: Design, summary: StitchRecognition.Summary) {
        var design = try imported(name)
        let summary = design.recognizeObjects(Set(design.objects.map(\.id)))
        return (design, summary)
    }

    func testEachDesignComesBackAsTheFillsAndSatinsItWasMadeOf() throws {
        // Counted by eye from the designs: the smileys are a face and two cheeks (fills), two eyes and a mouth
        // (satins), the Ink/Stitch one with a satin ring round it too; the melting face is one fill with two oval
        // eyes and a mouth; the grinning face is a face and a sweat drop, two eyes, a mouth (sewn as two columns)
        // and a small satin beside the drop.
        let expected: [(String, fills: Int, satins: Int)] = [
            ("smiling-face", 3, 3), ("smiling-face-inkstitch", 3, 4), ("melting-face", 1, 3), ("melting-face-hand-stitch", 1, 3),
            ("grinning-face-with-sweat", 2, 4)
        ]
        for (name, fills, satins) in expected {
            let (design, summary) = try recognized(name)
            XCTAssertEqual(summary.fills, fills, "\(name) fills")
            XCTAssertEqual(summary.satins, satins, "\(name) satins")
            XCTAssertEqual(design.objects.filter { $0.kind == .fill }.count, fills, name)
            XCTAssertEqual(design.objects.filter { $0.kind == .satin }.count, satins, name)
            // Whatever wasn't recognized is a small share of the design.
            let imported = try self.imported(name).objects.compactMap(\.rawStitches).reduce(0) { $0 + $1.commands.count }
            XCTAssertLessThan(Double(summary.keptStitches), 0.1 * Double(imported), name)
        }
    }

    func testRecognizedFillsKeepTheirRows() throws {
        // The melting face's fill: rows about 109° (−71° shown), 0.2 mm apart (0.4 measured across two rows), 4 mm stitches.
        let fill = try XCTUnwrap(recognized("melting-face").design.objects.first { $0.kind == .fill })
        XCTAssertEqual(fill.settings.angle, -71, accuracy: 3)
        XCTAssertEqual(fill.settings.spacing, 0.4, accuracy: 0.03)
        XCTAssertEqual(fill.stitchLength, 4, accuracy: 0.3)
        XCTAssertEqual(fill.holes?.count, 3, "the eyes and the mouth")
    }

    func testEveryRecognizedObjectSews() throws {
        for name in ["smiling-face", "smiling-face-inkstitch", "melting-face", "melting-face-hand-stitch", "grinning-face-with-sweat"] {
            let design = try recognized(name).design
            let (plan, broken) = try StitchEngine.compileSkippingBroken(design)
            XCTAssertEqual(broken, [:], name)
            XCTAssertGreaterThan(plan.stitchCount, 1000, name)
        }
    }

    func testAt150PercentTheDesignKeepsItsDensity() throws {
        func grown(_ design: Design) -> Design {
            var design = design
            for i in design.objects.indices { design.objects[i].transform { $0 * 1.5 } }
            return design
        }
        let imported = try self.imported("melting-face"), design = try recognized("melting-face").design
        let before = try RunningEngine.compile(design).stitchCount, after = try RunningEngine.compile(grown(design)).stitchCount
        // 1.5 times as wide and as tall: about 2.25 times the stitches (satins only grow with their length).
        XCTAssertGreaterThan(Double(after) / Double(before), 1.8)
        // Imported stitches just stretch: the same stitches, 1.5 times as long and as far apart.
        XCTAssertEqual(try RunningEngine.compile(grown(imported)).stitchCount, try RunningEngine.compile(imported).stitchCount)
    }

    func testAStopInTheStitchesStays() throws {
        // A 20 × 10 mm block of fill rows 0.2 mm apart, 3 mm stitches, and the machine stops after it.
        var commands: [RawStitch] = [], y = 0.0, forward = true
        while y <= 10 {
            for x in stride(from: 0.0, through: 20, by: 2.5) { commands.append(RawStitch(.stitch, Point(forward ? x : 20 - x, y))) }
            y += 0.2; forward.toggle()
        }
        commands.append(RawStitch(.stop, commands[commands.count - 1].point))
        var block = RunObject(name: "block", nodes: [], color: ThreadColor("Red", 0xff0000))
        block.rawStitches = RawStitchBlock(start: Point(0, 0), commands: commands, sourceFormat: "pes")
        var design = Design(); design.objects = [block]
        let summary = design.recognizeObjects([block.id])
        XCTAssertEqual(summary.fills, 1)
        XCTAssertEqual(design.objects.last?.kind, .fill)
        XCTAssertEqual(design.objects.last?.stopAfter, true)
    }

    /// A satin sewn at a known spacing, read back as imported stitches, is recognized at that spacing (not the
    /// default), so resizing it keeps the original density.
    func testRecognizedSatinsKeepTheirSpacing() throws {
        for spacing in [0.3, 0.6] {
            var satin = RunObject(name: "Satin", nodes: (0..<5).flatMap { i -> [PathNode] in let x = Double(i) * 10 - 20; return [PathNode(Point(x, 0)), PathNode(Point(x, 4))] })
            satin.digitizing = DigitizingSettings(kind: .satin); satin.digitizing?.spacing = spacing
            var made = Design(); made.objects = [satin]
            var design = Design()
            design.objects = try MachineImport.objects(from: RunningEngine.compile(made), format: "pes", name: "Satin")
            _ = design.recognizeObjects(Set(design.objects.map(\.id)))
            let found = try XCTUnwrap(design.objects.first { $0.kind == .satin }, "spacing \(spacing)")
            XCTAssertEqual(found.settings.spacing, spacing, accuracy: 0.03, "spacing \(spacing)")
        }
    }

    /// A fill sewn with a tatami pattern, read back as imported stitches, comes back with that pattern, at an angle
    /// too; a plain (Smooth) fill comes back plain.
    func testRecognizedFillsKeepTheirTatamiPattern() throws {
        for (id, angle) in [("smooth", 45.0), ("reverse", 45), ("sawtooth", 0), ("sawtoothReversed", 30), ("zigzag", -30), ("blocks", 90), ("steep", 15), ("hills", 60)] {
            var fill = RunObject(name: "Fill", nodes: ShapeGeometry.nodes(.ellipse, in: (Point(-25, -20), Point(25, 20))))
            fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
            fill.digitizing?.angle = angle; fill.digitizing?.tatamiPattern = id == "smooth" ? nil : id
            var made = Design(); made.objects = [fill]
            var design = Design()
            design.objects = try MachineImport.objects(from: RunningEngine.compile(made), format: "pes", name: "Fill")
            _ = design.recognizeObjects(Set(design.objects.map(\.id)))
            let found = try XCTUnwrap(design.objects.first { $0.kind == .fill }, id)
            XCTAssertEqual(found.settings.tatamiPattern, id == "smooth" ? nil : id, "\(id) at \(angle)°")
        }
    }

    /// A satin ring (a border round a shape) comes back as one closed satin, not an open column with a notch where
    /// its ends meet; so does the grinning face's mouth ring. Columns whose ends are apart stay open.
    func testASatinRingComesBackClosed() throws {
        let ring = try ShapeStitching.closedShape(ShapeGeometry.nodes(.ellipse, in: (Point(-25, -15), Point(25, 15))), fill: nil, outline: .satin, satinWidth: 3, name: "Ring", color: .palette[0])
        var made = Design(); made.objects = ring
        var design = Design()
        design.objects = try MachineImport.objects(from: RunningEngine.compile(made), format: "pes", name: "Ring")
        _ = design.recognizeObjects(Set(design.objects.map(\.id)))
        let satins = design.objects.filter { $0.kind == .satin }
        XCTAssertEqual(satins.count, 1)
        XCTAssertEqual(satins.first?.closed, true)
        XCTAssertNoThrow(try RunningEngine.compile(design))
        let grinning = try recognized("grinning-face-with-sweat").design.objects.filter { $0.kind == .satin }
        XCTAssertEqual(grinning.filter(\.closed).count, 1, "the mouth ring")
        XCTAssertFalse(try recognized("melting-face").design.objects.contains { $0.kind == .satin && $0.closed }, "eyes and mouth are open columns")
    }

    func testABlockWithNothingToRecognizeStaysAsItIs() throws {
        // A short straight line: no fill, no satin.
        var block = RunObject(name: "line", nodes: [], color: ThreadColor("Red", 0xff0000))
        block.rawStitches = RawStitchBlock(start: Point(0, 0), commands: (1...5).map { RawStitch(.stitch, Point(Double($0) * 2.5, 0)) }, sourceFormat: "dst")
        var design = Design(); design.objects = [block]
        let before = design
        XCTAssertFalse(design.recognizeObjects([block.id]).foundAny)
        XCTAssertEqual(design, before)
    }

    func testOnlyTheChosenBlocksChange() throws {
        var design = try imported("melting-face")
        let untouched = design.objects[1]
        let summary = design.recognizeObjects([design.objects[0].id])
        XCTAssertEqual(summary.fills, 1)
        XCTAssertEqual(summary.satins, 0, "the satins are in the other thread, which wasn't chosen")
        XCTAssertEqual(design.objects.last, untouched)
    }
}
