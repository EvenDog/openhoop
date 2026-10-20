// What the picture menus in Properties (Fill style, a tatami fill's Pattern) share: the button that opens one, and
// trying a choice out on the canvas. While the pointer is over a choice, the selected objects are stitched with it and
// drawn in place of their own stitches; nothing in the design changes until the choice is clicked.
import SwiftUI
import EmbroideryCore

/// The selected objects' stitches with a choice tried out, which the canvas draws in place of theirs. `choice` names
/// it (say "style:contour"). `kept` once it has been chosen, until the design's own stitches catch up.
struct SettingsPreview {
    let choice: String
    let objects: Set<UUID>
    let plan: StitchPlan
    var kept = false
}

extension EditorState {
    /// Shows the selected objects that `applies` to on the canvas as they'd be with `change` made to their settings,
    /// or stops showing a preview (nil `choice`). Only objects the change would alter are tried. Their stitches are
    /// worked out in the background on their own, apart from the rest of the design, so a big design doesn't slow the
    /// preview down.
    func previewSettings(_ choice: String?, applies: (RunObject) -> Bool = { _ in true }, change: (inout DigitizingSettings) -> Void = { _ in }) {
        settingsPreviewTask?.cancel(); settingsPreviewTask = nil
        let tried = design.objects.compactMap { object -> RunObject? in
            guard choice != nil, selection.contains(object.id), !object.locked, applies(object) else { return nil }
            var settings = object.settings
            change(&settings)
            guard settings != object.settings else { return nil }
            var changed = object
            changed.digitizing = settings
            changed.stitchEdits = nil   // as on the real change: new settings mean fresh stitches
            return changed
        }
        guard let choice, !tried.isEmpty else {
            if settingsPreview?.kept != true { settingsPreview = nil }
            return
        }
        var sample = design
        sample.objects = tried
        let work = Task.detached(priority: .userInitiated) { try RunningEngine.compile(sample) }
        settingsPreviewTask = work
        Task { [weak self] in
            // A choice that can't be sewn (Guided with no guide line) just shows no preview.
            guard let plan = try? await work.value, let self, self.settingsPreviewTask == work else { return }
            self.settingsPreview = SettingsPreview(choice: choice, objects: Set(tried.map(\.id)), plan: plan)
        }
    }
    /// After `choice` is chosen from a menu: keeps its preview on the canvas until the design's fresh stitches are
    /// ready (EditorState.plan clears it), so the old stitches don't flash back in between.
    func keepSettingsPreview(_ choice: String) {
        settingsPreviewTask?.cancel(); settingsPreviewTask = nil
        if settingsPreview?.choice == choice { settingsPreview?.kept = true } else { settingsPreview = nil }
    }
}

/// The face of a picture menu's button: a small picture, the current choice's name and a down arrow, in a rounded
/// box. `compact` is the Pro size.
struct PictureMenuLabel<Picture: View>: View {
    let title: String
    var compact = false
    @ViewBuilder let picture: Picture
    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            picture.frame(width: compact ? 26 : 46, height: compact ? 17 : 30)
            Text(title).font(Theme.body(compact ? 11 : 12, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: compact ? 8 : 9, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
        }
        .padding(compact ? 2 : 4).padding(.trailing, compact ? 4 : 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
        .contentShape(Rectangle())
    }
}

/// The line at the foot of a picture menu: what the canvas shows while the pointer is over `pointedAt`.
func pictureMenuNote(pointedAt: String?, current: String, kind: String) -> some View {
    let text = pointedAt.map { "Your shape shows \($0). Click to keep it; move away to go back to \(current)." } ?? "Point at a \(kind) to see it stitched on your shape."
    return Text(text).font(Theme.body(11)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.ground))
}
