// Native SwiftUI panels provide the tool strip, object list, stitch properties, playback and shortcut editor.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import EmbroideryCore

private let accent = Theme.accent

struct SectionLabel: View {
    var title: String
    var body: some View { Text(title.uppercased()).font(Theme.caption).tracking(1.0).foregroundStyle(Theme.inkSecondary).frame(maxWidth: .infinity, alignment: .leading) }
}

/// The strip docked under the window toolbar: tools grouped by job, each labeled with its current hotkey.
/// Buttons run the same commands as the menus and shortcuts, so rebinding a key updates the label here.
/// Related tools can share one slot (a "flyout"): its chevron, or a right-click, lists them all, and the slot
/// shows the one picked last, or the active tool if it's one of them.
struct ToolStrip: View {
    @ObservedObject var state: EditorState
    /// True for the Pro view's rail down the left side, which shows only when it's picked in Settings; false for the
    /// strip across the top.
    var rail = false
    @ObservedObject var preferences = Preferences.shared
    /// The command each shared slot shows, keyed by the slot's first command; it changes when you pick from its menu.
    @State private var picked: [CommandID: CommandID] = [:]
    /// The shared slot whose list is open (keyed by its first command), or nil.
    @State private var openSlot: CommandID?
    /// True while the Show list is open.
    @State private var showListOpen = false
    /// What the Show list switches on and off.
    private let showList: [CommandID] = [.showStitches, .showOutlines, .showConnectors, .needles, .showUnderlay, .hideOthers, .showRulers, .densityMap]
    // Each group is a caption plus its slots, in on-screen order; a slot with several commands is a flyout.
    private let groups: [(title: String, slots: [[CommandID]])] = [
        ("Pick & shape", [[.selectTool], [.nodeTool, .editStitches, .smoothShapes], [.knifeTool, .weldObjects, .branching], [.entryExitTool]]),
        ("Stitch", [[.runTool], [.satinTool], [.fillTool, .holeTool, .addStitchAngles, .removeStitchAngles]]),
        ("Shape", [[.openShapeTool, .closedShapeTool], [.freehandOpenTool, .freehandClosedTool], [.rectangleTool, .ellipseTool, .basicShapeTool]]),
        ("Add", [[.lettering, .addMonogram, .satinBorder, .applique, .autoDigitize, .laydown]]),
        ("View", [[.panTool, .measureTool], [.grid], [.threadView], [.zoomFit, .zoomDesign, .zoomBoxTool, .zoomActual, .zoomSelected]])
    ]
    /// The Pro view's tools: every one out as an icon button (no shared slots or lists to open), in captioned groups.
    /// Hovering a button shows its name and key.
    static let proGroups: [(title: String, commands: [CommandID])] = [
        ("Pick & shape", [.selectTool, .nodeTool, .editStitches, .smoothShapes, .knifeTool, .weldObjects, .branching, .entryExitTool, .panTool, .artworkTool]),
        ("Stitch", [.runTool, .satinTool, .fillTool, .holeTool, .addStitchAngles, .removeStitchAngles]),
        ("Shape", [.openShapeTool, .closedShapeTool, .freehandOpenTool, .freehandClosedTool, .rectangleTool, .ellipseTool, .basicShapeTool]),
        ("Add", [.lettering, .addMonogram, .satinBorder, .applique, .autoDigitize, .laydown]),
        ("View", [.measureTool, .grid, .snap, .threadView]),
        ("Show", [.showStitches, .showOutlines, .showConnectors, .needles, .showUnderlay, .hideOthers, .showRulers, .densityMap]),
        ("Zoom", [.zoomFit, .zoomDesign, .zoomBoxTool, .zoomActual, .zoomSelected])
    ]
    /// The rail's groups: the same tools, with View and Show sharing a group so the rail's rows of three fill evenly.
    static var railGroups: [[CommandID]] {
        let groups = proGroups.map(\.commands)
        return Array(groups[0..<4]) + [groups[4] + groups[5], groups[6]]
    }
    var body: some View {
        if rail {
            if preferences.isPro && preferences.proToolsOnLeft { proRail } else { Color.clear.frame(width: 0) }
        } else if preferences.isPro {
            VStack(spacing: 0) {
                if !preferences.proToolsOnLeft {
                    proStrip
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.toolBand)
                    Theme.toolBandEdge.frame(height: 1)
                }
                PrecisionBar(state: state)   // exact position, size and turn of the selection
                Theme.edge.frame(height: 1)
            }
        } else {
            // ViewThatFits shows the first layout that fits the room the player leaves: full labels, else icons and keys only.
            HStack(alignment: .bottom, spacing: 12) {
                ViewThatFits(in: .horizontal) { strip(compact: false); strip(compact: true) }
                Spacer(minLength: 0)
                StripPlayer(state: state).fixedSize()
            }
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .overlay(alignment: .bottom) { Theme.edge.frame(height: 1) }
        }
    }
    /// The Pro strip across the top: each group under its caption, its buttons two high, filled column by column.
    private var proStrip: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(Self.proGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Theme.toolBandDivider.frame(width: 1, height: 62).padding(.horizontal, 9) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8)
                        .foregroundStyle(Theme.toolBandInkSecondary).padding(.leading, 3).lineLimit(1).fixedSize()
                    HStack(alignment: .top, spacing: 2) {
                        // stride(from:to:by:) counts 0, 2, 4…: the first button of each two-high column.
                        ForEach(Array(stride(from: 0, to: group.commands.count, by: 2)), id: \.self) { first in
                            VStack(spacing: 2) { ForEach(group.commands[first..<min(first + 2, group.commands.count)], id: \.self) { proButton($0) } }
                        }
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 12)
            let hint = Self.hint(for: state)
            // Two short lines fit beside the tools where one long one wouldn't. In a narrow window, only the tool's
            // name shows, or nothing (the status bar and the hover help still give the whole hint).
            ViewThatFits(in: .horizontal) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(hint.tool).font(Theme.body(12, weight: .bold)).foregroundStyle(Theme.toolBandInk)
                    Text(hint.how).font(Theme.body(11)).foregroundStyle(Theme.toolBandInkSecondary)
                }
                Text(hint.tool).font(Theme.body(12, weight: .bold)).foregroundStyle(Theme.toolBandInk)
                Color.clear.frame(width: 0, height: 0)
            }
            .lineLimit(1)
            .help(hint.tool + ": " + hint.how)
            Theme.toolBandDivider.frame(width: 1, height: 62).padding(.horizontal, 9)
            StripPlayer(state: state, onBand: true).fixedSize()
        }
    }
    /// The Pro rail down the left side (picked in Settings): the same tools, three across, groups split by lines,
    /// with the stitch player at the bottom. The tools scroll if the window is too short to show them all.
    private var proRail: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(Self.railGroups.enumerated()), id: \.offset) { index, group in
                        if index > 0 { Theme.toolBandDivider.frame(height: 1) }
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(stride(from: 0, to: group.count, by: 3)), id: \.self) { first in
                                HStack(spacing: 2) { ForEach(group[first..<min(first + 3, group.count)], id: \.self) { proButton($0) } }
                            }
                        }
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.never)
            Theme.toolBandDivider.frame(height: 1)
            StripPlayer(state: state, stacked: true, onBand: true).padding(10)
        }
        .frame(width: 112)
        .background(Theme.toolBand)
        .overlay(alignment: .trailing) { Theme.toolBandEdge.frame(width: 1) }
    }
    /// What the current tool is and, briefly, how to use it, for the Pro strip and the tool's choices in Properties.
    /// Keys that can be rebound are read from the current shortcuts.
    static func hint(for state: EditorState) -> (tool: String, how: String) {
        let preferences = Preferences.shared
        /// " · ↩ finishes", or nothing if the command has no key.
        func key(_ command: CommandID, _ verb: String) -> String {
            let keys = preferences.keys(command).first?.display ?? ""; return keys.isEmpty ? "" : " · \(keys) \(verb)"
        }
        switch state.tool {
        case .select: return ("Select", "Shift-click selects more")
        case .node: return ("Edit nodes", "drag nodes and handles" + key(.insertNode, "inserts") + key(.deleteNode, "removes"))
        case .run: return ("Running stitch", "click corners, drag for curves" + key(.finishPath, "finishes"))
        case .satin: return ("Satin column", "click the left edge, then the right" + key(.finishPath, "finishes"))
        case .fill: return ("Fill", "trace a closed outline" + key(.finishPath, "finishes"))
        case .hole: return ("Hole", "trace inside the fill" + key(.finishPath, "finishes"))
        case .pan: return ("Pan", "drag to move the view")
        case .entryExit: return ("Start & end", "click sets the start · Option-click the end")
        case .artwork: return ("Move artwork", "drag to move · drag a corner to resize")
        case .openShape: return ("Open shape", "click corners, drag for curves" + key(.finishPath, "finishes"))
        case .closedShape: return ("Closed shape", "trace the outline" + key(.finishPath, "finishes"))
        case .freehandOpen: return ("Freehand open", "press and drag · let go to finish")
        case .freehandClosed: return ("Freehand closed", "press and drag · let go to finish")
        case .ellipse: return ("Ellipse", "drag out from the center · ⌘ for a circle")
        case .rectangle, .basicShape: return ("Shape", "drag · ⌘ keeps it even · ⇧ from the center")
        case .zoomBox: return ("Zoom box", "drag a box to zoom into · click zooms in 2×")
        case .measure: return ("Measure", "drag between two points")
        case .text: return ("Lettering", "click where it goes, then type in Properties")
        case .knife: return ("Knife", "click points across shapes" + key(.finishPath, "cuts"))
        case .stitchEdit: return ("Edit stitches", "click or box-select points · drag moves" + key(.delete, "deletes") + " · ⌥-click adds")
        case .addAngles: return ("Stitch angles", state.angleStart == nil ? "click two points across the fill" : "click the other side")
        case .removeAngles: return ("Remove angles", "click a line to remove it")
        case .branch: return ("Branching", state.branchPoints.isEmpty ? "click where it starts · ↩ chooses for you" : "click where it ends · ↩ chooses for you")
        }
    }
    /// One Pro tool button: just the tool's icon. Its name and keys show when the pointer rests on it.
    private func proButton(_ command: CommandID) -> some View {
        let active = isActive(command), available = isAvailable(command)
        return Button { AppDelegate.shared.perform(command) } label: {
            Image(systemName: command.symbol).font(.system(size: 14))
                .frame(width: 30, height: 30)
                .background(active ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(active ? Theme.onAccent : Theme.toolBandInk)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!available).opacity(available ? 1 : 0.4)
        .help(preferences.hint(command))
        .accessibilityLabel(command.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
    private func strip(compact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: compact ? 12 : 18) {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title.uppercased()).font(Theme.caption).tracking(0.8).foregroundStyle(Theme.inkSecondary).padding(.leading, 4).lineLimit(1)
                    HStack(spacing: 2) {
                        ForEach(group.slots, id: \.self) { slot($0, compact: compact) }
                        if group.title == "View" { showButton(compact: compact) }
                    }
                }
            }
        }
        .fixedSize()   // never squeeze labels onto two lines; ViewThatFits switches to the compact strip instead
    }
    /// The command a slot shows: its active tool if any, else the one last picked from its menu, else its first.
    private func shown(_ slot: [CommandID]) -> CommandID {
        slot.first(where: isActive) ?? picked[slot[0]] ?? slot[0]
    }
    private func slot(_ commands: [CommandID], compact: Bool) -> some View {
        let command = shown(commands), active = isActive(command)
        return HStack(spacing: 0) {
            Button { AppDelegate.shared.perform(command) } label: {
                HStack(spacing: 6) {
                    Image(systemName: command.symbol).font(.system(size: 14))
                    if !compact { Text(shortName(command)).font(Theme.body(12, weight: .semibold)) }
                }
                .padding(.leading, 10).padding(.trailing, commands.count > 1 ? 4 : 10).frame(height: 32)
                .contentShape(Rectangle())   // makes the whole rounded area clickable, not just the icon and text
            }
            .buttonStyle(.plain)
            if commands.count > 1 {
                // The chevron opens a small list of the slot's tools under it.
                Button { openSlot = commands[0] } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        .padding(.leading, 2).padding(.trailing, 8).frame(height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("More tools: " + commands.map { shortName($0) }.joined(separator: ", "))
                .popover(isPresented: Binding(get: { openSlot == commands[0] }, set: { if !$0 { openSlot = nil } }), arrowEdge: .bottom) { flyout(commands) }
            }
        }
        .lineLimit(1)
        .fixedSize()   // a slot never shrinks below its natural size, which would squeeze its labels out of sight
        .background(active ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(active ? Theme.onAccent : Theme.ink)
        .contextMenu { if commands.count > 1 { menuItems(commands) } }   // right-click opens the same list
        .help(preferences.hint(command))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shortName(command))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
    /// The Show button: opens a list of what the canvas shows, each with a check mark when on and its key. In the
    /// Pro strip (`compact`) it's just an icon.
    private func showButton(compact: Bool) -> some View {
        let anyOff = !state.showStitches || state.hideOthers   // a hint that something is hidden
        return Button { showListOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d").font(.system(size: 14))
                if !compact { Text("Show").font(Theme.body(12, weight: .semibold)) }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, compact ? 6 : 10).frame(height: compact ? 30 : 32)
            .background(anyOff ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: compact ? 6 : 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Theme.ink).fixedSize()
        .help("Show or hide stitches, outlines, connectors and more")
        .accessibilityLabel("Show")
        .popover(isPresented: $showListOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(showList, id: \.self) { command in
                    Button { AppDelegate.shared.perform(command) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).frame(width: 16).opacity(isActive(command) ? 1 : 0)
                            Text(showName(command)).font(Theme.body(13, weight: .semibold))
                            Spacer(minLength: 16)
                            Text(preferences.label(command)).font(Theme.body(11, weight: .bold)).foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(preferences.hint(command))
                }
            }
            .padding(6).frame(minWidth: 250).foregroundStyle(Theme.ink)
        }
    }
    /// The names in the Show list.
    private func showName(_ command: CommandID) -> String {
        switch command {
        case .showStitches: return "Stitches"
        case .showOutlines: return "Outlines of every object"
        case .showConnectors: return "Connectors (travel moves)"
        case .needles: return "Needle points"
        case .showUnderlay: return "Underlay"
        case .densityMap: return "Density"
        case .hideOthers: return "Hide unselected objects"
        default: return command.title
        }
    }
    /// The list a slot's chevron opens: each tool with its icon, full name and hotkey. Tools that can't run right
    /// now are dimmed.
    private func flyout(_ commands: [CommandID]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(commands, id: \.self) { command in
                let available = isAvailable(command)
                Button { openSlot = nil; picked[commands[0]] = command; AppDelegate.shared.perform(command) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: command.symbol).font(.system(size: 14)).frame(width: 20)
                        Text(command.title).font(Theme.body(13, weight: .semibold))
                        Spacer(minLength: 16)
                        Text(preferences.label(command)).font(Theme.body(11, weight: .bold)).foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(shown(commands) == command ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!available).opacity(available ? 1 : 0.45).help(preferences.hint(command))
            }
        }
        .padding(6).frame(minWidth: 250).foregroundStyle(Theme.ink)
    }
    /// One menu item per command in a shared slot, with its full name and hotkey; picking one also makes it the
    /// command the slot shows.
    @ViewBuilder private func menuItems(_ commands: [CommandID]) -> some View {
        ForEach(commands, id: \.self) { command in
            Button { picked[commands[0]] = command; AppDelegate.shared.perform(command) } label: {
                let keys = preferences.label(command)
                Label(command.title + (keys.isEmpty ? "" : "   " + keys), systemImage: command.symbol)
            }
            .disabled(!isAvailable(command))
        }
    }
    /// False for commands that can't run right now, so their menu items are greyed out.
    private func isAvailable(_ command: CommandID) -> Bool {
        switch command {
        case .holeTool: return state.selection.count == 1 && state.selected?.kind == .fill && state.selected?.locked == false
        case .addStitchAngles: return state.selection.count == 1 && state.selected?.kind == .fill && state.selected?.locked == false && [.tatami, .satin].contains(state.selected?.settings.fillStyle ?? .tatami)
        case .removeStitchAngles: return state.selection.count == 1 && state.selected?.locked == false && !(state.selected?.settings.angleLines ?? []).isEmpty
        case .useAsFillGuide: return state.fillAndGuideLine != nil
        case .putLetteringOnLine: return state.letteringAndLine != nil
        case .satinBorder, .applique: return state.design.objects.contains { state.selection.contains($0.id) && !$0.locked && SatinBorder.canBorder($0) }
        case .autoDigitize: return state.design.artwork != nil
        case .weldObjects: return state.design.objects.filter { state.selection.contains($0.id) && !$0.locked && $0.areaRings != nil }.count >= 2
        case .smoothShapes: return !state.editableSelection.isEmpty
        case .editStitches: return state.selection.count == 1 && state.selected?.locked == false && [.run, .satin, .fill].contains(state.selected?.kind)
        case .branching: return state.design.objects.filter { state.selection.contains($0.id) && !$0.locked && [.run, .satin, .fill].contains($0.kind) }.count >= 2
        default: return !command.needsSelection || !state.selection.isEmpty
        }
    }
    /// True when this button's tool is the current tool, or its view option (the grid) is switched on.
    private func isActive(_ command: CommandID) -> Bool {
        if let tool = Tool.forCommand[command] { return state.tool == tool }
        switch command {
        case .grid: return state.grid
        case .snap: return state.snap
        case .needles: return state.needles
        case .showUnderlay: return state.showUnderlay
        case .densityMap: return state.showDensity
        case .threadView: return preferences.threadView
        case .showRulers: return preferences.showsRulers
        case .showStitches: return state.showStitches
        case .showOutlines: return state.showOutlines
        case .showConnectors: return state.showsConnectors
        case .hideOthers: return state.hideOthers
        default: return false
        }
    }
    /// Short labels that fit the strip; menus and Keyboard Shortcuts keep the full command titles.
    private func shortName(_ command: CommandID) -> String {
        switch command {
        case .selectTool: return "Select"
        case .nodeTool: return "Nodes"
        case .runTool: return "Running"
        case .satinTool: return "Satin"
        case .fillTool: return "Fill"
        case .holeTool: return "Hole"
        case .panTool: return "Pan"
        case .entryExitTool: return "Start/End"
        case .smoothShapes: return "Smooth"
        case .openShapeTool: return "Open"
        case .closedShapeTool: return "Closed"
        case .freehandOpenTool: return "Freehand"
        case .freehandClosedTool: return "Freehand closed"
        case .basicShapeTool: return "Shapes"
        case .lettering: return "Text"
        case .satinBorder: return "Border"
        case .applique: return "Appliqué"
        case .autoDigitize: return "Auto-digitize"
        case .grid: return "Grid"
        case .threadView: return "Thread View"
        case .zoomFit: return "Fit hoop"
        case .zoomBoxTool: return "Zoom box"
        case .zoomActual: return "Real size"
        default: return command.title
        }
    }
}

