// Travel runs: when one object sews in several sections (fill rows split by holes or concave edges, or underlay
// followed by the top layer), the needle can usually run from the end of one section to the start of the next
// with a few small stitches inside the shape, instead of trimming the thread and jumping. This file finds those
// routes. It prefers paths along the shape's edge, where travel stitches hide among the row ends.
import Foundation

struct TravelRouter {
    /// The area travel stitches must stay inside (the same region the stitches themselves fill), set up for answering
    /// "is this inside?" quickly: routing asks that hundreds of thousands of times.
    private let inside: InsideTest
    /// Direction of the fill rows in degrees, or nil for satin.
    let rowAngle: Double?
    private var nodes: [Point] = []
    /// Whether each edge point is inside the area, worked out once (every straight line to or from it needs it).
    private var nodeInside: [Bool] = []
    private var neighbors: [[(node: Int, cost: Double)]] = []
    /// For each point a route has started or ended at, the edge points it can reach in a straight line (and what that
    /// costs). Working that out is most of a route's time, and ordering a fill's sections asks about the same section
    /// ends over and over (a wave fill with 53 sections: about 300 routes), so the answer is remembered.
    /// A class, so the router can fill it in from `route`, which doesn't change the router itself.
    private final class SightLines { var known: [Point: [(node: Int, cost: Double)]] = [:] }
    private let sightLines = SightLines()
    /// Longest route worth sewing once the top layer has started (travel may show); anything longer is trimmed and
    /// jumped instead. Before the top layer, travel is covered by it, so longer routes are fine.
    static let maximumVisibleLength = 40.0
    static let maximumCoveredLength = 150.0
    static let stitchLength = 2.0
    /// Crossings between rings: each point links to up to 3 points of every other ring, chosen from its 8 nearest.
    /// (Trying every pair grew with the cube of the shape's size: about a second for an 80 mm satin border.)
    static let crossingCandidates = 8, crossingsPerPoint = 3

    /// `edges` are the rings travel should follow (the shape's outline and holes, just inside its edge); `bounds`
    /// is the region every travel stitch must stay inside. Returns nil when the shape is too complex to route quickly.
    init?(edges: [[Point]], bounds: [[Point]], rowAngle: Double? = nil) {
        self.rowAngle = rowAngle
        let total = edges.reduce(0) { $0 + $1.count }
        guard total >= 3, total <= 1200, !bounds.isEmpty else { return nil }
        inside = InsideTest(bounds)
        var firstIndex: [Int] = []
        for ring in edges { firstIndex.append(nodes.count); nodes += ring }
        nodeInside = nodes.map { inside.contains($0) }
        neighbors = Array(repeating: [], count: nodes.count)
        func link(_ a: Int, _ b: Int, _ cost: Double) { neighbors[a].append((b, cost)); neighbors[b].append((a, cost)) }
        // Walking along each ring.
        for (r, ring) in edges.enumerated() {
            for i in ring.indices {
                let a = firstIndex[r] + i, b = firstIndex[r] + (i + 1) % ring.count
                if segmentInside(a, b) { link(a, b, nodes[a].distance(to: nodes[b])) }
            }
        }
        // Short crossings between different rings (such as a hole and the outline), so every ring can be reached:
        // from each point, to the nearest few points of each other ring that it can reach in a straight line.
        var linked = Set<[Int]>()   // pairs already linked (two points can each find the other), lowest index first
        for r in edges.indices { for s in edges.indices where s != r {
            for i in edges[r].indices {
                let a = firstIndex[r] + i
                let nearest = edges[s].indices.map { firstIndex[s] + $0 }.sorted { nodes[a].distance(to: nodes[$0]) < nodes[a].distance(to: nodes[$1]) }
                var found = 0
                for b in nearest.prefix(Self.crossingCandidates) where found < Self.crossingsPerPoint {
                    guard segmentInside(a, b) else { continue }
                    found += 1
                    if linked.insert([min(a, b), max(a, b)]).inserted { link(a, b, crossingCost(nodes[a], nodes[b])) }
                }
            }
        } }
    }

    /// Whether the straight line between edge points `a` and `b` (their indexes) stays inside the shape.
    private func segmentInside(_ a: Int, _ b: Int) -> Bool {
        inside.segmentInside(nodes[a], nodes[b], aInside: nodeInside[a], bInside: nodeInside[b])
    }

    /// What a straight run across the inside of the shape costs, compared with following its edge (cost = length).
    /// A run along the fill rows sinks between them and hides, so it costs the same as the edge; a run straight
    /// across the rows sits on top and shows, so it costs three times as much. Without rows (satin), crossings cost double.
    func crossingCost(_ a: Point, _ b: Point) -> Double {
        let length = a.distance(to: b)
        guard let rowAngle, length > 1e-9 else { return length * 2 }
        let radians = rowAngle * .pi / 180
        let across = abs(AreaGeometry.cross(Point(cos(radians), sin(radians)), b - a)) / length   // sine of the angle to the rows
        return length * (1 + 2 * across)
    }

