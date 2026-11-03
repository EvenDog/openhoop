// Auto-digitizing turns the reference image into stitches. It reduces the picture to a few thread colors,
// traces the outline of every patch of each color along the pixel edges, smooths away the pixel "staircase",
// and stitches each patch by its width (thin lines as running stitch, narrow parts as satin, the rest as tatami),
// placed exactly over the image. With a thread chart chosen, each color becomes that chart's closest thread. Parts
// sew nearest first, fills at angles that follow each shape (touching shapes at clearly different angles), and each
// part starts where the one before it ends.
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
        let image = try PixelImage(data: artwork.data, maxSide: tracingSize(for: artwork))
        return try run(image, center: artwork.center, width: artwork.width, height: artwork.height, options: options)
    }

    /// Traces `image`, shown `width` × `height` mm and centered on `center`, into fill objects.
    public static func run(_ image: PixelImage, center: Point, width: Double, height: Double, options: AutoDigitizeOptions) throws -> AutoDigitizeResult {
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
        let hasTransparency = labels.contains(-1)
        var background: Int? = nil
        if options.skipBackground && !hasTransparency {
            var counts = [Int](repeating: 0, count: centers.count)
            for x in 0..<w { counts[labels[x]] += 1; counts[labels[(h - 1) * w + x]] += 1 }
            for y in 0..<h { counts[labels[y * w]] += 1; counts[labels[y * w + w - 1]] += 1 }
            background = counts.indices.max { counts[$0] < counts[$1] }
        }

        // Pixel corner (x, y) in image coordinates → millimeters on the canvas (image rows run down, the canvas runs up).
        let left = center.x - width / 2, top = center.y + height / 2
        func place(_ x: Double, _ y: Double) -> Point { Point(left + x * pixelWidth, top - y * pixelHeight) }

        var areas = [Int](repeating: 0, count: centers.count)
        for label in labels where label >= 0 { areas[label] += 1 }
        let order = centers.indices.filter { areas[$0] > 0 }.sorted { areas[$0] > areas[$1] }   // big areas sew first, details on top
        var objects: [RunObject] = [], colors: [AutoDigitizeColor] = [], warnings: [String] = []
        var smallParts = 0, failedParts = 0, filledHoles = 0, lines = 0, satins = 0, tatamis = 0
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
            let rings = traced.map { simplify(softened($0), tolerance: max(1, 0.1 / min(pixelWidth, pixelHeight))) }.filter { $0.count >= 3 }.map { $0.map { place($0.x, $0.y) } }
            var parts: [[[Point]]] = []
            for traced in try AreaGeometry.svgRegions(rings, nonzero: false) {
                guard let (region, filled) = fitted(traced, smallest: max(options.smallestArea, 0.05)) else { failedParts += 1; continue }
                filledHoles += filled
                let area = AreaGeometry.area(region[0]).magnitude - region.dropFirst().reduce(0) { $0 + AreaGeometry.area($1).magnitude }
                guard area >= max(options.smallestArea, 0.05) else { smallParts += 1; continue }
                guard (try? AreaGeometry.validate(region)) != nil else { failedParts += 1; continue }
                parts.append(region)
            }
            parts = nearestFirst(parts, after: objects.last.map { AreaGeometry.centroid($0.nodes.map(\.point)) })
            // Millimeters on the canvas → pixel corners in the image (the reverse of `place`).
            func pixel(_ p: Point) -> Point { Point((p.x - left) / pixelWidth, (top - p.y) / pixelHeight) }
            for (index, region) in parts.enumerated() {
                // The stitch type follows the part's width. Area ÷ half the outline is about a strip's width (a dot's radius).
                let area = AreaGeometry.area(region[0]).magnitude - region.dropFirst().reduce(0) { $0 + AreaGeometry.area($1).magnitude }
                let perimeter = region.reduce(0) { $0 + AreaGeometry.pathLength($1 + [$1[0]]) }
                // Thinner than 1 mm: a triple running stitch down the middle of the line, if it has one at least 1 mm long.
                if 2 * area / perimeter < 1, let line = centerline(of: region.map { $0.map(pixel) }, mask: mask, width: w, height: h) {
                    let path = simplifyLine(line.path.map { place($0.x, $0.y) }[...], tolerance: max(0.1, pixelWidth, pixelHeight))
                    if path.count >= 2, AreaGeometry.pathLength(path) >= 1 {
                        var object = RunObject(name: "\(thread.name) line \(index + 1)", nodes: path.map { PathNode($0) }, color: thread)
                        object.closed = line.closed
                        var settings = DigitizingSettings(kind: .run); settings.runPasses = 3; object.digitizing = settings
                        objects.append(object); lines += 1
                        continue
                    }
                }
                var object = RunObject(name: "\(thread.name) area \(index + 1)", nodes: region[0].map { PathNode($0) }, color: thread)
                object.closed = true; object.holes = region.count > 1 ? region.dropFirst().map { $0.map { PathNode($0) } } : nil
                object.digitizing = DigitizingSettings(kind: .fill)
                // At most 8 mm across (the short side of the smallest box around it): satin, stitches straight across.
                // A curved strip has a wider box and stays tatami: one stitch direction can't follow its bends.
                if turnedBox(region[0]).short <= 8 { object.digitizing?.fillStyle = .satin; satins += 1 } else { tatamis += 1 }
                objects.append(object)
            }
            colors.append(AutoDigitizeColor(color: thread, area: Double(areas[label]) * pixelArea, parts: parts.count, background: false))
        }
        if hasTransparency && options.skipBackground == false { warnings.append("Transparent parts of the image are always left out.") }
        if smallParts > 0 { warnings.append("\(smallParts) patch\(smallParts == 1 ? " was" : "es were") smaller than \(options.smallestArea.formatted()) mm² and left out.") }
        if filledHoles > 0 { warnings.append("\(filledHoles) small hole\(filledHoles == 1 ? " was" : "s were") filled in, so \(filledHoles == 1 ? "it's" : "they're") sewn over.") }
        if lines + satins > 0 {
            // (how many, one, several, why)
            let kinds = [(lines, "running stitch line", "running stitch lines", "thinner than 1 mm"), (satins, "satin", "satin", "up to 8 mm across"), (tatamis, "tatami", "tatami", "wider")]
                .filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2) (\($0.3))" }
            warnings.append("Each part's stitch follows its width: " + kinds.joined(separator: ", ") + ".")
        }
        if failedParts > 0 { warnings.append("\(failedParts) part\(failedParts == 1 ? "" : "s") couldn't be traced cleanly and \(failedParts == 1 ? "was" : "were") left out. Try fewer colors or a larger smallest part.") }
        guard !objects.isEmpty else { throw DesignError.invalid("Nothing large enough to stitch was found. Try more colors, turn off Skip background, or lower the smallest part.") }
        guard objects.count <= 500 else { throw DesignError.invalid("The picture traced into \(objects.count) parts, which is too many. Use fewer colors or a larger smallest part.") }
        // Neighbors traced from the same pixel edge end up at most a smoothing step or two apart, so closer than
        // three pixels (at least 0.3 mm) counts as touching.
        setAngles(&objects, touching: 3 * max(0.1, pixelWidth, pixelHeight))
        try setStartPoints(&objects)
        var check = Design(); check.objects = objects; try check.validate()
        return AutoDigitizeResult(objects: objects, colors: colors, warnings: warnings)
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

    /// `parts` (each an outline and its holes) put in sewing order, nearest part next so the needle travels less:
    /// after the part sewn last, the one whose middle is closest to its middle. `after` is the middle of the part
    /// sewn just before these (the color before ends there); nil starts with the top-left part, where you'd start
    /// reading the picture.
    static func nearestFirst(_ parts: [[[Point]]], after: Point?) -> [[[Point]]] {
        var left = parts.map { (region: $0, middle: AreaGeometry.centroid($0[0])) }, ordered: [[[Point]]] = []
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
            ordered.append(left[next].region); last = left[next].middle
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

    /// The middle of a thin part as one path through pixel centers (in image pixels), and whether it is a loop (a
    /// thin ring). The part's pixels (those of `mask` whose centers are inside `region`, given in pixels) are thinned
    /// to a line one pixel wide, which is then walked from one end. Side branches are sewn out and back, shortest
    /// first, so the walk can end at the far end of the longest one. nil when thinning leaves nothing.
    static func centerline(of region: [[Point]], mask: [Bool], width w: Int, height h: Int) -> (path: [Point], closed: Bool)? {
        let points = region.flatMap { $0 }
        let x0 = max(0, Int(points.map(\.x).min()!)), x1 = min(w - 1, Int(points.map(\.x).max()!))
        let y0 = max(0, Int(points.map(\.y).min()!)), y1 = min(h - 1, Int(points.map(\.y).max()!))
        guard x0 <= x1, y0 <= y1 else { return nil }
        // Work in the part's box only, with an empty one-pixel border so every pixel has eight neighbors.
        let bw = x1 - x0 + 3, bh = y1 - y0 + 3
        var on = [Bool](repeating: false, count: bw * bh)
        for y in y0...y1 { for x in x0...x1 where mask[y * w + x] && AreaGeometry.contains(Point(Double(x) + 0.5, Double(y) + 0.5), rings: region) {
            on[(y - y0 + 1) * bw + x - x0 + 1] = true
        } }
        thin(&on, width: bw, height: bh)
        let pixels = on.indices.filter { on[$0] }
        guard let any = pixels.first else { return nil }
        // Neighbors along the sides first, then on the diagonals, so the walk prefers the straight step.
        let steps = [-bw, 1, bw, -1, -bw + 1, bw + 1, bw - 1, -bw - 1]
        func neighbors(_ i: Int) -> [Int] { steps.map { i + $0 }.filter { on[$0] } }
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
        return (walk.map { Point(Double($0 % bw + x0 - 1) + 0.5, Double($0 / bw + y0 - 1) + 0.5) }, closed)
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
