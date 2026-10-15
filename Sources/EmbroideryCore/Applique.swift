// Appliqué: a piece of fabric sewn on as part of the design. A closed shape becomes three parts, grouped:
// a placement line (then the machine stops so you lay the fabric over it), a tack-down that holds the fabric
// (then it stops so you trim the fabric close to the stitching), and a satin edge that covers the raw edge.
import Foundation

public struct AppliqueResult: Sendable {
    /// Placement line, tack-down and satin edge, in sewing order and grouped together.
    public var objects: [RunObject]
    public var warnings: [String]
}

public enum Applique {
    public enum TackDown: String, CaseIterable, Sendable {
        case zigzag, running
        public var title: String { self == .zigzag ? "Zigzag" : "Running" }
    }
    /// Satin edge widths: wide enough to cover the placement and tack-down stitches and the cut fabric edge.
    public static let coverWidths = 2.5...8.0
    public static let defaultCoverWidth = 3.5
    /// The zigzag tack-down: narrower than the satin edge so the edge hides it, with stitches 1.5 mm apart.
    static let tackDownSpacing = 1.5

    /// Builds the appliqué parts for `object` (a fill or closed outline; holes are ignored), all in `color`.
    /// Throws if the shape isn't closed or is too small or sharp for a satin edge `coverWidth` mm wide.
    public static func make(from object: RunObject, coverWidth: Double, tackDown: TackDown, color: ThreadColor) throws -> AppliqueResult {
        guard SatinBorder.canBorder(object) else { throw DesignError.invalid("‘\(object.name)’ isn't a closed shape. Appliqué needs a fill or closed outline.") }
        guard coverWidths.contains(coverWidth) else { throw DesignError.invalid("The satin edge must be between 2.5 and 8 mm wide.") }
        let group = UUID()
        func part(_ base: RunObject, _ suffix: String) -> RunObject {
            var part = base; part.id = UUID(); part.name = "\(object.name) · \(suffix)"; part.color = color; part.groupID = group
            part.lettering = nil; part.entry = nil; part.exit = nil; part.locked = false; part.visible = true
            return part
        }

        // 1. Placement: a running stitch right on the shape's edge, keeping its curves.
        var placement = part(RunObject(name: "", nodes: object.nodes, color: color), "placement")
        placement.closed = true; placement.digitizing = DigitizingSettings(kind: .run); placement.stitchLength = 2.5
        placement.stopAfter = true

        // 2. Tack-down: an open zigzag along the edge (or a running stitch on it), then a stop to trim the fabric.
        var tack: RunObject
        switch tackDown {
        case .zigzag:
            let zigzag = try SatinBorder.around(object, width: max(1.5, coverWidth - 1.5), color: color).object
            tack = part(zigzag, "tack-down")
            tack.digitizing?.spacing = tackDownSpacing; tack.digitizing?.underlay = .none; tack.digitizing?.pullPercent = nil
        case .running:
            tack = part(placement, "tack-down")
        }
        tack.stopAfter = true

        // 3. Satin edge covering the raw edge of the fabric.
        let cover = try SatinBorder.around(object, width: coverWidth, color: color)
        var edge = part(cover.object, "satin edge"); edge.stopAfter = false

        var warnings = cover.warnings
        if !(object.holes ?? []).isEmpty { warnings.append("‘\(object.name)’ has holes; appliqué uses only its outside edge.") }
        return AppliqueResult(objects: [placement, tack, edge], warnings: warnings)
    }
}
