// The Monogram dialog: type one to three initials, pick a font, layout, ornaments and border, see the
// monogram as you go, then add it (or, when editing, rebuild it in place).
import AppKit
import SwiftUI
import EmbroideryCore

extension GuidedDialog {
    /// The choices used last, so the next monogram starts from them.
    static var lastMonogram: MonogramSpec?
    /// Classic monogram typefaces that come with macOS, offered after the embroidery fonts (those not installed are
    /// left out). They're converted to fills.
    static let monogramMacFonts = ["Didot-Bold", "Baskerville-Bold", "Georgia-Bold", "BodoniSvtyTwoITCTT-Bold", "SnellRoundhand-Bold", "Copperplate-Bold"]
        .filter { NSFont(name: $0, size: 12) != nil }
    /// The Monogram dialog: returns the recipe, or nil if the person cancelled. `editing` is a monogram's recipe to
    /// change (its identity and placement are kept).
    static func monogram(color: ThreadColor, editing: MonogramSpec? = nil) -> MonogramSpec? {
        let fallback = EmbroideryFontLibrary.fonts.first.map { MonogramSpec(initials: "ABC", fontKind: .embroidery, font: $0.folder.lastPathComponent, height: min(25, $0.heights.upperBound)) }
            ?? MonogramSpec(initials: "ABC", fontKind: .system, font: monogramMacFonts.first ?? "Helvetica-Bold")
        var start = editing ?? lastMonogram ?? fallback
        if editing == nil { start.id = UUID(); start.anchor = Point(0, 0); start.alongMarker = Point(10, 0); start.upMarker = Point(0, 10) }
        var made: MonogramSpec?   // the dialog's closure writes the recipe here before it closes
        let confirmed = run(width: 820) { finish in
            MonogramView(spec: start, color: color, editing: editing != nil) { spec in
                if let spec, editing == nil { lastMonogram = spec }
                made = spec; finish(spec != nil)
            }
        }
        return confirmed ? made : nil
    }
}

struct MonogramView: View {
    @State var spec: MonogramSpec
    let color: ThreadColor
    let editing: Bool
    /// Called with the recipe (nil for Cancel).
    let done: (MonogramSpec?) -> Void
    /// The latest preview and its notes, or a problem; nil while it's being worked out.
    @State private var built: Result<(objects: [RunObject], notes: [String]), Error>?

    /// The fonts to choose from, as "embroidery:folder" or "system:PostScript name".
    private var fontChoice: Binding<String> {
        Binding(get: { "\(spec.fontKind.rawValue):\(spec.font)" }, set: { value in
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            spec.fontKind = parts[0] == "embroidery" ? .embroidery : .system; spec.font = parts[1]
            if spec.fontKind == .embroidery, let font = EmbroideryFontLibrary.font(spec.font), !font.heights.contains(spec.height) { spec.height = min(max(spec.height, max(8, font.heights.lowerBound)), font.heights.upperBound) }
        })
    }

    var body: some View {
        DialogFrame(eyebrow: "Monogram", title: editing ? "Edit the monogram" : "Add a monogram",
                    subtitle: "One to three initials in a classic layout, with ornaments either side and a satin border if you like. Double-click it later to change anything.",
                    primary: editing ? "Update Monogram" : "Add Monogram",
                    finish: { add in if !add { done(nil) } else if case .success? = built { done(spec) } }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Initials").font(Theme.body(13, weight: .semibold))
                        TextField("ABC", text: Binding(get: { spec.initials }, set: { spec.initials = String($0.prefix(3)) }))
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                    Picker("Font", selection: fontChoice) {
                        if !EmbroideryFontLibrary.fonts.isEmpty {
                            Section("Embroidery fonts") { ForEach(EmbroideryFontLibrary.fonts, id: \.folder) { Text($0.name).tag("embroidery:\($0.folder.lastPathComponent)") } }
                        }
                        Section("Mac fonts · converted to fill") {
                            ForEach(GuidedDialog.monogramMacFonts, id: \.self) { name in Text(NSFont(name: name, size: 12)?.displayName ?? name).tag("system:\(name)") }
                        }
                    }.font(Theme.body(13, weight: .semibold))
                    Stepper(value: $spec.height, in: MonogramSpec.heights, step: 1) {
                        Text("Height: \(Preferences.shared.unit.short(spec.height))").font(Theme.body(13, weight: .semibold))
                    }
                    Picker("Layout", selection: $spec.layout) { ForEach(MonogramLayout.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .font(Theme.body(13, weight: .semibold))
                    Picker("Ornaments", selection: $spec.ornament) { ForEach(MonogramOrnament.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .font(Theme.body(13, weight: .semibold))
                    Picker("Border", selection: $spec.border) { ForEach(MonogramBorder.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .font(Theme.body(13, weight: .semibold))
                    if spec.border != .none {
                        Stepper(value: $spec.borderWidth, in: MonogramSpec.borderWidths, step: 0.5) {
                            Text("Border width: \(spec.borderWidth.formatted()) mm").font(Theme.body(13, weight: .semibold))
                        }
                        Stepper(value: $spec.borderGap, in: MonogramSpec.borderGaps, step: 0.5) {
                            Text("Gap: \(Preferences.shared.unit.short(spec.borderGap))").font(Theme.body(13, weight: .semibold))
                        }
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: color.nsColor)).frame(width: 12, height: 12)
                        Text("Sews in \(color.name), the current thread.").foregroundStyle(Theme.inkSecondary)
                    }.font(Theme.body(12))
                }.frame(width: 300, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        Theme.ground
                        switch built {
                        case .success(let made)?: StitchThumbnail(objects: made.objects, label: "Preview of the monogram")
                        case .failure(let error)?: Text(error.localizedDescription).font(Theme.body(12)).foregroundStyle(.orange).padding()
                        case nil: ProgressView().controlSize(.small)
                        }
                    }.frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 14))
                    if case .success(let made)? = built, !made.notes.isEmpty { NotesList(title: "Notes", notes: made.notes) }
                }
            }
        }
        // Rebuild the preview in the background whenever a choice changes.
        .task(id: spec) {
            built = nil
            let spec = spec, color = color
            let result = await Task.detached(priority: .userInitiated) { Result { try spec.build(color: color, embroideryFonts: EmbroideryFontLibrary.fonts) } }.value
            if !Task.isCancelled { built = result }
        }
    }
}
