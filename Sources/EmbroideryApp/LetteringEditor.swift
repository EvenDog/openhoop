// The Lettering section of Properties: a selected word's text, font, height, letter spacing and baseline, changed
// right there (the letters rebuild as you go, each change one undoable step), like other digitizing software's
// lettering properties. Shared by the Guided and Pro layouts.
import SwiftUI
import AppKit
import EmbroideryCore

extension InspectorPanel {
    @ViewBuilder func letteringEditor(_ spec: LetteringSpec) -> some View {
        let objects = state.design.letteringObjects(spec.id)
        let embroideryFont = spec.fontKind == .embroidery ? EmbroideryFontLibrary.font(spec.font) : nil
        VStack(alignment: .leading, spacing: pro ? 6 : 8) {
            Label("Lettering", systemImage: CommandID.lettering.symbol).font(Theme.body(pro ? 11 : 13, weight: .semibold))
            LetteringTextBox(spec: spec, pro: pro) { text in
                var next = spec; next.text = text
                state.rebuildLettering(next, action: "Edit Text")
            }
            HStack {
                Text("Font").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
                Picker("Font", selection: letteringFont(spec)) {
                    if !EmbroideryFontLibrary.fonts.isEmpty {
                        Section("Embroidery fonts") {
                            ForEach(EmbroideryFontLibrary.fonts, id: \.folder) { font in Text(font.name).tag(LetteringView.FontChoice.embroidery(font.folder.lastPathComponent)) }
                        }
                    }
                    Section("Mac fonts") {
                        ForEach(Self.fontFamilies, id: \.self) { family in Text(family).tag(LetteringView.FontChoice.system(family)) }
                    }
                }.labelsHidden().frame(width: pro ? 130 : 150)
            }
            .help("Embroidery fonts are hand-digitized satin lettering; Mac fonts are converted to fill or outline.")
            if let embroideryFont, let image = NSImage(contentsOf: embroideryFont.folder.appendingPathComponent("preview.png")) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: pro ? 16 : 20, alignment: .leading)
            }
            if spec.fontKind == .system {
                let family = NSFont(name: spec.font, size: 12)?.familyName ?? spec.font
                HStack {
                    Text("Style").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
                    Picker("Style", selection: Binding(get: { spec.font }, set: { name in var next = spec; next.font = name; state.rebuildLettering(next, action: "Font Style") })) {
                        ForEach(Self.fontStyles(of: family), id: \.name) { Text($0.title).tag($0.name) }
                    }.labelsHidden().frame(width: pro ? 130 : 150)
                }
                HStack {
                    Text("Stitch").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)); Spacer()
                    Picker("Stitch", selection: Binding(get: { spec.stitch }, set: { stitch in var next = spec; next.stitch = stitch; state.rebuildLettering(next, action: "Lettering Stitch") })) {
                        ForEach(LetteringStitch.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: pro ? 130 : 150)
                }
            }
            number("Height", value: spec.currentHeight, range: embroideryFont?.heights ?? Lettering.heights, length: true,
                   help: embroideryFont.map { "This font is digitized for letters \(preferences.unit.short($0.heights.lowerBound))–\(preferences.unit.short($0.heights.upperBound)) tall." } ?? "How tall the capital letters are.") { height in
                var next = spec; next.height = height
                state.rebuildLettering(next, action: "Letter Height")
            }
            number("Letter spacing", value: spec.letterSpacing ?? 0, range: LetteringSpec.letterSpacings,
                   help: "Extra space between letters in mm, on top of the font's own spacing (negative pulls them closer).") { spacing in
                var next = spec; next.letterSpacing = abs(spacing) < 0.005 ? nil : spacing
                state.rebuildLettering(next, action: "Letter Spacing")
            }
            HStack {
                Text("Baseline").font(Theme.body(pro ? 11 : 12, weight: pro ? .regular : .semibold)).fixedSize(); Spacer()
                Picker("Baseline", selection: Binding(get: { spec.shape }, set: { shape in var next = spec; next.shape = shape; state.rebuildLettering(next, action: "Lettering Baseline") })) {
                    // On a line shows only while the lettering is on one (Put Lettering on Line puts it there).
                    ForEach(LetteringShape.pickable + (spec.shape == .onLine ? [.onLine] : []), id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if spec.shape == .onLine { explain("The letters sit along the dashed line. Reshape it with Edit Nodes and they follow; choose Straight or an arch to take them off it.") }
            if spec.shape.isArch {
                number("Arc radius", value: spec.radius, range: Lettering.radii, length: true, help: "The circle the letters follow. Smaller is more curved.") { radius in
                    var next = spec; next.radius = radius
                    state.rebuildLettering(next, action: "Arc Radius")
                }
            }
            if !(spec.letterOffsets ?? [:]).isEmpty {
                Button("Reset letter positions") { var next = spec; next.letterOffsets = nil; state.rebuildLettering(next, action: "Reset Letter Positions") }
                    .buttonStyle(ThemedButtonStyle()).help("Put every letter you moved with Edit Nodes back where the font places it")
            }
            if !spec.matchesFreshBuild(objects, embroideryFonts: EmbroideryFontLibrary.fonts) {
                explain("Some letters were changed by hand. Changing these settings rebuilds every letter from the font, which replaces those changes.")
            }
            if !pro { explain("With \(preferences.key(.nodeTool)) (Edit Nodes), drag a letter's handle to move just that letter; it stays put when you change the settings above.") }
            HStack {
                Button(pro ? "More…" : "More options…") { AppDelegate.shared.perform(.editLettering) }.buttonStyle(ThemedButtonStyle())
                    .help("Alignment and line spacing for several lines, with a preview (\(preferences.label(.editLettering)))")
                Button("Break apart") { AppDelegate.shared.perform(.breakApartLettering) }.buttonStyle(ThemedButtonStyle())
                    .help(preferences.hint(.breakApartLettering))
            }
        }
    }

    /// The font menu's choice for `spec`, and switching font: an embroidery font keeps the height if it's digitized
    /// for it (otherwise its own size), a Mac font gets its Bold style if it has one.
    private func letteringFont(_ spec: LetteringSpec) -> Binding<LetteringView.FontChoice> {
        Binding(get: {
            spec.fontKind == .embroidery ? .embroidery(spec.font) : .system(NSFont(name: spec.font, size: 12)?.familyName ?? spec.font)
        }, set: { choice in
            var next = spec
            switch choice {
            case .embroidery(let folder):
                next.fontKind = .embroidery; next.font = folder
                if let font = EmbroideryFontLibrary.font(folder), !font.heights.contains(next.height) {
                    next.height = (min(max(font.size, font.heights.lowerBound), font.heights.upperBound) * 10).rounded() / 10
                }
            case .system(let family):
                let styles = Self.fontStyles(of: family)
                guard let style = (styles.first { $0.title == "Bold" } ?? styles.first)?.name else { return }
                next.fontKind = .system; next.font = style
                next.height = min(max(next.height, Lettering.heights.lowerBound), Lettering.heights.upperBound)
            }
            state.rebuildLettering(next, action: "Lettering Font")
        })
    }

    /// Font families installed on this Mac (names starting with "." are hidden system fonts).
    static var fontFamilies: [String] { NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") } }
    /// The styles in a font family as (PostScript name, style name) pairs, such as ("AvenirNext-Bold", "Bold").
    static func fontStyles(of family: String) -> [(name: String, title: String)] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard member.count > 1, let name = member[0] as? String, let title = member[1] as? String else { return nil }
            return (name, title)
        }
    }
}

/// The lettering's text, editable in place. The letters rebuild when you pause typing (or press Return), and the
/// box follows the lettering when it changes some other way, such as Undo.
struct LetteringTextBox: View {
    let spec: LetteringSpec
    let pro: Bool
    let commit: (String) -> Void
    @State private var text = ""
    @State private var pending: DispatchWorkItem?
    @FocusState private var editing: Bool
    var body: some View {
        TextField("Text", text: $text, axis: .vertical)
            .lineLimit(1...4).textFieldStyle(.roundedBorder).font(Theme.body(pro ? 12 : 13))
            .focused($editing)
            .onAppear { text = spec.text }
            .onChange(of: spec.text) { _, new in if !editing || pending == nil { text = new } }
            .onChange(of: text) { _, new in
                guard new != spec.text else { return }
                pending?.cancel()
                // A short pause after the last key, so each word typed rebuilds once instead of every letter.
                let work = DispatchWorkItem { pending = nil; if !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { commit(new) } }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
            }
            .help("The lettering's text. Press Option-Return for a new line.")
    }
}
