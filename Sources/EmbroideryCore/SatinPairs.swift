// Untangling hand-drawn satin columns. A satin column is drawn as edge pairs, left point then right point; a pair
// clicked right-then-left twists the column there, and the satin engine refuses it ("Satin rungs cross or reverse").
// This finds such pairs and swaps them back.

import Foundation

public enum SatinPairs {
    /// `nodes` (left, right, left, right…) with every pair that faces the other way from the rest of the column
    /// swapped, or nil when none does. A pair "faces" one way or the other by which side of the column's direction
    /// its left point is on (measured from the pair before it to the pair after it); the side most pairs agree on
    /// counts as left, so a wrong first pair is the one swapped, and a column drawn right-then-left all the way is
    /// left alone. Pairs lying almost along the column (no clear side) count either way. Each point keeps its own
    /// curve handles. `closed` columns (borders) wrap round, the last pair's next being the first.
    public static func untangled(_ nodes: [PathNode], closed: Bool) -> [PathNode]? {
        guard nodes.count >= 4, nodes.count % 2 == 0 else { return nil }
        let count = nodes.count / 2
        let middles = (0..<count).map { (nodes[2 * $0].point + nodes[2 * $0 + 1].point) * 0.5 }
        // Which way each pair faces: +1, -1, or 0 when its rung lies along the column.
        let facing: [Int] = (0..<count).map { i in
            let before = i > 0 ? i - 1 : closed ? count - 1 : i, after = i < count - 1 ? i + 1 : closed ? 0 : i
            let along = middles[after] - middles[before], rung = nodes[2 * i + 1].point - nodes[2 * i].point
            let side = AreaGeometry.cross(along, rung), size = hypot(along.x, along.y) * hypot(rung.x, rung.y)
            return size > 1e-9 && abs(side) > 0.1 * size ? (side > 0 ? 1 : -1) : 0
        }
        let majority = facing.reduce(0, +) >= 0 ? 1 : -1
        let wrong = (0..<count).filter { facing[$0] == -majority }
        guard !wrong.isEmpty, wrong.count < count else { return nil }
        var result = nodes
        for i in wrong { result.swapAt(2 * i, 2 * i + 1) }
        return result
    }

    /// `object` untangled, for a hand-drawn satin column the satin engine refuses as it is but sews with its
    /// wrong-way pairs swapped (see `untangled`); nil otherwise. Columns that already sew are never touched, so an
    /// unusual column the facing test misjudges (a tight turn with few pairs) stays as drawn. Satins from embroidery
    /// fonts fan and overlap their stitches on purpose and are left alone.
    public static func untangle(_ object: RunObject) -> RunObject? {
        guard object.kind == .satin, object.settings.relaxedChecks != true, let nodes = untangled(object.nodes, closed: object.closed),
              (try? AreaEngine.satin(object)) == nil else { return nil }
        var fixed = object; fixed.nodes = nodes
        return (try? AreaEngine.satin(fixed)) != nil ? fixed : nil
    }
    /// True for a satin column `untangle` would fix.
    public static func isTangled(_ object: RunObject) -> Bool { untangle(object) != nil }
}
