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

    var body: some View {
        PictureListMenu(label: "Fill style", options: EmbroideryCore.FillStyle.allCases, current: style, name: \.title, tagline: \.tagline, help: \.summary, compact: compact,
                        tryOut: { option in if let option { Self.preview(option, state) } else { state.previewSettings(nil) } },
                        picture: { FillStyleThumbnail(style: $0, color: color) }) { option in
            choose(option)
            state.keepSettingsPreview(Self.choice(option))
        }
        .onAppear { FillStyleSamples.shared.load() }
    }
    /// The name of trying `option` out (see SettingsPreview).
    static func choice(_ option: EmbroideryCore.FillStyle) -> String { "style:\(option.rawValue)" }
    /// Tries `option` out on the selected fills.
    static func preview(_ option: EmbroideryCore.FillStyle, _ state: EditorState) {
        state.previewSettings(choice(option), applies: { $0.kind == .fill }) { $0.fillStyle = option == .tatami ? nil : option }
    }
}

/// The Next shape bar's Fill menu: the fill the next closed shape gets, or None (first) for just an outline, in the
/// thread it gets. There's no shape yet to show a choice on, so pointing at one only highlights it.
struct NewShapeFillMenu: View {
    let current: EmbroideryCore.FillStyle?
    let color: ThreadColor
    var compact = false
    let choose: (EmbroideryCore.FillStyle?) -> Void

    var body: some View {
        // Optional.some wraps each style, so the list can hold None (nil) too.
        let options: [EmbroideryCore.FillStyle?] = [nil] + EmbroideryCore.FillStyle.forNewShapes.map(Optional.some)
        PictureListMenu(label: "Fill", options: options, current: current, name: { $0?.title ?? "None" },
                        tagline: { $0?.tagline ?? "No fill: just the outline." }, help: { $0?.summary ?? "The shape gets no fill, just its outline." }, compact: compact,
                        picture: { option in
                            if let option { FillStyleThumbnail(style: option, color: color) } else { NoStitchPicture() }
                        }, choose: choose)
        .onAppear { FillStyleSamples.shared.load() }
    }
}
