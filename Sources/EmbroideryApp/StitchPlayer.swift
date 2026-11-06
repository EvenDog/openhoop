// The stitch player at the right end of the tool strip: what color and object it's at, rewind, jumps to the previous
// or next color and object and to the end, play or pause, pause at trims, a speed menu, and a timeline of the design's
// colors (with its trims, stops and objects marked) to scrub through. The tool rail down the left shows it stacked at
// the bottom instead, with the colors, the color jumps and the speed buttons.
import SwiftUI
import EmbroideryCore

/// The stitch player as one more captioned group of the tool strip, or stacked for the narrow left rail.
struct StripPlayer: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// True for the left rail: everything in one narrow column.
    var stacked = false
    var body: some View {
        let total = state.plan.stitchCount
        let count = Text("\(Int(state.playback * Double(total)).formatted()) / \(total.formatted())")
            .font(Theme.body(10, weight: .semibold)).monospacedDigit().foregroundStyle(secondaryInk).lineLimit(1)
        if stacked {
            VStack(alignment: .leading, spacing: 5) {
                caption
                HStack(spacing: 4) { rewindButton; playButton; pauseAtTrimsButton }
                HStack(spacing: 4) { jumpButton(.previousColor); jumpButton(.nextColor); jumpButton(.toEnd) }
                TimelineBar(state: state, showsMarks: false)
                count.minimumScaleFactor(0.7)
                SpeedButtons(stacked: true)
            }
        } else {
            // Three rows, like the tool groups beside it: what's sewing and the count, the buttons, then the timeline.
            // It's as wide as the strip has room for, between the two widths, so the tools are never pushed off.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { caption; nowSewing; Spacer(minLength: 8); count }
                // In a narrow strip the object and end jumps step aside (their keys and menu items still work), so
                // the player needs no more room than it used to.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 2) {
                        rewindButton; jumpButton(.previousColor); jumpButton(.previousObject)
                        playButton.padding(.horizontal, 3)
                        jumpButton(.nextObject); jumpButton(.nextColor); jumpButton(.toEnd)
                        Theme.toolBandDivider.frame(width: 1, height: 16).padding(.horizontal, 6)
                        pauseAtTrimsButton
                        Spacer(minLength: 8)
                        SpeedMenu()
                    }
                    HStack(spacing: 2) {
                        rewindButton; jumpButton(.previousColor); playButton.padding(.horizontal, 2); jumpButton(.nextColor); pauseAtTrimsButton
                        Spacer(minLength: 4)
                        SpeedMenu()
                    }
                }
                TimelineBar(state: state, showsMarks: true)
            }
            .frame(minWidth: 250, idealWidth: 460, maxWidth: 520)
        }
    }
    private var secondaryInk: Color { Theme.toolBandInkSecondary }   // the tool band has its own ink colors
    /// The group's caption, in the same type as the tool groups' captions.
    private var caption: some View {
        Text("PLAYER").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8)
            .foregroundStyle(secondaryInk).padding(.leading, 3).lineLimit(1).fixedSize()
    }
    /// The color the player is at (what sews next), with its place among the design's colors and, when there's room,
    /// the object's name. In a narrower strip the object, then the place, are left out.
    @ViewBuilder private var nowSewing: some View {
        let timeline = state.playerTimeline, threads = state.plan.threads
        let position = Int(Double(timeline.length) * state.playback)
        if let colorIndex = PlayerTimeline.index(at: position, in: timeline.colors) {
            let thread = threads.indices.contains(timeline.colors[colorIndex].thread) ? threads[timeline.colors[colorIndex].thread] : nil
            // `flatMap` carries on only when there is a value: an object run, then its object's id, then the object.
            let object = PlayerTimeline.index(at: position, in: timeline.objects).flatMap { timeline.objects[$0].objectID }
                .flatMap { id in state.design.objects.first { $0.id == id } }
            let swatch = Circle().fill(thread.map { Color(nsColor: $0.nsColor) } ?? Theme.toolBandDivider).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
            let name = Text(thread?.name ?? "Thread").font(Theme.body(11, weight: .bold)).foregroundStyle(Theme.toolBandInk)
            let place = Text("color \(colorIndex + 1) of \(timeline.colors.count)").font(Theme.body(10)).foregroundStyle(secondaryInk)
            let objectName = Text("· \(object?.name ?? "")").font(Theme.body(10, weight: .semibold)).foregroundStyle(Theme.toolBandInk)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { swatch; name; place; if object != nil { objectName } }
                HStack(spacing: 5) { swatch; name; place }
                HStack(spacing: 5) { swatch; name }
                swatch
            }
            .lineLimit(1)
            .help("What sews next: \(thread?.name ?? "this thread")\(object.map { ", in \($0.name)" } ?? "")")
        }
    }
    private var rewindButton: some View {
        Button { AppDelegate.shared.perform(.rewind) } label: {
            Image(systemName: "backward.end.fill").font(.system(size: 10)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(secondaryInk)
        .help(preferences.hint(.rewind)).accessibilityLabel("Rewind")
    }
    /// A button for one of the player's jumps: an arrow beside a dot for a color, beside a square for an object, or
    /// the end. They do what the Stitch Player menu's commands do, keys included.
    private func jumpButton(_ command: CommandID) -> some View {
        Button { AppDelegate.shared.perform(command) } label: {
            jumpIcon(command).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(secondaryInk)
        .help(preferences.hint(command)).accessibilityLabel(command.title)
    }
    @ViewBuilder private func jumpIcon(_ command: CommandID) -> some View {
        let back = Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
        let on = Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
        let color = Image(systemName: "circle.fill").font(.system(size: 7))
        let object = Image(systemName: "square").font(.system(size: 8, weight: .bold))
        switch command {
        case .previousColor: HStack(spacing: 1) { back; color }
        case .nextColor: HStack(spacing: 1) { color; on }
        case .previousObject: HStack(spacing: 1) { back; object }
        case .nextObject: HStack(spacing: 1) { object; on }
        default: Image(systemName: "forward.end.fill").font(.system(size: 10))
        }
    }
    private var playButton: some View {
        Button { AppDelegate.shared.perform(.play) } label: {
            Image(systemName: state.playing ? "pause.fill" : "play.fill").font(.system(size: 9))
                .frame(width: 22, height: 22).background(Circle().fill(Theme.accent)).foregroundStyle(Theme.onAccent)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(state.playing ? "Pause  \(preferences.label(.play))" : preferences.hint(.play))
        .accessibilityLabel(state.playing ? "Pause" : "Play")
    }
    /// Pause at trims: lit, playing stops at each trim, stop and thread change, like a sew-out. Remembered between launches.
    private var pauseAtTrimsButton: some View {
        let on = preferences.data.pauseAtTrims == true
        return Button { preferences.data.pauseAtTrims = on ? nil : true; preferences.save(announce: false) } label: {
            Image(systemName: "scissors").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
                .background(Circle().fill(on ? Theme.accent.opacity(0.18) : Color.clear))
                .foregroundStyle(on ? Theme.accent : secondaryInk)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(on ? "Pausing at trims, stops and thread changes. Press Play to carry on; click to play straight through."
              : "Pause at trims: playing stops at each trim, stop and thread change, as the machine would.")
        .accessibilityLabel("Pause at trims").accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The player's timeline: the design's colors as blocks in sewing order, each as long as its share of the design,
/// the part not sewn yet faded, and the playhead. With `showsMarks`, scissors above it mark the trims, a terracotta
/// mark the stops, and ticks below it where each object starts. Click or drag on it to move the player there.
struct TimelineBar: View {
    @ObservedObject var state: EditorState
    let showsMarks: Bool
    var body: some View {
        let timeline = state.playerTimeline, threads = state.plan.threads, playback = state.playback
        let markHeight: CGFloat = showsMarks ? 11 : 0, barHeight: CGFloat = 10, tickHeight: CGFloat = showsMarks ? 5 : 0
        let barTop = markHeight + 2
        GeometryReader { geometry in
            Canvas { context, size in
                let length = Double(max(1, timeline.length))
                // Where a position (a count of commands) sits along the bar.
                func x(_ position: Int) -> CGFloat { CGFloat(Double(position) / length) * size.width }
                // Where a mark above the bar goes: kept far enough in from the ends to show whole.
                func markX(_ position: Int) -> CGFloat { min(max(x(position), 5), size.width - 5) }
                let head = CGFloat(playback) * size.width
                let bar = Path(roundedRect: CGRect(x: 0, y: barTop, width: size.width, height: barHeight), cornerRadius: 3)
                context.fill(bar, with: .color(Theme.toolBandDivider))
                // A layer clipped to the bar's rounded ends: each color's block (a 1 pt gap after it), then the part
                // not sewn yet faded with the band's color.
                context.drawLayer { layer in
                    layer.clip(to: bar)
                    for run in timeline.colors {
                        let color = threads.indices.contains(run.thread) ? Color(nsColor: threads[run.thread].nsColor) : Theme.toolBandDivider
                        let block = CGRect(x: x(run.start), y: barTop, width: max(1, x(run.end) - x(run.start) - 1), height: barHeight)
                        layer.fill(Path(block), with: .color(color))
                    }
                    layer.fill(Path(CGRect(x: head, y: barTop, width: size.width - head, height: barHeight)), with: .color(Theme.toolBand.opacity(0.6)))
                }
                context.stroke(bar, with: .color(Color.black.opacity(0.18)), lineWidth: 0.5)
                if showsMarks {
                    // Marks closer than a few points to the one before are skipped, so a busy design doesn't smear.
                    var lastTrim = -100.0
                    for position in timeline.trims where Double(x(position)) - lastTrim >= 7 {
                        if let scissors = context.resolveSymbol(id: 0) { context.draw(scissors, at: CGPoint(x: markX(position), y: markHeight / 2 + 1)) }
                        lastTrim = Double(x(position))
                    }
                    for position in timeline.stops {
                        if let stop = context.resolveSymbol(id: 1) { context.draw(stop, at: CGPoint(x: markX(position), y: markHeight / 2 + 1)) }
                    }
                    var lastTick = -100.0
                    for run in timeline.objects.dropFirst() where Double(x(run.start)) - lastTick >= 3 {
                        context.fill(Path(CGRect(x: x(run.start), y: barTop + barHeight + 1, width: 1, height: tickHeight)), with: .color(Theme.toolBandInkSecondary.opacity(0.7)))
                        lastTick = Double(x(run.start))
                    }
                }
                // The playhead: a dark upright bar with a light edge, a little taller than the bar.
                let handle = Path(roundedRect: CGRect(x: head - 1.5, y: barTop - 3, width: 3, height: barHeight + 6), cornerRadius: 1.5)
                context.stroke(handle, with: .color(Theme.card), lineWidth: 2)
                context.fill(handle, with: .color(Theme.toolBandInk))
            } symbols: {
                // Drawn by the marks above (`resolveSymbol(id:)` looks them up by these tags).
                Image(systemName: "scissors").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.toolBandInkSecondary).tag(0)
                Image(systemName: "pause.rectangle.fill").font(.system(size: 9)).foregroundStyle(Theme.primaryAction).tag(1)
            }
            .contentShape(Rectangle())
            // `minimumDistance: 0` makes a plain click move the player too, not only a drag.
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                state.playback = min(1, max(0, Double(drag.location.x / max(1, geometry.size.width))))
            })
        }
        .frame(height: barTop + barHeight + 1 + tickHeight)
        .help("Click or drag to step through the design, stitch by stitch. Each block is one thread color"
              + (showsMarks ? "; scissors mark trims, ticks mark where each object starts." : ".") + " Esc shows the whole design again.")
        .accessibilityElement()
        .accessibilityLabel("Stitch sequence")
        .accessibilityValue("Stitch \(Int(playback * Double(state.plan.stitchCount)).formatted()) of \(state.plan.stitchCount.formatted())")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: state.playback = min(1, state.playback + 0.01)
            case .decrement: state.playback = max(0, state.playback - 0.01)
            @unknown default: break
            }
        }
    }
}

/// The speed as one menu button, for the tool strip's player: the speed it sews at, and a menu of the preset speeds,
/// a speed of your own, and a way to change the presets in Settings.
private struct SpeedMenu: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var choosingCustomSpeed = false
    var body: some View {
        Menu {
            // An inline picker shows the presets as menu items with a check by the one in use.
            Picker("Speed", selection: $preferences.playbackSpeed) {
                ForEach(preferences.speedPresets, id: \.self) { Text("\(Int($0).formatted()) stitches/s").tag($0) }
            }
            .pickerStyle(.inline).labelsHidden()
            Divider()
            Button("Custom Speed…") { choosingCustomSpeed = true }
            Button("Change Preset Speeds…") { SettingsNavigation.shared.page = .tools; AppDelegate.shared.perform(.settings) }
        } label: {
            Text("\(Int(preferences.playbackSpeed).formatted()) st/s").font(Theme.body(11, weight: .bold)).monospacedDigit()
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("How fast the player sews, in stitches per second. A machine sews about 12.")
        .accessibilityLabel("Speed, \(Int(preferences.playbackSpeed).formatted()) stitches per second")
        .popover(isPresented: $choosingCustomSpeed, arrowEdge: .bottom) {
            HStack(spacing: 6) {
                Text("Speed")
                PlaybackSpeedField().frame(width: 60)
                Text("stitches/s")
            }
            .font(Theme.body(12)).foregroundStyle(Theme.ink).padding(12)
        }
    }
}

/// The speed buttons. The lit one is the speed the player sews at; changing it while playing takes effect at once.
/// A right-click offers a one-off speed of your own, or opens Settings to change the buttons.
private struct SpeedButtons: View {
    /// True for the left rail: the buttons two by two, with the unit below.
    let stacked: Bool
    @ObservedObject var preferences = Preferences.shared
    @State private var choosingCustomSpeed = false
    var body: some View {
        let presets = preferences.speedPresets
        // A speed typed in Custom Speed… that isn't one of the buttons shows next to "st/s" instead.
        let custom = !presets.contains(preferences.playbackSpeed)
        let unit = Text(custom ? "\(Int(preferences.playbackSpeed).formatted()) st/s" : "st/s")
            .font(Theme.body(11, weight: custom ? .bold : .regular))
            .foregroundStyle(custom ? Theme.accent : secondaryInk)
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 3) {
                    // Two flexible columns: the four buttons sit two by two in the rail's narrow width.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) { buttons(presets) }
                    unit.padding(.leading, 3)
                }
            } else {
                HStack(spacing: 2) { buttons(presets); unit.padding(.leading, 3) }
            }
        }
        .contextMenu {
            Button("Custom Speed…") { choosingCustomSpeed = true }
            Button("Change Speed Buttons…") { SettingsNavigation.shared.page = .tools; AppDelegate.shared.perform(.settings) }
        }
        .popover(isPresented: $choosingCustomSpeed, arrowEdge: .bottom) {
            HStack(spacing: 6) {
                Text("Speed")
                PlaybackSpeedField().frame(width: 60)
                Text("stitches/s")
            }
            .font(Theme.body(12)).foregroundStyle(Theme.ink).padding(12)
        }
    }
    private var secondaryInk: Color { Theme.toolBandInkSecondary }   // the tool band has its own ink colors
    /// One button per preset speed.
    private func buttons(_ presets: [Double]) -> some View {
        ForEach(Array(presets.enumerated()), id: \.offset) { _, speed in
            let on = preferences.playbackSpeed == speed
            Button { preferences.playbackSpeed = speed } label: {
                // In the narrow rail the buttons get less padding and may shrink a little, so "2,000" fits whole.
                Text(Int(speed).formatted())
                    .font(Theme.body(11, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, stacked ? 3 : 6).frame(height: 20)
                    .background(Capsule().fill(on ? Theme.accent : Color.clear))
                    .foregroundStyle(on ? Theme.onAccent : secondaryInk)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Sew at \(Int(speed).formatted()) stitches per second. A machine sews about 12. Right-click for another speed.")
            .accessibilityLabel("\(Int(speed).formatted()) stitches per second")
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}
