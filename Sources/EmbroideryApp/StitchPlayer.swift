// The stitch player in the title bar: rewind, play or pause, a bar to scrub through the stitches, the stitch count,
// and speed buttons (set in Settings › General). It always controls the design tab on screen.
import AppKit
import SwiftUI
import EmbroideryCore

/// Which design the title-bar player controls. The window points it at the design tab on screen.
@MainActor final class StitchPlayerModel: ObservableObject {
    @Published var state: EditorState?
}

/// The title-bar player, in one rounded pill. It's empty only for the moment a window has no design tab.
struct ToolbarPlayer: View {
    @ObservedObject var model: StitchPlayerModel
    var body: some View {
        if let state = model.state { PlayerControls(state: state) }
    }
}

private struct PlayerControls: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        let total = state.plan.stitchCount
        HStack(spacing: 6) {
            Button { AppDelegate.shared.perform(.rewind) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 10)).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
            .help(preferences.hint(.rewind)).accessibilityLabel("Rewind")
            Button { AppDelegate.shared.perform(.play) } label: {
                Image(systemName: state.playing ? "pause.fill" : "play.fill").font(.system(size: 9))
                    .frame(width: 22, height: 22).background(Circle().fill(Theme.accent)).foregroundStyle(Theme.onAccent)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(state.playing ? "Pause  \(preferences.label(.play))" : preferences.hint(.play))
            .accessibilityLabel(state.playing ? "Pause" : "Play")
            Slider(value: $state.playback, in: 0...1).controlSize(.small).tint(Theme.accent).frame(width: 140)
                .help("Drag to step through the design, stitch by stitch. Esc shows the whole design again.")
                .accessibilityLabel("Stitch sequence")
            // A fixed width, so the pill doesn't change size as the count goes up.
            Text("\(Int(state.playback * Double(total)).formatted()) / \(total.formatted())")
                .font(Theme.body(11, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                .lineLimit(1).frame(width: 92, alignment: .leading)
            Rectangle().fill(Theme.controlBorder).frame(width: 1, height: 16)
            SpeedButtons()
        }
        .padding(.leading, 4).padding(.trailing, 10).frame(height: 30)
        .background(Capsule().fill(Theme.divider))
    }
}

/// The speed buttons. The lit one is the speed the player sews at; changing it while playing takes effect at once.
/// A right-click offers a one-off speed of your own, or opens Settings to change the buttons.
private struct SpeedButtons: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var choosingCustomSpeed = false
    var body: some View {
        let presets = preferences.speedPresets
        // A speed typed in Custom Speed… that isn't one of the buttons shows next to "st/s" instead.
        let custom = !presets.contains(preferences.playbackSpeed)
        HStack(spacing: 2) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, speed in
                let on = preferences.playbackSpeed == speed
                Button { preferences.playbackSpeed = speed } label: {
                    Text(Int(speed).formatted())
                        .font(Theme.body(11, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 6).frame(height: 20)
                        .background(Capsule().fill(on ? Theme.accent : Color.clear))
                        .foregroundStyle(on ? Theme.onAccent : Theme.inkSecondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Sew at \(Int(speed).formatted()) stitches per second. A machine sews about 12. Right-click for another speed.")
                .accessibilityLabel("\(Int(speed).formatted()) stitches per second")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Text(custom ? "\(Int(preferences.playbackSpeed).formatted()) st/s" : "st/s")
                .font(Theme.body(11, weight: custom ? .bold : .regular))
                .foregroundStyle(custom ? Theme.accent : Theme.inkSecondary)
                .padding(.leading, 3)
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
}

extension NSToolbarItem.Identifier {
    /// The stitch player in the title bar.
    static let stitchPlayer = NSToolbarItem.Identifier("stitchPlayer")
}
