// The editor's compact views: the precision bar under the tool strip, for placing the selection exactly; the sewing
// order table; the Threads panel; the status bar's numbers; and the Properties layout. (Named "Pro" from when OpenHoop
// also had a Guided view.)
import AppKit
import SwiftUI
import EmbroideryCore

/// One row under the Pro tool strip: the selection's name; its exact center (X, Y), size (W, H, optionally keeping
/// proportions) and a "rotate by" angle; the arrow keys' nudge distance (while something is selected); and one-click
/// arrange buttons.
struct PrecisionBar: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        let ids = state.editableSelection, box = state.design.bounds(of: ids)
        HStack(spacing: 8) {
            Text(title).font(Theme.body(12, weight: .bold)).lineLimit(1).frame(width: 140, alignment: .leading)
            if let box {
                let center = (box.min + box.max) * 0.5, width = box.max.x - box.min.x, height = box.max.y - box.min.y
                field("X", center.x, range: -1000...1000, length: true, help: "Center of the selection, from the hoop's center") { state.moveSelection(centerX: $0) }
                field("Y", center.y, range: -1000...1000, length: true, help: "Center of the selection, from the hoop's center (up is positive)") { state.moveSelection(centerY: $0) }
                if width > 0.001 { field("W", width, range: 0.1...1000, length: true, help: "Width of the selection") { resize(width: $0, from: width, height) } }
                if height > 0.001 { field("H", height, range: 0.1...1000, length: true, help: "Height of the selection") { resize(height: $0, from: width, height) } }
                unitLabel   // one label for X, Y, W and H
                let keep = preferences.data.keepProportions ?? true
                Button { preferences.data.keepProportions = !keep; preferences.save() } label: {
                    Image(systemName: keep ? "link" : "link.badge.plus").font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 20)
                        .background(keep ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(keep ? Theme.accent : Theme.inkSecondary)
                }
                .buttonStyle(.plain).help(keep ? "Keeping proportions: W and H change together. Click to size them separately." : "W and H change separately. Click to keep proportions.")
                .accessibilityLabel("Keep proportions").accessibilityAddTraits(keep ? .isSelected : [])
                field("Rotate", 0, range: -360...360, help: "Type an angle and press Return to turn the selection by it (positive turns counterclockwise)") { state.rotateSelection(by: $0) }
                field("Skew", 0, range: -60...60, help: "Type an angle and press Return to lean the selection sideways by it (positive leans the top to the right, like italics)") { state.skewSelection(by: $0) }
                // Only with something to move.
                Theme.controlBorder.frame(width: 1, height: 18)
                field("Nudge", preferences.nudge, range: Preferences.nudgeRange, length: true, help: "How far the arrow keys move the selection") { value in
                    preferences.data.nudgeDistance = value; preferences.save()
                }
                unitLabel
            } else {
                Text("Select objects to place them exactly").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                arrange(.mirrorH, "arrow.left.and.right.righttriangle.left.righttriangle.right")
                arrange(.mirrorV, "arrow.up.and.down.righttriangle.up.righttriangle.down")
                arrange(.rotateLeft, "rotate.left"); arrange(.rotateRight, "rotate.right")
                arrange(.earlier, "arrow.up"); arrange(.later, "arrow.down"); arrange(.sequenceBySelection, "list.number"); arrange(.sequenceByColor, "paintpalette")
                arrange(.group, "square.on.square"); arrange(.ungroup, "square.dashed")
                arrange(.lockObject, state.selected?.locked == true ? "lock.open" : "lock")
            }
            .disabled(state.selection.isEmpty)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .controlSize(.small)
        .foregroundStyle(Theme.ink)
        .background(Theme.ground)
    }

    /// The selection's name: one object, a group, or a count.
    private var title: String {
        let chosen = state.design.objects.filter { state.selection.contains($0.id) }
        guard let first = chosen.first else { return "Nothing selected" }
        if chosen.count == 1 { return first.name }
        if let group = first.groupID, chosen.allSatisfy({ $0.groupID == group }), let label = state.design.groupLabels[group] { return "\(label) · \(chosen.count) objects" }
        return "\(chosen.count) objects"
    }

    /// A small label and number field. Return (or leaving the field) commits; Escape puts the value back.
    /// `length` marks a size or position, shown and typed in the chosen unit (mm or inches).
    private func field(_ label: String, _ value: Double, range: ClosedRange<Double>, length: Bool = false, help: String, commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize()   // labels never get squeezed out
            NumberField(value: value, range: range, unit: length ? preferences.unit : nil, commit: commit, focusCanvas: state.focusCanvas).frame(width: 56, height: 20)
        }
        .help(help)
    }
    /// The unit after a run of length fields: "mm" or "in".
    private var unitLabel: some View { Text(preferences.unit.symbol).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).fixedSize() }

    /// Resizes the selection to a typed width or height; with proportions kept, the other side follows.
    private func resize(width: Double? = nil, height: Double? = nil, from oldWidth: Double, _ oldHeight: Double) {
        guard preferences.data.keepProportions ?? true else { state.resizeSelection(width: width, height: height); return }
        let factor = width.map { $0 / oldWidth } ?? height.map { $0 / oldHeight } ?? 1
        state.resizeSelection(width: oldWidth > 0.001 ? oldWidth * factor : nil, height: oldHeight > 0.001 ? oldHeight * factor : nil)
    }

    private func arrange(_ command: CommandID, _ symbol: String) -> some View {
        Button { AppDelegate.shared.perform(command) } label: {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preferences.hint(command))
        .accessibilityLabel(command.title)
    }
}

