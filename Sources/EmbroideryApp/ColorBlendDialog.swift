// The Color Blend dialog: pick the second thread, which way the blend runs and where the colors mix, and see the two
// layers' real stitches before anything changes. Also the Levels-style mixing bar, used here and in Properties. The
// blend itself is made in EmbroideryCore (ColorBlend.swift).
import SwiftUI
import EmbroideryCore

/// What the Color Blend dialog was closed with: the second thread, the way the blend runs (degrees), and where the
/// colors mix, seen from the first color's side.
struct BlendChoice { var second: ThreadColor; var direction: Double; var fade: BlendFade }

extension GuidedDialog {
    static var lastBlendDirection = 0.0
    /// Shows the Color Blend dialog for `fills`, offering `palette` (the design's threads) as swatches. `editing` is
    /// an existing blend's choices, to change them (`fills` is then its first color's layer). Returns the choices, or
    /// nil if the person cancelled.
    static func colorBlend(_ fills: [RunObject], palette: [ThreadColor], editing: BlendChoice? = nil) -> BlendChoice? {
        var chosen: BlendChoice?   // the dialog's closure writes the choice here before it closes
        let confirmed = run(width: 720) { finish in
            ColorBlendView(fills: fills, palette: palette, direction: editing?.direction ?? lastBlendDirection, startDirection: editing?.direction ?? lastBlendDirection,
                           editing: editing != nil, startSecond: editing?.second, fade: editing?.fade ?? .whole) { choice in
                if let choice, editing == nil { lastBlendDirection = choice.direction }
                chosen = choice; finish(choice != nil)
            }
        }
        return confirmed ? chosen : nil
    }
}

struct ColorBlendView: View {
    let fills: [RunObject]
    let palette: [ThreadColor]
    @State var direction: Double
    /// The direction the dialog opened with: offered in the menu too when it isn't one of the eight (an edited blend
    /// whose angle was typed in Properties).
    let startDirection: Double
    /// True when changing a blend that's already made, starting from its second thread `startSecond`.
    var editing = false
    var startSecond: ThreadColor? = nil
    /// Where the colors mix, seen from the first color's side.
    @State var fade: BlendFade
    /// Called with the choices, or nil for Cancel.
    let done: (BlendChoice?) -> Void
    @State private var second: ThreadColor?
    /// Threads picked from the thread chart, shown as swatches beside the palette's.
    @State private var picked: [ThreadColor] = []
    /// The two layers' stitches; nil while they're worked out.
    @State private var preview: StitchPlan?

    /// The eight directions offered: degrees (0 = left to right, counterclockwise), an arrow, and words for it.
    private static let directions: [(degrees: Double, arrow: String, words: String)] = [
        (0, "arrow.right", "Left to right"), (45, "arrow.up.right", "Up and to the right"), (90, "arrow.up", "Bottom to top"),
        (135, "arrow.up.left", "Up and to the left"), (180, "arrow.left", "Right to left"), (225, "arrow.down.left", "Down and to the left"),
        (270, "arrow.down", "Top to bottom"), (315, "arrow.down.right", "Down and to the right"),
    ]
    /// The eight directions, plus the one the dialog opened with if it's another.
    private var directionChoices: [(degrees: Double, arrow: String, words: String)] {
        Self.directions.contains { $0.degrees == startDirection } ? Self.directions : Self.directions + [(startDirection, "safari", "As it is now, \(Int(startDirection.rounded()))°")]
    }
    private var first: ThreadColor { fills[0].color }
    /// Swatches to pick the second thread from: the palette, then threads picked from the chart, each once, leaving
    /// out the shape's own thread.
    private var swatches: [ThreadColor] {
        var list: [ThreadColor] = []
        for thread in palette + picked where thread != first && !list.contains(thread) { list.append(thread) }
        return list
    }
    private struct PreviewKey: Equatable { var second: ThreadColor?; var direction: Double; var fade: BlendFade }

