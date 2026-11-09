// Auto-digitizing turns the reference image into stitches. It reduces the picture to a few thread colors,
// traces the outline of every patch of each color along the pixel edges, smooths away the pixel "staircase",
// and stitches each patch by its width (thin lines as running stitch, narrow parts as satin, curved strips as satin
// columns along their middle or, when tapered, satin turning with the strip; the rest as tatami), placed exactly
// over the image; or, painted by hand, each patch as chosen (paint by numbers). With a thread chart chosen, each
// color becomes that chart's closest thread. Colors that are mostly outlines sew last, on top. Parts sew nearest first, fills at angles that follow each shape (touching shapes at
// clearly different angles), fills reach a little under the parts sewn on top of them (so no fabric shows at the
// seams), and each part starts where the one before it ends.
import Foundation
import CoreGraphics
import ImageIO

/// An image as a grid of pixels, 4 bytes each (red, green, blue, alpha), rows from the top.
public struct PixelImage: Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]
    public init(width: Int, height: Int, rgba: [UInt8]) { self.width = width; self.height = height; self.rgba = rgba }

    /// Decodes PNG or JPEG data, shrinking it so its longer side is at most `maxSide` pixels. Photos keep
    /// their camera rotation. Throws if the data isn't a readable image.
    public init(data: Data, maxSide: Int) throws {
        // ImageIO's thumbnail maker decodes and shrinks in one step, which is much faster than decoding full size.
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: maxSide] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw DesignError.invalid("The reference image couldn't be read.") }
        // Local copies: Swift doesn't let the drawing closure below read self's properties until all are set.
        let width = image.width, height = image.height
        self.width = width; self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // Draw into a plain RGBA buffer. "Premultiplied" means colors are stored already darkened by their
        // transparency, so they are undone below for pixels that are partly see-through.
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width > 0, height > 0 else { throw DesignError.invalid("The reference image couldn't be read.") }
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 0 && bytes[i + 3] < 255 {
            let alpha = Int(bytes[i + 3])
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, Int(bytes[i + c]) * 255 / alpha)) }
        }
        rgba = bytes
    }

    /// This image (the artwork's picture, decoded) drawn the way `artwork` sits on the canvas, turned, flipped or
    /// skewed, into a level grid covering `box` (mm) at `width` × `height` pixels. Each pixel takes the color under its
    /// middle (the nearest picture pixel); pixels outside the picture are transparent and marked in `outside`.
    public func placed(_ artwork: Artwork, in box: (min: Point, max: Point), width: Int, height: Int) -> (image: PixelImage, outside: [Bool]) {
        var bytes = [UInt8](repeating: 0, count: width * height * 4), outside = [Bool](repeating: true, count: width * height)
        let pixelWidth = (box.max.x - box.min.x) / Double(width), pixelHeight = (box.max.y - box.min.y) / Double(height)
        for row in 0..<height { for column in 0..<width {
            // The pixel's middle on the canvas (rows run down from the top), then in the picture's own frame.
            let own = artwork.local(Point(box.min.x + (Double(column) + 0.5) * pixelWidth, box.max.y - (Double(row) + 0.5) * pixelHeight))
            let u = Int(((own.x / artwork.width) + 0.5) * Double(self.width)), v = Int((0.5 - own.y / artwork.height) * Double(self.height))
            guard (0..<self.width).contains(u), (0..<self.height).contains(v) else { continue }
            let from = (v * self.width + u) * 4, to = (row * width + column) * 4
            for c in 0..<4 { bytes[to + c] = rgba[from + c] }
            outside[row * width + column] = false
        } }
        return (PixelImage(width: width, height: height, rgba: bytes), outside)
    }
}

public struct AutoDigitizeOptions: Equatable, Sendable {
    public var colors = 4             // how many thread colors the picture is reduced to
    public var skipBackground = true  // leave out the transparent area, or the color around the image's edges
    public var smallestArea = 2.0     // square millimeters; smaller patches are left out
    public var chart: ThreadChart?    // the chart chosen in Threads: colors become its threads; nil keeps the picture's colors
    public init() {}
    public static let colorRange = 2...8
}

/// One thread color found in the picture.
public struct AutoDigitizeColor: Sendable, Equatable {
    public var color: ThreadColor
    public var area: Double       // square millimeters covered
    public var parts: Int         // objects made in this color
    public var background: Bool   // left out as the background
}

/// What a traced patch is sewn as when set by hand (paint-by-numbers auto-digitizing). See
/// `AutoDigitize.stitch(_:as:in:mask:thread:)` for what each one makes.
public enum PatchStitch: String, CaseIterable, Sendable { case tatami, satin, line, leaveOut }

/// A picture traced into patches of color, each with the stitch auto-digitize suggests for it, before anything is
/// stitched. `build` stitches it: as suggested, or with some patches set by hand.
public struct AutoDigitizeTrace: Sendable {
    public struct Patch: Sendable {
        public var region: [[Point]]       // outline, then holes, in mm on the canvas
        public var thread: ThreadColor
        public var suggested: PatchStitch  // what its width picks
        var color: Int                     // its color's index in `colors`
        var made: [RunObject]              // its stitches as suggested
        var kind: AutoDigitize.PartKind
    }
    public var patches: [Patch]
    var colors: [AutoDigitizeColor]
    var masks: [Int: [Bool]]               // each sewn color's pixels, by its index in `colors`
    var geometry: AutoDigitize.TraceGeometry
    var warnings: [String]                 // notes from tracing (small parts left out, holes filled in)

    /// The index of the patch at `point` (in mm), or nil if it's on none, e.g. on the background.
    public func patch(at point: Point) -> Int? { patches.indices.first { AreaGeometry.contains(point, rings: patches[$0].region) } }

    /// Choices for `build` that sew every patch in a thread as `stitches` gives for that thread; threads not in it
    /// keep their suggestions. A patch already suggested that stitch is left out, so it doesn't count as set by hand.
    public func choices(byThread stitches: [ThreadColor: PatchStitch]) -> [Int: PatchStitch] {
        var choices: [Int: PatchStitch] = [:]
        for (index, patch) in patches.enumerated() {
            if let stitch = stitches[patch.thread], stitch != patch.suggested { choices[index] = stitch }
        }
        return choices
    }

    /// The stitches suggested for the patches in `thread`, each once, in the order `PatchStitch` lists them.
    public func suggestions(for thread: ThreadColor) -> [PatchStitch] {
        let suggested = Set(patches.filter { $0.thread == thread }.map(\.suggested))
        return PatchStitch.allCases.filter(suggested.contains)
    }

    /// Stitches the patches: each as `choices` says (keyed by its index in `patches`), the rest as suggested.
    public func build(_ choices: [Int: PatchStitch] = [:]) throws -> AutoDigitizeResult { try AutoDigitize.build(self, choices: choices) }
}

public struct AutoDigitizeResult: Sendable {
    public var objects: [RunObject]
    public var colors: [AutoDigitizeColor]
    public var warnings: [String]
}

public enum AutoDigitize {
    /// Pixels on the longer side used for tracing: about 0.15 mm per pixel, between 200 and 800 pixels.
    public static func tracingSize(for artwork: Artwork) -> Int {
        min(800, max(200, Int(max(artwork.width, artwork.height) / 0.15)))
    }

    /// Traces the artwork's image into fill objects that sit exactly over it on the canvas.
    public static func run(_ artwork: Artwork, options: AutoDigitizeOptions) throws -> AutoDigitizeResult {
        try trace(artwork, options: options).build()
    }

    /// Traces `image`, shown `width` × `height` mm and centered on `center`, into fill objects.
    public static func run(_ image: PixelImage, center: Point, width: Double, height: Double, options: AutoDigitizeOptions) throws -> AutoDigitizeResult {
        try trace(image, center: center, width: width, height: height, options: options).build()
    }

    /// Traces the artwork's image into patches of color, each with the stitch auto-digitize suggests, ready to build.
    /// A turned, flipped or skewed image is traced the way it sits on the canvas.
    public static func trace(_ artwork: Artwork, options: AutoDigitizeOptions) throws -> AutoDigitizeTrace {
        let image = try PixelImage(data: artwork.data, maxSide: tracingSize(for: artwork))
        guard artwork.isTransformed else { return try trace(image, center: artwork.center, width: artwork.width, height: artwork.height, options: options) }
        // Drawn into a level grid round it, about as fine as the picture itself.
        let box = artwork.bounds, boxWidth = box.max.x - box.min.x, boxHeight = box.max.y - box.min.y
        let pixel = max(artwork.width / Double(image.width), artwork.height / Double(image.height))
        let width = max(2, min(1200, Int((boxWidth / pixel).rounded()))), height = max(2, min(1200, Int((boxHeight / pixel).rounded())))
        let placed = image.placed(artwork, in: box, width: width, height: height)
        return try trace(placed.image, center: (box.min + box.max) * 0.5, width: boxWidth, height: boxHeight, options: options, outside: placed.outside)
    }

