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
    /// out in full (crossed rungs show up there). Working out a whole fill can take seconds, so fills get the quick
    /// checks the fill engine makes before laying rows: the outline and holes don't cross, stitch angle lines still
    /// cross the shape, and a contour fill has room for its first ring. (Rarer problems still show up afterwards, as
    /// a red outline.)
    public static func shapeProblem(_ object: RunObject) -> String? {
        do {
            switch object.kind {
            case .satin: _ = try AreaEngine.satin(object.sewingOrder())
            case .fill:
                let rings = ([object.nodes] + (object.holes ?? [])).map { AreaGeometry.ring($0) }
                try AreaGeometry.validate(rings)
                // The region the fill engine lays rows in (AreaEngine.fill): the outline grown by the expansion.
                let s = object.settings, expanded = try AreaGeometry.offset(rings, by: s.expansion)
                let style = s.fillStyle ?? .tatami
                if style == .tatami, let lines = s.angleLines, !lines.isEmpty, TurningFill.chords(in: expanded, angleLines: lines).isEmpty {
                    throw DesignError.invalid("The stitch angle lines don't cross this fill. Draw them across it, or remove them.")
                }
                // A contour fill's first ring is the shape shrunk by half the row spacing; if nothing is left, there are no rings.
                if style == .contour, try AreaGeometry.offset(expanded, by: -s.spacing / 2).isEmpty {
                    throw DesignError.invalid("This fill is too small for the selected row spacing.")
                }
            case .run, .raw, .vector: break
            }
            return nil
        } catch { return error.localizedDescription }
    }
}
