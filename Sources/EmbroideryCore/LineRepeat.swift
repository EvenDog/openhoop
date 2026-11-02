// Copies along a line: copies of some shapes set out evenly along an open line, like leaves along a vine or a
// border of hearts. The line becomes an unstitched guide (drawn dashed) that remembers the settings. Reshape it, or
// change a setting, and the copies are built again from the first copy, so changes made to that copy (its color,
// stitches or size) carry over to all of them.
import Foundation

/// The settings of a set of copies along a line, kept on its guide line (`RunObject.lineRepeat`).
public struct LineRepeat: Codable, Hashable, Sendable {
    /// Where each copy sits: on the line, beside it on one side, or on alternate sides. Above is the left side
    /// looking along the line the way it was drawn (above, for a line drawn left to right).
    public enum Placement: String, Codable, CaseIterable, Sendable {
        case center, above, below, alternate
        public var title: String { rawValue.capitalized }
    }
    /// Ties the guide to its copies (`RepeatCopy.id`).
    public var id = UUID()
    /// How many copies, spread evenly from one end of the line to the other.
    public var copies = 5
    /// True when each copy turns to follow the line's direction where it sits; false keeps them all upright.
    public var turnsWithLine = true
    public var placement = Placement.center
    /// True when every other copy is mirrored across the line.
    public var mirrorsEveryOther = false
    /// The guide's path (mm) when the copies were last built. It moves with the guide, so moving everything together
    /// changes nothing; when the guide is reshaped it no longer matches, and the copies are built again. nil (after
    /// a setting changes) builds them again too.
    public var path: [Point]?
    public static let copyRange = 1...200
    public init(id: UUID = UUID(), copies: Int = 5) { self.id = id; self.copies = copies }
    var isValid: Bool { Self.copyRange.contains(copies) }
}

/// On each object of a copy along a line: which set of copies it belongs to, which copy it's part of (0 is the
/// first along the line), its name without the copy number, and three markers that move, turn, mirror and resize
/// with it, recording where the copy sits and which way it faces. `anchor` is the copy's middle, `along` 10 mm
/// along its own right and `up` 10 mm along its own up.
public struct RepeatCopy: Codable, Hashable, Sendable {
    public var id: UUID
    public var index: Int
    public var name: String
    public var anchor: Point, along: Point, up: Point
    /// Moves the markers with the object (called from RunObject.transform).
    mutating func transform(_ body: (Point) -> Point) { anchor = body(anchor); along = body(along); up = body(up) }
}

/// A place and a way of facing: an origin, a unit direction to the right and a unit direction up (at right angles,
/// up being to the right's left, or to its right when mirrored).
struct RepeatFrame {
    var origin: Point, right: Point, up: Point
    /// The frame the markers record, ignoring any stretching: just where the copy is, which way it turns and whether
    /// it's mirrored.
    init(_ copy: RepeatCopy) {
        let along = copy.along - copy.anchor, upward = copy.up - copy.anchor
        let length = max(along.distance(to: Point(0, 0)), 1e-9)
        right = along * (1 / length)
        let mirrored = along.x * upward.y - along.y * upward.x < 0
        up = mirrored ? Point(right.y, -right.x) : Point(-right.y, right.x)
        origin = copy.anchor
    }
    init(origin: Point, right: Point, up: Point) { self.origin = origin; self.right = right; self.up = up }
    /// A point in this frame (x to the right, y up) where it lands in the design.
    func place(_ p: Point) -> Point { origin + right * p.x + up * p.y }
    /// A point in the design as x and y in this frame.
    func local(_ p: Point) -> Point { let d = p - origin; return Point(d.x * right.x + d.y * right.y, d.x * up.x + d.y * up.y) }
}

extension RunObject {
    /// Moves the object from where it sits in `from` to the same place in `to`: moved, turned and mirrored, never
    /// stretched. A fill's rows turn with it.
    mutating func move(from: RepeatFrame, to: RepeatFrame) {
        transform { to.place(from.local($0)) }
        guard kind == .fill else { return }
        let a = settings.angle * .pi / 180, direction = from.local(from.origin + Point(cos(a), sin(a)))
        let turned = to.place(direction) - to.origin
        digitizing?.angle = Lettering.turned(atan2(turned.y, turned.x) * 180 / .pi, by: 0)
    }
}