    /// Traces `image`, shown `width` × `height` mm and centered on `center`, into patches of color: each patch's
    /// outline and holes, its thread, and the stitches its width suggests (see `stitch(_:as:in:mask:thread:)`).
    /// `outside` marks pixels that aren't part of the picture at all (round a turned image); they're left out.
    public static func trace(_ image: PixelImage, center: Point, width: Double, height: Double, options: AutoDigitizeOptions, outside: [Bool]? = nil) throws -> AutoDigitizeTrace {
        guard image.width > 1, image.height > 1, image.rgba.count == image.width * image.height * 4, width > 0, height > 0 else { throw DesignError.invalid("The reference image is empty.") }
        guard AutoDigitizeOptions.colorRange.contains(options.colors) else { throw DesignError.invalid("Choose between 2 and 8 colors.") }
        let w = image.width, h = image.height
        let pixelWidth = width / Double(w), pixelHeight = height / Double(h), pixelArea = pixelWidth * pixelHeight
        var (labels, centers) = try quantize(image, colors: options.colors)
        guard !centers.isEmpty else { throw DesignError.invalid("The reference image is fully transparent, so there is nothing to trace.") }
        // Thread colors come from the picture before speck cleanup, so specks don't count as inside pixels.
        centers = insideColors(image, labels: labels, fallback: centers)
        cleanSpecks(&labels, width: w, height: h)

        // The background is the transparent area if there is one, otherwise the color most common around the edges.
        // Pixels outside the picture are left out like transparent ones but aren't its transparent area: round a
        // turned picture, its edges are the pixels beside them.
        let hasTransparency = outside.map { outside in labels.indices.contains { labels[$0] == -1 && !outside[$0] } } ?? labels.contains(-1)
        var background: Int? = nil
        if options.skipBackground && !hasTransparency {
            var counts = [Int](repeating: 0, count: centers.count)
            if let outside {
                func out(_ x: Int, _ y: Int) -> Bool { x < 0 || y < 0 || x >= w || y >= h || outside[y * w + x] }
                for y in 0..<h { for x in 0..<w where labels[y * w + x] >= 0 && (out(x - 1, y) || out(x + 1, y) || out(x, y - 1) || out(x, y + 1)) { counts[labels[y * w + x]] += 1 } }
            } else {
                for x in 0..<w { counts[labels[x]] += 1; counts[labels[(h - 1) * w + x]] += 1 }
                for y in 0..<h { counts[labels[y * w]] += 1; counts[labels[y * w + w - 1]] += 1 }
            }
            background = counts.indices.max { counts[$0] < counts[$1] }
        }

        // Pixel corner (x, y) in image coordinates → millimeters on the canvas (image rows run down, the canvas runs up).
        let geometry = TraceGeometry(width: w, height: h, pixelWidth: pixelWidth, pixelHeight: pixelHeight, left: center.x - width / 2, top: center.y + height / 2)

        var areas = [Int](repeating: 0, count: centers.count)
        for label in labels where label >= 0 { areas[label] += 1 }
        let order = centers.indices.filter { areas[$0] > 0 }.sorted { areas[$0] > areas[$1] }   // big areas sew first, details on top
        var colors: [AutoDigitizeColor] = [], patches: [AutoDigitizeTrace.Patch] = [], masks: [Int: [Bool]] = [:], warnings: [String] = []
        var smallParts = 0, failedParts = 0, filledHoles = 0
        let sewn = order.filter { $0 != background }
        let chartThreads = options.chart.map { threads(for: sewn.map { centers[$0] }, from: $0) }
        for (number, label) in order.enumerated() {
            try Task.checkCancellation()
            var thread = ThreadColor("Color \(number + 1)", centers[label])
            if let chartThreads, let index = sewn.firstIndex(of: label), let match = chartThreads[index] { thread = match }
            if label == background {
                colors.append(AutoDigitizeColor(color: thread, area: Double(areas[label]) * pixelArea, parts: 0, background: true)); continue
            }
            var mask = labels.map { $0 == label }
            separateDiagonals(&mask, width: w, height: h)
            let traced = traceRings(mask, width: w, height: h)
            // Soften the pixel steps, then smooth by one pixel (at least 0.1 mm): enough to iron out uneven steps on
            // slanted edges, still finer than a thread is wide. Fewer points also keep stitch generation fast.
            let rings = traced.map { simplify(softened($0), tolerance: max(1, 0.1 / min(pixelWidth, pixelHeight))) }.filter { $0.count >= 3 }.map { $0.map { geometry.place($0.x, $0.y) } }
            var parts: [[[Point]]] = []
            for traced in try AreaGeometry.svgRegions(rings, nonzero: false) {
                guard let (region, filled) = fitted(traced, smallest: max(options.smallestArea, 0.05)) else { failedParts += 1; continue }
                filledHoles += filled
                let area = AreaGeometry.area(region[0]).magnitude - region.dropFirst().reduce(0) { $0 + AreaGeometry.area($1).magnitude }
                guard area >= max(options.smallestArea, 0.05) else { smallParts += 1; continue }
                guard (try? AreaGeometry.validate(region)) != nil else { failedParts += 1; continue }
                parts.append(region)
            }
            let colorIndex = colors.count
            masks[colorIndex] = mask
            for region in parts {
                // Left to its width, a patch always gets stitches (a fill if nothing else suits it).
                guard let made = stitch(region, as: nil, in: geometry, mask: mask, thread: thread) else { continue }
                patches.append(AutoDigitizeTrace.Patch(region: region, thread: thread, suggested: made.kind.stitch, color: colorIndex, made: made.objects, kind: made.kind))
            }
            colors.append(AutoDigitizeColor(color: thread, area: Double(areas[label]) * pixelArea, parts: parts.count, background: false))
        }
        if hasTransparency && options.skipBackground == false { warnings.append("Transparent parts of the image are always left out.") }
        if smallParts > 0 { warnings.append("\(smallParts) patch\(smallParts == 1 ? " was" : "es were") smaller than \(options.smallestArea.formatted()) mm² and left out.") }
        if filledHoles > 0 { warnings.append("\(filledHoles) small hole\(filledHoles == 1 ? " was" : "s were") filled in, so \(filledHoles == 1 ? "it's" : "they're") sewn over.") }
        if failedParts > 0 { warnings.append("\(failedParts) part\(failedParts == 1 ? "" : "s") couldn't be traced cleanly and \(failedParts == 1 ? "was" : "were") left out. Try fewer colors or a larger smallest part.") }
        return AutoDigitizeTrace(patches: patches, colors: colors, masks: masks, geometry: geometry, warnings: warnings)
    }

    /// Where a traced image sits: its size in pixels, mm per pixel, and its top left corner on the canvas.
    struct TraceGeometry: Sendable {
        var width: Int, height: Int, pixelWidth: Double, pixelHeight: Double, left: Double, top: Double
        var pixelSize: Double { (pixelWidth + pixelHeight) / 2 }
        /// Pixel corner (x, y) → millimeters on the canvas (image rows run down, the canvas runs up).
        func place(_ x: Double, _ y: Double) -> Point { Point(left + x * pixelWidth, top - y * pixelHeight) }
        /// Millimeters on the canvas → pixel corners in the image (the reverse of `place`).
        func pixel(_ p: Point) -> Point { Point((p.x - left) / pixelWidth, (top - p.y) / pixelHeight) }
    }

    /// How one patch ended up stitched; `stitch` says which brush it counts as, `strip` whether it's an outline-like
    /// strip (a running line or satin along its middle), which decides whether its color sews last.
    enum PartKind: Sendable {
        case line, outline, satin, column, tapered, tatami
        var stitch: PatchStitch { switch self { case .line, .outline: .line; case .satin, .column, .tapered: .satin; case .tatami: .tatami } }
        var strip: Bool { [.line, .outline, .column, .tapered].contains(self) }
    }

