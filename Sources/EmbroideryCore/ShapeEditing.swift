// Weld, Knife and Smooth Shapes: merging overlapping shapes into one fill, cutting objects along a
// drawn line (keeping their settings and colors), and removing nodes that barely change an outline.
import Foundation

extension RunObject {
    /// The area this object covers, as an outer ring followed by its holes (mm), for welding and cutting. A satin
    /// covers the band between its rails (a closed satin, a border, the ring between its two loops). nil for open
    /// lines, imported stitches and outlines too small to have an area.
    public var areaRings: [[Point]]? {
        var rings: [[Point]]
        switch kind {
        case .fill: rings = [AreaGeometry.ring(nodes)] + (holes ?? []).map(AreaGeometry.ring)
        case .run, .vector:
            guard closed else { return nil }
            rings = [AreaGeometry.ring(nodes)] + (holes ?? []).map(AreaGeometry.ring)
        case .satin:
            let (left, right) = (rail(0), rail(1))
            if closed {
                let a = AreaGeometry.ring(left), b = AreaGeometry.ring(right)
                rings = abs(AreaGeometry.area(a)) >= abs(AreaGeometry.area(b)) ? [a, b] : [b, a]
            } else { rings = [AreaGeometry.ring(left + right.reversed().map(\.reversedDirection))] }
        case .raw: return nil
        }
        guard let outer = rings.first, outer.count >= 3, abs(AreaGeometry.area(outer)) > 0.01 else { return nil }
        return rings.filter { $0.count >= 3 }
    }
    /// One rail of a satin: its left (0) or right (1) edge nodes.
    func rail(_ side: Int) -> [PathNode] { nodes.enumerated().filter { $0.offset % 2 == side }.map(\.element) }
}

extension Design {
    /// Weld: merges the objects in `ids` that have an area (fills, closed outlines, satins) into one fill, with the
    /// settings of the topmost object (the one sewn last). A satin or outline on top gives
    /// a fill in its color with the usual fill settings. The fill takes the topmost object's place in the sewing
    /// order. Parts that don't touch become separate fills. Returns the new fills' IDs, largest first (empty if
    /// fewer than two objects could be welded; locked objects are left out).
    public mutating func weld(_ ids: Set<UUID>) throws -> [UUID] {
        let welding = objects.filter { ids.contains($0.id) && !$0.locked && $0.areaRings != nil }
        guard welding.count >= 2, let top = welding.last, let topIndex = objects.firstIndex(where: { $0.id == top.id }) else { return [] }
        // First the pieces stop overlapping (each object loses what the ones before it cover), so joining them
        // can't cancel out where two overlapped.
        var pieces: [[[Point]]] = [], covered: [[[Point]]] = []
        for object in welding {
            let region = Self.oriented(object.areaRings!)
            var remaining = [region]
            for earlier in covered { remaining = try remaining.flatMap { try AreaGeometry.subtracting(earlier, from: $0) } }
            pieces += remaining; covered.append(region)
        }
        // Then they're joined: growing everything by 0.002 mm and shrinking it back closes hairline gaps, such as
        // the one a knife cut leaves, so pieces cut apart weld back together.
        let joined = try AreaGeometry.offset(AreaGeometry.offset(pieces.flatMap { $0 }, by: 0.002), by: -0.002)
        let regions = try AreaGeometry.svgRegions(joined, nonzero: false).sorted { abs(AreaGeometry.area($0[0])) > abs(AreaGeometry.area($1[0])) }
        guard !regions.isEmpty else { return [] }
        var made: [RunObject] = []
        for (number, region) in regions.enumerated() {
            let rings = region.map { Self.cornerNodes($0) }
            try AreaGeometry.validate(rings.map(AreaGeometry.ring))
            var fill = top
            if top.kind != .fill {
                fill = RunObject(name: top.name, nodes: [], color: top.color)
                fill.digitizing = DigitizingSettings(kind: .fill); fill.stitchLength = 3; fill.groupID = top.groupID
                fill = withFabric(fill)
            }
            fill.id = number == 0 ? top.id : UUID()
            if number > 0 { fill.name = "\(top.name) \(number + 1)" }
            fill.nodes = rings[0]; fill.holes = rings.count > 1 ? Array(rings.dropFirst()) : nil; fill.closed = true
            fill.lettering = nil   // welded letters are plain shapes
            fill.keepMarkers(inside: region)
            made.append(fill)
        }
        let weldedIDs = Set(welding.map(\.id))
        objects.removeAll { weldedIDs.contains($0.id) }
        objects.insert(contentsOf: made, at: topIndex - (welding.count - 1))   // every other welded object sewed before the top one
        return made.map(\.id)
    }

