// Checks the stitch quality checker itself, and (when asked) runs it over sample designs, every fill style on
// several shapes and sizes, satins, bean stitch, appliqué and every embroidery font, writing a report.
// Run the report with:  QUALITY_REPORT=/path/to/report.md swift test --filter StitchQualityTests
import XCTest
@testable import EmbroideryCore

final class StitchQualityTests: XCTestCase {
    private func stitch(_ x: Double, _ y: Double = 0, _ op: StitchOperation = .stitch) -> StitchCommand { StitchCommand(op, Point(x, y), thread: 0) }

    func testCountsShortLongAndRepeatedStitches() {
        var plan = StitchPlan()
        plan.commands = [stitch(0), stitch(0.1), stitch(0.1), stitch(0.5), stitch(3), stitch(11), stitch(24),
                         stitch(30, 0, .jump), stitch(30.05)]   // the jump breaks the run: no stitch from 24 to 30.05
        let quality = StitchQuality(plan: plan, design: Design())
        XCTAssertEqual(quality.stitches, 8)
        XCTAssertEqual(quality.tiny.count, 1)        // 0 → 0.1
        XCTAssertEqual(quality.zeroLength.count, 1)  // 0.1 → 0.1
        XCTAssertEqual(quality.short.count, 1)       // 0.1 → 0.5 is 0.4 mm
        XCTAssertEqual(quality.snag.count, 1)        // 3 → 11
        XCTAssertEqual(quality.overLimit.count, 1)   // 11 → 24
        XCTAssertEqual(quality.jumps, 1)
    }

    func testFindsNeedleHolePileUpsAndStiffPatches() {
        var plan = StitchPlan()
        // Ten stitches back and forth between the same two spots: two holes with five hits each, and 9 × 0.8 mm of
        // thread in one 1 mm square, which is 2.9 layers.
        plan.commands = (0..<10).map { stitch($0 % 2 == 0 ? 0.1 : 0.9, 0.5) }
        var quality = StitchQuality(plan: plan, design: Design())
        XCTAssertEqual(quality.holePileUps.count, 2)
        XCTAssertEqual(quality.worstHole, 5)
        XCTAssertEqual(quality.maxLayers, 9 * 0.8 / 2.5, accuracy: 0.01)
        XCTAssertEqual(quality.stiffCells.count, 0)
        plan.commands += (0..<20).map { stitch($0 % 2 == 0 ? 0.1 : 0.9, 0.5) }
        quality = StitchQuality(plan: plan, design: Design())
        XCTAssertEqual(quality.stiffCells.count, 1, "29 × 0.8 mm is about 9 layers")
    }

    /// The built-in samplers, a fill with a satin border and an appliqué sew no stitch under 0.3 mm, so never the
    /// same hole twice in a row either (before the clean-up, about 2–10% of their stitches were tiny).
    func testSamplesSewNoTinyOrRepeatedStitches() throws {
        // A small circle: satin borders around big shapes are slow to work out in test builds.
        let circle = try ShapeStitching.closedShape(ShapeGeometry.nodes(.ellipse, in: (Point(-6, -6), Point(6, 6))), fill: .tatami, outline: nil, name: "Circle", color: ink)[0]
        var bordered = Design(); bordered.objects = [circle, try SatinBorder.around(circle, width: 3, color: ink).object]
        var applique = Design(); applique.objects = try Applique.make(from: circle, coverWidth: 3, tackDown: .zigzag, color: ink).objects
        for (name, design) in [("sample", Design.sample()), ("sampler", Design.stitchSampler()), ("border", bordered), ("appliqué", applique)] {
            // Stitch lengths only (the full checker's thread maps are slow in test builds).
            var lengths: [Double] = [], previous: Point?
            for command in try StitchEngine.compile(design).commands {
                if command.op == .stitch { if let previous { lengths.append(previous.distance(to: command.point)) }; previous = command.point } else { previous = nil }
            }
            XCTAssertFalse(lengths.isEmpty, name)
            XCTAssertEqual(lengths.filter { $0 < StitchQuality.tinyLength }.count, 0, name)
        }
    }

