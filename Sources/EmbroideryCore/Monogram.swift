// Monograms: one to three initials in a classic layout, with optional ornaments either side and a
// satin border around it all. Every object made from a monogram carries its recipe, so it can be opened again and
// rebuilt in place, like lettering. The ornaments (swirls, leaves, dots) are simple shapes drawn here for OpenHoop.
import Foundation

/// How the initials are arranged.
public enum MonogramLayout: String, Codable, CaseIterable, Sendable {
    /// The middle initial (usually the surname) larger, the others smaller on either side.
    case bigMiddle
    /// All the same size in a row.
    case sideBySide
    /// One above the other.
    case stacked
    /// Sized to fit a diamond: a tall middle and shorter sides close in to it.
    case diamond
    public var title: String {
        switch self { case .bigMiddle: return "Big middle"; case .sideBySide: return "Side by side"; case .stacked: return "Stacked"; case .diamond: return "Diamond" }
    }
}

/// The border shape around a monogram.
public enum MonogramBorder: String, Codable, CaseIterable, Sendable {
    case none, circle, oval, roundedRectangle, diamond, shield
    public var title: String {
        switch self { case .none: return "None"; case .circle: return "Circle"; case .oval: return "Oval"; case .roundedRectangle: return "Rounded rectangle"; case .diamond: return "Diamond"; case .shield: return "Shield" }
    }
}

/// The ornaments either side of the initials.
public enum MonogramOrnament: String, Codable, CaseIterable, Sendable {
    case none, swirls, leaves, dots
    public var title: String { rawValue.capitalized }
}

/// Everything needed to build (and rebuild) a monogram.
public struct MonogramSpec: Codable, Hashable, Sendable {
    /// Ties together the objects made from one monogram (it's also their group).
    public var id = UUID()
    /// One to three initials.
    public var initials: String
    public var fontKind: LetteringSpec.FontKind
    /// An embroidery font's folder name, or a system font's PostScript name.
    public var font: String
    /// The tallest initial, in mm.
    public var height: Double
    public var layout: MonogramLayout
    public var ornament: MonogramOrnament
    public var border: MonogramBorder
    /// The satin border's width, and the gap between it and the monogram, in mm.
    public var borderWidth: Double
    public var borderGap: Double
    /// Placement markers, as for lettering: the monogram is centered on `anchor`, reading towards `alongMarker`,
    /// with `upMarker` above. They move, turn and mirror with the monogram.
    public var anchor = Point(0, 0)
    public var alongMarker = Point(10, 0)
    public var upMarker = Point(0, 10)
    public static let heights = 8.0...80.0, borderWidths = 1.5...4.0, borderGaps = 0.0...15.0

    public init(initials: String, fontKind: LetteringSpec.FontKind, font: String, height: Double = 25, layout: MonogramLayout = .bigMiddle,
                ornament: MonogramOrnament = .none, border: MonogramBorder = .circle, borderWidth: Double = 2.5, borderGap: Double = 3) {
        self.initials = initials; self.fontKind = fontKind; self.font = font; self.height = height; self.layout = layout
        self.ornament = ornament; self.border = border; self.borderWidth = borderWidth; self.borderGap = borderGap
    }

    /// This recipe at the monogram's size as it is now: resizing it stretches the markers too, so the height and the
    /// border's width and gap are scaled to match (each kept within its range, and rounded to 0.1 mm).
    public var asResized: MonogramSpec {
        let scale = upMarker.distance(to: anchor) / 10
        func sized(_ value: Double, _ range: ClosedRange<Double>) -> Double { min(max((value * scale * 10).rounded() / 10, range.lowerBound), range.upperBound) }
        var spec = self
        spec.height = sized(height, Self.heights); spec.borderWidth = sized(borderWidth, Self.borderWidths); spec.borderGap = sized(borderGap, Self.borderGaps)
        return spec
    }