/// The reference picture's row in the sewing order. The objects listed above it are drawn under the picture and the
/// ones below it on top; its arrows move it past one step (or one group). It's only how the canvas draws: it never sews.
struct PictureRow: View {
    @ObservedObject var state: EditorState
    var compact = false   // the Pro table's tighter rows
    var body: some View {
        let layer = state.design.artworkLayer, count = state.design.objects.count
        HStack(spacing: 6) {
            Image(systemName: "photo").font(.system(size: compact ? 10 : 12)).foregroundStyle(Theme.inkSecondary)
            Text("Reference image").font(Theme.body(compact ? 11 : 12, weight: .semibold)).lineLimit(1)
            if state.design.artwork?.visible == false { Image(systemName: "eye.slash").font(.caption2).help("Hidden") }
            Spacer(minLength: 0)
            arrow("chevron.up", step: -1, enabled: layer > 0)
            arrow("chevron.down", step: 1, enabled: layer < count)
        }
        .padding(.horizontal, compact ? 4 : 10).padding(.vertical, compact ? 3 : 6)
        .overlay(RoundedRectangle(cornerRadius: compact ? 4 : 10).strokeBorder(Theme.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .help("Objects above this row are drawn under the reference image, the ones below it on top. The image is never sewn.")
    }
    private func arrow(_ symbol: String, step: Int, enabled: Bool) -> some View {
        Button {
            state.edit("Move Reference Image") { $0.moveArtwork(by: step) }
            let layer = state.design.artworkLayer
            state.status = layer == 0 ? "The reference image is under everything." : "The reference image is drawn over step\(layer == 1 ? " 1" : "s 1–\(layer)")."
        } label: { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
        .buttonStyle(.borderless).disabled(!enabled || state.hasVersionMismatch)
        .help(step < 0 ? "Move up: the step above goes over the image" : "Move down: the step below goes under the image")
    }
}

struct ObjectPanel: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// The object whose name is being typed over (after a double-click), if any.
    @State private var renaming: UUID?
    /// Where dragged objects would land (a sewing order index), while a drag is over the list.
    @State private var dropTarget: Int?
    var body: some View {
        if preferences.isPro { ProSewingOrder(state: state) } else { steps }
    }
    /// The Guided view's sewing order: numbered steps joined by a dashed thread.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The panel's tab already says "Sewing order"; this line adds the count and how to read the list.
            HStack(alignment: .firstTextBaseline) {
                Text("The machine sews from step 1 down.").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text("\(sewingSteps.count)").font(Theme.body(11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    let labels = state.design.groupLabels
                    let pictureAt = state.design.artwork == nil ? nil : Optional(state.design.artworkLayer)
                    let entries = sewingSteps
                    ForEach(Array(entries.enumerated()), id: \.element.first.id) { number, step in
                        // The picture shows before the first step at or after its place (never inside lettering).
                        if pictureAt.map({ $0 <= step.index && (number == 0 || $0 > entries[number - 1].index) }) == true { PictureRow(state: state).padding(.leading, 36).padding(.bottom, 8) }
                        // Lettering drags all its letters; another object drags its whole group, as clicking it selects.
                        let ids = step.lettering.map { spec in Set(state.design.objects.filter { $0.lettering?.id == spec.id }.map(\.id)) } ?? state.design.groupMembers(of: step.first.id)
                        stepRow(number: number + 1, object: step.first, isLast: number == entries.count - 1, groupLabel: step.first.groupID.flatMap { labels[$0] }, lettering: step.lettering)
                            .sewingOrderRow(state: state, ids: ids, place: step.index, target: $dropTarget)
                    }
                    if pictureAt == state.design.objects.count { PictureRow(state: state).padding(.leading, 36).padding(.top, state.design.objects.isEmpty ? 0 : 8) }
                    if !state.design.objects.isEmpty { Color.clear.sewingOrderEnd(state: state, target: $dropTarget) }
                    if state.design.objects.isEmpty { Text("Your paths will appear here in sewing order.").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).padding(.vertical, 28) }
                }
            }
            .frame(maxHeight: .infinity)   // the list takes all the room the panel has
            HStack {
                icon(.earlier, "arrow.up"); icon(.later, "arrow.down"); icon(.sequenceByColor, "paintpalette"); Spacer(); icon(.duplicate, "plus.square.on.square"); icon(.delete, "trash")
            }
        }
        .foregroundStyle(Theme.ink)
    }
    /// The steps the list shows, in sewing order: each object on its own, except lettering, which is one step
    /// (its consecutive letters together). `index` is the first object's place in the sewing order.
    private var sewingSteps: [(index: Int, first: RunObject, lettering: LetteringSpec?)] {
        var steps: [(index: Int, first: RunObject, lettering: LetteringSpec?)] = []
        for (index, object) in state.design.objects.enumerated() {
            if let spec = object.lettering, let last = steps.last, last.lettering?.id == spec.id, index > 0, state.design.objects[index - 1].lettering?.id == spec.id { continue }
            steps.append((index, object, object.lettering))
        }
        return steps
    }
    /// One sewing step: a numbered dot in the object's thread color, a dashed "thread" leading to the next step,
    /// and a card with the object's name and details (for lettering, its text and font). Clicking selects it
    /// (Shift-click selects a range, ⌘-click adds one); double-clicking the name renames it (not lettering, which
    /// shows its text).
    private func stepRow(number: Int, object: RunObject, isLast: Bool, groupLabel: String?, lettering: LetteringSpec?) -> some View {
        let selected = state.selection.contains(object.id)
        let font = lettering.map { $0.fontKind == .embroidery ? EmbroideryFontLibrary.font($0.font)?.name ?? $0.font : NSFont(name: $0.font, size: 12)?.displayName ?? $0.font }
        let details = object.kind == .raw
            ? "Imported · \(object.rawStitches?.commands.filter { $0.op == .stitch }.count ?? 0) stitches"
            : font.map { "Lettering · \($0) · \(object.color.name)" } ?? "\(object.stitchTitle) · \(object.color.name) · \(object.nodes.count) nodes"
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text("\(number)").font(Theme.body(11, weight: .bold))
                    .foregroundStyle(isLightThread(object.color.hex) ? Color.black.opacity(0.75) : Color.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(nsColor: object.color.nsColor)))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.18)))
                if !isLast { ThreadLine().stroke(Theme.controlBorder, style: StrokeStyle(lineWidth: 2, dash: [4, 3])).frame(width: 2) }
            }
            .frame(width: 26)
            Button { state.listClick(object.id) } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(lettering.map { "“\($0.lines.joined(separator: " / "))”" } ?? object.name).font(Theme.body(12, weight: .semibold)).lineLimit(1)
                            if let groupLabel, lettering == nil {
                                Text(groupLabel).font(Theme.body(9, weight: .bold)).lineLimit(1).fixedSize()
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent)
                            }
                        }
                        Text(details).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if object.locked { Image(systemName: "lock.fill").font(.caption2).help("Locked") }
                    if !object.visible { Image(systemName: "eye.slash").font(.caption2).help("Hidden while editing; still sews") }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(selected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { if lettering == nil { renaming = object.id } })
            .overlay(alignment: .topLeading) {
                // The rename box sits over the name line while typing.
                if renaming == object.id {
                    RenameField(state: state, object: object, font: Theme.body(12, weight: .semibold),
                                editing: Binding(get: { renaming == object.id }, set: { if !$0 { renaming = nil } }))
                        .padding(.leading, 5).padding(.trailing, 8).padding(.top, 3)
                }
            }
            .help(lettering == nil ? "Double-click the name to rename it. Drag to change when it sews." : "Drag to change when it sews.")
            .padding(.bottom, isLast ? 0 : 8)
        }
        // fixedSize lets the dashed line stretch exactly to the height of its row instead of growing without limit.
        .fixedSize(horizontal: false, vertical: true)
    }
    /// True for pale threads (ivory, gold) where a white step number would be hard to read.
    private func isLightThread(_ hex: Int) -> Bool {
        let red = Double((hex >> 16) & 255), green = Double((hex >> 8) & 255), blue = Double(hex & 255)
        return (0.299 * red + 0.587 * green + 0.114 * blue) / 255 > 0.6   // perceived brightness, 0 (black) to 1 (white)
    }
    private func icon(_ command: CommandID, _ symbol: String) -> some View {
        Button { AppDelegate.shared.perform(command) } label: { Image(systemName: symbol) }.buttonStyle(.borderless).help(Preferences.shared.hint(command))
    }
}

