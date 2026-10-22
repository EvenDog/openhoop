// Review Sewing Order: the design taken one step at a time, in the order it sews. Each step is an object (or a whole
// piece of lettering, which is one object to the person sewing it), with where its stitches begin and end and how
// the needle gets there from the step before: trimmed, jumped or stitched across, and whether the thread changes.
// Moves worth a second look (long ones, and jumps left untrimmed) are warned about.
import Foundation

/// One step of the sewing order, read from the stitch plan.
public struct SewingStep: Equatable, Sendable {
    /// The objects sewn in this step, in sewing order: one, or each letter of a piece of lettering.
    public var objects: [UUID]
    /// Its stitches' place in the plan's commands, from its first stitch to just past its last.
    public var commands: Range<Int>
    /// Where its first and last stitches go.
    public var start: Point
    public var end: Point
    public var stitches: Int
    /// How the needle gets here from the step before; nil for the first step.
    public var travel: SewingTravel?
}

/// The way from the end of one step to the start of the next.
public struct SewingTravel: Equatable, Sendable {
    /// Where the step before ended.
    public var from: Point
    /// How far it is, in mm, in a straight line.
    public var length: Double
    /// True when the thread is cut on the way.
    public var trimmed: Bool
    /// True when the machine moves without sewing (a jump) on the way.
    public var jumped: Bool
    /// True when the thread changes to another color.
    public var colorChange: Bool
    /// True when the machine stops on the way (Stop after on the step before).
    public var stopped: Bool
}

extension Design {
    /// The design's sewing steps, in the order `plan` sews them. Objects that sew no stitches have no step.
    public func sewingSteps(plan: StitchPlan) -> [SewingStep] {
        // Every letter of a piece of lettering belongs to the lettering's step.
        var stepKey: [UUID: UUID] = [:]
        for object in objects { stepKey[object.id] = object.lettering?.id ?? object.id }
        var steps: [SewingStep] = [], currentKey: UUID?
        for (index, command) in plan.commands.enumerated() where command.op == .stitch {
            guard let id = command.objectID else { continue }
            let key = stepKey[id] ?? id
            if key == currentKey, var step = steps.popLast() {
                if step.objects.last != id { step.objects.append(id) }
                step.commands = step.commands.lowerBound..<(index + 1)
                step.end = command.point; step.stitches += 1
                steps.append(step)
                continue
            }
            // A new step: what lies between the last step's final stitch and this first stitch is how it gets here.
            let travel = steps.last.map { previous in
                let between = plan.commands[previous.commands.upperBound..<index]
                return SewingTravel(from: previous.end, length: previous.end.distance(to: command.point),
                                    trimmed: between.contains { $0.op == .trim }, jumped: between.contains { $0.op == .jump },
                                    colorChange: between.contains { $0.op == .colorChange }, stopped: between.contains { $0.op == .stop })
            }
            steps.append(SewingStep(objects: [id], commands: index..<(index + 1), start: command.point, end: command.point, stitches: 1, travel: travel))
            currentKey = key
        }
        return steps
    }
}

/// Something about the move to a step that's worth a second look before sewing.
public enum SewingWarning: Equatable, Sendable {
    /// A jump this long (mm) with no trim: the thread is left lying across the fabric.
    case untrimmedJump(Double)
    /// A move this long (mm) in the same thread: time spent travelling, and a long tail to snip if the machine can't
    /// trim.
    case longMove(Double)
}

extension SewingTravel {
    /// Moves at least this long (mm) in the same thread are warned about. A starting guess, to be tuned against real
    /// sew-outs.
    public static let longMove = 15.0

    /// The warning this move is worth, if any. Nothing is worth one where the thread changes: the machine stops and
    /// starts afresh with the new thread anyway. Otherwise, a jump that isn't trimmed is warned about once it's as
    /// long as the design's trim distance (the length it trims jumps at), since trimming would have cut it, and any
    /// move of `longMove` or more.
    public func warning(trimDistance: Double) -> SewingWarning? {
        if colorChange { return nil }
        if jumped && !trimmed && length >= trimDistance { return .untrimmedJump(length) }
        if length >= Self.longMove { return .longMove(length) }
        return nil
    }
}

extension Design {
    /// The warnings for `steps` (from `sewingSteps`), by step index; steps without one aren't listed.
    public func sewingWarnings(_ steps: [SewingStep]) -> [Int: SewingWarning] {
        let trimDistance = self.trimDistance ?? Design.defaultTrimDistance
        var warnings: [Int: SewingWarning] = [:]
        for (index, step) in steps.enumerated() { if let warning = step.travel?.warning(trimDistance: trimDistance) { warnings[index] = warning } }
        return warnings
    }
}
