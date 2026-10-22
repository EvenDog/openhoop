// Picture menus for line stitches: a selected line's Line style in Properties, and the Next shape bar's Stitch and
// Outline. Each choice shows a picture of its stitches on a short sample curve, worked out by the stitch engine, so
// the picture is what the line will sew. Pointing at a Line style shows the selected lines sewn that way on the
// canvas (PictureMenu.swift); the Next shape menus have no shape to show it on yet.
import SwiftUI
import EmbroideryCore

/// A line stitch a menu shows: a choice for the next open shape or outline, or a line's Line style.
enum LineStitch: Hashable, Sendable {
    case newLine(OpenShapeStitch)
    case style(RunStyle)
    static let all = OpenShapeStitch.allCases.map(newLine) + RunStyle.allCases.map(style)
}

/// Each line stitch's stitches on one sample curve, for the menus' pictures. They're worked out once, in the
/// background, the first time a line stitch menu shows, and kept until the app quits.
@MainActor final class LineStitchSamples: ObservableObject {
    static let shared = LineStitchSamples()
    /// Each stitch's needle points, as runs (a new run starts at each jump).
    @Published private(set) var runs: [LineStitch: [[Point]]] = [:]
    private var loading = false

    func load() {
        guard !loading else { return }
        loading = true
        Task {
            runs = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: LineStitch.all.map { ($0, Self.stitches($0)) })
            }.value
        }
    }

    /// The stitches of `stitch` along a gentle S curve 28 mm long, centered on 0,0, made the way the real line is:
    /// a new shape's by `ShapeStitching.openShape`, a Line style on a plain running line.
    nonisolated static func stitches(_ stitch: LineStitch) -> [[Point]] {
        let nodes = (0...28).map { i -> PathNode in let x = Double(i) - 14; return PathNode(Point(x, -2.5 * sin(x * .pi / 14))) }
        var line = RunObject(name: "Sample", nodes: nodes)
        switch stitch {
        case .newLine(let choice):
            guard let made = try? ShapeStitching.openShape(nodes, stitch: choice, satinWidth: SatinLine.defaultWidth, name: "Sample", color: line.color) else { return [] }
            line = made
        case .style(let style):
            line.digitizing = DigitizingSettings(kind: .run)
            line.digitizing?.runStyle = style == .running ? nil : style
        }
        var design = Design(); design.objects = [line]
        guard let plan = try? RunningEngine.compile(design) else { return [] }
        var runs: [[Point]] = []
        for command in plan.commands {
            if command.op == .jump { runs.append([command.point]) }
            else if command.op == .stitch { if runs.isEmpty { runs.append([]) }; runs[runs.count - 1].append(command.point) }
        }
        return runs
    }
}

extension RunStyle {
    /// A few words about the style, for its row in the Line style menu (`summary` says more).
    var tagline: String {
        switch self {
        case .running: return "One line of short stitches."
        case .zigzag: return "Swings from side to side along the line."
        case .blanket: return "Prongs off one side: the appliqué edge."
        case .backStitch: return "Two forward, one back: a hand-sewn look."
        case .stemStitch: return "Slanted stitches, like a twisted rope."
        case .motif: return "A small pattern repeated along the line."
        case .ripple: return "The line again and again, smaller each time."
        }
    }
}

extension OpenShapeStitch {
    /// A few words about the stitch, for its row in the Next shape menus.
    var tagline: String {
        switch self {
        case .bean: return "Each stitch sewn three times: a bolder line."
        case .satin: return "A smooth, shiny band along the line."
        default: return runStyle?.tagline ?? RunStyle.running.tagline
        }
    }
    /// More about it, for its tooltip.
    var summary: String {
        switch self {
        case .bean: return "Each running stitch is sewn three times, there, back and there again, for a bolder line that stands out."
        case .satin: return "A satin column along the line, centered on it, as wide as Satin width (below)."
        default: return runStyle?.summary ?? RunStyle.running.summary
        }
    }
}

