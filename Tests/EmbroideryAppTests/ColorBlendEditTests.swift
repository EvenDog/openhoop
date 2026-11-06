// Checks that editing a color blend in the app keeps its two layers in step: every edit goes through the document,
// which brings the layers back to one shape and opposite angles (Design.syncBlends).
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ColorBlendEditTests: XCTestCase {
    @MainActor func testTypingOneAngleForBothLayersKeepsTheBlend() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var square = RunObject(name: "Square", nodes: [Point(-15, -15), Point(15, -15), Point(15, 15), Point(-15, 15)].map { PathNode($0) }, color: ThreadColor.palette[0])
        square.closed = true; square.digitizing = DigitizingSettings(kind: .fill)
        state.design.objects = ColorBlend.layers(of: square, second: ThreadColor.palette[1], direction: 0)
        state.selection = Set(state.design.objects.map(\.id))

        // What Properties does when an angle is typed with both layers selected.
        state.editSelected("Fill Angle") { $0.digitizing?.angle = 30 }
        XCTAssertEqual(state.design.objects[0].settings.angle, 30)
        XCTAssertEqual(state.design.objects[1].settings.angle, -150, "The second layer turned back to face the first")
        XCTAssertEqual(state.design.schemaVersion, 19, "a new blend's rows are spaced across two rows, which needs file version 19")

        // Reshaping the layer on top reshapes the one under it.
        state.selection = [state.design.objects[1].id]
        state.editSelected("Move Node") { $0.nodes[2].point = Point(25, 20) }
        XCTAssertEqual(state.design.objects[0].nodes, state.design.objects[1].nodes)

        document.undoManager?.undo()
        XCTAssertEqual(state.design.objects[0].nodes[2].point, Point(15, 15), "Undo puts both back")
        XCTAssertEqual(state.design.objects[1].nodes[2].point, Point(15, 15))
    }

    /// Drawing on the preview: screen y runs down, so dragging up is 90° (bottom to top).
    func testDrawnDirection() {
        let o = CGPoint(x: 100, y: 100)
        XCTAssertEqual(ColorBlendView.drawnDirection(from: o, to: CGPoint(x: 160, y: 100), step: 1), 0)
        XCTAssertEqual(ColorBlendView.drawnDirection(from: o, to: CGPoint(x: 100, y: 40), step: 1), 90)
        XCTAssertEqual(ColorBlendView.drawnDirection(from: o, to: CGPoint(x: 40, y: 160), step: 1), 225)
        XCTAssertEqual(ColorBlendView.drawnDirection(from: o, to: CGPoint(x: 160, y: 75), step: 1), 23, "Whole degrees")
        XCTAssertEqual(ColorBlendView.drawnDirection(from: o, to: CGPoint(x: 160, y: 75), step: 15), 30, "15° steps with Shift")
        XCTAssertNil(ColorBlendView.drawnDirection(from: o, to: CGPoint(x: 103, y: 102), step: 1), "A click isn't a line")
    }
}
