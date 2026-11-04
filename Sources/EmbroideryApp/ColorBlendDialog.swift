// The Color Blend dialog: pick the second thread, which way the blend runs and where the colors mix, and see the two
// layers' real stitches before anything changes. Also the Levels-style mixing bar, used here and in Properties. The
// blend itself is made in EmbroideryCore (ColorBlend.swift).
import SwiftUI
import EmbroideryCore

/// What the Color Blend dialog was closed with: the first thread (nil keeps each fill's own), the second thread, the
/// way the blend runs (degrees), and where the colors mix, seen from the first color's side.
struct BlendChoice { var first: ThreadColor?; var second: ThreadColor; var direction: Double; var fade: BlendFade }

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
    /// The first thread for every selected fill; nil keeps each fill's own (offered while their threads differ).
    @State private var first: ThreadColor?
    @State private var second: ThreadColor?
    /// Threads picked from the thread chart, shown as swatches beside the palette's.
    @State private var picked: [ThreadColor] = []
    /// The two layers' stitches; nil while they're worked out.
    @State private var preview: StitchPlan?
    /// True draws the preview as real thread (Thread View), false as plain stitch lines. Starts as the canvas is.
    @State private var threadView = Preferences.shared.threadView
    /// The direction line drawn across the preview (in its points): while dragging, and after, until the direction is
    /// changed another way. `degrees` is the direction it set.
    @State private var drawnLine: (start: CGPoint, end: CGPoint, degrees: Double?)?

    /// The eight directions offered: degrees (0 = left to right, counterclockwise), an arrow, and words for it.
    private static let directions: [(degrees: Double, arrow: String, words: String)] = [
        (0, "arrow.right", "Left to right"), (45, "arrow.up.right", "Up and to the right"), (90, "arrow.up", "Bottom to top"),
        (135, "arrow.up.left", "Up and to the left"), (180, "arrow.left", "Right to left"), (225, "arrow.down.left", "Down and to the left"),
        (270, "arrow.down", "Top to bottom"), (315, "arrow.down.right", "Down and to the right"),
    ]
    /// The eight directions, plus the current one if it's another: drawn on the preview, or as the blend was when the
    /// dialog opened (an angle typed in Properties).
    private var directionChoices: [(degrees: Double, arrow: String, words: String)] {
        guard !Self.directions.contains(where: { $0.degrees == direction }) else { return Self.directions }
        let words = direction == startDirection && drawnLine == nil ? "As it is now" : "Drawn"
        return Self.directions + [(direction, "pencil.and.outline", "\(words), \(Int(direction.rounded()))°")]
    }
    /// The selected fills' own threads, each once.
    private var ownThreads: [ThreadColor] {
        var list: [ThreadColor] = []
        for fill in fills where !list.contains(fill.color) { list.append(fill.color) }
        return list
    }
    /// The first thread as shown: the one chosen, or the first fill's own.
    private var shownFirst: ThreadColor { first ?? fills[0].color }
    /// Threads to pick from: the fills' own, the palette, then threads picked from the chart, each once, leaving out
    /// `excluded` (the thread chosen for the blend's other end).
    private func swatches(excluding excluded: ThreadColor?) -> [ThreadColor] {
        var list: [ThreadColor] = []
        for thread in ownThreads + palette + picked where thread != excluded && !list.contains(thread) { list.append(thread) }
        return list
    }
    private struct PreviewKey: Equatable { var first: ThreadColor?; var second: ThreadColor?; var direction: Double; var fade: BlendFade }

    var body: some View {
        DialogFrame(eyebrow: "Color blend", title: editing ? "Change the blend" : "Blend two threads",
                    subtitle: "Two gradient fills of the same shape, one on top of the other: the first thread solid where the blend starts, the second solid where it ends, mixing in between.",
                    primary: editing ? "Update Blend" : "Add Blend",
                    finish: { add in
                        if !add { done(nil) } else if let second { done(BlendChoice(first: first, second: second, direction: direction, fade: fade)) }
                    }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("From").font(Theme.body(13, weight: .semibold))
                        if ownThreads.count > 1 {
                            Toggle("Each shape's own thread", isOn: Binding(get: { first == nil }, set: { first = $0 ? nil : ownThreads[0] }))
                                .toggleStyle(.checkbox).font(Theme.body(12))
                        }
                        threadPicker(selected: first, excluding: second) { first = $0 }
                        Text(first?.name ?? "Each shape's own thread").font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To").font(Theme.body(13, weight: .semibold))
                        threadPicker(selected: second, excluding: shownFirst) { second = $0 }
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
                            LevelsBar(fade: fade, first: shownFirst, second: second, onChange: { fade = $0 })
                        }
                    }
                    Text("The two layers keep one shape: reshape or turn either and the other follows.")
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 280, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    Picker("Preview", selection: $threadView) {
                        Text("Stitches").tag(false)
                        Text("Thread View").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    ZStack {
                        Theme.ground
                        if let preview { StitchPlanPicture(plan: preview, threadView: threadView).padding(14) } else { ProgressView().controlSize(.small) }
                        // The drawn direction, shown while it's the blend's direction.
                        if let line = drawnLine, line.degrees == nil || line.degrees == direction { DirectionArrow(start: line.start, end: line.end) }
                    }
                    .frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                    .gesture(drawDirection)
                    .help("Drag across the preview to draw which way the blend runs, from the first thread toward the second. Hold Shift for 15° steps.")
                    Text("Drag across the preview to draw the direction.").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .onAppear {
            if ownThreads.count == 1 { first = ownThreads[0] }
            if let startSecond, !swatches(excluding: nil).contains(startSecond) { picked.append(startSecond) }   // a thread no longer in the palette still shows
            if second == nil { second = startSecond ?? swatches(excluding: shownFirst).first }
        }
        // Work out the layers' stitches in the background whenever a thread, the direction or the mix changes.
        .task(id: PreviewKey(first: first, second: second, direction: direction, fade: fade)) {
            preview = nil
            guard let second else { return }
            let fills = fills.map { fill -> RunObject in var fill = fill; if let first { fill.color = first }; return fill }
            let direction = direction, fade = fade
            let plan = await Task.detached(priority: .userInitiated) { () -> StitchPlan? in
                var sample = Design()
                sample.objects = fills.flatMap { ColorBlend.layers(of: $0, second: second, direction: direction, fade: fade) }
                return try? StitchEngine.compile(sample)
            }.value
            if !Task.isCancelled { preview = plan }
        }
    }

    /// Drawing the direction on the preview: from where the first thread should be solid toward the second. The
    /// screen's y runs down and the design's up, so y is turned over. Whole degrees, or 15° steps with Shift; a drag
    /// shorter than 8 points (a click) changes nothing.
    private var drawDirection: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag in drawnLine = (drag.startLocation, drag.location, nil) }
            .onEnded { drag in
                guard let degrees = Self.drawnDirection(from: drag.startLocation, to: drag.location, step: NSEvent.modifierFlags.contains(.shift) ? 15 : 1) else { drawnLine = nil; return }
                drawnLine = (drag.startLocation, drag.location, degrees)
                direction = degrees
            }
    }
    /// The blend direction (degrees, 0 = left to right, counterclockwise, 0 up to 360) of a line drawn on screen from
    /// `start` to `end`, rounded to `step` degrees; nil for a line under 8 points long.
    static func drawnDirection(from start: CGPoint, to end: CGPoint, step: Double) -> Double? {
        let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
        guard hypot(dx, dy) >= 8 else { return nil }
        let degrees = (atan2(-dy, dx) * 180 / .pi / step).rounded() * step   // -dy: the screen's y runs down
        return degrees < 0 ? degrees + 360 : degrees >= 360 ? degrees - 360 : degrees
    }

    /// Swatches in rows of up to eight, then a Thread Chart… button. `selected` gets a ring; `choose` hears the thread
    /// picked from either.
    private func threadPicker(selected: ThreadColor?, excluding: ThreadColor?, choose: @escaping (ThreadColor) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // LazyVGrid lays the swatches out in rows of up to eight.
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                ForEach(swatches(excluding: excluding), id: \.self) { thread in
                    Button { choose(thread) } label: {
                        Circle().fill(Color(nsColor: thread.nsColor)).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Theme.ink, lineWidth: selected == thread ? 2 : 0).padding(-3))
                    }.buttonStyle(.plain).help(thread.name)
                }
            }
            Button("Thread Chart…") { if let thread = chartThread(current: selected ?? shownFirst) { choose(thread) } }.buttonStyle(ThemedButtonStyle())
        }
    }
    /// Opens the thread chart over this dialog and returns the thread chosen there (also kept as a swatch), or nil.
    private func chartThread(current: ThreadColor) -> ThreadColor? {
        guard case .use(let thread)? = GuidedDialog.threadChart(current: current, designThreads: palette) else { return nil }
        if !picked.contains(thread) { picked.append(thread) }
        return thread
    }
}