/// The sewing order: a compact table with each object's number, thread, stitch type (as an icon; the
/// full name shows on hover), name, stitch count, flags (T = trims after, S = stops after, H = hidden but still sews) and a
/// lock to click (LayerControls.swift; right-click a line to rename, lock or hide). Objects grouped together in a row of the sewing order
/// fold under one line for the group (lettering shows its text); the chevron opens it to show each object.
struct ProSewingOrder: View {
    @ObservedObject var state: EditorState
    /// The groups opened to show their objects (closed by default, so lettering takes one line).
    @State private var opened: Set<UUID> = []
    /// The object whose name is being typed over (after a double-click), if any.
    @State private var renaming: UUID?
    /// Where dragged objects would land (a sewing order index), while a drag is over the table.
    @State private var dropTarget: Int?
    /// The line the pointer is over (its `Line.id`), which shows its lock faintly.
    @State private var hovered: String?

    /// One line of the table: an object, or a group's heading line.
    private enum Line: Identifiable {
        case object(index: Int, RunObject, indented: Bool)
        case group(id: UUID, first: Int, members: [RunObject])
        case picture   // the reference picture's place (ArtworkLayer.swift)
        var id: String {
            switch self {
            case .picture: return "picture"
            case .object(_, let object, _): return object.id.uuidString
            case .group(let id, let first, _): return "\(id.uuidString)-\(first)"
            }
        }
    }

