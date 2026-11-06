// Checks the underlay views: "only underlay" draws an object's underlay without the stitching on top, for every object
// or just the selected ones, and only shown or hidden is remembered for the next launch.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class UnderlayOnlyTests: XCTestCase {
    @MainActor func testOnlyUnderlayLeavesOutTheTopStitchingOfTheChosenObjects() throws {
        _ = NSApplication.shared
        /// A 24 mm square fill centered at x = `x`, with an edge run and tatami underlay.
        func square(_ name: String, x: Double, hex: Int) -> RunObject {
            var fill = RunObject(name: name, nodes: [Point(x - 12, -12), Point(x + 12, -12), Point(x + 12, 12), Point(x - 12, 12)].map { PathNode($0) }, color: ThreadColor(name, hex))
            fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
            fill.digitizing?.underlay = .edge; fill.digitizing?.secondUnderlay = .tatami
            return fill
        }
        let red = square("Red", x: -15, hex: 0xFF0000), green = square("Green", x: 15, hex: 0x00C000)
        let document = DesignDocument(), state = document.state
        state.design.objects = [red, green]
        document.makeWindowControllers()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.setFrame(NSRect(x: 0, y: 0, width: 1100, height: 800), display: true)
        let deadline = Date().addingTimeInterval(10)
        while state.plan.stitchCount == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        state.needles = false
        Preferences.shared.data.threadView = true   // the thread's own color, with no selection highlight
        let canvas = try XCTUnwrap(state.canvas)

        /// How much of the middle 12 × 12 mm of the square centered at x = `x` is covered by thread of `hue` (0 to 1).
        func coverage(x: Double, red wantRed: Bool) throws -> Double {
            canvas.needsDisplay = true; canvas.display()
            let rep = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            let scale = Double(rep.pixelsWide) / canvas.bounds.width
            let low = canvas.screen(Point(x - 6, -6)), high = canvas.screen(Point(x + 6, 6))
            var hits = 0, all = 0
            for y in stride(from: low.y, to: high.y, by: 1) { for px in stride(from: low.x, to: high.x, by: 1) {
                guard let c = rep.colorAt(x: Int(px * scale), y: Int((canvas.bounds.height - y) * scale))?.usingColorSpace(.sRGB) else { continue }
                all += 1
                let thread = wantRed ? c.redComponent > c.greenComponent + 0.25 : c.greenComponent > c.redComponent + 0.25
                if thread { hits += 1 }
            } }
            return Double(hits) / Double(max(all, 1))
        }

        state.underlayView = .shown
        let full = (red: try coverage(x: -15, red: true), green: try coverage(x: 15, red: false))
        XCTAssertGreaterThan(full.red, 0.6, "shown: the fill covers its square")

        state.underlayView = .onlyAll
        let onlyAll = (red: try coverage(x: -15, red: true), green: try coverage(x: 15, red: false))
        XCTAssertLessThan(onlyAll.red, full.red * 0.6, "only underlay: the open underlay rows, not the whole fill")
        XCTAssertGreaterThan(onlyAll.red, 0.02, "but the underlay itself shows")
        XCTAssertLessThan(onlyAll.green, full.green * 0.6, "for every object")

        state.underlayView = .onlySelected; state.selection = [red.id]
        XCTAssertEqual(try coverage(x: -15, red: true), onlyAll.red, accuracy: 0.02, "the selected one shows only its underlay")
        XCTAssertEqual(try coverage(x: 15, red: false), full.green, accuracy: 0.02, "the others stay as they are")

        state.underlayView = .hidden
        XCTAssertGreaterThan(try coverage(x: -15, red: true), 0.6, "hidden: the top stitching alone still covers it")
    }

    @MainActor func testOnlyShownOrHiddenIsRemembered() {
        let state = DesignDocument().state
        state.underlayView = .hidden
        XCTAssertEqual(Preferences.shared.shown.underlay, false)
        state.underlayView = .onlyAll
        XCTAssertEqual(Preferences.shared.shown.underlay, false, "an underlay-only view isn't saved")
        XCTAssertTrue(state.showUnderlay, "but the Show Underlay button looks on")
        state.underlayView = .shown
        XCTAssertEqual(Preferences.shared.shown.underlay, true)
    }

    func testTheFilterPicksStitchesByViewAndSelection() {
        let picked = UUID(), other = UUID()
        func stitch(_ object: UUID, underlay: Bool) -> StitchCommand { var c = StitchCommand(.stitch, Point(0, 0), thread: 0, objectID: object); c.underlay = underlay; return c }
        let selected = UnderlayFilter(view: .onlySelected, selection: [picked])
        XCTAssertTrue(selected.shows(stitch(picked, underlay: true))); XCTAssertFalse(selected.shows(stitch(picked, underlay: false)))
        XCTAssertTrue(selected.shows(stitch(other, underlay: true))); XCTAssertTrue(selected.shows(stitch(other, underlay: false)))
        XCTAssertTrue(selected.showsAlone(stitch(picked, underlay: true))); XCTAssertFalse(selected.showsAlone(stitch(other, underlay: true)), "others' underlay stays faint")
        XCTAssertFalse(UnderlayFilter(view: .hidden).shows(stitch(other, underlay: true)))
        XCTAssertFalse(UnderlayFilter(view: .onlyAll).shows(stitch(other, underlay: false)))
        XCTAssertTrue(UnderlayFilter.all.shows(stitch(other, underlay: true)))
    }
}
