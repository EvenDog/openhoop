// The arrangement of the editor's panels, Photoshop style: a left and a right dock, each a column of panel groups
// (several panels in one group show as tabs), plus groups floating in their own small windows. This file is only
// the arrangement and the moves you can make with it; the app draws it. Saved with the app's preferences.
import Foundation

/// The panels that can be docked, tabbed, floated or hidden.
public enum PanelID: String, Codable, CaseIterable, Sendable {
    case sewingOrder, properties, design, reference, threads, player
    public var title: String {
        switch self {
        case .sewingOrder: return "Sewing order"
        case .properties: return "Properties"
        case .design: return "Design"
        case .reference: return "Reference image"
        case .threads: return "Threads"
        case .player: return "Stitch player"
        }
    }
}

/// One or more panels shown together; with more than one, they're tabs and `selected` is the visible one.
public struct PanelGroup: Codable, Equatable, Sendable {
    public var panels: [PanelID]
    public var selected: PanelID
    /// The height (points) chosen by dragging the divider below it; nil shares the dock's room evenly.
    public var height: Double?
    public init(_ panels: [PanelID], selected: PanelID? = nil) { self.panels = panels; self.selected = selected ?? panels[0] }
}

/// A group in its own floating window, with the window's frame in screen points (origin at the bottom-left).
public struct FloatingGroup: Codable, Equatable, Sendable {
    public var group: PanelGroup
    public var x: Double, y: Double, width: Double, height: Double
    public init(group: PanelGroup, x: Double, y: Double, width: Double, height: Double) { self.group = group; self.x = x; self.y = y; self.width = width; self.height = height }
}

public enum DockSide: String, Codable, Sendable { case left, right }

/// Where a dragged panel can be dropped.
public enum PanelDestination: Equatable, Sendable {
    case newGroup(DockSide, at: Int)      // a new group in a dock, before the group now at that position
    case tab(DockSide, group: Int)        // as a tab of a docked group
    case floatingTab(Int)                 // as a tab of a floating group
    case float(x: Double, y: Double, width: Double, height: Double)   // a new floating window
}

public struct PanelLayout: Codable, Equatable, Sendable {
    public var left: [PanelGroup]
    public var right: [PanelGroup]
    public var floating: [FloatingGroup] = []
    public var leftWidth = 230.0
    public var rightWidth = 280.0

    /// The out-of-the-box arrangement: sewing order and threads on the left; properties, design and reference image
    /// (as tabs) and the stitch player on the right.
    public static let standard = PanelLayout(left: [PanelGroup([.sewingOrder]), PanelGroup([.threads])],
                                             right: [PanelGroup([.properties]), PanelGroup([.design, .reference]), PanelGroup([.player])])

    /// The Pro view's out-of-the-box arrangement: sewing order, design and reference image (as tabs) above the
    /// threads on a wider left dock; properties above the stitch player on the right.
    public static let pro: PanelLayout = {
        var layout = PanelLayout(left: [PanelGroup([.sewingOrder, .design, .reference]), PanelGroup([.threads])],
                                 right: [PanelGroup([.properties]), PanelGroup([.player])])
        layout.leftWidth = 340; layout.rightWidth = 290
        return layout
    }()

    public init(left: [PanelGroup], right: [PanelGroup], floating: [FloatingGroup] = []) { self.left = left; self.right = right; self.floating = floating }

    public func groups(_ side: DockSide) -> [PanelGroup] { side == .left ? left : right }
    private mutating func setGroups(_ side: DockSide, _ groups: [PanelGroup]) { if side == .left { left = groups } else { right = groups } }

    /// True if the panel is shown anywhere (docked or floating).
    public func isVisible(_ panel: PanelID) -> Bool {
        (left + right + floating.map(\.group)).contains { $0.panels.contains(panel) }
    }

    /// Hides a panel: takes it out of wherever it is. Groups left empty disappear.
    public mutating func hide(_ panel: PanelID) {
        func without(_ group: PanelGroup) -> PanelGroup? {
            let rest = group.panels.filter { $0 != panel }
            guard !rest.isEmpty else { return nil }
            var result = PanelGroup(rest, selected: rest.contains(group.selected) ? group.selected : rest[0]); result.height = group.height
            return result
        }
        left = left.compactMap(without); right = right.compactMap(without)
        floating = floating.compactMap { f in without(f.group).map { var copy = f; copy.group = $0; return copy } }
    }

