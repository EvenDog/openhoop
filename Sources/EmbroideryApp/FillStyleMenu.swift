// The Fill style menu in Properties: a button with a small picture of the fill's stitches that opens a list of every
// fill style, each with a picture, its name and a line about it. Pointing at a style shows the selected fills stitched
// that way on the canvas; nothing in the design changes until a style is clicked. (EmbroideryCore.FillStyle is spelled
// out because SwiftUI has a FillStyle of its own.)
import SwiftUI
import EmbroideryCore

/// While pointing at a style in the Fill style menu: the selected fills' stitches in that style, which the canvas
/// draws in place of theirs. `kept` once the style has been chosen, until the design's own stitches catch up.
struct FillStylePreview {
    let style: EmbroideryCore.FillStyle
    let objects: Set<UUID>
    let plan: StitchPlan
    var kept = false
}

extension EditorState {
    /// Shows the selected fills stitched in `style` on the canvas (nil stops). Their stitches are worked out in the
    /// background on their own, apart from the rest of the design, so a big design doesn't slow the preview down.
    func previewFillStyle(_ style: EmbroideryCore.FillStyle?) {
        fillStylePreviewTask?.cancel(); fillStylePreviewTask = nil
        let fills = design.objects.filter { selection.contains($0.id) && $0.kind == .fill && !$0.locked && ($0.settings.fillStyle ?? .tatami) != style }
        guard let style, !fills.isEmpty else {
            if fillStylePreview?.kept != true { fillStylePreview = nil }
            return
        }
        var sample = design
        sample.objects = fills.map { object in
            var object = object, settings = object.settings
            settings.fillStyle = style == .tatami ? nil : style
            object.digitizing = settings
            object.stitchEdits = nil   // as on the real change: a new style means fresh stitches
            return object
        }
        let work = Task.detached(priority: .userInitiated) { try RunningEngine.compile(sample) }
        fillStylePreviewTask = work
        Task { [weak self] in
            // A style that can't be sewn (Guided with no guide line) just shows no preview.
            guard let plan = try? await work.value, let self, self.fillStylePreviewTask == work else { return }
            self.fillStylePreview = FillStylePreview(style: style, objects: Set(fills.map(\.id)), plan: plan)
        }
    }
    /// After `style` is chosen from the menu: keeps its preview on the canvas until the design's fresh stitches are
    /// ready (EditorState.plan clears it), so the old style doesn't flash back in between.
    func keepFillStylePreview(_ style: EmbroideryCore.FillStyle) {
        fillStylePreviewTask?.cancel(); fillStylePreviewTask = nil
        if fillStylePreview?.style == style { fillStylePreview?.kept = true } else { fillStylePreview = nil }
    }
}

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
            HStack(spacing: compact ? 6 : 8) {
                FillStyleThumbnail(style: style, color: color).frame(width: compact ? 26 : 46, height: compact ? 17 : 30)
                Text(style.title).font(Theme.body(compact ? 11 : 12, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: compact ? 8 : 9, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            .padding(compact ? 2 : 4).padding(.trailing, compact ? 4 : 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fill style: \(style.title)")
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
        .onAppear { FillStyleSamples.shared.load() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(EmbroideryCore.FillStyle.allCases, id: \.self) { option in row(option) }
            Text(note).font(Theme.body(11)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.ground)).padding(.top, 4)
        }
        .padding(6).frame(width: 290)
        // Moving off the list, or closing it without choosing, puts the fills' own stitches back. (Leaving one row
        // for the next doesn't, so the canvas doesn't flash back in between.)
        .onHover { inside in if !inside { pointedAt = nil; state.previewFillStyle(nil) } }
        .onDisappear { pointedAt = nil; state.previewFillStyle(nil) }
    }

    private var note: String {
        guard let pointedAt, pointedAt != style else { return "Point at a style to see it stitched on your shape." }
        return "Your shape shows \(pointedAt.title). Click to keep it; move away to go back to \(style.title)."
    }

    private func row(_ option: EmbroideryCore.FillStyle) -> some View {
        Button {
            choose(option)
            state.keepFillStylePreview(option)
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
        .onHover { inside in if inside { pointedAt = option; state.previewFillStyle(option) } }
    }
}
