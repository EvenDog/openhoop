// Renaming an object where its name is shown: double-click it in the sewing order, or click it at the top of
// Properties, and type. Return or clicking elsewhere keeps the new name, Esc keeps the old one.
import AppKit
import SwiftUI
import EmbroideryCore

/// The text box that renames `object`, shown while `editing` is on. It opens with the whole name selected, so typing
/// replaces it. Each rename is one Undo step; an empty name keeps the old one.
struct RenameField: View {
    @ObservedObject var state: EditorState
    let object: RunObject
    let font: Font
    @Binding var editing: Bool
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.roundedBorder).font(font)
            .focused($focused)
            .onSubmit { finish(keep: true) }
            .onExitCommand { finish(keep: false) }   // Esc
            // Clicking anywhere else takes the keyboard away, which keeps the new name.
            .onChange(of: focused) { _, hasKeyboard in if !hasKeyboard { finish(keep: true) } }
            .onAppear {
                draft = object.name
                // As in the lettering editor: take the keyboard, then select the whole name (SwiftUI can't on macOS 14).
                DispatchQueue.main.async {
                    focused = true
                    DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                }
            }
            .accessibilityLabel("Name of \(object.name)")
    }
    private func finish(keep: Bool) {
        guard editing else { return }   // already finished (Return, then the keyboard leaving, would finish twice)
        editing = false
        if keep { state.rename(object.id, to: draft) }
        state.focusCanvas()
    }
}

/// The object's name at the top of Properties: click it (or its pencil) to rename it.
struct ClickToRename: View {
    @ObservedObject var state: EditorState
    let object: RunObject
    let font: Font
    var lineLimit = 1
    @State private var editing = false
    var body: some View {
        if editing {
            RenameField(state: state, object: object, font: font, editing: $editing)
        } else {
            Button { editing = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(object.name).font(font).lineLimit(lineLimit)
                    Image(systemName: "pencil").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to rename")
            .accessibilityLabel("Rename \(object.name)")
        }
    }
}
