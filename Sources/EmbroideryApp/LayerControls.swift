// Locking, hiding and renaming objects right in the sewing order, as with layers in a drawing app: each row has a
// lock (solid when locked, faint while the pointer is over the row) and a right-click menu with Rename, Lock and
// Hide. Used by the Guided and Pro sewing order alike.
import SwiftUI
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
@MainActor @ViewBuilder func layerMenu(state: EditorState, ids: Set<UUID>, rename: (() -> Void)?) -> some View {
    let objects = state.design.objects.filter { ids.contains($0.id) }
    let locked = state.allLocked(ids), hidden = !objects.isEmpty && objects.allSatisfy { !$0.visible }
    if let rename {
        // On the next pass of the main loop, once the menu has closed, so the name box gets the keyboard.
        Button("Rename") { RunLoop.main.perform { MainActor.assumeIsolated { rename() } } }
    }
    Button(locked ? "Unlock" : "Lock") { state.setLocked(ids, !locked) }
    Button(hidden ? "Show" : "Hide") { state.setVisible(ids, hidden) }
}
