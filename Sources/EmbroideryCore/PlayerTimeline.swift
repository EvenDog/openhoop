// What the stitch player's timeline shows: the design's thread colors as blocks along it, where each object starts,
// and where the machine trims or stops. Positions count the plan's commands (0 is none shown, the plan's length is
// all of them), the same way the player and its Next Color / Next Object steps (StitchStepping.swift) measure.
import Foundation

/// The stitch player's timeline for one stitch plan.
public struct PlayerTimeline: Equatable, Sendable {
    /// One stretch of the timeline, from position `start` up to (not including) `end`: one color, or one object.
    public struct Run: Equatable, Sendable {
        public var start: Int
        public var end: Int
        /// The plan thread (an index into `StitchPlan.threads`) its stitches are sewn in.
        public var thread: Int
        public var objectID: UUID?
    }
    /// How many commands the plan has: the timeline's whole length.
    public var length = 0
    /// One run per color, in sewing order. A thread used twice with another between gives two runs, since the
    /// machine changes thread twice. The first run starts at 0 and the last ends at `length`, so they cover it all.
    public var colors: [Run] = []
    /// One run per object, in sewing order, covering the timeline the same way.
    public var objects: [Run] = []
    /// The position just past each trim and each stop, up to the last stitch (a trim after it isn't a pause).
    public var trims: [Int] = []
    public var stops: [Int] = []
    public init() {}

    /// Which of `runs` the player is in with `position` commands shown: the run holding the next command to sew
    /// (the last run at the end). Nil only when there are no runs.
    public static func index(at position: Int, in runs: [Run]) -> Int? {
        guard !runs.isEmpty else { return nil }
        let next = min(max(position, 0), runs[runs.count - 1].end - 1)
        return runs.firstIndex { $0.start <= next && next < $0.end } ?? runs.count - 1
    }
}

extension StitchPlan {
    /// The player's timeline: a new color run wherever a stitch's thread differs from the stitch before it, and a new
    /// object run wherever its object does (as Next Color and Next Object step), plus the trims and stops.
    public var timeline: PlayerTimeline {
        var timeline = PlayerTimeline()
        timeline.length = commands.count
        guard let lastStitch = commands.lastIndex(where: { $0.op == .stitch }) else { return timeline }
        var previous: StitchCommand?
        for (index, command) in commands.enumerated() {
            switch command.op {
            case .trim where index < lastStitch: timeline.trims.append(index + 1)
            case .stop where index < lastStitch: timeline.stops.append(index + 1)
            case .stitch:
                if let previous {
                    // The run before ends where this one starts.
                    if previous.thread != command.thread {
                        timeline.colors[timeline.colors.count - 1].end = index
                        timeline.colors.append(.init(start: index, end: commands.count, thread: command.thread, objectID: command.objectID))
                    }
                    if previous.objectID != command.objectID {
                        timeline.objects[timeline.objects.count - 1].end = index
                        timeline.objects.append(.init(start: index, end: commands.count, thread: command.thread, objectID: command.objectID))
                    }
                } else {
                    // The first runs start at 0, so the jumps before the first stitch belong to them.
                    timeline.colors.append(.init(start: 0, end: commands.count, thread: command.thread, objectID: command.objectID))
                    timeline.objects.append(.init(start: 0, end: commands.count, thread: command.thread, objectID: command.objectID))
                }
                previous = command
            default: break
            }
        }
        return timeline
    }
}