    /// The table's lines: runs of two or more consecutive objects in the same group become a group line,
    /// followed by their objects when the group is open.
    private var lines: [Line] {
        var lines: [Line] = [], index = 0
        let objects = state.design.objects
        while index < objects.count {
            let object = objects[index]
            var end = index + 1
            if let group = object.groupID { while end < objects.count && objects[end].groupID == group { end += 1 } }
            if let group = object.groupID, end - index >= 2 {
                lines.append(.group(id: group, first: index, members: Array(objects[index..<end])))
                // Lettering is one object: its line never opens into letter parts.
                if opened.contains(group) && object.lettering == nil { for i in index..<end { lines.append(.object(index: i, objects[i], indented: true)) } }
            } else {
                for i in index..<end { lines.append(.object(index: i, objects[i], indented: false)) }
            }
            index = end
        }
        // The picture goes before the first line of the object it sits above (never inside a group: moving it skips
        // whole groups), or at the end.
        if state.design.artwork != nil {
            let layer = state.design.artworkLayer
            let at = lines.firstIndex { line in
                switch line { case .object(let index, _, _): return index >= layer; case .group(_, let first, _): return first >= layer; case .picture: return false }
            } ?? lines.count
            lines.insert(.picture, at: at)
        }
        return lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(number: "#", swatch: nil, symbol: nil, name: Text("NAME"), stitches: "STITCHES", flags: "")
                .font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSecondary)
                .frame(height: 18)
            Theme.divider.frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    let counts = state.stitchCounts, labels = state.design.groupLabels
                    let warned = state.reviewing ? state.warnedObjects : []   // marked while reviewing the sewing order
                    ForEach(lines) { line in
                        switch line {
                        case .object(let index, let object, let indented):
                            // A row inside an opened group drags just that object; otherwise its whole group comes along.
                            objectRow(index, object, indented: indented, count: counts[object.id], warned: warned.contains(object.id))
                                .sewingOrderRow(state: state, ids: indented ? [object.id] : state.design.groupMembers(of: object.id), place: index, target: $dropTarget)
                        case .group(let id, let first, let members):
                            groupRow(id, first: first, members: members, label: labels[id], count: members.compactMap { counts[$0.id] }.reduce(0, +),
                                     warned: members.contains { warned.contains($0.id) })
                                .sewingOrderRow(state: state, ids: Set(members.map(\.id)), place: first, target: $dropTarget)
                        case .picture: PictureRow(state: state).padding(.vertical, 2)
                        }
                    }
                    if !state.design.objects.isEmpty { Color.clear.sewingOrderEnd(state: state, target: $dropTarget) }
                    if state.design.objects.isEmpty { Text("Objects appear here in sewing order.").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).padding(.vertical, 20) }
                }
            }
            .frame(maxHeight: .infinity)
            Theme.divider.frame(height: 1)
            HStack(spacing: 10) {
                icon(.earlier, "arrow.up"); icon(.later, "arrow.down"); icon(.sequenceByColor, "paintpalette"); Spacer(); icon(.duplicate, "plus.square.on.square"); icon(.delete, "trash")
            }
            .padding(.top, 6)
        }
        .foregroundStyle(Theme.ink)
    }

    /// The table's columns, shared by the heading and every line so they stay lined up.
    /// `warned` puts a warning triangle in the type-icon column (a step Review Sewing Order warns about).
    private func row<Name: View>(number: String, swatch: Color?, symbol: String?, name: Name, stitches: String, flags: String, indent: Bool = false, warned: Bool = false) -> some View {
        HStack(spacing: 4) {   // kept tight so the name column gets as much of a narrow panel as possible
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.inkSecondary).lineLimit(1).frame(width: 20, alignment: .leading)
            Group { if let swatch { RoundedRectangle(cornerRadius: 2).fill(swatch).overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.25))) } else { Color.clear } }
                .frame(width: 10, height: 10)
            Group {
                if warned { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Theme.primaryAction).help("Review Sewing Order warns about the move to this step") }
                else if let symbol { Image.symbol(symbol, size: 10).font(.system(size: 10)).foregroundStyle(Theme.inkSecondary) } else { Color.clear }
            }
                .frame(width: 14, height: 12)
            name.lineLimit(1).truncationMode(.tail).padding(.leading, indent ? 10 : 0).frame(maxWidth: .infinity, alignment: .leading)
            Text(stitches).font(.system(size: 10, design: .monospaced)).fixedSize().frame(width: 46, alignment: .trailing)   // fixedSize: the "STITCHES" heading may spill left, never truncate
            Text(flags).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.inkSecondary).lineLimit(1).frame(width: 22, alignment: .leading)
            Color.clear.frame(width: 16)   // the lock (RowLock) sits over this column
        }
        .font(Theme.body(11))
        .padding(.horizontal, 4)
    }

    private func objectRow(_ index: Int, _ object: RunObject, indented: Bool, count: Int?, warned: Bool) -> some View {
        let selected = state.selection.contains(object.id)
        let flags = [object.trimAfter ? "T" : "", object.stopAfter ? "S" : "", object.visible ? "" : "H"].joined()
        let type = object.kind == .raw ? "Imported stitches" : object.stitchTitle
        let notes = [object.trimAfter ? (object.trimRule == .always ? ", trims after" : ", trims after when far") : "", object.stopAfter ? ", stops after" : "", object.locked ? ", locked" : "", object.visible ? "" : ", hidden (still sews)"].joined()
        return Button { state.listClick(object.id, single: indented) } label: {
            row(number: "\(index + 1)", swatch: Color(nsColor: object.color.nsColor), symbol: Self.symbol(object), name: Text(object.name),
                stitches: count.map { $0.formatted() } ?? "–", flags: flags, indent: indented, warned: warned)
                .frame(height: 22)
                .background(selected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if object.lettering == nil { renaming = object.id } })
        .overlay(alignment: .leading) {
            // The rename box sits over the name column while typing (past the number, swatch and type icon).
            if renaming == object.id {
                RenameField(state: state, object: object, font: Theme.body(11),
                            editing: Binding(get: { renaming == object.id }, set: { if !$0 { renaming = nil } }))
                    .padding(.leading, indented ? 62 : 52).padding(.trailing, 72)
            }
        }
        .help("\(object.name): \(type), \(object.color.name) thread\(notes). Double-click the name to rename it; drag to change when it sews.")
        .overlay(alignment: .trailing) { RowLock(state: state, ids: [object.id], showing: hovered == object.id.uuidString).padding(.trailing, 4) }
        .onHover { inside in hovered = inside ? object.id.uuidString : (hovered == object.id.uuidString ? nil : hovered) }
        .contextMenu { layerMenu(state: state, ids: [object.id], rename: object.lettering == nil ? { renaming = object.id } : nil) }
    }

    /// A group's line: open/close chevron (in the type-icon column, so the name keeps the table's full width),
    /// what it is (lettering shows its text) with the group label, and total stitches.
    private func groupRow(_ id: UUID, first: Int, members: [RunObject], label: String?, count: Int, warned: Bool) -> some View {
        let open = opened.contains(id), selected = members.allSatisfy { state.selection.contains($0.id) }
        let lettering = members.first?.lettering
        let title = lettering.map { "“\($0.lines.joined(separator: " / "))”" } ?? "\(members.count) objects"
        let colors = Set(members.map(\.color))
        return Button { state.listClick(members[0].id) } label: {
            row(number: "\(first + 1)", swatch: colors.count == 1 ? Color(nsColor: members[0].color.nsColor) : nil, symbol: nil,
                name: groupName(title, label: lettering == nil ? label : nil),
                stitches: count.formatted(), flags: "", warned: warned)
                .frame(height: 22)
                .background(selected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(lettering == nil ? "Group of \(members.count) objects, sewing \(first + 1)–\(first + members.count). Drag to change when it sews." : "Lettering, sewing \(first + 1)–\(first + members.count). Edit it in Properties; Break Apart Lettering splits it into shapes.")
        // The group's lock and menu act on all its objects.
        .overlay(alignment: .trailing) { RowLock(state: state, ids: Set(members.map(\.id)), showing: hovered == "\(id.uuidString)-\(first)").padding(.trailing, 4) }
        .onHover { inside in let key = "\(id.uuidString)-\(first)"; hovered = inside ? key : (hovered == key ? nil : hovered) }
        .contextMenu { layerMenu(state: state, ids: Set(members.map(\.id)), rename: nil) }
        .overlay(alignment: .leading) {
            // Drawn over the row's empty icon column: 4 (padding) + 20 (number) + 4 + 10 (swatch) + 4. Lettering has
            // none: it's one object.
            if lettering == nil {
                Button { if open { opened.remove(id) } else { opened.insert(id) } } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).frame(width: 14, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.leading, 42)
                .accessibilityLabel(open ? "Close \(label ?? "group")" : "Open \(label ?? "group")")
            }
        }
    }

    /// A group's title, followed by its label (such as "Group A") as a small chip when it has one.
    @ViewBuilder private func groupName(_ title: String, label: String?) -> some View {
        let text = Text(title).font(Theme.body(11, weight: .semibold))
        if let label {
            HStack(spacing: 4) {
                text.layoutPriority(1)   // the text gets room before the label
                Text(label).font(Theme.body(9, weight: .bold)).lineLimit(1).padding(.horizontal, 4).background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent)
            }
        } else {
            text
        }
    }

    /// A small icon for an object's stitch type, matching the tool that makes it.
    static func symbol(_ object: RunObject) -> String {
        switch object.kind {
        case .run: return CommandID.runTool.symbol
        case .satin: return CommandID.satinTool.symbol
        case .fill: return "square.grid.2x2"   // the tool's filled square would look like a thread swatch here
        case .raw: return "waveform.path"
        case .vector: return "scribble"
        }
    }

    private func icon(_ command: CommandID, _ symbol: String) -> some View {
        Button { AppDelegate.shared.perform(command) } label: { Image(systemName: symbol) }.buttonStyle(.borderless).help(Preferences.shared.hint(command))
    }
}

