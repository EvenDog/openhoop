// Live lettering: every letter object remembers the "recipe" it was made from (text, font, size, shape) plus
// three marker points that move whenever the letters move. Editing the text cooks the recipe again and uses the
// markers to put the new letters exactly where, and at the angle, the old ones were.
import Foundation

/// How the lines of multi-line lettering line up with each other.
public enum LetteringAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
    public var title: String { rawValue.capitalized }
}

/// Everything needed to rebuild a piece of lettering. Each object made from it carries a copy.
public struct LetteringSpec: Codable, Hashable, Sendable {
    public enum FontKind: String, Codable, Sendable { case embroidery, system }
    /// Ties together the objects made from one piece of lettering (separately from grouping).
    public var id = UUID()
    public var text: String
    public var fontKind: FontKind
    /// An embroidery font's folder name, or a system font's PostScript name (such as "AvenirNext-Bold").
    public var font: String
    /// Fill or outline; only used by system fonts (embroidery fonts bring their own stitches).
    public var stitch: LetteringStitch
    public var height: Double
    public var shape: LetteringShape
    public var radius: Double
    /// Multi-line lettering: how the lines line up (nil means centered), and the distance from one line's baseline
    /// to the next as a multiple of the letter height (nil means the default).
    public var alignment: LetteringAlignment?
    public var lineSpacing: Double?
    /// Extra space between letters, in mm (negative tightens); nil means the font's own spacing.
    public var letterSpacing: Double?
    public static let letterSpacings = -3.0...10.0
    /// Letters nudged with Edit Nodes: by letter key (line × 1000 + place in the line), how far the letter moved
    /// along and up from where the font puts it, as a share of the letter height, so the nudge scales with the size
    /// and survives changing the text, font or size. nil means none.
    public var letterOffsets: [Int: Point]?
    /// Where the lettering starts and ends sewing (Start & End points), in mm, or nil. Lettering sews its letters in
    /// order, so the start goes on its first letter and the end on its last; kept here so rebuilding keeps them.
    public var entry: Point?
    public var exit: Point?
    public static let defaultLineSpacing = 1.4, lineSpacings = 0.8...4.0, maximumLines = 10
    /// Placement markers, in mm. Freshly made lettering is centered on `anchor` = (0, 0), with `alongMarker`
    /// 10 mm to the right (the reading direction) and `upMarker` 10 mm up. They move, turn and mirror with the
    /// letters, so together they record where the lettering is and which way it faces.
    public var anchor = Point(0, 0)
    public var alongMarker = Point(10, 0)
    public var upMarker = Point(0, 10)

    public init(text: String, fontKind: FontKind, font: String, stitch: LetteringStitch = .fill, height: Double, shape: LetteringShape = .straight, radius: Double = 40) {
        self.text = text; self.fontKind = fontKind; self.font = font; self.stitch = stitch; self.height = height; self.shape = shape; self.radius = radius
    }

    /// The letter height as it is now: resizing the letters stretches the markers too, so this can differ from
    /// `height`. Rounded to 0.1 mm.
    public var currentHeight: Double {
        let scale = upMarker.distance(to: anchor) / 10
        return (height * scale * 10).rounded() / 10
    }

    /// Moves the markers with the letters (called from RunObject.transform).
    public mutating func transform(_ body: (Point) -> Point) {
        anchor = body(anchor); alongMarker = body(alongMarker); upMarker = body(upMarker)
        entry = entry.map(body); exit = exit.map(body)
    }

    /// Builds the lettering and puts it where the markers say: centered on `anchor`, turned and mirrored like
    /// the markers (any stretching is left out; the letters are `height` tall). Every object gets a copy of this
    /// spec and a new group. Embroidery fonts are looked up by folder name in `embroideryFonts`.
    public func build(color: ThreadColor, embroideryFonts: [EmbroideryFont]) throws -> LetteringResult {
        var result = try stackedLines(color: color, embroideryFonts: embroideryFonts)
        // The placement: `along` is the reading direction; `up` is a quarter turn to its left, or to its right
        // when the markers have been mirrored. A point (x, y) of the centered lettering lands at anchor + x·along + y·up.
        let along = unit(alongMarker - anchor) ?? Point(1, 0)
        let mirrored = cross(alongMarker - anchor, upMarker - anchor) < 0
        let up = mirrored ? Point(along.y, -along.x) : Point(-along.y, along.x)
        let turn = atan2(along.y, along.x) * 180 / .pi
        var spec = self
        spec.anchor = anchor; spec.alongMarker = anchor + along * 10; spec.upMarker = anchor + up * 10
        for i in result.objects.indices {
            result.objects[i].transform { p in anchor + along * p.x + up * p.y }
            // Fill rows turn with the letters; mirroring also reflects them.
            if result.objects[i].kind == .fill {
                let angle = result.objects[i].settings.angle
                result.objects[i].digitizing?.angle = Lettering.turned(mirrored ? -angle : angle, by: turn)
            }
            result.objects[i].lettering = spec
        }
        // The lettering's start goes on its first letter, its end on its last.
        if !result.objects.isEmpty { result.objects[0].entry = entry; result.objects[result.objects.count - 1].exit = exit }
        return result
    }

