// Checks what the Measure tool reads out: the distance in mm and the angle, counted counterclockwise from pointing right.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class MeasureTests: XCTestCase {
    func testMeasurementReadsDistanceAndAngle() {
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(0, 0), to: Point(3, 4)), "5.0 mm · 53°")
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(10, 10), to: Point(10, 22.5)), "12.5 mm · 90°")
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(0, 0), to: Point(-8, 0)), "8.0 mm · 180°")
        XCTAssertEqual(DesignCanvas.measurementText(from: Point(0, 0), to: Point(5, -5)), "7.1 mm · -45°")
    }

    @MainActor func testTheMeasurementGoesWhenTheToolChanges() {
        _ = NSApplication.shared
        let canvas = DesignCanvas(state: EditorState())
        canvas.state.tool = .measure; canvas.measurement = (Point(0, 0), Point(3, 4))
        canvas.state.tool = .select; canvas.state.tool = .measure
        XCTAssertNil(canvas.measurement, "pressing M again starts afresh, without the last line")
    }
}
