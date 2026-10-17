// Copy and paste of design objects, within one design or between designs. Copied objects travel on the Mac's
// pasteboard as JSON; pasting gives them fresh identities so they edit separately from the originals.
import Foundation

public struct ObjectClipboard: Codable, Equatable, Sendable {
    /// The pasteboard type the app writes and reads (a private type, so other apps ignore it).
    public static let pasteboardType = "app.embroidery.objects"
    /// Copied data larger than this is refused when pasting, so a damaged pasteboard can't flood the app.
    public static let maxBytes = 50_000_000
    public var version = 1
    public var objects: [RunObject]
    public init(objects: [RunObject]) { self.objects = objects }
}

extension Design {
    /// The objects with these ids, in sewing order, ready to copy.
    public func copying(_ ids: Set<UUID>) -> ObjectClipboard {
        ObjectClipboard(objects: objects.filter { ids.contains($0.id) })
    }

    /// Adds copied objects at the end of the sewing order, moved by `offset` (mm), and returns their new ids.
    /// Each gets a fresh id; objects that were grouped together (or were the same lettering or branch) stay together
    /// as a new group (or new lettering or branch), separate from the originals. Pasted objects are unlocked.
    @discardableResult
    public mutating func paste(_ clipboard: ObjectClipboard, offset: Point = Point(0, 0)) -> [UUID] {
        var ids: [UUID] = [], newGroups: [UUID: UUID] = [:], newLettering: [UUID: UUID] = [:], copies: [UUID: UUID] = [:]
        for object in clipboard.objects {
            var copy = object; copy.id = UUID(); copy.locked = false; copies[object.id] = copy.id
            if offset != Point(0, 0) { copy.transform { $0 + offset } }
            if let old = copy.groupID { if newGroups[old] == nil { newGroups[old] = UUID() }; copy.groupID = newGroups[old] }
            if let old = copy.branchID { if newGroups[old] == nil { newGroups[old] = UUID() }; copy.branchID = newGroups[old] }   // a separate branch too
            if let old = copy.lettering?.id { if newLettering[old] == nil { newLettering[old] = UUID() }; copy.lettering?.id = newLettering[old]! }
            if let old = copy.monogram?.id { if newLettering[old] == nil { newLettering[old] = UUID() }; copy.monogram?.id = newLettering[old]! }   // a separate monogram too
            ids.append(copy.id); objects.append(copy)
        }
        relinkCopiedGuides(copies.merging(newLettering) { a, _ in a })   // a copied guide line guides the copied fill or lettering
        return ids
    }
}