/// The Threads panel: the thread library as a two-column list of swatch, name and number (click to choose the
/// current thread and recolor the selection), then the design's thread steps in sewing order with their stitch counts.
/// The bar between them drags to make the steps list taller or shorter; double-clicking it lets the list fit its steps again.
struct ProThreads: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// The steps list's height while the bar is being dragged (saved when the drag ends), and as last laid out.
    @State private var draggedHeight: Double?
    @State private var shownHeight: Double = 0
    @State private var dragBase: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // At least three rows; every bit of height the sewing order list doesn't need goes to the library, so a
            // taller panel shows more threads (and a wider one more columns).
            ThreadLibraryView(state: state, layout: .list(minColumnWidth: 100), minHeight: 64)
            divider
            HStack {
                Text("IN SEWING ORDER").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(Theme.inkSecondary)
                Spacer()
                JumpStopsButton(state: state)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.summary.steps, id: \.number) { step in
                        HStack(spacing: 8) {
                            Text("\(step.number)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.inkSecondary).frame(width: 18, alignment: .leading)
                            Circle().fill(Color(nsColor: step.color.nsColor)).frame(width: 11, height: 11).overlay(Circle().strokeBorder(Color.black.opacity(0.25)))
                            Text(step.color.name).font(Theme.body(11)).lineLimit(1)
                            // A chart thread shows its color number (the spool to load); a plain color shows its hex value.
                            Text(step.color.code ?? String(format: "#%06X", step.color.hex)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.inkSecondary)
                            Spacer(minLength: 4)
                            if step.stopAfter { Text("STOP").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(Theme.primaryAction) }
                            Text(step.stitches.formatted()).font(.system(size: 10, design: .monospaced))
                        }
                        .frame(height: 20)
                        .help(step.parts.joined(separator: ", "))
                    }
                }
            }
            // As tall as it was dragged to, or else as its steps need. The list asks first (layoutPriority), but never
            // for the library's last three rows, so in a short panel it gets less than asked rather than spilling out.
            .frame(minHeight: 0, maxHeight: Self.stepsHeight(dragged: draggedHeight ?? preferences.data.threadStepsHeight, steps: state.summary.steps.count))
            .onGeometryChange(for: Double.self) { $0.size.height } action: { shownHeight = $0 }
            .layoutPriority(1)
        }
        .foregroundStyle(Theme.ink)
    }

    /// The steps list's height: the dragged height if there is one, else room for its steps (two at least, eight at most).
    static func stepsHeight(dragged: Double?, steps: Int) -> Double {
        dragged ?? max(44, min(Double(steps) * 20 + 4, 164))
    }

    /// The bar above the steps list, drawn like the one between panel groups. Dragging it up makes the list taller.
    private var divider: some View {
        Theme.card.frame(height: 8).frame(maxWidth: .infinity)
            .overlay(Capsule().fill(Theme.controlBorder).frame(width: 36, height: 3))
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .help("Drag to show more threads or more sewing steps. Double-click to fit the steps again.")
            .onTapGesture(count: 2) { draggedHeight = nil; preferences.data.threadStepsHeight = nil; preferences.save(announce: false) }
            // Measured in window coordinates, so the distance doesn't change as the bar moves with the list.
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    if dragBase == nil { dragBase = shownHeight }   // starts from the height on screen, which may be less than asked
                    draggedHeight = max(0, (dragBase ?? 0) - drag.translation.height)
                }
                .onEnded { _ in
                    // Saved as the height it ended up on screen, so a drag past the library's minimum doesn't stick.
                    if draggedHeight != nil { preferences.data.threadStepsHeight = shownHeight; preferences.save(announce: false) }
                    draggedHeight = nil; dragBase = nil
                })
    }
}

