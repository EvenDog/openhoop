// 3C-styled dialogs for importing and exporting: the import report, the machine-format chooser and the export check.
// Each waits for a choice exactly like a standard macOS alert (the code that opens it pauses until a button is
// clicked), so the import and export steps around it run in the same order as before.
import AppKit
import SwiftUI
import EmbroideryCore

@MainActor enum GuidedDialog {
    /// Shows `content` in its own modal window and returns true if the person chose the main action.
    /// `content` receives a `finish` function; its buttons call finish(true) or finish(false) to close the dialog.
    static func run<Content: View>(width: CGFloat = 700, @ViewBuilder content: (_ finish: @escaping (Bool) -> Void) -> Content) -> Bool {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        // stopModal ends NSApp.runModal below and hands back the code for the chosen button.
        let finish: (Bool) -> Void = { choice in NSApp.stopModal(withCode: choice ? .OK : .cancel) }
        let host = NSHostingView(rootView: content(finish).frame(width: width))
        window.contentView = host
        window.setContentSize(host.fittingSize)   // size the window to fit the dialog's content
        window.center()
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response == .OK
    }
    /// The format chooser: returns the picked format, or nil if the person cancelled.
    static func chooseFormat(threadListOnly: Bool) -> MachineFormat? {
        var chosen: MachineFormat?   // the chooser's closure writes the pick here before the dialog closes
        let confirmed = run(width: 820) { finish in
            FormatChooserView(threadListOnly: threadListOnly) { format in chosen = format; finish(format != nil) }
        }
        return confirmed ? chosen : nil
    }
}

/// The shared look of every dialog: a small label, a serif title and subtitle, the body, then Cancel and the main button.
/// Return presses the main button and Escape presses Cancel.
struct DialogFrame<Content: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var primary: String
    var finish: (Bool) -> Void
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased()).font(Theme.caption).tracking(1).foregroundStyle(Theme.inkSecondary)
                Text(title).font(Theme.heading(26))
                Text(subtitle).font(Theme.body(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 16)
            Theme.divider.frame(height: 1)
            content.padding(.horizontal, 28).padding(.vertical, 18)
            Theme.divider.frame(height: 1)
            HStack {
                Spacer()
                Button("Cancel") { finish(false) }.keyboardShortcut(.cancelAction).buttonStyle(ThemedButtonStyle())
                Button(primary) { finish(true) }.keyboardShortcut(.defaultAction).buttonStyle(ThemedButtonStyle(prominent: true))
            }.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.card)
    }
}

/// Everything the import report shows, gathered by the import code before the dialog opens.
struct ImportReport {
    enum Kind { case machine(MachineFormat), svg }
    var kind: Kind
    var fileName: String
    var count: Int          // stitches for a machine file, outlines for an SVG
    var blocks: Int         // thread blocks (machine file) or outlines (SVG)
    var width: Double
    var height: Double
    var fitsHoop: Bool
    var warnings: [String]
    var objects: [RunObject]
}

struct ImportReportView: View {
    let report: ImportReport
    let finish: (Bool) -> Void
    private var isMachine: Bool { if case .machine = report.kind { return true }; return false }
    var body: some View {
        DialogFrame(eyebrow: isMachine ? "Import machine file" : "Import SVG outlines",
                    title: isMachine ? "Import \(report.count.formatted()) stitches?" : "Import \(report.count) vector outlines?",
                    subtitle: "From \(report.fileName). This is added to your design as one step you can undo; the original file isn't changed.",
                    primary: isMachine ? "Import Stitches" : "Import Outlines", finish: finish) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    StitchThumbnail(objects: report.objects).frame(width: 230, height: 180)
                    facts
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(isMachine ? "What you're bringing in" : "What happens next").font(Theme.body(13, weight: .bold))
                    Text(isMachine
                         ? "These are finished stitches, not shapes. You can move, rotate, mirror, recolor, reorder and combine them. Resizing changes how dense the stitches are; it doesn't recalculate them. Editing points and changing the stitch type aren't available for imported stitches."
                         : "These outlines don't sew until you assign Running Stitch or Tatami Fill. Curves keep their Bézier handles, so you can reshape them with N; overlapping shapes that have to be merged become points instead. Satin still needs edge pairs drawn by hand.")
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
                if !report.warnings.isEmpty { NotesList(title: "Notes about this file", notes: report.warnings) }
            }
        }
    }
    private var facts: some View {
        // Grid lines labels up in one column and values in the next.
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
            if case .machine(let format) = report.kind { fact("Format", format.title) }
            fact(isMachine ? "Stitches" : "Outlines", report.count.formatted())
            if isMachine { fact("Thread blocks", report.blocks.formatted()) }
            fact("Size", String(format: "%.1f × %.1f mm", report.width, report.height))
            fact("Placement", isMachine ? "Kept from the file" : "Centered at original size")
            GridRow {
                Text("Hoop").foregroundStyle(Theme.inkSecondary)
                Label(report.fitsHoop ? "Fits the sewing area" : (isMachine ? "Some movement is outside the sewing area. Reposition or resize before export." : "Larger than the sewing area: resize the imported selection before digitizing."),
                      systemImage: report.fitsHoop ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(report.fitsHoop ? Theme.success : Color.orange).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
            }
        }.font(Theme.body(13))
    }
    private func fact(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(Theme.inkSecondary); Text(value).fontWeight(.bold) }
    }
}

