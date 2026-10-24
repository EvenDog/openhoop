// Wreath and kaleidoscope: copies of a selection placed all the way round a center point, each turned a further
// step, like the petals of a flower. In a kaleidoscope every other copy is a mirror image, so neighbours face each
// other in pairs. The result is one group, sewn one thread color at a time so the copies add no thread changes.
import Foundation

extension Design {
    /// The most copies a wreath can have (the originals count as the first).
    public static let wreathCopies = 2...100

    /// Places copies of the objects in `ids` round `center`: `copies` in all, counting the originals as the first, each
    /// turned a further 360 / `copies` degrees. With `mirrored` (kaleidoscope), every other copy is the originals'
    /// mirror image, which needs an even number of copies. Locked objects are left out.
    ///
    /// The originals and the copies become one new group, put in the sewing order where the first original was, sewn in
    /// color blocks: each run of same-colored objects in the originals is sewn in every copy (going round the circle)
    /// before the next run starts. So the wreath changes thread no more often than the originals did, and what lay on
    /// top in the originals still lies on top. Returns the ids of every object in the wreath, in sewing order.
    @discardableResult
    public mutating func wreath(_ ids: Set<UUID>, copies: Int, around center: Point, mirrored: Bool) throws -> [UUID] {
        let sources = objects.filter { ids.contains($0.id) && !$0.locked }
        guard let firstIndex = objects.firstIndex(where: { ids.contains($0.id) && !$0.locked }) else { throw DesignError.invalid("Select the objects to repeat round the wreath.") }
        guard Self.wreathCopies.contains(copies) else { throw DesignError.invalid("A wreath has between 2 and 100 copies.") }
        guard !mirrored || copies % 2 == 0 else { throw DesignError.invalid("A kaleidoscope needs an even number of copies, so the mirrored ones pair up.") }
        let step = 360.0 / Double(copies)
        // Mirrored copies are reflected across the line halfway to the next copy, measured from where the originals sit
        // (seen from the center), so each mirror image lands one step round, facing back toward the original.
        let box = bounds(of: Set(sources.map(\.id))) ?? (center, center)
        let offset = (box.min + box.max) * 0.5 - center
        let sitting = offset.distance(to: Point(0, 0)) < 1e-9 ? 0 : atan2(offset.y, offset.x) * 180 / .pi
        // Every copy in its own place, as a whole set of objects, with fresh ids like pasted ones.
        let group = UUID()
        var sets: [[RunObject]] = []
        for k in 0..<copies {
            var made = sources
            if k > 0 {
                made = Self.freshCopies(of: sources)
                let turns = mirrored && k % 2 == 1 ? Double(k - 1) * step : Double(k) * step
                for i in made.indices {
                    if mirrored && k % 2 == 1 { made[i].reflect(across: center, at: sitting + step / 2) }
                    made[i].turn(by: turns, around: center)
                    made[i].name = "\(sources[i].name) \(k + 1)"
                }
            }
            for i in made.indices { made[i].groupID = group }
            sets.append(made)
        }
        // Color blocks: runs of neighbouring originals sharing a thread, each sewn copy by copy.
        var blocks: [Range<Int>] = []
        for i in sources.indices {
            if let last = blocks.last, sources[last.lowerBound].color == sources[i].color { blocks[blocks.count - 1] = last.lowerBound..<(i + 1) }
            else { blocks.append(i..<(i + 1)) }
        }
        let ordered = blocks.flatMap { block in sets.flatMap { $0[block] } }
        objects.removeAll { ids.contains($0.id) && !$0.locked }
        objects.insert(contentsOf: ordered, at: min(firstIndex, objects.count))
        return ordered.map(\.id)
    }

    /// Copies of `objects` with fresh ids, kept together the way `paste` keeps them (a new lettering or branch for
    /// each one copied, guide lines still guiding their copied fill), without adding them anywhere.
    private static func freshCopies(of objects: [RunObject]) -> [RunObject] {
        var scratch = Design()
        scratch.paste(ObjectClipboard(objects: objects))
        return scratch.objects
    }
}

extension RunObject {
    /// Turns the object by `degrees` (positive is counterclockwise) around `center`, as Rotate does: a fill's rows
    /// turn with it.
    fileprivate mutating func turn(by degrees: Double, around center: Point) {
        guard degrees != 0 else { return }
        let radians = degrees * .pi / 180, c = cos(radians), s = sin(radians)
        transform { p in let q = p - center; return center + Point(q.x * c - q.y * s, q.x * s + q.y * c) }
        if kind == .fill { let angle = settings.angle; digitizing?.angle = Lettering.turned(angle, by: degrees) }
    }

    /// Mirrors the object across the line through `center` at `degrees`, as Mirror does: a fill's rows are mirrored
    /// with it.
    fileprivate mutating func reflect(across center: Point, at degrees: Double) {
        let twice = 2 * degrees * .pi / 180, c = cos(twice), s = sin(twice)
        transform { p in let q = p - center; return center + Point(q.x * c + q.y * s, q.x * s - q.y * c) }
        // Rows at angle a, mirrored across a line at angle m, run at 2m − a.
        if kind == .fill { let angle = settings.angle; digitizing?.angle = Lettering.turned(-angle, by: 2 * degrees) }
    }
}
