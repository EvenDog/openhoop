// Color blends: two thread colors fading into each other across one shape. Every object sews in one thread, so a
// blend is two gradient fills of the same shape on top of each other: the first color solid where the blend starts
// and sheer toward its end, the second color the other way round, so the two mix in the middle.

import Foundation

public enum ColorBlend {
    /// Whether `object` can be turned into a blend: an unlocked fill that isn't part of lettering or a monogram (those
    /// are rebuilt from their text, which would leave the blend's second layer behind).
    public static func canBlend(_ object: RunObject) -> Bool {
        object.kind == .fill && !object.locked && object.lettering == nil && object.monogram == nil
    }

    /// The two layers that replace `fill`, in sewing order:
    /// - the bottom layer, in `fill`'s own thread, solid where the blend starts, with `fill`'s underlay;
    /// - the top layer, in `second`, solid where the blend ends, with no underlay (the bottom one's already covers it).
    /// `direction` is the way the blend runs from the first color to the second, in degrees: 0 is left to right, 90
    /// bottom to top. The layers share `fill`'s group, or a new one, so they select and move together.
    public static func layers(of fill: RunObject, second: ThreadColor, direction: Double) -> [RunObject] {
        var bottom = fill
        var settings = fill.settings
        settings.fillStyle = .gradient
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
        return [bottom, top]
    }

    /// The fill angle whose gradient rows are solid where a blend running in `direction` starts. A gradient fill at
    /// angle θ is solid on one side and thins out toward (−sin θ, cos θ) (AreaEngine.sweptRows), which points along
    /// `direction` when θ = direction − 90. Kept within -180…180, as fill angles are.
    public static func angle(for direction: Double) -> Double {
        var angle = (direction - 90).truncatingRemainder(dividingBy: 360)
        if angle > 180 { angle -= 360 } else if angle <= -180 { angle += 360 }
        return angle
    }
}