extension Design {
    /// Copies along a line: sets out `copies` copies of the objects in `ids` evenly along the open line `lineID`,
    /// which becomes their unstitched guide. The copies and the guide make one group, sewn one thread color at a time
    /// like a wreath. Returns the new set's id. Throws, saying why, when the selection isn't some shapes and an open
    /// line, or the shapes are already copies along a line.
    @discardableResult
    public mutating func repeatAlongLine(_ ids: Set<UUID>, line lineID: UUID, copies: Int = 5) throws -> UUID {
        let sources = objects.filter { ids.contains($0.id) && $0.id != lineID && !$0.locked }
        guard !sources.isEmpty else { throw DesignError.invalid("Select the shapes to repeat and an open line to set them along.") }
        guard !sources.contains(where: { $0.repeatCopy != nil || $0.lineRepeat != nil }) else {
            throw DesignError.invalid("Some of those are already copies along a line. Break them apart first (Copies along line, in Properties).")
        }
        guard LineRepeat.copyRange.contains(copies) else { throw DesignError.invalid("Copies along a line can number 1 to 200.") }
        let id = UUID()
        var line = try takeGuide(lineID, for: id)
        line.name = "Copies · line"; line.lineRepeat = LineRepeat(id: id, copies: copies)
        // The shapes become the first copy, as they are: their markers sit at their middle, facing upright.
        guard let box = bounds(of: Set(sources.map(\.id))) else { throw DesignError.invalid("Select the shapes to repeat.") }
        let middle = (box.min + box.max) * 0.5
        let at = objects.firstIndex { ids.contains($0.id) && $0.id != lineID && !$0.locked }!
        let first = sources.map { o -> RunObject in
            var copy = o
            copy.repeatCopy = RepeatCopy(id: id, index: 0, name: o.name, anchor: middle, along: middle + Point(10, 0), up: middle + Point(0, 10))
            return copy
        }
        objects.removeAll { ids.contains($0.id) && $0.id != lineID && !$0.locked }
        objects.insert(contentsOf: first + [line], at: min(at, objects.count))
        try rebuildRepeat(id)
        return id
    }

    /// Changes the settings of the copies along a line `id`; they're built again after the edit (syncGuides).
    public mutating func setLineRepeat(_ id: UUID, _ body: (inout LineRepeat) -> Void) {
        guard let g = objects.firstIndex(where: { $0.lineRepeat?.id == id }) else { return }
        body(&objects[g].lineRepeat!)
        objects[g].lineRepeat!.path = nil
    }

    /// Break Apart: the copies along a line `id` become ordinary objects (still grouped) and its guide a plain
    /// unstitched line.
    public mutating func breakApartRepeat(_ id: UUID) {
        for i in objects.indices where objects[i].repeatCopy?.id == id { objects[i].repeatCopy = nil }
        for i in objects.indices where objects[i].lineRepeat?.id == id { objects[i].lineRepeat = nil; objects[i].guideFor = nil }
    }