    /// Moves a panel to `destination` (from wherever it was, or from hidden) and makes it the visible tab there.
    /// Positions in `destination` refer to the layout before the move.
    public mutating func move(_ panel: PanelID, to destination: PanelDestination) {
        // Identify the target group before removing the panel, since removing can shift or delete groups.
        var targetGroup: PanelGroup?
        switch destination {
        case .tab(let side, let index): targetGroup = groups(side).indices.contains(index) ? groups(side)[index] : nil
        case .floatingTab(let index): targetGroup = floating.indices.contains(index) ? floating[index].group : nil
        default: break
        }
        if let group = targetGroup, group.panels.contains(panel) { select(panel); return }   // already there
        // A new group's position counts groups before the move; dropping a panel next to its own old spot stays put.
        var insertion: (side: DockSide, index: Int)?
        if case .newGroup(let side, let at) = destination {
            let before = groups(side).prefix(max(0, min(at, groups(side).count)))
            insertion = (side, before.filter { !($0.panels == [panel]) }.count)
        }
        hide(panel)
        switch destination {
        case .newGroup:
            guard let (side, index) = insertion else { return }
            var list = groups(side); list.insert(PanelGroup([panel]), at: min(index, list.count)); setGroups(side, list)
        case .tab(let side, _):
            guard let target = targetGroup, let index = groups(side).firstIndex(where: { $0.panels.contains(target.panels.first { $0 != panel } ?? panel) }) else {
                var list = groups(side); list.append(PanelGroup([panel])); setGroups(side, list); return
            }
            var list = groups(side); list[index].panels.append(panel); list[index].selected = panel; setGroups(side, list)
        case .floatingTab:
            guard let target = targetGroup, let index = floating.firstIndex(where: { $0.group.panels.contains(target.panels.first { $0 != panel } ?? panel) }) else { return }
            floating[index].group.panels.append(panel); floating[index].group.selected = panel
        case .float(let x, let y, let width, let height):
            floating.append(FloatingGroup(group: PanelGroup([panel]), x: x, y: y, width: width, height: height))
        }
    }

    /// Shows a hidden panel where it lives in `home` (the standard layout of the current view): as a tab with its
    /// neighbors there if one of them is showing, else as a new group at the bottom of its dock there.
    public mutating func show(_ panel: PanelID, home: PanelLayout = .standard) {
        guard !isVisible(panel) else { select(panel); return }
        let side: DockSide = home.left.contains { $0.panels.contains(panel) } ? .left : .right
        let neighbors = home.groups(side).first { $0.panels.contains(panel) }?.panels.filter { $0 != panel } ?? []
        if let index = groups(side).firstIndex(where: { !Set($0.panels).isDisjoint(with: neighbors) }) { move(panel, to: .tab(side, group: index)) }
        else { move(panel, to: .newGroup(side, at: groups(side).count)) }
    }

    /// Sets the height of the docked group holding `panel` (from dragging the divider below it).
    public mutating func setHeight(_ height: Double, ofGroupWith panel: PanelID) {
        for i in left.indices where left[i].panels.contains(panel) { left[i].height = height }
        for i in right.indices where right[i].panels.contains(panel) { right[i].height = height }
    }

    /// Makes `panel` the visible tab of its group.
    public mutating func select(_ panel: PanelID) {
        for i in left.indices where left[i].panels.contains(panel) { left[i].selected = panel }
        for i in right.indices where right[i].panels.contains(panel) { right[i].selected = panel }
        for i in floating.indices where floating[i].group.panels.contains(panel) { floating[i].group.selected = panel }
    }

    /// Repairs a layout read from disk: each panel at most once, no empty groups, valid selections.
    public func normalized() -> PanelLayout {
        var seen = Set<PanelID>()
        func clean(_ group: PanelGroup) -> PanelGroup? {
            let panels = group.panels.filter { seen.insert($0).inserted }
            guard !panels.isEmpty else { return nil }
            var result = PanelGroup(panels, selected: panels.contains(group.selected) ? group.selected : panels[0])
            result.height = group.height.map { min(2000, max(80, $0)) }
            return result
        }
        var result = self
        result.left = left.compactMap(clean); result.right = right.compactMap(clean)
        result.floating = floating.compactMap { f in clean(f.group).map { var copy = f; copy.group = $0; return copy } }
        result.leftWidth = min(500, max(180, leftWidth)); result.rightWidth = min(500, max(200, rightWidth))
        return result
    }
}