/// A straight vertical line down the middle of its frame; drawn dashed, it is the "thread" joining sewing steps.
struct ThreadLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
    }
}

/// A native property field commits once and restores canvas focus; invalid input stays editable.
struct NumberField: NSViewRepresentable {
    var value: Double
    var identifier = ""
    var range: ClosedRange<Double>
    /// For lengths: the unit the field shows and takes. `value`, `range` and what's committed stay in millimeters.
    var unit: LengthUnit? = nil
    var commit: (Double) -> Void
    var focusCanvas: () -> Void
    /// The value as the field shows it, with two decimals (in `unit` for a length).
    var text: String { String(format: "%.2f", unit?.shown(value) ?? value) }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let view = NSTextField(string: text)
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.delegate = context.coordinator; view.alignment = .right; view.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        return view
    }
    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.parent = self
        if view.currentEditor() == nil { view.stringValue = text }
    }
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumberField
        var cancel = false
        init(_ parent: NumberField) { self.parent = parent }
        /// The typed value (in millimeters for a length), or nil, colored red, if it isn't a number in range.
        func valid(_ field: NSTextField) -> Double? {
            guard let typed = Double(field.stringValue), typed.isFinite else { field.textColor = .systemRed; return nil }
            let number = parent.unit?.millimeters(typed) ?? typed
            guard parent.range.contains(number) else { field.textColor = .systemRed; return nil }
            field.textColor = .labelColor; return number
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                guard let number = valid(field) else { NSSound.beep(); return true }
                // Return commits once: `cancel` stops the end-of-editing commit that follows when focus moves on,
                // which would repeat actions such as "rotate by".
                parent.commit(number); cancel = true; parent.focusCanvas(); return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                cancel = true; field.stringValue = parent.text; parent.focusCanvas(); return true
            }
            return false
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            defer { cancel = false }
            guard !cancel, let field = notification.object as? NSTextField, let number = valid(field) else { return }
            // Only a changed number commits. It's compared with what the field showed, so the rounding of a shown
            // length (100 mm shows as 3.94 in) never changes the design when you just pass through the field.
            if Double(field.stringValue) != Double(parent.text) { parent.commit(number) }
        }
    }
}

/// The three dockable panels drawn by InspectorPanel.
enum InspectorSection { case properties, design, reference }