    /// Knife: cuts the objects in `ids` along `line` (mm, two or more points): each piece keeps the
    /// object's settings and color, and the pieces take its place in the sewing order. Fills and closed outlines
    /// split into the areas on either side; satins are cut across their column; lines are cut where the knife
    /// crosses them. Objects the line doesn't cut through, and locked ones, are left alone. Returns the pieces' IDs.
    public mutating func cut(_ ids: Set<UUID>, along line: [Point]) throws -> [UUID] {
        guard line.count >= 2 else { return [] }
        var result: [UUID] = [], index = 0
        while index < objects.count {
            let object = objects[index]
            guard ids.contains(object.id), !object.locked, object.kind != .raw else { index += 1; continue }
            let pieces: [RunObject]
            switch object.kind {
            case .satin: pieces = Self.cutSatin(object, along: line)
            case .fill, .run, .vector:
                if object.kind == .fill || object.closed { pieces = try Self.cutArea(object, along: line) }
                else { pieces = Self.cutLine(object, along: line) }
            case .raw: pieces = []
            }
            guard !pieces.isEmpty else { index += 1; continue }   // not cut through (a border cut once opens into one piece)
            objects.replaceSubrange(index...index, with: pieces)
            result += pieces.map(\.id); index += pieces.count
        }
        return result
    }

    /// Smooth Shapes: removes nodes from the objects in `ids` that barely shape their outlines: each one whose
    /// removal keeps the outline within `tolerance` mm of where it was. Satins lose a node from each rail together
    /// (a rung), only where both rails stay within it. Locked objects and imported stitches are left alone.
    /// Returns how many nodes were removed.
    @discardableResult public mutating func smoothShapes(_ ids: Set<UUID>, tolerance: Double = 0.2) -> Int {
        var removed = 0
        for i in objects.indices where ids.contains(objects[i].id) && !objects[i].locked && objects[i].kind != .raw && objects[i].kind != .satin {
            let closed = objects[i].kind == .fill || objects[i].closed, before = objects[i].allNodes.count
            objects[i].nodes = Self.reduced([objects[i].nodes], closed: closed, tolerance: tolerance)[0]
            if let holes = objects[i].holes { objects[i].holes = holes.map { Self.reduced([$0], closed: true, tolerance: tolerance)[0] } }
            removed += before - objects[i].allNodes.count
        }
        for i in objects.indices where ids.contains(objects[i].id) && !objects[i].locked && objects[i].kind == .satin {
            let rails = Self.reduced([objects[i].rail(0), objects[i].rail(1)], closed: objects[i].closed, tolerance: tolerance)
            removed += objects[i].nodes.count - rails[0].count * 2
            objects[i].nodes = zip(rails[0], rails[1]).flatMap { [$0, $1] }
        }
        return removed
    }

    // MARK: Helpers

    /// A region with its outer ring counterclockwise and its holes clockwise, as joining shapes needs.
    static func oriented(_ region: [[Point]]) -> [[Point]] {
        region.enumerated().map { index, ring in (AreaGeometry.area(ring) > 0) == (index == 0) ? ring : ring.reversed() }
    }

    /// A ring of points (such as one Clipper worked out) as corner nodes, leaving out points that sit within 0.05 mm
    /// of the outline without them, so straight edges don't carry hundreds of nodes. Smooth Shapes can thin them more.
    static func cornerNodes(_ ring: [Point]) -> [PathNode] {
        reduced([ring.map { PathNode($0) }], closed: true, tolerance: 0.05)[0]
    }