    /// Stitches one traced patch: `region` (outline and holes, in mm), `mask` its color's pixels, sewn in `thread`.
    /// With `choice` nil its width decides, as auto-digitize always has; otherwise it is sewn as chosen by hand:
    /// - Line: a triple running stitch down the middle (thinner than 1 mm when its width decides; up to 3 mm when
    ///   chosen), or when chosen for a wider patch, a triple running stitch round each of its edges, as an outline.
    /// - Satin: satin columns along a curved strip 1–8 mm wide, or satin turning with it when tapered; otherwise a
    ///   satin fill, straight across (its width picks this only up to 8 mm across).
    /// - Tatami: a tatami fill.
    /// Returns the objects (not yet named in sewing order) and how it was stitched; nil for Leave out.
    static func stitch(_ region: [[Point]], as choice: PatchStitch?, in geometry: TraceGeometry, mask: [Bool], thread: ThreadColor) -> (objects: [RunObject], kind: PartKind)? {
        if choice == .leaveOut { return nil }
        let g = geometry
        // Area ÷ half the outline is about a strip's width (a dot's radius).
        let area = AreaGeometry.area(region[0]).magnitude - region.dropFirst().reduce(0) { $0 + AreaGeometry.area($1).magnitude }
        let perimeter = region.reduce(0) { $0 + AreaGeometry.pathLength($1 + [$1[0]]) }
        let width = 2 * area / perimeter
        let pixels = region.map { $0.map(g.pixel) }
        // A triple running stitch down the middle of the line, if it has one at least 1 mm long.
        if choice == nil ? width < 1 : choice == .line && width <= 3,
           let line = centerline(of: pixels, mask: mask, width: g.width, height: g.height) {
            let path = simplifyLine(line.path.map { g.place($0.x, $0.y) }[...], tolerance: max(0.1, g.pixelWidth, g.pixelHeight))
            if path.count >= 2, AreaGeometry.pathLength(path) >= 1 {
                var object = RunObject(name: "\(thread.name) line", nodes: path.map { PathNode($0) }, color: thread)
                object.closed = line.closed
                var settings = DigitizingSettings(kind: .run); settings.runPasses = 3; object.digitizing = settings
                return ([object], .line)
            }
        }
        if choice == .line {
            // Too wide for one line down the middle: a triple running stitch round each edge, as an outline.
            let rings = region.map { ring -> RunObject in
                var object = RunObject(name: "\(thread.name) line", nodes: ring.map { PathNode($0) }, color: thread)
                object.closed = true
                var settings = DigitizingSettings(kind: .run); settings.runPasses = 3; object.digitizing = settings
                return object
            }
            return (rings, .outline)
        }
        // A curved strip 1–8 mm wide, too bent for satin fill's one stitch direction: even strips get satin columns
        // along their middle, tapered ones (crescents, swooshes) a satin fill turning with the strip.
        if choice != .tatami, width >= 1 && width <= 8 && turnedBox(region[0]).short > 8,
           let middle = stripMiddle(of: pixels, mask: mask, imageWidth: g.width, imageHeight: g.height, width: width, pixelSize: g.pixelSize) {
            if let columns = satinColumns(along: middle, width: width, pixelSize: g.pixelSize, place: { g.place($0.x, $0.y) }, name: "\(thread.name) satin", thread: thread) {
                return (columns, .column)
            }
            if let turning = turningSatin(region, along: middle, place: { g.place($0.x, $0.y) }, name: "\(thread.name) satin", thread: thread) {
                return ([turning], .tapered)
            }
        }
        var object = RunObject(name: "\(thread.name) area", nodes: region[0].map { PathNode($0) }, color: thread)
        object.closed = true; object.holes = region.count > 1 ? region.dropFirst().map { $0.map { PathNode($0) } } : nil
        object.digitizing = DigitizingSettings(kind: .fill)
        // Left to its width: at most 8 mm across (the short side of the smallest box around it) is satin, stitches
        // straight across. A curved strip has a wider box and stays tatami: one stitch direction can't follow its bends.
        if choice == .satin || (choice == nil && turnedBox(region[0]).short <= 8) {
            object.digitizing?.fillStyle = .satin
            return ([object], .satin)
        }
        return ([object], .tatami)
    }

    /// Stitches a trace's patches: each as `choices` says (keyed by its index in `trace.patches`), the rest as
    /// suggested. Then outline colors sew last, nearest parts next, fills get their angles and reach under later
    /// parts, and each part starts where the one before ended.
    static func build(_ trace: AutoDigitizeTrace, choices: [Int: PatchStitch]) throws -> AutoDigitizeResult {
        var colors = trace.colors, warnings: [String] = []
        // Each sewn color's parts: the region, the objects stitching it, and whether it is a strip (a running line or
        // satin along its middle). They're put in sewing order and named once all colors are stitched.
        var tracedColors: [(thread: ThreadColor, colorIndex: Int, parts: [(region: [[Point]], objects: [RunObject], strip: Bool)])] =
            colors.indices.filter { !colors[$0].background }.map { (thread: colors[$0].color, colorIndex: $0, parts: []) }
        var counts: [PartKind: Int] = [:], byHand = 0
        for (index, patch) in trace.patches.enumerated() {
            try Task.checkCancellation()
            let choice = choices[index] ?? patch.suggested
            var stitched: (objects: [RunObject], kind: PartKind)? = (patch.made, patch.kind)
            if choice != patch.suggested {
                byHand += 1
                stitched = stitch(patch.region, as: choice, in: trace.geometry, mask: trace.masks[patch.color] ?? [], thread: patch.thread)
            }
            guard let stitched, let c = tracedColors.firstIndex(where: { $0.colorIndex == patch.color }) else { continue }
            tracedColors[c].parts.append((patch.region, stitched.objects, stitched.kind.strip))
            counts[stitched.kind, default: 0] += stitched.kind == .column ? stitched.objects.count : 1
        }
        for color in tracedColors { colors[color.colorIndex].parts = color.parts.count }
        var objects: [RunObject] = [], shapes: [[[Point]]] = []   // each object's traced part (outline and holes), before any overlap
        // A color that is mostly outlines (at least half its area in running stitch lines and satin columns) sews last,
        // on top of the fills it outlines: its edges cover theirs, and they reach under it (see `overlap`).
        func area(_ region: [[Point]]) -> Double { AreaGeometry.area(region[0]).magnitude - region.dropFirst().reduce(0) { $0 + AreaGeometry.area($1).magnitude } }
        let outlines = tracedColors.count < 2 ? [] : tracedColors.indices.filter { c in
            let all = tracedColors[c].parts.reduce(0) { $0 + area($1.region) }, strips = tracedColors[c].parts.filter(\.strip).reduce(0) { $0 + area($1.region) }
            return all > 0 && strips >= all / 2
        }
        for c in tracedColors.indices.filter({ !outlines.contains($0) }) + outlines {
            // Nearest part next, starting near where the color before ended.
            let parts = nearestFirst(tracedColors[c].parts, region: \.region, after: objects.last.map { AreaGeometry.centroid($0.nodes.map(\.point)) })
            for (number, part) in parts.enumerated() {
                for (column, object) in part.objects.enumerated() {
                    // Named in sewing order, e.g. "Black satin 3", or "Black satin 3.2" for a strip's second column.
                    var object = object
                    object.name += " \(number + 1)" + (part.objects.count > 1 ? ".\(column + 1)" : "")
                    objects.append(object); shapes.append(part.region)
                }
            }
        }
        if !outlines.isEmpty {
            let colorIndexes = outlines.map { tracedColors[$0].colorIndex }
            colors = colors.indices.filter { !colorIndexes.contains($0) }.map { colors[$0] } + colorIndexes.map { colors[$0] }   // listed in sewing order
            let names = outlines.map { tracedColors[$0].thread.name }
            let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
            warnings.append("\(list) \(names.count == 1 ? "is" : "are") mostly outlines, so \(names.count == 1 ? "it sews" : "they sew") last, on top of the other colors.")
        }
        warnings += trace.warnings
        // (kind, one, several, why its width chose it)
        let kinds: [(PartKind, String, String, String)] = [(.line, "running stitch line", "running stitch lines", "thinner than 1 mm"),
            (.outline, "running outline", "running outlines", ""), (.satin, "satin", "satin", "up to 8 mm across"),
            (.column, "satin column", "satin columns", "along curved strips"), (.tapered, "tapered satin", "tapered satins", "turning with the strip"),
            (.tatami, "tatami", "tatami", "wider")]
        let used = kinds.filter { counts[$0.0, default: 0] > 0 }
        if byHand > 0 {
            let list = used.map { "\(counts[$0.0]!) \(counts[$0.0]! == 1 ? $0.1 : $0.2)" }.joined(separator: ", ")
            warnings.append("\(byHand) part\(byHand == 1 ? " was" : "s were") set by hand." + (list.isEmpty ? "" : " Stitches: \(list)."))
        } else if used.contains(where: { $0.0 != .tatami }) {
            warnings.append("Each part's stitch follows its width: " + used.map { "\(counts[$0.0]!) \(counts[$0.0]! == 1 ? $0.1 : $0.2) (\($0.3))" }.joined(separator: ", ") + ".")
        }
        guard !objects.isEmpty else {
            throw DesignError.invalid(byHand > 0 ? "Every part is left out, so there is nothing to stitch." : "Nothing large enough to stitch was found. Try more colors, turn off Skip background, or lower the smallest part.")
        }
        guard objects.count <= 500 else { throw DesignError.invalid("The picture traced into \(objects.count) parts, which is too many. Use fewer colors or a larger smallest part.") }
        // Neighbors traced from the same pixel edge end up at most a smoothing step or two apart, so closer than
        // three pixels (at least 0.3 mm) counts as touching.
        let touching = 3 * max(0.1, trace.geometry.pixelWidth, trace.geometry.pixelHeight)
        setAngles(&objects, touching: touching)
        // After the angles and stitch types, which follow the traced shapes; before the start points, which follow the grown ones.
        let grown = try overlap(&objects, shapes: shapes, by: overlapAmount, sliver: touching)
        if grown > 0 { warnings.append("\(grown) part\(grown == 1 ? " reaches" : "s reach") \(overlapAmount.formatted()) mm under the parts sewn on top of \(grown == 1 ? "it" : "them"), so no fabric shows between them.") }
        try setStartPoints(&objects)
        var check = Design(); check.objects = objects; try check.validate()
        return AutoDigitizeResult(objects: objects, colors: colors, warnings: warnings)
    }

