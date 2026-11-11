// The Monogram section of Properties: a selected monogram's initials, height and font, and its layout, ornaments
// and border as pictures, each drawn with the monogram's own initials. Every change rebuilds the monogram on the
// hoop straight away, as one step you can undo. Add Monogram puts a new one in the middle of the hoop and this
// section takes over.
import SwiftUI
import AppKit
import EmbroideryCore

extension InspectorPanel {
    @ViewBuilder func monogramEditor(_ monogram: MonogramSpec) -> some View {
        // A monogram resized with its handles is rebuilt at the size it is now (asResized), so it doesn't jump back.
        let spec = monogram.asResized
        let color = state.design.monogramObjects(spec.id).first?.color ?? state.currentColor
        let embroideryFont = spec.fontKind == .embroidery ? EmbroideryFontLibrary.font(spec.font) : nil
        VStack(alignment: .leading, spacing: 6) {
            Label { Text("Monogram") } icon: { Image.symbol(CommandID.addMonogram.symbol, size: 13) }.font(Theme.body(11, weight: .semibold))
            HStack {
                Text("Initials").font(Theme.body(11, weight: .regular)); Spacer()
                // Initials typed in a row undo as one step.
                MonogramInitialsBox(initials: spec.initials, focusRequested: state.monogramInitialsFocusRequested,
                                    focused: { state.monogramInitialsFocusRequested = false }) { initials in
                    var next = spec; next.initials = initials
                    state.rebuildMonogram(next, action: "Monogram Initials", run: "initials \(spec.id)")
                }
            }
            number("Height", value: spec.height, range: MonogramSpec.heights, length: true,
                   help: embroideryFont.map { "The tallest initial. This font is digitized for letters \(preferences.unit.short($0.heights.lowerBound))–\(preferences.unit.short($0.heights.upperBound)) tall." } ?? "The tallest initial.") { height in
                var next = spec; next.height = height
                state.rebuildMonogram(next, action: "Monogram Height")
            }
            Text("Font").font(Theme.body(11, weight: .regular))
            // The same list as lettering's, showing these initials in each font. Fonts tried in a row undo as one step.
            LetteringFontList(spec: LetteringSpec(text: spec.initials, fontKind: spec.fontKind, font: spec.font, height: spec.height), color: color) { choice in
                state.rebuildMonogram(Self.monogram(spec, withFont: choice), action: "Monogram Font", run: "font \(spec.id)")
            }
            .help("Embroidery fonts are hand-digitized satin lettering; Mac fonts are converted to fill.")
            MonogramTileGrid(heading: "Layout", options: MonogramLayout.allCases, chosen: spec.layout, columns: 4, color: color, title: \.title,
                             sample: { Self.tileSample(spec, layout: $0) }) { layout in
                var next = spec; next.layout = layout
                state.rebuildMonogram(next, action: "Monogram Layout")
            }
            MonogramTileGrid(heading: "Ornaments", options: MonogramOrnament.allCases, chosen: spec.ornament, columns: 4, color: color, title: \.title,
                             sample: { Self.tileSample(spec, ornament: $0) }) { ornament in
                var next = spec; next.ornament = ornament
                state.rebuildMonogram(next, action: "Monogram Ornaments")
            }
            MonogramTileGrid(heading: "Border", options: MonogramBorder.allCases, chosen: spec.border, columns: 4, color: color, title: \.title,
                             sample: { Self.tileSample(spec, border: $0) }) { border in
                var next = spec; next.border = border
                state.rebuildMonogram(next, action: "Monogram Border")
            }
            if spec.border != .none {
                number("Border width", value: spec.borderWidth, range: MonogramSpec.borderWidths, unit: "mm", help: "How wide the border's satin is.") { width in
                    var next = spec; next.borderWidth = width
                    state.rebuildMonogram(next, action: "Monogram Border Width")
                }
                number("Gap", value: spec.borderGap, range: MonogramSpec.borderGaps, length: true, help: "The space between the border and the initials and ornaments.") { gap in
                    var next = spec; next.borderGap = gap
                    state.rebuildMonogram(next, action: "Monogram Border Gap")
                }
            }
            Button("Break apart") { AppDelegate.shared.perform(.breakApartLettering) }.buttonStyle(ThemedButtonStyle())
                .help(preferences.hint(.breakApartLettering))
        }
    }

