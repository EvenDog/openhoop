// Running stitch generation is deterministic and independent of the user interface.
// Curves are flattened adaptively, while original corner nodes remain needle positions.
import Foundation

public enum RunningEngine {
    public static func flatten(_ nodes: [PathNode], closed: Bool = false) -> [[Point]] {
        guard nodes.count >= 2 else { return [] }
        let count = nodes.count
        var segments: [[Point]] = []
        for i in 0..<(closed ? count : count - 1) {
            let (start, c1, c2, end) = controls(nodes, closed: closed, segment: i)
            var points = [start]
            subdivide(start, c1, c2, end, depth: 0, into: &points)
            segments.append(points)
        }
        return segments
    }

    /// The four Bézier control points of the segment from node `i` to the next node.
    /// Explicit handles win; otherwise a smooth node uses its automatic handle and a corner gives a straight line.
    public static func controls(_ nodes: [PathNode], closed: Bool, segment i: Int) -> (Point, Point, Point, Point) {
        let j = (i + 1) % nodes.count, a = nodes[i], b = nodes[j]
        let c1 = a.outHandle ?? (a.smooth ? automaticHandles(nodes, closed: closed, index: i).outgoing : a.point + (b.point - a.point) * (1.0 / 3))
        let c2 = b.inHandle ?? (b.smooth ? automaticHandles(nodes, closed: closed, index: j).incoming : b.point - (b.point - a.point) * (1.0 / 3))
        return (a.point, c1, c2, b.point)
    }

    /// A point on a cubic Bézier curve, `t` running from 0 (start) to 1 (end).
    public static func bezierPoint(_ a: Point, _ b: Point, _ c: Point, _ d: Point, _ t: Double) -> Point {
        let u = 1 - t
        return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
    }
    /// Splits a cubic Bézier curve at `t` into two curves that together trace exactly the same shape
    /// (de Casteljau's method: repeatedly take the point `t` of the way along each control-polygon edge).
    public static func split(_ a: Point, _ b: Point, _ c: Point, _ d: Point, at t: Double) -> (left: (Point, Point, Point, Point), right: (Point, Point, Point, Point)) {
        func lerp(_ p: Point, _ q: Point) -> Point { p + (q - p) * t }
        let ab = lerp(a, b), bc = lerp(b, c), cd = lerp(c, d), abc = lerp(ab, bc), bcd = lerp(bc, cd), mid = lerp(abc, bcd)
        return ((a, ab, abc, mid), (mid, bcd, cd, d))
    }
    /// The same path with every node's handles written out explicitly (including straight lines and automatic
    /// smooth curves), so nodes can be inserted or reordered without changing the shape.
    public static func withExplicitHandles(_ nodes: [PathNode], closed: Bool) -> [PathNode] {
        var result = nodes
        guard nodes.count >= 2 else { return result }
        for i in 0..<(closed ? nodes.count : nodes.count - 1) {
            let (_, c1, c2, _) = controls(nodes, closed: closed, segment: i)
            result[i].outHandle = c1; result[(i + 1) % nodes.count].inHandle = c2
        }
        return result
    }