    /// Builds the copies along a line `id` again, along its guide's current path, from its first copy (the lowest
    /// copy number still there). The old copies are replaced by new objects where the first of them was, with the
    /// guide just after them.
    mutating func rebuildRepeat(_ id: UUID) throws {
        guard let g = objects.firstIndex(where: { $0.lineRepeat?.id == id }) else { return }
        let spec = objects[g].lineRepeat!, path = objects[g].outlinePaths.first ?? []
        let members = objects.filter { $0.repeatCopy?.id == id }
        guard let lowest = members.map({ $0.repeatCopy!.index }).min() else { throw DesignError.invalid("These copies along a line have no copies left.") }
        guard let places = Self.places(along: path, count: spec.copies) else { throw DesignError.invalid("The line is too short to set copies along.") }
        // The motif: the first copy moved back from where it sits to the origin, upright and not mirrored, then
        // centered there. Copies made from it start without a set, so pasting them doesn't link them to anything.
        let upright = RepeatFrame(origin: Point(0, 0), right: Point(1, 0), up: Point(0, 1))
        var motif = members.filter { $0.repeatCopy!.index == lowest }.map { o -> RunObject in
            var m = o; m.move(from: RepeatFrame(o.repeatCopy!), to: upright); m.repeatCopy = nil; return m
        }
        let names = members.filter { $0.repeatCopy!.index == lowest }.map { $0.repeatCopy!.name }
        var scratch = Design(); scratch.objects = motif
        guard let box = scratch.bounds(of: Set(motif.map(\.id))) else { return }
        let middle = (box.min + box.max) * 0.5, half = (box.max.y - box.min.y) / 2
        for i in motif.indices { motif[i].transform { $0 - middle } }
        // Each copy in its own place, as a whole set of objects with fresh ids, like pasted ones.
        let group = objects[g].groupID ?? UUID()
        var sets: [[RunObject]] = []
        for (k, place) in places.enumerated() {
            let right = spec.turnsWithLine ? place.direction : Point(1, 0), up = Point(-right.y, right.x)
            let side: Double
            switch spec.placement {
            case .center: side = 0
            case .above: side = half
            case .below: side = -half
            case .alternate: side = k % 2 == 0 ? half : -half
            }
            let origin = place.point + up * side
            let frame = RepeatFrame(origin: origin, right: right, up: spec.mirrorsEveryOther && k % 2 == 1 ? up * -1 : up)
            var made = Self.freshCopies(of: motif)
            for i in made.indices {
                made[i].move(from: upright, to: frame)
                made[i].name = "\(names[i]) \(k + 1)"
                made[i].repeatCopy = RepeatCopy(id: id, index: k, name: names[i], anchor: origin, along: frame.place(Point(10, 0)), up: frame.place(Point(0, 10)))
                made[i].groupID = group
            }
            sets.append(made)
        }
        // Color blocks, as a wreath sews them: each run of same-colored parts is sewn in every copy along the line
        // before the next run starts.
        var blocks: [Range<Int>] = []
        for i in motif.indices {
            if let last = blocks.last, motif[last.lowerBound].color == motif[i].color { blocks[blocks.count - 1] = last.lowerBound..<(i + 1) }
            else { blocks.append(i..<(i + 1)) }
        }
        let ordered = blocks.flatMap { block in sets.flatMap { $0[block] } }
        var guide = objects[g]
        guide.groupID = group; guide.lineRepeat!.path = path
        let at = objects.firstIndex { $0.repeatCopy?.id == id || $0.lineRepeat?.id == id }!
        objects.removeAll { $0.repeatCopy?.id == id || $0.lineRepeat?.id == id }
        objects.insert(contentsOf: ordered + [guide], at: min(at, objects.count))
    }

    /// `count` places spread evenly along `path` from one end to the other (one copy sits in the middle), each with
    /// the line's direction there as a unit step. The direction is taken over a millimeter either side, so a curve's
    /// short straight pieces don't make copies wobble. nil for a path with no length.
    static func places(along path: [Point], count: Int) -> [(point: Point, direction: Point)]? {
        var lengths = [0.0]
        for (a, b) in zip(path, path.dropFirst()) { lengths.append(lengths.last! + a.distance(to: b)) }
        guard let total = lengths.last, total > 0.01, count >= 1 else { return nil }
        /// The point `s` mm along the path (clamped to its ends).
        func point(at s: Double) -> Point {
            let s = min(max(s, 0), total)
            let k = max(1, lengths.firstIndex { $0 >= s } ?? lengths.count - 1)
            let piece = lengths[k] - lengths[k - 1]
            return piece < 1e-9 ? path[k] : path[k - 1] + (path[k] - path[k - 1]) * ((s - lengths[k - 1]) / piece)
        }
        return (0..<count).map { k in
            let s = count == 1 ? total / 2 : total * Double(k) / Double(count - 1)
            let step = min(1, total / 2), d = point(at: s + step) - point(at: s - step)
            let length = d.distance(to: Point(0, 0))
            return (point(at: s), length < 1e-9 ? Point(1, 0) : d * (1 / length))
        }
    }
}