    /// Moves the markers with the monogram (called from RunObject.transform).
    public mutating func transform(_ body: (Point) -> Point) { anchor = body(anchor); alongMarker = body(alongMarker); upMarker = body(upMarker) }

    /// The monogram's objects in sewing order (initials, ornaments, border), grouped, each carrying this recipe,
    /// placed where the markers say; and any notes (such as a size an embroidery font couldn't sew).
    public func build(color: ThreadColor, embroideryFonts: [EmbroideryFont]) throws -> (objects: [RunObject], notes: [String]) {
        let letters = Array(initials.filter { !$0.isWhitespace }.prefix(3)).map(String.init)
        guard !letters.isEmpty else { throw DesignError.invalid("Type one to three initials.") }
        guard Self.heights.contains(height) else { throw DesignError.invalid("Monogram height must be between 8 and 80 mm.") }
        var notes: [String] = [], objects: [RunObject] = []

        // The initials, each built like lettering and set in place.
        let big = letters.count == 3 && (layout == .bigMiddle || layout == .diamond)
        let small = layout == .diamond ? 0.6 : 0.68
        var built: [(objects: [RunObject], box: (min: Point, max: Point))] = []
        for (index, letter) in letters.enumerated() {
            var size = big && index != 1 ? height * small : height
            if fontKind == .embroidery, let font = embroideryFonts.first(where: { $0.folder.lastPathComponent == self.font }), !font.heights.contains(size) {
                let fitted = min(max(size, font.heights.lowerBound), font.heights.upperBound)
                notes.append("\(font.name) is digitized for letters \(font.heights.lowerBound.formatted())–\(font.heights.upperBound.formatted()) mm tall, so ‘\(letter)’ is \(fitted.formatted(.number.precision(.fractionLength(0...1)))) mm.")
                size = fitted
            }
            let spec = LetteringSpec(text: letter, fontKind: fontKind, font: font, height: size)
            let result = try spec.build(color: color, embroideryFonts: embroideryFonts)
            notes += result.warnings
            guard let box = Self.box(result.objects) else { continue }
            built.append((result.objects, box))
        }
        guard !built.isEmpty else { throw DesignError.invalid("None of the initials could be made in this font.") }
        let gap = height * (layout == .diamond ? 0.04 : 0.12)
        if layout == .stacked {
            // Top to bottom, each centered across.
            let total = built.reduce(0) { $0 + ($1.box.max.y - $1.box.min.y) } + gap * Double(built.count - 1)
            var top = total / 2
            for letter in built {
                let shift = Point(-(letter.box.min.x + letter.box.max.x) / 2, top - letter.box.max.y)
                objects += letter.objects.map { var o = $0; o.transform { $0 + shift }; return o }
                top -= (letter.box.max.y - letter.box.min.y) + gap
            }
        } else {
            // Left to right, each centered up and down.
            let total = built.reduce(0) { $0 + ($1.box.max.x - $1.box.min.x) } + gap * Double(built.count - 1)
            var left = -total / 2
            for letter in built {
                let shift = Point(left - letter.box.min.x, -(letter.box.min.y + letter.box.max.y) / 2)
                objects += letter.objects.map { var o = $0; o.transform { $0 + shift }; return o }
                left += (letter.box.max.x - letter.box.min.x) + gap
            }
        }
        for i in objects.indices { objects[i].lettering = nil }   // the monogram's recipe rebuilds them, not lettering's

        // Ornaments either side, mirrored, in the initials' thread.
        if ornament != .none, let letterBox = Self.box(objects) {
            let size = height * 0.55, offset = height * 0.12
            for side in [-1.0, 1.0] {
                let start = Point(side < 0 ? letterBox.min.x - offset : letterBox.max.x + offset, 0)
                objects += Self.ornament(ornament, color: color).map { var o = $0; o.transform { start + Point($0.x * size * side, $0.y * size) }; return o }
            }
        }

        // The border, a satin column centered on an outline `borderGap` (plus half its width) outside everything.
        if border != .none, let box = Self.box(objects) {
            let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
            let outline = RunObject(name: "Monogram border", nodes: Self.borderNodes(border, around: box, points: points, gap: borderGap + borderWidth / 2), color: color)
            var closed = outline; closed.closed = true
            let made = try SatinBorder.around(closed, width: borderWidth, color: color)
            notes += made.warnings
            var object = made.object; object.name = "Monogram border"
            objects.append(object)
        }

        // Grouped, carrying the recipe, and placed by the markers (as lettering is).
        let along = Self.unit(alongMarker - anchor) ?? Point(1, 0)
        let mirrored = AreaGeometry.cross(alongMarker - anchor, upMarker - anchor) < 0
        let up = mirrored ? Point(along.y, -along.x) : Point(-along.y, along.x)
        let turn = atan2(along.y, along.x) * 180 / .pi
        var spec = self; spec.alongMarker = anchor + along * 10; spec.upMarker = anchor + up * 10
        for i in objects.indices {
            objects[i].transform { p in anchor + along * p.x + up * p.y }
            if objects[i].kind == .fill {
                let angle = objects[i].settings.angle
                objects[i].digitizing?.angle = Lettering.turned(mirrored ? -angle : angle, by: turn)
            }
            objects[i].groupID = id; objects[i].monogram = spec
        }
        return (objects, notes)
    }

