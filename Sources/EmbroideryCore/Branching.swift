// Branching: the selected objects become one branch that sews without trims. They're put
// in an order where each starts near where the one before it finished, take the first one's thread, and are
// grouped; when stitches are worked out, the needle travels from one to the next with a short run inside the
// branch's own shapes (where later stitching covers it) instead of a trim and a jump.
import Foundation

extension Design {
    /// Branching: makes the objects in `ids` (two or more fills, satins or lines; locked ones are left out) one
    /// branch, starting at `entry` and finishing at `exit` (nil lets OpenHoop choose: the object that sews first now
    /// starts it). The order is chosen object by object: next is whichever remaining one lies nearest. Each object
    /// starts where the one before it finishes and, if it's a fill, finishes at its point nearest the next one.
    /// The branch takes the place of its earliest object in the sewing order. Returns the branch's objects in order
    /// (empty if fewer than two could be branched).
    public mutating func branch(_ ids: Set<UUID>, entry: Point?, exit: Point?) throws -> [UUID] {
        var remaining = objects.filter { ids.contains($0.id) && !$0.locked && [.run, .satin, .fill].contains($0.kind) }
        guard remaining.count >= 2, let start = objects.firstIndex(where: { $0.id == remaining[0].id }) else { return [] }
        let outlines = Dictionary(uniqueKeysWithValues: remaining.map { ($0.id, Self.outlinePoints($0)) })
        func gap(_ a: UUID, _ b: UUID) -> Double { Self.gap(outlines[a]!, outlines[b]!) }
        // The order: the object nearest the start point (or the one sewn first now), then each time the nearest left.
        var ordered = [remaining.remove(at: entry.map { p in remaining.indices.min { Self.gap([p], outlines[remaining[$0].id]!) < Self.gap([p], outlines[remaining[$1].id]!) }! } ?? 0)]
        while !remaining.isEmpty {
            let last = ordered.last!.id
            ordered.append(remaining.remove(at: remaining.indices.min { gap(last, remaining[$0].id) < gap(last, remaining[$1].id) }!))
        }
        let branch = UUID(), color = ordered[0].color
        for i in ordered.indices {
            ordered[i].branchID = branch; ordered[i].groupID = branch; ordered[i].color = color
            // Stitches edited by hand already decide where the object starts and finishes. Changing its start or end
            // point would throw the edits away, so it keeps them, and the next object starts where they finish.
            if ordered[i].hasCurrentStitchEdits { continue }
            if i == 0, let entry { ordered[i].entry = entry }
            if i == ordered.count - 1 { if let exit { ordered[i].exit = exit } }
            else if ordered[i].kind == .fill { ordered[i].exit = Self.nearestPoint(of: outlines[ordered[i].id]!, to: outlines[ordered[i + 1].id]!) }
            else { ordered[i].exit = nil }   // lines and satins finish at whichever end their start leaves; an old end point would pull them away
            if i > 0 {
                // Start where the one before finishes (worked out from its stitches).
                var before = Design(); before.hoop = hoop; before.objects = [ordered[i - 1]]
                if let end = try StitchEngine.compile(before).commands.last(where: { $0.op == .stitch })?.point { ordered[i].entry = end }
            }
        }
        let branched = Set(ordered.map(\.id))
        objects.removeAll { branched.contains($0.id) }
        objects.insert(contentsOf: ordered, at: start)   // everything before the earliest of them was left in place
        return ordered.map(\.id)
    }

    /// The route finder for travel between the objects of a branch: inside the shapes of all its objects (lines count
    /// as a 1 mm band along them), joined into one area. nil if the branch has no area or it's too complex to route.
    func branchRouter(_ branch: UUID) -> TravelRouter? {
        var rings: [[Point]] = []
        for object in objects where object.branchID == branch {
            if let area = object.areaRings { rings += Self.oriented(area) }
            else { for path in object.outlinePaths where path.count >= 2 { rings += Self.band(path, halfWidth: 0.5) } }
        }
        // Counterclockwise outlines and clockwise holes, joined by "nonzero": overlaps add up, and a hole stays a
        // hole only where no other object covers it.
        guard !rings.isEmpty, let joined = try? AreaGeometry.svgRegions(rings, nonzero: true).flatMap({ $0 }), !joined.isEmpty else { return nil }
        func simple(_ rings: [[Point]]) -> [[Point]] { rings.map { Self.cornerNodes($0).map(\.point) } }
        // Stitches can sit a little outside a shape (satin compensation), so the area reaches 0.5 mm further;
        // travel follows rings just inside the edges.
        let bounds = simple((try? AreaGeometry.offset(joined, by: 0.5)) ?? joined)
        let edges = simple((try? AreaGeometry.offset(joined, by: -0.25)).flatMap { $0.isEmpty ? nil : $0 } ?? joined)
        return TravelRouter(edges: edges, bounds: bounds)
    }

    /// An object's outline as points, for measuring how far apart objects are.
    static func outlinePoints(_ object: RunObject) -> [Point] { object.outlinePaths.flatMap { AreaGeometry.sampled($0, length: 1) } }
    /// The shortest distance between two sets of points.
    static func gap(_ a: [Point], _ b: [Point]) -> Double { a.lazy.flatMap { p in b.lazy.map { p.distance(to: $0) } }.min() ?? .infinity }
    /// The point of `a` nearest any point of `b`.
    static func nearestPoint(of a: [Point], to b: [Point]) -> Point? { a.min { gap([$0], b) < gap([$1], b) } }
}
