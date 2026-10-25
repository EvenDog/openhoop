// The Lettering section of Properties: a selected word's text, font, height, letter spacing and baseline, changed
// right there (the letters rebuild as you go, each change one undoable step), like other digitizing software's
// lettering properties. New lettering is made here too: Add Lettering's click puts a word on the hoop and this
// section takes over.
import SwiftUI
import AppKit
import EmbroideryCore

extension InspectorPanel {
    @ViewBuilder func letteringEditor(_ spec: LetteringSpec) -> some View {
        let objects = state.design.letteringObjects(spec.id)
        let embroideryFont = spec.fontKind == .embroidery ? EmbroideryFontLibrary.font(spec.font) : nil
        VStack(alignment: .leading, spacing: 6) {
            Label("Lettering", systemImage: CommandID.lettering.symbol).font(Theme.body(11, weight: .semibold))
            LetteringTextBox(spec: spec, focusRequested: state.letteringTextFocusRequested,
                             focused: { state.letteringTextFocusRequested = false }) { text in
                var next = spec; next.text = text
                state.rebuildLettering(next, action: "Edit Text")
            }
            HStack {
                Text("Font").font(Theme.body(11, weight: .regular)); Spacer()
            }
            LetteringFontList(spec: spec, color: objects.first?.color ?? state.currentColor) { choice in
                // Fonts tried one after another on this lettering undo as one step.
                state.rebuildLettering(Self.spec(spec, withFont: choice), action: "Lettering Font", run: "font \(spec.id)")
            }
            .help("Embroidery fonts are hand-digitized satin lettering; Mac fonts are converted to fill or outline.")
            if spec.fontKind == .system {
                let family = NSFont(name: spec.font, size: 12)?.familyName ?? spec.font
                HStack {
                    Text("Style").font(Theme.body(11, weight: .regular)); Spacer()
                    Picker("Style", selection: Binding(get: { spec.font }, set: { name in var next = spec; next.font = name; state.rebuildLettering(next, action: "Font Style") })) {
                        ForEach(Self.fontStyles(of: family), id: \.name) { Text($0.title).tag($0.name) }
                    }.labelsHidden().frame(width: 130)
                }
                HStack {
                    Text("Stitch").font(Theme.body(11, weight: .regular)); Spacer()
                    Picker("Stitch", selection: Binding(get: { spec.stitch }, set: { stitch in var next = spec; next.stitch = stitch; state.rebuildLettering(next, action: "Lettering Stitch") })) {
                        ForEach(LetteringStitch.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
                }
            }
            number("Height", value: spec.currentHeight, range: embroideryFont?.heights ?? Lettering.heights, length: true,
                   help: embroideryFont.map { "This font is digitized for letters \(preferences.unit.short($0.heights.lowerBound))–\(preferences.unit.short($0.heights.upperBound)) tall." } ?? "How tall the capital letters are.") { height in
                var next = spec; next.height = height
                state.rebuildLettering(next, action: "Letter Height")
            }
            HStack {
                Text("Between letters").font(Theme.body(11, weight: .regular)); Spacer()
                Picker("Between letters", selection: Binding(get: { spec.betweenLetters ?? .whenFar }, set: { choice in
                    var next = spec; next.betweenLetters = choice == .whenFar ? nil : choice
                    state.rebuildLettering(next, action: "Between Letters")
                })) {
                    ForEach(LetterConnector.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            .help("How the needle gets from one letter (or part of a letter) to the next. Trim when far keeps the font's own trims; Jump never trims; Run sews running stitches that the next letter covers, with no trims or ties.")
            number("Letter spacing", value: spec.letterSpacing ?? 0, range: LetteringSpec.letterSpacings,
                   help: "Extra space between letters in mm, on top of the font's own spacing (negative pulls them closer).") { spacing in
                var next = spec; next.letterSpacing = abs(spacing) < 0.005 ? nil : spacing
                state.rebuildLettering(next, action: "Letter Spacing")
            }
            if spec.lines.count > 1 {
                HStack {
                    Text("Lines").font(Theme.body(11, weight: .regular)); Spacer()
                    Picker("Lines", selection: Binding(get: { spec.alignment ?? .center }, set: { alignment in var next = spec; next.alignment = alignment; state.rebuildLettering(next, action: "Line Alignment") })) {
                        ForEach(LetteringAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                number("Line spacing", value: spec.lineSpacing ?? LetteringSpec.defaultLineSpacing, range: LetteringSpec.lineSpacings,
                       help: "From one line's baseline to the next, in letter heights (1.4 leaves a little room between lines).") { spacing in
                    var next = spec; next.lineSpacing = spacing
                    state.rebuildLettering(next, action: "Line Spacing")
                }
            }
            HStack {
                Text("Baseline").font(Theme.body(11, weight: .regular)).fixedSize(); Spacer()
                Picker("Baseline", selection: Binding(get: { spec.shape }, set: { shape in var next = spec; next.shape = shape; state.rebuildLettering(next, action: "Lettering Baseline") })) {
                    // On a line shows only while the lettering is on one (Put Lettering on Line puts it there).
                    ForEach(LetteringShape.pickable + (spec.shape == .onLine ? [.onLine] : []), id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if spec.shape == .straight {
                HStack {
                    Text("Envelope").font(Theme.body(11, weight: .regular)).fixedSize(); Spacer()
                    Picker("Envelope", selection: Binding(get: { spec.envelope?.kind }, set: { kind in
                        var next = spec; next.envelope = kind.map { LetteringEnvelope(kind: $0) }
                        state.rebuildLettering(next, action: "Lettering Envelope")
                    })) {
                        Text("None").tag(EnvelopeKind?.none)
                        ForEach(EnvelopeKind.allCases, id: \.self) { Text($0.title).tag(EnvelopeKind?.some($0)) }
                    }.labelsHidden().frame(width: 130)
                }
                .help("Bend the whole word into a shape: Bridge curves it, Pennant tapers it, Perspective leans it, Diamond brings it to a point")
                if let envelope = spec.envelope {
                    // Each handle's move, in mm (kept as a share of the letter height, so it grows with the letters).
                    let reach = LetteringEnvelope.moves.lowerBound * spec.height...LetteringEnvelope.moves.upperBound * spec.height
                    ForEach(envelope.kind.handles, id: \.self) { handle in
                        number(handle.title, value: (envelope.move(handle) * spec.height * 100).rounded() / 100, range: reach, length: true,
                               help: envelope.kind.slides ? "How far this corner slides right (negative: left)" : "How far this handle moves up (negative: down)") { amount in
                            var next = spec; next.envelope?.setMove(handle, amount / spec.height)
                            state.rebuildLettering(next, action: "Shape Envelope")
                        }
                    }
                    Text("Or drag its handles with Edit Nodes (\(preferences.key(.nodeTool))): Shift bends the \(envelope.kind.slides ? "other end" : "opposite edge") the other way, ⌘ the same way.")
                        .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
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
            HStack {
                Button("Break apart") { AppDelegate.shared.perform(.breakApartLettering) }.buttonStyle(ThemedButtonStyle())
                    .help(preferences.hint(.breakApartLettering))
                if spec.fontKind == .embroidery {
                    Button("Font credits…") { showFontCredits = true }.buttonStyle(ThemedButtonStyle())
                        .help("Who made each embroidery font, and its license")
                        .popover(isPresented: $showFontCredits, arrowEdge: .leading) { FontCreditsView() }
                }
            }
        }
    }

    /// `spec` switched to another font: an embroidery font keeps the height if it's digitized for it (otherwise it
    /// takes its own size), a Mac font gets its Bold style if it has one.
    static func spec(_ spec: LetteringSpec, withFont choice: LetteringFontChoice) -> LetteringSpec {
        var next = spec
        switch choice {
        case .embroidery(let folder):
            next.fontKind = .embroidery; next.font = folder
            if let font = EmbroideryFontLibrary.font(folder), !font.heights.contains(next.height) {
                next.height = (min(max(font.size, font.heights.lowerBound), font.heights.upperBound) * 10).rounded() / 10
            }
        case .system(let family):
            let styles = fontStyles(of: family)
            guard let style = (styles.first { $0.title == "Bold" } ?? styles.first)?.name else { return spec }
            next.fontKind = .system; next.font = style
            next.height = min(max(next.height, Lettering.heights.lowerBound), Lettering.heights.upperBound)
        }
        return next
    }
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
    /// True when the box should take the keyboard (new lettering, or Edit Lettering); `focused` is called once it has.
    var focusRequested = false
    var focused: () -> Void = {}
    let commit: (String) -> Void
    @State private var text = ""
    @State private var pending: DispatchWorkItem?
    @FocusState private var editing: Bool
    var body: some View {
        TextField("Text", text: $text, axis: .vertical)
            .lineLimit(1...4).textFieldStyle(.roundedBorder).font(Theme.body(12))
            .focused($editing)
            .onAppear { text = spec.text; if focusRequested { takeFocus() } }
            .onChange(of: focusRequested) { _, requested in if requested { takeFocus() } }
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
    /// Puts the keyboard here with the text selected, so typing replaces it. (SwiftUI can't select a text box's
    /// text on macOS 14, so this sends the standard Select All once the box has the keyboard.)
    private func takeFocus() {
        focused()
        DispatchQueue.main.async {
            editing = true
            DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
        }
    }
}

/// One choice in the font list: an embroidery font (by folder name) or a Mac font family.
enum LetteringFontChoice: Hashable {
    case embroidery(String), system(String)
    init(_ spec: LetteringSpec) {
        self = spec.fontKind == .embroidery ? .embroidery(spec.font) : .system(NSFont(name: spec.font, size: 12)?.familyName ?? spec.font)
    }
}

/// The font list in Properties: the embroidery fonts, then the Mac fonts, each row showing the lettering's own
/// words in that font. Click a row to switch; while the list has the keyboard, ↑ ↓ move to the next font and
/// the lettering on the hoop changes with it. It's OpenHoop's own list (not a Mac List) so the chosen font gets
/// the app's soft denim highlight, which keeps its words readable.
struct LetteringFontList: View {
    let spec: LetteringSpec
    let color: ThreadColor
    let choose: (LetteringFontChoice) -> Void
    @ObservedObject private var preferences = Preferences.shared
    @FocusState private var hasKeyboard: Bool
    /// Font families installed on this Mac (names starting with "." are hidden system fonts), read once.
    static let macFamilies = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
    /// Every font in list order, for moving up and down with the arrow keys.
    static let order = EmbroideryFontLibrary.fonts.map { LetteringFontChoice.embroidery($0.folder.lastPathComponent) } + macFamilies.map { .system($0) }

    var body: some View {
        let current = LetteringFontChoice(spec)
        // The first line, cut short so it fits a row.
        let sample = String((spec.lines.first ?? spec.text).prefix(16))
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy: only the rows scrolled into view are drawn (a Mac can have hundreds of fonts).
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                    if !EmbroideryFontLibrary.fonts.isEmpty {
                        Section {
                            ForEach(EmbroideryFontLibrary.fonts, id: \.folder) { font in
                                row(.embroidery(font.folder.lastPathComponent), current: current) { embroideryRow(font, sample: sample) }
                            }
                        } header: { heading("Embroidery fonts · satin") }
                    }
                    Section {
                        ForEach(Self.macFamilies, id: \.self) { family in
                            row(.system(family), current: current) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sample).font(.custom(family, size: 15)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Text(family).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                                }
                            }
                        }
                    } header: { heading("Mac fonts · fill or outline") }
                }
                .padding(4)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // The outline turns denim while the list has the keyboard, so it's clear the arrow keys will work.
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hasKeyboard ? Theme.accent : Theme.controlBorder, lineWidth: hasKeyboard ? 2 : 1))
            .focusable().focused($hasKeyboard).focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1, from: current, proxy); return .handled }
            .onKeyPress(.upArrow) { step(-1, from: current, proxy); return .handled }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
    }

    /// Moves `by` rows from `current` (staying within the list) and scrolls just enough to show the new font.
    private func step(_ by: Int, from current: LetteringFontChoice, _ proxy: ScrollViewProxy) {
        guard let index = Self.order.firstIndex(of: current) else { return }
        let next = Self.order[min(max(index + by, 0), Self.order.count - 1)]
        guard next != current else { return }
        choose(next)
        proxy.scrollTo(next)
    }

    /// One clickable row; the chosen font has a pale denim background and a denim outline.
    private func row<Content: View>(_ choice: LetteringFontChoice, current: LetteringFontChoice, @ViewBuilder _ content: () -> Content) -> some View {
        let chosen = choice == current
        return Button {
            hasKeyboard = true   // so ↑ ↓ work straight after clicking
            if !chosen { choose(choice) }
        } label: {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(chosen ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(chosen ? Theme.accent : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(choice)
    }

    /// A section heading. It stays at the top while its fonts scroll under it, so it has a solid background.
    private func heading(_ title: String) -> some View {
        Text(title.uppercased()).font(Theme.caption).tracking(0.6).foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
    }
    /// A row for an embroidery font: the words drawn in its satin letters, then its name and the heights it's
    /// digitized for. A font missing some of the letters shows just its name.
    private func embroideryRow(_ font: EmbroideryFont, sample: String) -> some View {
        let objects = FontSamples.objects(font, text: sample, color: color)
        let rowHeight: Double = 18
        return VStack(alignment: .leading, spacing: 2) {
            if let aspect = FontSamples.aspect(objects) {
                StitchThumbnail(objects: objects, label: "\(sample) in \(font.name)", padding: 1, onFabric: false)
                    .frame(width: min(rowHeight * aspect, 170), height: rowHeight)
            }
            Text("\(font.name) · \(preferences.unit.short(font.heights.lowerBound))–\(preferences.unit.short(font.heights.upperBound))")
                .font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
        }
    }
}

/// The font list's sample words in each embroidery font, built once per font, text and thread color (building
/// them on every redraw would slow the panel down).
@MainActor enum FontSamples {
    private static var built: [String: [RunObject]] = [:]
    static func objects(_ font: EmbroideryFont, text: String, color: ThreadColor) -> [RunObject] {
        let key = "\(font.folder.lastPathComponent)\n\(color.hex)\n\(text)"
        if let objects = built[key] { return objects }
        if built.count > 400 { built.removeAll() }   // keeps the memory used small after lots of typing
        let height = min(max(font.size, font.heights.lowerBound), font.heights.upperBound)
        let spec = LetteringSpec(text: text, fontKind: .embroidery, font: font.folder.lastPathComponent, height: height)
        let objects = (try? spec.build(color: color, embroideryFonts: [font]))?.objects ?? []
        built[key] = objects
        return objects
    }
    /// Width over height of the drawn words, or nil when there's nothing to draw.
    static func aspect(_ objects: [RunObject]) -> Double? {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxY > minY else { return nil }
        return (maxX - minX) / (maxY - minY)
    }
}

/// What new lettering starts as: the text, font, size, stitch and shape used last, kept until the app quits.
@MainActor enum LetteringDefaults {
    private static var last = LetteringSpec(text: "Your Text", fontKind: .embroidery, font: "small_font", height: 8)
    /// Keeps `spec`'s choices for the next lettering (not its place, moved letters, start and end, or line).
    static func remember(_ spec: LetteringSpec) {
        var kept = LetteringSpec(text: spec.text, fontKind: spec.fontKind, font: spec.font, stitch: spec.stitch, height: spec.height,
                                 shape: spec.shape == .onLine ? .straight : spec.shape, radius: spec.radius)
        kept.letterSpacing = spec.letterSpacing; kept.alignment = spec.alignment; kept.lineSpacing = spec.lineSpacing; kept.betweenLetters = spec.betweenLetters
        last = kept
    }
    /// A new recipe (with its own id) for the next lettering, in a font this Mac has.
    static func next() -> LetteringSpec {
        var spec = last; spec.id = UUID()
        if spec.fontKind == .embroidery && EmbroideryFontLibrary.font(spec.font) == nil {
            if let font = EmbroideryFontLibrary.fonts.first {
                spec.font = font.folder.lastPathComponent
                spec.height = min(max(spec.height, font.heights.lowerBound), font.heights.upperBound)
            } else { spec.fontKind = .system; spec.font = "Helvetica-Bold" }
        }
        if spec.fontKind == .system && NSFont(name: spec.font, size: 12) == nil { spec.font = "Helvetica-Bold" }
        return spec
    }
}
