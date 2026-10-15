// Cutting out overlaps: a fill can leave out the area that shapes sewn after it will cover, so the hidden part
// isn't stitched twice (stiff, bulky embroidery). The fill keeps sewing a little way under each covering shape's
// edge so no gap opens up. The shapes themselves never change; the cut is worked out each time stitches are made,
// so moving the shape on top lets the fill fill back in. It's an option on each fill, off unless switched on.
import Foundation

public enum OverlapCutout {
    /// How far (mm) the fill keeps sewing under the edge of a shape on top, so no gap shows between them.
    public static let tuck = 1.0
    /// Leftover pieces narrower than this (mm) are dropped: too thin to fill.
    static let minimumWidth = 1.0

    /// The area an object covers when it sews: a fill's outline (its holes stay uncovered) or a satin's column.
    /// Running lines, outlines, imported stitches and empty shapes cover nothing.
    static func coveredArea(_ object: RunObject) -> [[Point]]? {
        guard object.rawStitches == nil else { return nil }
        switch object.kind {
        case .fill:
            guard object.nodes.count >= 3 else { return nil }
            return ([object.nodes] + (object.holes ?? [])).map { AreaGeometry.ring($0) }
        case .satin:
            guard object.nodes.count >= 4, object.nodes.count % 2 == 0 else { return nil }
            let left = stride(from: 0, to: object.nodes.count, by: 2).map { object.nodes[$0] }
            let right = stride(from: 1, to: object.nodes.count, by: 2).map { object.nodes[$0] }
            let l = RunningEngine.flatten(left, closed: object.closed).flatMap { $0 }, r = RunningEngine.flatten(right, closed: object.closed).flatMap { $0 }
            // An open column is one outline (down one rail, back up the other); a closed one is a ring between its rails.
            return object.closed ? [l, r] : [l + r.reversed()]
        default: return nil
        }
    }

    /// The pieces of `fill` left after cutting out what `later` objects (sewn after it) cover, each as an outline
    /// followed by its holes. Returns nil when nothing on top overlaps it, so the fill sews as drawn.
    public static func pieces(of fill: RunObject, under later: [RunObject]) throws -> [[[Point]]]? {
        let original = ([fill.nodes] + (fill.holes ?? [])).map { AreaGeometry.ring($0) }
        var pieces = [original]
        for cover in later {
            try Task.checkCancellation()
            guard let area = coveredArea(cover), area.allSatisfy({ $0.count >= 3 }) else { continue }
            // Shrink the cover first, so the fill reaches `tuck` mm under its edge. Covers thinner than that vanish.
            guard let shrunk = try? AreaGeometry.offset(area, by: -tuck), !shrunk.isEmpty else { continue }
            var next: [[[Point]]] = []
            for piece in pieces { next += try AreaGeometry.subtracting(shrunk, from: piece) }
            pieces = next
        }
        // Nothing on top overlapped it if the area left is the area it started with.
        func area(_ piece: [[Point]]) -> Double { abs(AreaGeometry.area(piece[0])) - piece.dropFirst().reduce(0) { $0 + abs(AreaGeometry.area($1)) } }
        guard abs(area(original) - pieces.reduce(0) { $0 + area($1) }) > 0.01 else { return nil }
        // Drop slivers too thin to fill: a piece that vanishes when shrunk by half the minimum width.
        return try pieces.filter { piece in !(try AreaGeometry.offset(piece, by: -minimumWidth / 2)).isEmpty }
    }

    /// Stitches for a fill with overlaps cut out: each remaining piece is filled as its own small fill (same
    /// settings; radial fills keep fanning from the whole shape's center). Returns nil when nothing is cut.
    static func fill(_ object: RunObject, under later: [RunObject]) throws -> ObjectStitches? {
        guard let pieces = try pieces(of: object, under: later) else { return nil }
        var result = ObjectStitches()
        guard !pieces.isEmpty else {
            result.warnings.append("\(object.name) is completely covered by the shapes sewn on top, so it isn't sewn.")
            return result
        }
        var settings = object.settings
        if settings.radialCenter == nil { settings.radialCenter = AreaGeometry.centroid(AreaGeometry.ring(object.nodes)) }
        for (index, piece) in pieces.enumerated() {
            var part = object
            part.nodes = piece[0].map { PathNode($0) }; part.holes = piece.count > 1 ? piece.dropFirst().map { $0.map { PathNode($0) } } : nil
            part.digitizing = settings; part.keepAngleLines(for: piece)
            // A chosen start point applies to the first piece and an end point to the last.
            if index > 0 { part.entry = nil }
            if index < pieces.count - 1 { part.exit = nil }
            let stitches = try AreaEngine.fill(part)
            result.sections += stitches.sections
            for warning in stitches.warnings where !result.warnings.contains(warning) { result.warnings.append(warning) }
        }
        return result
    }
}