struct InspectorPanel: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// Which part this panel shows: the selected object's properties, the design (fabric and sewing area), or the
    /// reference image. Each is its own dockable panel.
    var section: InspectorSection = .properties
    /// A fabric just picked while the design has shapes it would change: the alert asks whether to update them.
    @State private var pendingFabric: (fabric: FabricType, shapes: Int)?
    /// True while the lettering section's Font credits popover is open.
    @State var showFontCredits = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: pro ? 7 : 12) {
                switch section {
                case .properties: propertiesSection
                case .design: designSection
                case .reference: referenceSection
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .alert(pendingFabric.map { "Update \($0.shapes) shape\($0.shapes == 1 ? "" : "s") to \($0.fabric.title) settings?" } ?? "",
               isPresented: Binding(get: { pendingFabric != nil }, set: { if !$0 { pendingFabric = nil } })) {
            Button("Update Shapes") { if let pending = pendingFabric { setFabric(pending.fabric, updateShapes: true) } }
            Button("Keep Their Settings") { if let pending = pendingFabric { setFabric(pending.fabric, updateShapes: false) } }
            Button("Cancel", role: .cancel) { pendingFabric = nil }
        } message: {
            Text("This changes the fills' and satins' density, pull compensation and underlay to suit the fabric. Lettering, running lines and appliqué tack-downs keep theirs. New shapes use the fabric's settings either way, and Undo puts everything back.")
        }
    }
    /// The Fabric type menu: what the design will be sewn on, with the stabilizer to use.
    @ViewBuilder private var fabricTypePicker: some View {
        let fabric = state.design.fabric
        Picker("Fabric type", selection: Binding(get: { fabric }, set: { chooseFabric($0) })) {
            ForEach(FabricType.allCases, id: \.self) { Text($0.title).tag($0) }
        }.font(Theme.body(12, weight: .semibold))
        .help("What you'll sew on. It sets starting density, pull compensation and underlay for fills and satins.")
        // The stabilizer matters in both views, so it's always shown; Guided adds what the fabric covers.
        Text(fabric.stabilizer).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        explain("For \(fabric.examples). These are starting values; a test sew-out tells you if they need adjusting.")
    }
    /// Picking a fabric: if shapes would change, ask first; otherwise just switch.
    private func chooseFabric(_ fabric: FabricType) {
        guard fabric != state.design.fabric else { return }
        var preview = state.design; preview.fabricType = fabric
        let shapes = preview.shapesNeedingFabric
        if shapes > 0 { pendingFabric = (fabric, shapes) } else { setFabric(fabric, updateShapes: false) }
    }
    /// Sets the design's fabric (and, if asked, its shapes' settings) as one step you can undo.
    private func setFabric(_ fabric: FabricType, updateShapes: Bool) {
        var changed = 0
        state.edit("Fabric Type") { design in design.fabricType = fabric; if updateShapes { changed = design.applyFabricToAll() } }
        state.status = "Fabric: \(fabric.title)." + (updateShapes ? " Updated \(changed) shape\(changed == 1 ? "" : "s")." : " New shapes will use its settings.")
        pendingFabric = nil
    }
    /// For a monogram's parts: what it is, and a button to change it.
    func monogramSummary(_ monogram: MonogramSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Monogram “\(monogram.initials)”", systemImage: CommandID.addMonogram.symbol).font(Theme.body(13, weight: .semibold)).lineLimit(1)
            if !pro { explain("\(monogram.layout.title) · \(preferences.unit.short(monogram.height)) · border: \(monogram.border.title.lowercased()). Double-click it on the canvas to change it.") }
            Button("Edit monogram…") { AppDelegate.shared.perform(.editMonogram) }.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.editMonogram))
        }
    }
    /// True when the selection is exactly one piece of lettering (all its letters): Properties then shows it as one
    /// object, not as a group of shapes.
    var selectionIsOneLettering: Bool { state.selectedLettering != nil }
    /// The heading Properties gives `object`: lettering's text, otherwise the object's name.
    func heading(_ object: RunObject) -> String { object.lettering.map { "“\($0.lines.joined(separator: " / "))”" } ?? object.name }
    /// What `object` is, under its heading: "Lettering · Helvetica Bold" for lettering, otherwise its stitch type.
    func detail(_ object: RunObject) -> String {
        guard let spec = object.lettering else { return object.stitchTitle }
        let font = spec.fontKind == .embroidery ? EmbroideryFontLibrary.font(spec.font)?.name ?? spec.font : NSFont(name: spec.font, size: 12)?.displayName ?? spec.font
        return "Lettering · \(font)"
    }
    /// True in the Pro view: every setting shown at once, compact, with explanations as tooltips instead of text.
    var pro: Bool { preferences.isPro }
    @ViewBuilder private var propertiesSection: some View {
        ToolOptions(state: state)   // the current tool's choices, such as the next shape's (ToolOptions.swift)
        if pro, let object = state.selected {
            proProperties(object)   // the compact Pro layout (ProViews.swift)
        } else if let object = state.selected {
            if state.selection.count > 1 && !selectionIsOneLettering { selectionSummary }
            VStack(alignment: .leading, spacing: 2) {
                // One object (not lettering, which shows its text): click its name to rename it.
                if object.lettering == nil && state.selection.count == 1 {
                    ClickToRename(state: state, object: object, font: Theme.heading(18), lineLimit: 2).id(object.id)
                } else {
                    Text(heading(object)).font(Theme.heading(18)).lineLimit(2)
                }
                Text(object.kind == .raw ? object.kind.title : "\(detail(object)) · \(object.color.name) thread").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            }
            if object.stitchEdits != nil { stitchEditNotice(object) }
            if let lettering = object.lettering { letteringEditor(lettering) }
            if let monogram = object.monogram { monogramSummary(monogram) }
            if object.kind == .run || object.kind == .satin || object.kind == .fill { closeUp(object) }
            if object.kind == .fill {
                let style=object.settings.fillStyle ?? .tatami
                Picker("Fill style",selection:Binding(get:{style},set:{value in settings(.fill,"Fill Style"){$0.fillStyle=value == .tatami ? nil:value}})){
                    ForEach(FillStyle.allCases,id:\.self){Text($0.title).tag($0)}
                }.font(Theme.body(12, weight: .semibold)).help(style.summary)
                explain(style.summary)
                // Only where the rows follow it (with stitch angle lines, or for contour, radial and guided fills, it
                // turns just the underlay: see Underlay angle below).
                if StitchAngleLine.applies(to: object) {
                    number("Fill angle °",value:object.settings.angle,id:"fillAngle",range:-180...180,help:"The direction the fill rows run."){value in settings(.fill,"Fill Angle"){$0.angle=value}}
                }
                if style == .tatami || style == .satin { stitchAngles(object) }
                if style == .wave {
                    let waveHelp = "How far each ripple rises and falls (mm, crest to trough), and the distance from one crest to the next. Tall, short waves pack the rows closer on their slopes."
                    number("Wave height",value:object.settings.waveHeight ?? DigitizingSettings.defaultWaveHeight,range:DigitizingSettings.waveHeightRange,hover:waveHelp){value in settings(.fill,"Wave Height"){$0.waveHeight=value}}
                    number("Wave length",value:object.settings.waveLength ?? DigitizingSettings.defaultWaveLength,range:DigitizingSettings.waveLengthRange,help:waveHelp){value in settings(.fill,"Wave Length"){$0.waveLength=value}}
                }
                patternSettings(object)
                if style == .radial {
                    explain("Drag the Center dot on the canvas to move the point the stitches fan out from.")
                    if object.settings.radialCenter != nil {Button("Center in the shape"){settings(.fill,"Reset Radial Center"){$0.radialCenter=nil}}.buttonStyle(ThemedButtonStyle()).help("Move the radial center back to the middle of the shape")}
                }
            }
            // Not for zigzag lines or cross stitch fills: their own sizes set their stitches.
            if (object.kind == .fill && (object.settings.fillStyle ?? .tatami).usesStitchLength) || (object.kind == .run && (object.settings.runStyle ?? .running).usesStitchLength) {
                number("Stitch length", value: object.stitchLength, id: "stitchLength", range: 0.3...10, help: object.kind == .fill ? fillStitchLengthHelp(object) : "How far the needle moves per stitch. Shorter stitches follow curves more closely.") { value in state.editSelected("Stitch Length") { $0.stitchLength = value } }
            }
            // A guide line only steers its fill or lettering: no satin column, closing or border for it.
            if SatinLine.canConvert(object) && object.guideFor == nil { satinLine(object) }
            if object.kind == .run {
                runStyle(object)
                if (object.settings.runStyle ?? .running) == .running {
                    runPasses(object)
                    explain("Bean stitch sews each stitch forward, back and forward again for a bold outline. Stitch lengths of 2.5–3.5 mm suit it.")
                }
            }
            if (object.kind == .run || object.kind == .vector) && object.guideFor == nil {toggle("Closed path", value: object.closed) { _ in AppDelegate.shared.perform(.closePath) }.help(preferences.hint(.closePath))}
            if SatinBorder.canBorder(object) {
                Button("Add satin border…") { AppDelegate.shared.perform(.satinBorder) }.buttonStyle(ThemedButtonStyle())
                    .help("A satin column around this shape's outside edge, like the finished edge of a patch")
                Button("Make appliqué…") { AppDelegate.shared.perform(.applique) }.buttonStyle(ThemedButtonStyle())
                    .help("Sew a piece of fabric in this shape: placement line, tack-down and a satin edge, with stops to lay and trim the fabric")
            }
            if object.kind == .raw {
                explain("Existing stitches: move, rotate, mirror or recolor this thread block. Scaling changes density and stitch lengths; it does not regenerate stitches. Node editing and stitch-type conversion are unavailable.")
            }
            if object.kind == .vector, let fill = object.guideFor.flatMap({ id in state.design.objects.first { $0.id == id } }) {
                explain("This dashed line guides the fill “\(fill.name)”: its rows follow it. It doesn't sew. Reshape it with Edit Nodes and the rows follow. Running Stitch turns it back into a line that sews.")
                Button("Running Stitch"){AppDelegate.shared.perform(.convertRun)}.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.convertRun))
            } else if object.kind == .vector {
                explain("This outline does not sew until you assign stitches. Satin requires manually drawn edge pairs.")
                HStack{Button("Running Stitch"){AppDelegate.shared.perform(.convertRun)}.help(preferences.hint(.convertRun));Button("Tatami Fill"){AppDelegate.shared.perform(.convertFill)}.help(preferences.hint(.convertFill))}.buttonStyle(ThemedButtonStyle())
            }
            // Fill styles with a spacing of their own (no Row spacing), and the open, decorative ones (no underlay).
            let ownSpacing = object.kind == .fill && [.stipple, .motif, .crossStitch, .gradient].contains(object.settings.fillStyle ?? .tatami)
            let noUnderlay = object.kind == .fill && [.stipple, .motif, .crossStitch].contains(object.settings.fillStyle ?? .tatami)
            if object.kind == .satin || object.kind == .fill {
                if object.kind == .satin { satinWidth(object) }
                if !ownSpacing { number("Row spacing",value:object.settings.spacing,id:"rowSpacing",range:object.kind == .fill ? 0.15...10:0.15...5,help:object.settings.rowSpacingHelp){value in settings(object.kind,"Row Spacing"){$0.spacing=value}} }
                if object.kind == .fill {
                    HStack{Button("Add hole"){AppDelegate.shared.perform(.holeTool)}.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.holeTool));Text(ProStats.count(object.holes?.count ?? 0, "hole")).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)}
                    if !(object.holes ?? []).isEmpty {Button("Remove all holes"){AppDelegate.shared.perform(.removeHoles)}.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.removeHoles))}
                    cutOutToggle(object)
                    explain("Leaves out the part of this fill that shapes sewn after it cover, so it isn't stitched twice. The fill still reaches 1 mm under their edges so no gap shows.")
                }
                sectionDivider
                if noUnderlay { explain("\(object.settings.fillStyle?.title ?? "This") fill sews without underlay.") } else {
                Picker("Underlay",selection:Binding(get:{object.settings.underlay},set:{value in settings(object.kind,"Underlay"){$0.underlay=value}})){
                    ForEach(object.kind == .fill ? [UnderlayStyle.none,.edge,.edgeAndSparse]:[.auto,.none,.center,.edge,.zigzag],id:\.self){style in Text(style.title).tag(style)}
                }.font(Theme.body(12, weight: .semibold)).help("A quick first layer under the stitches. It holds the fabric still so the top stitches lie smooth.")
                if StitchAngleLine.steersOnlyUnderlay(object) {
                    number("Underlay angle °",value:object.settings.angle,id:"fillAngle",range:-180...180,help:"The direction of the sparse underlay rows. This fill's own stitches don't follow an angle, so it only turns the underlay."){value in settings(.fill,"Underlay Angle"){$0.angle=value}}
                }
                explain(object.settings.underlay == .auto ? "Auto picks from the satin's average width: a center run under 2 mm, an edge run up to 4 mm, an edge run then a zigzag above that (from 2 mm on knit and towel). It updates as you reshape the satin." : "A quick first layer under the stitches. It holds the fabric still so the top stitches lie smooth.")
                }
            }
            if object.kind != .vector { moreSettings(object) }
            sectionDivider
            SectionLabel(title: "Arrange")
            HStack {
                Button("Mirror") { AppDelegate.shared.perform(.mirrorH) }.help(preferences.hint(.mirrorH))
                Button("Rotate 90°") { AppDelegate.shared.perform(.rotateRight) }.help(preferences.hint(.rotateRight))
            }.buttonStyle(ThemedButtonStyle())
            HStack { Button(object.locked ? "Unlock" : "Lock") { AppDelegate.shared.perform(.lockObject) }.help(preferences.hint(.lockObject)); Button(object.visible ? "Hide" : "Show") { AppDelegate.shared.perform(.hideObject) }.help(preferences.hint(.hideObject)) }.buttonStyle(ThemedButtonStyle())
            Button("Rename…"){AppDelegate.shared.perform(.renameObject)}.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.renameObject))
            if let box = state.design.bounds(of: state.editableSelection) {
                let width = box.max.x - box.min.x, height = box.max.y - box.min.y
                if width>0.001{number("Object width",value:width,range:0.1...1000, length: true, hover:"How wide the selection is. Type a new width and press Return to resize it; the height follows."){state.resizeSelection(width:$0)}}
                if height>0.001{number("Object height",value:height,range:0.1...1000, length: true, hover:"How tall the selection is. Type a new height and press Return to resize it; the width follows."){state.resizeSelection(height:$0)}}
                // Exact placement, folded with the other extras.
                if preferences.data.guidedMoreOpen ?? false {
                    number("Center X", value: (box.min.x + box.max.x) / 2, range: -1000...1000, length: true, help: "Where the selection's center sits, from the hoop's center.") { state.moveSelection(centerX: $0) }
                    number("Center Y", value: (box.min.y + box.max.y) / 2, range: -1000...1000, length: true, hover: "Where the selection's center sits, above the hoop's center (below is negative).") { state.moveSelection(centerY: $0) }
                    number("Rotate by °", value: 0, range: -360...360, help: "Type an angle and press Return to turn the selection by it (positive turns counterclockwise).") { state.rotateSelection(by: $0) }
                    number("Skew by °", value: 0, range: -60...60, help: "Type an angle and press Return to lean the selection sideways by it (positive leans the top to the right, like italics).") { state.skewSelection(by: $0) }
                }
            }
            if preferences.data.guidedMoreOpen ?? false {
                number("Nudge distance", value: preferences.nudge, range: Preferences.nudgeRange, length: true, help: "How far the arrow keys move the selection.") { value in preferences.data.nudgeDistance = value; preferences.save() }
            }
            explain(object.kind == .raw ? "V moves stitch blocks. Use the thread palette to recolor the selection." : "V moves objects. N edits nodes: drag a node's handles to shape its curve, Option-drag to move one side of a smooth node. Secondary-click switches corner and smooth. \(preferences.label(.insertNode)) inserts near the pointer; Delete removes the selected node (a pair for satin).")
        } else if !NextShapeOptions.shows(state.tool) {
            Text("Nothing selected").font(Theme.heading(16))
            explain("Click an object on the canvas or in the sewing order to edit its stitches here.")
        }
    }
    /// The settings most people leave alone: underlay detail, compensation, finishing and start & end. The Guided
    /// view folds them under "More settings", remembering whether it was left open. (Pro shows them in its own layout.)
    @ViewBuilder private func moreSettings(_ object: RunObject) -> some View {
        let open = preferences.data.guidedMoreOpen ?? false
        Button {
            preferences.data.guidedMoreOpen = !open; preferences.save()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(open ? "Fewer settings" : "More settings").font(Theme.body(12, weight: .bold))
                    if !open { Text(object.kind == .raw ? "Trim and stop, exact position" : "Underlay detail, compensation, finishing, start & end, exact position").font(Theme.body(10)).foregroundStyle(Theme.inkSecondary) }
                }
                Spacer()
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .padding(.top, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
        .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
        .help(open ? "Fold away the extra settings" : "Show the settings most people leave alone: underlay detail, compensation, finishing, start & end and exact position")
        .accessibilityLabel(open ? "Fewer settings" : "More settings")
        if open {
            if object.kind == .satin || object.kind == .fill {
                if object.settings.underlay != .none {
                    if object.kind == .satin && object.settings.underlay != .auto {
                        Picker("Second underlay",selection:Binding(get:{object.settings.secondUnderlay ?? UnderlayStyle.none},set:{value in settings(.satin,"Second Underlay"){$0.secondUnderlay=value == UnderlayStyle.none ? nil:value}})){
                            ForEach([UnderlayStyle.none,.center,.edge,.zigzag].filter{$0 != object.settings.underlay},id:\.self){style in Text(style.title).tag(style)}
                        }.help("Sewn after the first underlay, back along the column. Common pairs: center run then zigzag, or edge run then zigzag for wide satins.")
                        explain("Sewn after the first underlay, back along the column. Common pairs: center run then zigzag, or edge run then zigzag for wide satins.")
                    }
                    if object.settings.usesUnderlayInset {number("Underlay inset",value:object.settings.inset,range:0...3,help:"How far inside the edge the underlay runs."){value in settings(object.kind,"Underlay Inset"){$0.inset=value}}}
                    // Only underlay with rows to space (not an edge run alone).
                    if object.settings.usesUnderlaySpacing(object.kind) {number("Underlay spacing",value:object.settings.underlaySpacing,range:0.5...5,help:"Gap between the underlay's rows."){value in settings(object.kind,"Underlay Spacing"){$0.underlaySpacing=value}}}
                }
                number(object.kind == .fill ? "Fill expansion":"Compensation / side",value:object.settings.expansion,range:0...2,help:object.kind == .fill ? "Grows the fill past its outline by this much, because thread pulls fabric inward as it sews." : "Thread pulls fabric inward as it sews. A little extra width on each side keeps the column the size you drew."){value in settings(object.kind,"Compensation"){$0.expansion=value}}
                if object.kind == .satin {
                    number("Compensation % of width",value:object.settings.pullPercent ?? 0,range:DigitizingSettings.pullPercentRange,help:"Extra compensation for each stitch, as a share of its width, on top of the amount above, so wide parts of the satin get more. 3% is a starting value to tune after a test sew-out."){value in settings(.satin,"Compensation % of Width"){$0.pullPercent=value}}
                    number("Maximum stitch",value:object.settings.maximumSatin,range:1...10,help:"The longest satin stitch allowed. With Split wide satin on, longer stitches are split; otherwise wider columns are refused."){value in settings(.satin,"Satin Limit"){$0.maximumSatin=value}}
                    satinOptions(object)
                }
            }
            sectionDivider
            SectionLabel(title: "Finishing")
            let finishingHelp = (object.kind == .raw ? "" : "Ties are tiny locking stitches so the thread can't unravel. ") + "Trim cuts the thread before the next part (When far: only if it starts \(preferences.unit.short(state.design.trimDistance ?? Design.defaultTrimDistance)) or more away); Stop pauses the machine."
            if object.kind != .raw {
                toggle("Tie in", value: object.tieIn) { _ in AppDelegate.shared.perform(.tieIn) }.help(finishingHelp)
                toggle("Tie off", value: object.tieOut) { _ in AppDelegate.shared.perform(.tieOut) }.help(finishingHelp)
            }
            trimMenu(object).help(finishingHelp)
            toggle("Stop after", value: object.stopAfter) { _ in AppDelegate.shared.perform(.stopAfter) }.help(finishingHelp)
            explain(finishingHelp)
            explain("PES encodes travel moves after the first as trim/jumps. Separate trim requests may be omitted; your machine decides whether to cut.")
            if object.kind == .run || object.kind == .satin || object.kind == .fill {
                sectionDivider
                SectionLabel(title: "Start & end")
                HStack {
                    Text("Start: \(object.entry == nil ? "automatic" : "set") · End: \(object.exit == nil ? "automatic" : "set")").font(Theme.body(12, weight: .semibold))
                    Spacer()
                }.help(startEndHelp(object))
                if let entry = object.entry { pointFields("Start", entry, object: object.id) { $0.entry = $1 } }
                if let exit = object.exit { pointFields("End", exit, object: object.id) { $0.exit = $1 } }
                explain(startEndHelp(object))
                HStack {
                    Button("Set…") { AppDelegate.shared.perform(.entryExitTool) }.help(startEndHelp(object))
                    if object.entry != nil || object.exit != nil { Button("Clear start & end") { AppDelegate.shared.perform(.clearStartEnd) }.help(preferences.hint(.clearStartEnd)) }
                    Button("Auto for all") { AppDelegate.shared.perform(.autoStartPoints) }.help("Start every object where the previous one ends, to shorten travel")
                }.buttonStyle(ThemedButtonStyle())
            }
        }
    }
    @ViewBuilder private var designSection: some View {
        SectionLabel(title: "Fabric")
        fabricTypePicker
        fabricPicker
        explain("The cloth shown in the hoop for this design. Preview only: it never changes your stitches or exports.")
        sectionDivider
        SectionLabel(title: "Sewing area")
        hoopMenu
        explain("Pick the hoop your machine uses: stitches must stay inside its dashed line. Typing your own width or height makes it a custom size. New designs start with the hoop you picked last.")
        let hoop = state.design.hoop
        number("Width", value: hoop.width, range: 1...1000, length: true, hover: "The sewing area's width. Typing your own makes it a custom size.") { value in setHoop(Hoop(width: value, height: hoop.height, oval: hoop.oval), "Hoop Width") }
        number("Height", value: hoop.height, range: 1...1000, length: true, hover: "The sewing area's height. Typing your own makes it a custom size.") { value in setHoop(Hoop(width: hoop.width, height: value, oval: hoop.oval), "Hoop Height") }
        Button { setHoop(hoop.turned, "Turn Hoop") } label: { Label("Turn sideways", systemImage: "rotate.right") }
            .buttonStyle(ThemedButtonStyle()).disabled(hoop.width == hoop.height)
            .help("Swap width and height, for a hoop mounted with its long side left to right")
        toggle("Oval sewing area", value: hoop.oval) { value in setHoop(Hoop(width: hoop.width, height: hoop.height, oval: value), "Hoop Shape") }
            .help("For a hoop whose sewing area is an oval: stitches must stay inside the oval, not just the rectangle.")
        sectionDivider
        SectionLabel(title: "Holding the fabric")
        toggle("Basting box", value: state.design.basting != nil) { on in state.edit("Basting Box") { $0.basting = on ? 5 : nil } }
            .help("Long running stitches around the design, sewn first, that hold the fabric to the stabilizer. Pull them out after sewing.")
        if let margin = state.design.basting {
            number("Margin", value: margin, range: Design.bastingMargins, length: true, help: "How far outside the design the basting box runs.") { value in state.edit("Basting Margin") { $0.basting = value } }
        }
        explain("Long running stitches around the design, sewn first in its first thread, that hold the fabric to the stabilizer. Pull them out after sewing.")
        Button { AppDelegate.shared.perform(.laydown) } label: { Label("Add laydown…", systemImage: CommandID.laydown.symbol) }
            .buttonStyle(ThemedButtonStyle()).help(preferences.hint(.laydown))
        explain("A light, open fill under the design (or the selection) that flattens the pile of towels, fleece and velvet.")
        sectionDivider
        SectionLabel(title: "Trims")
        number("Trim jumps of at least", value: state.design.trimDistance ?? Design.defaultTrimDistance, range: Design.trimDistances, length: true,
               help: "Objects whose Trim after is When far cut the thread only when the next part starts this far away or more.") { value in
            state.edit("Trim Distance") { $0.trimDistance = value == Design.defaultTrimDistance ? nil : value }
        }
        explain("For objects whose Trim after is When far. Closer than this, one plain stitch carries the thread across instead of a tie-off and trim.")
        if state.hasVersionMismatch {
            Text("This project uses an older stitch engine. Its saved preview is preserved.").font(Theme.body(11)).foregroundStyle(.orange)
            Button("Regenerate with current engine") { var next = state.design; next.engineVersion = Design.engineVersion; state.document?.replace(next, action: "Regenerate Project") }.buttonStyle(ThemedButtonStyle(prominent: true))
                .help("Work out this older project's stitches again with the current stitch engine, so you can edit it. The stitches may change slightly.")
        }
        if let error = state.generationError { Text(error).font(Theme.body(11)).foregroundStyle(.red) }
        ForEach(state.plan.warnings, id: \.self) { warning in Label(warning, systemImage: "exclamationmark.circle").font(Theme.body(11)).foregroundStyle(.orange) }
    }
    /// The Trim after menu: Off, Always, or When far (showing the design's trim distance), for every selected object.
    func trimMenu(_ object: RunObject) -> some View {
        let distance = preferences.unit.short(state.design.trimDistance ?? Design.defaultTrimDistance)
        return Picker("Trim after", selection: Binding(get: { object.trimRule }, set: { rule in state.editSelected("Trim After") { $0.trimRule = rule } })) {
            ForEach(TrimRule.allCases, id: \.self) { rule in Text(rule == .whenFar ? "When far (\(distance))" : rule.title).tag(rule) }
        }.font(Theme.body(12, weight: .semibold))
    }
    /// The hoop menu: the common hoops grouped by brand. Its button shows the current hoop, e.g. "Brother 5 × 7 in · 130 × 180 mm".
    private var hoopMenu: some View {
        Menu {
            ForEach(HoopPreset.brands, id: \.self) { brand in
                Section(brand) {
                    ForEach(HoopPreset.all.filter { $0.brand == brand }) { preset in Button(preset.menuTitle) { setHoop(preset.hoop, "Choose Hoop") } }
                }
            }
        } label: { Text(state.design.hoop.label).font(Theme.body(12, weight: .semibold)) }
        .help("Choose your machine's hoop")
    }
    /// Changes the design's hoop (one undoable step), remembers it for new designs (unless a hoop for them is picked
    /// in Settings), and zooms to show the whole hoop.
    private func setHoop(_ hoop: Hoop, _ action: String) {
        state.edit(action) { $0.hoop = hoop }
        preferences.rememberHoop(hoop)
        state.canvas?.fit()
    }
    @ViewBuilder private var referenceSection: some View {
        if let artwork = state.design.artwork {
            Text(artwork.name).font(Theme.body(11)).lineLimit(1)
            Button { AppDelegate.shared.perform(.artworkTool) } label: { Label("Move & size on canvas", systemImage: "photo") }
                .buttonStyle(ThemedButtonStyle(prominent: state.tool == .artwork)).help("Drag the image and its corners on the canvas (\(preferences.label(.artworkTool)))")
            opacitySlider(artwork.opacity)
            number("Width", value: artwork.width, range: 0.1...1000, length: true, hover: "The reference image's width; its height follows.") { value in state.edit("Scale Artwork") { design in design.artwork?.width = value; design.artwork?.height = artwork.height * value / artwork.width } }
            number("Center X", value: artwork.center.x, range: -1000...1000, length: true, hover: "Where the image's center sits, right of the hoop's center (left is negative).") { value in state.edit("Move Artwork") { $0.artwork?.center.x = value } }
            number("Center Y", value: artwork.center.y, range: -1000...1000, length: true, hover: "Where the image's center sits, above the hoop's center (below is negative).") { value in state.edit("Move Artwork") { $0.artwork?.center.y = value } }
            toggle("Show reference", value: artwork.visible) { _ in AppDelegate.shared.perform(.artwork) }.help(preferences.hint(.artwork))
            Button { AppDelegate.shared.perform(.autoDigitize) } label: { Label("Auto-digitize…", systemImage: "wand.and.rays") }.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.autoDigitize))
        } else {
            Text("No reference image").font(Theme.heading(16))
            explain("Import a picture of your logo or artwork to trace over or auto-digitize.")
            Button { AppDelegate.shared.perform(.importImage) } label: { Label("Import artwork…", systemImage: "photo.badge.plus") }.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.importImage))
        }
    }
    /// The artwork's opacity as a slider with a % readout. The image fades live while it's dragged; letting go saves
    /// it as one undoable step.
    private func opacitySlider(_ saved: Double) -> some View {
        let shown = state.artworkOpacityPreview ?? saved
        return HStack {
            Text("Opacity").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold))
            Slider(value: Binding(get: { shown }, set: { state.previewArtworkOpacity($0) }), in: 0...1, onEditingChanged: { state.artworkOpacitySlider(editing: $0) })
                .controlSize(pro ? .small : .regular).tint(Theme.accent)
            Text("\(Int((shown * 100).rounded()))%").font(Theme.body(pro ? 11 : 12)).monospacedDigit().frame(width: 36, alignment: .trailing)
        }
        .help("How see-through the reference image is: drag left to fade it, right to make it solid")
    }
    /// A small "close-up" box showing what the selected object's stitches look like at their current settings.
    private func closeUp(_ object: RunObject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "Close-up")
            StitchPreview(kind: object.kind, color: Color(nsColor: object.color.nsColor), spacing: object.settings.rowGap, stitchLength: object.stitchLength, angle: object.settings.angle,
                          fillStyle: object.settings.fillStyle ?? .tatami, waveHeight: object.settings.waveHeight ?? DigitizingSettings.defaultWaveHeight, waveLength: object.settings.waveLength ?? DigitizingSettings.defaultWaveLength, settings: object.settings)
                .frame(height: 44)
        }
        .padding(10)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12))
    }
    private var sectionDivider: some View { Theme.divider.frame(height: 1) }
    /// Swatches for common garment fabrics plus a custom color; the choice is saved with this design.
    private var fabricPicker: some View {
        let presets: [(name: String, hex: Int?)] = [("Natural linen", nil), ("White", 0xFFFFFF), ("Black", 0x1C1C1E), ("Navy", 0x1F2A44),
                                                     ("Heather grey", 0x9A9A9E), ("Red", 0xB3261E), ("Khaki", 0xC3B091), ("Forest", 0x2E4A33)]
        return VStack(alignment: .leading, spacing: 8) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 6)], alignment: .leading, spacing: 8) {
            ForEach(presets, id: \.name) { preset in
                let chosen = state.design.fabricColor == preset.hex
                Button { setFabric(preset.hex) } label: {
                    Circle().fill(Color(nsColor: preset.hex.map(Theme.fixed) ?? Theme.Canvas.fabric)).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Theme.controlBorder))
                        .overlay(Circle().strokeBorder(Theme.accent.opacity(chosen ? 1 : 0), lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain).help(preset.name).accessibilityLabel(preset.name).accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)   // room for the selection ring, which sits 3 points outside each swatch
        ColorPicker("Custom color", selection: Binding(get: { Color(nsColor: state.design.fabricColor.map(Theme.fixed) ?? Theme.Canvas.fabric) },
                                                       set: { setFabric(Theme.hex(of: $0)) }), supportsOpacity: false)
            .font(Theme.body(12, weight: .semibold))
            .help("Pick any color for the cloth shown in the hoop. Preview only: it never changes your stitches.")
        }
    }
    private func setFabric(_ hex: Int?) { if state.design.fabricColor != hex { state.edit("Fabric Color") { $0.fabricColor = hex } } }
    // The helpers below are shared with the Pro view's Properties layout in ProViews.swift, so they aren't private.
    /// Shown when several objects are selected: how many, which group, and a Group/Ungroup button.
    var selectionSummary: some View {
        let chosen = state.design.objects.filter { state.selection.contains($0.id) }
        let groups = Set(chosen.compactMap(\.groupID)), labels = state.design.groupLabels
        let grouped = groups.count == 1 && chosen.allSatisfy { $0.groupID != nil }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(chosen.count) objects selected" + (grouped ? groups.first.flatMap { labels[$0] }.map { " · " + $0 } ?? "" : ""))
                    .font(Theme.body(12, weight: .bold))
                Spacer()
                Button(grouped ? "Ungroup" : "Group") { AppDelegate.shared.perform(grouped ? .ungroup : .group) }.buttonStyle(ThemedButtonStyle()).help(preferences.hint(grouped ? .ungroup : .group))
            }
            HStack {
                Button("Sew in click order") { AppDelegate.shared.perform(.sequenceBySelection) }
                    .help("Sequence by Selection Order: these objects sew one after another in the order you clicked them.")
                Button("Weld") { AppDelegate.shared.perform(.weldObjects) }
                    .help("Merge these shapes into one fill, with the settings of the topmost (the one sewn last).")
                Button("Branch") { AppDelegate.shared.perform(.branching) }
                    .help("Branching: sew these one after another in one thread, travelling inside them instead of trimming.")
            }.buttonStyle(ThemedButtonStyle())
            // Align and space: objects line up with the one selected last.
            HStack(spacing: 0) {
                ForEach([CommandID.alignLeft, .alignCentersVertically, .alignRight, .alignTop, .alignCentersHorizontally, .alignBottom, .alignCenters], id: \.self) { alignButton($0) }
                Theme.controlBorder.frame(width: 1, height: 16).padding(.horizontal, 4)
                alignButton(.spaceAcross); alignButton(.spaceDown)
            }
            explain("Moving, mirroring, rotating, resizing and recolor apply to all of them. Settings below apply to each selected object of the same stitch type. Option-click picks one object inside a group.")
        }
        .padding(10).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
    }
    /// One small icon button for an align or space command; its name and what it lines up with show on hover.
    private func alignButton(_ command: CommandID) -> some View {
        Button { AppDelegate.shared.perform(command) } label: {
            Image(systemName: command.symbol).font(.system(size: 12)).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Theme.ink)
        .help(command.title + ([.spaceAcross, .spaceDown].contains(command) ? ": equal gaps between three or more; the outer two stay put." : ", to the object selected last."))
        .accessibilityLabel(command.title)
    }
    /// Shown for an object whose stitches were edited by hand: they sew until its shape or a setting changes, and
    /// Regenerate swaps them for fresh ones now. Shared by the Guided and Pro Properties.
    func stitchEditNotice(_ object: RunObject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Stitches edited by hand", systemImage: CommandID.editStitches.symbol).font(Theme.body(12, weight: .bold))
                Spacer()
                Button("Regenerate") { state.editSelected("Regenerate Stitches") { $0.stitchEdits = nil } }.buttonStyle(ThemedButtonStyle())
                    .help("Throw away the hand edits and work the stitches out again from the shape and settings")
            }
            if !pro { explain("Changing the shape or a setting replaces them with fresh stitches; moving, turning or resizing keeps them.") }
        }
        .padding(10).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
    }
    /// The stitch angle lines of a tatami or satin fill: how many, Add (the Add Stitch Angles tool) and Remove all. Shared by
    /// the Guided and Pro Properties.
    func stitchAngles(_ object: RunObject) -> some View {
        let count = object.settings.angleLines?.count ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(count == 0 ? "Stitch angles: straight rows" : "Stitch angles: \(count) line\(count == 1 ? "" : "s")").font(Theme.body(12, weight: .semibold))
                Spacer()
                Button("Add…") { AppDelegate.shared.perform(.addStitchAngles) }.help(preferences.hint(.addStitchAngles))
                if count > 0 { Button("Remove all") { settings(.fill, "Remove Stitch Angles") { $0.angleLines = nil } }.help("Take out every stitch angle line, so the fill sews straight rows again.") }
            }.buttonStyle(ThemedButtonStyle())
            if !pro { explain("Draw lines across the fill and its stitches run along them, turning gradually from one line to the next, so the fill can follow a curved shape like a satin column does.") }
        }
    }
    /// Plain-English help for start and end points, naming the current shortcut for the Start & End tool.
    func startEndHelp(_ object: RunObject) -> String {
        let key = preferences.label(.entryExitTool), press = key.isEmpty ? "Choose Start & End Points" : "Press \(key)"
        switch object.kind {
        case .fill: return "\(press) and click where this fill should start; Option-click where it should end. Rows begin and finish at the matching corners. Drag a marker on the canvas to move it."
        case .satin: return "\(press) and click near the end this column should start from. The end point doesn't change satin."
        default: return object.closed ? "\(press) and click where this outline should start; it begins at the nearest point on the line and finishes there." : "\(press) and click near the end this line should start from."
        }
    }
    /// X and Y fields (in the chosen unit) for one of an object's points, such as its start point; committing moves just that point.
    func pointFields(_ title: String, _ point: Point, object id: UUID, set: @escaping (inout RunObject, Point) -> Void) -> some View {
        func commit(_ next: Point) {
            state.edit("Move \(title) Point") { design in if let i = design.objects.firstIndex(where: { $0.id == id && !$0.locked }) { set(&design.objects[i], next) } }
        }
        return HStack(spacing: 6) {
            Text(title).font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
            Text("X").font(Theme.body(10)).foregroundStyle(Theme.inkSecondary)
            NumberField(value: point.x, range: -1000...1000, unit: preferences.unit, commit: { commit(Point($0, point.y)) }, focusCanvas: state.focusCanvas).frame(width: 60, height: pro ? 21 : 24)
            Text("Y").font(Theme.body(10)).foregroundStyle(Theme.inkSecondary)
            NumberField(value: point.y, range: -1000...1000, unit: preferences.unit, commit: { commit(Point(point.x, $0)) }, focusCanvas: state.focusCanvas).frame(width: 60, height: pro ? 21 : 24)
            Text(preferences.unit.symbol).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary)
        }
        .help("\(title) point, from the hoop's center")
    }
    /// One line of plain-English help under a setting. The Pro view leaves these out (the settings show them as tooltips).
    @ViewBuilder func explain(_ text: String) -> some View {
        if !pro { Text(text).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true) }
    }
    /// What a fill's Stitch length does, for its help: stipple stitches stop at 2 mm, so longer lengths sew the same.
    func fillStitchLengthHelp(_ object: RunObject) -> String {
        object.settings.fillStyle == .stipple ? "Length of each stitch along the wandering line. Stipple stitches are 2 mm at most, so lengths over 2 mm sew the same." : "Length of each stitch along a fill row."
    }
    /// Fills: the "Cut out shapes sewn on top" checkbox (OverlapCutout.swift). Off unless switched on. Shared with Pro.
    func cutOutToggle(_ object: RunObject) -> some View {
        toggle("Cut out shapes sewn on top", value: object.settings.cutOutOverlaps == true) { on in settings(.fill, "Cut Out Overlaps") { $0.cutOutOverlaps = on ? true : nil } }
            .help("Leave out the part of this fill that shapes sewn after it cover, tucking 1 mm under their edges. Select several fills to switch them all.")
    }
    /// Satin's two automatic helpers, as checkboxes. Shared with the Pro layout.
    @ViewBuilder func satinOptions(_ object: RunObject) -> some View {
        toggle("Short stitches on curves", value: object.settings.shortStitches == true) { on in settings(.satin, "Short Stitches") { $0.shortStitches = on } }
            .help("On the inside of a curve, every other stitch stops short so thread doesn't pile up into a hard ridge.")
        toggle("Split wide satin", value: object.settings.autoSplit == true) { on in settings(.satin, "Split Wide Satin") { $0.autoSplit = on } }
            .help("Stitches longer than the maximum stitch are split into shorter ones, staggered like bricks, instead of the column being refused.")
        toggle("Raised (padded)", value: object.settings.raised == true) { on in settings(.satin, "Raised Satin") { $0.raised = on ? true : nil } }
            .help("Lanes of padding stitches are sewn along the column first, so the satin stands up off the fabric for a 3D look. Uses more thread; best on columns 3 mm and wider.")
    }
    /// Satin from a center line: a width and a button that turns this line into a satin column. Shared with Pro.
    @ViewBuilder func satinLine(_ object: RunObject) -> some View {
        number("Satin width", value: preferences.data.satinLineWidth ?? SatinLine.defaultWidth, range: SatinLine.widths, help: "Turn this line into a satin column this wide, centered on the line.") { value in preferences.data.satinLineWidth = value; preferences.save() }
        Button("Make satin column") { AppDelegate.shared.perform(.convertSatin) }.buttonStyle(ThemedButtonStyle())
            .help("Turn this line into a satin column centered on it (\(Preferences.shared.label(.convertSatin).isEmpty ? "Digitize menu" : Preferences.shared.label(.convertSatin)))")
    }
    /// The settings a fill style has of its own: stipple spacing; a motif fill's motif, size and gap; a cross stitch
    /// fill's square size; a gradient fill's row spacing where it starts and ends; a satin fill's splitting. Shared
    /// with the Pro layout.
    @ViewBuilder func patternSettings(_ object: RunObject) -> some View {
        let s = object.settings
        switch s.fillStyle ?? .tatami {
        case .stipple:
            number("Stipple spacing", value: s.stippleSpacing ?? DigitizingSettings.defaultStippleSpacing, range: DigitizingSettings.stippleSpacingRange, help: "How far apart the line's neighbouring passes are (mm). Smaller is denser. Stipple sews without underlay.") { value in settings(.fill, "Stipple Spacing") { $0.stippleSpacing = value } }
        case .motif:
            motifPicker(object, kind: .fill)
            number("Motif size", value: s.patternSize ?? DigitizingSettings.defaultPatternSize(.motif), range: DigitizingSettings.patternSizeRange, help: "How big each motif is (mm). Only whole motifs that fit inside the shape are sewn.") { value in settings(.fill, "Motif Size") { $0.patternSize = value } }
            number("Gap", value: s.patternGap ?? DigitizingSettings.defaultPatternGap, range: DigitizingSettings.patternGapRange, help: "The space between motifs (mm).") { value in settings(.fill, "Motif Gap") { $0.patternGap = value } }
        case .crossStitch:
            number("Square size", value: s.patternSize ?? DigitizingSettings.defaultPatternSize(.crossStitch), range: DigitizingSettings.patternSizeRange, help: "The size of each cross-stitch square (mm). Smaller squares follow the shape more closely and take more stitches.") { value in settings(.fill, "Square Size") { $0.patternSize = value } }
        case .gradient:
            let gradientHelp = "Row spacing where the rows start (the solid end) and where they finish (the open end), in mm. The rows run at the fill angle and open up from one side of the shape to the other; turning the angle by 180° swaps the sides."
            number("Spacing at start", value: s.gradientStart ?? DigitizingSettings.defaultGradientStart, range: DigitizingSettings.gradientSpacingRange, hover: gradientHelp) { value in settings(.fill, "Gradient Start") { $0.gradientStart = value } }
            number("Spacing at end", value: s.gradientEnd ?? DigitizingSettings.defaultGradientEnd, range: DigitizingSettings.gradientSpacingRange, help: gradientHelp) { value in settings(.fill, "Gradient End") { $0.gradientEnd = value } }
        case .guided:
            explain(s.guideLine == nil ? "Draw a line over this fill, select both and choose Digitize → Use Line as Fill Guide. The rows bend to follow it."
                                       : "The rows follow the dashed guide line, keeping the row spacing. Reshape it with Edit Nodes and the rows follow. Keep it gentle: rows far from a tight bend round off on its outside and close into a corner on its inside.")
        case .satin:
            // For fills, Auto split is on unless turned off (nil counts as on).
            toggle("Auto split", value: s.autoSplit != false) { on in settings(.fill, "Auto Split") { $0.autoSplit = on ? nil : false } }
                .help("Stitches longer than the split length are broken into shorter ones, in bands that follow the shape's edge, so wide parts don't get long, loose stitches.")
            number("Split length", value: s.satinSplit ?? DigitizingSettings.defaultSatinSplit, range: DigitizingSettings.satinSplitRange, length: true, help: "The longest satin stitch. Longer ones are split with Auto split on; with it off, the shape must be narrower than this.") { value in settings(.fill, "Split Length") { $0.satinSplit = value == DigitizingSettings.defaultSatinSplit ? nil : value } }
        default: EmptyView()
        }
    }
    /// The pattern a motif run or motif fill repeats.
    func motifPicker(_ object: RunObject, kind: StitchKind) -> some View {
        HStack {
            Text("Motif").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
            Picker("Motif", selection: Binding(get: { object.settings.motif ?? .heart }, set: { value in settings(kind, "Motif") { $0.motif = value == .heart ? nil : value } })) {
                ForEach(Motif.allCases, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().frame(width: pro ? 120 : 140)
        }
    }
    /// A line's stitch style (running, zigzag, blanket, back or stem stitch, motif), with the width and spacing the style
    /// uses. Guided explains the style under the picker; Pro shows the explanation as a tooltip.
    @ViewBuilder func runStyle(_ object: RunObject) -> some View {
        let style = object.settings.runStyle ?? .running
        HStack {
            Text("Line style").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
            Picker("Line style", selection: Binding(get: { style }, set: { value in settings(.run, "Line Style") { $0.runStyle = value == .running ? nil : value; $0.runWidth = nil; $0.runSpacing = nil } })) {
                ForEach(RunStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().frame(width: pro ? 120 : 140)
        }
        .help(style.summary)
        if !pro { explain(style.summary) }
        if style == .motif { motifPicker(object, kind: .run) }
        if style.hasWidth {
            number(style == .blanket ? "Prong length" : style == .motif ? "Motif size" : "Width", value: object.settings.runWidth ?? DigitizingSettings.defaultRunWidth(style), range: DigitizingSettings.runWidthRange,
                   help: style == .blanket ? "How far each prong reaches from the line (mm)." : style == .motif ? "How long each motif is along the line (mm)." : "How wide the stitch is across the line (mm).") { value in settings(.run, "Line Width") { $0.runWidth = value } }
        }
        if style.hasSpacing {
            number(style == .blanket ? "Prong spacing" : style == .motif ? "Gap" : "Spacing", value: object.settings.runSpacing ?? DigitizingSettings.defaultRunSpacing(style), range: DigitizingSettings.runSpacingRange,
                   help: style == .blanket ? "How far apart the prongs are along the line (mm)." : style == .motif ? "The running stitch between motifs (mm)." : "How far the needle moves along the line with each swing (mm). Smaller is denser.") { value in settings(.run, "Line Spacing") { $0.runSpacing = value } }
        }
        if style == .zigzag { explain("Each zigzag stitch runs from one side of the line to the other: Width sets how far across, Spacing how far along.") }
        if style == .ripple {
            let range = DigitizingSettings.rippleLineRange
            number("Lines", value: Double(object.settings.rippleLines ?? DigitizingSettings.defaultRippleLines), range: Double(range.lowerBound)...Double(range.upperBound),
                   help: "How many times the line is sewn, each copy smaller. More lines sit closer together.") { value in settings(.run, "Ripple Lines") { $0.rippleLines = Int(value.rounded()) } }
            if object.settings.radialCenter != nil {
                Button("Reset target") { settings(.run, "Reset Ripple Target") { $0.radialCenter = nil } }.buttonStyle(ThemedButtonStyle())
                    .help("Move the Target dot back to where it starts: the middle of the shape")
            }
        }
    }
    /// Running stitch passes: Single, or bean stitch sewing each stitch 3 or 5 times. Shared with the Pro layout.
    func runPasses(_ object: RunObject) -> some View {
        HStack {
            Text("Passes").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
            Picker("Passes", selection: Binding(get: { object.settings.runPasses ?? 1 }, set: { value in settings(.run, "Running Passes") { $0.runPasses = value == 1 ? nil : value } })) {
                Text("Single").tag(1); Text("Bean ×3").tag(3); Text("Bean ×5").tag(5)
            }.pickerStyle(.segmented).labelsHidden().frame(width: pro ? 170 : 190)
        }
        .help("How many times each stitch is sewn. Bean stitch (3 or 5) goes forward, back and forward again for a bold line.")
    }
    func settings(_ kind:StitchKind,_ title:String,_ body:@escaping(inout DigitizingSettings)->Void){state.editSelected(title){object in guard object.kind==kind else{return};var s=object.settings;body(&s);object.digitizing=s}}
    /// A labeled number field. `help` explains the setting: as a line under it in the Guided view, as a tooltip in Pro.
    /// `hover` is an explanation shown only as a tooltip, for settings whose meaning the panel already makes clear.
    /// `length` marks a size or position: it's shown and typed in the chosen unit (mm or inches), with the unit beside it.
    @ViewBuilder func number(_ title: String, value: Double, id: String = "", range: ClosedRange<Double>, length: Bool = false, help: String? = nil, hover: String? = nil, commit: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
            NumberField(value: value, identifier: id, range: range, unit: length ? preferences.unit : nil, commit: commit, focusCanvas: state.focusCanvas).frame(width: pro ? 84 : 74, height: pro ? 21 : 24)
            if length { Text(preferences.unit.symbol).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).fixedSize().frame(width: 18, alignment: .leading) }
        }
        .help(hover ?? help ?? "")
        if let help { explain(help) }
    }
    /// Width, for even-width satins (satin borders and satins made from a line): typing a new one rebuilds the satin
    /// around its middle line. Hand-drawn columns, whose width varies, don't show it. Shared with the Pro layout.
    @ViewBuilder func satinWidth(_ object: RunObject) -> some View {
        if let width = SatinLine.evenWidth(of: object) {
            number("Width", value: (width * 100).rounded() / 100, range: SatinLine.widths, length: true,
                   help: "How wide the satin is. Type a new width and press Return; it stays centered where it is.") { state.setSatinWidth($0) }
        }
    }
    func toggle(_ title: String, value: Bool, action: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: action)).font(Theme.body(pro ? 11 : 12)).toggleStyle(.checkbox)
    }
}