    /// Inserts a node on segment `i` at the point nearest `p`, keeping the path's shape. Straight segments get a
    /// plain corner node; on curves the two neighboring nodes have their handles written out (so their other
    /// curves don't shift) and the curve is split exactly. Returns the new node list and the new node's index.
    public static func insertingNode(_ nodes: [PathNode], closed: Bool, segment i: Int, near p: Point) -> (nodes: [PathNode], index: Int) {
        let j = (i + 1) % nodes.count
        let (a, b, c, d) = controls(nodes, closed: closed, segment: i)
        var best = (t: 0.5, distance: Double.infinity)
        for step in 1..<64 { let t = Double(step) / 64, distance = bezierPoint(a, b, c, d, t).distance(to: p); if distance < best.distance { best = (t, distance) } }
        // Then narrow in around the best of those, halving the step each time, so the node lands on the curve right
        // at the point (a knife cut needs it exact, not just the nearest of 64 places).
        var step = 1.0 / 64
        for _ in 0..<24 {
            step /= 2
            for t in [best.t - step, best.t + step] where t > 0 && t < 1 {
                let distance = bezierPoint(a, b, c, d, t).distance(to: p); if distance < best.distance { best = (t, distance) }
            }
        }
        var result = nodes
        let curved = nodes[i].smooth || nodes[i].hasHandles || nodes[j].smooth || nodes[j].hasHandles
        guard curved else { result.insert(PathNode(bezierPoint(a, b, c, d, best.t)), at: i + 1); return (result, i + 1) }
        // Fix both neighbors' handles at their current positions before the node list changes.
        let explicit = withExplicitHandles(nodes, closed: closed)
        for k in [i, j] where nodes[k].smooth || nodes[k].hasHandles { result[k].inHandle = explicit[k].inHandle; result[k].outHandle = explicit[k].outHandle }
        let (left, right) = split(a, b, c, d, at: best.t)
        result[i].outHandle = left.1; result[j].inHandle = right.2
        result.insert(PathNode(left.3, smooth: true, inHandle: left.2, outHandle: right.1), at: i + 1)
        return (result, i + 1)
    }

    /// `insertingNode`, with the new node made a corner (`smooth` false: no handles, so the outline comes to a point
    /// there) or a curve node (`smooth` true: on a straight edge nothing bends until the node is dragged, then the
    /// edge curves smoothly through it). Nil keeps what `insertingNode` makes.
    public static func insertingNode(_ nodes: [PathNode], closed: Bool, segment i: Int, near p: Point, smooth: Bool?) -> (nodes: [PathNode], index: Int) {
        var (result, index) = insertingNode(nodes, closed: closed, segment: i, near: p)
        if smooth == true { result[index].smooth = true }
        if smooth == false { result[index].smooth = false; result[index].inHandle = nil; result[index].outHandle = nil }
        return (result, index)
    }

    /// The handles a smooth node gets when none are set: parallel to the line joining its two neighbors,
    /// one sixth of that line's length on each side. Dragging a handle in the editor starts from these.
    public static func automaticHandles(_ nodes: [PathNode], closed: Bool, index i: Int) -> (incoming: Point, outgoing: Point) {
        let count = nodes.count
        let prev = nodes[i == 0 ? (closed ? count - 1 : 0) : i - 1].point
        let next = nodes[i + 1 < count ? i + 1 : (closed ? 0 : i)].point
        let tangent = (next - prev) * (1.0 / 6)
        return (nodes[i].point - tangent, nodes[i].point + tangent)
    }

    private static func subdivide(_ a: Point, _ b: Point, _ c: Point, _ d: Point, depth: Int, into points: inout [Point]) {
        let chord = a.distance(to: d)
        let polygon = a.distance(to: b) + b.distance(to: c) + c.distance(to: d)
        let deviation: Double
        if chord < 1e-9 { deviation = max(a.distance(to: b), a.distance(to: c)) }
        else {
            func lineDistance(_ p: Point) -> Double { abs((d.x - a.x) * (a.y - p.y) - (a.x - p.x) * (d.y - a.y)) / chord }
            deviation = max(lineDistance(b), lineDistance(c))
        }
        if depth >= 16 || (deviation <= 0.025 && polygon - chord <= 0.025) { points.append(d); return }
        let ab = (a + b) * 0.5, bc = (b + c) * 0.5, cd = (c + d) * 0.5
        let abc = (ab + bc) * 0.5, bcd = (bc + cd) * 0.5, mid = (abc + bcd) * 0.5
        subdivide(a, ab, abc, mid, depth: depth + 1, into: &points)
        subdivide(mid, bcd, cd, d, depth: depth + 1, into: &points)
    }

