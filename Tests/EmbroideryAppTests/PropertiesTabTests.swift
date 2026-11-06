// Checks the Properties tabs: which tabs each kind of object has and what the first one is called, and that the tab
// last picked stays picked as other objects are selected, falling back to the first tab when an object hasn't got it.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class PropertiesTabTests: XCTestCase {
    private func object(_ kind: StitchKind, style: FillStyle? = nil) -> RunObject {
        var o = RunObject(name: "Shape", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0)), PathNode(Point(10, 10)), PathNode(Point(0, 10))])
        o.closed = kind == .fill
        o.digitizing = DigitizingSettings(kind: kind)
        o.digitizing?.fillStyle = style
        return o
    }

    func testEachKindHasItsTabs() {
        XCTAssertEqual(PropertiesTab.tabs(for: object(.fill)), [.stitch, .underlay, .finish, .object])
        XCTAssertEqual(PropertiesTab.tabs(for: object(.satin)), [.stitch, .underlay, .finish, .object])
        XCTAssertEqual(PropertiesTab.tabs(for: object(.run)), [.stitch, .finish, .object], "lines have no underlay")
        XCTAssertEqual(PropertiesTab.tabs(for: object(.fill, style: .stipple)), [.stitch, .finish, .object], "stipple sews without underlay")
        XCTAssertEqual(PropertiesTab.tabs(for: object(.vector)), [.stitch, .object], "unstitched outlines don't finish")
        XCTAssertEqual(PropertiesTab.stitch.title(for: object(.fill)), "Fill")
        XCTAssertEqual(PropertiesTab.stitch.title(for: object(.satin)), "Satin")
        XCTAssertEqual(PropertiesTab.stitch.title(for: object(.run)), "Line")
    }

    @MainActor func testThePickedTabStaysPicked() {
        let state = EditorState()
        let fill = object(.fill), line = object(.run)
        state.propertiesTab = .underlay
        XCTAssertEqual(state.shownTab(for: fill), .underlay)
        XCTAssertEqual(state.shownTab(for: line), .stitch, "a line has no Underlay tab: its first tab shows")
        XCTAssertEqual(state.propertiesTab, .underlay, "and Underlay is still picked for the next fill")
        state.propertiesTab = .finish
        XCTAssertEqual(state.shownTab(for: line), .finish)
    }

    /// The Focus commands find their field by its identifier, so a fill's Row spacing, Stitch length and Angle must
    /// be built in the window, now that they sit in a two-across grid.
    @MainActor func testFocusCommandsCanFindTheFillsNumbers() throws {
        _ = NSApplication.shared
        let document = DesignDocument()
        var fill = object(.fill)
        fill.digitizing?.spacing = 0.4
        document.state.design.objects = [fill]
        document.makeWindowControllers()
        defer { document.close() }
        let window = try XCTUnwrap(EditorWindowController.host(of: document)?.window)
        window.setFrame(NSRect(x: 0, y: 0, width: 1400, height: 1000), display: true)
        document.state.selection = [fill.id]
        document.state.propertiesTab = .stitch
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
        }
        let root = try XCTUnwrap(window.contentView)
        for identifier in ["rowSpacing", "stitchLength", "fillAngle"] {
            XCTAssertNotNil(find(identifier, in: root), "the \(identifier) field is in the window")
        }
    }
}
