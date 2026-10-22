// Exact arranging for the precision bar: the box around some objects,
// moving them by an exact amount, and turning them by any angle with their fill rows turning along. Also sewing
// objects in the order they were clicked, dragging them to a new place in the sewing order, gathering each thread's
// objects together, lining them up, and skewing them.
import Foundation

/// The ways Align lines objects up: by an edge, or by their centers on a vertical or horizontal line.
public enum ObjectAlignment: Sendable { case left, centersVertically, right, top, centersHorizontally, bottom, centers }

extension Design {
    /// The box around the outlines of the objects in `ids` (mm), or nil if they have no points.
    public func bounds(of ids: Set<UUID>) -> (min: Point, max: Point)? {
        let points = objects.filter { ids.contains($0.id) }.flatMap { $0.outlinePaths.flatMap { $0 } }
        guard let first = points.first else { return nil }
        return (points.reduce(first) { Point(Swift.min($0.x, $1.x), Swift.min($0.y, $1.y)) },
                points.reduce(first) { Point(Swift.max($0.x, $1.x), Swift.max($0.y, $1.y)) })
    }

    /// Sequence by Selection Order: the objects in `ids` sew one after another in that order, starting where the
    /// earliest of them sewed before. The other objects keep their order around them.
    public mutating func sequence(_ ids: [UUID]) {
        guard let start = objects.firstIndex(where: { ids.contains($0.id) }) else { return }
        let picked = ids.compactMap { id in objects.first { $0.id == id } }
        objects.removeAll { ids.contains($0.id) }
        objects.insert(contentsOf: picked, at: start)   // everything before `start` was left in place, so it's still there
    }

    /// Runs of objects that must stay together in the sewing order, as ranges of `objects`: a group's (or lettering's)
    /// consecutive members, and a branch's consecutive objects (joined by travel instead of trims). Every other object
    /// is a run of one.
    public var sewingUnits: [Range<Int>] {
        func together(_ a: RunObject, _ b: RunObject) -> Bool {
            (a.groupID != nil && a.groupID == b.groupID) || (a.lettering != nil && a.lettering?.id == b.lettering?.id) || (a.branchID != nil && a.branchID == b.branchID)
        }
        var units: [Range<Int>] = [], start = 0
        for index in objects.indices.dropFirst() where !together(objects[index - 1], objects[index]) { units.append(start..<index); start = index }
        if !objects.isEmpty { units.append(start..<objects.count) }
        return units
    }

