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
}

/// The shared look of every dialog: a small label, a serif title and subtitle, the body, then Cancel and the main button.
/// Return presses the main button and Escape presses Cancel.
struct DialogFrame<Content: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var primary: String
    /// The other button's label; it closes the dialog as Cancel does.
    var secondary = "Cancel"
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
                Button(secondary) { finish(false) }.keyboardShortcut(.cancelAction).buttonStyle(ThemedButtonStyle())
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
            fact("Size", Preferences.shared.unit.size(report.width, report.height))
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
    /// The space left around the drawing, in points.
    var padding = 14.0
    /// False draws the stitches straight onto whatever is behind, without the cream fabric patch.
    var onFabric = true
    var body: some View {
        Canvas { context, size in
            let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
            let pad = padding
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
        .background(onFabric ? Theme.ground : Color.clear, in: RoundedRectangle(cornerRadius: 14))
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
                    subtitle: "Size: \(Preferences.shared.unit.size(check.width, check.height)). Saving as \(check.fileName).",
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

/// The embroidery fonts that ship inside the app (Resources/EmbroideryFonts), read once.
enum EmbroideryFontLibrary {
    static let fonts: [EmbroideryFont] = Bundle.main.resourceURL.map { EmbroideryFont.all(in: $0.appendingPathComponent("EmbroideryFonts")) } ?? []
    static func font(_ folder: String) -> EmbroideryFont? { fonts.first { $0.folder.lastPathComponent == folder } }
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
                        Text("Patch borders are usually 2.5–4 mm. Satin stitches over 12 mm can snag.")
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

extension GuidedDialog {
    static var lastOutlineOptions = OutlineOptions()
    /// The Outlines & Offsets dialog: returns each source shape's ID with its new outlines, or nil if the person cancelled.
    static func outlinesOffsets(_ shapes: [RunObject], color: ThreadColor) -> [(source: UUID, outlines: [RunObject])]? {
        var made: [(source: UUID, outlines: [RunObject])] = []   // the dialog's closure writes the outlines here before it closes
        let confirmed = run(width: 760) { finish in
            OutlinesOffsetsView(shapes: shapes, color: color, options: lastOutlineOptions) { options, outlines in
                lastOutlineOptions = options; made = outlines ?? []; finish(outlines != nil)
            }
        }
        return confirmed ? made : nil
    }
}

/// Pick which outlines to add (on the edge, and up to two offsets) and their stitch, and see them around the
/// selected shapes. Outlines that don't fit are explained.
struct OutlinesOffsetsView: View {
    let shapes: [RunObject]
    let color: ThreadColor
    @State var options: OutlineOptions
    /// Called with the options and the outlines (nil for Cancel).
    let done: (OutlineOptions, [(source: UUID, outlines: [RunObject])]?) -> Void
    /// The latest outlines and notes; nil while they are being worked out.
    @State private var built: (outlines: [(source: UUID, outlines: [RunObject])], notes: [String])?
    /// Each offset's distance, kept while it's switched off so switching it back on brings it back.
    @State private var distances: [Double]
    init(shapes: [RunObject], color: ThreadColor, options: OutlineOptions, done: @escaping (OutlineOptions, [(source: UUID, outlines: [RunObject])]?) -> Void) {
        self.shapes = shapes; self.color = color; self.done = done
        _options = State(initialValue: options)
        _distances = State(initialValue: [options.offsets[0] ?? 3, options.offsets[1] ?? 6])
    }

    var body: some View {
        DialogFrame(eyebrow: "Outlines & offsets", title: "Add outlines and offsets",
                    subtitle: "New outlines around \(shapes.count == 1 ? "the selected shape" : "each selected shape"): one right on its edge, and up to two more a set distance outside or inside it. Each is an ordinary outline you can recolor or reshape.",
                    primary: "Add Outlines",
                    finish: { add in
                        if !add { done(options, nil) } else if let built, built.outlines.contains(where: { !$0.outlines.isEmpty }) { done(options, built.outlines) }
                    }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Outline on the edge", isOn: $options.edge).font(Theme.body(13, weight: .semibold))
                        offsetRow(0); offsetRow(1)
                        Text("Offsets go outside the shape. Below 0 they go inside it.")
                            .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        Picker("Corners", selection: $options.sharpCorners) { Text("Sharp").tag(true); Text("Rounded").tag(false) }
                            .pickerStyle(.segmented).font(Theme.body(13, weight: .semibold))
                        Picker("Stitch", selection: $options.stitch) { ForEach(OpenShapeStitch.allCases, id: \.self) { Text($0.title).tag($0) } }
                            .font(Theme.body(13, weight: .semibold))
                        if options.stitch == .satin {
                            Stepper(value: $options.satinWidth, in: SatinLine.widths, step: 0.5) {
                                Text("Satin width: \(options.satinWidth.formatted()) mm").font(Theme.body(13, weight: .semibold))
                            }
                        }
                        Toggle("Outline holes too", isOn: $options.holes).font(Theme.body(13, weight: .semibold))
                        HStack(spacing: 6) {
                            Circle().fill(Color(nsColor: color.nsColor)).frame(width: 12, height: 12)
                            Text("Sews in \(color.name), the current thread, right after its shape.").foregroundStyle(Theme.inkSecondary)
                        }.font(Theme.body(12)).fixedSize(horizontal: false, vertical: true)
                    }.frame(width: 300, alignment: .leading)
                    ZStack {
                        Theme.ground
                        if let built { StitchThumbnail(objects: shapes + built.outlines.flatMap(\.outlines), label: "Preview of the outlines") } else { ProgressView().controlSize(.small) }
                    }.frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if let built, !built.notes.isEmpty { NotesList(title: "Notes", notes: built.notes) }
            }
        }
        // Rebuild the outlines in the background whenever an option changes.
        .task(id: options) {
            built = nil
            let shapes = shapes, options = options, color = color
            let result = await Task.detached(priority: .userInitiated) { () -> (outlines: [(source: UUID, outlines: [RunObject])], notes: [String]) in
                var outlines: [(source: UUID, outlines: [RunObject])] = [], notes: [String] = []
                guard options.makesSomething else { return ([], ["Switch on the edge outline or an offset."]) }
                for shape in shapes {
                    do { let made = try OutlinesOffsets.around(shape, options: options, color: color); outlines.append((shape.id, made.objects)); notes += made.warnings }
                    catch { notes.append(error.localizedDescription) }
                }
                return (outlines, notes)
            }.value
            if !Task.isCancelled { built = result }
        }
    }

    /// "Offset 1" or "Offset 2": a switch, and its distance from the edge in the person's unit.
    private func offsetRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Toggle("Offset \(index + 1)", isOn: Binding(get: { options.offsets[index] != nil },
                                                       set: { options.offsets[index] = $0 ? distances[index] : nil }))
                .font(Theme.body(13, weight: .semibold))
            Spacer(minLength: 8)
            NumberField(value: options.offsets[index] ?? distances[index], range: OutlinesOffsets.distances, unit: Preferences.shared.unit,
                        commit: { distances[index] = $0; options.offsets[index] = $0 }, focusCanvas: {})
                .frame(width: 70, height: 22)
            Text(Preferences.shared.unit.symbol).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
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
