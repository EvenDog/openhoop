// Join Lines: open running lines (or open satin columns) joined end to end into one object. Starting from the one
// sewn first, the nearest free end of another line is joined on, at whichever end of the growing line it's nearest,
// turning that line round if needed. Ends that touch become one point; a gap is bridged, by a straight stretch of
// line, or by the column carrying on across it.
import Foundation

extension Design {
    /// Joins the objects in `ids` into the one sewn first, which keeps its settings, color, name and place in the
    /// sewing order; the others are removed. Returns its ID. Throws, changing nothing, when fewer than two are
    /// selected, when any can't be joined (closed shapes, fills, lettering, monograms, guide lines, imported stitches
    /// or locked objects), or when lines and satin columns are mixed.
    /// Whether `joinLines` would accept `ids`: two or more open lines, or two or more open satin columns (not both),
    /// none of them locked or otherwise unjoinable. Properties offers Join lines only then.
    public func canJoinLines(_ ids: Set<UUID>) -> Bool {
        let chosen = objects.filter { ids.contains($0.id) }
        guard chosen.count >= 2, chosen.allSatisfy(\.canContinueDrawing) else { return false }
        return Set(chosen.map { $0.kind == .satin }).count == 1
    }
    public mutating func joinLines(_ ids: Set<UUID>) throws -> UUID {
        let chosen = objects.filter { ids.contains($0.id) }
        guard chosen.count >= 2 else { throw DesignError.invalid("Select two or more lines, or two or more satin columns, to join.") }
        guard chosen.allSatisfy(\.canContinueDrawing) else {
            throw DesignError.invalid("Only open running lines and satin columns can be joined: not closed shapes, fills, lettering, monograms, guide lines or locked objects.")
        }
        let satin = chosen[0].kind == .satin
        guard chosen.allSatisfy({ ($0.kind == .satin) == satin }) else { throw DesignError.invalid("Join lines with lines, or satin columns with satin columns, not both at once.") }

        /// Where a path starts and ends: a line's first and last points, or the middle of a column's first and last
        /// edge pairs.
        func ends(_ nodes: [PathNode]) -> (start: Point, end: Point) {
            guard satin else { return (nodes[0].point, nodes[nodes.count - 1].point) }
            let n = nodes.count
            return ((nodes[0].point + nodes[1].point) * 0.5, (nodes[n - 2].point + nodes[n - 1].point) * 0.5)
        }
        let touching = 0.1, pair = satin ? 2 : 1   // ends closer than 0.1 mm count as the same point
        var joined = chosen[0].nodes
        var rest = Array(chosen.dropFirst())
        while !rest.isEmpty {
            let chain = ends(joined)
            // The nearest of: a line's start or end to the joined line's end (joined after it), or to its start
            // (joined before it). `reverse` turns the line round so it runs the same way as the joined line.
            var best = (index: 0, after: true, reverse: false, distance: Double.infinity)
            for (index, line) in rest.enumerated() {
                let own = ends(line.nodes)
                for (after, reverse, distance) in [(true, false, chain.end.distance(to: own.start)), (true, true, chain.end.distance(to: own.end)),
                                                   (false, false, chain.start.distance(to: own.end)), (false, true, chain.start.distance(to: own.start))]
                where distance < best.distance { best = (index, after, reverse, distance) }
            }
            var next = rest.remove(at: best.index).nodes
            if best.reverse { next = RunObject.reversedPath(next, satin: satin) }
            if best.after {
                if best.distance < touching { next.removeFirst(pair) }
                joined += next
            } else {
                if best.distance < touching { next.removeLast(pair) }
                joined = next + joined
            }
        }
        let first = chosen[0].id, others = Set(chosen.dropFirst().map(\.id))
        guard let index = objects.firstIndex(where: { $0.id == first }) else { return first }
        // Its start and end points, and any stitch edits, were for the shorter line.
        objects[index].nodes = joined; objects[index].entry = nil; objects[index].exit = nil; objects[index].stitchEdits = nil
        objects.removeAll { others.contains($0.id) }
        return first
    }
}
