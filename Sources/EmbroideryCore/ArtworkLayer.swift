// The reference picture's place in the sewing order: the objects sewn before it are drawn under the picture and the
// rest on top, so you can digitize one layer, move the picture above it, and trace the next layer over it. Only the
// canvas uses this; the picture is never sewn.
import Foundation

extension Design {
    /// How many objects, from the first sewn, are drawn under the reference picture: 0 (under everything) up to all
    /// of them. 0 when there's no picture.
    public var artworkLayer: Int { min(max(artwork?.layer ?? 0, 0), objects.count) }

    /// Moves the picture one step down the sewing order (`step` 1: the next object goes under it) or up (`step` -1:
    /// the object before it comes over it). Grouped objects next to each other (such as the letters of a word) count
    /// as one step, so the picture never lands between them.
    public mutating func moveArtwork(by step: Int) {
        guard artwork != nil else { return }
        var layer = artworkLayer
        if step > 0, layer < objects.count {
            layer += 1
            // Past the rest of a group, if the object just passed is in one.
            while let group = objects[layer - 1].groupID, layer < objects.count, objects[layer].groupID == group { layer += 1 }
        } else if step < 0, layer > 0 {
            layer -= 1
            while let group = objects[layer].groupID, layer > 0, objects[layer - 1].groupID == group { layer -= 1 }
        }
        artwork?.layer = layer
    }

    /// After an edit from `previous`, keeps the picture between the same objects: objects added or removed don't
    /// shift it (it goes just after the last surviving object that was under it, so new objects land on top), while
    /// objects reordered among themselves pass it, as rows in a list would. An edit that sets the picture's place
    /// itself (moving the picture, or Undo putting back an older design) is kept as it is.
    public mutating func keepArtworkPlace(from previous: Design) {
        guard artwork != nil, artwork?.layer == previous.artwork?.layer else { return }
        let before = previous.objects.map(\.id)
        guard Set(before) != Set(objects.map(\.id)) else { return }
        let under = Set(before.prefix(previous.artworkLayer))
        artwork?.layer = objects.lastIndex { under.contains($0.id) }.map { $0 + 1 } ?? 0
    }
}
