// Checks that the settings Properties offers really change the stitches, and the ones it hides really don't: stitch
// length for each fill and line style, each underlay layer's inset, spacing, length and angle, and a fill's angle.
// (Properties shows Stitch length only where `usesStitchLength`, an underlay layer's numbers only where its type
// `usesInset`, `usesSpacing`, `usesLength` or `usesAngle`, and the fill's angle where the rows follow it.)
import XCTest
@testable import EmbroideryCore

final class SettingsMatterTests: XCTestCase {
    private func sewn(_ object: RunObject) throws -> [Point] { var design = Design(); design.objects = [object]; return try StitchEngine.compile(design).commands.map(\.point) }
    /// True when `change` changes `object`'s stitches.
    private func matters(_ object: RunObject, _ change: (inout RunObject) -> Void) throws -> Bool {
        var changed = object; change(&changed)
        return try sewn(object) != sewn(changed)
    }
    private let blob: [Point] = (0..<40).map { i in let t = Double(i) / 40 * 2 * .pi; return Point(14 * cos(t), 10 * sin(t) + 2 * sin(3 * t)) }
    private func fill(_ style: FillStyle, underlay: UnderlayStyle = .edge, second: UnderlayStyle? = .tatami) -> RunObject {
        var object = RunObject(name: "Fill", nodes: blob.map { PathNode($0) }); object.closed = true
        object.digitizing = DigitizingSettings(kind: .fill); object.digitizing?.fillStyle = style; object.digitizing?.underlay = underlay
        object.digitizing?.secondUnderlay = underlay == .none ? nil : second
        if style == .guided { object.digitizing?.guideLine = [Point(-20, -3), Point(0, 5), Point(20, -2)] }
        return object
    }

    func testStitchLengthIsOfferedWhereItMatters() throws {
        for style in FillStyle.allCases {
            // A short length, under a fifth of a motif's size, so motif stitches feel it too.
            XCTAssertEqual(try matters(fill(style)) { $0.stitchLength = 0.8 }, style.usesStitchLength, "\(style) fill")
        }
        for style in RunStyle.allCases {
            var line = RunObject(name: "Line", nodes: stride(from: 0.0, through: 40, by: 8).map { PathNode(Point($0, 5 * sin($0 / 7))) })
            line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.runStyle = style
            XCTAssertEqual(try matters(line) { $0.stitchLength = 0.8 }, style.usesStitchLength, "\(style) line")
        }
    }

    func testTheAngleIsOfferedWhereItMatters() throws {
        for style in FillStyle.allCases {
            for (underlay, second) in [(UnderlayStyle.none, nil), (.edge, nil), (.edge, UnderlayStyle.tatami), (.tatami, nil)] {
                var objects = [fill(style, underlay: underlay, second: second)]
                if style == .tatami { var lined = objects[0]; lined.digitizing?.angleLines = [[Point(-5, -15), Point(-5, 15)], [Point(8, -15), Point(10, 15)]]; objects.append(lined) }
                for object in objects {
                    let shown = StitchAngleLine.applies(to: object) || StitchAngleLine.steersOnlyUnderlay(object)
                    XCTAssertFalse(StitchAngleLine.applies(to: object) && StitchAngleLine.steersOnlyUnderlay(object), "shown once, as one or the other")
                    XCTAssertEqual(try matters(object) { $0.digitizing?.angle = 35 }, shown, "\(style) fill, \(underlay) + \(second.map { "\($0)" } ?? "nothing") underlay\(object.settings.angleLines == nil ? "" : ", angle lines")")
                }
            }
        }
    }

    /// Checks each of `object`'s underlay layers: its inset, spacing, length and angle change the stitches exactly
    /// when its type shows them.
    private func checkUnderlayNumbers(_ object: RunObject, _ label: String) throws {
        for number in [1, 2] {
            guard let style = object.settings.underlayLayer(number)?.style else { continue }
            XCTAssertEqual(try matters(object) { $0.digitizing?.setUnderlay(number, inset: 1) }, style.usesInset, "\(label): Underlay \(number) inset")
            XCTAssertEqual(try matters(object) { $0.digitizing?.setUnderlay(number, spacing: 3.5) }, style.usesSpacing, "\(label): Underlay \(number) spacing")
            XCTAssertEqual(try matters(object) { $0.digitizing?.setUnderlay(number, length: 1) }, style.usesLength, "\(label): Underlay \(number) length")
            XCTAssertEqual(try matters(object) { $0.digitizing?.setUnderlay(number, angle: 30) }, style.usesAngle, "\(label): Underlay \(number) angle")
        }
    }

    func testUnderlayNumbersAreOfferedWhereTheyMatter() throws {
        for (underlay, second) in [(UnderlayStyle.edge, nil), (.edge, UnderlayStyle.tatami), (.tatami, nil), (.tatami, .edge)] {
            try checkUnderlayNumbers(fill(.tatami, underlay: underlay, second: second), "fill \(underlay) + \(second.map { "\($0)" } ?? "nothing")")
        }
        let rungs = stride(from: 0.0, through: 30, by: 3).flatMap { x -> [PathNode] in let y = 3 * sin(x / 10); return [PathNode(Point(x, y)), PathNode(Point(x, y + 5))] }
        for underlay in [UnderlayStyle.auto, .center, .edge, .zigzag] {
            for second in [nil, UnderlayStyle.center, .edge, .zigzag] where underlay != .auto || second == nil {
                guard second != underlay else { continue }
                var satin = RunObject(name: "Satin", nodes: rungs); satin.digitizing = DigitizingSettings(kind: .satin)
                satin.digitizing?.underlay = underlay; satin.digitizing?.secondUnderlay = second
                // A center run's length starts at the spacing it always sewed with; the spacing row is hidden, so
                // it's given a length of its own first, as changing Length in Properties does.
                for number in [1, 2] where satin.settings.underlayLayer(number)?.style == .center { satin.digitizing?.setUnderlay(number, length: 1.5) }
                try checkUnderlayNumbers(satin, "satin \(underlay) + \(second.map { "\($0)" } ?? "nothing")")
            }
        }
    }
}
