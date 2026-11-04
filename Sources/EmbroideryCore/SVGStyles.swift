// The CSS in an SVG's <style> blocks, as design apps write it: rules that pick shapes by tag name, .class or #id
// (or a mix, like path.cls-1), plus the 148 CSS color names. Not a full CSS engine: rules with other selectors
// (g > path, :hover, @media…) are skipped and counted, so the importer can say so.

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct SVGStyles {
    /// One simple selector, such as `path.cls-1` or `#logo`. A nil tag (or "*") matches any element.
    struct Selector {
        var tag: String?
        var id: String?
        var classes: [String] = []
        /// CSS priority: ids, then classes, then tag names. A higher triple wins.
        var specificity: (Int, Int, Int) { (id == nil ? 0 : 1, classes.count, tag == nil ? 0 : 1) }
        func matches(tag elementTag: String, id elementID: String?, classes elementClasses: [String]) -> Bool {
            (tag == nil || tag == elementTag) && (id == nil || id == elementID) && classes.allSatisfy(elementClasses.contains)
        }
    }
    struct Rule {
        var selector: Selector
        var declarations: [(property: String, value: String)]
        /// Position in the file, so a later rule wins a tie.
        var order: Int
    }

    var rules: [Rule] = []
    /// Rules (or comma-separated parts of one) that were left out because their selector or block isn't supported.
    var skippedRules = 0

    /// Reads every <style> block in an SVG file. They're read before the shapes because a style block may come
    /// after the shapes it colors. Throws for a style that loads another file (@import).
    static func collect(_ data: Data) throws -> SVGStyles {
        let collector = StyleCollector(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.shouldProcessNamespaces = true; parser.delegate = collector
        _ = parser.parse()   // a broken file is reported by the main import pass
        return try SVGStyles(css: collector.css)
    }

    /// No rules: an SVG without <style> blocks.
    init() {}

    /// Parses CSS text into rules.
    init(css: String) throws {
        let text = Array(Self.removingComments(css)), count = text.count
        var i = 0, order = 0
        /// The index just past the `}` closing the block whose `{` is at `open` (nested blocks included).
        func blockEnd(_ open: Int) -> Int {
            var depth = 0, j = open
            while j < count {
                if text[j] == "{" { depth += 1 } else if text[j] == "}" { depth -= 1; if depth == 0 { return j + 1 } }
                j += 1
            }
            return count
        }
        while i < count {
            guard let open = text[i...].firstIndex(where: { $0 == "{" || $0 == ";" }) else { break }
            let prelude = String(text[i..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
            if text[open] == ";" {
                // A statement like @import url(…); or @charset "utf-8";
                if prelude.lowercased().hasPrefix("@import") {
                    throw DesignError.invalid("SVG styles that load other files (@import) are not supported. Export SVG with inline styles or presentation attributes.")
                }
                i = open + 1; continue
            }
            let end = blockEnd(open)
            let body = String(text[(open + 1)..<max(open + 1, end - 1)])
            i = end
            // @media, @font-face and nested rules: not something a stitch file can use.
            if prelude.hasPrefix("@") || body.contains("{") { skippedRules += 1; continue }
            let declarations = Self.declarations(body)
            for part in prelude.split(separator: ",") {
                if let selector = Self.selector(part.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    rules.append(Rule(selector: selector, declarations: declarations, order: order))
                } else {
                    skippedRules += 1
                }
            }
            order += 1
        }
    }

    /// The style properties the rules give an element, the strongest rule's value for each property.
    func declarations(tag: String, id: String?, classes: [String]) -> [String: String] {
        let matching = rules.filter { $0.selector.matches(tag: tag, id: id, classes: classes) }
            .sorted { a, b in
                let x = a.selector.specificity, y = b.selector.specificity
                return (x.0, x.1, x.2, a.order) < (y.0, y.1, y.2, b.order)   // Swift compares tuples left to right
            }
        var result: [String: String] = [:]
        for rule in matching { for (property, value) in rule.declarations { result[property] = value } }   // stronger rules come later and overwrite
        return result
    }

    /// `fill: red; stroke-width: 2px` → [("fill", "red"), ("stroke-width", "2px")]. `!important` is dropped:
    /// design apps don't write it, so its extra priority isn't worth handling.
    static func declarations(_ text: String) -> [(property: String, value: String)] {
        text.split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            var value = parts[1]
            if let bang = value.range(of: "!important", options: .caseInsensitive) { value = value[..<bang.lowerBound].trimmingCharacters(in: .whitespaces) }
            return (parts[0].lowercased(), value)
        }
    }

    /// Parses `tag`, `.class`, `#id`, `*`, or a run of them with no spaces (`path.a.b`). nil for anything else,
    /// such as `g > path`, `.a .b`, `.a:hover` or `[fill]`.
    static func selector(_ text: String) -> Selector? {
        guard !text.isEmpty else { return nil }
        let nameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var selector = Selector(), rest = Substring(text)
        func takeName() -> String? {
            let name = rest.prefix { $0.unicodeScalars.allSatisfy(nameCharacters.contains) }
            rest = rest.dropFirst(name.count)
            return name.isEmpty ? nil : String(name)
        }
        if rest.first == "*" { rest = rest.dropFirst() }
        else if rest.first != "." && rest.first != "#" { guard let tag = takeName() else { return nil }; selector.tag = tag }
        while let mark = rest.first {
            rest = rest.dropFirst()
            guard let name = takeName() else { return nil }
            switch mark {
            case ".": selector.classes.append(name)
            case "#": guard selector.id == nil else { return nil }; selector.id = name
            default: return nil
            }
        }
        return selector
    }

    static func removingComments(_ css: String) -> String {
        var result = "", rest = Substring(css)
        while let start = rest.range(of: "/*") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].range(of: "*/") else { return result }
            rest = rest[end.upperBound...]
        }
        return result + rest
    }

    /// The 148 named colors of CSS, as 0xRRGGBB.
    static let colorNames: [String: Int] = [
        "aliceblue": 0xf0f8ff, "antiquewhite": 0xfaebd7, "aqua": 0x00ffff, "aquamarine": 0x7fffd4, "azure": 0xf0ffff,
        "beige": 0xf5f5dc, "bisque": 0xffe4c4, "black": 0x000000, "blanchedalmond": 0xffebcd, "blue": 0x0000ff,
        "blueviolet": 0x8a2be2, "brown": 0xa52a2a, "burlywood": 0xdeb887, "cadetblue": 0x5f9ea0, "chartreuse": 0x7fff00,
        "chocolate": 0xd2691e, "coral": 0xff7f50, "cornflowerblue": 0x6495ed, "cornsilk": 0xfff8dc, "crimson": 0xdc143c,
        "cyan": 0x00ffff, "darkblue": 0x00008b, "darkcyan": 0x008b8b, "darkgoldenrod": 0xb8860b, "darkgray": 0xa9a9a9,
        "darkgreen": 0x006400, "darkgrey": 0xa9a9a9, "darkkhaki": 0xbdb76b, "darkmagenta": 0x8b008b,
        "darkolivegreen": 0x556b2f, "darkorange": 0xff8c00, "darkorchid": 0x9932cc, "darkred": 0x8b0000,
        "darksalmon": 0xe9967a, "darkseagreen": 0x8fbc8f, "darkslateblue": 0x483d8b, "darkslategray": 0x2f4f4f,
        "darkslategrey": 0x2f4f4f, "darkturquoise": 0x00ced1, "darkviolet": 0x9400d3, "deeppink": 0xff1493,
        "deepskyblue": 0x00bfff, "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1e90ff,
        "firebrick": 0xb22222, "floralwhite": 0xfffaf0, "forestgreen": 0x228b22, "fuchsia": 0xff00ff,
        "gainsboro": 0xdcdcdc, "ghostwhite": 0xf8f8ff, "gold": 0xffd700, "goldenrod": 0xdaa520, "gray": 0x808080,
        "green": 0x008000, "greenyellow": 0xadff2f, "grey": 0x808080, "honeydew": 0xf0fff0, "hotpink": 0xff69b4,
        "indianred": 0xcd5c5c, "indigo": 0x4b0082, "ivory": 0xfffff0, "khaki": 0xf0e68c, "lavender": 0xe6e6fa,
        "lavenderblush": 0xfff0f5, "lawngreen": 0x7cfc00, "lemonchiffon": 0xfffacd, "lightblue": 0xadd8e6,
        "lightcoral": 0xf08080, "lightcyan": 0xe0ffff, "lightgoldenrodyellow": 0xfafad2, "lightgray": 0xd3d3d3,
        "lightgreen": 0x90ee90, "lightgrey": 0xd3d3d3, "lightpink": 0xffb6c1, "lightsalmon": 0xffa07a,
        "lightseagreen": 0x20b2aa, "lightskyblue": 0x87cefa, "lightslategray": 0x778899, "lightslategrey": 0x778899,
        "lightsteelblue": 0xb0c4de, "lightyellow": 0xffffe0, "lime": 0x00ff00, "limegreen": 0x32cd32,
        "linen": 0xfaf0e6, "magenta": 0xff00ff, "maroon": 0x800000, "mediumaquamarine": 0x66cdaa,
        "mediumblue": 0x0000cd, "mediumorchid": 0xba55d3, "mediumpurple": 0x9370db, "mediumseagreen": 0x3cb371,
        "mediumslateblue": 0x7b68ee, "mediumspringgreen": 0x00fa9a, "mediumturquoise": 0x48d1cc,
        "mediumvioletred": 0xc71585, "midnightblue": 0x191970, "mintcream": 0xf5fffa, "mistyrose": 0xffe4e1,
        "moccasin": 0xffe4b5, "navajowhite": 0xffdead, "navy": 0x000080, "oldlace": 0xfdf5e6, "olive": 0x808000,
        "olivedrab": 0x6b8e23, "orange": 0xffa500, "orangered": 0xff4500, "orchid": 0xda70d6,
        "palegoldenrod": 0xeee8aa, "palegreen": 0x98fb98, "paleturquoise": 0xafeeee, "palevioletred": 0xdb7093,
        "papayawhip": 0xffefd5, "peachpuff": 0xffdab9, "peru": 0xcd853f, "pink": 0xffc0cb, "plum": 0xdda0dd,
        "powderblue": 0xb0e0e6, "purple": 0x800080, "rebeccapurple": 0x663399, "red": 0xff0000,
        "rosybrown": 0xbc8f8f, "royalblue": 0x4169e1, "saddlebrown": 0x8b4513, "salmon": 0xfa8072,
        "sandybrown": 0xf4a460, "seagreen": 0x2e8b57, "seashell": 0xfff5ee, "sienna": 0xa0522d, "silver": 0xc0c0c0,
        "skyblue": 0x87ceeb, "slateblue": 0x6a5acd, "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xfffafa,
        "springgreen": 0x00ff7f, "steelblue": 0x4682b4, "tan": 0xd2b48c, "teal": 0x008080, "thistle": 0xd8bfd8,
        "tomato": 0xff6347, "turquoise": 0x40e0d0, "violet": 0xee82ee, "wheat": 0xf5deb3, "white": 0xffffff,
        "whitesmoke": 0xf5f5f5, "yellow": 0xffff00, "yellowgreen": 0x9acd32,
    ]
}

/// Gathers the text inside <style> elements (plain or in a CDATA section) while an XMLParser reads the file.
private final class StyleCollector: NSObject, XMLParserDelegate {
    var css = "", inStyle = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "style" { inStyle += 1; css += "\n" }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "style" { inStyle -= 1 }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inStyle > 0 { css += string } }
    func parser(_ parser: XMLParser, foundCDATA block: Data) { if inStyle > 0 { css += String(decoding: block, as: UTF8.self) } }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
}
