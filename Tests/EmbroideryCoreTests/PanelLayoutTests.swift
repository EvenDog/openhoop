// Panel arrangement: docking, tabbing, floating, hiding and showing panels.
import XCTest
@testable import EmbroideryCore

final class PanelLayoutTests: XCTestCase {
    private var layout = PanelLayout.standard

    func testStandardLayoutShowsEveryPanelOnce() {
        for standard in [PanelLayout.standard, .pro] {
            let all = (standard.left + standard.right).flatMap(\.panels)
            XCTAssertEqual(Set(all), Set(PanelID.allCases)); XCTAssertEqual(all.count, PanelID.allCases.count)
            XCTAssertEqual(standard, standard.normalized(), "The standard layouts need no repair")
        }
    }

    func testPanelsReturnToTheirProHome() {
        // In the Pro view, the design panel's home is a tab beside the sewing order on the left.
        var pro = PanelLayout.pro
        pro.hide(.design); pro.hide(.player)
        XCTAssertEqual(pro.left.map(\.panels), [[.sewingOrder, .reference], [.threads]])
        pro.show(.design, home: .pro)
        XCTAssertEqual(pro.left.map(\.panels), [[.sewingOrder, .reference, .design], [.threads]])
        pro.show(.player, home: .pro)
        XCTAssertEqual(pro.right.map(\.panels), [[.properties], [.player]])
    }

    func testDockingAsTabAndAsNewGroup() {
        // Threads joins the sewing order group as a tab, leaving the left dock with one group.
        layout.move(.threads, to: .tab(.left, group: 0))
        XCTAssertEqual(layout.left, [PanelGroup([.sewingOrder, .threads], selected: .threads)])
        // Properties moves to the top of the left dock as its own group; the right dock closes up.
        layout.move(.properties, to: .newGroup(.left, at: 0))
        XCTAssertEqual(layout.left.map(\.panels), [[.properties], [.sewingOrder, .threads]])
        XCTAssertEqual(layout.right.map(\.panels), [[.design, .reference], [.player]])
        // Moving a tab out of a group leaves the rest with a valid selection.
        layout.move(.reference, to: .newGroup(.right, at: 2))
        XCTAssertEqual(layout.right.map(\.panels), [[.design], [.player], [.reference]])
        XCTAssertEqual(layout.right[0].selected, .design)
    }

    func testMovingWithinTheSameDock() {
        // The stitch player (third on the right) moves above properties (first): positions are "before the move".
        layout.move(.player, to: .newGroup(.right, at: 0))
        XCTAssertEqual(layout.right.map(\.panels), [[.player], [.properties], [.design, .reference]])
        // Dropping a lone panel just below itself changes nothing.
        let before = layout
        layout.move(.player, to: .newGroup(.right, at: 1))
        XCTAssertEqual(layout, before)
        // Dropping a panel onto its own group's tabs just selects it.
        layout.move(.reference, to: .tab(.right, group: 2))
        XCTAssertEqual(layout.right[2], PanelGroup([.design, .reference], selected: .reference))
    }

    func testFloatingAndBack() {
        layout.move(.player, to: .float(x: 300, y: 200, width: 280, height: 160))
        XCTAssertEqual(layout.floating, [FloatingGroup(group: PanelGroup([.player]), x: 300, y: 200, width: 280, height: 160)])
        XCTAssertFalse(layout.right.contains { $0.panels.contains(.player) })
        layout.move(.threads, to: .floatingTab(0))
        XCTAssertEqual(layout.floating[0].group, PanelGroup([.player, .threads], selected: .threads))
        XCTAssertEqual(layout.left.map(\.panels), [[.sewingOrder]])
        // Docking both back removes the floating window.
        layout.move(.player, to: .newGroup(.left, at: 1)); layout.move(.threads, to: .tab(.left, group: 1))
        XCTAssertTrue(layout.floating.isEmpty)
        XCTAssertEqual(layout.left.map(\.panels), [[.sewingOrder], [.player, .threads]])
    }

    func testHideAndShowReturnPanelsToTheirHome() {
        layout.hide(.reference); layout.hide(.properties)
        XCTAssertFalse(layout.isVisible(.reference)); XCTAssertEqual(layout.right.map(\.panels), [[.design], [.player]])
        layout.show(.reference)   // its standard neighbor (design) is showing, so it becomes a tab there
        XCTAssertEqual(layout.right.map(\.panels), [[.design, .reference], [.player]])
        layout.show(.properties)  // no neighbors: a new group at the bottom of its dock
        XCTAssertEqual(layout.right.last?.panels, [.properties])
        layout.hide(.sewingOrder); layout.hide(.threads)
        XCTAssertTrue(layout.left.isEmpty, "An empty dock is allowed (the app hides it)")
    }

    func testRepairingASavedLayout() throws {
        let broken = PanelLayout(left: [PanelGroup([.threads, .threads, .design], selected: .player), PanelGroup([.design])], right: [], floating: [])
        let fixed = broken.normalized()
        XCTAssertEqual(fixed.left, [PanelGroup([.threads, .design])])
        let data = try JSONEncoder().encode(PanelLayout.standard)
        XCTAssertEqual(try JSONDecoder().decode(PanelLayout.self, from: data), .standard)
    }
}