    /// Bean stitch: sews each stitch `passes` times, back and forth (A→B, back to A, on to B for 3 passes), so the
    /// line is bolder while the needle still ends where the single line would. 1 pass returns the points unchanged.
    public static func repeated(_ points: [Point], passes: Int) throws -> [Point] {
        guard passes > 1, let first = points.first else { return points }
        guard points.count * passes <= 1_000_000 else { throw DesignError.invalid("This path exceeds the one-million-command limit with bean stitch. Shorten it, increase the stitch length or use fewer passes.") }
        var result = [first]
        for i in 1..<points.count {
            for pass in 1...passes { result.append(pass % 2 == 1 ? points[i] : points[i - 1]) }   // odd passes go forward
        }
        return result
    }

    /// The run that takes an open line's sewing from its start point to the end it sews from: from the point on the
    /// line nearest `entry`, back along `stitches` through the line's own needle holes to its first one. That stretch
    /// is sewn twice, which keeps the travel on the line instead of across the fabric. Nil when the start point is
    /// more than 1 mm off the line, or within 1 mm of the line's start (measured along it): the line then simply
    /// starts at its end, as it always did.
    public static func leadIn(along stitches: [Point], from entry: Point) -> [Point]? {
        guard stitches.count >= 2 else { return nil }
        var nearest = (index: 0, point: stitches[0], distance: Double.infinity)
        for i in stitches.indices.dropLast() {
            let q = AreaGeometry.projection(entry, stitches[i], stitches[i + 1]), d = q.distance(to: entry)
            if d < nearest.distance { nearest = (i, q, d) }
        }
        let back = [nearest.point] + stitches[...nearest.index].reversed()
        guard nearest.distance <= 1, zip(back, back.dropFirst()).reduce(0, { $0 + $1.0.distance(to: $1.1) }) > 1 else { return nil }
        return back
    }

    /// Sample each source segment at equal distances so no long stitch spans a corner.
    public static func stitches(for object: RunObject) throws -> [Point] {
        // Reject excessive work before allocating flattened geometry or needle arrays.
        var estimate = 0.0
        let nodes = object.nodes, count = nodes.count
        if count < 2 { return [] }
        for i in 0..<(object.closed ? count : count - 1) {
            try Task.checkCancellation()
            let (a, c1, c2, b) = controls(nodes, closed: object.closed, segment: i)
            // The control polygon is never shorter than the curve, so this over-estimates safely.
            estimate += ceil((a.distance(to: c1) + c1.distance(to: c2) + c2.distance(to: b)) / max(0.3, object.stitchLength)) + 1
            guard estimate.isFinite, estimate <= 1_000_000 else { throw DesignError.invalid("This path exceeds the one-million-command limit. Shorten it or increase the stitch length.") }
        }
        var result: [Point] = []
        for segment in flatten(object.nodes, closed: object.closed) {
            try Task.checkCancellation()
            var lengths = [0.0]
            for i in 1..<segment.count { lengths.append(lengths.last! + segment[i - 1].distance(to: segment[i])) }
            let length = lengths.last ?? 0
            guard length > 0.00001 else { continue }
            let divisions = max(1, Int(ceil(length / max(0.3, object.stitchLength))))
            var index = 1
            for sample in 0...divisions {
                if sample % 256 == 0 { try Task.checkCancellation() }
                let distance = length * Double(sample) / Double(divisions)
                while index < lengths.count - 1 && lengths[index] < distance { index += 1 }
                let span = lengths[index] - lengths[index - 1]
                let fraction = span > 0 ? (distance - lengths[index - 1]) / span : 0
                let p = segment[index - 1] + (segment[index] - segment[index - 1]) * fraction
                if result.last.map({ $0.distance(to: p) > 0.00001 }) ?? true { result.append(p) }
            }
        }
        return result
    }

    public static func compile(_ design: Design) throws -> StitchPlan {
        try StitchEngine.compile(design)
    }
}