    /// Drag in the sewing order list: the objects in `ids` (in their present order) move to sew just before the
    /// object now at `index` (`objects.count`: at the end). A place inside a group, lettering or branch moves to that
    /// unit's end, so it's never split. Returns false when nothing moves.
    @discardableResult public mutating func moveInSewingOrder(_ ids: Set<UUID>, to index: Int) -> Bool {
        // Where it lands, counted among the objects that stay, pushed past any unit it would fall inside.
        var place = Swift.min(Swift.max(0, index), objects.count)
        if let unit = sewingUnits.first(where: { $0.lowerBound < place && place < $0.upperBound }) { place = unit.upperBound }
        let staying = objects.filter { !ids.contains($0.id) }, moving = objects.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return false }
        let before = objects[..<place].filter { !ids.contains($0.id) }.count
        let next = Array(staying[..<before]) + moving + Array(staying[before...])
        guard next.map(\.id) != objects.map(\.id) else { return false }
        objects = next
        return true
    }

    /// Sequence by Color: each thread's objects sew together, the threads in the order they first appear, so the
    /// machine changes thread as few times as possible. Within a thread, objects keep their order. Groups, lettering
    /// and branches stay whole, sewn with the thread of their first object. Returns false when nothing moves.
    @discardableResult public mutating func sequenceByColor() -> Bool {
        let units = sewingUnits
        var colors: [ThreadColor] = []
        for unit in units where !colors.contains(objects[unit.lowerBound].color) { colors.append(objects[unit.lowerBound].color) }
        let next = colors.flatMap { color in units.filter { objects[$0.lowerBound].color == color }.flatMap { objects[$0] } }
        guard next.map(\.id) != objects.map(\.id) else { return false }
        objects = next
        return true
    }

    /// The objects in `ids` as the blocks that arranging moves: each group's members together (in the order the
    /// first of them appears in `ids`), every other object on its own.
    public func arrangeUnits(_ ids: [UUID]) -> [[UUID]] {
        var units: [[UUID]] = [], unitOfGroup: [UUID: Int] = [:]
        for id in ids {
            guard let object = objects.first(where: { $0.id == id }) else { continue }
            if let group = object.groupID, let index = unitOfGroup[group] { units[index].append(id); continue }
            if let group = object.groupID { unitOfGroup[group] = units.count }
            units.append([id])
        }
        return units
    }

    /// Align: lines up the objects in `ids` with the last one (the last one selected stays
    /// put). Groups move as one block; blocks with a locked object stay put.
    public mutating func align(_ ids: [UUID], _ alignment: ObjectAlignment) {
        let units = arrangeUnits(ids)
        guard let reference = units.last, let target = bounds(of: Set(reference)) else { return }
        for unit in units.dropLast() where !objects.contains(where: { unit.contains($0.id) && $0.locked }) {
            guard let box = bounds(of: Set(unit)) else { continue }
            func middle(_ b: (min: Point, max: Point)) -> Point { (b.min + b.max) * 0.5 }
            let delta: Point
            switch alignment {
            case .left: delta = Point(target.min.x - box.min.x, 0)
            case .right: delta = Point(target.max.x - box.max.x, 0)
            case .centersVertically: delta = Point(middle(target).x - middle(box).x, 0)   // centers on one up-and-down line
            case .top: delta = Point(0, target.max.y - box.max.y)   // up is +y
            case .bottom: delta = Point(0, target.min.y - box.min.y)
            case .centersHorizontally: delta = Point(0, middle(target).y - middle(box).y)   // centers on one level line
            case .centers: delta = middle(target) - middle(box)
            }
            move(Set(unit), by: delta)
        }
    }

    /// Space Evenly Across (or Down): leaves the leftmost and rightmost (or lowest and highest) of three or more
    /// blocks where they are and moves the others so the gaps between neighbours are equal. Blocks with a locked
    /// object stay put, which can leave the gaps uneven.
    public mutating func spaceEvenly(_ ids: [UUID], across: Bool) {
        let boxes = arrangeUnits(ids).compactMap { unit in bounds(of: Set(unit)).map { (unit: unit, box: $0) } }
        guard boxes.count >= 3 else { return }
        func low(_ b: (min: Point, max: Point)) -> Double { across ? b.min.x : b.min.y }
        func size(_ b: (min: Point, max: Point)) -> Double { across ? b.max.x - b.min.x : b.max.y - b.min.y }
        let sorted = boxes.sorted { low($0.box) < low($1.box) }
        let first = sorted.first!.box, last = sorted.last!.box
        let gap = ((across ? last.max.x : last.max.y) - low(first) - sorted.map { size($0.box) }.reduce(0, +)) / Double(sorted.count - 1)
        var next = low(first) + size(first) + gap   // where the next block's low edge goes
        for entry in sorted.dropFirst().dropLast() {
            let shift = next - low(entry.box)
            if !objects.contains(where: { entry.unit.contains($0.id) && $0.locked }) { move(Set(entry.unit), by: across ? Point(shift, 0) : Point(0, shift)) }
            next += size(entry.box) + gap
        }
    }

    /// Moves the objects in `ids` by `delta` (mm).
    public mutating func move(_ ids: Set<UUID>, by delta: Point) {
        for i in objects.indices where ids.contains(objects[i].id) { objects[i].transform { $0 + delta } }
    }

    /// Skew: leans the objects in `ids` sideways by `degrees` (positive leans the top to the right, like italics),
    /// keeping the level line through `center` in place. Points keep their height and slide across in proportion
    /// to it. Fill rows lean along, so they keep their look.
    public mutating func skew(_ ids: Set<UUID>, by degrees: Double, around center: Point) {
        let slant = tan(degrees * .pi / 180)
        for i in objects.indices where ids.contains(objects[i].id) {
            objects[i].transform { p in Point(p.x + (p.y - center.y) * slant, p.y) }
            if objects[i].kind == .fill {
                // The rows' direction (cos, sin) slides the same way: across by its height times the slant.
                let radians = objects[i].settings.angle * .pi / 180
                objects[i].digitizing?.angle = atan2(sin(radians), cos(radians) + sin(radians) * slant) * 180 / .pi
            }
            objects[i].refreshStitchEdits()
        }
    }

    /// Turns the objects in `ids` by `degrees` (positive is counterclockwise) around `center`. Everything that
    /// belongs to an object turns with it: nodes and handles, holes, start and end points, a radial fill's center,
    /// lettering markers and imported stitches; fill rows turn by the same angle so they keep their look.
    public mutating func rotate(_ ids: Set<UUID>, by degrees: Double, around center: Point) {
        let radians = degrees * .pi / 180, c = cos(radians), s = sin(radians)
        for i in objects.indices where ids.contains(objects[i].id) {
            objects[i].transform { p in
                let q = p - center
                return center + Point(q.x * c - q.y * s, q.x * s + q.y * c)
            }
            if objects[i].kind == .fill { let angle = objects[i].settings.angle; objects[i].digitizing?.angle = Lettering.turned(angle, by: degrees) }
            objects[i].refreshStitchEdits()   // edited stitches turned with it
        }
    }
}
