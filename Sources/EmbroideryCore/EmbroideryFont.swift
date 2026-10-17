// Embroidery fonts: hand-digitized lettering made for Ink/Stitch (a free embroidery program), read from its own
// font folders and turned into this app's satin, running and fill objects. A font folder holds `font.json`
// (name, license, letter height, spacing and kerning), `ltr.svg` (or an `ltr` folder of SVGs) with one layer per
// letter named "GlyphLayer-<letter>", and a LICENSE file. This is our own reader; no Ink/Stitch code is used.
import Foundation

/// One embroidery font: its description from font.json, with the letters themselves read on first use.
public final class EmbroideryFont: @unchecked Sendable {   // the glyph cache below is guarded by a lock
    public let folder: URL
    public let name: String
    public let license: String          // e.g. "SIL Open Font License v1.1"
    public let originalFont: String?
    public let summary: String
    /// Height in mm of the font's reference letter at 100%, and the range of scales it was digitized for.
    public let size: Double, minScale: Double, maxScale: Double
    let advances: [String: Double]      // horizontal advance per glyph, in font units (SVG pixels)
    let defaultAdvance: Double?
    let wordSpacing: Double
    let kerning: [String: Double]
    let letterCase: String
    let defaultGlyph: String?
    private var glyphCache: [String: FontGlyph]?
    private var unit = 25.4 / 96                     // millimeters per font unit (SVG user unit), set when glyphs are read
    private let lock = NSLock()

    /// The letter heights (mm) this font was digitized for.
    public var heights: ClosedRange<Double> { size * minScale...size * max(minScale, maxScale) }