    /// The text's lines, without blank lines at the start or end.
    public var lines: [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func blank(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).isEmpty }
        while lines.first.map(blank) == true { lines.removeFirst() }
        while lines.last.map(blank) == true { lines.removeLast() }
        return lines
    }

    /// The lettering centered on the hoop, before it's placed by the markers. One line is built as it is (and can
    /// follow an arc); several lines are built one by one on their own baselines, `lineSpacing` × height apart,
    /// lined up by `alignment`, and joined into one group sewn line by line.
    private func stackedLines(color: ThreadColor, embroideryFonts: [EmbroideryFont]) throws -> LetteringResult {
        let lines = self.lines
        /// One line of lettering, its letters spaced (and, for a single line, nudged), each part knowing its letter
        /// (line × 1000 + place).
        func line(_ text: String, number: Int, centered: Bool) throws -> LetteringResult {
            let spacing = letterSpacing ?? 0
            let nudges = centered ? Dictionary(uniqueKeysWithValues: (letterOffsets ?? [:]).filter { $0.key / 1000 == number }.map { ($0.key % 1000, $0.value * height) }) : [:]
            var result: LetteringResult
            switch fontKind {
            case .embroidery:
                guard let embroideryFont = embroideryFonts.first(where: { $0.folder.lastPathComponent == font }) else { throw DesignError.invalid("The embroidery font ‘\(font)’ isn't available.") }
                result = try embroideryFont.shapes(text: text, height: height, color: color, shape: shape, radius: radius, centered: centered, spacing: spacing, nudges: nudges)
            case .system:
                result = try Lettering.shapes(text: text, fontName: font, height: height, stitch: stitch, color: color, shape: shape, radius: radius, centered: centered, spacing: spacing, nudges: nudges)
            }
            for i in result.objects.indices { result.objects[i].letterKey = number * 1000 + (result.objects[i].letterKey ?? 0) }
            return result
        }
        guard lines.count > 1 else { return try line(lines.first ?? text, number: 0, centered: true) }
        guard lines.count <= Self.maximumLines else { throw DesignError.invalid("Lettering can have up to \(Self.maximumLines) lines.") }
        guard shape == .straight else { throw DesignError.invalid("Curved lettering is one line. Choose Straight for several lines, or make each curved line its own lettering.") }
        let spacing = lineSpacing ?? Self.defaultLineSpacing
        guard Self.lineSpacings.contains(spacing) else { throw DesignError.invalid("Line spacing must be between \(Self.lineSpacings.lowerBound) and \(Self.lineSpacings.upperBound) times the letter height.") }

        var objects: [RunObject] = [], warnings: [String] = []
        let group = UUID()
        for (index, text) in lines.enumerated() where !text.trimmingCharacters(in: .whitespaces).isEmpty {   // blank lines just add space
            var built = try line(text, number: index, centered: false)
            // Line up the line's left edge, middle or right edge at x = 0, and move it down to its baseline.
            let xs = built.objects.flatMap { $0.outlinePaths.flatMap { $0.map(\.x) } }
            let shift = Point(-(alignment == .left ? xs.min()! : alignment == .right ? xs.max()! : (xs.min()! + xs.max()!) / 2), -Double(index) * spacing * height)
            for i in built.objects.indices { built.objects[i].transform { $0 + shift }; built.objects[i].groupID = group }
            objects += built.objects
            warnings += built.warnings.filter { !warnings.contains($0) }
        }
        // Center the whole block on the hoop.
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        let low = Point(points.map(\.x).min()!, points.map(\.y).min()!), high = Point(points.map(\.x).max()!, points.map(\.y).max()!)
        let center = (low + high) * 0.5
        for i in objects.indices { objects[i].transform { $0 - center } }
        // Nudged letters move last, after the lines are lined up and centered, so the rest stay put.
        for i in objects.indices {
            guard let key = objects[i].letterKey, let nudge = letterOffsets?[key] else { continue }
            objects[i].transform { $0 + nudge * height }
        }
        var check = Design(); check.objects = objects; try check.validate()
        return LetteringResult(objects: objects, warnings: warnings, width: high.x - low.x, height: high.y - low.y)
    }

    /// True if `objects` (this lettering's objects, in sewing order) are just as `build` would make them: no letter
    /// reshaped, deleted or reordered, and no stitch settings changed. Colors, names, hiding and locking don't count.
    public func matchesFreshBuild(_ objects: [RunObject], embroideryFonts: [EmbroideryFont]) -> Bool {
        guard let color = objects.first?.color, let fresh = try? build(color: color, embroideryFonts: embroideryFonts).objects,
              fresh.count == objects.count else { return false }
        func near(_ p: Point?, _ q: Point?) -> Bool { p == nil && q == nil || (p.flatMap { p in q.map { p.distance(to: $0) < 0.01 } } ?? false) }
        func same(_ a: [PathNode], _ b: [PathNode]) -> Bool {
            return a.count == b.count && zip(a, b).allSatisfy { near($0.point, $1.point) && $0.smooth == $1.smooth && near($0.inHandle, $1.inHandle) && near($0.outHandle, $1.outHandle) }
        }
        return zip(objects, fresh).allSatisfy { old, new in
            var oldSettings = old.digitizing, newSettings = new.digitizing   // angles are compared with a tolerance
            let anglesMatch = abs(Lettering.turned(old.settings.angle, by: -new.settings.angle)) < 0.01
            oldSettings?.angle = 0; newSettings?.angle = 0
            return same(old.nodes, new.nodes) && (old.holes ?? []).count == (new.holes ?? []).count && zip(old.holes ?? [], new.holes ?? []).allSatisfy(same)
                && old.closed == new.closed && oldSettings == newSettings && anglesMatch && old.stitchLength == new.stitchLength
                && old.tieIn == new.tieIn && old.tieOut == new.tieOut && old.trimAfter == new.trimAfter && old.stopAfter == new.stopAfter
                && near(old.entry, new.entry) && near(old.exit, new.exit)
        }
    }

    private func unit(_ p: Point) -> Point? { let length = hypot(p.x, p.y); return length > 1e-9 ? p * (1 / length) : nil }
    private func cross(_ a: Point, _ b: Point) -> Double { a.x * b.y - a.y * b.x }
}