    /// How far a fill reaches under the parts sewn on top of it, in mm, so no fabric shows along the seam.
    static let overlapAmount = 0.8

    /// Grows each fill (tatami or satin) `amount` mm under the parts sewn after it, so no fabric shows between
    /// neighbors once the stitches pull in. Only growth that lands under a later part (fill or line) is kept: edges
    /// facing bare fabric, or parts sewn earlier, stay where they are. `shapes` are the traced parts, one per object.
    /// Neighbors' outlines are smoothed one at a time, which leaves hair-thin slivers between them; those narrower
    /// than `sliver` mm count as covered, so the grown fill gets no tiny holes. A fill whose growth can't be worked
    /// out keeps its traced shape. Returns how many fills grew.
    static func overlap(_ objects: inout [RunObject], shapes: [[[Point]]], by amount: Double, sliver: Double) throws -> Int {
        // Outline counterclockwise, holes clockwise, so overlapping parts join into one area when offset together.
        func oriented(_ region: [[Point]]) -> [[Point]] {
            region.enumerated().map { k, ring in (AreaGeometry.area(ring) > 0) == (k == 0) ? ring : ring.reversed() }
        }
        var grownCount = 0
        for i in objects.indices where objects[i].kind == .fill {
            try Task.checkCancellation()
            let later = objects.indices.filter { $0 > i && touches(shapes[i], shapes[$0], within: amount) }
            guard !later.isEmpty else { continue }
            do {
                let grown = try AreaGeometry.offset(oriented(shapes[i]), by: amount)
                // Where it may reach: itself and the later parts, joined, with the slivers between them closed up
                // (everything grown by half a sliver, then shrunk back, which leaves outer edges where they were).
                let joined = ([i] + later).flatMap { oriented(shapes[$0]) }
                let allowed = try AreaGeometry.offset(AreaGeometry.offset(joined, by: sliver / 2), by: -sliver / 2)
                // Cut away the growth that landed anywhere else (bare fabric, parts sewn earlier).
                let elsewhere = try AreaGeometry.subtracting(allowed, from: grown)
                let pieces = try AreaGeometry.subtracting(elsewhere.flatMap { $0 }, from: grown)
                // One piece is expected; keep the largest in case a speck broke off.
                guard let piece = pieces.max(by: { AreaGeometry.area($0[0]).magnitude < AreaGeometry.area($1[0]).magnitude }),
                      let region = sewable(piece) else { continue }
                objects[i].nodes = region[0].map { PathNode($0) }
                objects[i].holes = region.count > 1 ? region.dropFirst().map { $0.map { PathNode($0) } } : nil
                grownCount += 1
            } catch let stop as CancellationError { throw stop } catch { continue }   // stop if the dialog moved on; otherwise keep the traced shape
        }
        return grownCount
    }

    /// `piece` (outline, then holes) as a shape a fill can have, or nil if it can't be made one. Cutting a fill's
    /// growth away from where it may not go can leave an outline that touches itself, or specks of holes touching
    /// it; shrinking it 0.02 mm (too little to see) pulls those touching points apart, and specks under 1 mm² are
    /// sewn over. A shape pinched to a point would come apart in two, which one fill can't sew: nil then.
    static func sewable(_ piece: [[Point]]) -> [[Point]]? {
        if let (region, _) = fitted(piece, smallest: 0.05), (try? AreaGeometry.validate(region)) != nil { return region }
        guard let shrunk = try? AreaGeometry.subtracting([], from: AreaGeometry.offset(piece, by: -0.02)) else { return nil }
        let parts = shrunk.filter { AreaGeometry.area($0[0]).magnitude >= 1 }
        guard parts.count == 1, let (region, _) = fitted(parts[0], smallest: 1), (try? AreaGeometry.validate(region)) != nil else { return nil }
        return region
    }

    /// Each part starts where the one before it finishes, so the needle travels less in between: the same start
    /// points as Auto Start Points, found faster. That command sews everything before a part to see where it ends,
    /// which takes minutes for hundreds of parts; plain fills and lines end in the same place sewn on their own, so
    /// here each part is sewn once.
    static func setStartPoints(_ objects: inout [RunObject]) throws {
        for i in objects.indices.dropFirst() {
            try Task.checkCancellation()
            var previous = Design(); previous.objects = [objects[i - 1]]
            objects[i].entry = try StitchEngine.compile(previous).commands.last { $0.op == .stitch }?.point
        }
    }

    /// `parts` put in sewing order, nearest part next so the needle travels less: after the part sewn last, the one
    /// whose middle is closest to its middle. `region` gives each part's shape (outline and holes). `after` is the
    /// middle of the part sewn just before these (the color before ends there); nil starts with the top-left part,
    /// where you'd start reading the picture.
    static func nearestFirst<Part>(_ parts: [Part], region: (Part) -> [[Point]], after: Point?) -> [Part] {
        var left = parts.map { (part: $0, region: region($0), middle: AreaGeometry.centroid(region($0)[0])) }, ordered: [Part] = []
        var last = after
        while !left.isEmpty {
            let next: Int
            if let last {
                next = left.indices.min { left[$0].middle.distance(to: last) < left[$1].middle.distance(to: last) }!
            } else {
                // The highest top edge (within 1 mm), then the leftmost.
                next = left.indices.min { a, b in
                    let ya = left[a].region[0].map(\.y).max()!, yb = left[b].region[0].map(\.y).max()!
                    return abs(ya - yb) > 1 ? ya > yb : left[a].region[0].map(\.x).min()! < left[b].region[0].map(\.x).min()!
                }!
            }
            ordered.append(left[next].part); last = left[next].middle
            left.remove(at: next)
        }
        return ordered
    }

    /// Gives each fill its stitch angle, in sewing order. Tatami rows run along the shape's long side (fewer turns,
    /// and the stitches follow the shape); satin stitches run across it, so they stay short. When a fill touches one sewn before it whose angle is within 30° of its own,
    /// it turns 45° (or -45°, or 90°, whichever first clears every such neighbor), so neighbors read as separate
    /// shapes instead of one patch. Shapes about as wide as they are long keep the default angle. Lines have no angle.
    static func setAngles(_ objects: inout [RunObject], touching gap: Double) {
        let regions = objects.map { [$0.nodes.map(\.point)] + ($0.holes ?? []).map { $0.map(\.point) } }
        // How far apart two angles are, in degrees: 0–90, since rows at 10° and 190° are the same rows.
        func apart(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 180); return min(d, 180 - d) }
        let fills = objects.indices.filter { objects[$0].kind == .fill }
        for i in fills {
            let box = turnedBox(regions[i][0]), satin = objects[i].settings.fillStyle == .satin
            // A shape about as wide as it is long has no long side to follow.
            let base = box.short < 0.9 * box.long ? box.angle + (satin ? 90 : 0) : objects[i].settings.angle
            let neighbors = fills.filter { $0 < i && touches(regions[i], regions[$0], within: gap) }.map { objects[$0].settings.angle }
            let choices = [base, base + 45, base - 45, base + 90]
            // How far a choice is from its closest neighbor; with no neighbors, as far as can be.
            func clearance(_ angle: Double) -> Double { neighbors.map { apart(angle, $0) }.min() ?? 90 }
            let angle = choices.first { clearance($0) >= 30 } ?? choices.max { clearance($0) < clearance($1) }!
            // Kept between 0° and 180° (rows look the same turned half a circle).
            objects[i].digitizing?.angle = (angle.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
        }
    }

    /// The smallest box that fits around a shape when the box may turn: the direction of its long side in whole
    /// degrees (0–179), and its long and short sides in mm. Every whole degree is tried, which is plenty for stitch angles.
    static func turnedBox(_ outline: [Point]) -> (angle: Double, long: Double, short: Double) {
        var best: (area: Double, angle: Double, long: Double, short: Double)?
        for degrees in 0..<90 {   // a box turned 90° is the same box on its side, so 0–89° covers them all
            // Turning the shape back by `degrees` lines that direction up with x, so the box is plain min/max.
            let turned = outline.map { AreaGeometry.rotate($0, degrees: -Double(degrees)) }
            let width = turned.map(\.x).max()! - turned.map(\.x).min()!, height = turned.map(\.y).max()! - turned.map(\.y).min()!
            if best == nil || width * height < best!.area {
                best = (width * height, Double(width >= height ? degrees : degrees + 90), max(width, height), min(width, height))
            }
        }
        return (best!.angle, best!.long, best!.short)
    }

