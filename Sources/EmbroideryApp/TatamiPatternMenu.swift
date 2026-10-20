// The Pattern menu of a tatami fill in Properties: a button with a small picture of the current pattern that opens a
// grid of every pattern (TatamiPattern.swift). Pointing at one shows the selected tatami fills sewn with it on the
// canvas; nothing in the design changes until a pattern is clicked (PictureMenu.swift).
import SwiftUI
import EmbroideryCore

/// A swatch of tatami rows in `pattern`, in `color`: each stitch a short strand with a small gap at each needle hole,
/// so the lines of holes show the texture the pattern makes. Drawn level and enlarged, not at the fill's real size.
struct TatamiPatternThumbnail: View {
    let pattern: TatamiPattern
    let color: ThreadColor
    var body: some View {
        // Canvas draws with code, like the main canvas does, instead of laying out views.
        Canvas { context, size in
            let rowGap = 1.7, stitch = 11.0, hole = 1.1
            var path = Path()
            for row in 0...Int(size.height / rowGap) {
                let y = (Double(row) + 0.5) * rowGap
                var x = (pattern.offset(row: row) - 1) * stitch   // the hole just left of the picture
                while x < size.width {
                    path.move(to: CGPoint(x: x + hole / 2, y: y)); path.addLine(to: CGPoint(x: x + stitch - hole / 2, y: y))
                    x += stitch
                }
            }
            let thread = color.nsColor, shade = thread.blended(withFraction: 0.15, of: .black) ?? thread
            context.stroke(path, with: .color(Color(nsColor: shade)), style: StrokeStyle(lineWidth: 1.3, lineCap: .butt))
        }
        .background(Color(nsColor: Theme.Canvas.fabric))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

/// The Pattern control of a tatami fill: a button with the current pattern's picture and name, which opens the grid
/// of patterns. `compact` is the Pro size. `choose` applies a pattern to the selection (one Undo step).
struct TatamiPatternMenu: View {
    @ObservedObject var state: EditorState
    let pattern: TatamiPattern
    let color: ThreadColor
    var compact = false
    let choose: (TatamiPattern) -> Void
    @State private var open = false
    @State private var pointedAt: TatamiPattern?

    var body: some View {
        Button { open.toggle() } label: {
            PictureMenuLabel(title: pattern.name, compact: compact) { TatamiPatternThumbnail(pattern: pattern, color: color) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pattern: \(pattern.name)")
        .popover(isPresented: $open, arrowEdge: .bottom) { grid }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 6), count: 3), spacing: 6) {
                    ForEach(TatamiPattern.library) { option in tile(option) }
                }
                .padding(2)
            }
            .frame(height: 430)
            pictureMenuNote(pointedAt: pointedAt == pattern ? nil : pointedAt?.name, current: pattern.name, kind: "pattern")
        }
        .padding(8).frame(width: 320)
        // Moving off the grid, or closing it without choosing, puts the fills' own stitches back. (Leaving one tile
        // for the next doesn't, so the canvas doesn't flash back in between.)
        .onHover { inside in if !inside { pointedAt = nil; state.previewSettings(nil) } }
        .onDisappear { pointedAt = nil; state.previewSettings(nil) }
    }

    private func tile(_ option: TatamiPattern) -> some View {
        Button {
            choose(option)
            state.keepSettingsPreview(Self.choice(option))
            open = false
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                TatamiPatternThumbnail(pattern: option, color: color).frame(height: 52)
                    .overlay(alignment: .topTrailing) {
                        if option == pattern {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.accent).background(Circle().fill(Theme.card)).padding(3)
                        }
                    }
                Text(option.name).font(Theme.body(11, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 7).fill(pointedAt == option ? Theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.tagline)
        .accessibilityLabel(option.name)
        .accessibilityValue(option == pattern ? "In use" : "")
        .onHover { inside in if inside { pointedAt = option; Self.preview(option, state) } }
    }

    /// The name of trying `option` out (see SettingsPreview).
    static func choice(_ option: TatamiPattern) -> String { "pattern:\(option.id)" }
    /// Tries `option` out on the selected tatami fills.
    static func preview(_ option: TatamiPattern, _ state: EditorState) {
        state.previewSettings(choice(option), applies: { $0.kind == .fill && ($0.settings.fillStyle ?? .tatami) == .tatami }) {
            $0.tatamiPattern = option == .smooth ? nil : option.id
        }
    }
}
