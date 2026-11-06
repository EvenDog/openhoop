// Checks the Properties tabs: which tabs each kind of object has and what the first one is called, and that the tab
// last picked stays picked as other objects are selected, falling back to the first tab when an object hasn't got it.
import XCTest
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
}
