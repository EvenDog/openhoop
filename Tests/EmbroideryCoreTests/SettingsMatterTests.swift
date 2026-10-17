// Checks that the settings Properties offers really change the stitches, and the ones it hides really don't: stitch
// length for each fill and line style, underlay spacing for each fill and satin underlay, and a fill's angle.
// (Properties shows Stitch length only where `usesStitchLength`, Underlay spacing only where `usesUnderlaySpacing`,
// and the angle as Fill angle where the rows follow it or Underlay angle where only the underlay does.)
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
    private func fill(_ style: FillStyle, underlay: UnderlayStyle = .edgeAndSparse) -> RunObject {
        var object = RunObject(name: "Fill", nodes: blob.map { PathNode($0) }); object.closed = true
        object.digitizing = DigitizingSettings(kind: .fill); object.digitizing?.fillStyle = style; object.digitizing?.underlay = underlay
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
            for underlay in [UnderlayStyle.none, .edge, .edgeAndSparse] {
                var objects = [fill(style, underlay: underlay)]
                if style == .tatami { var lined = objects[0]; lined.digitizing?.angleLines = [[Point(-5, -15), Point(-5, 15)], [Point(8, -15), Point(10, 15)]]; objects.append(lined) }
                for object in objects {
                    let shown = StitchAngleLine.applies(to: object) || StitchAngleLine.steersOnlyUnderlay(object)
                    XCTAssertFalse(StitchAngleLine.applies(to: object) && StitchAngleLine.steersOnlyUnderlay(object), "shown once, as one or the other")
                    XCTAssertEqual(try matters(object) { $0.digitizing?.angle = 35 }, shown, "\(style) fill, \(underlay) underlay\(object.settings.angleLines == nil ? "" : ", angle lines")")
                }
            }
        }
    }

    func testUnderlaySpacingIsOfferedWhereItMatters() throws {
        for underlay in [UnderlayStyle.edge, .edgeAndSparse] {
            let object = fill(.tatami, underlay: underlay)
            XCTAssertEqual(try matters(object) { $0.digitizing?.underlaySpacing = 3.5 }, object.settings.usesUnderlaySpacing(.fill), "fill \(underlay)")
        }
        let rungs = stride(from: 0.0, through: 30, by: 3).flatMap { x -> [PathNode] in let y = 3 * sin(x / 10); return [PathNode(Point(x, y)), PathNode(Point(x, y + 5))] }
        for underlay in [UnderlayStyle.auto, .center, .edge, .zigzag] {
            for second in [nil, UnderlayStyle.center, .edge, .zigzag] where underlay != .auto || second == nil {
                guard second != underlay else { continue }
                var satin = RunObject(name: "Satin", nodes: rungs); satin.digitizing = DigitizingSettings(kind: .satin)
                satin.digitizing?.underlay = underlay; satin.digitizing?.secondUnderlay = second
                XCTAssertEqual(try matters(satin) { $0.digitizing?.underlaySpacing = 3.5 }, satin.settings.usesUnderlaySpacing(.satin), "satin \(underlay) + \(second.map { "\($0)" } ?? "nothing")")
            }
        }
    }
}
