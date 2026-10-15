// A "crash hunt" for the stitch engine. Each round builds a small design from random shapes, random settings and
// random node edits (the kinds of things a person does in the app), then checks that:
//   • working out the stitches either succeeds or gives a reason, and never crashes;
//   • no stitch is too long for a machine, and none lands far outside the shape that sewed it;
//   • the quick "can this shape still be sewn?" check, used when a node drag ends, agrees with the full engine;
//   • the design comes back unchanged after a save and reopen;
//   • remembered (cached) stitches are exactly what a fresh compile makes.
// The random numbers come from a starting number (a "seed"), so a round that finds a problem can be replayed exactly.
// Normal runs do 15 rounds. FUZZ_ROUNDS=<n> runs more, FUZZ_SEED=<n> replays one round, FUZZ_SLOW=<seconds> also reports
// objects slower than that to work out, and FUZZ_OUT=<folder> saves each problem round's design there (plus the round
// being worked on, so a crash leaves it behind). Long hunts are much faster in a release build:
//   FUZZ_ROUNDS=5000 FUZZ_SLOW=1 swift test -c release -Xswiftc -enable-testing --filter RandomDesignTests
import XCTest
@testable import EmbroideryCore

/// A small random number generator that always gives the same numbers from the same seed (the SplitMix64 recipe).
/// Swift's built-in generator can't be given a seed, which is why this exists.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        // `&+=` and `&*` add and multiply letting the number wrap around, instead of stopping the program on overflow.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class RandomDesignTests: XCTestCase {
    private let ink = ThreadColor.palette[0]
    /// The longest stitch a home machine sews (the same limit the stitch quality checker uses).
    private let machineLimit = 12.1
    /// How far (mm) past its outline a stitch may land before it counts as stray. Satin compensation and fill
    /// expansion rightly push stitches a little past the outline.
    private let strayMargin = 5.0


    /// One kind of problem: how many rounds showed it, the first few seeds, and one example message.
    private struct Finding { var count = 0; var seeds: [UInt64] = []; var example = "" }

    func testRandomDesignsSewSafely() throws {
        let settings = ProcessInfo.processInfo.environment
        let seeds: [UInt64] = settings["FUZZ_SEED"].flatMap(UInt64.init).map { [$0] }
            ?? (1...max(1, settings["FUZZ_ROUNDS"].flatMap(Int.init) ?? 15)).map(UInt64.init)
        // Working out one object for longer than this (seconds) is reported: the app works its stitches out again after
        // every edit, so the person would be left waiting. Off by default, since a test build is many times slower.
        let slowObject = settings["FUZZ_SLOW"].flatMap(Double.init)
        let out = settings["FUZZ_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let out { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }

        var findings: [String: Finding] = [:]
        var sewn = 0, refused = 0, slowest = (seconds: 0.0, seed: UInt64(0))
        var refusals: [String: Int] = [:]   // why designs couldn't be sewn, to check the reasons make sense
        /// Records one problem, saving the round's design for a closer look when FUZZ_OUT is set.
        func note(_ kind: String, _ seed: UInt64, _ detail: String, _ design: Design) {
            var finding = findings[kind] ?? Finding()
            if finding.seeds.last != seed { finding.count += 1; if finding.seeds.count < 8 { finding.seeds.append(seed) } }
            if finding.example.isEmpty { finding.example = "seed \(seed): \(detail)" }
            findings[kind] = finding
            if let out, let data = try? JSONEncoder().encode(design) { try? data.write(to: out.appendingPathComponent("seed-\(seed).json")) }
        }

        for seed in seeds {
            var random = SeededGenerator(seed: seed)
            let design = randomDesign(&random, name: "Round \(seed)")
            if let out, let data = try? JSONEncoder().encode(design) { try? data.write(to: out.appendingPathComponent("current-round.json")) }
            let started = Date()

            // Saving and reopening gives back the same design.
            let reopened = (try? JSONEncoder().encode(design)).flatMap { try? JSONDecoder().decode(Design.self, from: $0) }
            if reopened != design { note("The design changes when saved and reopened", seed, "", design) }

            // Each object on its own: the quick check used after a node drag, against the full engine.
            for object in design.objects {
                var alone = design; alone.objects = [object]
                let quick = StitchEngine.shapeProblem(object)
                let objectStarted = Date()
                let full: String? = { do { _ = try StitchEngine.compile(alone); return nil } catch { return error.localizedDescription } }()
                let objectSeconds = Date().timeIntervalSince(objectStarted)
                if let slowObject, objectSeconds > slowObject {
                    note("One object takes over \(slowObject.formatted()) s to work out", seed, "\(describe(object)) took \(objectSeconds.formatted(.number.precision(.fractionLength(1)))) s", design)
                }
                if let quick, full == nil {
                    note("The drag check refuses a shape the engine can sew", seed, "\(object.stitchTitle): \(quick)", design)
                }
                if quick == nil, let full {
                    note("The drag check lets through a \(object.stitchTitle.lowercased()) that can't be sewn: \(pattern(full))", seed, full, design)
                }
            }

            // The whole design.
            let plan: StitchPlan
            do { plan = try StitchEngine.compile(design); sewn += 1 }
            catch { refused += 1; refusals[pattern(error.localizedDescription), default: 0] += 1; continue }

            // Every stitch: a real position, not too long, and near the shape that sewed it.
            let boxes = Dictionary(uniqueKeysWithValues: design.objects.map { ($0.id, outlineBox($0)) })
            var previous: StitchCommand?
            for command in plan.commands {
                defer { previous = command }   // `defer` runs this at the end of each pass, whichever way it ends
                guard command.point.finite else { note("A stitch has no real position", seed, "\(command)", design); continue }
                guard command.op == .stitch else { continue }
                if let previous, previous.op == .stitch, previous.point.distance(to: command.point) > machineLimit {
                    let object = design.objects.first { $0.id == command.objectID }
                    note("A stitch is longer than \(machineLimit) mm", seed,
                         "\(previous.point.distance(to: command.point).formatted(.number.precision(.fractionLength(1)))) mm in \(object?.stitchTitle ?? "?")", design)
                }
                if let id = command.objectID, let box = boxes[id],
                   command.point.x < box.min.x - strayMargin || command.point.x > box.max.x + strayMargin ||
                   command.point.y < box.min.y - strayMargin || command.point.y > box.max.y + strayMargin {
                    let object = design.objects.first { $0.id == id }
                    note("A stitch lands more than \(strayMargin.formatted()) mm outside its shape", seed, "\(object?.stitchTitle ?? "?") at \(command.point)", design)
                }
            }

            // Remembered stitches are the same as fresh ones.
            StitchCache.shared.clear()
            if let fresh = try? StitchEngine.compile(design), fresh != plan {
                note("Remembered stitches differ from freshly worked-out ones", seed, "", design)
            }

            let seconds = Date().timeIntervalSince(started)
            if seconds > slowest.seconds { slowest = (seconds, seed) }
        }

        print("RandomDesigns: \(seeds.count) rounds, \(sewn) sewn, \(refused) refused with a reason; slowest round \(slowest.seed) took \(slowest.seconds.formatted(.number.precision(.fractionLength(2)))) s")
        for (reason, count) in refusals.sorted(by: { $0.value > $1.value }) { print("RandomDesigns refused \(count)×: \(reason)") }
        for (kind, finding) in findings.sorted(by: { $0.value.count > $1.value.count }) {
            let line = "\(kind): \(finding.count) rounds (seeds \(finding.seeds.map(String.init).joined(separator: ", "))). Example: \(finding.example)"
            print("RandomDesigns finding: \(line)")
            XCTFail(line)
        }
    }

    // MARK: - Making random designs

    /// One to three random objects (a closed shape with a fill or outline or both counts as one, grouped) in a hoop
    /// big enough that the hoop never gets in the way.
    private func randomDesign(_ r: inout SeededGenerator, name: String) -> Design {
        var design = Design(); design.hoop = Hoop(width: 400, height: 400)
        for index in 1...Int.random(in: 1...3, using: &r) {
            // A shape the app would refuse to make (say, a satin too wide for it) is simply left out.
            guard var made = try? randomObjects(&r, name: "\(name) shape \(index)") else { continue }
            for i in made.indices { randomize(&made[i], &r) }
            design.objects += made
        }
        return design
    }

    /// A closed shape, an open line or a basic shape, each with the stitches the shape tools offer.
    private func randomObjects(_ r: inout SeededGenerator, name: String) throws -> [RunObject] {
        let width = Double.random(in: 3...120, using: &r), height = width * Double.random(in: 0.3...1.5, using: &r)
        let center = Point(.random(in: -100...100, using: &r), .random(in: -100...100, using: &r))
        let box = (min: Point(center.x - width / 2, center.y - height / 2), max: Point(center.x + width / 2, center.y + height / 2))
        let satinWidth = Double.random(in: SatinLine.widths, using: &r)
        switch Int.random(in: 0..<10, using: &r) {
        case 0..<5:
            return try closedShape(randomOutline(&r, in: box), &r, satinWidth: satinWidth, name: name)
        case 5..<8:
            // An open line wandering across the box.
            let count = Int.random(in: 2...8, using: &r)
            let nodes = (0..<count).map { i -> PathNode in
                let x = box.min.x + (box.max.x - box.min.x) * Double(i) / Double(count - 1)
                return PathNode(Point(x, .random(in: box.min.y...box.max.y, using: &r)), smooth: Bool.random(using: &r))
            }
            return [try ShapeStitching.openShape(nodes, stitch: OpenShapeStitch.allCases.randomElement(using: &r)!, satinWidth: satinWidth, name: name, color: ink)]
        default:
            var shape = ShapeSettings()
            shape.polygonSides = Int.random(in: ShapeSettings.polygonSideRange, using: &r)
            shape.starPoints = Int.random(in: ShapeSettings.starPointRange, using: &r)
            shape.starInner = Double.random(in: ShapeSettings.starInnerRange, using: &r)
            shape.cornerRadius = Bool.random(using: &r) ? 0 : Double.random(in: ShapeSettings.cornerRadiusRange, using: &r)
            let nodes = ShapeGeometry.nodes(BasicShape.allCases.randomElement(using: &r)!, in: box, settings: shape)
            return try closedShape(nodes, &r, satinWidth: satinWidth, name: name)
        }
    }

    /// The Closed Shape tool's result with a random fill and outline (at least one of them).
    private func closedShape(_ nodes: [PathNode], _ r: inout SeededGenerator, satinWidth: Double, name: String) throws -> [RunObject] {
        let fill: FillStyle? = Bool.random(using: &r) || Bool.random(using: &r) ? FillStyle.allCases.randomElement(using: &r) : nil
        let outline: OpenShapeStitch? = fill == nil || Bool.random(using: &r) ? OpenShapeStitch.allCases.randomElement(using: &r) : nil
        return try ShapeStitching.closedShape(nodes, fill: fill, outline: outline, satinWidth: satinWidth, name: name, color: ink)
    }

    /// Corners around the middle of `box` at increasing angles, so the outline never crosses itself; some are curve
    /// nodes. One time in ten the corners are anywhere in the box instead, which may cross: the engine should say so.
    private func randomOutline(_ r: inout SeededGenerator, in box: (min: Point, max: Point)) -> [PathNode] {
        let middle = Point((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2)
        let half = Point((box.max.x - box.min.x) / 2, (box.max.y - box.min.y) / 2)
        let count = Int.random(in: 3...12, using: &r)
        if Int.random(in: 0..<10, using: &r) == 0 {
            return (0..<count).map { _ in PathNode(Point(.random(in: box.min.x...box.max.x, using: &r), .random(in: box.min.y...box.max.y, using: &r))) }
        }
        let angles = (0..<count).map { _ in Double.random(in: 0..<(2 * .pi), using: &r) }.sorted()
        return angles.map { angle in
            let reach = Double.random(in: 0.3...1, using: &r)
            return PathNode(Point(middle.x + cos(angle) * half.x * reach, middle.y + sin(angle) * half.y * reach), smooth: Int.random(in: 0..<10, using: &r) < 3)
        }
    }

    /// Random settings (within what Properties allows), node edits, a hole, and start and end points.
    private func randomize(_ object: inout RunObject, _ r: inout SeededGenerator) {
        let box = outlineBox(object)
        func anywhere(_ r: inout SeededGenerator, grow: Double = 0) -> Point {
            Point(.random(in: (box.min.x - grow)...(box.max.x + grow), using: &r), .random(in: (box.min.y - grow)...(box.max.y + grow), using: &r))
        }
        switch object.kind {
        case .fill:
            var s = object.settings
            s.spacing = .random(in: 0.25...1.2, using: &r); s.angle = .random(in: -180...180, using: &r)
            s.expansion = .random(in: 0...1, using: &r); s.underlay = [.none, .edge, .edgeAndSparse].randomElement(using: &r)!
            s.inset = .random(in: 0...1.5, using: &r); s.underlaySpacing = .random(in: 0.5...5, using: &r)
            s.waveHeight = .random(in: DigitizingSettings.waveHeightRange, using: &r); s.waveLength = .random(in: DigitizingSettings.waveLengthRange, using: &r)
            if Int.random(in: 0..<3, using: &r) == 0 { s.radialCenter = anywhere(&r) }
            if (s.fillStyle ?? .tatami) == .tatami, Int.random(in: 0..<3, using: &r) == 0 {
                s.angleLines = (0..<Int.random(in: 1...3, using: &r)).map { _ in [anywhere(&r), anywhere(&r)] }
            }
            if Int.random(in: 0..<3, using: &r) == 0 { s.cutOutOverlaps = true }
            if Bool.random(using: &r) { s.angleLineCenter = anywhere(&r) }
            object.digitizing = s
            object.stitchLength = .random(in: 1...7, using: &r)
            if Int.random(in: 0..<4, using: &r) == 0 {
                // A small hole near the middle.
                let middle = Point((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2)
                let size = min(box.max.x - box.min.x, box.max.y - box.min.y) * .random(in: 0.05...0.3, using: &r)
                object.holes = [[Point(-1, -1), Point(1, -1), Point(1, 1), Point(-1, 1)].map { PathNode(middle + $0 * size) }]
            }
        case .satin:
            var s = object.settings
            s.spacing = .random(in: 0.25...1, using: &r); s.expansion = .random(in: 0...1, using: &r)
            s.underlay = [.none, .center, .edge, .zigzag, .auto].randomElement(using: &r)!
            // The second underlay is set after the first, which clears it when it isn't allowed.
            if ![.none, .auto].contains(s.underlay), Bool.random(using: &r) {
                s.secondUnderlay = [UnderlayStyle.center, .edge, .zigzag].filter { $0 != s.underlay }.randomElement(using: &r)
            }
            s.inset = .random(in: 0...1.5, using: &r); s.underlaySpacing = .random(in: 0.5...5, using: &r)
            s.pullPercent = Bool.random(using: &r) ? .random(in: DigitizingSettings.pullPercentRange, using: &r) : nil
            s.maximumSatin = .random(in: 4...10, using: &r)
            s.shortStitches = Bool.random(using: &r); s.autoSplit = Int.random(in: 0..<4, using: &r) > 0
            object.digitizing = s
        case .run:
            object.stitchLength = .random(in: 0.5...6, using: &r)
            if Bool.random(using: &r) { object.digitizing = DigitizingSettings(kind: .run); object.digitizing?.runPasses = DigitizingSettings.runPassChoices.randomElement(using: &r) }
        case .vector, .raw: break
        }

        // Node edits, as in Edit Nodes: add a corner or curve node on an edge (not on satins, whose nodes come in
        // rung pairs), and drag a node up to 10 mm.
        for _ in 0..<Int.random(in: 0...3, using: &r) where object.nodes.count >= 2 {
            if object.kind != .satin, Bool.random(using: &r) {
                let segments = object.closed ? object.nodes.count : object.nodes.count - 1
                let i = Int.random(in: 0..<segments, using: &r), a = object.nodes[i].point, b = object.nodes[(i + 1) % object.nodes.count].point
                let near = (a + b) * 0.5 + Point(.random(in: -1...1, using: &r), .random(in: -1...1, using: &r))
                object.nodes = RunningEngine.insertingNode(object.nodes, closed: object.closed, segment: i, near: near, smooth: [true, false, nil].randomElement(using: &r)!).nodes
            } else {
                let i = Int.random(in: 0..<object.nodes.count, using: &r)
                let move = Point(.random(in: -10...10, using: &r), .random(in: -10...10, using: &r))
                object.nodes[i].transform { $0 + move }
            }
        }

        if Int.random(in: 0..<5, using: &r) == 0 { object.entry = anywhere(&r, grow: 5) }
        if Int.random(in: 0..<5, using: &r) == 0 { object.exit = anywhere(&r, grow: 5) }
        if Int.random(in: 0..<4, using: &r) == 0 { object.trimAfter = false }
    }

    // MARK: - Helpers

    /// The box around the object's outline as drawn (curves included, which can bulge past their nodes), its holes,
    /// and its nodes and handles.
    private func outlineBox(_ object: RunObject) -> (min: Point, max: Point) {
        let points = object.outlinePaths.flatMap { $0 } + object.allNodes.flatMap { [$0.point, $0.inHandle, $0.outHandle].compactMap { $0 } }
        guard let first = points.first else { return (Point(0, 0), Point(0, 0)) }
        return points.reduce((first, first)) { box, p in (Point(min(box.0.x, p.x), min(box.0.y, p.y)), Point(max(box.1.x, p.x), max(box.1.y, p.y))) }
    }

    /// The object in a few words, for a problem report: its stitch, size, and the settings that change its effort.
    private func describe(_ object: RunObject) -> String {
        let box = outlineBox(object), s = object.settings
        var words = "\(object.stitchTitle) \(Int(box.max.x - box.min.x))×\(Int(box.max.y - box.min.y)) mm, \(object.nodes.count) nodes"
        if object.kind != .run { words += ", spacing \(s.spacing.formatted(.number.precision(.fractionLength(2))))" }
        if object.kind == .fill { words += ", stitch \(object.stitchLength.formatted(.number.precision(.fractionLength(1)))) mm" }
        if !(s.angleLines ?? []).isEmpty { words += ", \(s.angleLines!.count) angle lines" }
        if s.cutOutOverlaps == true { words += ", cut-out" }
        if !(object.holes ?? []).isEmpty { words += ", hole" }
        return words
    }

    /// An engine message with object names and numbers taken out, so the same kind of problem groups together.
    private func pattern(_ message: String) -> String {
        message.replacingOccurrences(of: #"Round \d+ shape \d+( outline)?"#, with: "<shape>", options: .regularExpression)
            .replacingOccurrences(of: #"\d+(\.\d+)?"#, with: "#", options: .regularExpression)
    }
}
