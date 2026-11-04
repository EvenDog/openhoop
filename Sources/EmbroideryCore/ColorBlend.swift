// Color blends: two thread colors fading into each other across one shape. Every object sews in one thread, so a
// blend is two gradient fills of the same shape on top of each other: the first color solid where the blend starts
// and sheer toward its end, the second color the other way round, so the two mix in the middle. The second layer
// links to the first (`RunObject.blendOf`), and after every edit the two are brought back in step: one shape,
// opposite angles (`Design.syncBlends`).

import Foundation

/// How one layer of a color blend fades, measured across the shape from the layer's solid side (0) to its far side
/// (1): solid up to `start`, covering half the fabric at `middle`, and no stitches from `end` on, changing in a
/// straight line in between. The other layer's fade is the mirror image (`mirrored`), so together the two cover the
/// fabric once everywhere: as one thins out, the other fills in.
public struct BlendFade: Codable, Hashable, Sendable {
    public var start: Double
    public var middle: Double
    public var end: Double
    public init(start: Double, middle: Double, end: Double) { self.start = start; self.middle = middle; self.end = end }
    /// A blend across the whole shape, mixing half and half in the middle: what a new blend starts with.
    public static let whole = BlendFade(start: 0, middle: 0.5, end: 1)
    /// The three points in order, inside the shape: 0 ≤ start < middle < end ≤ 1.
    public var isValid: Bool { [start, middle, end].allSatisfy(\.isFinite) && 0 <= start && start < middle && middle < end && end <= 1 }
    /// How much of the fabric this layer covers at `t` (0–1 across from its solid side): 1 down to 0.
    public func coverage(at t: Double) -> Double {
        if t <= start { return 1 }
        if t >= end { return 0 }
        if t < middle { return 1 - 0.5 * (t - start) / (middle - start) }
        return 0.5 - 0.5 * (t - middle) / (end - middle)
    }
    /// The other layer's fade: the same blend seen from that layer's own solid side.
    public var mirrored: BlendFade { BlendFade(start: 1 - end, middle: 1 - middle, end: 1 - start) }
}

public enum ColorBlend {
    /// Whether `object` can be turned into a blend: an unlocked fill that isn't part of lettering or a monogram (those
    /// are rebuilt from their text, which would leave the blend's second layer behind). A layer of a blend already
    /// can't; `Design.blend(containing:)` finds those, to edit.
    public static func canBlend(_ object: RunObject) -> Bool {
        object.kind == .fill && !object.locked && object.lettering == nil && object.monogram == nil && object.blendOf == nil
    }

    /// The two layers that replace `fill`, in sewing order:
    /// - the bottom layer, in `fill`'s own thread, solid where the blend starts, with `fill`'s underlay;
    /// - the top layer, in `second`, solid where the blend ends, with no underlay (the bottom one's already covers it).
    /// `direction` is the way the blend runs from the first color to the second, in degrees: 0 is left to right, 90
    /// bottom to top. `fade` is where the colors mix, seen from the first color's side (the second's is its mirror).
    /// The layers share `fill`'s group, or a new one, so they select and move together.
    public static func layers(of fill: RunObject, second: ThreadColor, direction: Double, fade: BlendFade = .whole) -> [RunObject] {
        var bottom = fill
        var settings = fill.settings
        settings.fillStyle = .gradient
        settings.blendFade = fade
        settings.gradientEnd = sparsest
        settings.angleLines = nil   // gradient rows run straight across, square to the blend
        settings.angle = angle(for: direction)
        bottom.digitizing = settings
        bottom.stitchEdits = nil    // new stitches, so edits made to the old ones no longer fit
        bottom.groupID = fill.groupID ?? UUID()

        var top = bottom
        top.id = UUID()
        top.name = "\(fill.name) blend"
        top.color = second
        top.digitizing?.angle = angle(for: direction + 180)
        top.digitizing?.underlay = .none
        top.digitizing?.blendFade = fade.mirrored
        top.blendOf = bottom.id
        return [bottom, top]
    }

    /// The fill angle whose gradient rows are solid where a blend running in `direction` starts. A gradient fill at
    /// angle θ is solid on one side and thins out toward (−sin θ, cos θ) (AreaEngine.sweptRows), which points along
    /// `direction` when θ = direction − 90. Kept within -180…180, as fill angles are.
    public static func angle(for direction: Double) -> Double { normalized(direction - 90) }
    /// A blend layer's Spacing at end: rows further apart than this (mm) are left out, so past its fade a color sews
    /// nothing and the other is pure.
    public static let sparsest = 5.0
    /// The way a blend whose first color's layer is `base` runs, in degrees from 0 up to 360 (the reverse of `angle(for:)`).
    public static func direction(of base: RunObject) -> Double {
        let direction = (base.settings.angle + 90).truncatingRemainder(dividingBy: 360)
        return direction < 0 ? direction + 360 : direction
    }
    /// `angle` turned to lie within -180…180, as fill angles do.
    static func normalized(_ angle: Double) -> Double {
        var angle = angle.truncatingRemainder(dividingBy: 360)
        if angle > 180 { angle -= 360 } else if angle <= -180 { angle += 360 }
        return angle
    }
    /// True for a gradient fill, the only thing a blend's layers can be.
    static func isGradient(_ object: RunObject) -> Bool { object.kind == .fill && object.settings.fillStyle == .gradient }
}