    /// The cheapest path from `a` to `b` inside the shape, as corner points from `a` to `b`, or nil if there is none.
    /// Uses Dijkstra's shortest-path method: repeatedly settle the unsettled point with the lowest total cost so far.
    func route(from a: Point, to b: Point) -> [Point]? {
        if a.distance(to: b) < 1e-6 { return [a, b] }
        // Two extra points, a (index n) and b (index n + 1), joined to every edge point they can see in a straight line.
        let n = nodes.count, start = n, goal = n + 1
        var links = neighbors + [[], []]
        let ends = [a, b]
        for (k, p) in ends.enumerated() {
            for (v, cost) in visible(from: p) { links[n + k].append((v, cost)); links[v].append((n + k, cost)) }
        }
        if inside.segmentInside(a, b) { let cost = crossingCost(a, b); links[start].append((goal, cost)); links[goal].append((start, cost)) }
        var best = [Double](repeating: .infinity, count: n + 2), from = [Int](repeating: -1, count: n + 2), settled = [Bool](repeating: false, count: n + 2)
        best[start] = 0
        while true {
            var current = -1
            for v in 0..<(n + 2) where !settled[v] && best[v] < .infinity && (current < 0 || best[v] < best[current]) { current = v }
            guard current >= 0 else { return nil }
            if current == goal { break }
            settled[current] = true
            for (next, cost) in links[current] where best[current] + cost < best[next] { best[next] = best[current] + cost; from[next] = current }
        }
        var path: [Point] = [], v = goal
        while v >= 0 { path.append(v == start ? a : v == goal ? b : nodes[v]); v = from[v] }
        return path.reversed()
    }

    /// The edge points `p` can reach in a straight line inside the shape, in order, each with the cost of that run.
    /// Worked out once per point and then remembered (see `sightLines`).
    private func visible(from p: Point) -> [(node: Int, cost: Double)] {
        if let known = sightLines.known[p] { return known }
        // Whether `p` itself is inside is the same for every line from it, so it's asked once (outside: none are).
        let pInside = inside.contains(p)
        let found = !pInside ? [] : nodes.indices.filter { inside.segmentInside(p, nodes[$0], aInside: true, bInside: nodeInside[$0]) }.map { (node: $0, cost: crossingCost(p, nodes[$0])) }
        sightLines.known[p] = found
        return found
    }

    /// The sections in a cheaper sewing order: after each one, the needle goes to whichever remaining section it can
    /// reach by the shortest route inside the shape, entering from whichever end is closer (a section sewn backwards
    /// covers exactly the same stitches). Only the three sections nearest in a straight line are routed, to keep this
    /// quick. The first section stays first; with `keepingLast`, the last stays last too.
    func ordered(_ sections: [StitchSection], keepingLast: Bool) -> [StitchSection] {
        guard sections.count > 2 || (sections.count == 2 && !keepingLast) else { return sections }
        var result = [sections[0]], remaining = Array(sections.dropFirst())
        let last = keepingLast ? remaining.popLast() : nil
        while !remaining.isEmpty {
            let a = result.last!.points.last!
            func straight(_ i: Int) -> Double { min(a.distance(to: remaining[i].points.first!), a.distance(to: remaining[i].points.last!)) }
            let nearest = remaining.indices.sorted { straight($0) < straight($1) }.prefix(3)
            var best: (index: Int, reversed: Bool, cost: Double)?
            for i in nearest {
                for reversed in [false, true] {
                    let b = reversed ? remaining[i].points.last! : remaining[i].points.first!
                    let cost = route(from: a, to: b).map(AreaGeometry.pathLength) ?? .infinity
                    if best == nil || cost < best!.cost { best = (i, reversed, cost) }
                }
            }
            // No route to any of them: keep the original order and direction.
            let choice = best.flatMap { $0.cost.isFinite ? $0 : nil } ?? (index: remaining.startIndex, reversed: false, cost: 0)
            var next = remaining.remove(at: choice.index)
            if choice.reversed { next.points.reverse() }
            result.append(next)
        }
        if let last { result.append(last) }
        return relocated(result, keepingLast: keepingLast)
    }

