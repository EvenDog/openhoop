// View › Customize Tools…: rearrange the tool band. Tools can be dragged within a group, into another group or into
// a Hidden tray, and whole groups can be dragged into a new order. The arrangement is saved in the preferences.
import SwiftUI
import EmbroideryCore

/// The tool band's groups and the tools taken off it, as a list you can rearrange. The moves here are what dragging
/// does in the Customize Tools sheet.
struct ToolArrangement: Equatable {
    struct Group: Equatable {
        /// The group's built-in title ("Pick & shape", "Stitch"…), which also identifies it.
        var title: String
        var commands: [CommandID]
    }
    var groups: [Group]
    /// Tools taken off the band. They stay in the menus and keep their keys.
    var hidden: [CommandID]

    /// The band as OpenHoop arranges it.
    static var builtIn: ToolArrangement { ToolArrangement(groups: ToolStrip.proGroups.map { Group(title: $0.title, commands: $0.commands) }, hidden: []) }

    /// Moves `tool` into group `group` (nil: the Hidden tray), onto the place of `target`, a tool already there; with
    /// no target it goes at the end. Dropped on a tool further along the same list, it lands just after that tool,
    /// so dragging right works as well as dragging left.
    mutating func move(_ tool: CommandID, to group: Int?, onto target: CommandID? = nil) {
        guard tool != target else { return }
        // The target's place, found before `tool` is taken out. Inserting there puts `tool` before the target, or,
        // when `tool` came from earlier in the same list, just after it (taking `tool` out shifted the target left).
        let place = target.flatMap { list(group).firstIndex(of: $0) }
        for index in groups.indices { groups[index].commands.removeAll { $0 == tool } }
        hidden.removeAll { $0 == tool }
        if let group { groups[group].commands.insert(tool, at: place ?? groups[group].commands.count) } else { hidden.insert(tool, at: place ?? hidden.count) }
    }
    /// Moves the group titled `title` to where the group at `index` is.
    mutating func moveGroup(_ title: String, to index: Int) {
        guard let from = groups.firstIndex(where: { $0.title == title }), groups.indices.contains(index), from != index else { return }
        groups.insert(groups.remove(at: from), at: index)
    }
    /// The tools of group `group`, or the Hidden tray's for nil.
    private func list(_ group: Int?) -> [CommandID] { group.map { groups[$0].commands } ?? hidden }
}

/// How the arrangement is saved in the preferences. Tools are stored by their command names, so a file from a newer
/// OpenHoop (with tools this one doesn't know) still loads.
struct ToolLayout: Codable, Equatable {
    struct Group: Codable, Equatable {
        var title: String
        var tools: [String]
    }
    var groups: [Group]
    var hidden: [String]

    init(groups: [Group], hidden: [String]) { self.groups = groups; self.hidden = hidden }
    /// What to save for `arrangement`: nil when it's the built-in one.
    init?(_ arrangement: ToolArrangement) {
        guard arrangement != .builtIn else { return nil }
        groups = arrangement.groups.map { Group(title: $0.title, tools: $0.commands.map(\.rawValue)) }
        hidden = arrangement.hidden.map(\.rawValue)
    }

    /// The arrangement a saved layout stands for, or the built-in one for nil. A saved layout is repaired on the way:
    /// unknown or repeated tools are dropped, a missing group comes back at the end, and a tool that's neither placed
    /// nor hidden (one added in a later version) joins its built-in group. Groups may come back empty.
    static func arrangement(_ layout: ToolLayout?) -> ToolArrangement {
        let builtIn = ToolArrangement.builtIn
        guard let layout else { return builtIn }
        let bandTools = Set(builtIn.groups.flatMap(\.commands))
        var placed = Set<CommandID>()
        /// The known tools in `names`, each only the first time it turns up anywhere in the layout.
        func tools(_ names: [String]) -> [CommandID] { names.compactMap(CommandID.init(rawValue:)).filter { bandTools.contains($0) && placed.insert($0).inserted } }
        let hidden = tools(layout.hidden)
        var groups: [ToolArrangement.Group] = []
        for group in layout.groups where builtIn.groups.contains(where: { $0.title == group.title }) && !groups.contains(where: { $0.title == group.title }) {
            groups.append(.init(title: group.title, commands: tools(group.tools)))
        }
        for group in builtIn.groups where !groups.contains(where: { $0.title == group.title }) { groups.append(.init(title: group.title, commands: [])) }
        for group in builtIn.groups {
            let index = groups.firstIndex { $0.title == group.title }!
            groups[index].commands += group.commands.filter { !placed.contains($0) }
        }
        return ToolArrangement(groups: groups, hidden: hidden)
    }
}

/// The Customize Tools window: the band's groups as on the band (caption on top, tools two high, groups side by side,
/// wrapping onto more lines), then the Hidden tray. Drag a tool onto another tool to take its place, onto a group to
/// add it at the end, or onto Hidden to take it off the band; drag a group by its name to move the whole group.
/// Every change shows on the band at once (`changed`); Cancel puts back the arrangement it started with.
struct CustomizeToolsView: View {
    @State var arrangement: ToolArrangement
    var changed: (ToolArrangement) -> Void
    var finish: (Bool) -> Void
    /// The group a drag is over (-1 for Hidden), to light it up.
    @State private var targetGroup: Int?

