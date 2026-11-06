// Color blends: two thread colors fading into each other across one shape. Every object sews in one thread, so a
// blend is two fills of the same shape on top of each other: the first color solid where the blend starts and sheer
// toward its end, the second color the other way round, so the two mix in the middle. A straight blend is two
// gradient fills (rows spreading out across the shape); a wave one, two wave fills whose rows spread out the same
// way; a guided one, two guided fills whose rows (copies of the guide line) spread out from one side of the guide
// to the other; a radial one, two radial fills whose rays change color part
// way out; a contour one, two contour fills whose rings spread out between the edge and the middle. The second layer
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
    /// How far across (0–1, from the solid side) the layer reaches with at least `share` (0–1) of its stitches: the
    /// inverse of `coverage`. A radial blend gives each ray a share, and the ray stops here.
    public func extent(covering share: Double) -> Double {
        if share >= 1 { return start }
        if share <= 0 { return end }
        if share >= 0.5 { return start + 2 * (1 - share) * (middle - start) }
        return middle + 2 * (0.5 - share) * (end - middle)
    }
    /// The other layer's fade: the same blend seen from that layer's own solid side.
    public var mirrored: BlendFade { BlendFade(start: 1 - end, middle: 1 - middle, end: 1 - start) }
}

/// The ways a color blend can run across its shape, each sewn with its own fill style.
public enum BlendShape: String, CaseIterable, Sendable {
    /// Straight across, in a direction: gradient fills.
    case straight
    /// Across in a direction, on rows that ripple: wave fills spaced like gradient fills.
    case wave
    /// From the center out to the edge along rays: radial fills.
    case radial
    /// From the middle out to the edge along rings that follow the outline: contour fills.
    case contour
    /// From one side of a guide line to the other, on rows that follow it: guided fills. Only for fills with a guide.
    case guided
    public var title: String { switch self { case .straight: return "Straight"; case .wave: return "Wave"; case .radial: return "Radial"; case .contour: return "Contour"; case .guided: return "Guided" } }
    /// The fill style each layer of this kind of blend sews with.
    public var fillStyle: FillStyle { switch self { case .straight: return .gradient; case .wave: return .wave; case .radial: return .radial; case .contour: return .contour; case .guided: return .guided } }
    /// The kind of blend a layer sewn in `style` belongs to, or nil for a style no blend uses.
    public init?(style: FillStyle?) {
        guard let shape = Self.allCases.first(where: { $0.fillStyle == (style ?? .tatami) }) else { return nil }
        self = shape
    }
    /// True for blends that run in a direction; the others run between the middle and the edge, or (guided) from one
    /// side of the guide line to the other.
    public var hasDirection: Bool { self == .straight || self == .wave }
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
    /// `shape` is the kind of blend. A straight blend runs in `direction` from the first color to the second, in
    /// degrees: 0 is left to right, 90 bottom to top. A radial or contour blend runs from the middle to the edge, or
    /// with `firstAtEdge` from the edge to the middle. `fade` is where the colors mix, seen from the first color's side
    /// (the second's is its mirror). The layers share `fill`'s group, or a new one, so they select and move together.
    public static func layers(of fill: RunObject, second: ThreadColor, direction: Double, fade: BlendFade = .whole,
                              shape: BlendShape = .straight, firstAtEdge: Bool = false) -> [RunObject] {
        var bottom = fill
        var settings = fill.settings
        settings.fillStyle = shape.fillStyle
        settings.blendFade = fade
        settings.gradientEnd = sparsest
        settings.angleLines = nil   // gradient rows run straight across, square to the blend
        settings.angle = angle(for: direction)
        settings.blendFromEdge = shape.hasDirection ? nil : firstAtEdge
        // Row blends space their rows like tatami: Spacing at start across two rows (radial and contour fills don't pair rows).
        settings.blendRowsPaired = Self.pairsRows(shape) ? true : nil
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
        top.digitizing?.blendFromEdge = shape.hasDirection ? nil : !firstAtEdge
        top.blendOf = bottom.id
        return [bottom, top]
    }

    /// True for blends sewn in rows (straight, wave, guided), whose Spacing at start is measured across two rows.
    static func pairsRows(_ shape: BlendShape) -> Bool { [.straight, .wave, .guided].contains(shape) }

