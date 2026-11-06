// Continue drawing: picking up a finished open line or satin column at either end, so more points or edge pairs can
// be added past it. Its points become the drawing in progress, facing out of the end that was picked; finishing turns
// them back, so the object keeps the way it runs. Closed outlines (fills, closed lines) are picked up at any of their
// points instead, and new points go in after it.
import Foundation

extension RunObject {
    /// True for objects the Running and Satin tools can carry on: open running lines and open satin columns (not
    /// lettering, monograms, guide lines, imported stitches or locked objects).
    public var canContinueDrawing: Bool {
        !closed && !locked && rawStitches == nil && lettering == nil && monogram == nil && guideFor == nil
            && ((kind == .run && nodes.count >= 2) || (kind == .satin && nodes.count >= 4 && nodes.count % 2 == 0))
    }

    /// The points that pick it up at its start and at its end: a line's first or last point, or either point of a
    /// column's first or last edge pair.
    public var continueHandles: (start: [Point], end: [Point]) {
        let points = nodes.map(\.point)
        guard kind == .satin, points.count >= 4 else { return (Array(points.prefix(1)), Array(points.suffix(1))) }
        return (Array(points.prefix(2)), Array(points.suffix(2)))
    }

    /// `nodes` turned to run the other way: a line's points in reverse, or a column's edge pairs in reverse, each pair
    /// keeping its left/right order so the rails stay on the same sides. Curve handles swap with the direction. Doing
    /// it twice gives the nodes back.
    public static func reversedPath(_ nodes: [PathNode], satin: Bool) -> [PathNode] {
        guard satin else { return nodes.reversed().map(\.reversedDirection) }
        return stride(from: nodes.count - 2, through: 0, by: -2).flatMap { [nodes[$0].reversedDirection, nodes[$0 + 1].reversedDirection] }
    }

    /// True for closed outlines the Fill and Closed Shape tools can draw more points into: fills of any style and
    /// closed running lines (not satin borders, lettering, monograms, guide lines, imported stitches or locked objects).
    public var canDrawInto: Bool {
        closed && !locked && rawStitches == nil && lettering == nil && monogram == nil && guideFor == nil
            && kind != .satin && nodes.count >= 3
    }

    /// The outline as a drawing in progress that carries on from point `index`: the points after it, then the points
    /// up to and including it. New clicks land at the end, between that point and the next one, and the closed
    /// drawing joins the last of them back to the next one.
    public func drawing(continuingAfter index: Int) -> [PathNode] {
        Array(nodes[(index + 1)...] + nodes[...index])
    }

    /// A drawing made with `drawing(continuingAfter:)`, new points and all, back in the outline's own order, so its
    /// first point stays first. `leading` is how many points the drawing started with that came after the picked one.
    public static func outline(fromDrawing drawing: [PathNode], leading: Int) -> [PathNode] {
        // Deleting points while drawing can eat into the old ones; then there's no order left to restore.
        guard leading > 0, drawing.count > leading else { return drawing }
        return Array(drawing[leading...] + drawing[..<leading])
    }
}