/// A small picture of imported stitches or outlines, scaled to fit, each in its own thread color.
struct StitchThumbnail: View {
    let objects: [RunObject]
    var label = "Preview of the imported design"
    var body: some View {
        Canvas { context, size in
            let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
            let pad = 14.0
            let scale = min((size.width - 2 * pad) / max(maxX - minX, 0.1), (size.height - 2 * pad) / max(maxY - minY, 0.1))
            let left = (size.width - (maxX - minX) * scale) / 2, bottom = (size.height - (maxY - minY) * scale) / 2
            // Design coordinates point up; screen coordinates point down, so y is flipped here.
            func place(_ p: Point) -> CGPoint { CGPoint(x: left + (p.x - minX) * scale, y: size.height - (bottom + (p.y - minY) * scale)) }
            for object in objects {
                if object.kind == .fill {
                    // Fill shapes are drawn solid; eoFill ("even-odd") leaves their holes open.
                    var shape = Path()
                    for ring in object.outlinePaths where ring.count > 2 { shape.addLines(ring.map(place)); shape.closeSubpath() }
                    context.fill(shape, with: .color(Color(nsColor: object.color.nsColor)), style: FillStyle(eoFill: true))
                    continue
                }
                let paths = object.outlinePaths
                if object.kind == .satin, paths.count >= 2, paths[0].count > 1, paths[1].count > 1 {
                    // A satin column is the band between its two rails (the first two outline paths): down one rail and
                    // back up the other. A closed satin (a border) is two loops instead, and even-odd leaves its middle open.
                    var band = Path()
                    if object.closed {
                        band.addLines(paths[0].map(place)); band.closeSubpath()
                        band.addLines(paths[1].map(place)); band.closeSubpath()
                    } else {
                        band.addLines((paths[0] + paths[1].reversed()).map(place)); band.closeSubpath()
                    }
                    context.fill(band, with: .color(Color(nsColor: object.color.nsColor)), style: FillStyle(eoFill: true))
                    continue
                }
                for path in object.outlinePaths where path.count > 1 {
                    var line = Path(); line.move(to: place(path[0])); for point in path.dropFirst() { line.addLine(to: place(point)) }
                    context.stroke(line, with: .color(Color(nsColor: object.color.nsColor)), lineWidth: 0.8)
                }
            }
        }
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(label)
    }

    /// Draws the design on cream fabric as a 512×512-pixel PNG (saved projects carry it for Finder), or nil if drawing fails.
    @MainActor static func png(of objects: [RunObject]) -> Data? {
        let renderer = ImageRenderer(content: StitchThumbnail(objects: objects).frame(width: 256, height: 256))
        renderer.scale = 2   // 256 points at 2 pixels per point
        var picture: CGImage?
        // The app's cream turns dark brown in Dark Mode; drawing under the light appearance keeps the saved picture cream.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { picture = renderer.cgImage }
        guard let picture else { return nil }
        return NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:])
    }
}

/// A list of notes (import or export warnings) as small cards; long lists scroll.
struct NotesList: View {
    var title: String
    var notes: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.body(13, weight: .bold))
            if notes.count > 3 { ScrollView { cards }.frame(height: 230) } else { cards }
        }
    }
    private var cards: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                    Text(note).font(Theme.body(12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.divider))
            }
        }
    }
}

