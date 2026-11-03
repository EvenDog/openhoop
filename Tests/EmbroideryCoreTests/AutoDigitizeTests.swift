// Auto-digitizing: small made-up pictures with known shapes and colors are traced into fill objects.
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import EmbroideryCore

final class AutoDigitizeTests: XCTestCase {
    /// A picture `size` pixels square where `paint(x, y)` gives each pixel's color as 0xRRGGBB, or nil for transparent.
    private func picture(_ size: Int, _ paint: (Int, Int) -> Int?) -> PixelImage {
        var bytes = [UInt8]()
        for y in 0..<size { for x in 0..<size {
            if let c = paint(x, y) { bytes += [UInt8(c >> 16 & 255), UInt8(c >> 8 & 255), UInt8(c & 255), 255] } else { bytes += [0, 0, 0, 0] }
        } }
        return PixelImage(width: size, height: size, rgba: bytes)
    }
    private func run(_ image: PixelImage, colors: Int = 2, skip: Bool = true, size: Double = 20, center: Point = Point(0, 0)) throws -> AutoDigitizeResult {
        var options = AutoDigitizeOptions(); options.colors = colors; options.skipBackground = skip
        return try AutoDigitize.run(image, center: center, width: size, height: size, options: options)
    }

    func testRingBecomesOneFillWithAHole() throws {
        // A red ring (outer radius 40 px, inner 20 px) on white, shown 20 mm wide: 0.2 mm per pixel.
        let ring = picture(100) { x, y in let r = hypot(Double(x) - 49.5, Double(y) - 49.5); return r < 40 && r > 20 ? 0xD02020 : 0xFFFFFF }
        let result = try run(ring)
        XCTAssertEqual(result.objects.count, 1)
        let fill = result.objects[0]
        XCTAssertEqual(fill.kind, .fill); XCTAssertEqual(fill.holes?.count, 1)
        XCTAssertEqual(fill.color.hex, 0xD02020)
        let area = abs(AreaGeometry.area(fill.nodes.map(\.point))) - abs(AreaGeometry.area(fill.holes![0].map(\.point)))
        XCTAssertEqual(area, Double.pi * (8 * 8 - 4 * 4), accuracy: 6, "Ring area in mm² (outer 8 mm, inner 4 mm radius)")
        XCTAssertEqual(result.colors.filter(\.background).map(\.color.hex), [0xFFFFFF], "White around the edges is the background")
        XCTAssertLessThan(fill.nodes.count, 120, "The pixel staircase is smoothed into far fewer points")
    }

    func testThreadColorsIgnoreBlendedEdges() throws {
        // A red dot whose edge blends into the white around it, as in a smoothed (anti-aliased) picture.
        let dot = picture(80) { x, y in
            let r = hypot(Double(x) - 39.5, Double(y) - 39.5)
            return r < 20 ? 0xD02020 : r < 24 ? 0xE89090 : 0xFFFFFF
        }
        XCTAssertEqual(try run(dot).objects[0].color.hex, 0xD02020, "The thread matches the dot, not the blended edge")
    }

    func testShapesLandWhereTheImageIs() throws {
        // A black square filling the top-left quarter of an image shown 50 mm wide, centered at (10, -5).
        let quarter = picture(100) { x, y in x < 50 && y < 50 ? 0x000000 : 0xFFFFFF }
        let points = try run(quarter, size: 50, center: Point(10, -5)).objects[0].nodes.map(\.point)
        XCTAssertEqual(points.map(\.x).min()!, -15, accuracy: 0.01); XCTAssertEqual(points.map(\.x).max()!, 10, accuracy: 0.01)
        XCTAssertEqual(points.map(\.y).max()!, 20, accuracy: 0.01); XCTAssertEqual(points.map(\.y).min()!, -5, accuracy: 0.01)
        // Smoothing only trims a sliver off each corner; it must not cut across them.
        XCTAssertEqual(abs(AreaGeometry.area(points)), 25 * 25, accuracy: 0.5)
    }