/// The status bar's numbers: stitches, thread steps, trims, stops, size and estimated sewing time, plus
/// where the pointer is.
struct ProStats: View {
    @ObservedObject var state: EditorState
    @ObservedObject var pointer: PointerReadout
    @ObservedObject var preferences = Preferences.shared   // redraws when mm/inches is switched
    var body: some View {
        let summary = state.summary, speed = Preferences.shared.data.machineSpeed ?? ProductionSummary.defaultSpeed
        HStack(spacing: 12) {
            if let p = pointer.position { Text("x \(preferences.unit.number(p.x, decimals: 2))  y \(preferences.unit.number(p.y, decimals: 2)) \(preferences.unit.symbol)").font(.system(size: 10, design: .monospaced)).frame(width: 150, alignment: .trailing) }
            Text("\(summary.stitchCount.formatted()) st").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.ink)
            Text([Self.count(summary.steps.count, "step"), Self.count(summary.trims, "trim"), Self.count(summary.stops, "stop")].joined(separator: " · ")).help("Thread steps (a new one at each thread change or stop), trims and stops")
            Text(preferences.unit.size(summary.width, summary.height))
            Text("est. \(ProductionSummary.duration(summary.sewingMinutes(speed: speed)))")
                .help("Estimated sewing time at \(speed) stitches per minute (set on the production worksheet), plus time for trims, thread changes and stops")
        }
        .lineLimit(1).foregroundStyle(Theme.inkSecondary)
        .fixedSize()   // the numbers keep their room; the status message beside them shortens instead
    }
    /// "1 stop", "3 stops".
    static func count(_ n: Int, _ noun: String) -> String { "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")" }
}

/// Properties for the selection, laid out compactly in labeled sections (FILL / SATIN / RUNNING, UNDERLAY, FINISH,
/// START & END, OBJECT) with a small close-up beside the name. Explanations show as tooltips.
extension InspectorPanel {
    @ViewBuilder func proProperties(_ object: RunObject) -> some View {
        if state.selection.count > 1 && !selectionIsOneLettering { selectionSummary }
        proHeader(object)
        if object.stitchEdits != nil { stitchEditNotice(object) }
        if let lettering = object.lettering { letteringEditor(lettering) }
        if let monogram = object.monogram { monogramSummary(monogram) }
        switch object.kind {
        case .fill: proFill(object)
        case .satin: proSatin(object)
        case .run: proRunning(object)
        case .vector: proOutline(object)
        case .raw: EmptyView()
        }
        // Stipple, motif and cross stitch fills sew without underlay, so they have no Underlay section.
        if object.kind == .satin || (object.kind == .fill && ![.stipple, .motif, .crossStitch].contains(object.settings.fillStyle ?? .tatami)) { proUnderlay(object) }
        if object.kind != .vector { proFinish(object) }
        if object.kind == .run || object.kind == .satin || object.kind == .fill { proStartEnd(object) }
        proSection("Object") {
            HStack(spacing: 6) {
                Button(object.locked ? "Unlock" : "Lock") { AppDelegate.shared.perform(.lockObject) }.help(preferences.hint(.lockObject))
                Button(object.visible ? "Hide" : "Show") { AppDelegate.shared.perform(.hideObject) }.help(preferences.hint(.hideObject))
                Button("Rename…") { AppDelegate.shared.perform(.renameObject) }.help(preferences.hint(.renameObject))
            }
            .buttonStyle(ThemedButtonStyle())
        }
    }