    /// `spec` switched to another font, as lettering does it (InspectorPanel.spec(_:withFont:)): an embroidery font
    /// keeps the height if it's digitized for it (otherwise it takes its own size), a Mac font gets its Bold style.
    /// The height is then kept within a monogram's range.
    static func monogram(_ spec: MonogramSpec, withFont choice: LetteringFontChoice) -> MonogramSpec {
        let lettering = Self.spec(LetteringSpec(text: spec.initials, fontKind: spec.fontKind, font: spec.font, height: spec.height), withFont: choice)
        var next = spec
        next.fontKind = lettering.fontKind; next.font = lettering.font
        next.height = min(max(lettering.height, MonogramSpec.heights.lowerBound), MonogramSpec.heights.upperBound)
        return next
    }

    /// What a picture in the Layout, Ornaments or Border grid shows: the monogram's own initials and font with that
    /// one choice, and nothing else that would make it harder to see. Ornament pictures use just the first initial,
    /// so the small ornaments either side stay big enough to make out.
    static func tileSample(_ spec: MonogramSpec, layout: MonogramLayout? = nil, ornament: MonogramOrnament? = nil, border: MonogramBorder? = nil) -> MonogramSpec {
        var sample = MonogramSpec(initials: spec.initials, fontKind: spec.fontKind, font: spec.font, height: spec.height,
                                  layout: layout ?? spec.layout, ornament: ornament ?? .none, border: border ?? .none,
                                  borderWidth: spec.borderWidth, borderGap: spec.borderGap)
        sample.id = MonogramTiles.sampleID   // the same id every time, so equal samples are found in the cache
        if ornament != nil { sample.initials = String(spec.initials.filter { !$0.isWhitespace }.prefix(1)) }
        return sample
    }
}

/// The monogram's initials, typed in place (up to three). The monogram rebuilds a moment after the last key, and
/// the box follows the monogram when it changes some other way, such as Undo.
struct MonogramInitialsBox: View {
    let initials: String
    /// True when the box should take the keyboard (a new monogram, or Edit Monogram); `focused` is called once it has.
    var focusRequested = false
    var focused: () -> Void = {}
    let commit: (String) -> Void
    @State private var text = ""
    @State private var pending: DispatchWorkItem?
    @FocusState private var editing: Bool
    var body: some View {
        // The binding drops anything past the third letter as it's typed.
        TextField("ABC", text: Binding(get: { text }, set: { text = String($0.prefix(3)) }))
            .textFieldStyle(.roundedBorder).font(Theme.body(12)).frame(width: 70)
            .focused($editing)
            .onAppear { text = initials; if focusRequested { takeFocus() } }
            .onChange(of: focusRequested) { _, requested in if requested { takeFocus() } }
            .onChange(of: initials) { _, new in if !editing || pending == nil { text = new } }
            .onChange(of: text) { _, new in
                guard new != initials else { return }
                pending?.cancel()
                // A short pause after the last key, so typing "EMR" rebuilds once instead of three times.
                let work = DispatchWorkItem { pending = nil; if !new.trimmingCharacters(in: .whitespaces).isEmpty { commit(new) } }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
            .help("One to three initials. With three, Big middle and Diamond make the middle one larger (usually the surname).")
    }
    /// Puts the keyboard here with the initials selected, so typing replaces them (as LetteringTextBox does).
    private func takeFocus() {
        focused()
        DispatchQueue.main.async {
            editing = true
            DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
        }
    }
}

/// A heading and a grid of picture choices (Layout, Ornaments or Border). The chosen one has the soft denim
/// highlight; pointing at one shows its name.
struct MonogramTileGrid<Option: Hashable>: View {
    let heading: String
    let options: [Option]
    let chosen: Option
    let columns: Int
    let color: ThreadColor
    let title: (Option) -> String
    /// The monogram each picture shows.
    let sample: (Option) -> MonogramSpec
    let choose: (Option) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(Theme.body(11, weight: .regular))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(options, id: \.self) { option in
                    MonogramTile(sample: sample(option), color: color, chosen: option == chosen, title: title(option)) {
                        if option != chosen { choose(option) }
                    }
                }
            }
        }
    }
}