/// The machine-format chooser: one card per format, plus notes on the selected format.
struct FormatChooserView: View {
    let threadListOnly: Bool
    let choose: (MachineFormat?) -> Void
    @State private var selected: MachineFormat = .pes
    var body: some View {
        DialogFrame(eyebrow: threadListOnly ? "Thread list" : "Save for machine",
                    title: threadListOnly ? "Thread list for which format?" : "Choose a machine format",
                    subtitle: "PES is the default for your Brother. Select the format accepted by the target machine.",
                    primary: "Continue", finish: { confirmed in choose(confirmed ? selected : nil) }) {
            HStack(alignment: .top, spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(MachineFormat.allCases, id: \.self) { format in card(format) }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Good to know about \(selected.title)").font(Theme.heading(17))
                    ForEach(Self.notes(for: selected), id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) { Text("•"); Text(note).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 0)
                }
                .font(Theme.body(12)).foregroundStyle(Theme.ink)
                .padding(14).frame(width: 250, alignment: .leading).frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
    private func card(_ format: MachineFormat) -> some View {
        let active = selected == format
        // The description reads like "PES — Brother / Baby Lock"; the part after the dash names the machines.
        let machines = format.description.components(separatedBy: " — ").last ?? ""
        return Button { selected = format } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(format.title).font(Theme.heading(19))
                    Spacer()
                    if format == .pes { Text("Default").font(Theme.body(10, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 2).background(Theme.success.opacity(0.15), in: Capsule()).foregroundStyle(Theme.success) }
                }
                Text(machines).font(Theme.body(12, weight: .semibold))
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? Theme.accent : Theme.divider, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
    /// Plain-English notes per format, condensed from the export format table in README.md.
    static func notes(for format: MachineFormat) -> [String] {
        switch format {
        case .pes: return ["PES 6 stores your exact thread colors. The embedded preview and PES 1 use Brother's palette.", "The design must fit the hoop chosen under Sewing area; its size is stored in the file.", "Moves between parts can become trims. Separate trim requests may be omitted; your machine decides whether to cut."]
        case .pec: return ["Colors are matched to Brother's palette.", "Moves and trims follow PEC's rules; the configured hoop is checked."]
        case .dst: return ["DST doesn't store thread colors. Export the thread list (CSV) to know the loading order.", "Trims are written as jump sequences; whether they cut depends on the machine's setup."]
        case .exp: return ["EXP doesn't store thread colors. Export the thread list (CSV) to know the loading order.", "Trim commands are written, but controllers treat them differently."]
        case .jef: return ["Colors are matched to Janome's palette.", "The file picks a standard hoop from the design's size; placement outside that hoop is rejected."]
        case .vp3: return ["VP3 stores your thread colors.", "Moves between parts are always trimmed first.", "How the first move behaves still needs a test sew-out."]
        case .xxx: return ["XXX stores your thread colors.", "This exporter allows at most 21 thread blocks."]
        }
    }
}

/// What the export check found, gathered after the file has been encoded and read back.
struct ExportCheck {
    var format: MachineFormat
    var stitchCount: Int
    var width: Double
    var height: Double
    var omittedOutlines: Int
    var warnings: [String]
    var threadListOnly: Bool
    var fileName: String
}

struct ExportCheckView: View {
    let check: ExportCheck
    let finish: (Bool) -> Void
    private let checks = ["Needle count and positions", "Color changes and stops", "Thread color mapping", "Moves between parts", "Fits the hoop"]
    var body: some View {
        DialogFrame(eyebrow: check.threadListOnly ? "Thread list ready" : "Export checked",
                    title: "\(check.format.title) checked · \(check.stitchCount.formatted()) stitches",
                    subtitle: String(format: "Size: %.1f × %.1f mm. Saving as %@.", check.width, check.height, check.fileName),
                    primary: check.threadListOnly ? "Save Thread List" : "Save \(check.format.title)", finish: finish) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("We read the file back and checked").font(Theme.body(13, weight: .bold))
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                        ForEach(checks, id: \.self) { item in Label(item, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success).font(Theme.body(12, weight: .semibold)) }
                    }
                }
                if check.omittedOutlines > 0 || !check.warnings.isEmpty {
                    NotesList(title: "Notes", notes: (check.omittedOutlines > 0 ? ["\(check.omittedOutlines) unstitched vector outlines are excluded."] : []) + check.warnings)
                }
                Label("File read-back checks passed. Machine compatibility and stitch quality still require a test sew-out.", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.body(12)).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// The choices in the lettering dialog. The last ones used are kept until the app quits, so the next
/// lettering starts from the same font and size.
struct LetteringChoices {
    enum Source { case embroidery, mac }   // a hand-digitized embroidery font, or a system font installed on this Mac
    var text = "Your Text"
    var source = Source.embroidery
    var embroideryFont = "small_font"  // the font's folder name in the app's EmbroideryFonts resources
    var family = "Avenir Next"
    var fontName = "AvenirNext-Bold"   // the PostScript name: one exact style within the family
    var height = 8.0
    var stitch = LetteringStitch.fill
    var shape = LetteringShape.straight
    var radius = 40.0   // mm; only used for arched lettering
    var alignment = LetteringAlignment.center   // only used for several lines
    var lineSpacing = LetteringSpec.defaultLineSpacing

    /// The lettering recipe for these choices. When editing, `base` is the existing lettering's recipe, whose
    /// identity and placement are kept.
    func spec(base: LetteringSpec?) -> LetteringSpec {
        var spec = base ?? LetteringSpec(text: text, fontKind: .system, font: fontName, height: height)
        spec.text = text; spec.height = height; spec.stitch = stitch; spec.shape = shape; spec.radius = radius
        spec.alignment = alignment; spec.lineSpacing = lineSpacing
        spec.fontKind = source == .embroidery ? .embroidery : .system
        spec.font = source == .embroidery ? embroideryFont : fontName
        return spec
    }

    /// The choices showing existing lettering's recipe, keeping `fallback`'s choices for the other kind of font.
    static func editing(_ spec: LetteringSpec, fallback: LetteringChoices) -> LetteringChoices {
        var choices = fallback
        choices.text = spec.text; choices.height = spec.currentHeight; choices.stitch = spec.stitch; choices.shape = spec.shape; choices.radius = spec.radius
        choices.alignment = spec.alignment ?? .center; choices.lineSpacing = spec.lineSpacing ?? LetteringSpec.defaultLineSpacing
        switch spec.fontKind {
        case .embroidery: choices.source = .embroidery; choices.embroideryFont = spec.font
        case .system:
            choices.source = .mac; choices.fontName = spec.font
            choices.family = NSFont(name: spec.font, size: 12)?.familyName ?? choices.family
        }
        return choices
    }
}

/// The embroidery fonts that ship inside the app (Resources/EmbroideryFonts), read once.
enum EmbroideryFontLibrary {
    static let fonts: [EmbroideryFont] = Bundle.main.resourceURL.map { EmbroideryFont.all(in: $0.appendingPathComponent("EmbroideryFonts")) } ?? []
    static func font(_ folder: String) -> EmbroideryFont? { fonts.first { $0.folder.lastPathComponent == folder } }
}

extension GuidedDialog {
    static var lastLettering = LetteringChoices()
    /// The lettering dialog, for new lettering or (with `editing`, its current recipe) to change existing lettering.
    /// `handEdited` adds a note that updating undoes changes made by hand. Returns the recipe to build, or nil if
    /// the person cancelled.
    static func lettering(color: ThreadColor, hoop: Hoop, editing: LetteringSpec? = nil, handEdited: Bool = false) -> LetteringSpec? {
        var made: LetteringSpec?   // the dialog's closure writes the recipe here before it closes
        if NSFont(name: lastLettering.fontName, size: 12) == nil { lastLettering.family = "Helvetica"; lastLettering.fontName = "Helvetica-Bold" }
        if EmbroideryFontLibrary.fonts.isEmpty { lastLettering.source = .mac }
        else if EmbroideryFontLibrary.font(lastLettering.embroideryFont) == nil { lastLettering.embroideryFont = EmbroideryFontLibrary.fonts[0].folder.lastPathComponent }
        let confirmed = run(width: 780) { finish in
            LetteringView(choices: editing.map { LetteringChoices.editing($0, fallback: lastLettering) } ?? lastLettering,
                          color: color, hoop: hoop, editing: editing, handEdited: handEdited) { choices, spec in
                lastLettering = choices; made = spec; finish(spec != nil)
            }
        }
        return confirmed ? made : nil
    }
}

/// Type a line of text, pick a font, style, height and stitch, and see the letters update as you go.
struct LetteringView: View {
    @State var choices: LetteringChoices
    // The height as typed. A number-formatted field only updates when you press Return or leave it, so clicking
    // Add Lettering straight after typing could use the old height; this text is read on every keystroke instead.
    @State private var heightText = ""
    @State private var radiusText = ""   // typed the same way as the height
    @FocusState private var textFocused: Bool
    @State private var showCredits = false
    let color: ThreadColor
    let hoop: Hoop
    /// The recipe of the lettering being edited, or nil when adding new lettering.
    let editing: LetteringSpec?
    let handEdited: Bool
    /// Called with the choices and the recipe to build (nil for Cancel).
    let done: (LetteringChoices, LetteringSpec?) -> Void
    // Font families installed on this Mac; names starting with "." are hidden system fonts.
    private let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }

    var body: some View {
        // The preview is built upright and centered; the finished lettering goes where the old one was.
        let preview = Result { try choices.spec(base: nil).build(color: color, embroideryFonts: EmbroideryFontLibrary.fonts) }
        DialogFrame(eyebrow: "Lettering", title: editing == nil ? "Add lettering" : "Edit lettering",
                    subtitle: editing == nil
                        ? "Type your text (Return starts a new line) and pick a font. Embroidery fonts are hand-digitized satin lettering; system fonts (any font on this Mac) become fill or outline shapes. The letters are grouped so they move together, and stay editable: double-click them later to change the text."
                        : "Change the text, font, size or shape. The letters are rebuilt in the same place, turned the same way.",
                    primary: editing == nil ? "Add Lettering" : "Update Lettering",
                    finish: { add in
                        if !add { done(choices, nil) } else if case .success = preview { done(choices, choices.spec(base: editing)) }
                    }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 22) {
                    controls.frame(width: 300)
                    VStack(alignment: .leading, spacing: 8) {
                        switch preview {
                        case .success(let letters):
                            StitchThumbnail(objects: letters.objects, label: "Preview of the lettering").frame(height: 200)
                            sizeLine(letters)
                        case .failure(let error):
                            Theme.ground.clipShape(RoundedRectangle(cornerRadius: 14)).frame(height: 200)
                                .overlay { Text(error.localizedDescription).font(Theme.body(13)).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center).padding() }
                        }
                    }
                }
                let notes = (handEdited ? ["Some of these letters were reshaped, reordered or given different stitch settings. Updating rebuilds every letter from the font, so those changes will be lost (Undo brings them back)."] : [])
                    + ((try? preview.get())?.warnings ?? [])
                if !notes.isEmpty { NotesList(title: "Notes", notes: notes) }
            }
        }
        // A new embroidery font keeps the height if the font was digitized for it, else uses the font's own size.
        .onChange(of: choices.embroideryFont) { fitHeightToFont() }
        .onChange(of: choices.source) { fitHeightToFont() }
        // Switching family picks that family's bold style when it has one.
        .onChange(of: choices.family) { choices.fontName = Self.preferredStyle(in: styles(of: choices.family)) ?? choices.fontName }
        // Keep the typed height and the stepper in step with each other. Text that isn't a number becomes 0,
        // which the preview explains is out of range.
        .onAppear { heightText = Self.format(choices.height) }
        .onChange(of: heightText) { choices.height = Double(heightText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        .onChange(of: choices.height) { if Double(heightText.replacingOccurrences(of: ",", with: ".")) != choices.height { heightText = Self.format(choices.height) } }
        .onAppear { radiusText = Self.format(choices.radius) }
        // Start in the text box with its text selected, so typing replaces it. (SwiftUI's text box has no way to
        // select text on macOS 14, so this sends the standard Select All to whatever has the keyboard focus.)
        .onAppear {
            textFocused = true
            DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
        }
        .onChange(of: radiusText) { choices.radius = Double(radiusText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        .onChange(of: choices.radius) { if Double(radiusText.replacingOccurrences(of: ",", with: ".")) != choices.radius { radiusText = Self.format(choices.radius) } }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Text") {
                // A small multi-line box: Return starts a new line.
                TextEditor(text: $choices.text)
                    .font(Theme.body(13)).scrollContentBackground(.hidden).padding(.horizontal, 3).padding(.vertical, 4)
                    .frame(height: 62).focused($textFocused)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.divider))
            }
            if lineCount > 1 {
                field("Lines") {
                    Picker("Alignment", selection: $choices.alignment) { ForEach(LetteringAlignment.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                    HStack(spacing: 6) {
                        Text("Line spacing").foregroundStyle(Theme.inkSecondary)
                        TextField("Line spacing", value: $choices.lineSpacing, format: .number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder).frame(width: 56)
                        Text("× letter height").foregroundStyle(Theme.inkSecondary)
                        Stepper("Line spacing", value: $choices.lineSpacing, in: LetteringSpec.lineSpacings, step: 0.1).labelsHidden()
                    }
                }
            }
            field("Font") {
                // One list in two labeled sections, each font marked with its kind: embroidery fonts (hand-digitized
                // satin) first, then the system fonts installed on this Mac (converted to fill or outline).
                Picker("Font", selection: fontChoice) {
                    if !EmbroideryFontLibrary.fonts.isEmpty {
                        Section("Embroidery fonts · hand-digitized satin") {
                            ForEach(EmbroideryFontLibrary.fonts, id: \.folder) { font in
                                Label("\(font.name)   \(Self.range(font))", systemImage: FontKind.embroidery.symbol).tag(FontChoice.embroidery(font.folder.lastPathComponent))
                            }
                        }
                    }
                    Section("System fonts · converted to fill or outline") {
                        ForEach(families, id: \.self) { family in Label(family, systemImage: FontKind.system.symbol).tag(FontChoice.system(family)) }
                    }
                }.labelsHidden()
                FontKindBadge(kind: choices.source == .embroidery ? .embroidery : .system)
            }
            if choices.source == .embroidery, let font = embroideryFont {
                // The font's own preview: its name, embroidered.
                if let image = NSImage(contentsOf: font.folder.appendingPathComponent("preview.png")) {
                    Image(nsImage: image).resizable().scaledToFit().frame(height: 22, alignment: .leading)   // fixed, so a tall dialog can't squeeze it away
                }
                heightField(range: font.heights, step: 0.5)
                Text("Hand-digitized satin lettering, digitized for letters \(Self.range(font)) tall. \(font.license).")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                Button("Font credits…") { showCredits = true }.buttonStyle(ThemedButtonStyle())
                    .popover(isPresented: $showCredits, arrowEdge: .trailing) { FontCreditsView() }
            } else {
                field("Style") {
                    Picker("Style", selection: $choices.fontName) { ForEach(styles(of: choices.family), id: \.name) { Text($0.title).tag($0.name) } }.labelsHidden()
                }
                heightField(range: Lettering.heights, step: 1)
                field("Stitch") {
                    Picker("Stitch", selection: $choices.stitch) { ForEach(LetteringStitch.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                }
                Text(choices.stitch == .fill
                     ? "Solid tatami fill inside each letter. Best for bold letters 10 mm or taller."
                     : "A running stitch around each letter's edges, including the inside of letters like O and A.")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            field("Shape") {
                Picker("Shape", selection: $choices.shape) { ForEach(LetteringShape.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            }
            if choices.shape != .straight {
                field("Arc radius") {
                    HStack(spacing: 6) {
                        TextField("Radius", text: $radiusText).textFieldStyle(.roundedBorder).frame(width: 70)
                        Text("mm").foregroundStyle(Theme.inkSecondary)
                        Stepper("Arc radius", value: $choices.radius, in: Lettering.radii, step: 5).labelsHidden()
                        Spacer()
                    }
                }
                Text(choices.shape == .archUp
                     ? "Letters follow the top of a circle this size, like text across the top of a round badge. Smaller is more curved."
                     : "Letters follow the bottom of a circle this size, like text along the bottom of a round badge. Smaller is more curved.")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Circle().fill(Color(nsColor: color.nsColor)).frame(width: 12, height: 12)
                Text(editing == nil ? "Sews in \(color.name), the current thread." : "Sews in \(color.name), as before.").foregroundStyle(Theme.inkSecondary)
            }.font(Theme.body(12))
        }
        .font(Theme.body(13))
    }

    private var embroideryFont: EmbroideryFont? { EmbroideryFontLibrary.font(choices.embroideryFont) }
    /// How many lines the typed text has (ignoring blank lines at the start and end).
    private var lineCount: Int { choices.spec(base: nil).lines.count }

    /// One value for the combined font list: which embroidery font (by folder) or system font family is chosen.
    enum FontChoice: Hashable { case embroidery(String), system(String) }
    private var fontChoice: Binding<FontChoice> {
        Binding(get: { choices.source == .embroidery ? .embroidery(choices.embroideryFont) : .system(choices.family) },
                set: { choice in
                    switch choice {
                    case .embroidery(let folder): choices.source = .embroidery; choices.embroideryFont = folder
                    case .system(let family): choices.source = .mac; choices.family = family
                    }
                })
    }

    /// The letter height: typed, or stepped within `range`.
    private func heightField(range: ClosedRange<Double>, step: Double) -> some View {
        field("Letter height") {
            HStack(spacing: 6) {
                TextField("Height", text: $heightText).textFieldStyle(.roundedBorder).frame(width: 70)
                Text("mm").foregroundStyle(Theme.inkSecondary)
                Stepper("Letter height", value: $choices.height, in: range, step: step).labelsHidden()
                Spacer()
            }
        }
    }

    /// After switching to an embroidery font that wasn't digitized for the current height, use the font's own size.
    private func fitHeightToFont() {
        guard choices.source == .embroidery, let font = embroideryFont, !font.heights.contains(choices.height) else { return }
        choices.height = (min(max(font.size, font.heights.lowerBound), font.heights.upperBound) * 10).rounded() / 10
    }
    private static func range(_ font: EmbroideryFont) -> String {
        "\(font.heights.lowerBound.formatted(.number.precision(.fractionLength(0...1))))–\(font.heights.upperBound.formatted(.number.precision(.fractionLength(0...1)))) mm"
    }

    /// A small caption above one control.
    private func field<Control: View>(_ title: String, @ViewBuilder _ control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(Theme.body(12, weight: .bold)); control() }
    }

    private func sizeLine(_ letters: LetteringResult) -> some View {
        let fits = letters.objects.allSatisfy { $0.outlinePaths.allSatisfy { $0.allSatisfy { hoop.contains($0) } } }
        return HStack(spacing: 10) {
            Text(String(format: "%.1f × %.1f mm", letters.width, letters.height)).fontWeight(.semibold)
            Label(fits ? "Fits the sewing area" : "Larger than the sewing area", systemImage: fits ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(fits ? Theme.success : Color.orange)
        }.font(Theme.body(12))
    }

    /// The styles in a font family as (PostScript name, style name) pairs, such as ("AvenirNext-Bold", "Bold").
    private func styles(of family: String) -> [(name: String, title: String)] {
        // Each member is an array: [PostScript name, style name, weight, traits].
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard member.count > 1, let name = member[0] as? String, let title = member[1] as? String else { return nil }
            return (name, title)
        }
    }
    private static func format(_ height: Double) -> String { height.formatted(.number.precision(.fractionLength(0...1))) }
    private static func preferredStyle(in styles: [(name: String, title: String)]) -> String? {
        (styles.first { $0.title == "Bold" } ?? styles.first)?.name
    }
}

extension GuidedDialog {
    static var lastAutoDigitize = AutoDigitizeOptions()
    /// The auto-digitize dialog: returns the traced fills, or nil if the person cancelled.
    static func autoDigitize(_ artwork: Artwork) -> AutoDigitizeResult? {
        var made: AutoDigitizeResult?   // the dialog's closure writes the result here before it closes
        let confirmed = run(width: 820) { finish in
            AutoDigitizeView(artwork: artwork, options: lastAutoDigitize) { options, result in
                lastAutoDigitize = options; made = result; finish(result != nil)
            }
        }
        return confirmed ? made : nil
    }
}

/// Choose how many thread colors to trace, whether to skip the background and the smallest part to keep,
/// and compare the picture with the traced fills. Tracing reruns in the background after every change.
struct AutoDigitizeView: View {
    let artwork: Artwork
    @State var options: AutoDigitizeOptions
    /// Called with the options and the traced fills (nil for Cancel).
    let done: (AutoDigitizeOptions, AutoDigitizeResult?) -> Void
    @State private var traced: Result<AutoDigitizeResult, Error>?   // nil while tracing
    private let smallestChoices: [Double] = [0.5, 1, 2, 5, 10]

    var body: some View {
        DialogFrame(eyebrow: "Auto-digitize", title: "Trace your image into fills",
                    subtitle: "The picture is reduced to a few thread colors and each patch of color becomes a tatami fill, placed exactly over your image. Check the result: thin lines and small text usually look better redrawn as satin or running stitch.",
                    primary: "Add Fills",
                    finish: { add in
                        if !add { done(options, nil) } else if case .success(let result) = traced { done(options, result) }
                    }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    picture("Your image") {
                        if let image = NSImage(data: artwork.data) { Image(nsImage: image).resizable().scaledToFit().padding(14) }
                    }
                    picture("Traced fills") {
                        switch traced {
                        case .none: ProgressView().controlSize(.small)
                        case .success(let result)?: StitchThumbnail(objects: result.objects, label: "Preview of the traced fills")
                        case .failure(let error)?: Text(error.localizedDescription).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center).padding()
                        }
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    controls.frame(width: 300, alignment: .leading)
                    colorList.frame(maxWidth: .infinity, alignment: .leading)
                }
                if case .success(let result)? = traced, !result.warnings.isEmpty { NotesList(title: "Notes", notes: result.warnings) }
            }
        }
        // .task(id:) restarts whenever the options change, cancelling the previous trace if it hasn't finished.
        .task(id: options) {
            traced = nil
            let artwork = artwork, options = options
            let result = await Task.detached(priority: .userInitiated) { Result { try AutoDigitize.run(artwork, options: options) } }.value
            if !Task.isCancelled { traced = result }
        }
    }

    /// A captioned, fixed-size box, so the dialog doesn't jump around while tracing.
    private func picture<Content: View>(_ caption: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(Theme.body(12, weight: .bold))
            ZStack { Theme.ground; content() }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $options.colors, in: AutoDigitizeOptions.colorRange) {
                Text("Thread colors: \(options.colors)").font(Theme.body(13, weight: .semibold))
            }
            Text("Include the background color in this count. More colors keep more detail but make more parts.")
                .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Skip the background", isOn: $options.skipBackground).font(Theme.body(13, weight: .semibold))
            Text("Leaves out transparent areas, or the color around the image's edges, so the fabric shows through.")
                .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Leave out parts smaller than").font(Theme.body(13, weight: .semibold))
                Picker("Smallest part", selection: $options.smallestArea) {
                    ForEach(smallestChoices, id: \.self) { Text("\($0.formatted()) mm²").tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
        }
    }

    private var colorList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colors found").font(Theme.body(12, weight: .bold))
            if case .success(let result)? = traced {
                ForEach(result.colors, id: \.color.name) { found in
                    HStack(spacing: 8) {
                        Circle().fill(Color(nsColor: found.color.nsColor)).frame(width: 16, height: 16).overlay(Circle().strokeBorder(Theme.controlBorder))
                        Text(found.color.name).fontWeight(.semibold)
                        Text(found.background ? "background · left out" : "\(found.parts) part\(found.parts == 1 ? "" : "s") · \(Int(found.area.rounded()).formatted()) mm²")
                            .foregroundStyle(Theme.inkSecondary)
                    }.font(Theme.body(12))
                }
            } else {
                Text("Tracing…").font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

extension GuidedDialog {
    static var lastBorderWidth = 3.0
    /// The satin border dialog: returns each source shape's ID with its new border, or nil if the person cancelled.
    static func satinBorder(_ shapes: [RunObject], color: ThreadColor) -> [(source: UUID, border: RunObject)]? {
        var made: [(source: UUID, border: RunObject)] = []   // the dialog's closure writes the borders here before it closes
        let confirmed = run(width: 720) { finish in
            SatinBorderView(shapes: shapes, color: color, width: lastBorderWidth) { width, borders in
                lastBorderWidth = width; made = borders ?? []; finish(borders?.isEmpty == false)
            }
        }
        return confirmed ? made : nil
    }
}

/// Pick a border width and see the borders around the selected shapes; shapes that can't take one are explained.
struct SatinBorderView: View {
    let shapes: [RunObject]
    let color: ThreadColor
    @State var width: Double
    /// Called with the width and the borders (nil for Cancel).
    let done: (Double, [(source: UUID, border: RunObject)]?) -> Void
    /// The latest borders, problems and notes; nil while they are being worked out.
    @State private var built: (borders: [(source: UUID, border: RunObject)], notes: [String])?

    var body: some View {
        DialogFrame(eyebrow: "Satin border", title: "Add a satin border",
                    subtitle: "A satin column runs all the way around the outside edge of \(shapes.count == 1 ? "the selected shape" : "each selected shape"), centered on it, like the finished edge of a patch. Corners are rounded just enough for the satin to turn.",
                    primary: "Add Border",
                    finish: { add in
                        if !add { done(width, nil) } else if let built, !built.borders.isEmpty { done(width, built.borders) }
                    }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(value: $width, in: SatinBorder.widths, step: 0.5) {
                            Text("Width: \(width.formatted()) mm").font(Theme.body(13, weight: .semibold))
                        }
                        Text("Patch borders are usually 2.5–4 mm. Satin wider than about 7 mm can snag.")
                            .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Circle().fill(Color(nsColor: color.nsColor)).frame(width: 12, height: 12)
                            Text("Sews in \(color.name), the current thread, right after its shape.").foregroundStyle(Theme.inkSecondary)
                        }.font(Theme.body(12)).fixedSize(horizontal: false, vertical: true)
                    }.frame(width: 260, alignment: .leading)
                    ZStack {
                        Theme.ground
                        if let built { StitchThumbnail(objects: shapes + built.borders.map(\.border), label: "Preview of the satin border") } else { ProgressView().controlSize(.small) }
                    }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if let built, !built.notes.isEmpty { NotesList(title: "Notes", notes: built.notes) }
            }
        }
        // Rebuild the borders in the background whenever the width changes.
        .task(id: width) {
            built = nil
            let shapes = shapes, width = width, color = color
            let result = await Task.detached(priority: .userInitiated) { () -> (borders: [(source: UUID, border: RunObject)], notes: [String]) in
                var borders: [(source: UUID, border: RunObject)] = [], notes: [String] = []
                for shape in shapes {
                    do { let made = try SatinBorder.around(shape, width: width, color: color); borders.append((shape.id, made.object)); notes += made.warnings }
                    catch { notes.append(error.localizedDescription) }
                }
                return (borders, notes)
            }.value
            if !Task.isCancelled { built = result }
        }
    }
}


/// Who made each bundled embroidery font, and its license. Every font's full license text is included.
struct FontCreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Embroidery font credits").font(Theme.heading(18))
                Text("These fonts come from the Ink/Stitch embroidery font collection (github.com/inkstitch/embroidery-fonts) and ship unmodified. Thank you to their designers and digitizers.")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(EmbroideryFontLibrary.fonts, id: \.folder) { font in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(font.name).font(Theme.body(13, weight: .bold))
                        Text(font.license + (font.originalFont.map { " · based on \($0)" } ?? "")).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                        DisclosureGroup("License text") {
                            Text(font.licenseText).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }.font(Theme.body(12))
                    }
                }
            }.padding(18)
        }
        .frame(width: 420, height: 480)
        .foregroundStyle(Theme.ink)
    }
}