    /// An ornament for the right-hand side, in units of its size: it starts at x = 0 (next to the initials) and
    /// reaches out to about x = 1, centered on y = 0. The left one is the same, mirrored.
    static func ornament(_ kind: MonogramOrnament, color: ThreadColor) -> [RunObject] {
        switch kind {
        case .none: return []
        case .swirls:
            // A scroll that curls back on itself, sewn as a bold triple run (bean stitch).
            let points = [Point(0, 0), Point(0.35, 0.22), Point(0.72, 0.18), Point(0.95, -0.02), Point(0.82, -0.22), Point(0.6, -0.16), Point(0.62, 0)]
            var swirl = RunObject(name: "Swirl", nodes: points.enumerated().map { PathNode($0.element, smooth: $0.offset > 0) }, color: color)
            swirl.digitizing = DigitizingSettings(kind: .run); swirl.digitizing?.runPasses = 3; swirl.stitchLength = 2
            return [swirl]
        case .leaves:
            // A leaf pointing outward: two gentle curves from its base to its tip, filled along its length.
            var leaf = RunObject(name: "Leaf", nodes: [PathNode(Point(0, 0)), PathNode(Point(0.5, 0.24), smooth: true), PathNode(Point(1.05, 0)), PathNode(Point(0.5, -0.24), smooth: true)], color: color)
            leaf.closed = true; leaf.digitizing = DigitizingSettings(kind: .fill); leaf.digitizing?.angle = 60; leaf.stitchLength = 2.5
            return [leaf]
        case .dots:
            // Three dots, getting smaller outward.
            return [(0.14, 0.13), (0.5, 0.1), (0.8, 0.07)].map { x, r in
                var dot = RunObject(name: "Dot", nodes: ShapeGeometry.nodes(.ellipse, in: (Point(x - r, -r), Point(x + r, r))), color: color)
                dot.closed = true; dot.digitizing = DigitizingSettings(kind: .fill); dot.stitchLength = 2
                return dot
            }
        }
    }

