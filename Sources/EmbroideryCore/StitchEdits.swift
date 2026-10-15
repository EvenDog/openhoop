// Edit Stitch: stitches moved, added or deleted by hand. An object keeps its settings and remembers
// its edited stitches together with a fingerprint of everything they were made from. While the fingerprint still
// matches, the edited stitches sew; once the shape or a setting changes, fresh stitches replace them (the app says
// so, and Undo brings them back). Moving, turning, mirroring, resizing or skewing the whole object carries the
// edited stitches along with it.
import Foundation

/// An object's stitches as edited by hand: its sections (runs of needle points), and the fingerprint of the object
/// they were made from.
public struct StitchEdits: Codable, Hashable, Sendable {
    public struct Section: Codable, Hashable, Sendable {
        public var points: [Point]
        public var underlay: Bool
        public var joined: Bool
        public init(points: [Point], underlay: Bool = false, joined: Bool = false) { self.points = points; self.underlay = underlay; self.joined = joined }
    }
    public var sections: [Section]
    public var signature: String
    public init(sections: [Section], signature: String) { self.sections = sections; self.signature = signature }
    /// The edited stitches in the stitch engine's form.
    var stitches: ObjectStitches { ObjectStitches(sections: sections.map { StitchSection($0.points, underlay: $0.underlay, joined: $0.joined) }) }
}

extension RunObject {
    /// A fingerprint of everything an object's stitches are worked out from: its shape, stitch type and settings,
    /// start and end. Its name, thread, lock, grouping, ties and trims don't change where the needle goes, so they're
    /// left out. (A hash of the object written out as text, the same every time the app runs.)
    public var stitchSignature: String {
        var recipe = self
        recipe.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        recipe.name = ""; recipe.color = ThreadColor.palette[0]; recipe.visible = true; recipe.locked = false
        recipe.tieIn = true; recipe.tieOut = true; recipe.trimAfter = true; recipe.stopAfter = false
        recipe.groupID = nil; recipe.branchID = nil; recipe.lettering = nil; recipe.monogram = nil; recipe.stitchEdits = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var hash: UInt64 = 0xcbf29ce484222325   // FNV-1a, a simple, well-known text hash
        for byte in (try? encoder.encode(recipe)) ?? Data() { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
    /// True when the object has stitch edits made from what it is now, so they sew instead of fresh stitches.
    public var hasCurrentStitchEdits: Bool { stitchEdits.map { $0.signature == stitchSignature } ?? false }
    /// After a change that carried the edited stitches along (moving, turning, mirroring, resizing, skewing),
    /// marks them as made from the object as it is now.
    public mutating func refreshStitchEdits() { if stitchEdits != nil { stitchEdits!.signature = stitchSignature } }
}

extension Design {
    /// Forgets stitch edits that no longer match their objects (the shape or a setting changed), so fresh stitches
    /// sew. Returns the names of the objects that lost them.
    public mutating func dropStaleStitchEdits() -> [String] {
        var names: [String] = []
        for i in objects.indices where objects[i].stitchEdits != nil && !objects[i].hasCurrentStitchEdits {
            objects[i].stitchEdits = nil; names.append(objects[i].name)
        }
        return names
    }
}
