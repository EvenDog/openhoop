// Break Apart: splits composite objects into their parts. Lettering and monograms become plain shapes (still
// grouped) that can be reshaped one by one; copies along a line become ordinary objects; and a fill with holes gets a
// new fill in each hole, with the fill's settings and color, so every piece can be recolored, moved or deleted on its
// own. Nothing is sewn twice: the original fill keeps its holes.
import Foundation

/// What Break Apart did, for the status line: how many of each kind it split, and the new hole fills' IDs.
public struct BreakApartResult: Equatable, Sendable {
    public var lettering = 0, monograms = 0, copies = 0, holeFills: [UUID] = []
    public var isEmpty: Bool { lettering == 0 && monograms == 0 && copies == 0 && holeFills.isEmpty }
}

extension Design {
    /// Break Apart on the objects in `ids`. A selected letter, monogram part or copy breaks apart the whole lettering,
    /// monogram or set of copies it belongs to. Fills with holes that are none of those (and aren't locked) get a new
    /// fill in each hole, placed right after them in the sewing order and in the same group.
    @discardableResult public mutating func breakApart(_ ids: Set<UUID>) -> BreakApartResult {
        var result = BreakApartResult()
        let chosen = objects.filter { ids.contains($0.id) }
        // Lettering: the letters forget their recipe (and which letter they were), so the text can't be edited.
        let letterings = Set(chosen.compactMap { $0.lettering?.id })
        for i in objects.indices where objects[i].lettering.map({ letterings.contains($0.id) }) == true {
            objects[i].lettering = nil; objects[i].letterKey = nil
        }
        result.lettering = letterings.count
        // Monograms: every part forgets the recipe, so it can't be rebuilt as a monogram.
        let monograms = Set(chosen.compactMap { $0.monogram?.id })
        for i in objects.indices where objects[i].monogram.map({ monograms.contains($0.id) }) == true { objects[i].monogram = nil }
        result.monograms = monograms.count
        // Copies along a line, whether a copy or the line was picked.
        let copies = Set(chosen.compactMap { $0.repeatCopy?.id ?? $0.lineRepeat?.id })
        for id in copies { breakApartRepeat(id) }
        result.copies = copies.count
        // Fills with holes. Each new fill goes in after the ones before it, so they keep the holes' order.
        let composite = { (o: RunObject) in o.lettering != nil || o.monogram != nil || o.repeatCopy != nil || o.lineRepeat != nil }
        for parent in chosen where parent.kind == .fill && !parent.locked && !composite(parent) && !(parent.holes ?? []).isEmpty {
            guard var index = objects.firstIndex(where: { $0.id == parent.id }) else { continue }
            for (number, hole) in parent.holes!.enumerated() where hole.count >= 3 {
                let piece = Self.holeFill(hole, of: parent, number: number + 1)
                index += 1
                objects.insert(piece, at: index)
                result.holeFills.append(piece.id)
            }
        }
        return result
    }

    /// A new fill for one hole of `parent`: the hole's outline (turned to run counterclockwise, like an outer edge),
    /// with the parent's settings, color and group, but none of its links or placed points (start and end, stitch
    /// edits, guides, blends, stitch angle lines, the radial center), which belong to the parent's shape.
    static func holeFill(_ hole: [PathNode], of parent: RunObject, number: Int) -> RunObject {
        var piece = parent
        piece.id = UUID(); piece.name = "\(parent.name) hole \(number)"
        let clockwise = AreaGeometry.area(AreaGeometry.ring(hole)) < 0
        piece.nodes = clockwise ? RunObject.reversedPath(hole, satin: false) : hole
        piece.holes = nil; piece.entry = nil; piece.exit = nil; piece.stitchEdits = nil; piece.branchID = nil; piece.connector = nil
        piece.guideFor = nil; piece.blendOf = nil; piece.lettering = nil; piece.letterKey = nil; piece.monogram = nil
        piece.lineRepeat = nil; piece.repeatCopy = nil
        piece.digitizing?.radialCenter = nil; piece.digitizing?.angleLines = nil; piece.digitizing?.blendFade = nil
        // A guided fill follows a guide line drawn for the parent; the piece has none, so it's a plain tatami.
        if piece.digitizing?.fillStyle == .guided { piece.digitizing?.fillStyle = nil }
        return piece
    }
}