    var body: some View {
        DialogFrame(eyebrow: "Tool band", title: "Customize tools",
                    subtitle: "Drag a tool onto another to take its place, or onto a group to add it at the end. Drag a group by its name to move it. Tools in Hidden leave the band but stay in the menus and keep their keys. The band changes as you go.",
                    primary: "Done", finish: finish) {
            VStack(alignment: .leading, spacing: 14) {
                FlowLayout(spacing: 8) {
                    ForEach(Array(arrangement.groups.enumerated()), id: \.element.title) { index, group in groupBox(group, index: index) }
                }
                hiddenTray
                HStack {
                    Button("Reset to Default") { arrangement = .builtIn }.buttonStyle(ThemedButtonStyle()).disabled(arrangement == .builtIn)
                    Spacer()
                }
            }
        }
        .onChange(of: arrangement) { _, new in changed(new) }
    }

    /// One group as it looks on the band: its caption (the handle for moving the group), then its tools in columns
    /// two high.
    private func groupBox(_ group: ToolArrangement.Group, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .semibold))
                Text(group.title.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Theme.toolBandInkSecondary)
            .padding(.leading, 3)
            .contentShape(Rectangle())
            .draggable("group:" + group.title)
            .help("Drag to move the \(group.title) group")
            HStack(alignment: .top, spacing: 2) {
                // stride(from:to:by:) counts 0, 2, 4…: the first tool of each two-high column, as on the band.
                ForEach(Array(stride(from: 0, to: group.commands.count, by: 2)), id: \.self) { first in
                    VStack(spacing: 2) { ForEach(group.commands[first..<min(first + 2, group.commands.count)], id: \.self) { cell($0, group: index, ink: Theme.toolBandInk) } }
                }
                if group.commands.isEmpty {
                    Text("Empty: drag\ntools here").font(Theme.body(10)).foregroundStyle(Theme.toolBandInkSecondary).frame(width: Self.cellWidth, height: 2 * Self.cellHeight + 2)
                }
            }
        }
        .padding(8)
        .background(Theme.toolBand, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targetGroup == index ? Theme.accent : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { items, _ in drop(items, group: index, onto: nil) } isTargeted: { highlight(index, $0) }
    }

    /// The tools taken off the band, in a dashed tray that wraps onto more lines.
    private var hiddenTray: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HIDDEN").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.inkSecondary).padding(.leading, 3)
            FlowLayout(spacing: 2) { ForEach(arrangement.hidden, id: \.self) { cell($0, group: nil, ink: Theme.ink) } }
                .frame(maxWidth: .infinity, minHeight: Self.cellHeight, alignment: .leading)
                .overlay(alignment: .leading) {
                    if arrangement.hidden.isEmpty { Text("Drag tools here to take them off the band").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).padding(.leading, 3) }
                }
        }
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targetGroup == -1 ? Theme.accent : Theme.controlBorder,
                                                               style: StrokeStyle(lineWidth: targetGroup == -1 ? 2 : 1, dash: targetGroup == -1 ? [] : [4, 3])))
        .dropDestination(for: String.self) { items, _ in drop(items, group: nil, onto: nil) } isTargeted: { highlight(-1, $0) }
    }

    static let cellWidth: CGFloat = 64, cellHeight: CGFloat = 54
    /// A tool: its icon with its name underneath. Drag it away to move it, or drop another tool on it to put that one
    /// in its place.
    private func cell(_ tool: CommandID, group: Int?, ink: Color) -> some View {
        VStack(spacing: 2) {
            Image.symbol(tool.symbol, size: 14).font(.system(size: 14)).frame(height: 24)
            Text(tool.title.replacingOccurrences(of: "…", with: "")).font(.system(size: 9, design: .rounded))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        .foregroundStyle(ink)
        .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
        .contentShape(Rectangle())
        .help(tool.title)
        .draggable("tool:" + tool.rawValue)
        .dropDestination(for: String.self) { items, _ in drop(items, group: group, onto: tool) }
    }

    /// Lights up the group (or Hidden, -1) a drag is over, and turns it off again when the drag leaves.
    private func highlight(_ key: Int, _ over: Bool) { if over { targetGroup = key } else if targetGroup == key { targetGroup = nil } }

    /// Handles a drop: a tool moves to `group` (onto `target`'s place, or the end); a group dropped on a group moves
    /// to that group's place. Returns false for anything else, which the drop then ignores.
    private func drop(_ items: [String], group: Int?, onto target: CommandID?) -> Bool {
        guard let item = items.first else { return false }
        if item.hasPrefix("tool:"), let tool = CommandID(rawValue: String(item.dropFirst("tool:".count))) {
            arrangement.move(tool, to: group, onto: target); return true
        }
        if item.hasPrefix("group:"), let group { arrangement.moveGroup(String(item.dropFirst("group:".count)), to: group); return true }
        return false
    }
}

/// Lays views out left to right, starting a new line when the next one wouldn't fit, like words in a paragraph.
/// (`Layout` is SwiftUI's way to write your own arrangement: it measures the views, then places them.)
struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, arrange(width: bounds.width, subviews).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }
    /// Where each view's top-left corner goes, and the size of the whole.
    private func arrange(width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += lineHeight + spacing; lineHeight = 0 }   // start a new line
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing; lineHeight = max(lineHeight, size.height); widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + lineHeight))
    }
}
