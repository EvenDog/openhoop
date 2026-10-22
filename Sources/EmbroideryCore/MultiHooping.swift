// Multi-hooping: sewing a design bigger than the hoop in several hoopings, re-hooping the fabric between them.
// Each hooping is the design's own hoop placed somewhere over the design. Every object sews in the first hooping
// that holds all of its stitches, and each hooping becomes its own stitch plan (and machine file), shifted so the
// hooping's center is the hoop's center. Small alignment marks, sewn by both hoopings where they overlap, show
// where to line the fabric up after re-hooping.
import Foundation

/// One placement of the hoop over the design.
public struct Hooping: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    /// Where the hoop's center sits on the design, in mm.
    public var center: Point
    public init(center: Point) { self.center = center }
}

/// How the alignment marks look: a small square with an X through it, or a plus.
public enum AlignmentMarkStyle: String, Codable, CaseIterable, Sendable {
    case box, cross
    public var title: String { self == .box ? "Box" : "Cross" }
}

/// A design's hoopings, in the order they're sewn, and its alignment marks (nil for none).
public struct MultiHooping: Codable, Hashable, Sendable {
    public var hoopings: [Hooping]
    public var marks: AlignmentMarkStyle?
    public init(hoopings: [Hooping], marks: AlignmentMarkStyle? = .box) { self.hoopings = hoopings; self.marks = marks }
    public static let limit = 50
}

/// Which hooping sews each object.
public struct HoopingAssignment: Equatable, Sendable {
    /// For each hooping, the IDs of the objects it sews, in sewing order.
    public var objects: [[UUID]]
    /// Objects that fit no hooping, in sewing order. Nothing can be saved for the machine until they do.
    public var unplaced: [UUID]
    /// Objects that now sew on top of something they used to sew under, because they're in a later hooping.
    public var warnings: [String]
}

extension Design {
    /// The smallest overlap (mm) Auto Layout leaves between neighbouring hoopings: room for the alignment marks.
    public static let hoopingOverlap = 16.0
    /// Half the width of an alignment mark, in mm (the marks are 5 mm across).
    static let markRadius = 2.5
    /// How close (mm) design stitches may come to an alignment mark's middle before it looks for a clearer spot.
    static let markClearance = 3.5

