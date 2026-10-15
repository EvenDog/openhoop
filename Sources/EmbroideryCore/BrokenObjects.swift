// When one object can't be sewn (say, a satin rung crossing a rail), the whole design can't be exported, but the
// rest of it can still be shown with up-to-date stitches. This finds the objects that can't be sewn, and quickly
// checks whether a shape can be sewn at all (used when a node drag ends).
import Foundation

extension StitchEngine {
    /// For the screen when `compile` fails: the stitches of every object that can be sewn, and the objects that
    /// can't, by id, with why. Throws when no single object is to blame (such as a design that's too big).
    public static func compileSkippingBroken(_ design: Design) throws -> (plan: StitchPlan, broken: [UUID: String]) {
        var broken: [UUID: String] = [:]
        for (index, object) in design.objects.enumerated() where object.rawStitches == nil && object.kind != .vector {
            if object.stitchEdits != nil && object.hasCurrentStitchEdits { continue }   // hand-edited stitches sew as they are
            let later = Array(design.objects[(index + 1)...])
            do { _ = try StitchCache.shared.stitches(for: object, under: later) { try fresh(object, under: later) } }
            catch is CancellationError { throw CancellationError() }
            catch { broken[object.id] = "\(object.name): \(error.localizedDescription)" }
        }
        guard !broken.isEmpty else { return (try compile(design), [:]) }
        var rest = design; rest.objects.removeAll { broken[$0.id] != nil }
        return (try compile(rest), broken)
    }

    /// Why `object`'s shape can't be sewn, or nil if it can. Quick enough to run when a drag ends: satins are worked
    /// out in full (crossed rungs show up there); fills have their outline and holes checked for crossings.
    public static func shapeProblem(_ object: RunObject) -> String? {
        do {
            switch object.kind {
            case .satin: _ = try AreaEngine.satin(object.sewingOrder())
            case .fill: try AreaGeometry.validate(([object.nodes] + (object.holes ?? [])).map { AreaGeometry.ring($0) })
            case .run, .raw, .vector: break
            }
            return nil
        } catch { return error.localizedDescription }
    }
}
