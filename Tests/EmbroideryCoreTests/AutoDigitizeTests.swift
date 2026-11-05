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
        // A red ring (outer radius 40 px, inner 20 px) on white, shown 60 mm wide: 0.6 mm per pixel, so the ring is
        // 12 mm wide, too wide for satin.
        let ring = picture(100) { x, y in let r = hypot(Double(x) - 49.5, Double(y) - 49.5); return r < 40 && r > 20 ? 0xD02020 : 0xFFFFFF }
        let result = try run(ring, size: 60)
        XCTAssertEqual(result.objects.count, 1)
        let fill = result.objects[0]
        XCTAssertEqual(fill.kind, .fill); XCTAssertEqual(fill.holes?.count, 1)
        XCTAssertEqual(fill.color.hex, 0xD02020)
        let area = abs(AreaGeometry.area(fill.nodes.map(\.point))) - abs(AreaGeometry.area(fill.holes![0].map(\.point)))
        XCTAssertEqual(area, Double.pi * (24 * 24 - 12 * 12), accuracy: 54, "Ring area in mm² (outer 24 mm, inner 12 mm radius)")
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
        // On white, apart from each other: a tall blue bar, a wide red bar and a green square. Shown 100 mm wide,
        // so even the bars are 10 mm across: too wide for satin, so all three are tatami.
        let image = picture(100) { x, y in
            if x >= 10 && x < 20 && y >= 10 && y < 90 { return 0x2040A0 }
            if x >= 35 && x < 95 && y >= 10 && y < 20 { return 0xD02020 }
            if x >= 50 && x < 80 && y >= 50 && y < 80 { return 0x20A040 }
            return 0xFFFFFF
        }
        let fills = try run(image, colors: 4, size: 100).objects
        func angle(_ hex: Int) -> Double { fills.first { $0.color.hex == hex }!.settings.angle }
        XCTAssertEqual(angle(0x2040A0), 90, "the tall bar's rows run up and down")
        XCTAssertEqual(angle(0xD02020), 0, "the wide bar's rows run across")
        XCTAssertEqual(angle(0x20A040), DigitizingSettings(kind: .fill).angle, "a square has no long side, so it keeps the default")
    }

    func testTouchingFillsGetDifferentAngles() throws {
        // Two wide bars, red above blue: touching, then with a white gap between them. Shown 100 mm wide (bars
        // 20 mm across, so tatami).
        func bars(gap: Int) -> PixelImage {
            picture(100) { x, y in
                guard x >= 10 && x < 90 else { return 0xFFFFFF }
                if y >= 20 && y < 40 { return 0xD02020 }
                if y >= 40 + gap && y < 60 + gap { return 0x2040A0 }
                return 0xFFFFFF
            }
        }
        let touching = try run(bars(gap: 0), colors: 3, size: 100).objects.map(\.settings.angle)
        XCTAssertEqual(touching.count, 2)
        XCTAssertEqual(touching[0], 0, "the first bar sews along its long side")
        XCTAssertEqual(touching[1], 45, "the bar touching it turns 45°, so the two don't read as one patch")
        XCTAssertEqual(try run(bars(gap: 20), colors: 3, size: 100).objects.map(\.settings.angle), [0, 0], "apart, both follow their long side")
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

    func testStitchTypeFollowsWidth() throws {
        // Shown 40 mm wide (0.4 mm per pixel), on white: a black line 2 pixels (0.8 mm) wide that bends like an L,
        // a red bar 10 pixels (4 mm) wide, and a big blue square 40 pixels (16 mm).
        let image = picture(100) { x, y in
            if (x >= 10 && x < 12 && y >= 10 && y < 60) || (y >= 58 && y < 60 && x >= 10 && x < 40) { return 0x000000 }
            if x >= 50 && x < 90 && y >= 10 && y < 20 { return 0xD02020 }
            if x >= 50 && x < 90 && y >= 40 && y < 80 { return 0x2040A0 }
            return 0xFFFFFF
        }
        let result = try run(image, colors: 4, size: 40)
        func part(_ hex: Int) -> RunObject { result.objects.first { $0.color.hex == hex }! }
        let line = part(0x000000), bar = part(0xD02020), square = part(0x2040A0)

        XCTAssertEqual(line.kind, .run); XCTAssertEqual(line.settings.runPasses, 3, "a triple (bean) running stitch")
        XCTAssertFalse(line.closed)
        // The run follows the L down its middle: from near one end, through the corner, to near the other end.
        let points = line.nodes.map(\.point), middleX = -20 + 11 * 0.4, middleY = 20 - 59 * 0.4
        XCTAssertEqual(AreaGeometry.pathLength(points), 19.6 + 11.6, accuracy: 2.5, "about as long as the L's two arms")
        XCTAssertTrue(points.allSatisfy { abs($0.x - middleX) < 0.5 || abs($0.y - middleY) < 0.5 }, "every point on the middle of an arm: \(points)")

        XCTAssertEqual(bar.kind, .fill); XCTAssertEqual(bar.settings.fillStyle, .satin)
        XCTAssertEqual(bar.settings.angle, 90, "satin stitches run across the bar")
        XCTAssertEqual(square.settings.fillStyle ?? .tatami, .tatami, "wider than 8 mm stays tatami")
        XCTAssertTrue(result.warnings.contains("Each part's stitch follows its width: 1 running stitch line (thinner than 1 mm), 1 satin (up to 8 mm across), 1 tatami (wider)."), "\(result.warnings)")
        var design = Design(); design.objects = result.objects
        XCTAssertNoThrow(try StitchEngine.compile(design))
    }

    func testAThinRingBecomesALoop() throws {
        // A black circle outline 2 pixels (0.8 mm) wide, radius 30 pixels (12 mm), on white.
        let image = picture(100) { x, y in let r = hypot(Double(x) - 49.5, Double(y) - 49.5); return r >= 29 && r < 31 ? 0x000000 : 0xFFFFFF }
        let line = try run(image, size: 40).objects
        XCTAssertEqual(line.count, 1); XCTAssertEqual(line[0].kind, .run)
        XCTAssertTrue(line[0].closed, "the ring is sewn as a closed loop")
        let radii = line[0].nodes.map { hypot($0.point.x, $0.point.y) }
        XCTAssertTrue(radii.allSatisfy { abs($0 - 12) < 0.6 }, "the loop runs down the middle of the ring: \(radii)")
    }

    func testThinningLeavesALineOnePixelWide() {
        // A bar 5 pixels tall and 20 long (with the empty border thinning needs) thins to a single row.
        let w = 24, h = 9
        var on = (0..<(w * h)).map { i in (2..<22).contains(i % w) && (2..<7).contains(i / w) }
        AutoDigitize.thin(&on, width: w, height: h)
        let rows = Set(on.indices.filter { on[$0] }.map { $0 / w })
        XCTAssertEqual(rows, [4], "one row, down the middle")
        XCTAssertGreaterThan(on.filter { $0 }.count, 14, "the line keeps most of its length")
    }

    func testEarlierPartsReachUnderLaterOnes() throws {
        // Shown 100 mm wide at 0.25 mm per pixel (about as fine as real tracing), on white: a big blue square, and
        // a smaller red one touching the middle of its right side. Blue is the larger area, so it sews first and
        // reaches under red. (In mm from the picture's top left: blue 10–60 across, 20–80 down; red 60–85, 30–70.)
        let image = picture(400) { x, y in
            let x = x / 4, y = y / 4
            if x >= 10 && x < 60 && y >= 20 && y < 80 { return 0x2040A0 }
            if x >= 60 && x < 85 && y >= 30 && y < 70 { return 0xD02020 }
            return 0xFFFFFF
        }
        let result = try run(image, colors: 3, size: 100)
        let blue = result.objects[0], red = result.objects[1]
        XCTAssertEqual(blue.color.hex, 0x2040A0)
        let b = blue.nodes.map(\.point), r = red.nodes.map(\.point)
        // Picture mm → canvas mm: x - 50 across, 50 - y up.
        XCTAssertEqual(b.map(\.x).max()!, 10 + AutoDigitize.overlapAmount, accuracy: 0.1, "blue reaches under red")
        XCTAssertEqual(b.map(\.x).min()!, -40, accuracy: 0.05, "blue's edges on bare fabric stay put")
        XCTAssertEqual(b.map(\.y).max()!, 30, accuracy: 0.05); XCTAssertEqual(b.map(\.y).min()!, -30, accuracy: 0.05)
        // Above and below red, blue's right edge stays at 10 mm: only the part beside red grew.
        XCTAssertTrue(b.filter { abs($0.y) > 20.5 }.allSatisfy { $0.x <= 10.05 }, "\(b)")
        XCTAssertEqual(abs(AreaGeometry.area(b)), 50 * 60 + 40 * AutoDigitize.overlapAmount, accuracy: 3)
        XCTAssertEqual(r.map(\.x).min()!, 10, accuracy: 0.05, "red, sewn on top, keeps its shape")
        XCTAssertTrue(result.warnings.contains { $0.hasPrefix("1 part reaches 0.8 mm under") }, "\(result.warnings)")
    }

    func testFillsMeetUnderAThinLine() throws {
        // Shown 40 mm wide (0.4 mm per pixel): a blue square cut in two by a black line 2 pixels (0.8 mm) wide. The
        // line is the smaller area, so it sews last, on top; both blue halves reach under it, leaving no fabric bare.
        let image = picture(100) { x, y in
            guard x >= 10 && x < 90 && y >= 10 && y < 90 else { return 0xFFFFFF }
            return x == 49 || x == 50 ? 0x000000 : 0x2040A0
        }
        let objects = try run(image, colors: 3, size: 40).objects
        XCTAssertEqual(objects.map(\.kind), [.fill, .fill, .run])
        let halves = objects.prefix(2).map { $0.nodes.map(\.point) }.sorted { $0.map(\.x).min()! < $1.map(\.x).min()! }
        XCTAssertGreaterThan(halves[0].map(\.x).max()!, halves[1].map(\.x).min()!, "the two halves overlap under the line")
    }

    /// Cutting a fill's growth to shape can leave a speck of a hole touching its outline, which a fill can't have.
    /// That used to throw the whole growth away (fabric then showed along the seam); now the speck is sewn over.
    func testASpeckTouchingTheOutlineDoesNotStopTheGrowth() throws {
        let square = [Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)]
        let speck = [Point(9, 4.5), Point(9, 5.5), Point(10, 5)]   // a hole with a corner on the right edge
        XCTAssertThrowsError(try AreaGeometry.validate([square, speck]))
        let region = try XCTUnwrap(AutoDigitize.sewable([square, speck]))
        XCTAssertNoThrow(try AreaGeometry.validate(region))
        XCTAssertEqual(AreaGeometry.area(region[0]).magnitude, 100, accuracy: 1.5, "the square, a hair smaller")
        // A shape pinched to a point (two squares meeting at a corner) would come apart, so it isn't used.
        let pinched = [Point(0, 0), Point(5, 0), Point(5, 5), Point(10, 5), Point(10, 10), Point(5, 10), Point(5, 5), Point(0, 5)]
        XCTAssertNil(AutoDigitize.sewable([pinched]))
        // A shape that's fine as it is stays exactly as it is.
        XCTAssertEqual(AutoDigitize.sewable([square]), [square])
    }

    /// The width of a satin column: how far apart each pair of rail points is, on average.
    private func satinWidth(_ satin: RunObject) -> Double {
        let points = satin.nodes.map(\.point)
        let pairs = stride(from: 0, to: points.count - 1, by: 2).map { points[$0].distance(to: points[$0 + 1]) }
        return pairs.reduce(0, +) / Double(pairs.count)
    }

    func testACurvedStripBecomesASatinColumn() throws {
        // A red ring (outer radius 40 px, inner 20 px) shown 20 mm wide: a strip 4 mm wide bent all the way round,
        // too curved for satin fill's single stitch direction.
        let ring = picture(100) { x, y in let r = hypot(Double(x) - 49.5, Double(y) - 49.5); return r < 40 && r > 20 ? 0xD02020 : 0xFFFFFF }
        let result = try run(ring)
        XCTAssertEqual(result.objects.count, 1)
        let satin = result.objects[0]
        XCTAssertEqual(satin.kind, .satin); XCTAssertTrue(satin.closed, "one closed column all the way round")
        XCTAssertEqual(satinWidth(satin), 4, accuracy: 0.4)
        let middles = stride(from: 0, to: satin.nodes.count - 1, by: 2).map { (satin.nodes[$0].point + satin.nodes[$0 + 1].point) * 0.5 }
        XCTAssertTrue(middles.allSatisfy { abs(hypot($0.x, $0.y) - 6) < 0.5 }, "the column runs down the middle of the ring")
        XCTAssertTrue(result.warnings.contains { $0.contains("1 satin column (along curved strips)") }, "\(result.warnings)")
        var design = Design(); design.objects = result.objects
        XCTAssertNoThrow(try StitchEngine.compile(design))
    }

    func testStripsSplitIntoColumnsWhereTheyMeet() throws {
        // A black T of strips 15 px (3 mm) wide, shown 20 mm wide: a bar across the top and a stem down from its middle.
        let tee = picture(100) { x, y in
            (y >= 20 && y < 35 && x >= 10 && x < 90) || (x >= 42 && x < 57 && y >= 35 && y < 90) ? 0x000000 : 0xFFFFFF
        }
        let objects = try run(tee).objects
        XCTAssertEqual(objects.map(\.kind), [.satin, .satin, .satin], "the bar's two halves and the stem, meeting at the junction")
        for satin in objects { XCTAssertEqual(satinWidth(satin), 3, accuracy: 0.4) }
        // Each loose end reaches out to the tip of its strip (thinning alone stops about half the width short).
        let ends = objects.flatMap { $0.nodes.map(\.point) }
        XCTAssertEqual(ends.map(\.x).min()!, -8, accuracy: 0.4, "the bar's left tip")
        XCTAssertEqual(ends.map(\.x).max()!, 8, accuracy: 0.4, "the bar's right tip")
        XCTAssertEqual(ends.map(\.y).min()!, -8, accuracy: 0.4, "the stem's tip")
        var design = Design(); design.objects = objects
        XCTAssertNoThrow(try StitchEngine.compile(design))
    }

    func testATaperedStripBecomesATurningSatin() throws {
        // A crescent, shown 20 mm wide: a disc (radius 8 mm) with the same disc moved up 6 mm cut out. It is 6 mm thick
        // at the bottom and tapers to points; its box is about 16 × 11 mm, too bent for satin fill's one direction,
        // and an even-width column can't follow it. It becomes a satin fill whose stitches turn with the strip.
        let moon = picture(100) { x, y in
            hypot(Double(x) - 49.5, Double(y) - 49.5) < 40 && hypot(Double(x) - 49.5, Double(y) - 19.5) >= 40 ? 0xF0C020 : 0xFFFFFF
        }
        let result = try run(moon)
        XCTAssertEqual(result.objects.count, 1)
        let fill = result.objects[0]
        XCTAssertEqual(fill.kind, .fill); XCTAssertEqual(fill.settings.fillStyle, .satin)
        let lines = try XCTUnwrap(fill.settings.angleLines)
        XCTAssertGreaterThanOrEqual(lines.count, 3, "stitch angle lines across the strip")
        XCTAssertGreaterThan(AutoDigitize.turnedBox(fill.nodes.map(\.point)).short, 8, "the outline is the traced crescent, tips and all")
        XCTAssertTrue(result.warnings.contains { $0.contains("1 tapered satin (turning with the strip)") }, "\(result.warnings)")
        // Sewn, every stitch crosses the strip (at most 6 mm thick, plus compensation): none runs along it.
        var design = Design(); design.objects = result.objects
        let commands = try StitchEngine.compile(design).commands
        var longest = 0.0
        for (a, b) in zip(commands, commands.dropFirst()) where a.op == .stitch && b.op == .stitch { longest = max(longest, a.point.distance(to: b.point)) }
        XCTAssertGreaterThan(longest, 3); XCTAssertLessThan(longest, 7.5)
    }

    func testASpikyRingIsNotAStrip() throws {
        // A sun, shown 68 mm wide (0.2 mm per pixel): a yellow face (radius 106 px) inside an orange band out to 134 px,
        // with 10 pointed rays reaching out to 165 px. Down the band's middle the orange looks like an even ring, but
        // the rays stick far out of it, so satin along that middle would cut them off: the orange stays a fill.
        let sun = picture(340) { x, y in
            let dx = Double(x) - 169.5, dy = Double(y) - 169.5, r = hypot(dx, dy)
            let turn = (atan2(dy, dx) / (2 * .pi) * 10 + 10).truncatingRemainder(dividingBy: 1)   // 0 to 1 between tips
            let rayEdge = 134 + 31 * max(0, abs(2 * turn - 1) - 0.25) / 0.75   // 165 at the tips, 134 between rays
            return r < 106 ? 0xFFC020 : r < rayEdge ? 0xF08020 : 0xFFFFFF
        }
        let result = try run(sun, colors: 3, size: 68)
        let orange = try XCTUnwrap(result.objects.first { $0.color.hex == 0xF08020 })
        XCTAssertEqual(orange.kind, .fill); XCTAssertNil(orange.settings.angleLines)
        XCTAssertEqual(orange.nodes.map { hypot($0.point.x, $0.point.y) }.max()!, 33, accuracy: 0.6, "the rays' tips are kept")
        XCTAssertFalse(result.warnings.contains { $0.contains("satin column") || $0.contains("tapered satin") }, "\(result.warnings)")
    }

    func testPatchesCanBeSetByHand() throws {
        // Shown 20 mm wide (0.2 mm per pixel): a red disc 10 mm across on the left, a black bar 3 × 12 mm on the right.
        let image = picture(100) { x, y in
            if hypot(Double(x) - 29.5, Double(y) - 49.5) < 25 { return 0xD02020 }
            return x >= 65 && x < 80 && y >= 20 && y < 80 ? 0x000000 : 0xFFFFFF
        }
        var options = AutoDigitizeOptions(); options.colors = 3
        let trace = try AutoDigitize.trace(image, center: Point(0, 0), width: 20, height: 20, options: options)
        let disc = try XCTUnwrap(trace.patch(at: Point(-4, 0))), bar = try XCTUnwrap(trace.patch(at: Point(4.5, 0)))
        XCTAssertNil(trace.patch(at: Point(9, 9)), "the background is no patch")
        XCTAssertEqual(trace.patches[disc].suggested, .tatami); XCTAssertEqual(trace.patches[bar].suggested, .satin)
        XCTAssertEqual(try trace.build().objects.map(\.name), try run(image, colors: 3).objects.map(\.name), "left alone, it's plain auto-digitize")
        // A stitch for a whole color sets each of its patches, except those already suggested it.
        let red = trace.patches[disc].thread, black = trace.patches[bar].thread
        XCTAssertEqual(trace.suggestions(for: red), [.tatami]); XCTAssertEqual(trace.suggestions(for: black), [.satin])
        XCTAssertEqual(trace.choices(byThread: [red: .satin, black: .satin]), [disc: .satin], "the bar is satin already")

        /// The objects stitching the patch in `color`, as built with `choices`.
        func built(_ choices: [Int: PatchStitch], _ color: Int) throws -> [RunObject] { try trace.build(choices).objects.filter { $0.color.hex == color } }
        let satinDisc = try XCTUnwrap(built([disc: .satin], 0xD02020).first)
        XCTAssertEqual(satinDisc.kind, .fill); XCTAssertEqual(satinDisc.settings.fillStyle, .satin)
        let tatamiBar = try XCTUnwrap(built([bar: .tatami], 0x000000).first)
        XCTAssertEqual(tatamiBar.kind, .fill); XCTAssertNotEqual(tatamiBar.settings.fillStyle, .satin)
        // A line: down the middle of the 3 mm bar, round the edge of the 10 mm disc.
        let barLine = try built([bar: .line], 0x000000)
        XCTAssertEqual(barLine.count, 1); XCTAssertEqual(barLine[0].kind, .run); XCTAssertFalse(barLine[0].closed)
        XCTAssertEqual(barLine[0].nodes.map(\.point.x).max()! - barLine[0].nodes.map(\.point.x).min()!, 0, accuracy: 0.5, "straight down the bar's middle")
        let discLine = try built([disc: .line], 0xD02020)
        XCTAssertEqual(discLine.count, 1); XCTAssertEqual(discLine[0].kind, .run); XCTAssertTrue(discLine[0].closed)
        XCTAssertEqual(discLine[0].nodes.map { hypot($0.point.x + 4, $0.point.y) }.max()!, 5, accuracy: 0.3, "round the disc's edge")
        XCTAssertTrue(try built([bar: .leaveOut], 0x000000).isEmpty)
        let result = try trace.build([bar: .leaveOut, disc: .satin])
        XCTAssertTrue(result.warnings.contains("2 parts were set by hand. Stitches: 1 satin."), "\(result.warnings)")
        XCTAssertThrowsError(try trace.build([bar: .leaveOut, disc: .leaveOut]))
        var design = Design(); design.objects = try trace.build([bar: .line, disc: .line]).objects
        XCTAssertNoThrow(try StitchEngine.compile(design))
    }

    func testOutlineColorsSewLast() throws {
        // Shown 20 mm wide: a red disc (radius 20 px, 4 mm) inside a black ring outline (radius 20–35 px, 3 mm wide),
        // on white. Black covers the larger area, so by area it would sew first; as an outline it sews last, on top.
        let image = picture(100) { x, y in
            let r = hypot(Double(x) - 49.5, Double(y) - 49.5)
            return r < 20 ? 0xD02020 : r < 35 ? 0x000000 : 0xFFFFFF
        }
        let result = try run(image, colors: 3)
        XCTAssertEqual(result.objects.map(\.color.hex), [0xD02020, 0x000000], "the fill first, its outline on top")
        XCTAssertEqual(result.objects[1].kind, .satin)
        XCTAssertEqual(result.objects.map(\.name), ["Color 3 area 1", "Color 2 satin 1"], "named in sewing order (white, the background, is Color 1)")
        XCTAssertEqual(result.colors.filter { !$0.background }.map(\.color.hex), [0xD02020, 0x000000], "listed in sewing order")
        XCTAssertTrue(result.warnings.contains("Color 2 is mostly outlines, so it sews last, on top of the other colors."), "\(result.warnings)")
        // Sewn before the outline, the red disc reaches under it.
        let radii = result.objects[0].nodes.map { hypot($0.point.x, $0.point.y) }
        XCTAssertEqual(radii.max()!, 4 + AutoDigitize.overlapAmount, accuracy: 0.15)
    }
}
