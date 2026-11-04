// The Color Blend dialog: pick the second thread and which way the blend runs, and see the two layers' real
// stitches before anything changes. The blend itself is made in EmbroideryCore (ColorBlend.swift).
import SwiftUI
import EmbroideryCore

extension GuidedDialog {
    static var lastBlendDirection = 0.0
    /// Shows the Color Blend dialog for `fills`, offering `palette` (the design's threads) as swatches. Returns the
    /// second thread and the blend's direction in degrees, or nil if the person cancelled.
    static func colorBlend(_ fills: [RunObject], palette: [ThreadColor]) -> (second: ThreadColor, direction: Double)? {
        var chosen: (second: ThreadColor, direction: Double)?   // the dialog's closure writes the choice here before it closes
        let confirmed = run(width: 720) { finish in
            ColorBlendView(fills: fills, palette: palette, direction: lastBlendDirection) { choice in
                if let choice { lastBlendDirection = choice.direction }
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
    /// Called with the second thread and the direction, or nil for Cancel.
    let done: ((second: ThreadColor, direction: Double)?) -> Void
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
    private var first: ThreadColor { fills[0].color }
    /// Swatches to pick the second thread from: the palette, then threads picked from the chart, each once, leaving
    /// out the shape's own thread.
    private var swatches: [ThreadColor] {
        var list: [ThreadColor] = []
        for thread in palette + picked where thread != first && !list.contains(thread) { list.append(thread) }
        return list
    }
    private struct PreviewKey: Equatable { var second: ThreadColor?; var direction: Double }

    var body: some View {
        DialogFrame(eyebrow: "Color blend", title: "Blend two threads",
                    subtitle: "Two gradient fills of the same shape, one on top of the other: the first thread solid where the blend starts, the second solid where it ends, mixing in between.",
                    primary: "Add Blend",
                    finish: { add in
                        if !add { done(nil) } else if let second { done((second, direction)) }
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
                                ForEach(Self.directions, id: \.degrees) { Label($0.words, systemImage: $0.arrow).tag($0.degrees) }
                            }.labelsHidden().pickerStyle(.menu).frame(width: 190)
                            // Swapping the colors is the same as running the blend the other way.
                            Button { direction = (direction + 180).truncatingRemainder(dividingBy: 360) } label: { Image(systemName: "arrow.left.arrow.right") }
                                .buttonStyle(ThemedButtonStyle()).help("Swap colors")
                        }
                    }
                    Text("Afterward each layer is an ordinary gradient fill. To let one color reach further, change its layer's spacing in Properties.")
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 260, alignment: .leading)
                ZStack {
                    Theme.ground
                    if let preview { StitchPlanPicture(plan: preview).padding(14) } else { ProgressView().controlSize(.small) }
                }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear { if second == nil { second = swatches.first } }
        // Work out the layers' stitches in the background whenever the thread or direction changes.
        .task(id: PreviewKey(second: second, direction: direction)) {
            preview = nil
            guard let second else { return }
            let fills = fills, direction = direction
            let plan = await Task.detached(priority: .userInitiated) { () -> StitchPlan? in
                var sample = Design()
                sample.objects = fills.flatMap { ColorBlend.layers(of: $0, second: second, direction: direction) }
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