/// One picture choice: the sample monogram, built in the background. The last picture stays on show until the new
/// one is ready (after typing new initials, say), so the grid never goes blank.
struct MonogramTile: View {
    let sample: MonogramSpec
    let color: ThreadColor
    let chosen: Bool
    let title: String
    let choose: () -> Void
    @State private var objects: [RunObject] = []
    private struct Key: Hashable { let sample: MonogramSpec; let color: ThreadColor }
    var body: some View {
        Button(action: choose) {
            StitchThumbnail(objects: objects, label: title, padding: 3, onFabric: false)
                .aspectRatio(1, contentMode: .fit)
                .background(chosen ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(chosen ? Theme.accent : Theme.controlBorder, lineWidth: chosen ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        // .task(id:) starts again when the sample or thread changes, cancelling a build that's no longer wanted.
        .task(id: Key(sample: sample, color: color)) {
            let built = await MonogramTiles.objects(sample, color: color)
            if !Task.isCancelled { objects = built }
        }
    }
}

/// The tile pictures, built once per sample and thread (building them on every redraw would slow the panel down).
@MainActor enum MonogramTiles {
    /// The id every sample is given, so two samples with the same choices are equal.
    static let sampleID = UUID()
    private static var built: [MonogramSpec: [RunObject]] = [:]
    private static var builtColor: ThreadColor?
    /// The sample's objects in `color`, from the cache or built in the background (an empty list if it can't be made).
    static func objects(_ sample: MonogramSpec, color: ThreadColor) async -> [RunObject] {
        if builtColor != color { built.removeAll(); builtColor = color }
        if let objects = built[sample] { return objects }
        let fonts = EmbroideryFontLibrary.fonts
        let objects = await Task.detached(priority: .userInitiated) { (try? sample.build(color: color, embroideryFonts: fonts))?.objects ?? [] }.value
        if built.count > 300 { built.removeAll() }   // keeps the memory used small after lots of typing
        if builtColor == color { built[sample] = objects }
        return objects
    }
}

/// What a new monogram starts as: the initials, font, size, layout, ornaments and border used last, kept until the
/// app quits.
@MainActor enum MonogramDefaults {
    private static var last: MonogramSpec?
    /// Keeps `spec`'s choices for the next monogram.
    static func remember(_ spec: MonogramSpec) { last = spec }
    /// A new recipe (with its own id, in the middle of the hoop) for the next monogram, in a font this Mac has.
    static func next() -> MonogramSpec {
        var spec = last ?? first
        spec.id = UUID(); spec.anchor = Point(0, 0); spec.alongMarker = Point(10, 0); spec.upMarker = Point(0, 10)
        if spec.fontKind == .embroidery && EmbroideryFontLibrary.font(spec.font) == nil {
            if let font = EmbroideryFontLibrary.fonts.first {
                spec.font = font.folder.lastPathComponent
                spec.height = min(max(spec.height, font.heights.lowerBound), font.heights.upperBound)
            } else { spec.fontKind = .system; spec.font = "Didot-Bold" }
        }
        if spec.fontKind == .system && NSFont(name: spec.font, size: 12) == nil { spec.font = "Helvetica-Bold" }
        return spec
    }
    /// The very first monogram: ABC in Caesarus SC (a classic serif made for initials), 30 mm, in a circle.
    private static let first = MonogramSpec(initials: "ABC", fontKind: .embroidery, font: "caesarus_SC_FI", height: 30, layout: .bigMiddle, ornament: .none, border: .circle)
}
