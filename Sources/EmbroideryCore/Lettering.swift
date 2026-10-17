// Lettering turns typed text into embroidery shapes using the fonts installed on this Mac.
// Core Text (Apple's built-in text engine) lays out the letters and supplies each one's outline; the SVG path
// reader and hole finder then turn those outlines into ordinary fill or outline objects, grouped together.
import Foundation
import CoreText

/// How lettering is stitched: solid tatami fill, or a running stitch around each letter's edges.
public enum LetteringStitch: String, Codable, CaseIterable, Sendable {
    case fill, outline
    public var title: String { self == .fill ? "Fill" : "Outline" }
}

/// The line lettering sits on: straight, or curved along part of a circle. "Arch up" bows upward like the top
/// of a round badge; "arch down" curves the other way like the bottom of one, still reading left to right.
public enum LetteringShape: String, Codable, CaseIterable, Sendable {
    case straight, archUp, archDown
    public var title: String {
        switch self { case .straight: return "Straight"; case .archUp: return "Arch up"; case .archDown: return "Arch down" }
    }
}

public struct LetteringResult: Sendable {
    public var objects: [RunObject]
    public var warnings: [String]
    public var width: Double
    public var height: Double
}

public enum Lettering {
    public static let maximumCharacters = 100
    public static let heights = 3.0...200.0
    /// Arc radii (mm, measured to the baseline) for curved lettering.
    public static let radii = 5.0...1000.0

    /// Builds one grouped shape per letter part for `text`, in the font with this PostScript name (its unique
    /// internal name, such as "AvenirNext-Heavy"), scaled so capital letters are `height` mm tall, set along
    /// `shape` (with the arc's `radius` in mm) and centered on the hoop's center. Throws if the font isn't
    /// installed or nothing in the text has an outline to stitch. With `centered` false, straight lettering keeps
    /// its baseline at y = 0 instead (used to stack lines of text).
    public static func shapes(text: String, fontName: String, height: Double, stitch: LetteringStitch, color: ThreadColor,
                              shape: LetteringShape = .straight, radius: Double = 40, centered: Bool = true, spacing: Double = 0, nudges: [Int: Point] = [:]) throws -> LetteringResult {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw DesignError.invalid("Type some text first.") }
        guard text.count <= maximumCharacters, !text.contains(where: \.isNewline) else { throw DesignError.invalid("Lettering is one line of up to \(maximumCharacters) characters.") }
        guard heights.contains(height) else { throw DesignError.invalid("Letter height must be between \(Int(heights.lowerBound)) and \(Int(heights.upperBound)) mm.") }
        // Core Text quietly substitutes a default font for unknown names, so check we got the one asked for.
        let font = CTFontCreateWithName(fontName as CFString, 100, nil)
        guard CTFontCopyPostScriptName(font) as String == fontName else { throw DesignError.invalid("The font ‘\(fontName)’ isn't installed on this Mac.") }
        let capHeight = CTFontGetCapHeight(font)
        let scale = height / (capHeight > 1 ? capHeight : CTFontGetAscent(font))   // millimeters per font unit

