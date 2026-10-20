// The Fill style menu in Properties: a button with a small picture of the fill's stitches that opens a list of every
// fill style, each with a picture, its name and a line about it. Pointing at a style shows the selected fills stitched
// that way on the canvas; nothing in the design changes until a style is clicked (PictureMenu.swift). (EmbroideryCore.FillStyle is spelled
// out because SwiftUI has a FillStyle of its own.)
import SwiftUI
import EmbroideryCore

/// Each fill style's stitches on one sample shape, for the menu's pictures. They're worked out once, in the
/// background, the first time a Fill style menu shows, and kept until the app quits.
@MainActor final class FillStyleSamples: ObservableObject {
    static let shared = FillStyleSamples()
    /// Each style's stitches as runs of needle points (a new run starts at each jump).
    @Published private(set) var runs: [EmbroideryCore.FillStyle: [[Point]]] = [:]
    private var loading = false

    func load() {
        guard !loading else { return }
        loading = true
        Task {
            let all = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: EmbroideryCore.FillStyle.allCases.map { ($0, Self.stitches($0)) })
            }.value
            runs = all
        }
    }

    /// The stitches of `style` on a rounded pillow 56 × 38 mm, centered on 0,0, with no underlay.
    nonisolated static func stitches(_ style: EmbroideryCore.FillStyle) -> [[Point]] {
        // A superellipse: like an ellipse, but fuller, so it reads as a rounded rectangle.
        let outline = (0..<72).map { i -> Point in
            let turn = Double(i) / 72 * 2 * .pi, x = cos(turn), y = sin(turn)
            return Point(28 * copysign(pow(abs(x), 0.6), x), 19 * copysign(pow(abs(y), 0.6), y))
        }
        var object = RunObject(name: "Sample", nodes: outline.map { PathNode($0) })
        object.closed = true
        var settings = DigitizingSettings(kind: .fill)
        settings.angle = 35; settings.underlay = UnderlayStyle.none
        settings.fillStyle = style == .tatami ? nil : style
        // Guided rows follow a guide line: a gentle S across the shape.
        if style == .guided { settings.guideLine = (0...30).map { i in let x = -30 + Double(i) * 2; return Point(x, 8 * sin(x / 9)) } }
        object.digitizing = settings
        var design = Design(); design.objects = [object]
        guard let plan = try? RunningEngine.compile(design) else { return [] }
        var runs: [[Point]] = []
        for command in plan.commands {
            if command.op == .jump { runs.append([command.point]) }
            else if command.op == .stitch { if runs.isEmpty { runs.append([]) }; runs[runs.count - 1].append(command.point) }
        }
        return runs
    }
}

extension EmbroideryCore.FillStyle {
    /// A few words about the style, for its row in the Fill style menu (`summary` says more).
    var tagline: String {
        switch self {
        case .tatami: return "Straight rows: the classic, flattest fill."
        case .contour: return "Rings that follow the outline inward."
        case .radial: return "Stitches fan out from a center point."
        case .wave: return "Rows that ripple in a gentle wave."
        case .stipple: return "One wandering line: the quilting look."
        case .motif: return "A small pattern repeated across the shape."
        case .crossStitch: return "Little X's on a square grid."
        case .gradient: return "Rows that open up, from solid to sheer."
        case .guided: return "Rows that bend along a guide line."
        case .satin: return "Shiny stitches from edge to edge."
        }
    }
}

/// A picture of `style`'s stitches on the sample shape, in `color`, on a patch of cloth. Blank cloth until the
/// samples are ready.
struct FillStyleThumbnail: View {
    @ObservedObject private var samples = FillStyleSamples.shared
    let style: EmbroideryCore.FillStyle
    let color: ThreadColor
    var body: some View {
        // Canvas draws with code, like the main canvas does, instead of laying out views.
        Canvas { context, size in
            guard let runs = samples.runs[style] else { return }
            // Fill the picture with the middle of the shape, 58 × 40 mm, cropping what doesn't fit.
            let scale = max(size.width / 58, size.height / 40)
            func place(_ point: Point) -> CGPoint { CGPoint(x: size.width / 2 + point.x * scale, y: size.height / 2 + point.y * scale) }
            var path = Path()
            for run in runs where !run.isEmpty {
                path.move(to: place(run[0]))
                for point in run.dropFirst() { path.addLine(to: place(point)) }
            }
            // A darker strand with a light line along its middle, so each stitch reads as thread.
            let thread = color.nsColor
            let shade = thread.blended(withFraction: 0.3, of: .black) ?? thread, shine = thread.blended(withFraction: 0.5, of: .white) ?? thread
            context.stroke(path, with: .color(Color(nsColor: shade)), style: StrokeStyle(lineWidth: max(0.5, 0.42 * scale), lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color(nsColor: shine).opacity(0.8)), style: StrokeStyle(lineWidth: max(0.25, 0.13 * scale), lineCap: .round, lineJoin: .round))
        }
        .background(Color(nsColor: Theme.Canvas.fabric))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

/// The Fill style control: a button with the current style's picture and name, which opens the list of styles.
/// `compact` is the Pro size. `choose` applies a style to the selection (one Undo step).
struct FillStyleMenu: View {
    @ObservedObject var state: EditorState
    let style: EmbroideryCore.FillStyle
    let color: ThreadColor
    var compact = false
    let choose: (EmbroideryCore.FillStyle) -> Void
    @State private var open = false
    @State private var pointedAt: EmbroideryCore.FillStyle?

    var body: some View {
        Button { open.toggle() } label: {
            PictureMenuLabel(title: style.title, compact: compact) { FillStyleThumbnail(style: style, color: color) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fill style: \(style.title)")
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
        .onAppear { FillStyleSamples.shared.load() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(EmbroideryCore.FillStyle.allCases, id: \.self) { option in row(option) }
            pictureMenuNote(pointedAt: pointedAt == style ? nil : pointedAt?.title, current: style.title, kind: "style").padding(.top, 4)
        }
        .padding(6).frame(width: 290)
        // Moving off the list, or closing it without choosing, puts the fills' own stitches back. (Leaving one row
        // for the next doesn't, so the canvas doesn't flash back in between.)
        .onHover { inside in if !inside { pointedAt = nil; state.previewSettings(nil) } }
        .onDisappear { pointedAt = nil; state.previewSettings(nil) }
    }

    private func row(_ option: EmbroideryCore.FillStyle) -> some View {
        Button {
            choose(option)
            state.keepSettingsPreview(Self.choice(option))
            open = false
        } label: {
            HStack(spacing: 10) {
                FillStyleThumbnail(style: option, color: color).frame(width: 66, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).font(Theme.body(12, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(option.tagline).font(Theme.body(10.5)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent).opacity(option == style ? 1 : 0)
            }
            .padding(4).padding(.trailing, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(pointedAt == option ? Theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.summary)
        .accessibilityLabel(option.title)
        .accessibilityValue(option == style ? "In use" : "")
        .onHover { inside in
            if inside { pointedAt = option; Self.preview(option, state) }
        }
    }
    /// The name of trying `option` out (see SettingsPreview).
    static func choice(_ option: EmbroideryCore.FillStyle) -> String { "style:\(option.rawValue)" }
    /// Tries `option` out on the selected fills.
    static func preview(_ option: EmbroideryCore.FillStyle, _ state: EditorState) {
        state.previewSettings(choice(option), applies: { $0.kind == .fill }) { $0.fillStyle = option == .tatami ? nil : option }
    }
}
