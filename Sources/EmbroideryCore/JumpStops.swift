// Stop at Jumps, for machines without a thread cutter. Such a machine ignores trims and drags the thread across to
// the next object as a loose jump, but it pauses at every stop (written as a change to the same thread). So Stop
// after on each object that ends in a jump lets the person snip the thread there, then press Start to carry on.
import Foundation

extension StitchPlan {
    /// The objects whose thread is cut and whose needle then travels to a different object in the same thread. Left
    /// out: objects followed by a thread change or a stop (the machine pauses there anyway), objects the next one
    /// carries straight on from, the last object, and jumps inside one object.
    public var objectsEndingInJump: Set<UUID> {
        var found: Set<UUID> = []
        var cutObject: UUID?          // the object whose thread was just cut
        var travelled = false         // ...and whether the needle has moved since
        var needle: Point?
        for command in commands {
            switch command.op {
            case .trim:
                cutObject = command.objectID; travelled = false
            case .jump:
                if cutObject != nil && command.point != needle { travelled = true }
            case .stitch:
                if let cut = cutObject, command.objectID != cut, travelled { found.insert(cut) }
                cutObject = nil
            case .colorChange, .stop, .end:
                cutObject = nil
            }
            needle = command.point
        }
        return found
    }
}

extension Design {
    /// True if any object in `scope` (nil means every object) has a stop added by Stop at Jumps.
    public func hasJumpStops(in scope: Set<UUID>?) -> Bool {
        objects.contains { (scope?.contains($0.id) ?? true) && $0.stopForJump == true }
    }

    /// Turns on Stop after for the unlocked objects in `scope` (nil means every object) that end in a jump in `plan`
    /// (compiled from this design) and don't stop already. Returns how many stops were added.
    public mutating func addJumpStops(using plan: StitchPlan, in scope: Set<UUID>?) -> Int {
        let jumping = plan.objectsEndingInJump
        var added = 0
        for index in objects.indices where jumping.contains(objects[index].id) && (scope?.contains(objects[index].id) ?? true)
            && !objects[index].locked && !objects[index].stopAfter {
            objects[index].stopAfter = true; objects[index].stopForJump = true; added += 1
        }
        return added
    }

    /// Turns off the stops Stop at Jumps added to the unlocked objects in `scope` (nil means every object); stops
    /// switched on by hand stay. Returns how many were removed.
    public mutating func removeJumpStops(in scope: Set<UUID>?) -> Int {
        var removed = 0
        for index in objects.indices where objects[index].stopForJump == true && (scope?.contains(objects[index].id) ?? true) && !objects[index].locked {
            objects[index].stopAfter = false; objects[index].stopForJump = nil; removed += 1
        }
        return removed
    }
}