    /// The rails (one, or a satin's two, with nodes in step) with every node removed whose loss keeps each curve
    /// within `tolerance` mm of the original one: of the original, not the last step, so small changes can't add
    /// up. Removing a node changes the curve between its two neighbours on each side (smooth nodes' automatic
    /// handles follow their neighbours), so only that stretch is compared, both ways round. An open path keeps its
    /// ends; a closed one keeps at least 3 nodes, an open one 2.
    static func reduced(_ rails: [[PathNode]], closed: Bool, tolerance: Double) -> [[PathNode]] {
        let minimum = closed ? 3 : 2
        guard let count = rails.first?.count, count > minimum, rails.allSatisfy({ $0.count == count }) else { return rails }
        let original = rails.map { RunningEngine.flatten($0, closed: closed) }   // original[r][j]: rail r's curve from node j to the next
        var current = rails, kept = Array(0..<count)   // kept[j]: which original node current node j is
        /// The points along `nodes`' curve from segment `first` to segment `last` (wrapping round on a closed path).
        func sampled(_ nodes: [PathNode], from first: Int, to last: Int) -> [Point] {
            var points: [Point] = [], j = first
            while true {
                let (a, b, c, d) = RunningEngine.controls(nodes, closed: closed, segment: (j + nodes.count) % nodes.count)
                points += (0...16).map { RunningEngine.bezierPoint(a, b, c, d, Double($0) / 16) }
                if j == last { return points }
                j += 1
            }
        }
        func distance(_ p: Point, to line: [Point]) -> Double {
            zip(line, line.dropFirst()).map { p.distance(to: AreaGeometry.projection(p, $0, $1)) }.min() ?? (line.first.map(p.distance) ?? 0)
        }
        func furthest(_ points: [Point], from line: [Point]) -> Double { points.map { distance($0, to: line) }.max() ?? 0 }
        var changed = true
        while changed {
            changed = false
            var i = closed ? 0 : 1
            while current[0].count > minimum && i < current[0].count - (closed ? 0 : 1) {
                let candidate = current.map { rail in var next = rail; next.remove(at: i); return next }
                var candidateKept = kept; candidateKept.remove(at: i)
                let n = candidate[0].count
                // The candidate's segments around the gap, and the original stretch they replace.
                let first = closed ? i - 2 : max(0, i - 2), last = closed ? i : min(i, n - 2)
                let start = candidateKept[(first + n) % n], end = candidateKept[(last + 1) % n]
                let fits = rails.indices.allSatisfy { r in
                    var before: [Point] = [], k = start
                    repeat { before += original[r][k]; k = (k + 1) % count } while k != end && (closed || k < count - 1)
                    let after = sampled(candidate[r], from: first, to: last)
                    return furthest(before, from: after) <= tolerance && furthest(after, from: before) <= tolerance
                }
                if fits { current = candidate; kept = candidateKept; changed = true } else { i += 1 }
            }
        }
        return current
    }

    /// The thin band (0.001 mm wide) a knife line cuts out of a shape, as rings.
    static func knifeBand(_ line: [Point]) throws -> [[Point]] {
        let boxes = band(line, halfWidth: 0.0005)   // counterclockwise, so overlapping boxes join up
        guard !boxes.isEmpty else { return [] }
        return try AreaGeometry.svgRegions(boxes, nonzero: true).flatMap { $0 }
    }

    /// A fill or closed outline cut along the knife line: one copy per piece of its area, or [] if the line doesn't
    /// cut all the way through.
    static func cutArea(_ object: RunObject, along line: [Point]) throws -> [RunObject] {
        guard let rings = object.areaRings else { return [] }
        let band = try knifeBand(line)
        guard !band.isEmpty else { return [] }
        let pieces = try AreaGeometry.subtracting(band, from: oriented(rings)).sorted { abs(AreaGeometry.area($0[0])) > abs(AreaGeometry.area($1[0])) }
        guard pieces.count >= 2 else { return [] }
        return pieces.enumerated().map { number, region in
            var piece = object.cutPiece(number)
            let nodes = region.map(cornerNodes)
            piece.nodes = nodes[0]; piece.holes = nodes.count > 1 ? Array(nodes.dropFirst()) : (object.holes == nil ? nil : [])
            piece.keepMarkers(inside: region); piece.keepAngleLines(for: region)
            return piece
        }
    }