extension Design {
    /// The color blend that the object `id` is a layer of (either one): the indices of its first color's layer
    /// (`base`) and its second's (`top`). nil if it isn't part of a blend.
    public func blend(containing id: UUID) -> (base: Int, top: Int)? {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return nil }
        if let baseID = objects[index].blendOf, let base = objects.firstIndex(where: { $0.id == baseID }) { return (base, index) }
        if let top = objects.firstIndex(where: { $0.blendOf == id }) { return (index, top) }
        return nil
    }

    /// Gives the blend that `id` is a layer of a new second thread, direction and fade (see `ColorBlend.layers`).
    public mutating func editBlend(containing id: UUID, second: ThreadColor, direction: Double, fade: BlendFade) {
        guard let (base, top) = blend(containing: id) else { return }
        objects[base].digitizing?.angle = ColorBlend.angle(for: direction)
        objects[top].digitizing?.angle = ColorBlend.angle(for: direction + 180)
        objects[top].color = second
        setBlendFade(containing: id, fade)
    }
    /// Sets where the blend that `id` is a layer of mixes, `fade` seen from its first color's side.
    public mutating func setBlendFade(containing id: UUID, _ fade: BlendFade) {
        guard let (base, top) = blend(containing: id) else { return }
        objects[base].digitizing?.blendFade = fade
        objects[top].digitizing?.blendFade = fade.mirrored
    }

    /// Brings each color blend's two layers back in step after an edit, comparing them with `previous` (the design
    /// before it):
    /// - shape (outline, holes, closed): if only the second color's layer was reshaped or moved, the first takes its
    ///   shape; otherwise the second takes the first's (so moving both together, or a new blend, changes nothing);
    /// - angle: the same, but the one that follows takes the opposite angle (+180°), so they stay solid at opposite ends;
    /// - fade: the same, the one that follows taking the mirror image, so together they still cover the fabric once.
    /// A blend whose layers aren't both gradient fills any more, or whose first layer is gone, comes apart: the second
    /// layer becomes an ordinary gradient fill (Undo puts the link back).
    public mutating func syncBlends(from previous: Design) {
        guard objects.contains(where: { $0.blendOf != nil }) else { return }
        let place = Dictionary(objects.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let before = Dictionary(previous.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var linked: Set<UUID> = []   // first layers already given a second, so a stray second link comes apart
        for t in objects.indices {
            guard let baseID = objects[t].blendOf else { continue }
            guard let b = place[baseID], b != t, ColorBlend.isGradient(objects[b]), ColorBlend.isGradient(objects[t]), !linked.contains(baseID) else {
                objects[t].blendOf = nil; continue
            }
            linked.insert(baseID)
            let top = objects[t], base = objects[b]
            // Which layer changed in this edit. One that wasn't there before (just made or pasted) counts as unchanged
            // for the second layer and changed for the first, so the first leads.
            func reshaped(_ object: RunObject, new: Bool) -> Bool {
                guard let old = before[object.id] else { return new }
                return old.nodes != object.nodes || old.holes != object.holes || old.closed != object.closed
            }
            func turned(_ object: RunObject, new: Bool) -> Bool {
                guard let old = before[object.id] else { return new }
                return old.settings.angle != object.settings.angle
            }
            if reshaped(top, new: false) && !reshaped(base, new: true) {
                objects[b].nodes = top.nodes; objects[b].holes = top.holes; objects[b].closed = top.closed
            } else {
                objects[t].nodes = base.nodes; objects[t].holes = base.holes; objects[t].closed = base.closed
            }
            if turned(top, new: false) && !turned(base, new: true) {
                objects[b].digitizing?.angle = ColorBlend.normalized(top.settings.angle + 180)
            } else {
                objects[t].digitizing?.angle = ColorBlend.normalized(base.settings.angle + 180)
            }
            func refaded(_ object: RunObject, new: Bool) -> Bool {
                guard let old = before[object.id] else { return new }
                return old.settings.blendFade != object.settings.blendFade
            }
            if refaded(top, new: false) && !refaded(base, new: true) {
                objects[b].digitizing?.blendFade = top.settings.blendFade?.mirrored
            } else {
                objects[t].digitizing?.blendFade = base.settings.blendFade?.mirrored
            }
        }
    }
}
