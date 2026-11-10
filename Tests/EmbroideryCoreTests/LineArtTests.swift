// Checks the ready-made line art: every drawing becomes grouped running lines of the chosen size, in the chosen
// thread and stitch; touching strokes are joined into one continuous line that leaves nothing out; and the curve
// nodes follow the drawing closely, with stitches at a normal length.
import XCTest
@testable import EmbroideryCore

final class LineArtTests: XCTestCase {
    func testEveryDrawingIsGroupedLinesOfTheChosenSizeAndStitch() throws {
        let color = ThreadColor("Red", 0xC0392B)
        for design in LineArtDesign.allCases {
            let lines = LineArt.objects(design, size: 60, bean: false, color: color)
            XCTAssertFalse(lines.isEmpty, design.title)
            XCTAssertEqual(Set(lines.map(\.groupID)).count, 1, "\(design.title): one group")
            XCTAssertNotNil(lines[0].groupID)
            XCTAssertTrue(lines.allSatisfy { $0.kind == .run && $0.color == color && ($0.settings.runPasses ?? 1) == 1 }, design.title)
            let points = lines.flatMap { $0.outlinePaths.flatMap { $0 } }
            XCTAssertEqual(points.map(\.x).max()! - points.map(\.x).min()!, 60, accuracy: 0.6, "\(design.title) is 60 mm wide")
            XCTAssertEqual(points.map(\.x).max()! + points.map(\.x).min()!, 0, accuracy: 0.6, "\(design.title) is centered across")
            XCTAssertEqual(points.map(\.y).max()! + points.map(\.y).min()!, 0, accuracy: 0.6, "\(design.title) is centered up and down")
            var plan = Design(); plan.objects = lines
            XCTAssertNoThrow(try plan.validate(), design.title)
            XCTAssertGreaterThan(try RunningEngine.compile(plan).stitchCount, 30, design.title)
            // Twice the size is twice as wide; bean stitch sews each line three times, but where it goes back over
            // itself only once.
            let big = LineArt.objects(design, size: 120, bean: true, color: color)
            func width(_ objects: [RunObject]) -> Double { let xs = objects.flatMap { $0.outlinePaths.flatMap { $0 } }.map(\.x); return xs.max()! - xs.min()! }
            XCTAssertEqual(width(big), 2 * width(lines), accuracy: 0.5, design.title)
            XCTAssertTrue(big.allSatisfy { $0.settings.runPasses == 3 && $0.settings.retraceOnce == true }, design.title)
        }
    }

    /// Bean line art sews the stretches it goes back over once, not three times: never more stitches than plain
    /// bean, and fewer for drawings whose joins go back over a line.
    func testBeanSewsRetracedStretchesOnce() throws {
        var fewer = 0
        for design in LineArtDesign.allCases {
            var once = Design(); once.objects = LineArt.objects(design, size: 60, bean: true, color: .palette[0])
            XCTAssertNoThrow(try once.validate(), design.title)
            var thrice = once; for i in thrice.objects.indices { thrice.objects[i].digitizing?.retraceOnce = nil }
            let onceCount = try RunningEngine.compile(once).stitchCount, thriceCount = try RunningEngine.compile(thrice).stitchCount
            XCTAssertLessThanOrEqual(onceCount, thriceCount, design.title)
            if onceCount < thriceCount { fewer += 1 }
        }
        XCTAssertGreaterThan(fewer, 0, "some drawings go back over a line, and those stretches are sewn once")
    }

    /// Touching strokes join into one line: most drawings sew in one go; only parts that float free (the butterfly's
    /// spots, the sun's face, the heart in the cup, the rosette's middle ring) are separate.
    func testTouchingStrokesJoinIntoOneLine() {
        let expected: [LineArtDesign: Int] = [.butterfly: 5, .sun: 4, .teacup: 2, .rosette: 2]
        for design in LineArtDesign.allCases {
            XCTAssertEqual(LineArt.objects(design, size: 60, bean: false, color: .palette[0]).count, expected[design] ?? 1, design.title)
        }
    }

    /// Joining leaves nothing out: every point of every stroke is on one of the joined lines.
    func testJoiningKeepsEveryStroke() {
        for design in LineArtDesign.allCases {
            let joined = LineArt.joined(LineArt.strokes(design))
            let pieces = joined.flatMap { line in zip(line, line.dropFirst()).map { ($0, $1) } }
            for stroke in LineArt.strokes(design) {
                for p in stroke {
                    let gap = pieces.map { AreaGeometry.projection(p, $0.0, $0.1).distance(to: p) }.min() ?? .infinity
                    XCTAssertLessThan(gap, 0.7, "\(design.title): \(p) is sewn")
                }
            }
        }
    }

    /// The curve nodes follow the drawing (within 0.6 mm at 60 mm wide), with far fewer nodes than points, and the
    /// stitches come out near the stitch length: few are under 1 mm (the tie-in and tie-off are, and tight curls).
    func testNodesFollowTheDrawingWithNormalStitches() throws {
        for design in LineArtDesign.allCases {
            let lines = LineArt.objects(design, size: 60, bean: false, color: .palette[0])
            // The drawing put the same way LineArt.objects puts it: 60 mm wide, centered on its middle.
            let all = LineArt.strokes(design).flatMap { $0 }
            let left = all.map(\.x).min()!, right = all.map(\.x).max()!, top = all.map(\.y).min()!, bottom = all.map(\.y).max()!
            let scale = 60 / (right - left), middle = Point((left + right) / 2, (top + bottom) / 2)
            let drawn = LineArt.strokes(design).map { $0.map { Point(($0.x - middle.x) * scale, (middle.y - $0.y) * scale) } }.flatMap { zip($0, $0.dropFirst()).map { ($0, $1) } }
            let curves = lines.flatMap { RunningEngine.flatten($0.nodes, closed: $0.closed).flatMap { $0 } }
            for p in curves {
                let gap = drawn.map { AreaGeometry.projection(p, $0.0, $0.1).distance(to: p) }.min()!
                XCTAssertLessThan(gap, 0.6, "\(design.title): the curve stays on the drawing")
            }
            var plan = Design(); plan.objects = lines
            let commands = try RunningEngine.compile(plan).commands
            // Only stitch to stitch: a jump to the next separate line isn't a stitch.
            let lengths = zip(commands, commands.dropFirst()).filter { $0.op == .stitch && $1.op == .stitch }.map { $0.point.distance(to: $1.point) }.filter { $0 > 0 }
            XCTAssertLessThanOrEqual(lengths.max() ?? 0, 2.0 + 1e-6, "\(design.title): no stitch over 2 mm")
            // (Tight curls, like the oval frame's, take shorter stitches to keep their shape.)
            XCTAssertLessThan(Double(lengths.filter { $0 < 1 }.count) / Double(lengths.count), 0.3, "\(design.title): mostly normal stitches")
        }
    }
}
