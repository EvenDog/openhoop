// Motifs of your own: the Create Motif dialog, which names the motif made from the selected lines and shows it as a
// motif line and a motif fill, and Settings › New designs › My motifs, where they're renamed or deleted. The motifs
// are kept in Preferences.myMotifs and listed in every Motif menu in Properties.
import SwiftUI
import EmbroideryCore

extension GuidedDialog {
    /// The Create Motif dialog for `motif`, drawn in `color`: returns the name typed, or nil if the person cancelled.
    static func createMotif(_ motif: CustomMotif, color: ThreadColor) -> String? {
        var name: String?
        let confirmed = run(width: 520) { finish in
            CreateMotifView(motif: motif, color: Color(nsColor: color.nsColor)) { typed in name = typed; finish(typed != nil) }
        }
        return confirmed ? name : nil
    }
}

struct CreateMotifView: View {
    let motif: CustomMotif
    let color: Color
    /// Called with the name (nil for Cancel).
    let done: (String?) -> Void
    @State private var name = "My motif"

    /// Settings that sew this motif, for the previews.
    private func settings(_ kind: StitchKind) -> DigitizingSettings {
        var s = DigitizingSettings(kind: kind); s.customMotif = motif
        if kind == .run { s.runStyle = .motif } else { s.fillStyle = .motif; s.angle = 0 }
        return s
    }
    var body: some View {
        DialogFrame(eyebrow: "Create Motif", title: "Make a motif of your own",
                    subtitle: "The selected lines become one motif. Copies join from its left end to its right end. It's saved in My motifs, ready to choose in Properties for any motif line or motif fill.",
                    primary: "Save Motif",
                    finish: { save in done(save && !name.trimmingCharacters(in: .whitespaces).isEmpty ? name : nil) }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Name").font(Theme.body(13, weight: .semibold))
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 240)
                }
                HStack(alignment: .top, spacing: 16) {
                    preview("As a motif line", StitchPreview(kind: .run, color: color, spacing: 0, stitchLength: 2.5, angle: 0, settings: settings(.run)))
                    preview("As a motif fill", StitchPreview(kind: .fill, color: color, spacing: 0, stitchLength: 2.5, angle: 0, fillStyle: .motif, settings: settings(.fill)))
                }
            }
        }
    }
    /// One preview, captioned, on the fabric color.
    private func preview(_ caption: String, _ drawing: StitchPreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            drawing.frame(width: 220, height: 90).background(Theme.ground).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.controlBorder))
        }
    }
}

/// Settings › New designs › My motifs: each motif of your own with a drawing of it, its name and delete.
struct MyMotifsCard: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        SettingsCard(caption: "My motifs") {
            ForEach(Array(preferences.myMotifs.enumerated()), id: \.element.id) { index, motif in
                if index > 0 { RowDivider() }
                MyMotifRow(motif: motif)
            }
            if !preferences.myMotifs.isEmpty { RowDivider() }
            Text("To make a motif, draw it with running lines, select them and choose \(CommandID.createMotif.title) in the Edit menu. Designs keep their own copy of each motif they use, so renaming or deleting one here doesn't change them.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

/// One of your motifs: a drawing of it, its name (saved when you press Return or leave the field), and delete.
private struct MyMotifRow: View {
    let motif: CustomMotif
    @ObservedObject var preferences = Preferences.shared
    @State private var draftName = ""
    @FocusState private var editingName: Bool
    var body: some View {
        HStack(spacing: 10) {
            MotifPicture(stroke: motif.stroke).frame(width: 44, height: 28)
            TextField("Name", text: $draftName).textFieldStyle(.roundedBorder).frame(width: 190)
                .focused($editingName)
                .onSubmit(commitName)
                .onChange(of: editingName) { _, editing in if !editing { commitName() } }
            Spacer(minLength: 12)
            Button { preferences.setMyMotifs(preferences.myMotifs.filter { $0.id != motif.id }) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete this motif. Designs already using it keep their copy.")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onAppear { draftName = motif.name }
    }
    /// Saves the typed name: tidied and made unique, or the old name back if it was left empty.
    private func commitName() {
        let others = preferences.myMotifs.filter { $0.id != motif.id }.map(\.name)
        guard let name = Preferences.uniqueMotifName(draftName, among: others) else { draftName = motif.name; return }
        draftName = name
        guard name != motif.name, let index = preferences.myMotifs.firstIndex(where: { $0.id == motif.id }) else { return }
        var motifs = preferences.myMotifs; motifs[index].name = name; preferences.setMyMotifs(motifs)
    }
}

/// A motif's stroke drawn as a line, scaled to fit the space it's given.
struct MotifPicture: View {
    let stroke: [Point]
    var body: some View {
        Canvas { context, size in
            let xs = stroke.map(\.x), ys = stroke.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
            // One scale for both directions, so the motif keeps its shape; y is flipped because the canvas is y-down.
            let scale = min((size.width - 4) / max(maxX - minX, 1e-6), (size.height - 4) / max(maxY - minY, 1e-6))
            let left = (size.width - (maxX - minX) * scale) / 2, bottom = (size.height + (maxY - minY) * scale) / 2
            var path = Path()
            for (index, p) in stroke.enumerated() {
                let q = CGPoint(x: left + (p.x - minX) * scale, y: bottom - (p.y - minY) * scale)
                if index == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            context.stroke(path, with: .color(Theme.ink), lineWidth: 1.2)
        }
    }
}