    var body: some View {
        DialogFrame(eyebrow: "Color blend", title: editing ? "Change the blend" : "Blend two threads",
                    subtitle: "Two gradient fills of the same shape, one on top of the other: the first thread solid where the blend starts, the second solid where it ends, mixing in between.",
                    primary: editing ? "Update Blend" : "Add Blend",
                    finish: { add in
                        if !add { done(nil) } else if let second { done(BlendChoice(second: second, direction: direction, fade: fade)) }
                    }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("From").font(Theme.body(13, weight: .semibold))
                        HStack(spacing: 6) {
                            Circle().fill(Color(nsColor: first.nsColor)).frame(width: 14, height: 14)
                            Text(fills.count == 1 ? "\(first.name), the shape's thread" : "Each shape's own thread").foregroundStyle(Theme.inkSecondary)
                        }.font(Theme.body(12))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To").font(Theme.body(13, weight: .semibold))
                        // LazyVGrid lays the swatches out in rows of up to eight.
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                            ForEach(swatches, id: \.self) { thread in
                                Button { second = thread } label: {
                                    Circle().fill(Color(nsColor: thread.nsColor)).frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(Theme.ink, lineWidth: second == thread ? 2 : 0).padding(-3))
                                }.buttonStyle(.plain).help(thread.name)
                            }
                        }
                        Button("Thread Chart…") { chooseFromChart() }.buttonStyle(ThemedButtonStyle())
                        if let second { Text(second.name).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Direction").font(Theme.body(13, weight: .semibold))
                        HStack {
                            Picker("Direction", selection: $direction) {
                                ForEach(directionChoices, id: \.degrees) { Label($0.words, systemImage: $0.arrow).tag($0.degrees) }
                            }.labelsHidden().pickerStyle(.menu).frame(width: 190)
                            // Swapping the colors is the same as running the blend the other way.
                            Button { direction = (direction + 180).truncatingRemainder(dividingBy: 360) } label: { Image(systemName: "arrow.left.arrow.right") }
                                .buttonStyle(ThemedButtonStyle()).help("Swap colors")
                        }
                    }
                    if let second {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mix").font(Theme.body(13, weight: .semibold))
                            LevelsBar(fade: fade, first: first, second: second, onChange: { fade = $0 })
                        }
                    }
                    Text("The two layers keep one shape: reshape or turn either and the other follows.")
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 280, alignment: .leading)
                ZStack {
                    Theme.ground
                    if let preview { StitchPlanPicture(plan: preview).padding(14) } else { ProgressView().controlSize(.small) }
                }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear {
            if let startSecond, !swatches.contains(startSecond) { picked.append(startSecond) }   // a thread no longer in the palette still shows
            if second == nil { second = startSecond ?? swatches.first }
        }
        // Work out the layers' stitches in the background whenever the thread or direction changes.
        .task(id: PreviewKey(second: second, direction: direction, fade: fade)) {
            preview = nil
            guard let second else { return }
            let fills = fills, direction = direction, fade = fade
            let plan = await Task.detached(priority: .userInitiated) { () -> StitchPlan? in
                var sample = Design()
                sample.objects = fills.flatMap { ColorBlend.layers(of: $0, second: second, direction: direction, fade: fade) }
                return try? StitchEngine.compile(sample)
            }.value
            if !Task.isCancelled { preview = plan }
        }
    }

    /// Opens the thread chart over this dialog; a thread chosen there becomes the second thread.
    private func chooseFromChart() {
        guard case .use(let thread)? = GuidedDialog.threadChart(current: second ?? first, designThreads: palette) else { return }
        if !picked.contains(thread) { picked.append(thread) }
        second = thread
    }
}

/// A stitch plan drawn as its stitches, each in its thread's color, scaled to fit.
struct StitchPlanPicture: View {
    let plan: StitchPlan
    var body: some View {
        Canvas { context, size in
            let points = plan.commands.map(\.point)
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
            let scale = min(size.width / max(maxX - minX, 0.1), size.height / max(maxY - minY, 0.1))
            let left = (size.width - (maxX - minX) * scale) / 2, bottom = (size.height - (maxY - minY) * scale) / 2
            // Design coordinates point up; screen coordinates point down, so y is flipped here.
            func place(_ p: Point) -> CGPoint { CGPoint(x: left + (p.x - minX) * scale, y: size.height - (bottom + (p.y - minY) * scale)) }
            // A stitch is the thread from the needle's last place (after a stitch or a jump) to the new one.
            for (previous, command) in zip(plan.commands, plan.commands.dropFirst())
            where command.op == .stitch && [.stitch, .jump].contains(previous.op) && plan.threads.indices.contains(command.thread) {
                var line = Path(); line.move(to: place(previous.point)); line.addLine(to: place(command.point))
                context.stroke(line, with: .color(Color(nsColor: plan.threads[command.thread].nsColor)), lineWidth: 0.6)
            }
        }
        .accessibilityLabel("Preview of the blend's stitches")
    }
}