    /// A small close-up of the stitches beside the object's name, stitch type, thread and stitch count.
    private func proHeader(_ object: RunObject) -> some View {
        // Lettering counts all its letters' stitches.
        let parts = object.lettering.map { state.design.letteringObjects($0.id).map(\.id) } ?? [object.id]
        let counts = parts.compactMap { state.stitchCounts[$0] }
        let count = counts.isEmpty ? "" : " · \(counts.reduce(0, +).formatted()) st"
        let detail = object.kind == .raw ? object.kind.title : "\(self.detail(object)) · \(object.color.name)"
        return HStack(spacing: 10) {
            if object.kind == .run || object.kind == .satin || object.kind == .fill {
                StitchPreview(kind: object.kind, color: Color(nsColor: object.color.nsColor), spacing: object.settings.rowGap, stitchLength: object.stitchLength, angle: object.settings.angle,
                              fillStyle: object.settings.fillStyle ?? .tatami, waveHeight: object.settings.waveHeight ?? DigitizingSettings.defaultWaveHeight, waveLength: object.settings.waveLength ?? DigitizingSettings.defaultWaveLength, settings: object.settings)
                    .frame(width: 40, height: 40)
                    .background(Theme.ground)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.controlBorder))
                    .help("Close-up of the stitches at these settings")
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                // One object (not lettering, which shows its text): click its name to rename it.
                if object.lettering == nil && state.selection.count == 1 {
                    ClickToRename(state: state, object: object, font: Theme.heading(15)).id(object.id)
                } else {
                    Text(heading(object)).font(Theme.heading(15)).lineLimit(1)
                }
                Text(detail + count).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
        }
        .help(object.kind == .raw ? "Existing stitches: move, rotate, mirror or recolor this thread block. Scaling changes density and stitch lengths; it does not regenerate stitches." : "")
    }


    private func proFill(_ object: RunObject) -> some View {
        let style = object.settings.fillStyle ?? .tatami, holes = object.holes?.count ?? 0
        return proSection("Fill") {
            proRow("Style", help: style.summary) {
                FillStyleMenu(state: state, style: style, color: object.color) { value in settings(.fill, "Fill Style") { $0.fillStyle = value == .tatami ? nil : value } }
                    .frame(width: 120)
            }
            // Only where the rows follow it; otherwise the Underlay section shows it as the underlay's angle.
            if StitchAngleLine.applies(to: object) {
                number("Angle °", value: object.settings.angle, id: "fillAngle", range: -180...180, help: "The direction the fill rows run.") { value in settings(.fill, "Fill Angle") { $0.angle = value } }
            }
            if style == .tatami || style == .satin { stitchAngles(object) }
            if style == .wave {
                let waveHelp = "How far each ripple rises and falls (mm, crest to trough), and the distance from one crest to the next. Tall, short waves pack the rows closer on their slopes."
                number("Wave height", value: object.settings.waveHeight ?? DigitizingSettings.defaultWaveHeight, range: DigitizingSettings.waveHeightRange, help: waveHelp) { value in settings(.fill, "Wave Height") { $0.waveHeight = value } }
                number("Wave length", value: object.settings.waveLength ?? DigitizingSettings.defaultWaveLength, range: DigitizingSettings.waveLengthRange, help: waveHelp) { value in settings(.fill, "Wave Length") { $0.waveLength = value } }
            }
            if style == .radial {
                proRow("Center", help: "Drag the Center dot on the canvas to move the point the stitches fan out from.") {
                    if object.settings.radialCenter != nil {
                        Button("Reset") { settings(.fill, "Reset Radial Center") { $0.radialCenter = nil } }.buttonStyle(ThemedButtonStyle())
                    } else {
                        Text("middle · drag on canvas").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            patternSettings(object)
            if ![.stipple, .motif, .crossStitch, .gradient].contains(style) {
                number("Row spacing", value: object.settings.spacing, id: "rowSpacing", range: 0.15...10, help: object.settings.rowSpacingHelp) { value in settings(.fill, "Row Spacing") { $0.spacing = value } }
            }
            // Not for cross stitch: its square size sets its stitches.
            if style.usesStitchLength {
                number("Stitch length", value: object.stitchLength, id: "stitchLength", range: 0.3...10, help: fillStitchLengthHelp(object)) { value in state.editSelected("Stitch Length") { $0.stitchLength = value } }
            }
            number("Expansion", value: object.settings.expansion, range: 0...2, help: "Grows the fill past its outline by this much, because thread pulls fabric inward as it sews.") { value in settings(.fill, "Compensation") { $0.expansion = value } }
            proRow("Holes", help: "Holes are areas inside the fill left unstitched. + traces a new one; − removes them all.") {
                Text(ProStats.count(holes, "hole")).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                Button { AppDelegate.shared.perform(.holeTool) } label: { Image(systemName: "plus") }.buttonStyle(ThemedButtonStyle()).accessibilityLabel("Add hole")
                Button { AppDelegate.shared.perform(.removeHoles) } label: { Image(systemName: "minus") }.buttonStyle(ThemedButtonStyle()).disabled(holes == 0).accessibilityLabel("Remove all holes")
            }
            cutOutToggle(object)
            border(object)
        }
    }

    private func proSatin(_ object: RunObject) -> some View {
        proSection("Satin") {
            satinWidth(object)
            number("Row spacing", value: object.settings.spacing, id: "rowSpacing", range: 0.15...5, help: "Gap between each pass of thread. Smaller gaps give fuller coverage and use more stitches.") { value in settings(.satin, "Row Spacing") { $0.spacing = value } }
            number("Compensation / side", value: object.settings.expansion, range: 0...2, help: "Thread pulls fabric inward as it sews. A little extra width on each side keeps the column the size you drew.") { value in settings(.satin, "Compensation") { $0.expansion = value } }
            number("% of width", value: object.settings.pullPercent ?? 0, range: DigitizingSettings.pullPercentRange, help: "Extra compensation for each stitch, as a share of its width, on top of the amount above, so wide parts of the satin get more. 3% is a starting value to tune after a test sew-out.") { value in settings(.satin, "Compensation % of Width") { $0.pullPercent = value } }
            number("Maximum stitch", value: object.settings.maximumSatin, range: DigitizingSettings.maximumSatinRange, help: "The longest satin stitch allowed. With Split wide satin on, longer stitches are split; otherwise wider columns are refused. Stitches over 12 mm get a warning: they can snag, and machine files split them.") { value in settings(.satin, "Satin Limit") { $0.maximumSatin = value } }
            satinOptions(object)
            border(object)
        }
    }

    private func proRunning(_ object: RunObject) -> some View {
        proSection("Running") {
            // Not for zigzag lines: Width and Spacing set their stitches.
            if (object.settings.runStyle ?? .running).usesStitchLength {
                number("Stitch length", value: object.stitchLength, id: "stitchLength", range: 0.3...10, help: "How far the needle moves per stitch. Shorter stitches follow curves more closely.") { value in state.editSelected("Stitch Length") { $0.stitchLength = value } }
            }
            runStyle(object)
            if (object.settings.runStyle ?? .running) == .running { runPasses(object) }
            toggle("Closed path", value: object.closed) { _ in AppDelegate.shared.perform(.closePath) }.help(preferences.hint(.closePath))
            satinLine(object)
            border(object)
        }
    }

    /// An outline that doesn't sew yet: buttons to give it stitches.
    private func proOutline(_ object: RunObject) -> some View {
        // A guide line only steers its fill or lettering: it can go back to being a sewn line, nothing else.
        proSection(object.guideFor == nil ? "Outline" : "Guide line") {
            if object.guideFor != nil {
                proRow("Sew as", help: "This dashed line guides a fill or lettering and doesn't sew. Reshape it with Edit Nodes and they follow. Running turns it back into a line that sews.") {
                    Button("Running") { AppDelegate.shared.perform(.convertRun) }.buttonStyle(ThemedButtonStyle())
                }
            } else {
                proRow("Sew as", help: "This outline does not sew until you assign stitches. Satin requires manually drawn edge pairs.") {
                    Button("Running") { AppDelegate.shared.perform(.convertRun) }.buttonStyle(ThemedButtonStyle())
                    Button("Fill") { AppDelegate.shared.perform(.convertFill) }.buttonStyle(ThemedButtonStyle())
                }
                satinLine(object)
                toggle("Closed path", value: object.closed) { _ in AppDelegate.shared.perform(.closePath) }.help(preferences.hint(.closePath))
                border(object)
            }
        }
    }

    /// "Satin border" with an Add button, for shapes that can have one.
    @ViewBuilder private func border(_ object: RunObject) -> some View {
        if SatinBorder.canBorder(object) {
            proRow("Satin border", help: "A satin column around this shape's outside edge, like the finished edge of a patch") {
                Button("Add…") { AppDelegate.shared.perform(.satinBorder) }.buttonStyle(ThemedButtonStyle())
            }
            proRow("Outlines & offsets", help: preferences.hint(.outlinesOffsets)) {
                Button("Add…") { AppDelegate.shared.perform(.outlinesOffsets) }.buttonStyle(ThemedButtonStyle())
            }
            proRow("Appliqué", help: "Sew a piece of fabric in this shape: placement line, tack-down and a satin edge, with stops to lay and trim the fabric") {
                Button("Make…") { AppDelegate.shared.perform(.applique) }.buttonStyle(ThemedButtonStyle())
            }
        }
    }

    private func proUnderlay(_ object: RunObject) -> some View {
        let underlay = object.settings.underlay
        return proSection("Underlay") {
            proRow("Type", help: "A quick first layer under the stitches. It holds the fabric still so the top stitches lie smooth." + (object.kind == .satin ? " Auto picks from the satin's average width: a center run under 2 mm, an edge run up to 4 mm, an edge run then a zigzag above that (from 2 mm on knit and towel). It updates as you reshape the satin." : "")) {
                Picker("Type", selection: Binding(get: { underlay }, set: { value in settings(object.kind, "Underlay") { $0.underlay = value } })) {
                    ForEach(object.kind == .fill ? [UnderlayStyle.none, .edge, .edgeAndSparse] : [.auto, .none, .center, .edge, .zigzag], id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
            if object.kind == .satin && underlay != .none && underlay != .auto {
                proRow("Second", help: "Sewn after the first underlay, back along the column. Common pairs: center run then zigzag, or edge run then zigzag for wide satins.") {
                    Picker("Second", selection: Binding(get: { object.settings.secondUnderlay ?? UnderlayStyle.none }, set: { value in settings(.satin, "Second Underlay") { $0.secondUnderlay = value == UnderlayStyle.none ? nil : value } })) {
                        ForEach([UnderlayStyle.none, .center, .edge, .zigzag].filter { $0 != underlay }, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
            }
            if StitchAngleLine.steersOnlyUnderlay(object) {
                number("Angle °", value: object.settings.angle, id: "fillAngle", range: -180...180, help: "The direction of the sparse underlay rows. This fill's own stitches don't follow an angle, so it only turns the underlay.") { value in settings(.fill, "Underlay Angle") { $0.angle = value } }
            }
            if object.settings.usesUnderlayInset {
                number("Inset", value: object.settings.inset, range: 0...3, help: "How far inside the edge the underlay runs.") { value in settings(object.kind, "Underlay Inset") { $0.inset = value } }
            }
            // Only underlay with rows to space (not an edge run alone).
            if object.settings.usesUnderlaySpacing(object.kind) {
                number("Spacing", value: object.settings.underlaySpacing, range: 0.5...5, help: "Gap between the underlay's rows.") { value in settings(object.kind, "Underlay Spacing") { $0.underlaySpacing = value } }
            }
        }
    }

    /// Tie in / tie off / trim / stop as checkboxes in two columns.
    private func proFinish(_ object: RunObject) -> some View {
        let help = (object.kind == .raw ? "" : "Ties are tiny locking stitches so the thread can't unravel. ") + "Trim cuts the thread before the next part; Stop pauses the machine. PES encodes travel moves after the first as trim/jumps, so your machine decides whether to cut."
        return proSection("Finish") {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 4) {
                if object.kind != .raw {
                    toggle("Tie in", value: object.tieIn) { _ in AppDelegate.shared.perform(.tieIn) }
                    toggle("Tie off", value: object.tieOut) { _ in AppDelegate.shared.perform(.tieOut) }
                }
                toggle("Stop after", value: object.stopAfter) { _ in AppDelegate.shared.perform(.stopAfter) }
            }
            .help(help)
            trimMenu(object).help(help)
        }
    }

    /// Exact start and end points (in the chosen unit), or "automatic", with buttons to set, clear or auto-place them.
    private func proStartEnd(_ object: RunObject) -> some View {
        proSection("Start & end") {
            if let entry = object.entry { pointFields("Start", entry, object: object.id) { $0.entry = $1 } } else { automatic("Start") }
            if let exit = object.exit { pointFields("End", exit, object: object.id) { $0.exit = $1 } } else { automatic("End") }
            HStack(spacing: 6) {
                Button("Set…") { AppDelegate.shared.perform(.entryExitTool) }.help(startEndHelp(object))
                if object.entry != nil || object.exit != nil { Button("Clear") { AppDelegate.shared.perform(.clearStartEnd) }.help("Clear this object's start and end points") }
                Button("Auto for all") { AppDelegate.shared.perform(.autoStartPoints) }.help("Start every object where the previous one ends, to shorten travel")
            }
            .buttonStyle(ThemedButtonStyle())
        }
    }

    private func automatic(_ title: String) -> some View {
        proRow(title, help: "Chosen automatically. Use Set… to place it yourself.") {
            Text("automatic").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
        }
    }

    /// A small uppercase heading over a group of settings, with a divider above it.
    private func proSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Theme.divider.frame(height: 1)
            Text(title.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(Theme.inkSecondary)
                .padding(.top, 2)
            content()
        }
    }

    /// A label on the left and a control (or a few) on the right, with the explanation as a tooltip.
    private func proRow<Control: View>(_ title: String, help: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: 6) {
            Text(title).font(Theme.body(11)).lineLimit(1)
            Spacer(minLength: 8)
            control()
        }
        .help(help)
    }
}
