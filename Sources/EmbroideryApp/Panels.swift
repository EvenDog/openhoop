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

/// The tools on their denim band: two rows across the top of the window, or (picked in Settings) a rail down the
/// left side. Every tool is its own icon button, in captioned groups; hovering one shows its name and key. Buttons
/// run the same commands as the menus and shortcuts.
struct ToolStrip: View {
    @ObservedObject var state: EditorState
    /// True for the rail down the left side, which shows only when it's picked in Settings; false for the strip
    /// across the top.
    var rail = false
    @ObservedObject var preferences = Preferences.shared
    /// The tools in their captioned groups, in their built-in order. View › Customize Tools… can rearrange them
    /// (`Preferences.toolArrangement`).
    static let proGroups: [(title: String, commands: [CommandID])] = [
        ("Pick & shape", [.selectTool, .nodeTool, .editStitches, .smoothShapes, .knifeTool, .weldObjects, .removeOverlaps, .branching, .entryExitTool, .panTool, .artworkTool]),
        ("Stitch", [.runTool, .satinTool, .fillTool, .holeTool, .addStitchAngles, .removeStitchAngles]),
        ("Shape", [.openShapeTool, .closedShapeTool, .freehandOpenTool, .freehandClosedTool, .rectangleTool, .ellipseTool, .basicShapeTool]),
        ("Add", [.lettering, .addMonogram, .satinBorder, .outlinesOffsets, .applique, .autoDigitize, .laydown, .wreath]),
        ("View", [.measureTool, .hoopingsTool, .grid, .snap, .threadView, .reviewSewingOrder]),
        ("Show", [.showStitches, .showOutlines, .showConnectors, .needles, .showUnderlay, .hideOthers, .showRulers, .densityMap]),
        ("Zoom", [.zoomFit, .zoomDesign, .zoomBoxTool, .zoomActual, .zoomSelected])
    ]
    /// The built-in rail's groups: the same tools, with View and Show sharing a group so the rail's rows of three
    /// fill evenly.
    static var railGroups: [[CommandID]] {
        let groups = proGroups.map(\.commands)
        return Array(groups[0..<4]) + [groups[4] + groups[5], groups[6]]
    }
    /// The groups the strip shows, as arranged in Customize Tools, leaving out any emptied there.
    private var shownGroups: [ToolArrangement.Group] { preferences.toolArrangement.groups.filter { !$0.commands.isEmpty } }
    /// The rail's groups: the built-in ones while the layout is unchanged, otherwise the strip's groups as they are.
    private var shownRailGroups: [[CommandID]] { preferences.data.toolLayout == nil ? Self.railGroups : shownGroups.map(\.commands) }
    var body: some View {
        if rail {
            if preferences.proToolsOnLeft { proRail } else { Color.clear.frame(width: 0) }
        } else {
            VStack(spacing: 0) {
                if !preferences.proToolsOnLeft {
                    proStrip
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.toolBand)
                        .contextMenu { customizeButton }   // after the background, so right-clicking anywhere on the band works
                    Theme.toolBandEdge.frame(height: 1)
                }
                PrecisionBar(state: state)   // exact position, size and turn of the selection
                Theme.edge.frame(height: 1)
            }
        }
    }
    /// The Pro strip across the top: each group under its caption, its buttons two high, filled column by column.
    private var proStrip: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(shownGroups.enumerated()), id: \.offset) { index, group in
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
            StripPlayer(state: state).fixedSize()
        }
    }
    /// The band's right-click menu item that opens Customize Tools.
    private var customizeButton: some View { Button(CommandID.customizeTools.title) { AppDelegate.shared.perform(.customizeTools) } }
    /// The Pro rail down the left side (picked in Settings): the same tools, three across, groups split by lines,
    /// with the stitch player at the bottom. The tools scroll if the window is too short to show them all.
    private var proRail: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(shownRailGroups.enumerated()), id: \.offset) { index, group in
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
            StripPlayer(state: state, stacked: true).padding(10)
        }
        .frame(width: 112)
        .background(Theme.toolBand)
        .contextMenu { customizeButton }
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
        if state.reviewing && state.tool == .select { return ("Reviewing", "← → step · Esc finishes") }
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
        case .hooping: return ("Hoopings", "drag one to move it · click to see what it sews")
        case .text: return ("Lettering", "click where it goes, then type in Properties")
        case .knife: return ("Knife", "click points across shapes" + key(.finishPath, "cuts"))
        case .stitchEdit: return ("Edit stitches", "click or box-select points · drag moves" + key(.delete, "deletes") + " · ⌥-click adds")
        case .addAngles: return ("Stitch angles", state.angleStart == nil ? "click two points across the fill" : "click the other side")
        case .removeAngles: return ("Remove angles", "click a line to remove it")
        case .wreath: return ("Wreath", state.wreathCenter == nil ? "click the center" : "click to move the center" + key(.finishPath, "makes it"))
        case .branch: return ("Branching", state.branchPoints.isEmpty ? "click where it starts · ↩ chooses for you" : "click where it ends · ↩ chooses for you")
        }
    }
    /// A tool's icon in the strip. Move & Size Artwork shows a photo with a + while the design has no image, since
    /// clicking it then imports one.
    static func symbol(_ command: CommandID, hasArtwork: Bool) -> String {
        command == .artworkTool && !hasArtwork ? CommandID.importImage.symbol : command.symbol
    }
    /// One Pro tool button: just the tool's icon. Its name and keys show when the pointer rests on it.
    private func proButton(_ command: CommandID) -> some View {
        let active = isActive(command), available = isAvailable(command)
        return Button { AppDelegate.shared.perform(command) } label: {
            Image.symbol(Self.symbol(command, hasArtwork: state.design.artwork != nil), size: 14).font(.system(size: 14))
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
    /// False for commands that can't run right now, so their menu items are greyed out.
    private func isAvailable(_ command: CommandID) -> Bool {
        switch command {
        case .holeTool: return state.selection.count == 1 && state.selected?.kind == .fill && state.selected?.locked == false
        case .addStitchAngles: return state.selection.count == 1 && state.selected?.kind == .fill && state.selected?.locked == false && [.tatami, .satin].contains(state.selected?.settings.fillStyle ?? .tatami)
        case .removeStitchAngles: return state.selection.count == 1 && state.selected?.locked == false && !(state.selected?.settings.angleLines ?? []).isEmpty
        case .useAsFillGuide: return state.fillAndGuideLine != nil
        case .putLetteringOnLine: return state.letteringAndLine != nil
        case .satinBorder, .outlinesOffsets, .applique: return state.design.objects.contains { state.selection.contains($0.id) && !$0.locked && SatinBorder.canBorder($0) }
        case .autoDigitize: return state.design.artwork != nil
        case .weldObjects: return state.design.objects.filter { state.selection.contains($0.id) && !$0.locked && $0.areaRings != nil }.count >= 2
        case .removeOverlaps: return state.design.objects.contains { (state.selection.isEmpty || state.selection.contains($0.id)) && $0.kind == .fill && !$0.locked }
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
        case .reviewSewingOrder: return state.reviewing
        case .showRulers: return preferences.showsRulers
        case .showStitches: return state.showStitches
        case .showOutlines: return state.showOutlines
        case .showConnectors: return state.showsConnectors
        case .hideOthers: return state.hideOthers
        default: return false
        }
    }
}

/// The reference picture's row in the sewing order. The objects listed above it are drawn under the picture and the
/// ones below it on top; its arrows move it past one step (or one group). It's only how the canvas draws: it never sews.
struct PictureRow: View {
    @ObservedObject var state: EditorState
    var body: some View {
        let layer = state.design.artworkLayer, count = state.design.objects.count
        HStack(spacing: 6) {
            Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(Theme.inkSecondary)
            Text("Reference image").font(Theme.body(11, weight: .semibold)).lineLimit(1)
            if state.design.artwork?.visible == false { Image(systemName: "eye.slash").font(.caption2).help("Hidden") }
            Spacer(minLength: 0)
            arrow("chevron.up", step: -1, enabled: layer > 0)
            arrow("chevron.down", step: 1, enabled: layer < count)
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
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
            VStack(alignment: .leading, spacing: 7) {
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
        Text(fabric.stabilizer).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
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
            Label { Text("Monogram “\(monogram.initials)”") } icon: { Image.symbol(CommandID.addMonogram.symbol, size: 13) }.font(Theme.body(13, weight: .semibold)).lineLimit(1)
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
    @ViewBuilder private var propertiesSection: some View {
        if state.reviewing { ReviewSection(state: state) }   // the step being reviewed, above the rest (ReviewSection.swift)
        ToolOptions(state: state)   // the current tool's choices, such as the next shape's (ToolOptions.swift)
        if ToolOptions.showsNextShape(state) || state.tool == .hooping {
            // A shape tool was just picked, or the Hoopings tool: its choices stand in for the selection's properties.
        } else if let object = state.selected {
            proProperties(object)   // the selection's settings in labeled sections (ProViews.swift)
        } else if !NextShapeOptions.shows(state.tool) {
            designOverview   // nothing selected: the whole design's figures and settings (DesignOverview.swift)
        }
    }
    @ViewBuilder var designSection: some View {
        SectionLabel(title: "Fabric")
        fabricTypePicker
        fabricPicker
        sectionDivider
        SectionLabel(title: "Sewing area")
        hoopMenu
        let hoop = state.design.hoop
        number("Width", value: hoop.width, range: 1...1000, length: true, help: "The sewing area's width. Typing your own makes it a custom size.") { value in setHoop(Hoop(width: value, height: hoop.height, oval: hoop.oval), "Hoop Width") }
        number("Height", value: hoop.height, range: 1...1000, length: true, help: "The sewing area's height. Typing your own makes it a custom size.") { value in setHoop(Hoop(width: hoop.width, height: value, oval: hoop.oval), "Hoop Height") }
        Button { setHoop(hoop.turned, "Turn Hoop") } label: { Label("Turn sideways", systemImage: "rotate.right") }
            .buttonStyle(ThemedButtonStyle()).disabled(hoop.width == hoop.height)
            .help("Swap width and height, for a hoop mounted with its long side left to right")
        toggle("Oval sewing area", value: hoop.oval) { value in setHoop(Hoop(width: hoop.width, height: hoop.height, oval: value), "Hoop Shape") }
            .help("For a hoop whose sewing area is an oval: stitches must stay inside the oval, not just the rectangle.")
        toggle("Multi-hooping", value: state.design.multiHooping != nil) { on in
            state.setMultiHooping(on)
            if on { AppDelegate.shared.perform(.hoopingsTool) }   // the Hoopings tool shows the hoopings in Properties
        }.help(preferences.hint(.hoopingsTool))
        if let count = state.design.multiHooping?.hoopings.count {
            Button { AppDelegate.shared.perform(.hoopingsTool) } label: { Label("\(count) hooping\(count == 1 ? "" : "s") · Edit…", systemImage: CommandID.hoopingsTool.symbol) }
                .buttonStyle(ThemedButtonStyle(prominent: state.tool == .hooping)).help(preferences.hint(.hoopingsTool))
        }
        sectionDivider
        SectionLabel(title: "Holding the fabric")
        toggle("Basting box", value: state.design.basting != nil) { on in state.edit("Basting Box") { $0.basting = on ? 5 : nil } }
            .help("Long running stitches around the design, sewn first, that hold the fabric to the stabilizer. Pull them out after sewing.")
        if let margin = state.design.basting {
            number("Margin", value: margin, range: Design.bastingMargins, length: true, help: "How far outside the design the basting box runs.") { value in state.edit("Basting Margin") { $0.basting = value } }
        }
        Button { AppDelegate.shared.perform(.laydown) } label: { Label("Add laydown…", systemImage: CommandID.laydown.symbol) }
            .buttonStyle(ThemedButtonStyle()).help(preferences.hint(.laydown))
        sectionDivider
        SectionLabel(title: "Connectors")
        number("Trim when the move is at least", value: state.design.trimDistance ?? Design.defaultTrimDistance, range: Design.trimDistances, length: true,
               help: "Objects whose Trim after is When far cut the thread only when the next part starts this far away or more.") { value in
            state.edit("Trim Distance") { $0.trimDistance = value == Design.defaultTrimDistance ? nil : value }
        }
        number("Tie when the move is at least", value: state.design.tieDistance ?? Design.defaultTieDistance, range: Design.tieDistances, length: true,
               help: "Objects whose Tie in or Tie off is When far tie only after (or before) a move this long or more, or where the thread is cut.") { value in
            state.edit("Tie Distance") { $0.tieDistance = value == Design.defaultTieDistance ? nil : value }
        }
        tieStitchesRow
        number("Run connector stitch length", value: state.design.runConnectorLength ?? Design.defaultRunConnectorLength, range: Design.runConnectorLengths, length: true,
               help: "How long the running stitches of run connectors are (Then: Run, in an object's Finish).") { value in
            state.edit("Run Connector Length") { $0.runConnectorLength = value == Design.defaultRunConnectorLength ? nil : value }
        }
        if state.hasVersionMismatch {
            Text("This project uses an older stitch engine. Its saved preview is preserved.").font(Theme.body(11)).foregroundStyle(.orange)
            Button("Regenerate with current engine") { var next = state.design; next.engineVersion = Design.engineVersion; state.document?.replace(next, action: "Regenerate Project") }.buttonStyle(ThemedButtonStyle(prominent: true))
                .help("Work out this older project's stitches again with the current stitch engine, so you can edit it. The stitches may change slightly.")
        }
        if let error = state.generationError { Text(error).font(Theme.body(11)).foregroundStyle(.red) }
        ForEach(state.plan.warnings, id: \.self) { warning in Label(warning, systemImage: "exclamationmark.circle").font(Theme.body(11)).foregroundStyle(.orange) }
    }
    /// Tie stitches: how many lock stitches tie the thread in and off, and how long each is.
    private var tieStitchesRow: some View {
        HStack {
            Text("Tie stitches").font(Theme.body(11, weight: .regular)); Spacer()
            Picker("Tie stitches", selection: Binding(get: { state.design.tieCount ?? Design.defaultTieCount },
                                                      set: { count in state.edit("Tie Stitches") { $0.tieCount = count == Design.defaultTieCount ? nil : count } })) {
                ForEach(Array(Design.tieCounts), id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden().fixedSize()
            Text("×").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            NumberField(value: state.design.tieLength ?? Design.defaultTieLength, range: Design.tieLengths, unit: preferences.unit,
                        commit: { value in state.edit("Tie Stitch Length") { $0.tieLength = value == Design.defaultTieLength ? nil : value } },
                        focusCanvas: state.focusCanvas).frame(width: 60, height: 21)
            Text(preferences.unit.symbol).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).fixedSize().frame(width: 18, alignment: .leading)
        }
        .help("How many tiny locking stitches tie the thread in and off, and how long each one is (1 × 0.6 mm unless changed).")
    }
    /// The Trim after menu: Off, Always, or When far (showing the design's trim distance), for every selected object.
    func trimMenu(_ object: RunObject) -> some View {
        let distance = preferences.unit.short(state.design.trimDistance ?? Design.defaultTrimDistance)
        return Picker("Trim after", selection: Binding(get: { object.trimRule }, set: { rule in state.editSelected("Trim After") { $0.trimRule = rule } })) {
            ForEach(TrimRule.allCases, id: \.self) { rule in Text(rule == .whenFar ? "When far (\(distance))" : rule.title).tag(rule) }
        }.font(Theme.body(12, weight: .semibold))
    }
    /// The hoop menu: your own hoops, then the common hoops grouped by brand. Its button shows the current hoop, e.g.
    /// "Brother 5 × 7 in · 130 × 180 mm".
    private var hoopMenu: some View {
        Menu {
            HoopMenuItems { setHoop($0, "Choose Hoop") }
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
            number("Width", value: artwork.width, range: 0.1...1000, length: true, help: "The reference image's width; its height follows.") { value in state.edit("Scale Artwork") { design in design.artwork?.width = value; design.artwork?.height = artwork.height * value / artwork.width } }
            number("Center X", value: artwork.center.x, range: -1000...1000, length: true, help: "Where the image's center sits, right of the hoop's center (left is negative).") { value in state.edit("Move Artwork") { $0.artwork?.center.x = value } }
            number("Center Y", value: artwork.center.y, range: -1000...1000, length: true, help: "Where the image's center sits, above the hoop's center (below is negative).") { value in state.edit("Move Artwork") { $0.artwork?.center.y = value } }
            toggle("Show reference", value: artwork.visible) { _ in AppDelegate.shared.perform(.artwork) }.help(preferences.hint(.artwork))
            Button { AppDelegate.shared.perform(.autoDigitize) } label: { Label("Auto-digitize…", systemImage: "wand.and.rays") }.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.autoDigitize))
        } else {
            Text("No reference image").font(Theme.heading(16))
            Button { AppDelegate.shared.perform(.importImage) } label: { Label("Import artwork…", systemImage: "photo.badge.plus") }.buttonStyle(ThemedButtonStyle()).help(preferences.hint(.importImage))
        }
    }
    /// The artwork's opacity as a slider with a % readout. The image fades live while it's dragged; letting go saves
    /// it as one undoable step.
    private func opacitySlider(_ saved: Double) -> some View {
        let shown = state.artworkOpacityPreview ?? saved
        return HStack {
            Text("Opacity").font(Theme.body(11, weight: .regular))
            Slider(value: Binding(get: { shown }, set: { state.previewArtworkOpacity($0) }), in: 0...1, onEditingChanged: { state.artworkOpacitySlider(editing: $0) })
                .controlSize(.small).tint(Theme.accent)
            Text("\(Int((shown * 100).rounded()))%").font(Theme.body(11)).monospacedDigit().frame(width: 36, alignment: .trailing)
        }
        .help("How see-through the reference image is: drag left to fade it, right to make it solid")
    }
    var sectionDivider: some View { Theme.divider.frame(height: 1) }
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
    // The helpers below are used by the Properties layout in ProViews.swift, so they aren't private.
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
            Button("Remove overlaps") { AppDelegate.shared.perform(.removeOverlaps) }
                .buttonStyle(ThemedButtonStyle()).help(preferences.hint(.removeOverlaps))
            // Align and space: objects line up with the one selected last.
            HStack(spacing: 0) {
                ForEach([CommandID.alignLeft, .alignCentersVertically, .alignRight, .alignTop, .alignCentersHorizontally, .alignBottom, .alignCenters], id: \.self) { alignButton($0) }
                Theme.controlBorder.frame(width: 1, height: 16).padding(.horizontal, 4)
                alignButton(.spaceAcross); alignButton(.spaceDown)
            }
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
    /// Regenerate swaps them for fresh ones now.
    func stitchEditNotice(_ object: RunObject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Stitches edited by hand", systemImage: CommandID.editStitches.symbol).font(Theme.body(12, weight: .bold))
                Spacer()
                Button("Regenerate") { state.editSelected("Regenerate Stitches") { $0.stitchEdits = nil } }.buttonStyle(ThemedButtonStyle())
                    .help("Throw away the hand edits and work the stitches out again from the shape and settings")
            }
        }
        .padding(10).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
    }
    /// The stitch angle lines of a tatami or satin fill: how many, Add (the Add Stitch Angles tool) and Remove all.
    func stitchAngles(_ object: RunObject) -> some View {
        let count = object.settings.angleLines?.count ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(count == 0 ? "Stitch angles: straight rows" : "Stitch angles: \(count) line\(count == 1 ? "" : "s")").font(Theme.body(12, weight: .semibold))
                Spacer()
                Button("Add…") { AppDelegate.shared.perform(.addStitchAngles) }.help(preferences.hint(.addStitchAngles))
                if count > 0 { Button("Remove all") { settings(.fill, "Remove Stitch Angles") { $0.angleLines = nil } }.help("Take out every stitch angle line, so the fill sews straight rows again.") }
            }.buttonStyle(ThemedButtonStyle())
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
            Text(title).font(Theme.body(11, weight: .regular)); Spacer()
            Text("X").font(Theme.body(10)).foregroundStyle(Theme.inkSecondary)
            NumberField(value: point.x, range: -1000...1000, unit: preferences.unit, commit: { commit(Point($0, point.y)) }, focusCanvas: state.focusCanvas).frame(width: 60, height: 21)
            Text("Y").font(Theme.body(10)).foregroundStyle(Theme.inkSecondary)
            NumberField(value: point.y, range: -1000...1000, unit: preferences.unit, commit: { commit(Point(point.x, $0)) }, focusCanvas: state.focusCanvas).frame(width: 60, height: 21)
            Text(preferences.unit.symbol).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary)
        }
        .help("\(title) point, from the hoop's center")
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
    /// Satin's two automatic helpers, as checkboxes.
    @ViewBuilder func satinOptions(_ object: RunObject) -> some View {
        toggle("Short stitches on curves", value: object.settings.shortStitches == true) { on in settings(.satin, "Short Stitches") { $0.shortStitches = on } }
            .help("On the inside of a curve, every other stitch stops short so thread doesn't pile up into a hard ridge.")
        toggle("Split wide satin", value: object.settings.autoSplit == true) { on in settings(.satin, "Split Wide Satin") { $0.autoSplit = on } }
            .help("Stitches longer than the maximum stitch are split into shorter ones, staggered like bricks, instead of the column being refused.")
        toggle("Raised (padded)", value: object.settings.raised == true) { on in settings(.satin, "Raised Satin") { $0.raised = on ? true : nil } }
            .help("Lanes of padding stitches are sewn along the column first, so the satin stands up off the fabric for a 3D look. Uses more thread; best on columns 3 mm and wider.")
    }
    /// Satin from a center line: a width and a button that turns this line into a satin column.
    @ViewBuilder func satinLine(_ object: RunObject) -> some View {
        number("Satin width", value: preferences.data.satinLineWidth ?? SatinLine.defaultWidth, range: SatinLine.widths, help: "Turn this line into a satin column this wide, centered on the line.") { value in preferences.data.satinLineWidth = value; preferences.save() }
        Button("Make satin column") { AppDelegate.shared.perform(.convertSatin) }.buttonStyle(ThemedButtonStyle())
            .help("Turn this line into a satin column centered on it (\(Preferences.shared.label(.convertSatin).isEmpty ? "Digitize menu" : Preferences.shared.label(.convertSatin)))")
    }
    /// The settings a fill style has of its own: stipple spacing; a motif fill's motif, size and gap; a cross stitch
    /// fill's square size; a gradient fill's row spacing where it starts and ends; a satin fill's splitting.
    @ViewBuilder func patternSettings(_ object: RunObject) -> some View {
        let s = object.settings
        switch s.fillStyle ?? .tatami {
        case .tatami where !(s.angleLines ?? []).isEmpty:
            EmptyView()   // patterns are for straight rows: with stitch angle lines, the rows keep the Smooth pattern
        case .tatami:
            let pattern = TatamiPattern.of(s)
            HStack {
                Text("Pattern").font(Theme.body(11, weight: .regular)); Spacer()
                TatamiPatternMenu(state: state, pattern: pattern, color: object.color) { value in settings(.fill, "Tatami Pattern") { $0.tatamiPattern = value == .smooth ? nil : value.id } }
                    .frame(width: 120)
            }
            .help("Where each row's needle holes go. The lines of holes make a texture in the fill: zigzags, waves, blocks. \(pattern.name): \(pattern.tagline)")
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
            number("Spacing at start", value: s.gradientStart ?? DigitizingSettings.defaultGradientStart, range: DigitizingSettings.gradientSpacingRange, help: gradientHelp) { value in settings(.fill, "Gradient Start") { $0.gradientStart = value } }
            number("Spacing at end", value: s.gradientEnd ?? DigitizingSettings.defaultGradientEnd, range: DigitizingSettings.gradientSpacingRange, help: gradientHelp) { value in settings(.fill, "Gradient End") { $0.gradientEnd = value } }
        case .satin:
            // For fills, Auto split is on unless turned off (nil counts as on).
            toggle("Auto split", value: s.autoSplit != false) { on in settings(.fill, "Auto Split") { $0.autoSplit = on ? nil : false } }
                .help("Stitches longer than the split length are broken into shorter ones, in bands that follow the shape's edge, so wide parts don't get long, loose stitches.")
            number("Split length", value: s.satinSplit ?? DigitizingSettings.defaultSatinSplit, range: DigitizingSettings.satinSplitRange, length: true, help: "The longest satin stitch. Longer ones are split with Auto split on; with it off, the shape must be narrower than this.") { value in settings(.fill, "Split Length") { $0.satinSplit = value == DigitizingSettings.defaultSatinSplit ? nil : value } }
        default: EmptyView()
        }
    }
    /// The pattern a motif run or motif fill repeats: a built-in one, or one of My motifs (Edit › Create Motif…),
    /// which is copied into the object's settings so the design keeps it even if it's later deleted from My motifs.
    func motifPicker(_ object: RunObject, kind: StitchKind) -> some View {
        let s = object.settings
        return HStack {
            Text("Motif").font(Theme.body(11, weight: .regular)); Spacer()
            Menu {
                ForEach(Motif.allCases, id: \.self) { motif in
                    Button(motif.title) { settings(kind, "Motif") { $0.motif = motif == .heart ? nil : motif; $0.customMotif = nil } }
                }
                if !preferences.myMotifs.isEmpty {
                    Section("My motifs") {
                        ForEach(preferences.myMotifs) { motif in Button(motif.name) { settings(kind, "Motif") { $0.customMotif = motif; $0.motif = nil } } }
                    }
                }
                Divider()
                Button("Edit My Motifs…") { SettingsNavigation.shared.page = .newDesigns; AppDelegate.shared.showSettings() }
            } label: { Text(s.customMotif?.name ?? (s.motif ?? .heart).title) }
            .frame(width: 120)
        }
        .help("The pattern that's repeated. Make your own from running lines with \(CommandID.createMotif.title) in the Edit menu.")
    }
    /// A line's stitch style (running, zigzag, blanket, back or stem stitch, motif), with the width and spacing the style
    /// uses. The style's explanation shows as a tooltip.
    @ViewBuilder func runStyle(_ object: RunObject) -> some View {
        let style = object.settings.runStyle ?? .running
        HStack {
            Text("Line style").font(Theme.body(11, weight: .regular)); Spacer()
            LineStyleMenu(state: state, style: style, color: object.color) { value in
                settings(.run, "Line Style") { $0.runStyle = value == .running ? nil : value; $0.runWidth = nil; $0.runSpacing = nil }
            }.frame(width: 120)
        }
        .help(style.summary)
        if style == .motif { motifPicker(object, kind: .run) }
        if style.hasWidth {
            number(style == .blanket ? "Prong length" : style == .motif ? "Motif size" : "Width", value: object.settings.runWidth ?? DigitizingSettings.defaultRunWidth(style), range: DigitizingSettings.runWidthRange,
                   help: style == .blanket ? "How far each prong reaches from the line (mm)." : style == .motif ? "How long each motif is along the line (mm)." : "How wide the stitch is across the line (mm).") { value in settings(.run, "Line Width") { $0.runWidth = value } }
        }
        if style.hasSpacing {
            number(style == .blanket ? "Prong spacing" : style == .motif ? "Gap" : "Spacing", value: object.settings.runSpacing ?? DigitizingSettings.defaultRunSpacing(style), range: DigitizingSettings.runSpacingRange,
                   help: style == .blanket ? "How far apart the prongs are along the line (mm)." : style == .motif ? "The running stitch between motifs (mm)." : "How far the needle moves along the line with each swing (mm). Smaller is denser.") { value in settings(.run, "Line Spacing") { $0.runSpacing = value } }
        }
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
    /// Running stitch passes: Single, or bean stitch sewing each stitch 3 or 5 times.
    func runPasses(_ object: RunObject) -> some View {
        HStack {
            Text("Passes").font(Theme.body(11, weight: .regular)); Spacer()
            Picker("Passes", selection: Binding(get: { object.settings.runPasses ?? 1 }, set: { value in settings(.run, "Running Passes") { $0.runPasses = value == 1 ? nil : value } })) {
                Text("Single").tag(1); Text("Bean ×3").tag(3); Text("Bean ×5").tag(5)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
        }
        .help("How many times each stitch is sewn. Bean stitch (3 or 5) goes forward, back and forward again for a bold line.")
    }
    func settings(_ kind:StitchKind,_ title:String,_ body:@escaping(inout DigitizingSettings)->Void){state.editSelected(title){object in guard object.kind==kind else{return};var s=object.settings;body(&s);object.digitizing=s}}
    /// A labeled number field. `help` explains the setting, as a tooltip.
    /// `length` marks a size or position: it's shown and typed in the chosen unit (mm or inches), with the unit beside it.
    @ViewBuilder func number(_ title: String, value: Double, id: String = "", range: ClosedRange<Double>, length: Bool = false, help: String? = nil, commit: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(Theme.body(11, weight: .regular)); Spacer()
            NumberField(value: value, identifier: id, range: range, unit: length ? preferences.unit : nil, commit: commit, focusCanvas: state.focusCanvas).frame(width: 84, height: 21)
            if length { Text(preferences.unit.symbol).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).fixedSize().frame(width: 18, alignment: .leading) }
        }
        .help(help ?? "")
    }
    /// Width, for even-width satins (satin borders and satins made from a line): typing a new one rebuilds the satin
    /// around its middle line. Hand-drawn columns, whose width varies, don't show it.
    @ViewBuilder func satinWidth(_ object: RunObject) -> some View {
        if let width = SatinLine.evenWidth(of: object) {
            number("Width", value: (width * 100).rounded() / 100, range: SatinLine.widths, length: true,
                   help: "How wide the satin is. Type a new width and press Return; it stays centered where it is.") { state.setSatinWidth($0) }
            toggle("Smart corners", value: object.settings.smartCorners == true) { state.setSmartCorners($0) }
                .help("Sharp corners (under 75°) get a sharp mitred point, and very sharp ones (under 45°) a cap, instead of being rounded off")
        }
    }
    func toggle(_ title: String, value: Bool, action: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: action)).font(Theme.body(11)).toggleStyle(.checkbox)
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
                                                    spacing: settings.runSpacing ?? DigitizingSettings.defaultRunSpacing(runStyle), length: stitchLength, motif: settings.motifStroke) ?? []
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