    /// Where a knife line crosses a path: for each crossing, the segment (from node `segment` to the next) and the
    /// point, in order along the path.
    static func crossings(_ nodes: [PathNode], closed: Bool, line: [Point]) -> [(segment: Int, point: Point)] {
        var found: [(segment: Int, along: Double, point: Point)] = []
        for (segment, points) in RunningEngine.flatten(nodes, closed: closed).enumerated() {
            var travelled = 0.0
            for (a, b) in zip(points, points.dropFirst()) {
                for (c, d) in zip(line, line.dropFirst()) {
                    let u = b - a, v = d - c, den = AreaGeometry.cross(u, v)
                    guard abs(den) > 1e-12 else { continue }
                    let t = AreaGeometry.cross(c - a, v) / den, s = AreaGeometry.cross(c - a, u) / den
                    if t >= 0, t < 1, s >= 0, s <= 1 { found.append((segment, travelled + t * a.distance(to: b), a + u * t)) }
                }
                travelled += a.distance(to: b)
            }
        }
        // Where the knife meets the path at a node, or at one of its own corners, the same place is found twice.
        var crossings: [(segment: Int, point: Point)] = []
        for crossing in found.sorted(by: { ($0.segment, $0.along) < ($1.segment, $1.along) }) where crossings.last.map({ $0.point.distance(to: crossing.point) >= 0.01 }) ?? true {
            crossings.append((crossing.segment, crossing.point))
        }
        if closed, crossings.count > 1, crossings[0].point.distance(to: crossings[crossings.count - 1].point) < 0.01 { crossings.removeLast() }
        return crossings
    }

    /// The node a crossing lands on (within 0.01 mm), if it does, so a cut there doesn't add a node on top of it.
    static func node(at crossing: (segment: Int, point: Point), in nodes: [PathNode]) -> Int? {
        [crossing.segment, (crossing.segment + 1) % nodes.count].first { nodes[$0].point.distance(to: crossing.point) < 0.01 }
    }

    /// `nodes` with a node added at each crossing (curves keep their exact shape), and the indices of those nodes.
    static func inserting(_ crossings: [(segment: Int, point: Point)], into nodes: [PathNode], closed: Bool) -> (nodes: [PathNode], cuts: [Int]) {
        var result = nodes, cuts: [Int] = []
        // From the last crossing back, so each one's segment number still holds when it's added.
        for crossing in crossings.reversed() {
            if let existing = node(at: crossing, in: result) { cuts.append(existing); continue }   // cut at the node itself
            let added = RunningEngine.insertingNode(result, closed: closed, segment: crossing.segment, near: crossing.point)
            result = added.nodes
            cuts = cuts.map { $0 >= added.index ? $0 + 1 : $0 } + [added.index]
        }
        return (result, cuts.sorted())
    }

    /// An open line cut where the knife crosses it: the stretches between crossings, each its own line.
    static func cutLine(_ object: RunObject, along line: [Point]) -> [RunObject] {
        let found = crossings(object.nodes, closed: false, line: line)
        guard !found.isEmpty else { return [] }
        let (nodes, cuts) = inserting(found, into: object.nodes, closed: false)
        let bounds = [0] + cuts + [nodes.count - 1]
        let stretches = zip(bounds, bounds.dropFirst()).filter { $1 > $0 }.map { Array(nodes[$0...$1]) }
        guard stretches.count >= 2 else { return [] }
        return stretches.enumerated().map { number, stretch in var piece = object.cutPiece(number); piece.nodes = stretch; piece.entry = nil; piece.exit = nil; return piece }
    }