extension Design {
    /// The objects made from the lettering with this id, in sewing order.
    public func letteringObjects(_ id: UUID) -> [RunObject] { objects.filter { $0.lettering?.id == id } }

    /// Sets where the lettering with this id starts sewing (nil clears it): on its first letter, and in its recipe so
    /// rebuilding keeps it.
    public mutating func setLetteringStart(_ id: UUID, _ point: Point?) {
        guard let first = objects.firstIndex(where: { $0.lettering?.id == id }) else { return }
        for i in objects.indices where objects[i].lettering?.id == id { objects[i].lettering?.entry = point }
        objects[first].entry = point
    }
    /// Sets where the lettering with this id ends sewing (nil clears it): on its last letter, and in its recipe.
    public mutating func setLetteringEnd(_ id: UUID, _ point: Point?) {
        guard let last = objects.lastIndex(where: { $0.lettering?.id == id }) else { return }
        for i in objects.indices where objects[i].lettering?.id == id { objects[i].lettering?.exit = point }
        objects[last].exit = point
    }

    /// Replaces the lettering with `spec.id` by `result` (from `spec.build`): the new letters take the old ones'
    /// place in the sewing order and their group. Returns the new objects' IDs.
    @discardableResult
    public mutating func replaceLettering(_ id: UUID, with result: LetteringResult) -> [UUID] {
        guard let first = objects.firstIndex(where: { $0.lettering?.id == id }) else { return [] }
        let group = objects[first].groupID
        var letters = result.objects
        for i in letters.indices { if let group { letters[i].groupID = group } }
        objects.removeAll { $0.lettering?.id == id }
        objects.insert(contentsOf: letters, at: min(first, objects.count))
        return letters.map(\.id)
    }
}
