// Photoshop-style panels: the left and right docks, panel groups with tabs, dragging a panel's tab to re-dock,
// tab or float it, and floating panel windows. The arrangement itself (PanelLayout) lives in the core and is
// saved in preferences; these views draw it and turn drags into PanelLayout moves.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import EmbroideryCore

/// The panel being dragged, if any. Drags carry a text item so macOS runs the drag, but drop targets read the
/// panel from here (drags of ordinary text from other apps leave it nil and are ignored).
@MainActor enum PanelDrag {
    static var panel: PanelID?
    static let prefix = "embroidery-panel:"
    static func provider(for panel: PanelID) -> NSItemProvider {
        Self.panel = panel
        return NSItemProvider(object: (prefix + panel.rawValue) as NSString)
    }
}

/// What a panel shows.
struct PanelContent: View {
    let panel: PanelID
    @ObservedObject var state: EditorState
    var body: some View {
        switch panel {
        case .sewingOrder: ObjectPanel(state: state)
        case .properties: InspectorPanel(state: state, section: .properties)
        case .design: InspectorPanel(state: state, section: .design)
        case .reference: InspectorPanel(state: state, section: .reference)
        case .threads: ThreadsPanel(state: state)
        }
    }
}

/// Where a group lives, so a drop on it knows what to do.
enum GroupPlace: Equatable { case dock(DockSide, Int), floating(Int) }

/// One panel group: a tab bar (one tab per panel; drag a tab to move that panel) above the selected panel.
/// Dropping a dragged panel on the tab bar adds it as a tab; on the top or bottom half of a docked group, it
/// becomes a new group above or below.
struct PanelGroupView: View {
    let group: PanelGroup
    let place: GroupPlace
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    enum Zone { case tabs, before, after }
    /// The Pro view draws panels tighter: less padding, a shorter tab bar, smaller corners.
    private var pro: Bool { preferences.isPro }
    @State private var zone: Zone?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                tabBar
                Theme.divider.frame(height: 1)
                PanelContent(panel: group.selected, state: state)
                    .controlSize(pro ? .small : .regular)   // smaller buttons, menus and checkboxes in the Pro view
                    .padding(pro ? 8 : 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: pro ? 7 : 12))
            .overlay(RoundedRectangle(cornerRadius: pro ? 7 : 12).strokeBorder(zone == nil ? Theme.cardBorder : Theme.accent, lineWidth: zone == nil ? 1 : 2))
            // A bar shows where a new group would go.
            .overlay(alignment: .top) { if zone == .before { Capsule().fill(Theme.accent).frame(height: 4).offset(y: -4) } }
            .overlay(alignment: .bottom) { if zone == .after { Capsule().fill(Theme.accent).frame(height: 4).offset(y: 4) } }
            .onDrop(of: [.plainText], delegate: GroupDrop(place: place, height: geometry.size.height, zone: $zone))
        }
        .padding(pro ? 3 : 6)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(group.panels, id: \.self) { panel in
                let selected = panel == group.selected
                Text(pro ? panel.shortTitle : panel.title)
                    .font(Theme.body(pro ? 11 : 12, weight: selected ? .bold : .semibold)).lineLimit(1)
                    .padding(.horizontal, pro ? 7 : 9).frame(height: pro ? 20 : 24)
                    .background(selected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                    .contentShape(Rectangle())
                    .onTapGesture { Preferences.shared.updatePanels { $0.select(panel) } }
                    .onDrag { PanelDrag.provider(for: panel) }
                    .help("Drag to move \(panel.title): onto another panel's tabs, above or below a panel, or onto the canvas to float it")
            }
            Spacer(minLength: 4)
            Button { Preferences.shared.updatePanels { $0.hide(group.selected) } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
            .help("Hide \(group.selected.title). Window ▸ Panels brings it back.")
        }
        .padding(.horizontal, 6).frame(height: pro ? 28 : 34)
        .background(zone == .tabs ? Theme.accentSoft : Color.clear)
    }
}