/// A tiny drawing of the selected stitch settings, at roughly 12 points per millimetre:
/// satin as a zigzag at the row spacing, fill as offset rows at the fill angle, running stitch as a dashed curve. Line
/// stitch styles and the stipple, motif, cross stitch, gradient and guided fills are the real stitches, worked out for a short
/// line or a small patch with the object's own `settings`.
struct StitchPreview: View {
    var kind: StitchKind
    var color: Color
    var spacing: Double       // mm between satin passes or fill rows
    var stitchLength: Double  // mm per running or fill stitch
    var angle: Double         // fill row direction, in degrees
    var fillStyle = FillStyle.tatami
    var waveHeight = DigitizingSettings.defaultWaveHeight, waveLength = DigitizingSettings.defaultWaveLength   // mm
    var settings = DigitizingSettings(kind: .run)
    var body: some View {
        let runStyle = settings.runStyle ?? .running
        // Canvas is SwiftUI's free-drawing view: its closure receives a drawing context and the space available.
        Canvas { context, size in
            let scale = 12.0, inset = 4.0
            switch kind {
            case .satin:
                // The needle swings edge to edge, moving along the column by one row spacing per pass.
                let step = max(spacing * scale, 1.5)
                var path = Path(), x = inset, onTop = true
                path.move(to: CGPoint(x: x, y: inset))
                while x < size.width - inset {
                    x += step; onTop.toggle()
                    path.addLine(to: CGPoint(x: x, y: onTop ? inset : size.height - inset))
                }
                context.stroke(path, with: .color(color), lineWidth: 1.3)
            case .run where runStyle != .running:
                // The style's own stitches along a straight line across the box (blanket's prongs reach up from near
                // the bottom, so they fit).
                let length = (size.width - 2 * inset) / scale, baseline = runStyle == .blanket ? size.height - inset : size.height / 2
                let points = RunningStyles.stitches(runStyle, along: [Point(0, 0), Point(length, 0)], closed: false, width: settings.runWidth ?? DigitizingSettings.defaultRunWidth(runStyle),
                                                    spacing: settings.runSpacing ?? DigitizingSettings.defaultRunSpacing(runStyle), length: stitchLength, motif: settings.motif ?? .heart) ?? []
                var path = Path()
                for (index, p) in points.enumerated() {
                    let q = CGPoint(x: inset + p.x * scale, y: baseline - p.y * scale)
                    if index == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                context.stroke(path, with: .color(color), lineWidth: 1.3)
            case .fill where [.stipple, .motif, .crossStitch, .gradient, .guided, .satin].contains(fillStyle):
                // The real fill of a patch the size of the box, drawn smaller (2 points per mm) so a few of its loops,
                // motifs or squares fit.
                let small = 2.0, w = size.width / small, h = size.height / small
                var patch = RunObject(name: "Preview", nodes: [Point(0, 0), Point(w, 0), Point(w, h), Point(0, h)].map { PathNode($0) })
                patch.closed = true; patch.stitchLength = stitchLength
                patch.digitizing = settings; patch.digitizing?.kind = .fill; patch.digitizing?.underlay = UnderlayStyle.none
                // A guided fill's own guide is somewhere else in the design: the preview bends its rows along an arch.
                if fillStyle == .guided { patch.digitizing?.guideLine = stride(from: -0.1, through: 1.1, by: 0.05).map { t in Point(w * t, h * (0.3 + 0.4 * sin(.pi * t))) } }
                var path = Path()
                for section in (try? AreaEngine.fill(patch).sections) ?? [] {
                    for (index, p) in section.points.enumerated() {
                        let q = CGPoint(x: p.x * small, y: size.height - p.y * small)
                        if index == 0 { path.move(to: q) } else { path.addLine(to: q) }
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.2)
            case .fill where fillStyle == .contour:
                // Rings following the box's edge inward.
                let gap = max(spacing * scale, 2), dash = max(stitchLength * scale, 4)
                var rect = CGRect(origin: .zero, size: size).insetBy(dx: gap / 2, dy: gap / 2)
                while rect.width > 1 && rect.height > 1 {
                    context.stroke(Path(roundedRect: rect, cornerRadius: min(8, rect.height / 2)), with: .color(color), style: StrokeStyle(lineWidth: 1.6, dash: [dash - 1.5, 1.5]))
                    rect = rect.insetBy(dx: gap, dy: gap)
                }
            case .fill where fillStyle == .radial:
                // Rays from a center just below the box, fanning out across it; every other one stops short.
                let gap = max(spacing * scale, 2), center = CGPoint(x: size.width / 2, y: size.height + 4)
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                let radius = hypot(size.width / 2, size.height + 4), step = gap / radius
                for i in -Int(1.6 / step)...Int(1.6 / step) {
                    let a = Double(i) * step - .pi / 2, inner = i % 2 == 0 ? 6.0 : 18.0
                    var ray = Path(); ray.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner)); ray.addLine(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
                    context.stroke(ray, with: .color(color), lineWidth: 1.3)
                }
            case .fill:
                // Parallel rows turned to the fill angle (rippling for wave fills); tiny gaps mark where one stitch
                // ends and the next begins.
                let gap = max(spacing * scale, 2), dash = max(stitchLength * scale, 4), reach = size.width + size.height
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                context.translateBy(x: size.width / 2, y: size.height / 2)
                context.rotate(by: .degrees(-angle))   // screen y points down, design y points up
                var y = -reach, row = 0
                while y < reach {
                    var line = Path(); line.move(to: CGPoint(x: -reach, y: y))
                    if fillStyle == .wave {
                        for x in stride(from: -reach, through: reach, by: 2) { line.addLine(to: CGPoint(x: x, y: y + waveHeight / 2 * scale * sin(2 * .pi * x / (waveLength * scale)))) }
                    } else { line.addLine(to: CGPoint(x: reach, y: y)) }
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, dash: [dash - 1.5, 1.5], dashPhase: row % 2 == 0 ? 0 : dash / 2))
                    y += gap; row += 1
                }
            default:
                // A gentle curve of running stitches, each one stitch-length long.
                let dash = max(stitchLength * scale, 3)
                var path = Path()
                path.move(to: CGPoint(x: inset, y: size.height / 2))
                path.addCurve(to: CGPoint(x: size.width - inset, y: size.height / 2), control1: CGPoint(x: size.width * 0.35, y: -size.height * 0.2), control2: CGPoint(x: size.width * 0.65, y: size.height * 1.2))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [dash - 1.5, 1.5]))
            }
        }
        .accessibilityLabel("Close-up preview of the stitches at the current settings")
    }
}