    /// The greedy order above can strand small sections: skipped early because a bigger one started nearer, they're
    /// left until the needle is far away, and then need a jump and a trim. This moves runs of one to three
    /// consecutive sections to wherever they add the least travel (sewn either way round) for as long as that
    /// shortens the total. To keep it quick, only runs whose way in and out is long enough to need a trim are moved,
    /// each tries only the six places whose ends are nearest in a straight line, and long lists are left as they are.
    private func relocated(_ sections: [StitchSection], keepingLast: Bool) -> [StitchSection] {
        guard sections.count >= 3, sections.count <= 60 else { return sections }
        var order = sections, known: [[Double]: Double] = [:]
        /// The travel from `a` to `b` inside the shape (routes are remembered); no route counts as very long.
        func travel(_ a: Point, _ b: Point) -> Double {
            let key = [a.x, a.y, b.x, b.y]
            if let length = known[key] { return length }
            let length = route(from: a, to: b).map(AreaGeometry.pathLength) ?? 1_000_000
            known[key] = length; return length
        }
        /// A run of sections sewn the other way round: last section first, each one backwards.
        func reversed(_ run: [StitchSection]) -> [StitchSection] { run.reversed().map { var s = $0; s.points.reverse(); return s } }
        var moves = 0, improved = true
        while improved && moves < 50 {
            improved = false
            let movable = keepingLast ? order.count - 1 : order.count
            search: for size in 1...3 {
                for i in 1..<movable where i + size <= movable {
                    let run = Array(order[i..<(i + size)])
                    let before = order[i - 1].points.last!, after = i + size < order.count ? order[i + size].points.first : nil
                    // What taking the run out saves; only a stranded run (one that would need a trim) is worth searching for.
                    let saving = travel(before, run[0].points.first!) + (after.map { travel(run.last!.points.last!, $0) - travel(before, $0) } ?? 0)
                    guard saving > Self.maximumVisibleLength else { continue }
                    var rest = order; rest.removeSubrange(i..<(i + size))
                    let start = run[0].points.first!, end = run.last!.points.last!
                    // Where it could go: after rest[p - 1] (never after a last section that must stay last).
                    let places = (1...(keepingLast ? rest.count - 1 : rest.count)).sorted { p, q in
                        let a = rest[p - 1].points.last!, b = rest[q - 1].points.last!
                        return min(a.distance(to: start), a.distance(to: end)) < min(b.distance(to: start), b.distance(to: end))
                    }.prefix(6)
                    var best: (place: Int, run: [StitchSection], cost: Double)?
                    for p in places {
                        let a = rest[p - 1].points.last!, b = p < rest.count ? rest[p].points.first : nil
                        for candidate in [run, reversed(run)] {
                            let cost = travel(a, candidate[0].points.first!) + (b.map { travel(candidate.last!.points.last!, $0) - travel(a, $0) } ?? 0)
                            if best == nil || cost < best!.cost { best = (p, candidate, cost) }
                        }
                    }
                    guard let best, best.cost < saving - 0.5 else { continue }
                    rest.insert(contentsOf: best.run, at: best.place); order = rest
                    moves += 1; improved = true; break search   // positions changed: start over
                }
            }
        }
        return order
    }

    /// Joins consecutive sections with travel runs wherever a short enough route exists inside the shape. Each travel
    /// run becomes its own section, marked as joined, and so is the section after it: the compiler sews them straight
    /// on from where the needle already is, with no trim, jump or tie stitches. Until the top layer starts, travel
    /// (including travel between underlay passes) is covered by it, so longer routes are allowed; so is the travel
    /// into a section listed in `coveredStarts` (the first section of a part of the fill sewn over its own travel).
    func join(_ sections: [StitchSection], coveredStarts: Set<Int> = []) -> [StitchSection] {
        guard var result = sections.first.map({ [$0] }) else { return [] }
        var topStarted = !result[0].underlay
        for (index, section) in sections.enumerated().dropFirst() {
            var next = section
            let covered = !topStarted || coveredStarts.contains(index)   // nothing of the top layer sewn yet, or sewn over next
            if let a = result.last?.points.last, let b = section.points.first, let path = route(from: a, to: b),
               AreaGeometry.pathLength(path) <= (covered ? Self.maximumCoveredLength : Self.maximumVisibleLength) {
                let travel = travelStitches(path)
                if travel.count > 1 { result.append(StitchSection(travel, joined: true)) }
                next.joined = true
            }
            result.append(next)
            if !section.underlay { topStarted = true }
        }
        return result
    }

    /// Running stitches of at most 2 mm along `path`, from its first point to its last. Every corner of the path
    /// is kept, so no stitch cuts a corner; a corner is skipped only when it is less than 0.3 mm from the previous
    /// stitch (very short stitches can knot) and the stitch past it still stays inside the shape.
    func travelStitches(_ path: [Point]) -> [Point] {
        guard let first = path.first else { return [] }
        var corners = [first]
        for (i, p) in path.enumerated().dropFirst() {
            let isLast = i == path.count - 1
            if !isLast && p.distance(to: corners.last!) < 0.3 && inside.segmentInside(corners.last!, path[i + 1]) { continue }
            if p.distance(to: corners.last!) > 1e-9 { corners.append(p) }
        }
        return AreaGeometry.sampled(corners, length: Self.stitchLength)
    }
}
