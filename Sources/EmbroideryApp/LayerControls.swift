// Locking, hiding and renaming objects right in the sewing order, as with layers in a drawing app: each row has a
// lock (solid when locked, faint while the pointer is over the row) and a right-click menu with Rename, Show Only
// Selected, Zoom to Selected, Lock, Hide, Trim After, Stop After, Group, and the edit commands. Used by the sewing
// order table.
import SwiftUI
import AppKit
import EmbroideryCore

extension EditorState {
    /// Locks or unlocks the objects with these ids, as one Undo step.
    func setLocked(_ ids: Set<UUID>, _ locked: Bool) {
        edit(locked ? "Lock" : "Unlock") { design in
            for index in design.objects.indices where ids.contains(design.objects[index].id) { design.objects[index].locked = locked }
        }
    }
    /// Shows or hides the objects with these ids (hidden objects still sew), as one Undo step.
    func setVisible(_ ids: Set<UUID>, _ visible: Bool) {
        edit(visible ? "Show" : "Hide") { design in
            for index in design.objects.indices where ids.contains(design.objects[index].id) { design.objects[index].visible = visible }
        }
    }
    /// True when every object with these ids is locked.
    func allLocked(_ ids: Set<UUID>) -> Bool {
        let objects = design.objects.filter { ids.contains($0.id) }
        return !objects.isEmpty && objects.allSatisfy(\.locked)
    }
}

/// A sewing order row's lock: solid when the row's objects are locked, faint while the pointer is over the row
/// (`showing`), otherwise invisible (it keeps its place). Clicking locks or unlocks them all.
struct RowLock: View {
    @ObservedObject var state: EditorState
    let ids: Set<UUID>
    let showing: Bool
    var size: CGFloat = 10
    var body: some View {
        let locked = state.allLocked(ids)
        Button { state.setLocked(ids, !locked) } label: {
            Image(systemName: locked ? "lock.fill" : "lock.open").font(.system(size: size))
                .foregroundStyle(locked ? Theme.ink : Theme.inkSecondary)
                .opacity(locked ? 1 : showing ? 0.6 : 0)
                .frame(width: 16, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(locked ? "Locked. Click to unlock." : "Click to lock, so it can't be moved or changed by accident.")
        .accessibilityLabel(locked ? "Unlock" : "Lock")
    }
}

/// The right-click menu of a sewing order row. `rename` is nil where the row can't be renamed (a group, lettering).
/// Like Finder, it acts on the whole selection when the row is part of it; otherwise it selects the row first (for
/// the commands that work on the selection) and acts on that.
@MainActor @ViewBuilder func layerMenu(state: EditorState, ids: Set<UUID>, rename: (() -> Void)?) -> some View {
    let targets = ids.isSubset(of: state.selection) ? state.selection : ids
    let objects = state.design.objects.filter { targets.contains($0.id) }
    let locked = state.allLocked(targets), hidden = !objects.isEmpty && objects.allSatisfy { !$0.visible }
    let trimmed = !objects.isEmpty && objects.allSatisfy(\.trimAfter), stopped = !objects.isEmpty && objects.allSatisfy(\.stopAfter)
    // Groups the targets belong to, apart from lettering (which stays one object; see ungroupSelection).
    let groups = Set(objects.filter { $0.lettering == nil }.compactMap(\.groupID))
    let canPaste = NSPasteboard.general.data(forType: .init(ObjectClipboard.pasteboardType)) != nil
    // Selects the row's objects unless the row is already part of the selection. (Closures, not functions: a
    // menu's builder allows only `let`s.)
    let select = { if state.selection != targets { state.selection = targets; state.selectedNode = nil } }
    // Runs a menu command on the targets.
    let run = { (command: CommandID) in select(); AppDelegate.shared.perform(command) }

    if let rename {
        // On the next pass of the main loop, once the menu has closed, so the name box gets the keyboard.
        Button("Rename") { RunLoop.main.perform { MainActor.assumeIsolated { rename() } } }
        Divider()
    }
    // Hide Unselected is a view switch: once on, the item turns it off again.
    if state.hideOthers { Button("Show All") { AppDelegate.shared.perform(.hideOthers) } }
    else { Button("Show Only Selected") { run(.hideOthers) } }
    Button("Zoom to Selected") { run(.zoomSelected) }
    Divider()
    Button(locked ? "Unlock" : "Lock") { state.setLocked(targets, !locked) }
    Button(hidden ? "Show" : "Hide") { state.setVisible(targets, hidden) }
    Divider()
    // Checked when every target has it; choosing it sets them all the same way.
    Toggle("Trim After", isOn: Binding(get: { trimmed }, set: { on in select(); state.editSelected("Trim After") { $0.trimAfter = on } }))
    Toggle("Stop After", isOn: Binding(get: { stopped }, set: { on in
        select(); state.editSelected("Stop After") { $0.stopAfter = on; $0.stopForJump = nil }   // now a stop set by hand
    }))
    Divider()
    if targets.count >= 2 && !(groups.count == 1 && objects.allSatisfy { $0.groupID == groups.first }) { Button("Group") { run(.group) } }
    if !groups.isEmpty { Button("Ungroup") { run(.ungroup) } }
    Divider()
    Button("Cut") { run(.cutObjects) }
    Button("Copy") { run(.copyObjects) }
    Button("Paste") { AppDelegate.shared.perform(.pasteObjects) }.disabled(!canPaste)
    Button("Duplicate") { run(.duplicate) }
    Button("Delete") { run(.delete) }
}