    /// Whether two regions (outline and holes each) come within `gap` mm of each other anywhere along their edges.
    static func touches(_ a: [[Point]], _ b: [[Point]], within gap: Double) -> Bool {
        // Quick check first: if their boxes, grown by the gap, don't overlap, they can't touch.
        let pa = a.flatMap { $0 }, pb = b.flatMap { $0 }
        guard pa.map(\.x).min()! - gap <= pb.map(\.x).max()!, pb.map(\.x).min()! - gap <= pa.map(\.x).max()!,
              pa.map(\.y).min()! - gap <= pb.map(\.y).max()!, pb.map(\.y).min()! - gap <= pa.map(\.y).max()! else { return false }
        // Any corner of one within `gap` of an edge of the other. Corners of a shared edge sit on both shapes' edges.
        func near(_ p: Point, _ rings: [[Point]]) -> Bool {
            rings.contains { ring in ring.indices.contains { p.distance(to: AreaGeometry.projection(p, ring[$0], ring[($0 + 1) % ring.count])) <= gap } }
        }
        return pa.contains { near($0, b) } || pb.contains { near($0, a) }
    }

    /// The closest thread in `chart` for each color, in order, with no thread used twice: when two colors are nearest
    /// the same thread, the earlier one (the larger area) gets it and the other takes its next closest, so colors that
    /// looked different stay different threads. nil for a color when the chart has run out of threads.
    static func threads(for colors: [Int], from chart: ThreadChart) -> [ThreadColor?] {
        var taken = Set<ThreadColor>()
        return colors.map { hex in
            let match = chart.nearest(to: hex, count: taken.count + 1).first { !taken.contains($0) }
            if let match { taken.insert(match) }
            return match
        }
    }

    /// Reduces the picture to at most `colors` colors with k-means: start from well-spread common colors, then
    /// repeatedly move each color to the average of the pixels nearest to it. Returns one label per pixel (an index
    /// into the colors, or -1 for transparent pixels) and the colors as 0xRRGGBB.
    static func quantize(_ image: PixelImage, colors: Int) throws -> (labels: [Int], centers: [Int]) {
        // Count pixels in 32 × 32 × 32 color buckets; k-means then works on the buckets, which is far faster than on pixels.
        var counts = [Int](repeating: 0, count: 32768), sums = [SIMD3<Double>](repeating: .zero, count: 32768)
        let pixels = image.width * image.height
        var bucketOf = [Int](repeating: -1, count: pixels)
        for p in 0..<pixels {
            let r = Int(image.rgba[p * 4]), g = Int(image.rgba[p * 4 + 1]), b = Int(image.rgba[p * 4 + 2])
            guard image.rgba[p * 4 + 3] >= 128 else { continue }
            let bucket = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            bucketOf[p] = bucket; counts[bucket] += 1; sums[bucket] += SIMD3(Double(r), Double(g), Double(b))
        }
        let used = counts.indices.filter { counts[$0] > 0 }
        guard !used.isEmpty else { return (bucketOf, []) }
        let mean = Dictionary(uniqueKeysWithValues: used.map { ($0, sums[$0] / Double(counts[$0])) })
        func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { let d = a - b; return (d * d).sum() }
        // Start with the most common color, then add the color that is both common and far from those chosen.
        var centers = [mean[used.max { counts[$0] < counts[$1] }!]!]
        while centers.count < min(colors, used.count) {
            let next = used.max { a, b in
                Double(counts[a]) * centers.map { distance(mean[a]!, $0) }.min()! < Double(counts[b]) * centers.map { distance(mean[b]!, $0) }.min()!
            }!
            if centers.map({ distance(mean[next]!, $0) }).min()! < 1 { break }   // no other distinct colors left
            centers.append(mean[next]!)
        }
        var nearest = [Int: Int]()
        for _ in 0..<12 {
            try Task.checkCancellation()
            var total = [SIMD3<Double>](repeating: .zero, count: centers.count), weight = [Double](repeating: 0, count: centers.count)
            for bucket in used {
                let k = centers.indices.min { distance(mean[bucket]!, centers[$0]) < distance(mean[bucket]!, centers[$1]) }!
                nearest[bucket] = k; total[k] += mean[bucket]! * Double(counts[bucket]); weight[k] += Double(counts[bucket])
            }
            let moved = centers.indices.map { weight[$0] > 0 ? total[$0] / weight[$0] : centers[$0] }
            if zip(moved, centers).allSatisfy({ distance($0, $1) < 0.25 }) { centers = moved; break }
            centers = moved
        }
        for bucket in used { nearest[bucket] = centers.indices.min { distance(mean[bucket]!, centers[$0]) < distance(mean[bucket]!, centers[$1]) }! }
        let labels = bucketOf.map { $0 < 0 ? -1 : nearest[$0]! }
        let hex = centers.map { c in Int(c.x.rounded()) << 16 | Int(c.y.rounded()) << 8 | Int(c.z.rounded()) }
        return (labels, hex)
    }

