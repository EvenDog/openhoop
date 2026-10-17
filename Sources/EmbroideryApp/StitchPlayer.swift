// The stitch player at the right end of the tool strip: rewind, play or pause, a bar to scrub through the stitches,
// the stitch count, and speed buttons (set in Settings › General). Pro's tool rail down the left shows it stacked at
// the bottom instead.
import SwiftUI
import EmbroideryCore

/// The stitch player as one more captioned group of the tool strip, or stacked for the narrow left rail.
struct StripPlayer: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// True for Pro's left rail: everything in one narrow column.
    var stacked = false
    /// True on Pro's tan tool band, which has its own ink colors; false on Guided's cream strip.
    var onBand = false
    var body: some View {
        let total = state.plan.stitchCount
        let count = Text("\(Int(state.playback * Double(total)).formatted()) / \(total.formatted())")
            .font(Theme.body(10, weight: .semibold)).monospacedDigit().foregroundStyle(secondaryInk).lineLimit(1)
        if stacked {
            VStack(alignment: .leading, spacing: 5) {
                caption
                HStack(spacing: 4) { rewindButton; playButton }
                slider
                count.minimumScaleFactor(0.7)
                SpeedButtons(stacked: true, onBand: onBand)
            }
        } else {
            // Caption and count on top, then the controls, then the speeds: two rows, like the tool groups beside it.
            VStack(alignment: .leading, spacing: 3) {
                HStack { caption; Spacer(minLength: 8); count }
                HStack(spacing: 4) { rewindButton; playButton; slider }
                SpeedButtons(stacked: false, onBand: onBand)
            }
            .frame(width: 250)
        }
    }
    private var secondaryInk: Color { onBand ? Theme.toolBandInkSecondary : Theme.inkSecondary }
    /// The group's caption, in the same type as the tool groups' captions.
    private var caption: some View {
        Text("PLAYER").font(onBand ? .system(size: 9, weight: .bold, design: .rounded) : Theme.caption).tracking(0.8)
            .foregroundStyle(secondaryInk).padding(.leading, 3).lineLimit(1).fixedSize()
    }
    private var rewindButton: some View {
        Button { AppDelegate.shared.perform(.rewind) } label: {
            Image(systemName: "backward.end.fill").font(.system(size: 10)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(secondaryInk)
        .help(preferences.hint(.rewind)).accessibilityLabel("Rewind")
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
    private var slider: some View {
        Slider(value: $state.playback, in: 0...1).controlSize(.small).tint(Theme.accent)
            .help("Drag to step through the design, stitch by stitch. Esc shows the whole design again.")
            .accessibilityLabel("Stitch sequence")
    }
}

/// The speed buttons. The lit one is the speed the player sews at; changing it while playing takes effect at once.
/// A right-click offers a one-off speed of your own, or opens Settings to change the buttons.
private struct SpeedButtons: View {
    /// True for the left rail: the buttons two by two, with the unit below.
    let stacked: Bool
    let onBand: Bool
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
            Button("Change Speed Buttons…") { AppDelegate.shared.perform(.settings) }
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
    private var secondaryInk: Color { onBand ? Theme.toolBandInkSecondary : Theme.inkSecondary }
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
