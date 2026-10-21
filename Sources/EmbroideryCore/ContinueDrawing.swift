// Continue drawing: picking up a finished open line or satin column at either end, so more points or edge pairs can
// be added past it. Its points become the drawing in progress, facing out of the end that was picked; finishing turns
// them back, so the object keeps the way it runs.
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
}
