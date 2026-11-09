// Make Redwork: the selected running lines turned into redwork, one continuous bean-stitch line for each set of
// lines that touch. The route is the one Line Art uses (LineArt.joined): it goes back over a line already sewn
// where it has to, instead of trimming, and those retraced stretches are sewn once (`retraceOnce`), so they come
// out nearly as bold as the rest. Only lines that don't touch any other need a jump between them.
import Foundation

extension Design {
    /// Whether `redwork` would accept `ids`: two or more plain running lines (open or closed), none of them locked,
    /// lettering, a monogram, a guide line or imported stitches. Properties offers Redwork only then.
    public func canMakeRedwork(_ ids: Set<UUID>) -> Bool {
        let chosen = objects.filter { ids.contains($0.id) }
        return chosen.count >= 2 && chosen.allSatisfy(\.canBeRedwork)
    }

    /// Replaces the lines in `ids` with redwork lines: one per set of touching lines, sewn as bean stitch (at least
    /// 3 passes) with retraced stretches sewn once. They take the place in the sewing order, color and settings of
    /// the line sewn first, and are grouped when there are more than one. Returns their IDs in sewing order. Throws,
    /// changing nothing, when fewer than two lines are selected or any can't be used.
    public mutating func redwork(_ ids: Set<UUID>) throws -> [UUID] {
        let chosen = objects.filter { ids.contains($0.id) }
        guard chosen.count >= 2 else { throw DesignError.invalid("Select two or more running lines to make into redwork.") }
        guard chosen.allSatisfy(\.canBeRedwork) else {
            throw DesignError.invalid("Only plain running lines can be made into redwork: not fills, satins, line styles, lettering, monograms, guide lines or locked objects.")
        }
        // Each line as the points it's sewn along, in mm. A closed line ends back where it started.
        let strokes = chosen.map { line -> [Point] in
            let segments = RunningEngine.flatten(line.nodes, closed: line.closed)
            return segments.enumerated().flatMap { index, segment in index == 0 ? segment : Array(segment.dropFirst()) }
        }
        // Lines closer than half a millimeter count as touching (a line drawn to end on another rarely lands exactly).
        let routes = LineArt.ordered(LineArt.joined(strokes, tolerance: 0.5))
        let first = chosen[0], group = routes.count > 1 ? UUID() : first.groupID
        let made = routes.enumerated().map { index, route -> RunObject in
            let closed = route.count > 2 && route[0].distance(to: route[route.count - 1]) < 1e-6
            var line = first
            line.id = UUID()
            line.name = routes.count == 1 ? "Redwork" : "Redwork \(index + 1)"
            line.nodes = LineArt.nodes(closed ? Array(route.dropLast()) : route, closed: closed)
            line.closed = closed
            // Its start and end points, and any stitch edits, were for the first line's old shape.
            line.entry = nil; line.exit = nil; line.stitchEdits = nil
            var settings = first.settings
            settings.runPasses = max(3, settings.runPasses ?? 1)
            settings.retraceOnce = true
            line.digitizing = settings
            line.groupID = group
            return line
        }
        guard let index = objects.firstIndex(where: { $0.id == first.id }) else { return [] }
        objects.replaceSubrange(index...index, with: made)
        let others = Set(chosen.dropFirst().map(\.id))
        objects.removeAll { others.contains($0.id) }
        return made.map(\.id)
    }
}

extension RunObject {
    /// A plain running line (any number of passes) that's free to change: not a line style, lettering, a monogram,
    /// a guide line, imported stitches or locked.
    var canBeRedwork: Bool {
        kind == .run && nodes.count >= 2 && (settings.runStyle ?? .running) == .running
            && !locked && rawStitches == nil && lettering == nil && monogram == nil && guideFor == nil
    }
}