/// Turns a drop on a group into a PanelLayout move.
struct GroupDrop: DropDelegate {
    let place: GroupPlace
    let height: CGFloat
    @Binding var zone: PanelGroupView.Zone?

    private func zoneAt(_ location: CGPoint) -> PanelGroupView.Zone {
        if location.y < 40 { return .tabs }
        if case .floating = place { return .tabs }   // floating windows only take tabs
        return location.y < height / 2 ? .before : .after
    }
    func validateDrop(info: DropInfo) -> Bool { PanelDrag.panel != nil }
    func dropEntered(info: DropInfo) { zone = zoneAt(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? { zone = zoneAt(info.location); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { zone = nil }
    func performDrop(info: DropInfo) -> Bool {
        defer { zone = nil; PanelDrag.panel = nil }
        guard let panel = PanelDrag.panel else { return false }
        let target = zoneAt(info.location)
        Preferences.shared.updatePanels { layout in
            switch (place, target) {
            case (.dock(let side, let index), .tabs): layout.move(panel, to: .tab(side, group: index))
            case (.dock(let side, let index), .before): layout.move(panel, to: .newGroup(side, at: index))
            case (.dock(let side, let index), .after): layout.move(panel, to: .newGroup(side, at: index + 1))
            case (.floating(let index), _): layout.move(panel, to: .floatingTab(index))
            }
        }
        return true
    }
}

/// One dock: its panel groups stacked top to bottom. Compact panels (threads, stitch player) get the height they
/// need and the others share the rest; dragging the divider under a group sets its height, which is remembered.
struct DockColumn: View {
    let side: DockSide
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    @State private var dragging: (panel: PanelID, height: Double)?   // live height while a divider is dragged
    @State private var dragBase = 0.0                                 // the group's height when the drag began

    var body: some View {
        let groups = preferences.panels.groups(side)
        GeometryReader { geometry in
            let heights = Self.heights(for: groups, total: geometry.size.height - Double(max(0, groups.count - 1)) * 8, dragging: dragging)
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.panels) { index, group in
                    PanelGroupView(group: group, place: .dock(side, index), state: state).frame(height: heights[index])
                    if index < groups.count - 1 { divider(below: group, height: heights[index]) }
                }
            }
        }
        .padding(.vertical, 4)
        .background(Theme.ground)
    }

    /// A thin bar between two groups; drag it to make the group above taller or shorter.
    private func divider(below group: PanelGroup, height: Double) -> some View {
        Theme.ground.frame(height: 8).frame(maxWidth: .infinity)
            .overlay(Capsule().fill(Theme.controlBorder).frame(width: 36, height: 3))
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            // Measured in window coordinates: measured from the divider itself (the default), the distance shrinks
            // as the divider moves with the group above it, so the divider trailed behind the pointer.
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    if dragging?.panel != group.panels[0] { dragBase = height }
                    dragging = (group.panels[0], max(80, dragBase + drag.translation.height))
                }
                .onEnded { _ in
                    if let dragging { Preferences.shared.updatePanels { $0.setHeight(dragging.height, ofGroupWith: dragging.panel) } }
                    dragging = nil
                })
    }

    /// Each group's height: a remembered (or live) height if it has one, else the compact panels' natural height,
    /// with the remaining room shared by the other groups; everything shrinks proportionally if there isn't room.
    static func heights(for groups: [PanelGroup], total: Double, dragging: (panel: PanelID, height: Double)?) -> [Double] {
        guard !groups.isEmpty else { return [] }
        var fixed: [Double?] = groups.map { group in
            if let dragging, group.panels.contains(dragging.panel) { return dragging.height }
            if let height = group.height { return height }
            return group.panels.allSatisfy { $0.compact != nil } ? group.panels.compactMap(\.compact).max() : nil
        }
        let flexibleCount = fixed.filter { $0 == nil }.count
        if flexibleCount == 0, let last = fixed.indices.last { fixed[last] = nil }   // someone has to take up the slack
        let used = fixed.compactMap { $0 }.reduce(0, +), flexible = max(1, fixed.filter { $0 == nil }.count)
        let share = (total - used) / Double(flexible)
        var heights = fixed.map { $0 ?? max(120, share) }
        let sum = heights.reduce(0, +)
        if sum > total, sum > 0 { heights = heights.map { $0 * total / sum } }
        return heights
    }
}