    // MARK: - The report

    /// One design to measure, with a name for the report.
    private struct Sample { let name: String; let design: Design }
    private let ink = ThreadColor.palette[0]

    func testWriteQualityReport() throws {
        guard let path = ProcessInfo.processInfo.environment["QUALITY_REPORT"] else {
            throw XCTSkip("Set QUALITY_REPORT=<file> to write the stitch quality report.")
        }
        var rows: [(Sample, StitchQuality)] = [], failures: [String] = []
        for sample in try samples() {
            do { rows.append((sample, StitchQuality(plan: try StitchEngine.compile(sample.design), design: sample.design))) }
            catch { failures.append("\(sample.name): \(error.localizedDescription)") }
        }
        try report(rows, failures: failures).write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Everything the report measures.
    private func samples() throws -> [Sample] {
        var samples = [Sample(name: "Built-in sample", design: .sample()), Sample(name: "Built-in satin + fill sampler", design: .stitchSampler())]
        // The sample projects next to the built app, when this checkout has them.
        let dist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("dist")
        for project in ["Sample", "SVG-Logo-Sample", "Satin-Fill-Sampler"] {
            let file = dist.appendingPathComponent("\(project).stitchproj/design.json")
            if let data = try? Data(contentsOf: file) { samples.append(Sample(name: "Project: \(project)", design: try JSONDecoder().decode(Design.self, from: data))) }
        }
        // Every fill style on four shapes at three sizes.
        let sizes: [(String, Double)] = [("8 mm", 8), ("30 mm", 30), ("80 mm", 80)]
        for style in FillStyle.allCases {
            for (sizeName, size) in sizes {
                var design = Design(); design.hoop = Hoop(width: 200, height: 200)
                for (index, shape) in [BasicShape.ellipse, .rectangle, .star, .heart].enumerated() {
                    let x = (Double(index) - 1.5) * (size + 10)
                    let nodes = ShapeGeometry.nodes(shape, in: (Point(x - size / 2, -size / 2), Point(x + size / 2, size / 2)))
                    design.objects += try ShapeStitching.closedShape(nodes, fill: style, outline: nil, name: "\(style.title) fill \(shape.title) \(sizeName)", color: ink)
                }
                samples.append(Sample(name: "\(style.title) fill, \(sizeName) shapes", design: design))
            }
        }
        // Satin lines of several widths, bean stitch and running stitch along the same S-curve.
        let curve = [Point(-30, -10), Point(-10, 10), Point(10, -10), Point(30, 10)].map { PathNode($0, smooth: true) }
        var lines = Design()
        for (index, width) in [1.0, 2, 4, 6].enumerated() {
            let moved = curve.map { node -> PathNode in var node = node; node.transform { $0 + Point(0, Double(index) * 12 - 18) }; return node }
            lines.objects.append(try ShapeStitching.openShape(moved, stitch: .satin, satinWidth: width, name: "Satin line \(width.formatted()) mm", color: ink))
        }
        lines.objects.append(try ShapeStitching.openShape(curve.map { var n = $0; n.transform { $0 + Point(0, 32) }; return n }, stitch: .bean, satinWidth: 0, name: "Bean line", color: ink))
        lines.objects.append(try ShapeStitching.openShape(curve.map { var n = $0; n.transform { $0 + Point(0, -32) }; return n }, stitch: .running, satinWidth: 0, name: "Running line", color: ink))
        samples.append(Sample(name: "Satin, bean and running lines", design: lines))
        // A satin border and an appliqué around 40 mm circles.
        let circle = try ShapeStitching.closedShape(ShapeGeometry.nodes(.ellipse, in: (Point(-20, -20), Point(20, 20))), fill: .tatami, outline: nil, name: "Circle fill", color: ink)[0]
        var bordered = Design(); bordered.objects = [circle, try SatinBorder.around(circle, width: 3, color: ink).object]
        samples.append(Sample(name: "Fill with satin border", design: bordered))
        var applique = Design(); applique.objects = try Applique.make(from: circle, coverWidth: 3, tackDown: .zigzag, color: ink).objects
        samples.append(Sample(name: "Appliqué circle", design: applique))
        // Every embroidery font, at its smallest size and a third of the way up its range.
        for font in EmbroideryFont.all(in: EmbroideryFontTests.directory) {
            for (label, height) in [("smallest", font.heights.lowerBound), ("medium", font.heights.lowerBound + (font.heights.upperBound - font.heights.lowerBound) / 3)] {
                let result = try font.shapes(text: "Hag 5", height: height, color: ink)
                var design = Design(); design.objects = result.objects
                samples.append(Sample(name: "Font \(font.name), \(label) (\(height.formatted(.number.precision(.fractionLength(1)))) mm)", design: design))
            }
        }
        return samples
    }

    /// The report as Markdown: one row per design, then the objects behind each kind of problem.
    private func report(_ rows: [(Sample, StitchQuality)], failures: [String]) -> String {
        func cell(_ q: StitchQuality, _ tally: StitchQuality.Tally) -> String { tally.count == 0 ? "·" : "\(tally.count) (\(q.perThousand(tally).formatted(.number.precision(.fractionLength(1))))‰)" }
        var text = """
        # Stitch quality report

        Counts per design, with the rate per 1,000 stitches in brackets. Tiny: under \(StitchQuality.tinyLength) mm. \
        Short: \(StitchQuality.tinyLength)–\(StitchQuality.shortLength) mm. Repeat: a stitch on the same spot. \
        Snag: over \(StitchQuality.snagLength) mm. Too long: over \(StitchQuality.machineLimit) mm. \
        Holes: \(StitchQuality.holeCell) mm squares with \(StitchQuality.holePileUp)+ needle hits (worst square). \
        Stiff: 1 mm squares with more than \(StitchQuality.stiffLayers.formatted()) layers of thread (most layers anywhere).

        | Design | Stitches | Tiny | Short | Repeat | Snag | Too long | Holes (worst) | Stiff (max layers) | Jumps | Trims | Warnings |
        | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |

        """
        for (sample, q) in rows {
            let holes = q.holePileUps.count == 0 ? "· (\(q.worstHole))" : "\(q.holePileUps.count) (\(q.worstHole))"
            let stiff = "\(q.stiffCells.count == 0 ? "·" : String(q.stiffCells.count)) (\(q.maxLayers.formatted(.number.precision(.fractionLength(1)))))"
            text += "| \(sample.name) | \(q.stitches) | \(cell(q, q.tiny)) | \(cell(q, q.short)) | \(cell(q, q.zeroLength)) | \(cell(q, q.snag)) | \(cell(q, q.overLimit)) | \(holes) | \(stiff) | \(q.jumps) | \(q.trims) | \(q.warnings.count) |\n"
        }
        // Which objects cause each problem, worst first, across all designs.
        let kinds: [(String, (StitchQuality) -> StitchQuality.Tally)] = [("Tiny stitches", \.tiny), ("Short stitches", \.short), ("Repeated stitches", \.zeroLength),
                                                                          ("Snag-length stitches", \.snag), ("Too-long stitches", \.overLimit), ("Needle-hole pile-ups", \.holePileUps), ("Stiff patches", \.stiffCells)]
        for (title, tally) in kinds {
            var totals: [String: Int] = [:]
            for (sample, q) in rows { for (object, count) in tally(q).byObject { totals["\(sample.name) › \(object)", default: 0] += count } }
            guard !totals.isEmpty else { continue }
            text += "\n## \(title): worst objects\n\n"
            for (object, count) in totals.sorted(by: { $0.value > $1.value }).prefix(15) { text += "- \(count) · \(object)\n" }
        }
        let warned = rows.filter { !$0.1.warnings.isEmpty }
        if !warned.isEmpty {
            text += "\n## Engine warnings\n\n"
            for (sample, q) in warned { text += "- \(sample.name): \(Set(q.warnings).sorted().joined(separator: " / "))\n" }
        }
        if !failures.isEmpty { text += "\n## Designs that didn't compile\n\n" + failures.map { "- \($0)\n" }.joined() }
        return text
    }
}