/// The Threads panel: the thread palette. Clicking a color sets the current thread and recolors the selection.
struct ThreadsPanel: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        if preferences.isPro { ProThreads(state: state) } else { palette }
    }
    private var palette: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)], alignment: .leading, spacing: 10) {
                ForEach(ThreadColor.palette, id: \.hex) { color in
                    Button {
                        state.currentColor = color; state.editSelected("Thread Color") { $0.color = color }; state.focusCanvas()
                    } label: {
                        Circle().fill(Color(nsColor: color.nsColor)).frame(width: 24, height: 24).overlay(Circle().strokeBorder(Theme.controlBorder))
                            .overlay(Circle().strokeBorder(Theme.ink.opacity(state.currentColor == color ? 0.85 : 0), lineWidth: 2).padding(-3))
                    }.buttonStyle(.plain).help(color.name)
                }
                // The last "swatch" opens the thread chart: real threads by brand and color number.
                Button { AppDelegate.shared.perform(.threadChart) } label: {
                    Image(systemName: "swatchpalette").font(.system(size: 13)).frame(width: 24, height: 24).overlay(Circle().strokeBorder(Theme.controlBorder))
                }.buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
                .help("Thread chart (\(preferences.label(.threadChart))): choose a real thread by brand and color number, or match every thread at once")
            }.padding(3)
            Text("Current thread: \(state.currentColor.name)\(state.currentColor.chartLabel.map { " · \($0)" } ?? ""). Clicking a color also recolors the selection.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.ink)
    }
}

