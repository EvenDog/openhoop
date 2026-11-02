// Scatter: copies of a selection dropped at random inside a closed shape, like confetti, stars or polka dots, each a
// random size between two limits and, if wanted, turned at random. The shape only marks the area: it's used up, and
// the copies replace the originals. The same settings and seed always give the same layout; Shuffle picks another.
import Foundation

/// Scatter's choices (the Scatter tool's options).
public struct ScatterSettings: Hashable, Sendable {
    /// How many copies to place; fewer go in when no more fit.
    public var copies = 20
    /// The smallest and largest size of a copy, as a percentage of the original.
    public var smallest = 70.0, largest = 130.0
    /// The least space (mm) between neighbouring copies, and between a copy and the area's edge.
    public var gap = 1.0
    /// True when each copy is turned at random; false keeps them all upright.
    public var turns = true
    /// Which random layout; Shuffle moves on to the next.
    public var seed: UInt64 = 1
    public init() {}
    public static let copyRange = 1...300, sizeRange = 10.0...300.0, gapRange = 0.0...20.0
}

extension Design {
    /// Scatters copies of the objects in `ids` at random inside the closed shape `areaID`, as `settings` says. The
    /// shape and the originals are removed; the copies make one group where the first original was, sewn one thread
    /// color at a time, and from each copy to the nearest one not yet sewn. Returns the copies' ids in sewing order and
    /// how many copies fit. Throws, saying why, when the area isn't a closed shape or not even one copy fits.
    @discardableResult
    public mutating func scatter(_ ids: Set<UUID>, inside areaID: UUID, _ settings: ScatterSettings) throws -> (ids: [UUID], placed: Int) {
        let sources = objects.filter { ids.contains($0.id) && $0.id != areaID && !$0.locked }
        guard !sources.isEmpty else { throw DesignError.invalid("Select the shapes to scatter and a closed shape to scatter them in.") }
        guard let area = objects.first(where: { $0.id == areaID }), let rings = area.areaRings else {
            throw DesignError.invalid("The area to scatter in must be a closed shape, such as a fill or a closed outline.")
        }
        guard ScatterSettings.copyRange.contains(settings.copies), ScatterSettings.sizeRange.contains(settings.smallest), ScatterSettings.sizeRange.contains(settings.largest),
              settings.smallest <= settings.largest, ScatterSettings.gapRange.contains(settings.gap) else { throw DesignError.invalid("Invalid scatter settings.") }
        guard let box = bounds(of: Set(sources.map(\.id))) else { throw DesignError.invalid("Select the shapes to scatter.") }
        // Each copy is kept apart as a circle round its middle, reaching its farthest outline point, so it holds the
        // copy turned any way.
        let middle = (box.min + box.max) * 0.5
        let radius = sources.flatMap { $0.outlinePaths.flatMap { $0 } }.map { $0.distance(to: middle) }.max() ?? 0
        guard radius > 0.01 else { throw DesignError.invalid("The shapes to scatter have no size.") }
        let edges = rings.flatMap { ring in zip(ring, ring.dropFirst() + ring.prefix(1)).map { ($0, $1) } }
        let points = rings.flatMap { $0 }
        let low = Point(points.map(\.x).min()!, points.map(\.y).min()!), high = Point(points.map(\.x).max()!, points.map(\.y).max()!)
        var dice = FillStyles.Seeded(seed: settings.seed &* 0x9E3779B97F4A7C15 &+ 0x2545F4914F6CDD1D)
        // Biggest first: they're the hardest to fit, and small ones fill the gaps they leave.
        let scales = (0..<settings.copies).map { _ in (settings.smallest + (settings.largest - settings.smallest) * dice.unit()) / 100 }.sorted(by: >)
        var placed: [(center: Point, radius: Double, scale: Double, degrees: Double)] = []
        for scale in scales {
            let r = radius * scale
            // A few hundred tries per copy; a copy that finds no room is left out.
            for _ in 0..<300 {
                let p = Point(low.x + (high.x - low.x) * dice.unit(), low.y + (high.y - low.y) * dice.unit())
                let degrees = settings.turns ? dice.unit() * 360 : 0
                guard AreaGeometry.contains(p, rings: rings),
                      edges.allSatisfy({ p.distance(to: AreaGeometry.projection(p, $0.0, $0.1)) >= r + settings.gap }),
                      placed.allSatisfy({ p.distance(to: $0.center) >= r + $0.radius + settings.gap }) else { continue }
                placed.append((p, r, scale, degrees)); break
            }
        }
        guard !placed.isEmpty else { throw DesignError.invalid("No copies fit in that shape. Make them smaller, or the gap narrower.") }
        // Sewn from the copy nearest the area's top left, then each time on to the nearest copy not yet sewn.
        var order: [Int] = [], left = Set(placed.indices), at = Point(low.x, high.y)
        while let next = left.min(by: { placed[$0].center.distance(to: at) < placed[$1].center.distance(to: at) }) {
            order.append(next); left.remove(next); at = placed[next].center
        }
        let group = UUID()
        let sets = order.enumerated().map { k, index -> [RunObject] in
            let copy = placed[index]
            var made = Self.freshCopies(of: sources)
            for i in made.indices {
                // Sized round its middle, moved there, then turned (a fill's rows turn with it).
                made[i].transform { copy.center + ($0 - middle) * copy.scale }
                made[i].turn(by: copy.degrees, around: copy.center)
                made[i].name = "\(sources[i].name) \(k + 1)"
                made[i].groupID = group
            }
            return made
        }
        // Color blocks, as a wreath sews them.
        var blocks: [Range<Int>] = []
        for i in sources.indices {
            if let last = blocks.last, sources[last.lowerBound].color == sources[i].color { blocks[blocks.count - 1] = last.lowerBound..<(i + 1) }
            else { blocks.append(i..<(i + 1)) }
        }
        let ordered = blocks.flatMap { block in sets.flatMap { $0[block] } }
        let first = objects.firstIndex { ids.contains($0.id) && $0.id != areaID && !$0.locked }!
        let removed = objects[..<first].filter { $0.id == areaID }.count
        objects.removeAll { (ids.contains($0.id) && !$0.locked) || $0.id == areaID }
        objects.insert(contentsOf: ordered, at: min(first - removed, objects.count))
        return (ordered.map { $0.id }, placed.count)
    }
}