    /// The kind of blend whose first color's layer is `base`.
    public static func shape(of base: RunObject) -> BlendShape { BlendShape(style: base.settings.fillStyle) ?? .straight }

    /// How a radial or contour blend layer with settings `s` thins out, for the fill engines; nil if it isn't one.
    static func fillBlend(_ s: DigitizingSettings) -> FillBlend? {
        s.blendFade.map { FillBlend(fade: $0, fromEdge: s.blendFromEdge ?? false, sparsest: s.gradientEnd ?? sparsest) }
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
    /// True for a fill in a style that blends (gradient, wave, radial, contour or guided): what a blend's layers must be.
    static func isLayer(_ object: RunObject) -> Bool { object.kind == .fill && BlendShape(style: object.settings.fillStyle) != nil }
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

    /// Gives the blend that `id` is a layer of new threads (a nil `first` keeps the first layer's), kind, direction and
    /// fade (see `ColorBlend.layers`). `shape` nil keeps the blend's kind.
    public mutating func editBlend(containing id: UUID, first: ThreadColor? = nil, second: ThreadColor, direction: Double, fade: BlendFade,
                                   shape: BlendShape? = nil, firstAtEdge: Bool = false) {
        guard let (base, top) = blend(containing: id) else { return }
        if let first { objects[base].color = first }
        let shape = shape ?? ColorBlend.shape(of: objects[base])
        objects[base].digitizing?.fillStyle = shape.fillStyle; objects[top].digitizing?.fillStyle = shape.fillStyle
        objects[base].digitizing?.blendFromEdge = shape.hasDirection ? nil : firstAtEdge
        objects[top].digitizing?.blendFromEdge = shape.hasDirection ? nil : !firstAtEdge
        objects[base].stitchEdits = nil; objects[top].stitchEdits = nil   // new stitches, so old edits no longer fit
        // A blend changed in the dialog takes the density its preview showed, even one made before rows were paired.
        let paired: Bool? = ColorBlend.pairsRows(shape) ? true : nil
        objects[base].digitizing?.blendRowsPaired = paired; objects[top].digitizing?.blendRowsPaired = paired
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
    /// - radial center, wave size and guide line: the same, so both layers' rays come from one point, their rows ripple
    ///   alike and follow one guide.
    /// A blend whose layers aren't both fills of the same blending style any more, or whose first layer is gone, comes
    /// apart: the second layer becomes an ordinary fill (Undo puts the link back). A wave, radial, contour or guided layer then
    /// loses its fade too, or it would sew as a ragged part of a fill (a gradient fill keeps it: it's still a gradient).
    public mutating func syncBlends(from previous: Design) {
        guard objects.contains(where: { $0.blendOf != nil }) else { return }
        let place = Dictionary(objects.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let before = Dictionary(previous.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var linked: Set<UUID> = []   // first layers already given a second, so a stray second link comes apart
        for t in objects.indices {
            guard let baseID = objects[t].blendOf else { continue }
            guard let b = place[baseID], b != t, ColorBlend.isLayer(objects[b]), ColorBlend.isLayer(objects[t]),
                  objects[b].settings.fillStyle == objects[t].settings.fillStyle, !linked.contains(baseID) else {
                objects[t].blendOf = nil
                for k in [t, place[baseID]].compactMap({ $0 }) where [.wave, .radial, .contour, .guided].contains(objects[k].settings.fillStyle) {
                    objects[k].digitizing?.blendFade = nil; objects[k].digitizing?.blendFromEdge = nil
                }
                continue
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
            // Settings both layers share as they are (radial center, wave size), the same way: the one changed leads.
            func share<Value: Equatable>(_ key: WritableKeyPath<DigitizingSettings, Value>) {
                func changed(_ object: RunObject, new: Bool) -> Bool {
                    guard let old = before[object.id] else { return new }
                    return old.settings[keyPath: key] != object.settings[keyPath: key]
                }
                if changed(top, new: false) && !changed(base, new: true) {
                    objects[b].digitizing?[keyPath: key] = top.settings[keyPath: key]
                } else {
                    objects[t].digitizing?[keyPath: key] = base.settings[keyPath: key]
                }
            }
            share(\.radialCenter); share(\.waveHeight); share(\.waveLength); share(\.guideLine); share(\.blendRowsPaired)
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