        // A CTLine is one laid-out line of text: Core Text picks the glyphs (letter drawings) and their positions,
        // including kerning. It splits the line into runs, one per font used.
        let string = text as NSString
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        var objects: [RunObject] = [], warnings: [String] = []
        var letters: [Int] = [], letter = -1   // which letter each object belongs to, counting every glyph
        func warn(_ note: String) { if !warnings.contains(note) { warnings.append(note) } }
        let group = UUID()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            if CTFontCopyPostScriptName(runFont) as String != fontName {
                warn("Some characters aren't in this font, so macOS used \(CTFontCopyDisplayName(runFont) as String) for them.")
            }
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count), indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)   // a length of 0 means "the whole run"
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for i in 0..<count {
                try Task.checkCancellation()
                letter += 1
                let character = string.substring(with: string.rangeOfComposedCharacterSequence(at: indices[i]))
                // Scale font units to millimeters and move the glyph to its place on the line.
                var placement = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: positions[i].x * scale, ty: positions[i].y * scale)
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], &placement) else {
                    if !character.allSatisfy(\.isWhitespace) { warn("‘\(character)’ has no outline to stitch and was left out.") }
                    continue
                }
                let regions: [[[PathNode]]]
                do { regions = try letterRegions(path) } catch { warn("‘\(character)’ couldn't be made into a clean shape and was left out."); continue }
                for (part, rings) in regions.enumerated() {
                    let name = "Letter \(character)" + (part > 0 ? " (part \(part + 1))" : "")
                    switch stitch {
                    case .fill:
                        var object = RunObject(name: name, nodes: rings[0], color: color)
                        object.closed = true; object.holes = rings.count > 1 ? Array(rings.dropFirst()) : nil
                        object.digitizing = DigitizingSettings(kind: .fill); object.groupID = group
                        objects.append(object); letters.append(letter)
                    case .outline:
                        // One closed running line per edge, the letter's outside first, then the edges of its holes.
                        for ring in rings {
                            var object = RunObject(name: name, nodes: ring, color: color)
                            object.closed = true; object.groupID = group
                            objects.append(object); letters.append(letter)
                        }
                    }
                }
            }
        }
        guard !objects.isEmpty else { throw DesignError.invalid("None of these characters have outlines to stitch in this font.") }
        if stitch == .fill && height < 10 { warn("Fill letters under about 10 mm tall can look rough. For small text, pick an embroidery font (hand-digitized satin) instead.") }

        let size = try arrange(&objects, letters: letters, height: height, shape: shape, radius: radius, centered: centered, spacing: spacing, nudges: nudges).size
        var check = Design(); check.objects = objects; try check.validate()
        return LetteringResult(objects: objects, warnings: warnings, width: size.width, height: size.height)
    }

    /// Sets straight lettering (baseline at y = 0) along `shape`, then centers it on the hoop (unless `centered`
    /// is false). On an arc each
    /// letter is turned whole to follow the curve, so its shape and stitches don't change; fill rows turn with it.
    /// `letters[i]` says which letter object i belongs to. Returns where each object's points moved (so other
    /// points, such as stitch ends, can be moved the same way) and the lettering's finished width and height.
    /// `spacing` (mm) is added between neighbouring letters before the letters follow an arc (so it bends with it).
    /// `nudges` then moves single letters (by letter number, in mm along the baseline and up) after everything is
    /// placed and centered, so nudging one letter never shifts the others; on an arc it follows that letter's tilt.
    static func arrange(_ objects: inout [RunObject], letters: [Int], height: Double, shape: LetteringShape, radius: Double, centered: Bool = true,
                        spacing: Double = 0, nudges: [Int: Point] = [:]) throws -> (moves: [(Point) -> Point], size: (width: Double, height: Double)) {
        func bounds(_ objects: [RunObject]) -> (min: Point, max: Point) {
            let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }   // the curves, not just the nodes
            return (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
        }
        var moves = [(Point) -> Point](repeating: { $0 }, count: objects.count)
        // Each letter's own directions along its baseline and up (tilted on an arc), for its nudge at the end.
        var frames: [Int: (along: Point, up: Point)] = [:]
        for i in objects.indices {
            if spacing != 0 { let shift = Point(Double(letters[i]) * spacing, 0); objects[i].transform { $0 + shift }; moves[i] = { $0 + shift } }
            objects[i].letterKey = letters[i]
        }
        if shape != .straight {
            guard radii.contains(radius) else { throw DesignError.invalid("The arc radius must be between \(Int(radii.lowerBound)) and \(Int(radii.upperBound)) mm.") }
            guard radius >= height * 1.5 else { throw DesignError.invalid("The arc is too tight for letters this tall. Use a radius of at least \(Int((height * 1.5).rounded(.up))) mm.") }
            let all = bounds(objects), middle = (all.min.x + all.max.x) / 2
            guard (all.max.x - all.min.x) / radius <= 1.8 * .pi else { throw DesignError.invalid("This text is too long to fit around a \(Int(radius)) mm arc. Use a larger radius or shorter text.") }
            for letter in Set(letters) {
                let members = objects.indices.filter { letters[$0] == letter }
                let box = bounds(members.map { objects[$0] }), center = (box.min.x + box.max.x) / 2
                // The letter's middle travels the same distance along the arc as it did along the straight line.
                // `base` is where its baseline middle lands, `along` the arc's direction there, and `up` the
                // direction the letter's top points: away from the circle's center for arch up, toward it for arch down.
                let angle = (center - middle) / radius
                let base = shape == .archUp ? Point(radius * sin(angle), radius * cos(angle) - radius) : Point(radius * sin(angle), radius - radius * cos(angle))
                let along = shape == .archUp ? Point(cos(angle), -sin(angle)) : Point(cos(angle), sin(angle))
                let up = Point(-along.y, along.x)
                frames[letter] = (along, up)
                let move: (Point) -> Point = { p in base + along * (p.x - center) + up * p.y }
                let turn = atan2(along.y, along.x) * 180 / .pi
                for i in members {
                    let before = moves[i]
                    objects[i].transform(move); moves[i] = { move(before($0)) }
                    if objects[i].kind == .fill { let angle = objects[i].settings.angle; objects[i].digitizing?.angle = turned(angle, by: turn) }
                }
            }
        }
        // Center on the hoop.
        let box = bounds(objects), center = centered ? Point((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2) : Point(0, 0)
        for i in objects.indices {
            objects[i].transform { $0 - center }
            let move = moves[i]; moves[i] = { move($0) - center }
        }
        // The nudges last, each letter on its own.
        for i in objects.indices {
            guard let nudge = nudges[letters[i]] else { continue }
            let frame = frames[letters[i]] ?? (Point(1, 0), Point(0, 1)), shift = frame.along * nudge.x + frame.up * nudge.y
            objects[i].transform { $0 + shift }
            let move = moves[i]; moves[i] = { move($0) + shift }
        }
        return (moves, (box.max.x - box.min.x, box.max.y - box.min.y))
    }

    /// A fill row angle (degrees, -180…180) turned by `degrees`.
    static func turned(_ angle: Double, by degrees: Double) -> Double { (angle + degrees + 540).truncatingRemainder(dividingBy: 360) - 180 }

    /// One glyph's filled areas, each as an outside edge followed by its holes, keeping the font's curves as
    /// Bézier handles. Font outlines use the nonzero fill rule. Overlapping outlines (common in variable fonts),
    /// or curves that don't pass the "edges cross or touch" check, fall back to the polygon resolver, which merges
    /// them as points instead of curves. Throws if neither version is a clean shape.
    static func letterRegions(_ path: CGPath) throws -> [[[PathNode]]] {
        // Rewrite the outline as SVG path text so the existing SVG reader can flatten it and build nodes.
        var text = ""
        path.applyWithBlock { element in
            let p = element.pointee.points
            func xy(_ i: Int) -> String { "\(Double(p[i].x)) \(Double(p[i].y)) " }
            switch element.pointee.type {
            case .moveToPoint: text += "M " + xy(0)
            case .addLineToPoint: text += "L " + xy(0)
            case .addQuadCurveToPoint: text += "Q " + xy(0) + xy(1)
            case .addCurveToPoint: text += "C " + xy(0) + xy(1) + xy(2)
            case .closeSubpath: text += "Z "
            @unknown default: break
            }
        }
        var parser = SVGPathParser(text, matrix: SVGMatrix())
        let outlines = try parser.parse().filter { $0.points.count >= 3 }
        guard !outlines.isEmpty else { return [] }
        return try regions(outlines)
    }

    /// Filled areas from closed outlines under the nonzero rule, each an outside edge followed by its holes,
    /// keeping curves where the outlines are clean (also used for fills in embroidery fonts).
    static func regions(_ outlines: [SVGSubpath]) throws -> [[[PathNode]]] {
        func clean(_ regions: [[[PathNode]]]) -> Bool { (try? regions.forEach { try AreaGeometry.validate($0.map { AreaGeometry.ring($0) }) }) != nil }
        // A few letters nearly touch themselves once their curves become editable nodes; those use points instead.
        if let curved = try SVGReader.curvedRegions(outlines, nonzero: true), clean(curved) { return curved }
        let merged = try AreaGeometry.svgRegions(outlines.map(\.points), nonzero: true).map { $0.map { $0.map { PathNode($0) } } }
        guard clean(merged) else { throw DesignError.invalid("Outline edges cross or touch.") }
        return merged
    }
}
