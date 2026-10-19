// The design's thread palette (ThreadPalette.swift) as a row of swatches: in a strip under the canvas, or docked at
// the top of the Threads panel (the button beside the chart menu, or View › Palette Under Canvas, moves it).
// Clicking a thread makes it current and recolors the selection. + keeps the current thread in the palette, − takes
// it out once nothing sews in it, and Remove unused clears every thread no object uses.
import SwiftUI
import EmbroideryCore

struct PaletteRow: View {
    enum Placement { case underCanvas, docked }
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    let placement: Placement

    var body: some View {
        let threads = state.design.paletteThreads
        // How many objects sew in each thread, for the hover text and to keep threads in use from being removed.
        let uses = Dictionary(state.design.objects.map { ($0.color, 1) }, uniquingKeysWith: +)
        let current = state.currentColor
        let canRemove = threads.contains(current) && uses[current] == nil
        let unused = threads.contains { uses[$0] == nil }
        switch placement {
        case .underCanvas:
            HStack(spacing: 8) {
                caption
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) { ForEach(threads, id: \.self) { slot($0, uses: uses[$0] ?? 0, size: 16) } }.padding(.vertical, 4).padding(.horizontal, 3)
                }
                buttons(threads: threads, canRemove: canRemove, unused: unused)
                Button { AppDelegate.shared.perform(.paletteUnderCanvas) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18) }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
                    .help("Dock the palette at the top of the Threads panel (\(preferences.label(.paletteUnderCanvas)))")
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(Theme.card).overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
        case .docked:
            // Compact, so the library and (in Pro) the sewing order list keep their room in the panel.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { caption; Spacer(minLength: 4); buttons(threads: threads, canRemove: canRemove, unused: unused) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 22), spacing: 6)], alignment: .leading, spacing: 7) {
                    ForEach(threads, id: \.self) { slot($0, uses: uses[$0] ?? 0, size: 16) }
                }.padding(3)
            }
        }
    }

    private var caption: some View {
        Text("PALETTE").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(Theme.inkSecondary)
    }

    /// One palette thread: its swatch, ringed when it's the current thread; name, number and use on hover.
    private func slot(_ color: ThreadColor, uses: Int, size: CGFloat) -> some View {
        Button { state.chooseThread(color) } label: {
            Circle().fill(Color(nsColor: color.nsColor)).frame(width: size, height: size).overlay(Circle().strokeBorder(Theme.controlBorder))
                .overlay(Circle().strokeBorder(Theme.ink.opacity(state.currentColor == color ? 0.85 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help("\(color.chartLabel.map { "\(color.name) · \($0)" } ?? color.name) · \(uses == 0 ? "not used yet" : "sewn in \(uses) object\(uses == 1 ? "" : "s")"). Click to make it the current thread and recolor the selection.")
        .contextMenu {
            Button("Remove from Palette") { state.removeFromPalette(color) }.disabled(uses > 0)
            Button("Remove Unused Threads") { state.removeUnusedThreads() }
        }
    }

    /// + (keep the current thread), − (take it out) and Remove unused.
    private func buttons(threads: [ThreadColor], canRemove: Bool, unused: Bool) -> some View {
        HStack(spacing: 4) {
            Button { state.addCurrentThreadToPalette() } label: { Image(systemName: "plus").frame(width: 20, height: 18) }
                .disabled(threads.contains(state.currentColor))
                .help(threads.contains(state.currentColor) ? "The current thread is already in the palette." : "Add the current thread (\(state.currentColor.name)) to the palette")
            Button { state.removeFromPalette(state.currentColor) } label: { Image(systemName: "minus").frame(width: 20, height: 18) }
                .disabled(!canRemove)
                .help(canRemove ? "Take the current thread (\(state.currentColor.name)) out of the palette"
                      : threads.contains(state.currentColor) ? "Objects still sew in \(state.currentColor.name), so it stays in the palette." : "The current thread isn't in the palette.")
            Button("Remove unused") { state.removeUnusedThreads() }.disabled(!unused)
                .help("Take every thread no object sews in out of the palette")
        }
        .buttonStyle(.borderless).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
    }
}

/// The strip under the canvas: the palette row while it's popped out there, nothing while it's docked.
struct PaletteStrip: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        if preferences.paletteUnderCanvas { PaletteRow(state: state, placement: .underCanvas) } else { Color.clear.frame(height: 0) }
    }
}