    func testSeveralColorsSewLargestFirst() throws {
        // A big blue square and a small yellow circle on white.
        let image = picture(100) { x, y in
            if hypot(Double(x) - 75, Double(y) - 75) < 12 { return 0xF0C020 }
            return x >= 10 && x < 55 && y >= 10 && y < 55 ? 0x2040A0 : 0xFFFFFF
        }
        let result = try run(image, colors: 3)
        XCTAssertEqual(result.objects.map(\.color.hex), [0x2040A0, 0xF0C020])
        XCTAssertEqual(result.objects.map(\.color.name), ["Color 2", "Color 3"], "Color 1 is the white background")
        XCTAssertEqual(result.colors.count, 3)
        var design = Design(); design.objects = result.objects
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100, "The traced fills sew")
    }

    func testTransparentBackgroundAndSpecks() throws {
        // A green square on a transparent background, sprinkled with single dark pixels.
        let image = picture(80) { x, y in
            if (x * 7 + y * 13) % 97 == 0 { return 0x101010 }
            return x >= 20 && x < 60 && y >= 20 && y < 60 ? 0x30A050 : nil
        }
        let result = try run(image, colors: 3)
        XCTAssertEqual(result.objects.count, 1, "Specks are cleaned up and the transparent area is skipped")
        XCTAssertEqual(result.objects[0].color.hex, 0x30A050)
        XCTAssertNil(result.objects[0].holes)
    }

    func testShapesTouchingAtACornerStillTrace() throws {
        // Two squares meeting at a single corner can't be sewn as touching outlines; they must still trace cleanly.
        let image = picture(60) { x, y in (x < 30) == (y < 30) ? 0x000000 : 0xFFFFFF }
        let result = try run(image, size: 30)
        XCTAssertFalse(result.objects.isEmpty)
        XCTAssertFalse(result.warnings.contains { $0.contains("couldn't be traced") }, "\(result.warnings)")
    }

    func testADetailedPictureTracesInsteadOfFailing() throws {
        // A black square, 60 mm, with a ragged edge (1-pixel teeth all round, far more points than one fill may have)
        // and 400 white holes: tiny ones (0.36 mm², under the 2 mm² smallest part) and bigger ones (2.56 mm²).
        // It used to fail outright because one fill can hold 2,000 points and 100 holes.
        let image = picture(320) { x, y in
            let inside = x >= 10 && x < 310 && y >= 10 && y < 310
            let tooth = (x < 13 || x >= 307 || y < 13 || y >= 307) && (x + y) % 2 == 0
            guard inside && !tooth else { return 0xFFFFFF }
            let gx = (x - 10) % 14, gy = (y - 10) % 14, big = ((x - 10) / 14 + (y - 10) / 14) % 2 == 0
            return gx >= 3 && gy >= 3 && gx < (big ? 11 : 6) && gy < (big ? 11 : 6) ? 0xFFFFFF : 0x000000
        }
        let result = try run(image, size: 64)
        XCTAssertEqual(result.objects.count, 1)
        let fill = result.objects[0]
        XCTAssertLessThanOrEqual(fill.holes?.count ?? 0, 100, "only the 100 largest holes stay")
        XCTAssertLessThanOrEqual(fill.allNodes.count, 2000)
        XCTAssertTrue(result.warnings.contains { $0.contains("filled in") }, "\(result.warnings)")
        var design = Design(); design.objects = result.objects
        XCTAssertNoThrow(try design.validate())
        XCTAssertNoThrow(try StitchEngine.compile(design))
    }

    func testSmallPartsAreLeftOutAndExplained() throws {
        let image = picture(100) { x, y in
            if x >= 80 && x < 83 && y >= 80 && y < 83 { return 0x000000 }   // 0.36 mm² at 0.2 mm per pixel
            return x >= 10 && x < 60 && y >= 10 && y < 60 ? 0x000000 : 0xFFFFFF
        }
        let result = try run(image)
        XCTAssertEqual(result.objects.count, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("smaller than") })
    }

    func testDecodingShrinksLargeImages() throws {
        let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let image = try PixelImage(data: data as Data, maxSide: 100)
        XCTAssertEqual(image.width, 100); XCTAssertEqual(image.height, 50)
        XCTAssertEqual(Array(image.rgba.prefix(4)), [255, 0, 0, 255])
        XCTAssertThrowsError(try PixelImage(data: Data("not an image".utf8), maxSide: 100))
    }

    func testNothingToTraceIsExplained() throws {
        XCTAssertThrowsError(try run(picture(40) { _, _ in nil }))
        XCTAssertThrowsError(try run(picture(40) { _, _ in 0xFFFFFF }), "A blank picture is all background")
        XCTAssertThrowsError(try run(picture(40) { x, _ in x < 20 ? 0 : 0xFFFFFF }, colors: 9))
    }

    func testColorsBecomeThreadsFromTheChosenChart() throws {
        // A big dark-blue square and a small blue circle on white. Both blues are nearest the chart's "Navy",
        // so the larger one gets Navy and the smaller one the next closest thread, never the same one.
        let image = picture(100) { x, y in
            if hypot(Double(x) - 75, Double(y) - 75) < 12 { return 0x2840B0 }
            return x >= 10 && x < 55 && y >= 10 && y < 55 ? 0x203890 : 0xFFFFFF
        }
        let chart = ThreadChart(name: "Test Brand", threads: [
            ThreadColor("Navy", 0x203890, brand: "Test Brand", code: "100"), ThreadColor("Royal", 0x3050D0, brand: "Test Brand", code: "200"),
            ThreadColor("Red", 0xD02020, brand: "Test Brand", code: "300")])
        var options = AutoDigitizeOptions(); options.colors = 3; options.chart = chart
        let result = try AutoDigitize.run(image, center: Point(0, 0), width: 20, height: 20, options: options)
        XCTAssertEqual(result.objects.map(\.color.name), ["Navy", "Royal"])
        XCTAssertEqual(result.objects.map(\.color.chartLabel), ["Test Brand 100", "Test Brand 200"])
        XCTAssertEqual(result.colors.filter(\.background).map(\.color.hex), [0xFFFFFF], "The background, which isn't sewn, keeps the picture's color")
        // Without a chart the picture's own colors stay.
        XCTAssertNil(try run(image, colors: 3).objects.first?.color.brand)
    }

    func testFillsRunAlongTheirLongSide() throws {
        // On white, apart from each other: a tall blue bar, a wide red bar and a green square.
        let image = picture(100) { x, y in
            if x >= 10 && x < 20 && y >= 10 && y < 90 { return 0x2040A0 }
            if x >= 35 && x < 95 && y >= 10 && y < 20 { return 0xD02020 }
            if x >= 50 && x < 80 && y >= 50 && y < 80 { return 0x20A040 }
            return 0xFFFFFF
        }
        let fills = try run(image, colors: 4).objects
        func angle(_ hex: Int) -> Double { fills.first { $0.color.hex == hex }!.settings.angle }
        XCTAssertEqual(angle(0x2040A0), 90, "the tall bar's rows run up and down")
        XCTAssertEqual(angle(0xD02020), 0, "the wide bar's rows run across")
        XCTAssertEqual(angle(0x20A040), DigitizingSettings(kind: .fill).angle, "a square has no long side, so it keeps the default")
    }

    func testTouchingFillsGetDifferentAngles() throws {
        // Two wide bars, red above blue: touching, then with a white gap between them.
        func bars(gap: Int) -> PixelImage {
            picture(100) { x, y in
                guard x >= 10 && x < 90 else { return 0xFFFFFF }
                if y >= 20 && y < 40 { return 0xD02020 }
                if y >= 40 + gap && y < 60 + gap { return 0x2040A0 }
                return 0xFFFFFF
            }
        }
        let touching = try run(bars(gap: 0), colors: 3).objects.map(\.settings.angle)
        XCTAssertEqual(touching.count, 2)
        XCTAssertEqual(touching[0], 0, "the first bar sews along its long side")
        XCTAssertEqual(touching[1], 45, "the bar touching it turns 45°, so the two don't read as one patch")
        XCTAssertEqual(try run(bars(gap: 20), colors: 3).objects.map(\.settings.angle), [0, 0], "apart, both follow their long side")
    }

    func testPartsSewNearestFirstAndStartWhereTheLastEnded() throws {
        // Three black dots: A top left, B top right a little lower, C just below A. Top to bottom would be A, B, C;
        // nearest first is A, C, B.
        let dots = [(15, 15), (85, 20), (15, 40)]
        let image = picture(100) { x, y in dots.contains { hypot(Double(x - $0.0), Double(y - $0.1)) < 6 } ? 0x000000 : 0xFFFFFF }
        let fills = try run(image).objects
        // Picture pixel (x, y) → canvas mm: 20 mm across 100 px, centered on 0, y up.
        let middles = fills.map { AreaGeometry.centroid($0.nodes.map(\.point)) }
        let expected = [dots[0], dots[2], dots[1]].map { Point(Double($0.0) * 0.2 - 10, 10 - Double($0.1) * 0.2) }
        for (middle, dot) in zip(middles, expected) { XCTAssertLessThan(middle.distance(to: dot), 0.5) }
        XCTAssertNil(fills[0].entry, "the first part starts on its own")
        XCTAssertTrue(fills.dropFirst().allSatisfy { $0.entry != nil }, "each later part starts where the one before it ended")
    }

    func testStartPointsMatchAutoStartPoints() throws {
        // A grid of touching squares in three colors: the quick start points equal those of the slower command.
        let image = picture(90) { x, y in [0xD02020, 0x2040A0, 0x20A040][(x / 30 + y / 30) % 3] }
        let fills = try run(image, colors: 3, skip: false).objects
        XCTAssertEqual(fills.count, 5, "squares of one color meeting at a corner join into one part")
        var design = Design(); design.objects = fills.map { var fill = $0; fill.entry = nil; return fill }
        XCTAssertEqual(try StitchEngine.autoStartPoints(design).objects.map(\.entry), fills.map(\.entry))
    }
}