    /// The outline the border's satin runs along, `gap` mm outside the monogram. Circles, ovals and diamonds hug its
    /// actual shapes (`points`, its outlines), so a diamond monogram gets a snug diamond rather than one around the
    /// corners of its box; rectangles and shields go round the box.
    static func borderNodes(_ border: MonogramBorder, around box: (min: Point, max: Point), points: [Point], gap: Double) -> [PathNode] {
        let c = (box.min + box.max) * 0.5, w = max((box.max.x - box.min.x) / 2, 0.1), h = max((box.max.y - box.min.y) / 2, 0.1)
        func around(_ a: Double, _ b: Double) -> (min: Point, max: Point) { (Point(c.x - a, c.y - b), Point(c.x + a, c.y + b)) }
        /// How much the w × h shape (an oval when `round`, else a diamond) must grow to hold every point (1 = as is).
        func reach(round: Bool) -> Double {
            points.map { p in let x = abs(p.x - c.x) / w, y = abs(p.y - c.y) / h; return round ? hypot(x, y) : x + y }.max() ?? 1
        }
        switch border {
        case .none: return []
        case .circle: let r = (points.map { $0.distance(to: c) }.max() ?? hypot(w, h)) + gap; return ShapeGeometry.nodes(.ellipse, in: around(r, r))
        case .oval: let k = reach(round: true); return ShapeGeometry.nodes(.ellipse, in: around(k * w + gap, k * h + gap))
        case .roundedRectangle:
            var settings = ShapeSettings(); settings.cornerRadius = min(w, h) * 0.4 + gap
            return ShapeGeometry.nodes(.rectangle, in: around(w + gap, h + gap), settings: settings)
        case .diamond:
            let k = reach(round: false), a = k * w + gap * 2.squareRoot(), b = k * h + gap * 2.squareRoot()
            return [Point(c.x, c.y + b), Point(c.x + a, c.y), Point(c.x, c.y - b), Point(c.x - a, c.y)].map { PathNode($0) }
        case .shield:
            // A flat top with rounded shoulders, curving in to a point at the bottom.
            let a = w + gap, b = h + gap
            return [PathNode(Point(c.x - a, c.y + b)), PathNode(Point(c.x + a, c.y + b)), PathNode(Point(c.x + a, c.y - b * 0.3), smooth: true),
                    PathNode(Point(c.x, c.y - b * 1.45)), PathNode(Point(c.x - a, c.y - b * 0.3), smooth: true)]
        }
    }

    static func box(_ objects: [RunObject]) -> (min: Point, max: Point)? {
        var design = Design(); design.objects = objects
        return design.bounds(of: Set(objects.map(\.id)))
    }
    static func unit(_ p: Point) -> Point? { let length = hypot(p.x, p.y); return length > 1e-9 ? Point(p.x / length, p.y / length) : nil }
}

extension Design {
    /// The objects made from the monogram with `id`.
    public func monogramObjects(_ id: UUID) -> [RunObject] { objects.filter { $0.monogram?.id == id } }
    /// Replaces the monogram with `id` by new objects (from `spec.build`), at the old ones' place in the sewing
    /// order. Each new part keeps the thread the old parts of its kind had (initials, ornaments, border), and the
    /// monogram stays in any group it was put in. Returns the new objects' IDs.
    @discardableResult public mutating func replaceMonogram(_ id: UUID, with made: [RunObject]) -> [UUID] {
        guard let first = objects.firstIndex(where: { $0.monogram?.id == id }) else { return [] }
        let old = monogramObjects(id)
        /// Which part of a monogram an object is.
        func kind(_ object: RunObject) -> Int { object.name == "Monogram border" ? 2 : ["Swirl", "Leaf", "Dot"].contains(object.name) ? 1 : 0 }
        var made = made, seen: [Int: Int] = [:]
        for i in made.indices {
            // The same-numbered old part of this kind, or failing that the first one (such as for a new initial).
            let k = kind(made[i]), same = old.filter { kind($0) == k }
            if let match = same.indices.contains(seen[k, default: 0]) ? same[seen[k, default: 0]] : same.first { made[i].color = match.color }
            seen[k, default: 0] += 1
            if let group = old.first?.groupID, group != id, old.allSatisfy({ $0.groupID == group }) { made[i].groupID = group }
        }
        objects.removeAll { $0.monogram?.id == id }
        objects.insert(contentsOf: made, at: min(first, objects.count))
        return made.map(\.id)
    }
}
