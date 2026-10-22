// Stepping the stitch player from the keyboard, as other embroidery software does: a stitch or ten at a time, on to
// the end, or to the next (or back to the previous) color, object or trim. A position is how many of the plan's
// commands are shown, from 0 (none) to all of them, which is how the canvas draws a paused player.
import Foundation

/// One step of the stitch player.
public enum StitchStep: Equatable, Sendable {
    /// Forward (above 0) or back (below 0) by this many stitches.
    case stitches(Int)
    /// To the start of the next color, or back to the start of this one (or the one before, from its start).
    case color(forward: Bool)
    /// The same, by object.
    case object(forward: Bool)
    /// Just past the next trim, or back to just past the one before.
    case trim(forward: Bool)
    /// To the last stitch.
    case end
}

extension StitchPlan {
    /// Where the player lands after `step` from `shown` commands shown, as a count of commands to show.
    public func position(after step: StitchStep, from shown: Int) -> Int {
        let total = commands.count, start = min(max(shown, 0), total)
        switch step {
        case .end:
            return total
        case .stitches(let count):
            // Count stitches only: jumps, trims and color changes on the way go past without using up the step.
            var position = start, left = abs(count)
            if count > 0 {
                while position < total && left > 0 { if commands[position].op == .stitch { left -= 1 }; position += 1 }
            } else {
                while position > 0 && left > 0 { position -= 1; if commands[position].op == .stitch { left -= 1 } }
            }
            return position
        case .color(let forward):
            return jump(forward, from: start, to: runStarts { $0.thread != $1.thread })
        case .object(let forward):
            return jump(forward, from: start, to: runStarts { $0.objectID != $1.objectID })
        case .trim(let forward):
            return jump(forward, from: start, to: commands.indices.filter { commands[$0].op == .trim }.map { $0 + 1 })
        }
    }

    /// The positions where a new run of stitches starts: the index of each stitch that `differs` from the stitch
    /// before it (so showing that many commands shows everything before the run and none of it).
    private func runStarts(_ differs: (StitchCommand, StitchCommand) -> Bool) -> [Int] {
        var starts: [Int] = [], previous: StitchCommand?
        for (index, command) in commands.enumerated() where command.op == .stitch {
            if let previous, differs(previous, command) { starts.append(index) }
            previous = command
        }
        return starts
    }

    /// The first of `marks` after `start` going forward (or the end), or the last one before it going back (or 0).
    private func jump(_ forward: Bool, from start: Int, to marks: [Int]) -> Int {
        forward ? marks.first { $0 > start } ?? commands.count : marks.last { $0 < start } ?? 0
    }
}