    /// A satin cut across its column where the knife crosses both rails. A satin is a ladder of rungs (each left node
    /// and the right node across from it), so every cut is a rung: where the knife crosses both rails between the
    /// same two rungs, a new node goes into each rail there; where it crosses them either side of one rung (cutting
    /// across a corner), the cut is made at that rung. Both rails always get the same nodes, so every node keeps its
    /// partner across the column. A closed satin (a border) first opens at its first cut.
    static func cutSatin(_ object: RunObject, along line: [Point]) -> [RunObject] {
        let closed = object.closed
        var left = object.rail(0), right = object.rail(1)
        let count = left.count
        guard count >= 2, right.count == count else { return [] }
        let leftCrossings = crossings(left, closed: closed, line: line)
        var rightCrossings = crossings(right, closed: closed, line: line)
        /// The rung two segments share, if they're neighbours (segment k runs from rung k to rung k + 1).
        func sharedRung(_ a: Int, _ b: Int) -> Int? {
            for (x, y) in [(a, b), (b, a)] where (closed ? (x + 1) % count : x + 1) == y { return y }
            return nil
        }
        // Each left crossing goes with the nearest right one: a new rung between them, or the rung they're either side of.
        var newRungs: [(segment: Int, left: Point, right: Point)] = [], cuts: [Int] = []
        for crossing in leftCrossings {
            guard let nearest = rightCrossings.indices.min(by: { rightCrossings[$0].point.distance(to: crossing.point) < rightCrossings[$1].point.distance(to: crossing.point) }) else { break }
            let other = rightCrossings.remove(at: nearest)
            if other.segment == crossing.segment {
                // Right through a rung: cut there. Otherwise a new rung goes in between.
                if let l = node(at: crossing, in: left), node(at: other, in: right) == l { cuts.append(l) } else { newRungs.append((crossing.segment, crossing.point, other.point)) }
            }
            else if let rung = sharedRung(crossing.segment, other.segment) { cuts.append(rung) }
        }
        // From the last new rung back (the crossings are in order along the rail), so each segment number still holds.
        for rung in newRungs.reversed() {
            let added = RunningEngine.insertingNode(left, closed: closed, segment: rung.segment, near: rung.left)
            left = added.nodes; right = RunningEngine.insertingNode(right, closed: closed, segment: rung.segment, near: rung.right).nodes
            cuts = cuts.map { $0 >= added.index ? $0 + 1 : $0 } + [added.index]
        }
        cuts = Array(Set(cuts)).sorted()
        guard let first = cuts.first else { return [] }
        if closed {
            // Open the ring at the first cut: both rails start there and run all the way round back to it.
            func opened(_ rail: [PathNode]) -> [PathNode] { Array(rail[first...]) + Array(rail[..<first]) + [rail[first]] }
            left = opened(left); right = opened(right)
            cuts = cuts.dropFirst().map { $0 - first }
        }
        let bounds = [0] + cuts + [left.count - 1]
        var pieces: [RunObject] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) where b > a {
            var piece = object.cutPiece(pieces.count)
            piece.nodes = zip(left[a...b], right[a...b]).flatMap { [$0, $1] }; piece.closed = false; piece.entry = nil; piece.exit = nil
            pieces.append(piece)
        }
        return pieces.count >= 2 || (closed && pieces.count == 1) ? pieces : []
    }
}

extension RunObject {
    /// A piece of this object after a knife cut: the same settings and color. The first piece keeps the object's
    /// identity; the others are new objects named after it ("Leaf 2", "Leaf 3"). Cut letters become plain shapes.
    func cutPiece(_ number: Int) -> RunObject {
        var piece = self
        if number > 0 { piece.id = UUID(); piece.name = "\(name) \(number + 1)" }
        piece.lettering = nil
        return piece
    }
    /// Keeps the stitch angle lines that belong to `region` (a piece of this fill, its outline and holes): the ones
    /// drawn across it. When none is, the piece becomes a plain fill at the nearest line's angle, so it still sews the
    /// way the fill ran there; lines that miss a fill would otherwise stop the whole design from sewing.
    mutating func keepAngleLines(for region: [[Point]]) {
        guard let lines = digitizing?.angleLines, !lines.isEmpty else { return }
        let across = lines.filter { $0.count >= 2 && !AreaGeometry.clippedSegment($0[0], $0[1], rings: region).isEmpty }
        if !across.isEmpty { digitizing?.angleLines = across; return }
        /// How far a line's middle is from the piece's edge.
        func distance(_ line: [Point]) -> Double {
            let middle = (line[0] + line[line.count - 1]) * 0.5
            return region.flatMap { ring in ring.indices.map { middle.distance(to: AreaGeometry.projection(middle, ring[$0], ring[($0 + 1) % ring.count])) } }.min() ?? .infinity
        }
        if let nearest = lines.filter({ $0.count >= 2 }).min(by: { distance($0) < distance($1) }) {
            digitizing?.angle = TurningFill.direction((nearest[0], nearest[1]))
        }
        digitizing?.angleLines = nil
    }
    /// Forgets start and end points that no longer lie inside `region` (a welded or cut shape's outline and holes).
    mutating func keepMarkers(inside region: [[Point]]) {
        if let entry, !AreaGeometry.contains(entry, rings: region) { self.entry = nil }
        if let exit, !AreaGeometry.contains(exit, rings: region) { self.exit = nil }
    }
}