/// A picture of `stitch`'s stitches on the sample curve, in `color`, on a patch of cloth. Each stitch is drawn on its
/// own, with a gap at the needle holes, so stitch lengths show, and a stitch sewn over again (a bean stitch's three
/// passes) is drawn bolder, as the piled-up thread looks. Blank cloth until the samples are ready.
struct LineStitchThumbnail: View {
    @ObservedObject private var samples = LineStitchSamples.shared
    let stitch: LineStitch
    let color: ThreadColor
    var body: some View {
        Canvas { context, size in
            guard let runs = samples.runs[stitch] else { return }
            // The middle of the curve, 30 × 20 mm, fills the picture.
            let scale = max(size.width / 30, size.height / 20)
            func place(_ point: Point) -> CGPoint { CGPoint(x: size.width / 2 + point.x * scale, y: size.height / 2 + point.y * scale) }
            // How many times each stitch is sewn, whichever way: keyed by its two ends, rounded to 0.01 mm, in order.
            func key(_ p: Point) -> [Int] { [Int((p.x * 100).rounded()), Int((p.y * 100).rounded())] }
            var times: [[[Int]]: Int] = [:]
            let stitches = runs.flatMap { run in zip(run, run.dropFirst()).filter { $0.0.distance(to: $0.1) > 0.01 } }
            for (a, b) in stitches { times[[key(a), key(b)].sorted { $0.lexicographicallyPrecedes($1) }, default: 0] += 1 }
            var single = Path(), repeated = Path()
            for (a, b) in stitches {
                let length = a.distance(to: b), gap = min(0.2, length / 4), step = (b - a) * (gap / length)
                let sewnAgain = times[[key(a), key(b)].sorted { $0.lexicographicallyPrecedes($1) }]! > 1
                if sewnAgain { repeated.move(to: place(a + step)); repeated.addLine(to: place(b - step)) }
                else { single.move(to: place(a + step)); single.addLine(to: place(b - step)) }
            }
            // A darker strand with a light line along its middle, as in the fill pictures.
            let thread = color.nsColor
            let shade = thread.blended(withFraction: 0.3, of: .black) ?? thread, shine = thread.blended(withFraction: 0.5, of: .white) ?? thread
            for (path, bold) in [(single, 1.0), (repeated, 1.8)] {
                context.stroke(path, with: .color(Color(nsColor: shade)), style: StrokeStyle(lineWidth: max(0.8, 0.45 * scale) * bold, lineCap: .butt))
                context.stroke(path, with: .color(Color(nsColor: shine).opacity(0.8)), style: StrokeStyle(lineWidth: max(0.3, 0.15 * scale) * bold, lineCap: .butt))
            }
        }
        .background(Color(nsColor: Theme.Canvas.fabric))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

/// A selected line's Line style: a button with the current style's picture and name, which opens the list of
/// styles. Pointing at one shows the selected lines sewn that way. `choose` applies a style (one Undo step).
struct LineStyleMenu: View {
    @ObservedObject var state: EditorState
    let style: RunStyle
    let color: ThreadColor
    let choose: (RunStyle) -> Void

    var body: some View {
        PictureListMenu(label: "Line style", options: RunStyle.allCases, current: style, name: \.title, tagline: \.tagline, help: \.summary,
                        tryOut: { option in if let option { Self.preview(option, state) } else { state.previewSettings(nil) } },
                        picture: { LineStitchThumbnail(stitch: .style($0), color: color) }) { option in
            choose(option)
            state.keepSettingsPreview(Self.choice(option))
        }
        .onAppear { LineStitchSamples.shared.load() }
    }
    /// The name of trying `option` out (see SettingsPreview).
    static func choice(_ option: RunStyle) -> String { "line:\(option.rawValue)" }
    /// Tries `option` out on the selected lines, changed as choosing it changes them (width and spacing back to the
    /// style's own).
    static func preview(_ option: RunStyle, _ state: EditorState) {
        state.previewSettings(choice(option), applies: { $0.kind == .run }) { $0.runStyle = option == .running ? nil : option; $0.runWidth = nil; $0.runSpacing = nil }
    }
}

/// The Next shape bar's Stitch (an open shape's stitch) and Outline (a closed shape's, where None is the first
/// choice) menus, in the thread the next shape gets.
struct NewLineStitchMenu: View {
    let label: String
    let current: OpenShapeStitch?
    var offersNone = false
    let color: ThreadColor
    let choose: (OpenShapeStitch?) -> Void

    var body: some View {
        let options: [OpenShapeStitch?] = (offersNone ? [nil] : []) + OpenShapeStitch.allCases.map(Optional.some)
        PictureListMenu(label: label, options: options, current: current, name: { $0?.title ?? "None" },
                        tagline: { $0?.tagline ?? "No outline: just the fill." }, help: { $0?.summary ?? "The shape gets no outline, just its fill." },
                        picture: { option in
                            if let option { LineStitchThumbnail(stitch: .newLine(option), color: color) } else { NoStitchPicture() }
                        }, choose: choose)
        .onAppear { LineStitchSamples.shared.load() }
    }
}