/// Where the two threads of a blend mix, drawn as a bar of the blend with three handles under it, like Levels in a
/// photo editor: where the first thread stops being solid, where the two mix half and half (the diamond), and where the
/// second becomes solid. `onChange` hears every move while dragging; `onCommit` hears the result when a drag ends (or a
/// handle is nudged with VoiceOver), so Properties records one Undo step per drag.
struct LevelsBar: View {
    let fade: BlendFade
    let first: ThreadColor
    let second: ThreadColor
    var onChange: (BlendFade) -> Void = { _ in }
    var onCommit: (BlendFade) -> Void = { _ in }
    /// The handles' places while one is being dragged; nil shows `fade`.
    @State private var dragging: BlendFade?
    /// Handles keep at least this far apart (as a fraction of the bar).
    private static let gap = 0.02

    var body: some View {
        let shown = dragging ?? fade
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(stops: [
                            .init(color: color(first), location: 0), .init(color: color(first), location: shown.start),
                            .init(color: mixed, location: shown.middle),
                            .init(color: color(second), location: shown.end), .init(color: color(second), location: 1),
                        ], startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.divider))
                        .frame(height: 22)
                    handle(\.start, in: shown, width: width, shape: AnyShape(LevelsTriangle()), fill: color(first), name: "\(first.name) solid until")
                    handle(\.middle, in: shown, width: width, shape: AnyShape(LevelsDiamond()), fill: Theme.card, name: "Half and half at")
                    handle(\.end, in: shown, width: width, shape: AnyShape(LevelsTriangle()), fill: color(second), name: "\(second.name) solid from")
                }
                .coordinateSpace(name: "levels")
            }
            .frame(height: 42)
            Text("\(first.name) solid to \(percent(shown.start)) · half and half at \(percent(shown.middle)) · \(second.name) solid from \(percent(shown.end))")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One handle under the bar, with a hairline up into it; dragging it moves that point of the fade.
    private func handle(_ key: WritableKeyPath<BlendFade, Double>, in shown: BlendFade, width: CGFloat, shape: AnyShape, fill: Color, name: String) -> some View {
        shape.fill(fill).overlay(shape.stroke(Theme.ink, lineWidth: 1))
            .frame(width: 16, height: 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.ink.opacity(0.5)).frame(width: 1.5, height: 24).offset(y: -25) }
            .contentShape(Rectangle().inset(by: -6))   // a little easier to grab
            .position(x: shown[keyPath: key] * width, y: 33)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("levels"))
                .onChanged { drag in let next = moved(key, to: drag.location.x / max(width, 1), from: dragging ?? fade); dragging = next; onChange(next) }
                .onEnded { _ in if let done = dragging { onCommit(done) }; dragging = nil })
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityValue(percent(shown[keyPath: key]))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.01 : -0.01, next = moved(key, to: fade[keyPath: key] + step, from: fade)
                onChange(next); onCommit(next)
            }
    }
    /// `fade` with one point moved to `value`, kept in order (start < middle < end) and inside the bar.
    private func moved(_ key: WritableKeyPath<BlendFade, Double>, to value: Double, from fade: BlendFade) -> BlendFade {
        var next = fade
        let value = min(1, max(0, value)), gap = Self.gap
        if key == \BlendFade.start { next.start = max(0, min(value, next.middle - gap)) }
        else if key == \BlendFade.end { next.end = min(1, max(value, next.middle + gap)) }
        else { next.middle = min(max(value, next.start + gap), next.end - gap) }
        return next
    }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func color(_ thread: ThreadColor) -> Color { Color(nsColor: thread.nsColor) }
    /// The two threads half and half, for the middle of the bar.
    private var mixed: Color {
        func channel(_ shift: Int) -> Double { Double(((first.hex >> shift) & 255) + ((second.hex >> shift) & 255)) / 2 / 255 }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
}

/// The Levels bar's end handles: a small triangle pointing up at the bar.
struct LevelsTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.closeSubpath() }
    }
}
/// The Levels bar's middle handle: a diamond.
struct LevelsDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); p.closeSubpath() }
    }
}