/// A stitch plan scaled to fit: each stitch as a thin line in its thread's color, or with `threadView` as real thread,
/// drawn the way the canvas's Thread View draws it.
struct StitchPlanPicture: View {
    let plan: StitchPlan
    var threadView = false
    var body: some View {
        Canvas { context, size in
            let points = plan.commands.map(\.point)
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
            let scale = min(size.width / max(maxX - minX, 0.1), size.height / max(maxY - minY, 0.1))
            let left = (size.width - (maxX - minX) * scale) / 2, bottom = (size.height - (maxY - minY) * scale) / 2
            if threadView {
                // withCGContext hands over the drawing as Core Graphics, which DesignCanvas.drawThread uses. Flipping it
                // to point up, as the design and the canvas do, keeps the light and shadows falling the same way.
                context.withCGContext { cg in
                    cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
                    DesignCanvas.drawThread(cg, plan.commands[...], from: plan.commands.first?.point ?? Point(0, 0), threads: plan.threads, hidden: [], showUnderlay: true,
                                            width: max(1.2, 0.45 * scale), visibleArea: CGRect(origin: .zero, size: size)) { p in
                        CGPoint(x: left + (p.x - minX) * scale, y: bottom + (p.y - minY) * scale)
                    }
                }
                return
            }
            // Design coordinates point up; screen coordinates point down, so y is flipped here.
            func place(_ p: Point) -> CGPoint { CGPoint(x: left + (p.x - minX) * scale, y: size.height - (bottom + (p.y - minY) * scale)) }
            // A stitch is the thread from the needle's last place (after a stitch or a jump) to the new one. zip pairs
            // each command with the one after it.
            for (previous, command) in zip(plan.commands, plan.commands.dropFirst())
            where command.op == .stitch && [.stitch, .jump].contains(previous.op) && plan.threads.indices.contains(command.thread) {
                var line = Path(); line.move(to: place(previous.point)); line.addLine(to: place(command.point))
                context.stroke(line, with: .color(Color(nsColor: plan.threads[command.thread].nsColor)), lineWidth: 0.6)
            }
        }
        .accessibilityLabel(threadView ? "Preview of the blend in Thread View" : "Preview of the blend's stitches")
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

/// The direction drawn on the Color Blend preview: a dot where it starts and an arrowhead where it points, dark with a
/// light edge so it shows on any thread color.
struct DirectionArrow: View {
    let start: CGPoint
    let end: CGPoint
    var body: some View {
        let angle = Double(atan2(end.y - start.y, end.x - start.x)), head = 10.0
        let left = CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6))
        let shape = Path { p in
            p.move(to: start); p.addLine(to: end)
            p.move(to: left); p.addLine(to: end); p.addLine(to: right)
        }
        ZStack {
            shape.stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            shape.stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            Circle().fill(Color.black.opacity(0.85)).overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: 9, height: 9).position(start)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