/// The floating panel windows of one design window. They're child windows, so they stay above the design and
/// move with it; their frames are saved in the panel layout.
@MainActor final class FloatingPanels: NSObject, NSWindowDelegate {
    private weak var owner: NSWindow?
    private let state: EditorState
    private var windows: [NSPanel] = []
    private var syncing = false

    init(owner: NSWindow, state: EditorState) { self.owner = owner; self.state = state }

    /// Makes the floating windows match the layout: creates, updates or closes them as needed.
    func sync(_ layout: PanelLayout) {
        syncing = true; defer { syncing = false }
        while windows.count > layout.floating.count {
            let window = windows.removeLast(); window.delegate = nil; owner?.removeChildWindow(window); window.orderOut(nil)
        }
        for (index, floating) in layout.floating.enumerated() {
            let window: NSPanel
            if index < windows.count { window = windows[index] } else { window = makeWindow(); windows.append(window) }
            let view = PanelGroupView(group: floating.group, place: .floating(index), state: state)
            if let host = window.contentView as? NSHostingView<PanelGroupView> { host.rootView = view } else { window.contentView = NSHostingView(rootView: view) }
            let frame = NSRect(x: floating.x, y: floating.y, width: floating.width, height: floating.height)
            if window.frame.integral != frame.integral { window.setFrame(frame, display: true) }
            if let owner, owner.isVisible, window.parent == nil { owner.addChildWindow(window, ordered: .above) }
        }
    }

    private func makeWindow() -> NSPanel {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 260), styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.becomesKeyOnlyIfNeeded = true; window.hidesOnDeactivate = true
        window.minSize = NSSize(width: 220, height: 130)
        window.backgroundColor = NSColor(Theme.ground)
        window.delegate = self
        return window
    }

    /// Saves a floating window's new position or size.
    private func remember(_ window: NSWindow) {
        guard !syncing, let index = windows.firstIndex(where: { $0 === window }) else { return }
        let frame = window.frame
        Preferences.shared.updatePanels { layout in
            guard layout.floating.indices.contains(index) else { return }
            layout.floating[index].x = frame.minX; layout.floating[index].y = frame.minY
            layout.floating[index].width = frame.width; layout.floating[index].height = frame.height
        }
    }
    func windowDidMove(_ notification: Notification) { if let window = notification.object as? NSWindow { remember(window) } }
    func windowDidEndLiveResize(_ notification: Notification) { if let window = notification.object as? NSWindow { remember(window) } }
    /// Closing a floating window hides its panels (Window ▸ Panels brings them back).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let index = windows.firstIndex(where: { $0 === sender }) else { return true }
        let panels = Preferences.shared.panels.floating.indices.contains(index) ? Preferences.shared.panels.floating[index].group.panels : []
        Preferences.shared.updatePanels { layout in panels.forEach { layout.hide($0) } }
        return false   // sync removes the window
    }
    func closeAll() { for window in windows { owner?.removeChildWindow(window); window.orderOut(nil) }; windows = [] }
}

extension PanelID {
    /// A shorter tab title for the Pro view's narrower tabs.
    var shortTitle: String {
        switch self {
        case .reference: return "Reference"
        default: return title
        }
    }
    /// The natural height of panels that need only a little room (threads); nil for panels that take whatever room
    /// the dock has.
    var compact: Double? {
        switch self {
        case .threads: return 170
        default: return nil
        }
    }
    /// The command that shows or hides this panel (each can have its own shortcut).
    var command: CommandID {
        switch self {
        case .sewingOrder: return .panelSewingOrder
        case .properties: return .inspector
        case .design: return .panelDesign
        case .reference: return .panelReference
        case .threads: return .palette
        }
    }
    init?(command: CommandID) {
        guard let panel = PanelID.allCases.first(where: { $0.command == command }) else { return nil }
        self = panel
    }
}
