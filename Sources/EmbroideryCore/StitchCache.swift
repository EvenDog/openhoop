// Remembers the stitches worked out for each object, so compiling a design again only works out the objects that
// changed. An object is looked up by its whole contents (shape, settings, start and end points…), so any change
// misses the cache and gets fresh stitches; nothing ever has to be thrown away by hand.
import Foundation

/// The memory of worked-out stitches that `StitchEngine.compile` uses. Safe to use from several compiles at once.
/// (`@unchecked Sendable` tells Swift that sharing this class between background tasks is safe, which the lock ensures.)
final class StitchCache: @unchecked Sendable {
    static let shared = StitchCache()
    /// How many objects are remembered at most. When full, the cache is emptied and starts over.
    static let limit = 300

    /// What an object's stitches depend on: the object itself, plus what's sewn after it for a fill that cuts out
    /// overlaps (moving a shape on top changes the cut).
    private struct Key: Hashable {
        let object: RunObject
        let later: [RunObject]
    }
    private var stored: [Key: ObjectStitches] = [:]
    private let lock = NSLock()   // lets only one compile at a time read or change `stored`

    /// How many objects' stitches are remembered (used by tests).
    var count: Int { lock.withLock { stored.count } }
    func clear() { lock.withLock { stored.removeAll() } }

    /// The stitches for `object` (with `later` sewn after it): remembered ones if this exact object was seen
    /// before, otherwise the result of `make`, which is then remembered. Errors aren't remembered.
    func stitches(for object: RunObject, under later: [RunObject], make: () throws -> ObjectStitches) throws -> ObjectStitches {
        let cutsOut = object.kind == .fill && object.settings.cutOutOverlaps == true
        let key = Key(object: object, later: cutsOut ? later : [])
        if let remembered = lock.withLock({ stored[key] }) { return remembered }
        // Worked out outside the lock, so a slow object doesn't hold up other compiles.
        let made = try make()
        lock.withLock {
            if stored.count >= Self.limit { stored.removeAll() }
            stored[key] = made
        }
        return made
    }
}