    /// The blocks that must sew in the same hooping, as object IDs in sewing order: each letter (all its parts),
    /// each group, and each branch. Lettering is split by letter, so a word can cross hoopings but a letter can't.
    /// Unstitched objects (guide lines) aren't in any block.
    public var hoopingUnits: [[UUID]] {
        let sewn = objects.filter { $0.kind != .vector }
        // Union-find: each object starts as its own block, and objects that must stay together are joined.
        var parent = Array(sewn.indices)
        func root(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        func join(_ a: Int, _ b: Int) { parent[root(a)] = root(b) }
        var firstWith: [String: Int] = [:]
        for (i, object) in sewn.enumerated() {
            var keys: [String] = []
            if let lettering = object.lettering {
                // Letters share their word's group, so the group is ignored; the letter key keeps a letter's parts together.
                keys.append("letter \(lettering.id) \(object.letterKey.map(String.init) ?? "all")")
            } else if let group = object.groupID { keys.append("group \(group)") }
            if let branch = object.branchID { keys.append("branch \(branch)") }
            for key in keys { if let other = firstWith[key] { join(i, other) } else { firstWith[key] = i } }
        }
        var order: [Int] = [], members: [Int: [UUID]] = [:]
        for i in sewn.indices { let r = root(i); if members[r] == nil { order.append(r) }; members[r, default: []].append(sewn[i].id) }
        return order.map { members[$0]! }
    }

    /// The stitches each object sews in `plan`, by object ID.
    private static func stitchPoints(_ plan: StitchPlan) -> [UUID: [Point]] {
        var points: [UUID: [Point]] = [:]
        for command in plan.commands where command.op == .stitch { if let id = command.objectID { points[id, default: []].append(command.point) } }
        return points
    }

    /// Which hooping sews each object, given the design's stitches (`plan`, compiled from this design): each block of
    /// `hoopingUnits` goes to the first hooping whose sewing area holds all of its stitches.
    public func hoopingAssignment(plan: StitchPlan) -> HoopingAssignment {
        let hoopings = multiHooping?.hoopings ?? []
        let points = Self.stitchPoints(plan)
        var placed = Array(repeating: Set<UUID>(), count: hoopings.count), unplaced = Set<UUID>(), hoopingOf: [UUID: Int] = [:]
        for unit in hoopingUnits {
            let stitches = unit.flatMap { points[$0] ?? [] }
            guard !stitches.isEmpty else { continue }   // nothing sews (an empty object): no hooping needed
            if let index = hoopings.firstIndex(where: { hooping in stitches.allSatisfy { hoop.contains($0 - hooping.center) } }) {
                placed[index].formUnion(unit); for id in unit { hoopingOf[id] = index }
            } else { unplaced.formUnion(unit) }
        }
        // Sewing hooping by hooping can put an object on top of one it used to sew under; say so where they overlap.
        var warnings: [String] = []
        let boxes = points.mapValues { p in (min: Point(p.map(\.x).min()!, p.map(\.y).min()!), max: Point(p.map(\.x).max()!, p.map(\.y).max()!)) }
        let ordered = objects.filter { hoopingOf[$0.id] != nil }
        for (i, earlier) in ordered.enumerated() {
            for later in ordered[(i + 1)...] where hoopingOf[later.id]! < hoopingOf[earlier.id]! {
                guard let a = boxes[earlier.id], let b = boxes[later.id], a.min.x < b.max.x, b.min.x < a.max.x, a.min.y < b.max.y, b.min.y < a.max.y else { continue }
                warnings.append("\(earlier.name) now sews on top of \(later.name), because it's in a later hooping.")
            }
        }
        return HoopingAssignment(objects: placed.map { ids in objects.map(\.id).filter(ids.contains) },
                                 unplaced: objects.map(\.id).filter(unplaced.contains), warnings: warnings)
    }

    /// Auto Layout: the fewest hoopings, in rows from the top left, that cover everything that sews, each overlapping
    /// its neighbours by at least `hoopingOverlap` mm. Hoopings left with nothing to sew are dropped. Empty when
    /// nothing sews.
    public func autoHoopings(plan: StitchPlan) -> [Hooping] {
        let stitches = Self.stitchPoints(plan).values.flatMap { $0 }
        guard !stitches.isEmpty else { return [] }
        let low = Point(stitches.map(\.x).min()!, stitches.map(\.y).min()!), high = Point(stitches.map(\.x).max()!, stitches.map(\.y).max()!)
        /// Centers along one direction: one in the middle if it fits, otherwise evenly spaced from end to end.
        func centers(_ from: Double, _ to: Double, _ size: Double) -> [Double] {
            let span = to - from
            guard span > size else { return [(from + to) / 2] }
            let count = Int(ceil((span - Self.hoopingOverlap) / (size - Self.hoopingOverlap)))
            let step = (span - size) / Double(count - 1)
            return (0..<count).map { from + size / 2 + step * Double($0) }
        }
        let xs = centers(low.x, high.x, hoop.width), ys = centers(low.y, high.y, hoop.height)
        let grid = ys.reversed().flatMap { y in xs.map { x in Hooping(center: Point(x, y)) } }   // top row first
        var trial = self
        trial.multiHooping = MultiHooping(hoopings: grid, marks: multiHooping?.marks ?? .box)
        let used = trial.hoopingAssignment(plan: plan).objects
        return grid.indices.filter { !used[$0].isEmpty }.map { grid[$0] }
    }

    /// The alignment mark at `center` (mm) as a running line in `color` that starts at the mark's middle, so
    /// stepping the machine to its first stitch shows where the needle will land.
    static func alignmentMark(at center: Point, style: AlignmentMarkStyle, color: ThreadColor) -> RunObject {
        let r = markRadius
        let path: [Point]
        switch style {
        case .box:   // middle, round the square, then both diagonals (one edge is sewn twice to get there)
            let a = Point(-r, -r), b = Point(r, -r), c = Point(r, r), d = Point(-r, r)
            path = [Point(0, 0), a, b, c, d, a, c, b, d]
        case .cross:
            path = [Point(0, 0), Point(r, 0), Point(-r, 0), Point(0, 0), Point(0, r), Point(0, -r)]
        }
        var mark = RunObject(name: "Alignment mark", nodes: path.map { PathNode(center + $0) }, color: color)
        mark.stitchLength = 1.5
        return mark
    }

    /// Where the alignment marks between two hoopings go, in design mm: two marks at the far ends of the area both
    /// sew (one in its middle if that's short), each moved inward to the first spot clear of the design's stitches.
    /// Empty when the hoopings don't overlap enough to hold a mark.
    func alignmentMarkSpots(between first: Hooping, and second: Hooping, avoiding stitches: [Point]) -> [Point] {
        let inset = Self.markRadius + 1
        let low = Point(max(first.center.x, second.center.x) - hoop.width / 2 + inset, max(first.center.y, second.center.y) - hoop.height / 2 + inset)
        let high = Point(min(first.center.x, second.center.x) + hoop.width / 2 - inset, min(first.center.y, second.center.y) + hoop.height / 2 - inset)
        guard low.x <= high.x, low.y <= high.y else { return [] }
        let tall = high.y - low.y > high.x - low.x
        let middle = (low + high) * 0.5
        /// The spot `t` mm along the long side of the shared area.
        func spot(_ t: Double) -> Point { tall ? Point(middle.x, low.y + t) : Point(low.x + t, middle.y) }
        let length = tall ? high.y - low.y : high.x - low.x
        func fits(_ p: Point) -> Bool { hoop.contains(p - first.center) && hoop.contains(p - second.center) }
        func clear(_ p: Point) -> Bool { !stitches.contains { $0.distance(to: p) < Self.markClearance } }
        guard length >= 12 else { return [spot(length / 2)].filter(fits) }
        // Search inward from each end, up to the middle, a millimeter at a time.
        let fromStart = stride(from: 0.0, through: length / 2, by: 1).map(spot)
        let fromEnd = stride(from: length, through: length / 2, by: -1).map(spot)
        return [fromStart, fromEnd].compactMap { candidates in
            candidates.first { fits($0) && clear($0) } ?? candidates.first(where: fits)
        }
    }

    /// One stitch plan per hooping, in sewing order, each shifted so its hooping's center is the hoop's center:
    /// the alignment marks it shares with an earlier hooping (then a stop, to check they sit on the marks that
    /// hooping sewed), the basting box if it's on, its objects, and the marks it shares with later hoopings.
    /// A hooping's marks are shared with the earlier hooping it overlaps most. `plan` is the whole design compiled.
    /// Throws when an object fits no hooping.
    public func hoopingPlans(plan: StitchPlan) throws -> [StitchPlan] {
        guard let layout = multiHooping, !layout.hoopings.isEmpty else { throw DesignError.invalid("This design has no hoopings.") }
        let assignment = hoopingAssignment(plan: plan)
        if let id = assignment.unplaced.first, let object = objects.first(where: { $0.id == id }) {
            throw DesignError.invalid("\(object.name) fits no hooping. Move a hooping, add one, or cut \(object.name) smaller.")
        }
        let hoopings = layout.hoopings
        let stitches = Self.stitchPoints(plan).values.flatMap { $0 }
        // Each hooping after the first lines up with the earlier hooping it overlaps most.
        func overlap(_ a: Hooping, _ b: Hooping) -> Double {
            max(0, hoop.width - abs(a.center.x - b.center.x)) * max(0, hoop.height - abs(a.center.y - b.center.y))
        }
        var marks: [Int: [Point]] = [:], partner: [Int: Int] = [:]
        if layout.marks != nil {
            for j in hoopings.indices.dropFirst() {
                guard let i = hoopings.indices.prefix(j).max(by: { overlap(hoopings[$0], hoopings[j]) < overlap(hoopings[$1], hoopings[j]) }),
                      overlap(hoopings[i], hoopings[j]) > 0 else { continue }
                let spots = alignmentMarkSpots(between: hoopings[i], and: hoopings[j], avoiding: stitches)
                if !spots.isEmpty { marks[j] = spots; partner[j] = i }
            }
        }
        return try hoopings.indices.map { index in
            let center = hoopings[index].center
            var part = self
            part.multiHooping = nil; part.cachedPlan = nil; part.artwork = nil; part.guides = nil
            let ids = Set(assignment.objects[index])
            part.objects = objects.filter { ids.contains($0.id) }
            part.move(Set(part.objects.map(\.id)), by: Point(0, 0) - center)
            guard let firstColor = part.objects.first?.color, let lastColor = part.objects.last?.color else { return StitchPlan() }
            let box = part.bastingBox
            part.basting = nil   // put back in by hand below, after the starting marks
            let style = layout.marks ?? .box
            var start = (marks[index] ?? []).map { Self.alignmentMark(at: $0 - center, style: style, color: firstColor) }
            if !start.isEmpty { start[start.count - 1].stopAfter = true }
            let end = marks.filter { partner[$0.key] == index }.sorted { $0.key < $1.key }.flatMap { $0.value }
                .map { Self.alignmentMark(at: $0 - center, style: style, color: lastColor) }
            part.objects = start + (box.map { [$0] } ?? []) + part.objects + end
            return try StitchEngine.compile(part)
        }
    }
}
