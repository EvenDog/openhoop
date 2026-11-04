// Paint Stitches (paint-by-numbers auto-digitizing): the traced parts start with auto-digitize's stitches, clicking
// with a brush changes one, and Add Stitches adds them all as one step you can undo.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class StitchPaintTests: XCTestCase {
    /// A traced picture shown 20 mm wide: a red disc 10 mm across on the left (tatami by its width) and a black bar
    /// 3 × 12 mm on the right (satin by its width), on white.
    private func trace() throws -> AutoDigitizeTrace {
        var bytes = [UInt8]()
        for y in 0..<100 { for x in 0..<100 {
            let color = hypot(Double(x) - 29.5, Double(y) - 49.5) < 25 ? 0xD02020 : x >= 65 && x < 80 && y >= 20 && y < 80 ? 0x000000 : 0xFFFFFF
            bytes += [UInt8(color >> 16 & 255), UInt8(color >> 8 & 255), UInt8(color & 255), 255]
        } }
        var options = AutoDigitizeOptions(); options.colors = 3
        return try AutoDigitize.trace(PixelImage(width: 100, height: 100, rgba: bytes), center: Point(0, 0), width: 20, height: 20, options: options)
    }

    @MainActor func testPaintingSetsStitchesThenAddsThemAsOneStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(); let state = document.state
        state.startStitchPaint(try trace())
        XCTAssertEqual(state.tool, .paintStitches)
        let disc = try XCTUnwrap(state.stitchPaint?.patch(at: Point(-4, 0))), bar = try XCTUnwrap(state.stitchPaint?.patch(at: Point(4.5, 0)))
        XCTAssertEqual(state.paintedStitch(disc), .tatami); XCTAssertEqual(state.paintedStitch(bar), .satin)

        state.paintBrush = .satin
        state.paintPatch(at: Point(-4, 0))
        XCTAssertEqual(state.paintedStitch(disc), .satin); XCTAssertEqual(state.paintChoices, [disc: .satin])
        state.paintPatch(at: Point(4.5, 0))
        XCTAssertEqual(state.paintChoices, [disc: .satin], "the bar already sews in satin, so nothing is set by hand")
        state.paintPatch(at: Point(9, 9))
        XCTAssertEqual(state.paintChoices.count, 1, "clicking the background paints nothing")
        state.paintBrush = .leaveOut
        state.paintPatch(at: Point(4.5, 0))
        XCTAssertEqual(state.paintedStitch(bar), .leaveOut)
        XCTAssertTrue(state.design.objects.isEmpty, "painting changes nothing in the design yet")

        state.applyStitchPaint()
        let deadline = Date().addingTimeInterval(20)
        while state.tool == .paintStitches && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(state.tool, .select)
        XCTAssertNil(state.stitchPaint, "done painting")
        XCTAssertEqual(state.design.objects.count, 1, "the bar is left out")
        XCTAssertEqual(state.design.objects[0].settings.fillStyle, .satin, "the disc, painted satin")
        XCTAssertEqual(state.selection, [state.design.objects[0].id])
        document.undoManager?.undo()
        XCTAssertTrue(state.design.objects.isEmpty, "one undo takes it all away")
        document.close()
    }

    @MainActor func testLeavingTheToolDropsThePainting() throws {
        _ = NSApplication.shared
        let document = DesignDocument(); let state = document.state
        state.startStitchPaint(try trace())
        state.paintPatch(at: Point(-4, 0))
        state.tool = .zoomBox
        XCTAssertNotNil(state.stitchPaint, "zooming in keeps the painting")
        state.tool = .paintStitches; state.tool = .select
        XCTAssertNil(state.stitchPaint); XCTAssertTrue(state.paintChoices.isEmpty)
        XCTAssertTrue(state.design.objects.isEmpty)
        document.close()
    }

    /// Fine-tune on Canvas: painting starts with the stitches picked per color in the Auto-Digitize window.
    @MainActor func testPaintingStartsWithTheColorsStitches() throws {
        _ = NSApplication.shared
        let document = DesignDocument(); let state = document.state
        let trace = try trace()
        let disc = try XCTUnwrap(trace.patch(at: Point(-4, 0)))
        state.startStitchPaint(trace, choices: trace.choices(byThread: [trace.patches[disc].thread: .line]))
        XCTAssertEqual(state.paintedStitch(disc), .line)
        XCTAssertEqual(state.paintStart, [disc: .line], "Reset goes back to these")
        document.close()
    }
}