/// The stitch player's speed in stitches per second, shared by every design window (it's in the player's Custom
/// Speed box). Numbers outside 1–5,000 are pulled back into range; the new speed applies once you press Return or
/// leave the box.
struct PlaybackSpeedField: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        TextField("Speed", value: Binding(get: { preferences.playbackSpeed },
                                          set: { preferences.playbackSpeed = min(max($0, Preferences.playbackSpeeds.lowerBound), Preferences.playbackSpeeds.upperBound) }),
                  format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            .help("Stitches per second while playing (1–5,000). A machine sews about 12; 120 is the usual preview speed.")
            .accessibilityLabel("Playback speed, stitches per second")
    }
}

/// The status bar along the bottom of the window: the latest message, the "Ready to save" checks, stitch count and zoom.
struct FooterPanel: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(state.busy ? Color.orange : Theme.accent).frame(width: 6, height: 6)
                Text(state.busy ? "Generating stitches…" : (state.generationError ?? state.status)).foregroundStyle(state.generationError == nil ? Theme.inkSecondary : Color.red).lineLimit(1).help(state.generationError ?? state.status)
                Spacer()
                readiness
                if preferences.isPro {
                    ProStats(state: state, pointer: state.pointer)
                    Text("\(Int(state.zoom * 20))%").foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("\(state.plan.stitchCount.formatted()) stitches · \(Int(state.zoom * 20))%").foregroundStyle(Theme.inkSecondary)
                }
            }.font(Theme.body(10, weight: .medium)).padding(.horizontal, 16).frame(height: 29)
            .background(Theme.ground)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.ground)
        .overlay(alignment: .top) { Theme.edge.frame(height: 1) }
    }
    /// The "Ready to save" checks. They mirror what the export commands require (plus a reminder that unstitched
    /// outlines are left out of exports), so a green chip means export will include everything.
    /// Otherwise each unmet check gets its own short chip explaining what to do.
    @ViewBuilder private var readiness: some View {
        let problems = readinessProblems
        if problems.isEmpty && state.plan.stitchCount > 0 {
            chip(preferences.isPro ? "Ready" : "Ready to save · fits the hoop", symbol: "checkmark.circle.fill", color: Theme.success)
                .help("Ready to save: the stitches are up to date and fit the hoop")
        } else {
            // Resting the pointer on a chip shows the whole story: for a stitch error, the full message (which is often
            // too long for the status line, and ends with how to fix it).
            ForEach(problems, id: \.self) { problem in
                chip(problem, symbol: "exclamationmark.circle.fill", color: Color.orange)
                    .help(problem == "Fix the stitch error first" ? (state.generationError ?? problem) : problem)
            }
        }
    }
    private var readinessProblems: [String] {
        var problems: [String] = []
        if !state.draft.isEmpty { problems.append("Finish or cancel the current path") }
        if state.design.objects.contains(where: { $0.kind == .vector && $0.guideFor == nil }) { problems.append("Unstitched outlines will be left out") }
        if state.hasVersionMismatch { problems.append("Regenerate with the current engine") }
        else if state.generationError != nil { problems.append("Fix the stitch error first") }
        else if state.busy || state.compiledRevision != state.revision { problems.append("Updating stitches…") }
        // The stitch generator adds this warning whenever stitches land outside the sewing area (AreaEngine.swift).
        if state.plan.warnings.contains(where: { $0.contains("beyond the sewing area") }) { problems.append("Move it inside the sewing area") }
        return problems
    }
    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).labelStyle(.titleAndIcon).font(Theme.body(10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

struct ShortcutSettings: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var search = ""
    @State private var category: String?   // nil shows every command
    @State private var recording: CommandID?
    @State private var pending: (CommandID, KeyBinding)?
    @State private var conflictText = ""
    @State private var showConflict = false
    private let categories = ["Digitizing", "Edit", "File", "View", "Workspace"]
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // The categories, key map and help scroll if the window is short; the command list scrolls on its own.
            ScrollView { sidebar }.scrollIndicators(.never).frame(width: 300)
            commandsColumn
        }
        .padding(.horizontal, 28).padding(.bottom, 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Theme.ink)
            .alert("Shortcut already assigned", isPresented: $showConflict) { Button("Replace Assignment") { if let (command, key) = pending { preferences.assign(key, to: command, replacing: true) }; pending = nil }; Button("Cancel", role: .cancel) { pending = nil } } message: { Text(conflictText) }
            .onDisappear { stopRecording() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stopRecording() }
    }
    /// Commands shown in the list: a search looks through everything; otherwise the chosen category filters it.
    private var visibleCommands: [CommandID] {
        CommandID.allCases.filter { command in
            if !search.isEmpty { return (command.title + " " + command.category + " " + preferences.label(command)).localizedCaseInsensitiveContains(search) }
            return category == nil || command.category == category
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 2) {
                categoryButton(nil, title: "All commands")
                ForEach(categories, id: \.self) { categoryButton($0, title: $0) }
            }
            .padding(8).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            keyboardMap
            VStack(alignment: .leading, spacing: 6) {
                Text("How it works").font(Theme.body(13, weight: .bold))
                Text("1. Click Record next to a command.\n2. Press the key or key combination you want.\n3. If that key is already taken, you'll be asked before anything is replaced.\nClick a key badge to remove it. A command can have more than one key.")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.divider, in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 0)
        }
    }
    private func categoryButton(_ value: String?, title: String) -> some View {
        let active = search.isEmpty && category == value
        let count = value == nil ? CommandID.allCases.count : CommandID.allCases.filter { $0.category == value }.count
        return Button { category = value; search = "" } label: {
            HStack { Text(title).font(Theme.body(13, weight: active ? .bold : .regular)); Spacer(); Text("\(count)").font(Theme.body(12)).opacity(0.8) }
                .padding(.horizontal, 12).frame(height: 34)
                .background(active ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(active ? Theme.onAccent : Theme.ink)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    /// A small keyboard showing which single letter keys already do something on the canvas, colored by category.
    private var keyboardMap: some View {
        let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Single keys in use").font(Theme.body(13, weight: .bold))
                Spacer()
                Text("Free keys are blank").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 5) {
                        ForEach(row.map(String.init), id: \.self) { letter in
                            // Ask the active profile which command (if any) this plain letter runs on the canvas.
                            let command = preferences.profile.command(for: KeyBinding(letter.lowercased()), context: .canvas)
                            Text(letter).font(Theme.body(11, weight: .bold))
                                .frame(width: 22, height: 26)
                                .background(command.map { categoryColor($0.category) } ?? Theme.card, in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(command == nil ? Theme.controlBorder : Color.clear))
                                .foregroundStyle(command == nil ? Theme.inkSecondary : Color.white)
                                .help(command.map { "\(letter): \($0.title)" } ?? "\(letter): free")
                        }
                    }.padding(.leading, CGFloat(index) * 14)
                }
            }
            HStack(spacing: 12) {
                ForEach(["Digitizing", "Edit", "View"], id: \.self) { name in
                    HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(categoryColor(name)).frame(width: 10, height: 10); Text(name) }
                }
            }.font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
        }
        .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Digitizing": return Color(red: 0.20, green: 0.31, blue: 0.48)  // denim (the light-mode accent), readable under white letters in both modes
        case "Edit": return Color(red: 0.69, green: 0.33, blue: 0.18)        // terracotta
        case "View": return Color(red: 0.31, green: 0.48, blue: 0.29)        // sage
        default: return Color(red: 0.42, green: 0.35, blue: 0.30)            // brown for File and Workspace
        }
    }
    private var commandsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Profile", selection: Binding(get: { preferences.data.activeProfile }, set: { preferences.data.activeProfile = $0; preferences.save() })) { ForEach(preferences.data.profiles.indices, id: \.self) { index in Text(preferences.data.profiles[index].name).tag(index) } }.frame(width: 280)
                Button("Duplicate…") { if let name = AppDelegate.shared.askName("Name this shortcut profile", value: "My Shortcuts Copy") { preferences.duplicateProfile(name: name) } }
                Spacer()
                Button("Import…") { importProfile() }; Button("Export…") { exportProfile() }
            }.buttonStyle(ThemedButtonStyle()).font(Theme.body(12, weight: .semibold))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSecondary)
                TextField("Search tools, actions, or assigned keys", text: $search).textFieldStyle(.plain).font(Theme.body(13))
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.controlBorder))
            if let recording {
                HStack(spacing: 12) {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                    Text("Press a shortcut for \(recording.title)…").font(Theme.body(13, weight: .bold))
                    Spacer()
                    Button("Cancel") { stopRecording() }.buttonStyle(ThemedButtonStyle())
                }
                .padding(12).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(search.isEmpty ? (category ?? "All commands") : "Search results").font(Theme.heading(17))
                    Spacer()
                    Text("\(visibleCommands.count) commands").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                Theme.divider.frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleCommands, id: \.self) { command in
                            commandRow(command)
                            Theme.divider.frame(height: 1)
                        }
                    }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                Text("Plain keys work in the design workspace, never while typing.\nFunction keys may require Fn, depending on your Mac settings.").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                Spacer()
                Button("Reset profile…") {
                    let alert = NSAlert(); alert.messageText = "Reset this profile to the defaults?"; alert.informativeText = "Other named profiles are unaffected."; alert.addButton(withTitle: "Reset"); alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn { preferences.data.profiles[preferences.data.activeProfile] = ShortcutProfile(name: preferences.profile.name); preferences.save() }
                }.buttonStyle(ThemedButtonStyle())
            }
            if let error = preferences.error { Text(error).font(Theme.body(11)).foregroundStyle(.orange) }
        }
    }
    /// One command: its name and where it works, its key badges (click one to remove it), and a Record button.
    private func commandRow(_ command: CommandID) -> some View {
        let isRecording = recording == command
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title).font(Theme.body(13, weight: .semibold))
                Text(command.category + " · " + (command.appWide ? "Application" : command.contexts == [.drawing] ? "While drawing" : "Design workspace")).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            ForEach(preferences.keys(command), id: \.self) { key in
                Button { preferences.remove(command, key: key) } label: {
                    HStack(spacing: 6) { Text(key.display).font(Theme.body(12, weight: .bold)); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.inkSecondary) }
                        .padding(.horizontal, 9).frame(height: 28)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.controlBorder))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help("Remove \(key.display)")
            }
            Button(isRecording ? "Listening…" : "Record…") { startRecording(command) }
                .buttonStyle(ThemedButtonStyle(prominent: isRecording)).disabled(recording != nil && !isRecording)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(isRecording ? Theme.accentSoft : Color.clear)
    }
    private func startRecording(_ command: CommandID) {
        recording = command; preferences.isRecording = true
        preferences.recordHandler = { key in
            stopRecording()
            let conflicts = preferences.profile.conflicts(key, for: command)
            if !conflicts.isEmpty { pending = (command, key); conflictText = "\(key.display) is assigned to \(conflicts.map(\.title).joined(separator: ", ")). Replace those assignments?"; showConflict = true }
            else { preferences.assign(key, to: command, replacing: false) }
        }
    }
    private func stopRecording() { recording = nil; preferences.isRecording = false; preferences.recordHandler = nil }
    private func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { do { try preferences.importProfile(url) } catch { preferences.error = error.localizedDescription } }
    }
    private func exportProfile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = preferences.profile.name + ".json"
        if panel.runModal() == .OK, let url = panel.url {
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(Preferences.ProfileFile(profile: preferences.profile)).write(to: url, options: .atomic) }
            catch { preferences.error = error.localizedDescription }
        }
    }
}