/// The two kinds of lettering font, with the icon and words used to tell them apart.
enum FontKind {
    case embroidery, system
    var symbol: String { self == .embroidery ? "scribble.variable" : "textformat" }
    var title: String { self == .embroidery ? "Embroidery font" : "System font" }
    var detail: String { self == .embroidery ? "Hand-digitized satin, made for sewing" : "Any font on this Mac, converted to fill or outline" }
}

/// A small label under the font list saying which kind of font is chosen: embroidery fonts in the accent color,
/// system fonts in plain gray.
struct FontKindBadge: View {
    let kind: FontKind
    var body: some View {
        HStack(spacing: 6) {
            Label(kind.title, systemImage: kind.symbol)
                .font(Theme.body(11, weight: .bold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(kind == .embroidery ? Theme.onAccent : Theme.ink)
                .background(kind == .embroidery ? Theme.accent : Theme.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(kind == .embroidery ? Color.clear : Theme.controlBorder))
            Text(kind.detail).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

extension GuidedDialog {
    /// The satin edge width and tack-down last used, so the next appliqué starts the same way.
    static var lastAppliqueWidth = Applique.defaultCoverWidth
    static var lastTackDown = Applique.TackDown.zigzag
    /// Make Appliqué: returns, for each shape that worked, the shape's id and its three parts; nil for Cancel.
    static func applique(_ shapes: [RunObject]) -> [(source: UUID, parts: [RunObject])]? {
        var made: [(source: UUID, parts: [RunObject])] = []   // the dialog's closure writes the result here before it closes
        let confirmed = run(width: 760) { finish in
            AppliqueView(shapes: shapes, width: lastAppliqueWidth, tackDown: lastTackDown) { width, tackDown, result in
                lastAppliqueWidth = width; lastTackDown = tackDown; made = result ?? []; finish(result?.isEmpty == false)
            }
        }
        return confirmed ? made : nil
    }
}

/// Make Appliqué: pick the satin edge width and the tack-down, see the result, and read what the machine will do.
struct AppliqueView: View {
    let shapes: [RunObject]
    @State var width: Double
    @State var tackDown: Applique.TackDown
    /// Called with the settings and the parts for each shape (nil for Cancel).
    let done: (Double, Applique.TackDown, [(source: UUID, parts: [RunObject])]?) -> Void
    /// The latest parts and notes; nil while they are being worked out.
    @State private var built: (parts: [(source: UUID, parts: [RunObject])], notes: [String])?

    var body: some View {
        DialogFrame(eyebrow: "Appliqué", title: "Make appliqué",
                    subtitle: "Sews a piece of fabric on in place of \(shapes.count == 1 ? "the selected shape" : "each selected shape"), instead of filling it with stitches. It uses the shape's own thread and takes its place in the sewing order.",
                    primary: "Make Appliqué",
                    finish: { make in
                        if !make { done(width, tackDown, nil) } else if let built, !built.parts.isEmpty { done(width, tackDown, built.parts) }
                    }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(value: $width, in: Applique.coverWidths, step: 0.5) {
                            Text("Satin edge: \(width.formatted()) mm").font(Theme.body(13, weight: .semibold))
                        }
                        Picker("Tack-down", selection: $tackDown) {
                            ForEach(Applique.TackDown.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 220).font(Theme.body(13))
                        VStack(alignment: .leading, spacing: 6) {
                            step(1, "Placement line, then the machine stops: lay your fabric over the line, covering it.")
                            step(2, "Tack-down holds the fabric, then it stops: trim the fabric close to the stitching.")
                            step(3, "The satin edge covers the cut edge.")
                        }.font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                    }.frame(width: 300, alignment: .leading)
                    ZStack {
                        Theme.ground
                        if let built { StitchThumbnail(objects: built.parts.flatMap(\.parts), label: "Preview of the appliqué") } else { ProgressView().controlSize(.small) }
                    }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if let built, !built.notes.isEmpty { NotesList(title: "Notes", notes: built.notes) }
            }
        }
        // Rebuild the parts in the background whenever the width or tack-down changes.
        .task(id: "\(width) \(tackDown.rawValue)") {
            built = nil
            let shapes = shapes, width = width, tackDown = tackDown
            let result = await Task.detached(priority: .userInitiated) { () -> (parts: [(source: UUID, parts: [RunObject])], notes: [String]) in
                var parts: [(source: UUID, parts: [RunObject])] = [], notes: [String] = []
                for shape in shapes {
                    do { let made = try Applique.make(from: shape, coverWidth: width, tackDown: tackDown, color: shape.color); parts.append((shape.id, made.objects)); notes += made.warnings }
                    catch { notes.append(error.localizedDescription) }
                }
                return (parts, notes)
            }.value
            if !Task.isCancelled { built = result }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)").font(Theme.body(11, weight: .bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
