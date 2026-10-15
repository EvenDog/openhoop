// Auto-digitizing turns the reference image into fill shapes. It reduces the picture to a few thread colors,
// traces the outline of every patch of each color along the pixel edges, smooths away the pixel "staircase",
// and makes each patch a tatami fill (with holes) placed exactly over the image.
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
    public init() {}
    public static let colorRange = 2...8
}

/// One thread color found in the picture.
public struct AutoDigitizeColor: Sendable, Equatable {
    public var color: ThreadColor
    public var area: Double       // square millimeters covered
    public var parts: Int         // fill objects made in this color
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
        var smallParts = 0, failedParts = 0, thinParts = 0
        for (number, label) in order.enumerated() {
            try Task.checkCancellation()
            let thread = ThreadColor("Color \(number + 1)", centers[label])
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
            for region in try AreaGeometry.svgRegions(rings, nonzero: false) {
                let area = AreaGeometry.area(region[0]).magnitude - region.dropFirst().reduce(0) { $0 + AreaGeometry.area($1).magnitude }
                guard area >= max(options.smallestArea, 0.05) else { smallParts += 1; continue }
                guard (try? AreaGeometry.validate(region)) != nil else { failedParts += 1; continue }
                let perimeter = region.reduce(0) { $0 + AreaGeometry.pathLength($1 + [$1[0]]) }
                if 2 * area / perimeter < 1.2 { thinParts += 1 }   // area ÷ half the perimeter: about the width of a strip, the radius of a dot
                parts.append(region)
            }
            // Top to bottom, then left to right, so the sewing order reads like the picture.
            parts.sort { a, b in
                let ya = a[0].map(\.y).max()!, yb = b[0].map(\.y).max()!
                return abs(ya - yb) > 1 ? ya > yb : a[0].map(\.x).min()! < b[0].map(\.x).min()!
            }
            for (index, region) in parts.enumerated() {
                var object = RunObject(name: "\(thread.name) area \(index + 1)", nodes: region[0].map { PathNode($0) }, color: thread)
                object.closed = true; object.holes = region.count > 1 ? region.dropFirst().map { $0.map { PathNode($0) } } : nil
                object.digitizing = DigitizingSettings(kind: .fill)
                objects.append(object)
            }
            colors.append(AutoDigitizeColor(color: thread, area: Double(areas[label]) * pixelArea, parts: parts.count, background: false))
        }
        if hasTransparency && options.skipBackground == false { warnings.append("Transparent parts of the image are always left out.") }
        if smallParts > 0 { warnings.append("\(smallParts) patch\(smallParts == 1 ? " was" : "es were") smaller than \(options.smallestArea.formatted()) mm² and left out.") }
        if thinParts > 0 { warnings.append("\(thinParts) part\(thinParts == 1 ? " is" : "s are") narrower than about 1.2 mm. Fill sews thin parts poorly; consider redrawing them as satin or running stitch.") }
        if failedParts > 0 { warnings.append("\(failedParts) part\(failedParts == 1 ? "" : "s") couldn't be traced cleanly and \(failedParts == 1 ? "was" : "were") left out. Try fewer colors or a larger smallest part.") }
        guard !objects.isEmpty else { throw DesignError.invalid("Nothing large enough to stitch was found. Try more colors, turn off Skip background, or lower the smallest part.") }
        guard objects.count <= 500 else { throw DesignError.invalid("The picture traced into \(objects.count) parts, which is too many. Use fewer colors or a larger smallest part.") }
        var check = Design(); check.objects = objects; try check.validate()
        return AutoDigitizeResult(objects: objects, colors: colors, warnings: warnings)
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
    static func simplify(_ ring: [Point], tolerance: Double) -> [Point] {
        guard ring.count > 4 else { return ring }
        // Split the ring at its first point and the point farthest from it, then simplify the two halves as lines.
        let far = ring.indices.max { ring[0].distance(to: ring[$0]) < ring[0].distance(to: ring[$1]) }!
        func line(_ points: ArraySlice<Point>) -> [Point] {
            guard points.count > 2, let first = points.first, let last = points.last else { return Array(points) }
            var worst = points.startIndex, worstDistance = 0.0
            for i in points.indices.dropFirst().dropLast() {
                let d = points[i].distance(to: AreaGeometry.projection(points[i], first, last))
                if d > worstDistance { worst = i; worstDistance = d }
            }
            guard worstDistance > tolerance else { return [first, last] }
            return line(points[points.startIndex...worst]).dropLast() + line(points[worst...])
        }
        let firstHalf = line(ring[0...far]), secondHalf = line((ring + [ring[0]])[far...])
        let result = Array(firstHalf.dropLast() + secondHalf.dropLast())
        return result.count >= 3 ? result : ring
    }
}