/// Stop at Jumps, for machines without a thread cutter (JumpStops.swift): adds a stop after each jump in the
/// selection (or the whole design when nothing is selected), and takes those stops off again.
struct JumpStopsButton: View {
    @ObservedObject var state: EditorState
    var body: some View {
        let removing = state.design.hasJumpStops(in: state.jumpStopScope)
        let scope = state.selection.isEmpty ? "the design" : "the selection"
        Button(removing ? "Remove Jump Stops" : "Stop at Jumps") { state.toggleJumpStops() }
            .buttonStyle(ThemedButtonStyle())
            .help(removing ? "Take off the stops Stop at Jumps added in \(scope). Stops you set yourself stay."
                  : "The machine pauses after each jump in \(scope), as for a thread change, so you can snip the loose thread. Press Start to carry on in the same thread.")
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
                ProStats(state: state, pointer: state.pointer)
                Text("\(Int(state.zoom * 20))%").foregroundStyle(Theme.inkSecondary)
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
            let hoopings = state.design.multiHooping?.hoopings.count
            chip("Ready", symbol: "checkmark.circle.fill", color: Theme.success)
                .help(hoopings == nil ? "Ready to save: the stitches are up to date and fit the hoop" : "Ready to save: the stitches are up to date and everything fits a hooping")
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
        // A multi-hooped design instead needs everything to fit a hooping (MultiHooping.swift).
        if let unplaced = state.hoopingAssignment?.unplaced, !unplaced.isEmpty { problems.append("Something fits no hooping") }
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
