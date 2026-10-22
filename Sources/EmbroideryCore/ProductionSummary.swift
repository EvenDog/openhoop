// The numbers on a production worksheet: the design's finished size, its stitch, trim and stop counts, the
// thread steps in sewing order, and an estimate of how long it takes to sew. Everything is read from the
// compiled stitch plan, so the worksheet always matches what the machine file would sew.
import Foundation

public struct ProductionSummary: Equatable, Sendable {
    /// One stretch of sewing with a single thread: the machine sews it without stopping. A step ends at a thread
    /// change or at a stop (a stop pauses the machine, for example to lay appliqué fabric, then carries on).
    public struct Step: Equatable, Sendable {
        public var number: Int
        public var color: ThreadColor
        public var stitches: Int
        /// What sews in this step, in sewing order: object names, with each piece of lettering listed once.
        public var parts: [String]
        /// True if the machine stops after this step without changing thread.
        public var stopAfter: Bool
        public init(number: Int, color: ThreadColor, stitches: Int, parts: [String], stopAfter: Bool) {
            self.number = number; self.color = color; self.stitches = stitches; self.parts = parts; self.stopAfter = stopAfter
        }
    }

    public var steps: [Step] = []
    public var stitchCount = 0
    public var trims = 0
    public var stops = 0
    public var threadChanges = 0
    /// The stitched area's size in mm (jumps don't count; they leave no thread).
    public var width = 0.0
    public var height = 0.0
    public var warnings: [String] = []
    /// What the design is sewn on; the worksheet names it and its stabilizer.
    public var fabric: FabricType = .woven

    /// Machine speeds the worksheet accepts, in stitches per minute, and the one it starts with.
    public static let speeds = 100...1500, defaultSpeed = 600
    /// Rough allowances for the time the machine isn't stitching: cutting the thread, and the pause while someone
    /// changes thread or does whatever a stop is for.
    public static let secondsPerTrim = 5.0, secondsPerThreadChange = 60.0, secondsPerStop = 60.0

    /// Reads the summary from `plan` (compiled from `design`, whose object names label the steps).
    public init(plan: StitchPlan, design: Design) {
        stitchCount = plan.stitchCount
        trims = plan.commands.filter { $0.op == .trim }.count
        stops = plan.commands.filter { $0.op == .stop }.count
        threadChanges = plan.commands.filter { $0.op == .colorChange }.count
        fabric = design.fabric
        // The first note says what to hoop: the stabilizer (and topping) for this fabric.
        warnings = ["Fabric: \(fabric.title) (\(fabric.examples)). \(fabric.stabilizer)"] + plan.warnings

        let objects = Dictionary(design.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        /// How an object is listed: lettering by its text (once for all its letters), anything else by its name.
        func part(_ id: UUID?) -> String? {
            if let id, Design.isAlignmentMark(id) { return "Alignment marks" }   // a multi-hooped design's (MultiHooping.swift)
            guard let id, let object = objects[id] else { return nil }
            if let lettering = object.lettering { return "Lettering “\(lettering.lines.joined(separator: " / "))”" }
            return object.name
        }
        // Walk the plan: a thread change or stop closes the current step; the next stitch opens a new one.
        var stepEnded = true
        var low = Point(.infinity, .infinity), high = Point(-.infinity, -.infinity)
        for command in plan.commands {
            switch command.op {
            case .colorChange: stepEnded = true
            case .stop: if !steps.isEmpty && !stepEnded { steps[steps.count - 1].stopAfter = true }; stepEnded = true
            case .stitch:
                if stepEnded {
                    let color = plan.threads.indices.contains(command.thread) ? plan.threads[command.thread] : ThreadColor("Unknown", 0x808080)
                    steps.append(Step(number: steps.count + 1, color: color, stitches: 0, parts: [], stopAfter: false))
                    stepEnded = false
                }
                steps[steps.count - 1].stitches += 1
                if let name = part(command.objectID), !steps[steps.count - 1].parts.contains(name) {
                    steps[steps.count - 1].parts.append(name)
                }
                low = Point(min(low.x, command.point.x), min(low.y, command.point.y))
                high = Point(max(high.x, command.point.x), max(high.y, command.point.y))
            default: break
            }
        }
        if stitchCount > 0 { width = high.x - low.x; height = high.y - low.y }
    }

    /// Estimated sewing time in minutes at `speed` stitches per minute, including the allowances above.
    public func sewingMinutes(speed: Int) -> Double {
        let pauses = Double(trims) * Self.secondsPerTrim + Double(threadChanges) * Self.secondsPerThreadChange + Double(stops) * Self.secondsPerStop
        return Double(stitchCount) / Double(max(1, speed)) + pauses / 60
    }

    /// A time in minutes written for people: "under 1 min", "12 min" or "1 h 05 min".
    public static func duration(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        if rounded < 1 { return "under 1 min" }
        return rounded < 60 ? "\(rounded) min" : String(format: "%d h %02d min", rounded / 60, rounded % 60)
    }
}

extension StitchPlan {
    /// How many stitches each object sews, by object ID (for the Pro view's sewing-order table).
    public var stitchCountsByObject: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for command in commands where command.op == .stitch { if let id = command.objectID { counts[id, default: 0] += 1 } }
        return counts
    }
}
