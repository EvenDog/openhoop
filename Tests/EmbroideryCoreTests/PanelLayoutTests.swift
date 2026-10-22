// Panel arrangement: docking, tabbing, floating, hiding and showing panels.
import XCTest
@testable import EmbroideryCore

final class PanelLayoutTests: XCTestCase {
    /// A two-dock arrangement for the moves below: sewing order and threads on the left; properties, design and
    /// reference image (as tabs) on the right.
    private static let twoDocks = PanelLayout(left: [PanelGroup([.sewingOrder]), PanelGroup([.threads])],
                                              right: [PanelGroup([.properties]), PanelGroup([.design, .reference])])
    private var layout = twoDocks

    func testStandardLayoutShowsEveryPanelOnce() {
        let standard = PanelLayout.standard
        let all = (standard.left + standard.right).flatMap(\.panels)
        XCTAssertEqual(Set(all), Set(PanelID.allCases)); XCTAssertEqual(all.count, PanelID.allCases.count)
        XCTAssertEqual(standard, standard.normalized(), "The standard layout needs no repair")
    }

    func testPanelsReturnToTheirHome() {
        // The design panel's home is a tab beside the sewing order on the left.
        var standard = PanelLayout.standard
        standard.hide(.design); standard.hide(.properties)
        XCTAssertEqual(standard.left.map(\.panels), [[.sewingOrder, .reference], [.threads]])
        standard.show(.design)
        XCTAssertEqual(standard.left.map(\.panels), [[.sewingOrder, .reference, .design], [.threads]])
        standard.show(.properties)
        XCTAssertEqual(standard.right.map(\.panels), [[.properties]])
    }

    func testDockingAsTabAndAsNewGroup() {
        // Threads joins the sewing order group as a tab, leaving the left dock with one group.
        layout.move(.threads, to: .tab(.left, group: 0))
        XCTAssertEqual(layout.left, [PanelGroup([.sewingOrder, .threads], selected: .threads)])
        // Properties moves to the top of the left dock as its own group; the right dock closes up.
        layout.move(.properties, to: .newGroup(.left, at: 0))
        XCTAssertEqual(layout.left.map(\.panels), [[.properties], [.sewingOrder, .threads]])
        XCTAssertEqual(layout.right.map(\.panels), [[.design, .reference]])
        // Moving a tab out of a group leaves the rest with a valid selection.
        layout.move(.reference, to: .newGroup(.right, at: 1))
        XCTAssertEqual(layout.right.map(\.panels), [[.design], [.reference]])
        XCTAssertEqual(layout.right[0].selected, .design)
    }

    func testMovingWithinTheSameDock() {
        // Threads (second on the left) moves above the sewing order (first): positions are "before the move".
        layout.move(.threads, to: .newGroup(.left, at: 0))
        XCTAssertEqual(layout.left.map(\.panels), [[.threads], [.sewingOrder]])
        // Dropping a lone panel just below itself changes nothing.
        let before = layout
        layout.move(.threads, to: .newGroup(.left, at: 1))
        XCTAssertEqual(layout, before)
        // Dropping a panel onto its own group's tabs just selects it.
        layout.move(.reference, to: .tab(.right, group: 1))
        XCTAssertEqual(layout.right[1], PanelGroup([.design, .reference], selected: .reference))
    }

    func testFloatingAndBack() {
        layout.move(.properties, to: .float(x: 300, y: 200, width: 280, height: 160))
        XCTAssertEqual(layout.floating, [FloatingGroup(group: PanelGroup([.properties]), x: 300, y: 200, width: 280, height: 160)])
        XCTAssertFalse(layout.right.contains { $0.panels.contains(.properties) })
        layout.move(.threads, to: .floatingTab(0))
        XCTAssertEqual(layout.floating[0].group, PanelGroup([.properties, .threads], selected: .threads))
        XCTAssertEqual(layout.left.map(\.panels), [[.sewingOrder]])
        // Docking both back removes the floating window.
        layout.move(.properties, to: .newGroup(.left, at: 1)); layout.move(.threads, to: .tab(.left, group: 1))
        XCTAssertTrue(layout.floating.isEmpty)
        XCTAssertEqual(layout.left.map(\.panels), [[.sewingOrder], [.properties, .threads]])
    }

    func testHideAndShowReturnPanelsToTheirHome() {
        layout.hide(.reference); layout.hide(.properties)
        XCTAssertFalse(layout.isVisible(.reference)); XCTAssertEqual(layout.right.map(\.panels), [[.design]])
        layout.show(.reference, home: Self.twoDocks)   // its neighbor there (design) is showing, so it becomes a tab there
        XCTAssertEqual(layout.right.map(\.panels), [[.design, .reference]])
        layout.show(.properties, home: Self.twoDocks)  // no neighbors: a new group at the bottom of its dock
        XCTAssertEqual(layout.right.last?.panels, [.properties])
        layout.hide(.sewingOrder); layout.hide(.threads)
        XCTAssertTrue(layout.left.isEmpty, "An empty dock is allowed (the app hides it)")
    }

    func testRepairingASavedLayout() throws {
        let broken = PanelLayout(left: [PanelGroup([.threads, .threads, .design], selected: .properties), PanelGroup([.design])], right: [], floating: [])
        let fixed = broken.normalized()
        XCTAssertEqual(fixed.left, [PanelGroup([.threads, .design])])
        let data = try JSONEncoder().encode(PanelLayout.standard)
        XCTAssertEqual(try JSONDecoder().decode(PanelLayout.self, from: data), .standard)
    }

    func testASavedStitchPlayerPanelIsLeftOut() throws {
        // Layouts saved before the stitch player moved to the title bar still list its panel. Loading leaves it out,
        // and groups that held only the player disappear, docked or floating.
        let saved = #"{"left":[{"panels":["sewingOrder"],"selected":"sewingOrder"}],"right":[{"panels":["properties"],"selected":"properties"},{"panels":["player"],"selected":"player","height":165},{"panels":["player","design"],"selected":"player"}],"floating":[{"group":{"panels":["player"],"selected":"player"},"x":0,"y":0,"width":200,"height":160}],"leftWidth":230,"rightWidth":280}"#
        let layout = try JSONDecoder().decode(PanelLayout.self, from: Data(saved.utf8)).normalized()
        XCTAssertEqual(layout.right, [PanelGroup([.properties]), PanelGroup([.design])])
        XCTAssertEqual(layout.left, [PanelGroup([.sewingOrder])])
        XCTAssertTrue(layout.floating.isEmpty)
    }
}