    /// Each color's average over its inside pixels only (those whose four neighbors share it). Soft edges blend
    /// into the next color, so leaving them out keeps thread colors true to the picture. Colors with no inside
    /// pixels keep their `fallback`.
    static func insideColors(_ image: PixelImage, labels: [Int], fallback: [Int]) -> [Int] {
        let w = image.width, h = image.height
        var sums = [SIMD3<Double>](repeating: .zero, count: fallback.count), counts = [Double](repeating: 0, count: fallback.count)
        for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            let i = y * w + x, label = labels[i]
            guard label >= 0, labels[i - 1] == label, labels[i + 1] == label, labels[i - w] == label, labels[i + w] == label else { continue }
            sums[label] += SIMD3(Double(image.rgba[i * 4]), Double(image.rgba[i * 4 + 1]), Double(image.rgba[i * 4 + 2])); counts[label] += 1
        } }
        return fallback.indices.map { k in
            guard counts[k] > 0 else { return fallback[k] }
            let c = sums[k] / counts[k]
            return Int(c.x.rounded()) << 16 | Int(c.y.rounded()) << 8 | Int(c.z.rounded())
        }
    }

    /// Two passes of a "majority" filter: a pixel that matches fewer than two of its eight neighbors takes the most
    /// common neighboring color. This removes single-pixel specks and the blended fringe along anti-aliased edges.
    static func cleanSpecks(_ labels: inout [Int], width w: Int, height h: Int) {
        for _ in 0..<2 {
            let before = labels
            for y in 0..<h { for x in 0..<w {
                // tally[label + 1] counts neighbors of each color; slot 0 counts transparent (-1) neighbors.
                var tally = [Int](repeating: 0, count: 9), same = 0
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let neighbor = before[ny * w + nx]
                    if neighbor == before[y * w + x] { same += 1 } else { tally[neighbor + 1] += 1 }
                } }
                if same < 2, let common = tally.indices.max(by: { tally[$0] < tally[$1] }), tally[common] > 0 { labels[y * w + x] = common - 1 }
            } }
        }
    }

    /// Where two filled pixels touch only at a corner (a checkerboard 2 × 2), fills one of the empty pixels so
    /// outlines never meet at a single point; outlines that touch can't be sewn as fills.
    static func separateDiagonals(_ mask: inout [Bool], width w: Int, height h: Int) {
        for _ in 0..<8 {
            var changed = false
            for y in 0..<(h - 1) { for x in 0..<(w - 1) {
                let a = mask[y * w + x], b = mask[y * w + x + 1], c = mask[(y + 1) * w + x], d = mask[(y + 1) * w + x + 1]
                if a && d && !b && !c { mask[y * w + x + 1] = true; changed = true }
                else if b && c && !a && !d { mask[y * w + x] = true; changed = true }
            } }
            if !changed { return }
        }
    }

    /// The outlines of the filled pixels as closed rings of pixel corners, following the edges between filled and
    /// empty pixels. Each edge is walked with the filled pixel on its right, so the rings never cross. Every corner
    /// is kept, one pixel apart, because the smoothing step takes the midpoint of each one-pixel edge.
    static func traceRings(_ mask: [Bool], width w: Int, height h: Int) -> [[Point]] {
        func filled(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] }
        let stride = w + 1
        var next = [Int32](repeating: -1, count: stride * (h + 1))   // for each pixel corner, the corner the outline goes to next
        for y in 0..<h { for x in 0..<w where mask[y * w + x] {
            if !filled(x, y - 1) { next[y * stride + x] = Int32(y * stride + x + 1) }                      // top edge, going right
            if !filled(x + 1, y) { next[y * stride + x + 1] = Int32((y + 1) * stride + x + 1) }          // right edge, going down
            if !filled(x, y + 1) { next[(y + 1) * stride + x + 1] = Int32((y + 1) * stride + x) }        // bottom edge, going left
            if !filled(x - 1, y) { next[(y + 1) * stride + x] = Int32(y * stride + x) }                  // left edge, going up
        } }
        var rings: [[Point]] = []
        for start in next.indices where next[start] >= 0 {
            var ring: [Point] = [], corner = start
            while next[corner] >= 0 {
                let following = Int(next[corner]); next[corner] = -1
                ring.append(Point(Double(corner % stride), Double(corner / stride)))
                corner = following
            }
            if ring.count >= 4 { rings.append(ring) }
        }
        return rings
    }

    /// A pixel outline with its staircase softened. On a slanted edge the true line runs through the middle of
    /// each step, so each one-pixel edge is replaced by its midpoint. Real corners, where two straight runs of at
    /// least two pixels meet, are kept exactly; a slanted pixel edge always has one-pixel steps, so it never has those.
    static func softened(_ ring: [Point]) -> [Point] {
        let n = ring.count
        func direction(_ i: Int) -> Point { ring[(i + 1) % n] - ring[(i % n + n) % n] }
        // run[i] is the length of the straight run that edge i belongs to.
        var run = [Int](repeating: 1, count: n)
        guard let start = (0..<n).first(where: { direction($0) != direction($0 - 1) }) else { return ring }
        var i = 0
        while i < n {
            var length = 1
            while length < n && direction(start + i + length) == direction(start + i) { length += 1 }
            for k in 0..<length { run[(start + i + k) % n] = length }
            i += length
        }
        var result: [Point] = []
        for i in 0..<n {
            if direction(i) != direction(i - 1) && run[i] >= 2 && run[(i + n - 1) % n] >= 2 { result.append(ring[i]) }
            result.append((ring[i] + ring[(i + 1) % n]) * 0.5)
        }
        return result
    }

    /// Douglas–Peucker simplification of a closed ring: keeps the points that stick out more than `tolerance`
    /// from a straight line between their neighbors' kept points, and drops the rest.
    /// `region` (an outline and its holes, in mm) made to fit what one fill can hold (Design.validate): holes smaller
    /// than `smallest` mm² are filled in, like parts that small; only the 100 largest holes stay; and the outline and
    /// holes are smoothed a little more at a time until they have 2,000 points between them. Returns the region and
    /// how many holes were filled in, or nil if even smoothing by 2 mm doesn't fit (or leaves no outline).
    static func fitted(_ region: [[Point]], smallest: Double) -> (region: [[Point]], filledHoles: Int)? {
        let holes = region.dropFirst().map { ($0, AreaGeometry.area($0).magnitude) }.filter { $0.1 >= smallest }
            .sorted { $0.1 > $1.1 }.prefix(100).map(\.0)
        let kept = [region[0]] + holes
        var fitted = kept, tolerance = 0.1
        while fitted.reduce(0, { $0 + $1.count }) > 2000 {
            tolerance *= 1.5
            guard tolerance <= 2 else { return nil }
            // Each pass starts again from the traced shapes, so smoothing doesn't pile up.
            fitted = [simplify(kept[0], tolerance: tolerance)] + kept.dropFirst().map { simplify($0, tolerance: tolerance) }.filter { $0.count >= 3 }
        }
        guard fitted[0].count >= 3 else { return nil }
        return (fitted, region.count - fitted.count)
    }

    static func simplify(_ ring: [Point], tolerance: Double) -> [Point] {
        guard ring.count > 4 else { return ring }
        // Split the ring at its first point and the point farthest from it, then simplify the two halves as lines.
        let far = ring.indices.max { ring[0].distance(to: ring[$0]) < ring[0].distance(to: ring[$1]) }!
        let firstHalf = simplifyLine(ring[0...far], tolerance: tolerance), secondHalf = simplifyLine((ring + [ring[0]])[far...], tolerance: tolerance)
        let result = Array(firstHalf.dropLast() + secondHalf.dropLast())
        return result.count >= 3 ? result : ring
    }

    /// Douglas–Peucker for an open line: keeps both ends, and splits at the point farthest from the straight line
    /// between them, again and again, while that point is more than `tolerance` away.
    static func simplifyLine(_ points: ArraySlice<Point>, tolerance: Double) -> [Point] {
        guard points.count > 2, let first = points.first, let last = points.last else { return Array(points) }
        var worst = points.startIndex, worstDistance = 0.0
        for i in points.indices.dropFirst().dropLast() {
            let d = points[i].distance(to: AreaGeometry.projection(points[i], first, last))
            if d > worstDistance { worst = i; worstDistance = d }
        }
        guard worstDistance > tolerance else { return [first, last] }
        return simplifyLine(points[points.startIndex...worst], tolerance: tolerance).dropLast() + simplifyLine(points[worst...], tolerance: tolerance)
    }

    /// One part's pixels: a grid over the part's box (in the traced image) with an empty one-pixel border, so every
    /// pixel has eight neighbors. Pixels are numbered row by row.
    struct PartGrid {
        var on: [Bool]
        let width: Int, height: Int, x0: Int, y0: Int   // x0, y0: the image pixel at the box's top left

        /// The part's pixels in `mask` (the whole image, `imageWidth` × `imageHeight`): the patch of touching mask
        /// pixels that `region` (an outline and holes in image pixels) was traced from. One pixel inside the region is
        /// found, then the patch is flooded out from it through side neighbors (traced patches touch only along sides,
        /// see `separateDiagonals`), which is much faster than testing every pixel against the outline. nil if no
        /// mask pixel is inside the region.
        init?(region: [[Point]], mask: [Bool], imageWidth w: Int, imageHeight h: Int) {
            let points = region.flatMap { $0 }
            let x0 = max(0, Int(points.map(\.x).min()!)), x1 = min(w - 1, Int(points.map(\.x).max()!))
            let y0 = max(0, Int(points.map(\.y).min()!)), y1 = min(h - 1, Int(points.map(\.y).max()!))
            guard x0 <= x1, y0 <= y1 else { return nil }
            self.x0 = x0; self.y0 = y0; width = x1 - x0 + 3; height = y1 - y0 + 3
            // The first mask pixel (row by row) inside the region.
            var seed: Int?
            search: for y in y0...y1 { for x in x0...x1 where mask[y * w + x] && AreaGeometry.contains(Point(Double(x) + 0.5, Double(y) + 0.5), rings: region) {
                seed = (y - y0 + 1) * width + x - x0 + 1; break search
            } }
            guard let seed else { return nil }
            var on = [Bool](repeating: false, count: width * height), stack = [seed]
            on[seed] = true
            while let i = stack.popLast() {
                for next in [i - width, i + 1, i + width, i - 1] where !on[next] {
                    let x = next % width + x0 - 1, y = next / width + y0 - 1
                    guard x >= x0, x <= x1, y >= y0, y <= y1, mask[y * w + x] else { continue }
                    on[next] = true; stack.append(next)
                }
            }
            self.on = on
        }
        /// The filled pixels next to pixel `i`: those along the sides first, then on the diagonals, so walks prefer the straight step.
        func neighbors(_ i: Int) -> [Int] { [-width, 1, width, -1, -width + 1, width + 1, width - 1, -width - 1].map { i + $0 }.filter { on[$0] } }
        /// Pixel `i`'s center, in image pixels.
        func center(_ i: Int) -> Point { Point(Double(i % width + x0 - 1) + 0.5, Double(i / width + y0 - 1) + 0.5) }
    }

    /// The middle of a thin part as one path through pixel centers (in image pixels), and whether it is a loop (a
    /// thin ring). The part's pixels (those of `mask` whose centers are inside `region`, given in pixels) are thinned
    /// to a line one pixel wide, which is then walked from one end. Side branches are sewn out and back, shortest
    /// first, so the walk can end at the far end of the longest one. nil when thinning leaves nothing.
    static func centerline(of region: [[Point]], mask: [Bool], width w: Int, height h: Int) -> (path: [Point], closed: Bool)? {
        guard var grid = PartGrid(region: region, mask: mask, imageWidth: w, imageHeight: h) else { return nil }
        thin(&grid.on, width: grid.width, height: grid.height)
        let pixels = grid.on.indices.filter { grid.on[$0] }
        guard let any = pixels.first else { return nil }
        let neighbors = grid.neighbors
        let start = pixels.first { neighbors($0).count == 1 } ?? any   // an end of the line; a loop has none
        // A tree of the line's pixels from `start`, and each pixel's reach: how many pixels the longest way on from it
        // is. Depth-first, claiming a pixel only when stepping onto it, so the tree follows the line (a loop is walked
        // all the way round instead of splitting into two halves at the start).
        var children = [Int: [Int]](), order: [Int] = [], seen = Set<Int>(), stack = [(pixel: start, parent: -1)]
        while let (pixel, parent) = stack.popLast() {
            guard seen.insert(pixel).inserted else { continue }
            if parent >= 0 { children[parent, default: []].append(pixel) }
            order.append(pixel)
            // Reversed, so the straight step (listed first) comes off the stack first.
            for next in neighbors(pixel).reversed() where !seen.contains(next) { stack.append((next, pixel)) }
        }
        var reach = [Int: Int]()
        for pixel in order.reversed() { reach[pixel] = (children[pixel] ?? []).map { reach[$0]! + 1 }.max() ?? 0 }
        // Walk the tree: into each child, shortest reach first, and back. After the last new pixel, stop: the walk
        // ends at the far end of the longest branch instead of coming all the way back.
        var walk = [start], newEnd = 1, path: [(pixel: Int, next: Int)] = [(start, 0)]
        while var top = path.popLast() {
            let kids = (children[top.pixel] ?? []).sorted { reach[$0]! < reach[$1]! }
            if top.next < kids.count {
                let child = kids[top.next]; top.next += 1
                path.append(top); path.append((child, 0)); walk.append(child); newEnd = walk.count
            } else if let parent = path.last { walk.append(parent.pixel) }
        }
        walk.removeSubrange(newEnd...)
        let closed = neighbors(start).count != 1 && walk.count > 3 && neighbors(walk.last!).contains(start)
        return (walk.map(grid.center), closed)
    }

    /// A curved strip's middle, ready to sew the strip in satin: its centerline (thinned to one pixel, cleaned, and cut
    /// into branches where three or more meet) and the strip's width at each centerline pixel, in mm.
    struct StripMiddle {
        var grid: PartGrid
        var branches: [(pixels: [Int], closed: Bool)]
        var widths: [Int: Double]
        var part: [Bool]        // the part's pixels before thinning, on the same grid
        var pixelSize: Double   // mm per pixel

        /// True if satin down the centerline, reaching `halfWidth(pixel)` mm to each side of each centerline pixel,
        /// covers nearly all of the part: at most 1% of its pixels lie more than 1 mm beyond it. Points sticking out of
        /// a strip (a sun's rays round a ring) have their bits of centerline trimmed off as spurs, so satin along it
        /// would leave them out; such a part is better sewn as a fill.
        func coversPart(halfWidth: (Int) -> Double) -> Bool {
            let w = grid.width, h = grid.height
            var reached = [Bool](repeating: false, count: part.count)
            // Mark a circle round each centerline pixel, as far as the satin reaches there plus 1 mm, in pixels.
            for pixel in grid.on.indices where grid.on[pixel] {
                let x = pixel % w, y = pixel / w, reach = (halfWidth(pixel) + 1) / pixelSize, steps = Int(reach)
                for dy in -steps...steps { for dx in -steps...steps where Double(dx * dx + dy * dy) <= reach * reach {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, nx < w, ny >= 0, ny < h { reached[ny * w + nx] = true }
                } }
            }
            let filled = part.indices.filter { part[$0] }
            return filled.filter { !reached[$0] }.count <= filled.count / 100
        }
    }

    /// The middle of a curved strip, or nil when the part isn't a strip. `region` is the part in image pixels, `width`
    /// its width in mm (area ÷ half the outline), `pixelSize` mm per pixel. It's a strip if it is nowhere much wider
    /// than `width` and its centerline is at least four times as long as `width` (not a blob).
    static func stripMiddle(of region: [[Point]], mask: [Bool], imageWidth: Int, imageHeight: Int, width: Double, pixelSize: Double) -> StripMiddle? {
        guard var grid = PartGrid(region: region, mask: mask, imageWidth: imageWidth, imageHeight: imageHeight) else { return nil }
        let distance = distances(grid)   // measured before thinning, from every pixel of the strip
        // A strip is nowhere much wider than its width; a blob with holes (whose long outline makes its width
        // look small) is. Checking now skips thinning it.
        guard (2 * distance.max()! - 0.5) * pixelSize <= 2 * width else { return nil }
        let part = grid.on   // kept to check the satin covers it (StripMiddle.coversPart)
        thin(&grid.on, width: grid.width, height: grid.height)
        removeCorners(&grid)
        pruneSpurs(&grid, shorterThan: Int((width / pixelSize).rounded()))
        removeCorners(&grid)
        let pixels = grid.on.indices.filter { grid.on[$0] }
        guard pixels.count >= 5 else { return nil }
        // The strip's width at each centerline pixel: twice the way to the nearest edge (centers are half a pixel in).
        let widths = Dictionary(uniqueKeysWithValues: pixels.map { ($0, (2 * distance[$0] - 0.5) * pixelSize) })
        let branches = branches(of: grid)
        guard !branches.isEmpty else { return nil }
        let length = branches.reduce(0.0) { total, branch in total + AreaGeometry.pathLength(branch.pixels.map(grid.center)) * pixelSize }
        guard length >= 4 * width else { return nil }
        return StripMiddle(grid: grid, branches: branches, widths: widths, part: part, pixelSize: pixelSize)
    }

    /// Satin columns down `middle`, one per branch, `width` mm wide, or nil when the strip isn't even: columns are
    /// even, so the widest stretches may be at most 1.5 times the narrowest, and the columns must cover the part (see
    /// `StripMiddle.coversPart`). `place` turns image pixels into canvas mm. Also nil if any column can't sew, so the
    /// part is sewn another way.
    static func satinColumns(along middle: StripMiddle, width: Double, pixelSize: Double, place: (Point) -> Point, name: String, thread: ThreadColor) -> [RunObject]? {
        let widths = middle.widths.values.sorted()
        guard widths[widths.count * 4 / 5] <= 1.5 * widths[widths.count / 5] else { return nil }
        // Each column is `width` wide all along, so it must reach all of the part from there.
        guard middle.coversPart(halfWidth: { _ in width / 2 }) else { return nil }
        let grid = middle.grid
        var branches = middle.branches
        // Sew the branches one after another, each starting at the end nearest where the last one finished.
        var ordered = [branches.removeFirst()]
        while !branches.isEmpty {
            let last = grid.center(ordered.last!.pixels.last!)
            func gap(_ pixel: Int) -> Double { grid.center(pixel).distance(to: last) }
            let next = branches.indices.min { min(gap(branches[$0].pixels.first!), gap(branches[$0].pixels.last!)) < min(gap(branches[$1].pixels.first!), gap(branches[$1].pixels.last!)) }!
            var branch = branches.remove(at: next)
            if gap(branch.pixels.last!) < gap(branch.pixels.first!) { branch.pixels.reverse() }
            ordered.append(branch)
        }
        var columns: [RunObject] = []
        for branch in ordered {
            var path = simplifyLine(branch.pixels.map { place(grid.center($0)) }[...], tolerance: max(0.1, pixelSize))
            guard path.count >= 2 else { continue }
            if !branch.closed {
                // Thinning stops about half the width short of a loose end, so the column reaches on to the tip.
                // (Ends at a junction stay: the other branches cover it.)
                func reach(_ end: Point, from inside: Point) -> Point { let d = end - inside, l = hypot(d.x, d.y); return l > 0 ? end + d * (width / 2 / l) : end }
                if grid.neighbors(branch.pixels.first!).count == 1 { path[0] = reach(path[0], from: path[1]) }
                if grid.neighbors(branch.pixels.last!).count == 1 { path[path.count - 1] = reach(path[path.count - 1], from: path[path.count - 2]) }
            }
            guard AreaGeometry.pathLength(path) >= 1 else { continue }   // a stub between two junctions close together
            var line = RunObject(name: "\(name) \(columns.count + 1)", nodes: path.map { PathNode($0) }, color: thread)
            line.closed = branch.closed && path.count >= 3
            line.digitizing = DigitizingSettings(kind: .run)
            guard var column = try? SatinLine.column(from: line, width: width) else { return nil }
            column.name = name
            columns.append(column)
        }
        return columns.isEmpty ? nil : columns
    }

    /// A tapered strip (a crescent, a swoosh thinning to a point) as a turning satin fill: `region` (in mm) sewn in
    /// satin, its stitches turning along stitch angle lines placed straight across the strip about every 3 mm, each a
    /// little longer than the strip is wide there. The edges are the traced outline, so tips taper exactly. nil when
    /// the strip branches (a turning fill can't turn where three lines meet), is wider than 8 mm somewhere, has points
    /// sticking out of it (see `StripMiddle.coversPart`), or its stitches can't be worked out (lines crossing in a
    /// tight bend).
    static func turningSatin(_ region: [[Point]], along middle: StripMiddle, place: (Point) -> Point, name: String, thread: ThreadColor) -> RunObject? {
        guard middle.branches.count == 1, middle.widths.values.max()! <= 8 else { return nil }
        // Its stitches turn along the centerline, as wide as the strip is at each point.
        guard middle.coversPart(halfWidth: { middle.widths[$0]! / 2 }) else { return nil }
        let branch = middle.branches[0]
        var path = branch.pixels.map { place(middle.grid.center($0)) }, widths = branch.pixels.map { middle.widths[$0]! }
        if branch.closed { path.append(path[0]); widths.append(widths[0]) }
        // How far along the centerline each of its points is.
        var along = [0.0]
        for i in path.indices.dropFirst() { along.append(along[i - 1] + path[i - 1].distance(to: path[i])) }
        let length = along.last!
        /// The point `distance` mm along the centerline (clamped to its ends), and the strip's width there.
        func at(_ distance: Double) -> (point: Point, width: Double) {
            let d = min(max(distance, 0), length)
            let i = min(max(along.firstIndex { $0 >= d } ?? path.count - 1, 1), path.count - 1)
            let piece = along[i] - along[i - 1], t = piece > 0 ? (d - along[i - 1]) / piece : 0
            return (path[i - 1] + (path[i] - path[i - 1]) * t, widths[i - 1] + (widths[i] - widths[i - 1]) * t)
        }
        // About every 3 mm (at most 95 lines; a fill takes 100), spread evenly so each end gets one half a spacing in.
        let count = min(95, max(2, Int((length / 3).rounded())))
        let spacing = length / Double(count)
        var lines: [[Point]] = []
        for k in 0..<count {
            let distance = (Double(k) + 0.5) * spacing
            let (point, width) = at(distance)
            // The way the strip runs here, from 1.5 mm back to 1.5 mm ahead, which smooths out the pixel steps.
            let run = at(distance + 1.5).point - at(distance - 1.5).point, l = hypot(run.x, run.y)
            guard l > 0 else { continue }
            let across = Point(-run.y / l, run.x / l), reach = width * 0.65 + 0.5   // past both edges
            lines.append([point - across * reach, point + across * reach])
        }
        guard lines.count >= 2, lines.count <= 100 else { return nil }
        var object = RunObject(name: name, nodes: region[0].map { PathNode($0) }, color: thread)
        object.closed = true; object.holes = region.count > 1 ? region.dropFirst().map { $0.map { PathNode($0) } } : nil
        object.digitizing = DigitizingSettings(kind: .fill)
        object.digitizing?.fillStyle = .satin; object.digitizing?.angleLines = lines
        // Check it sews: the lines must cross the strip one after another.
        guard let stitches = try? StitchEngine.fresh(object, under: []), !stitches.sections.isEmpty else { return nil }
        return object
    }

    /// For each filled pixel of `grid`, how far its center is from the nearest empty pixel's center, in pixels (1 to a
    /// side neighbor, about 1.4 to a diagonal one); 0 for empty pixels. Two sweeps, down the grid and back up, each
    /// handing distances on from the neighbors it has already passed (a "chamfer distance transform").
    static func distances(_ grid: PartGrid) -> [Double] {
        let w = grid.width, h = grid.height, diagonal = 2.0.squareRoot()
        var d = grid.on.map { $0 ? Double.infinity : 0 }
        for y in 1..<(h - 1) { for x in 1..<(w - 1) where grid.on[y * w + x] {
            let i = y * w + x
            d[i] = min(d[i], d[i - 1] + 1, d[i - w] + 1, d[i - w - 1] + diagonal, d[i - w + 1] + diagonal)
        } }
        for y in stride(from: h - 2, through: 1, by: -1) { for x in stride(from: w - 2, through: 1, by: -1) where grid.on[y * w + x] {
            let i = y * w + x
            d[i] = min(d[i], d[i + 1] + 1, d[i + w] + 1, d[i + w + 1] + diagonal, d[i + w - 1] + diagonal)
        } }
        return d
    }

    /// Takes the extra pixels out of a thinned line, so it is one pixel wide everywhere: thinning leaves staircase
    /// detours and, where the line runs at 45°, stretches two pixels thick. A pixel can go if its filled neighbors
    /// all touch each other without it (one connected group), so removing it can't break the line; ends (one
    /// neighbor) stay, and so do junctions, whose arms meet only through them. Afterwards every pixel on a plain
    /// stretch of line has exactly two neighbors, so only real junctions have three or more.
    static func removeCorners(_ grid: inout PartGrid) {
        let w = grid.width
        // Each neighbor's offset as (dx, dy), to tell which neighbors touch each other.
        let offsets = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
        var changed = true
        while changed {
            changed = false
            for i in grid.on.indices where grid.on[i] {
                let filled = offsets.filter { grid.on[i + $0.1 * w + $0.0] }
                guard filled.count >= 2 else { continue }
                // Grow one group from the first neighbor through neighbors that touch (at most one step apart each way).
                var group = [filled[0]], rest = Array(filled.dropFirst())
                var k = 0
                while k < group.count {
                    let (gx, gy) = group[k]
                    let touching = rest.filter { abs($0.0 - gx) <= 1 && abs($0.1 - gy) <= 1 }
                    group += touching; rest.removeAll { r in touching.contains { $0 == r } }
                    k += 1
                }
                if rest.isEmpty { grid.on[i] = false; changed = true }
            }
        }
    }

    /// Cuts off twigs shorter than `length` pixels: thinning leaves short side branches where a strip has a corner or
    /// a bump. Each loose end is followed back to where it meets the rest of the line; if that comes sooner than
    /// `length`, the twig is removed. A line with no junction at all is left alone.
    static func pruneSpurs(_ grid: inout PartGrid, shorterThan length: Int) {
        for end in grid.on.indices where grid.on[end] && grid.neighbors(end).count == 1 {
            var twig: [Int] = [], previous = -1, current = end
            while twig.count < length {
                twig.append(current)
                let next = grid.neighbors(current).filter { $0 != previous }
                guard next.count == 1 else { break }   // the line's other end: no junction
                if grid.neighbors(next[0]).count >= 3 { for i in twig { grid.on[i] = false }; break }   // reached a junction
                previous = current; current = next[0]
            }
        }
    }

    /// A thinned line cut into branches where three or more meet: each a path of pixels from one end or junction to
    /// the next (both included), or a loop with neither (closed, its first pixel not repeated).
    static func branches(of grid: PartGrid) -> [(pixels: [Int], closed: Bool)] {
        func isStop(_ i: Int) -> Bool { grid.neighbors(i).count != 2 }   // an end or a junction
        let pixels = grid.on.indices.filter { grid.on[$0] }
        var used = Set<Int>(), result: [(pixels: [Int], closed: Bool)] = []
        for stop in pixels where isStop(stop) {
            for first in grid.neighbors(stop) where !used.contains(first) && !isStop(first) {
                var path = [stop, first], previous = stop, current = first
                used.insert(first)
                while !isStop(current) {
                    let next = grid.neighbors(current).first { $0 != previous }!
                    path.append(next); previous = current; current = next
                    if !isStop(next) { used.insert(next) }
                }
                result.append((path, false))
            }
        }
        // What's left are loops with no ends or junctions: walk each round once.
        for start in pixels where !used.contains(start) && !isStop(start) {
            var path = [start], previous = start, current = grid.neighbors(start)[0]
            used.insert(start)
            while current != start {
                path.append(current); used.insert(current)
                let next = grid.neighbors(current).first { $0 != previous }!
                previous = current; current = next
            }
            result.append((path, true))
        }
        return result
    }

    /// Zhang–Suen thinning: peels edge pixels off the filled ones, in passes that alternate between the lower-right
    /// and upper-left edges so both sides wear away evenly, until a line one pixel wide is left down the middle. A
    /// pixel is peeled only if that keeps the line in one piece and doesn't shorten its ends. The grid's outer border
    /// must be empty.
    static func thin(_ on: inout [Bool], width w: Int, height h: Int) {
        var changed = true
        while changed {
            changed = false
            for pass in 0..<2 {
                var peel: [Int] = []
                for y in 1..<(h - 1) { for x in 1..<(w - 1) where on[y * w + x] {
                    let i = y * w + x
                    // The eight neighbors, clockwise from the one above: up, up-right, right, … , up-left.
                    let n = [i - w, i - w + 1, i + 1, i + w + 1, i + w, i + w - 1, i - 1, i - w - 1].map { on[$0] }
                    let filled = n.filter { $0 }.count
                    let gaps = (0..<8).filter { !n[$0] && n[($0 + 1) % 8] }.count   // empty-then-filled steps going round
                    // 2–6 filled neighbors: not an end of the line, not deep inside. One gap: peeling it can't split anything.
                    guard (2...6).contains(filled), gaps == 1 else { continue }
                    // Pass 1 peels pixels on the right or bottom edge (or top-left corner); pass 2 the left or top edge.
                    let up = n[0], right = n[2], down = n[4], left = n[6]
                    if pass == 0 ? !(up && right && down) && !(right && down && left) : !(up && right && left) && !(up && down && left) { peel.append(i) }
                } }
                for i in peel { on[i] = false }
                if !peel.isEmpty { changed = true }
            }
        }
    }
}