    /// Reads the font's description (font.json) only; the letters are read when first needed.
    public init(folder: URL) throws {
        self.folder = folder
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("font.json")),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DesignError.invalid("‘\(folder.lastPathComponent)’ has no readable font.json.") }
        func number(_ key: String) -> Double? { (json[key] as? NSNumber)?.doubleValue }
        name = json["name"] as? String ?? folder.lastPathComponent
        license = json["font_license"] as? String ?? "See LICENSE"
        originalFont = json["original_font"] as? String
        summary = json["description"] as? String ?? ""
        guard let size = number("size"), size > 0 else { throw DesignError.invalid("‘\(name)’ doesn't say how tall its letters are.") }
        self.size = size
        minScale = number("min_scale") ?? 1; maxScale = number("max_scale") ?? 1
        advances = (json["horiz_adv_x"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        defaultAdvance = number("horiz_adv_x_default")
        wordSpacing = number("horiz_adv_x_space") ?? 20
        kerning = (json["kerning_pairs"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        letterCase = json["letter_case"] as? String ?? ""
        defaultGlyph = json["default_glyph"] as? String
    }

    /// Every embroidery font in `directory` (one folder each), sorted by name. Folders that can't be read are skipped.
    public static func all(in directory: URL) -> [EmbroideryFont] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? EmbroideryFont(folder: $0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The font's LICENSE text.
    public var licenseText: String {
        for name in ["LICENSE", "license", "LICENSE.txt"] { if let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) { return text } }
        return license
    }

    /// The letters, read from the font's SVG files the first time they're needed.
    func glyphs() throws -> [String: FontGlyph] {
        lock.lock(); defer { lock.unlock() }
        if let glyphCache { return glyphCache }
        var files: [URL] = []
        let single = folder.appendingPathComponent("ltr.svg"), many = folder.appendingPathComponent("ltr")
        if FileManager.default.fileExists(atPath: single.path) { files = [single] }
        else { files = ((try? FileManager.default.contentsOfDirectory(at: many, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "svg" }.sorted { $0.path < $1.path } }
        guard !files.isEmpty else { throw DesignError.invalid("‘\(name)’ has no letter drawings (ltr.svg).") }
        var glyphs: [String: FontGlyph] = [:]
        for file in files {
            let reader = FontSVGReader()
            let parser = XMLParser(data: try Data(contentsOf: file))
            parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = reader
            guard parser.parse(), reader.failure == nil else { throw reader.failure ?? DesignError.invalid("‘\(name)’: \(file.lastPathComponent) couldn't be read.") }
            for (key, glyph) in reader.finishedGlyphs() { glyphs[key] = glyph }
            unit = reader.unit
        }
        glyphCache = glyphs
        return glyphs
    }

    /// The glyph names to use for `text`: case changed if the font asks for it, the longest matching glyph name
    /// at each position (so ligatures such as "ff" win), spaces kept as nil, and characters the font lacks listed
    /// (they're replaced by the font's placeholder glyph if it has one, or left out).
    func glyphNames(for text: String, in glyphs: [String: FontGlyph]) -> (names: [String?], missing: [String]) {
        let cased = letterCase == "upper" ? text.uppercased() : letterCase == "lower" ? text.lowercased() : text
        let characters = cased.map(String.init), longest = min(4, glyphs.keys.map(\.count).max() ?? 1)
        var names: [String?] = [], missing: [String] = [], i = 0
        while i < characters.count {
            if characters[i] == " " { names.append(nil); i += 1; continue }
            var matched = false
            for length in stride(from: min(longest, characters.count - i), through: 1, by: -1) {
                let candidate = characters[i..<(i + length)].joined()
                if glyphs[candidate] != nil { names.append(candidate); i += length; matched = true; break }
            }
            if !matched {
                if let fallback = defaultGlyph, fallback != " ", glyphs[fallback] != nil { names.append(fallback) }
                if !missing.contains(characters[i]) { missing.append(characters[i]) }
                i += 1
            }
        }
        return (names, missing)
    }

    /// Lettering in this font: one grouped object per stitched part of each letter, `height` mm tall (the font's
    /// reference letter), set along `shape` (with the arc's `radius` in mm), centered on the hoop, in `color`.
    /// With `centered` false, straight lettering keeps its baseline at y = 0 instead (used to stack lines of text).
    public func shapes(text: String, height: Double, color: ThreadColor, shape: LetteringShape = .straight, radius: Double = 40, centered: Bool = true,
                       spacing: Double = 0, nudges: [Int: Point] = [:]) throws -> LetteringResult {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw DesignError.invalid("Type some text first.") }
        guard text.count <= Lettering.maximumCharacters, !text.contains(where: \.isNewline) else { throw DesignError.invalid("Lettering is one line of up to \(Lettering.maximumCharacters) characters.") }
        let low = heights.lowerBound, high = heights.upperBound
        guard height >= low - 0.05, height <= high + 0.05 else {
            throw DesignError.invalid("\(name) is digitized for letters \(low.formatted(.number.precision(.fractionLength(1))))–\(high.formatted(.number.precision(.fractionLength(1)))) mm tall. Sizes outside that range would sew too dense or too loose.")
        }
        let glyphs = try glyphs()
        let (names, missing) = glyphNames(for: text, in: glyphs)
        var warnings: [String] = []
        if !missing.isEmpty {
            let placeholder = defaultGlyph.flatMap { $0 != " " && glyphs[$0] != nil ? $0 : nil }
            warnings.append("\(name) has no \(missing.map { "‘\($0)’" }.joined(separator: ", ")); \(placeholder.map { "the font's placeholder ‘\($0)’ was used instead" } ?? (missing.count == 1 ? "it was left out" : "they were left out")).")
        }

        // Lay out in font units (millimeters at 100%), the way Ink/Stitch does: each letter is placed by its left
        // edge, kerning and the font's advance widths. `unit` turns font units (SVG user units) into millimeters.
        let unit = lock.withLock { self.unit }
        var x = 0.0, previous: String?
        var placed: [(glyph: FontGlyph, name: String, x: Double)] = []
        for name in names {
            guard let name, let glyph = glyphs[name] else { x += wordSpacing * unit; previous = nil; continue }
            if let previous { x += glyph.minX - (kerning["\(previous) \(name)"] ?? kerning[previous + name] ?? 0) * unit }
            placed.append((glyph, name, x - glyph.minX))
            x += (advances[name].map { $0 * unit } ?? defaultAdvance.map { $0 * unit } ?? (glyph.width + glyph.minX)) - glyph.minX
            previous = name
        }
        guard !placed.isEmpty else { throw DesignError.invalid("None of these characters are in \(name).") }

        let scale = height / size, group = UUID()
        var objects: [RunObject] = [], ends: [(first: Point, last: Point)] = [], letters: [Int] = [], skipped = 0
        for (letter, (glyph, name, offset)) in placed.enumerated() {
            for (part, element) in glyph.elements.enumerated() {
                var object = element.object(name: "Letter \(name)" + (glyph.elements.count > 1 ? " (part \(part + 1))" : ""), color: color)
                object.transform { Point(($0.x + offset) * scale, $0.y * scale) }
                object.groupID = group
                // Specks under 0.3 mm across (stray marks in the font file) can't be sewn; skip them quietly.
                let xs = object.allNodes.map(\.point.x), ys = object.allNodes.map(\.point.y)
                guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max(), max(x1 - x0, y1 - y0) >= 0.3 else { continue }
                // Each part must sew with our engine; parts that don't are left out and counted.
                var check = Design(); check.objects = [object]
                let stitches = (try? StitchEngine.compile(check))?.commands.filter { $0.op == .stitch }.map(\.point) ?? []
                if let first = stitches.first, let last = stitches.last { objects.append(object); ends.append((first, last)); letters.append(letter) } else { skipped += 1 }
            }
        }
        guard !objects.isEmpty else { throw DesignError.invalid("These letters couldn't be converted from \(name).") }
        // Curve and center the letters, moving each part's first and last stitch along with it.
        let (moves, size) = try Lettering.arrange(&objects, letters: letters, height: height, shape: shape, radius: radius, centered: centered, spacing: spacing, nudges: nudges)
        for i in ends.indices { ends[i] = (moves[i](ends[i].first), moves[i](ends[i].last)) }
        // Trim only where the next part starts more than 2 mm away (and after the last one); shorter moves between
        // the parts of a letter are left as plain jumps, which embroidery software normally doesn't cut.
        for i in objects.indices { objects[i].trimAfter = i == objects.count - 1 || ends[i].last.distance(to: ends[i + 1].first) > 2 }
        if skipped > 0 { warnings.append("\(skipped) part\(skipped == 1 ? "" : "s") of these letters couldn't be converted and \(skipped == 1 ? "was" : "were") left out.") }
        return LetteringResult(objects: objects, warnings: warnings, width: size.width, height: size.height)
    }
}

/// One letter of an embroidery font, in millimeters at 100%, with its baseline at y = 0 (y pointing up).
struct FontGlyph {
    var elements: [FontElement]
    var minX: Double
    var width: Double
}

/// One stitched part of a letter.
enum FontElement {
    case satin(nodes: [PathNode], settings: DigitizingSettings)
    case running(nodes: [PathNode], closed: Bool, stitchLength: Double)
    case fill(rings: [[PathNode]], angle: Double)

    func object(name: String, color: ThreadColor) -> RunObject {
        switch self {
        case .satin(let nodes, let settings):
            var o = RunObject(name: name, nodes: nodes, color: color); o.digitizing = settings; return o
        case .running(let nodes, let closed, let length):
            var o = RunObject(name: name, nodes: nodes, color: color); o.closed = closed; o.stitchLength = min(10, max(0.3, length)); return o
        case .fill(let rings, let angle):
            var o = RunObject(name: name, nodes: rings[0], color: color); o.closed = true
            o.holes = rings.count > 1 ? Array(rings.dropFirst()) : nil
            o.digitizing = DigitizingSettings(kind: .fill); o.digitizing?.angle = angle; return o
        }
    }
}

/// Reads one Ink/Stitch font SVG: the baseline guide and every glyph layer's paths.
final class FontSVGReader: NSObject, XMLParserDelegate {
    var failure: Error?
    private var root = SVGMatrix(), viewHeight = 0.0
    /// Millimeters per SVG user unit (the font's spacing and kerning are in these units).
    var unit: Double { root.a }
    private var baseline: Double?                     // SVG units, y pointing down
    private var stack: [(matrix: SVGMatrix, glyph: String?, skip: Bool)] = []
    private var raw: [String: [(subpaths: [SVGSubpath], attributes: [String: String])]] = [:]
    private var order: [String] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        do {
            var context = stack.last ?? (SVGMatrix(), nil, false)
            if stack.isEmpty {
                guard name == "svg" else { throw DesignError.invalid("This isn't an SVG file.") }
                root = try SVGReader().viewport(a)
                let box = try a["viewBox"].map { try SVGScanner.numbers($0) }
                // The page height in user units: the viewBox's, or else the height attribute (which may carry units
                // such as "39.7mm"; without a viewBox one user unit is one CSS pixel).
                viewHeight = try box.map { $0.count == 4 ? $0[3] : 0 } ?? (a["height"].map { try SVGReader().length($0) } ?? 0)
                context.matrix = root
            }
            if name == "guide", a["inkscape:label"] == "baseline", let position = a["position"] {
                // Inkscape stores guide positions measured up from the bottom of the page.
                let numbers = try SVGScanner.numbers(position)
                if numbers.count == 2 { baseline = viewHeight - numbers[1] }
            }
            if ["defs", "symbol", "metadata", "namedview", "use", "text", "image", "clipPath", "mask"].contains(name) { context.skip = true }
            if let transform = a["transform"] { context.matrix = context.matrix.joined(try SVGReader.transform(transform)) }
            if name == "g", let label = a["inkscape:label"], label.hasPrefix("GlyphLayer-") {
                let glyph = String(label.dropFirst("GlyphLayer-".count))
                context.glyph = glyph
                if raw[glyph] == nil { order.append(glyph); raw[glyph] = [] }
            }
            stack.append(context)
            // Paths in a glyph layer; command connectors (inkscape:connection-end) aren't stitches.
            guard !context.skip, let glyph = context.glyph, ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"].contains(name),
                  a["inkscape:connection-end"] == nil else { return }
            let subpaths = try SVGReader().geometry(name, a, matrix: context.matrix)
            if !subpaths.isEmpty { raw[glyph]?.append((subpaths, a)) }
        } catch { failure = error; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if !stack.isEmpty { stack.removeLast() } }

    /// The glyphs, each moved so its baseline is y = 0 (with y pointing up) and converted to stitchable parts.
    func finishedGlyphs() -> [String: FontGlyph] {
        // The baseline guide's position is in the page's units; convert it like any other point.
        let base = root.apply(Point(0, baseline ?? viewHeight)).y
        var result: [String: FontGlyph] = [:]
        for glyph in order {
            guard let items = raw[glyph], !items.isEmpty else { continue }
            let xs = items.flatMap { $0.subpaths.flatMap { $0.points.map(\.x) } }
            guard let minX = xs.min(), let maxX = xs.max() else { continue }
            func up(_ p: Point) -> Point { Point(p.x, base - p.y) }   // baseline to y = 0, y pointing up
            var elements: [FontElement] = []
            for (subpaths, a) in items {
                let moved = subpaths.map { SVGSubpath(points: $0.points.map(up), closed: $0.closed, nodes: $0.nodes.map { var n = $0; n.transform(up); return n }) }
                elements += FontSVGReader.elements(moved, a)
            }
            result[glyph] = FontGlyph(elements: elements, minX: minX, width: maxX - minX)
        }
        return result
    }

    /// Turns one SVG element into stitched parts: a satin column, running stitches along a stroke, or a fill.
    static func elements(_ subpaths: [SVGSubpath], _ a: [String: String]) -> [FontElement] {
        var style: [String: String] = [:]
        for entry in (a["style"] ?? "").split(separator: ";") {
            let parts = entry.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { style[parts[0]] = parts[1] }
        }
        for key in ["fill", "stroke"] where style[key] == nil { style[key] = a[key] }
        func number(_ key: String) -> Double? { a["inkstitch:" + key].flatMap { Double($0.split(separator: " ").first.map(String.init) ?? "") } }
        if a["inkstitch:satin_column"]?.lowercased() == "true" {
            return SatinConversion.nodes(subpaths, reverse: a["inkstitch:reverse_rails"] ?? "automatic", swap: a["inkstitch:swap_rails"]?.lowercased() == "true").map { nodes in
                var settings = DigitizingSettings(kind: .satin)
                settings.relaxedChecks = true
                settings.pullPercent = nil   // the font designer's compensation, below, is the whole amount
                settings.spacing = min(5, max(0.15, number("zigzag_spacing_mm") ?? 0.4))
                // Ink/Stitch's pull compensation is "mm, each side", like ours; two values mean left and right.
                if let values = a["inkstitch:pull_compensation_mm"]?.split(separator: " ").compactMap({ Double($0) }), !values.isEmpty {
                    settings.expansion = min(2, max(0, values.reduce(0, +) / Double(values.count)))
                } else { settings.expansion = 0 }
                func on(_ key: String) -> Bool { a["inkstitch:" + key]?.lowercased() == "true" }
                settings.underlay = on("contour_underlay") ? .edge : on("zigzag_underlay") ? .zigzag : on("center_walk_underlay") ? .center : .none
                return [FontElement.satin(nodes: nodes, settings: settings)]
            } ?? []
        }
        let filled = (style["fill"] ?? "black") != "none"
        if filled {
            let outlines = subpaths.filter { $0.points.count >= 3 }
            guard !outlines.isEmpty, let regions = try? Lettering.regions(outlines) else { return [] }
            var angle = (number("angle") ?? 0).truncatingRemainder(dividingBy: 360)   // into -180…180°, the range fills accept
            if angle > 180 { angle -= 360 } else if angle < -180 { angle += 360 }
            // A "fill" with practically no area (a stray line in the font file) has nothing to fill.
            return regions.filter { abs(AreaGeometry.area(AreaGeometry.ring($0[0]))) >= 0.05 }.map { .fill(rings: $0, angle: angle) }
        }
        guard (style["stroke"] ?? "none") != "none" else { return [] }
        let length = number("running_stitch_length_mm") ?? 2.5
        return subpaths.filter { $0.nodes.count >= 2 }.map { .running(nodes: $0.nodes, closed: $0.closed, stitchLength: length) }
    }
}

/// Converts an Ink/Stitch satin column (two rails plus optional rungs) into this app's satin: edge pairs that
/// follow both rails in step. Between checkpoints (rungs, or matching rail nodes when there are no rungs) the
/// rails are divided in proportion, the same way the satin engine spaces its stitches.
enum SatinConversion {
    static func nodes(_ subpaths: [SVGSubpath], reverse: String, swap: Bool) -> [PathNode]? {
        let paths = subpaths.filter { $0.points.count > 1 }
        guard paths.count >= 2 else { return nil }
        // Rails and rungs: rungs cross both rails, so with more than two subpaths the rails are the ones crossed by
        // the others; if that's unclear, the two longest. With exactly two subpaths both are rails.
        var railIndices = [0, 1]
        if paths.count > 2 {
            let crossings = paths.indices.map { i in paths.indices.filter { j in j != i && crosses(paths[i].points, paths[j].points) }.count }
            let possible = paths.indices.filter { paths.count == 3 ? crossings[$0] == 1 : crossings[$0] > 2 }
            railIndices = possible.count == 2 ? possible : Array(paths.indices.sorted { length(paths[$0].points) > length(paths[$1].points) }.prefix(2))
        }
        var rails = railIndices.map { paths[$0] }
        if swap { rails.reverse() }
        // Rails should run the same way. "automatic" flips the second rail when its ends are closer crossed over.
        func flip(_ subpath: SVGSubpath) -> SVGSubpath { SVGSubpath(points: subpath.points.reversed(), closed: subpath.closed, nodes: subpath.nodes.reversed()) }
        switch reverse {
        case "first": rails[0] = flip(rails[0])
        case "second": rails[1] = flip(rails[1])
        case "both": rails = rails.map(flip)
        case "none": break
        default:
            let a = rails[0].points, b = rails[1].points
            if a[0].distance(to: b.last!) + a.last!.distance(to: b[0]) < a[0].distance(to: b[0]) + a.last!.distance(to: b.last!) { rails[1] = flip(rails[1]) }
        }
        let first = Rail(rails[0].points), second = Rail(rails[1].points)
        guard first.total > 0.05, second.total > 0.05 else { return nil }

        // Checkpoints: positions (distance along each rail) that must be sewn together.
        var checkpoints: [(Double, Double)] = [(0, 0)]
        let rungs = paths.indices.filter { !railIndices.contains($0) }.map { paths[$0].points }
        if !rungs.isEmpty {
            var found: [(Double, Double)] = []
            for rung in rungs { if let p = first.crossing(rung), let q = second.crossing(rung) { found.append((p, q)) } }
            for c in found.sorted(by: { $0.0 < $1.0 }) where c.0 > checkpoints.last!.0 + 0.01 && c.1 > checkpoints.last!.1 + 0.01 && c.0 < first.total - 0.01 && c.1 < second.total - 0.01 { checkpoints.append(c) }
        } else {
            // No rungs: the rails' own nodes, taken in pairs, act as rungs (only the inner ones; the ends always pair).
            let n1 = rails[0].nodes.dropFirst().dropLast().map { first.position(of: $0.point) }, n2 = rails[1].nodes.dropFirst().dropLast().map { second.position(of: $0.point) }
            for (p, q) in zip(n1, n2) where p > checkpoints.last!.0 + 0.01 && q > checkpoints.last!.1 + 0.01 && p < first.total - 0.01 && q < second.total - 0.01 { checkpoints.append((p, q)) }
        }
        checkpoints.append((first.total, second.total))

        // Edge pairs about every 0.5 mm (further apart on very long columns, to stay under 900 pairs).
        let spacing = max(0.5, max(first.total, second.total) / 900)
        var nodes: [PathNode] = []
        for (a, b) in zip(checkpoints, checkpoints.dropFirst()) {
            let span1 = b.0 - a.0, span2 = b.1 - a.1
            let steps = max(1, Int(ceil(max(span1, span2) / spacing)))
            for k in (nodes.isEmpty ? 0 : 1)...steps {
                let t = Double(k) / Double(steps)
                nodes.append(PathNode(first.at(a.0 + span1 * t))); nodes.append(PathNode(second.at(a.1 + span2 * t)))
            }
        }
        return nodes.count >= 4 ? nodes : nil
    }

    static func length(_ points: [Point]) -> Double { AreaGeometry.pathLength(points) }
    static func crosses(_ a: [Point], _ b: [Point]) -> Bool {
        for (p, q) in zip(a, a.dropFirst()) { for (r, s) in zip(b, b.dropFirst()) where AreaGeometry.intersects(p, q, r, s) { return true } }
        return false
    }

    /// A polyline measured by distance along it.
    struct Rail {
        let points: [Point], distances: [Double]
        var total: Double { distances.last ?? 0 }
        init(_ points: [Point]) {
            self.points = points
            var d = [0.0]; for (a, b) in zip(points, points.dropFirst()) { d.append(d.last! + a.distance(to: b)) }
            distances = d
        }
        /// The point `distance` along the rail.
        func at(_ distance: Double) -> Point {
            let target = max(0, min(total, distance))
            guard let i = distances.firstIndex(where: { $0 >= target }), i > 0 else { return points[0] }
            let span = distances[i] - distances[i - 1]
            return span > 0 ? points[i - 1] + (points[i] - points[i - 1]) * ((target - distances[i - 1]) / span) : points[i]
        }
        /// How far along the rail the point nearest `p` is.
        func position(of p: Point) -> Double {
            var best = (distance: Double.infinity, along: 0.0)
            for i in points.indices.dropLast() {
                let q = AreaGeometry.projection(p, points[i], points[i + 1]), d = q.distance(to: p)
                if d < best.distance { best = (d, distances[i] + points[i].distance(to: q)) }
            }
            return best.along
        }
        /// How far along the rail the rung first crosses it (rungs are drawn slightly longer than the gap), or nil.
        func crossing(_ rung: [Point]) -> Double? {
            for (r, s) in zip(rung, rung.dropFirst()) {
                for i in points.indices.dropLast() {
                    let a = points[i], b = points[i + 1], u = b - a, v = s - r, den = AreaGeometry.cross(u, v)
                    guard abs(den) > 1e-12 else { continue }
                    let t = AreaGeometry.cross(r - a, v) / den, w = AreaGeometry.cross(r - a, u) / den
                    if t >= 0, t <= 1, w >= 0, w <= 1 { return distances[i] + a.distance(to: b) * t }
                }
            }
            return nil
        }
    }
}
