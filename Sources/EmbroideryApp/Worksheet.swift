// The production worksheet: a printable sheet to keep beside the machine, with the design's size, stitch count,
// sewing time, a picture of the stitches (at actual size when it fits, to check placement on the garment) and
// the thread steps in order. The same SwiftUI page views are shown in a preview dialog and drawn into a PDF,
// which goes to the standard Mac print dialog (whose PDF menu also saves it as a file).
import AppKit
import PDFKit
import SwiftUI
import EmbroideryCore

/// Everything the worksheet shows, gathered when it opens.
struct WorksheetContent {
    var name: String
    var date = Date()
    var hoop: Hoop
    var plan: StitchPlan
    var summary: ProductionSummary
    /// The color behind the stitch picture, as 0xRRGGBB: the design's fabric color, or a pale linen.
    var fabric: Int
}

/// Where everything goes on paper. Sizes are in points (72 to the inch), the unit printers and PDFs use.
/// Every row has a fixed height, so the rows can be split into pages before anything is drawn.
struct WorksheetLayout {
    static let margin: CGFloat = 36   // half an inch all round
    static let pointsPerMillimeter: CGFloat = 72 / 25.4
    static let headerHeight: CGFloat = 132, continuedHeaderHeight: CGFloat = 44
    static let maximumPictureHeight: CGFloat = 330, picturePadding: CGFloat = 14, captionHeight: CGFloat = 26
    static let tableHeaderHeight: CGFloat = 34, rowHeight: CGFloat = 26
    static let notesHeadingHeight: CGFloat = 30, noteHeight: CGFloat = 26
    static let footerHeight: CGFloat = 22

    /// What one page holds: some of the thread steps and some of the notes (index ranges), and whether it's the
    /// first page (which has the header and picture).
    struct Page { var steps: Range<Int>; var notes: Range<Int>; var first: Bool }

    var pageSize: CGSize
    /// 1 means the picture is printed at actual size; smaller numbers shrink it to fit.
    var pictureScale: CGFloat
    /// The picture's height on the page, including its padding (it always spans the page's width).
    var pictureHeight: CGFloat
    var pages: [Page] = []

    init(summary: ProductionSummary, pageSize: CGSize) {
        self.pageSize = pageSize
        let width = pageSize.width - 2 * Self.margin
        let designWidth = summary.width * Self.pointsPerMillimeter, designHeight = summary.height * Self.pointsPerMillimeter
        let room = (width: width - 2 * Self.picturePadding, height: Self.maximumPictureHeight - 2 * Self.picturePadding)
        pictureScale = min(1, room.width / max(designWidth, 1), room.height / max(designHeight, 1))
        pictureHeight = designHeight * pictureScale + 2 * Self.picturePadding

        // Fill pages from the top: thread steps first, then notes. Each page's table repeats its column headings,
        // and the notes get a heading where they start.
        let usable = pageSize.height - 2 * Self.margin - Self.footerHeight
        var page = Page(steps: 0..<0, notes: 0..<0, first: true)
        var space = usable - Self.headerHeight - pictureHeight - Self.captionHeight
        func startNewPage() {
            pages.append(page)
            page = Page(steps: page.steps.upperBound..<page.steps.upperBound, notes: page.notes.upperBound..<page.notes.upperBound, first: false)
            space = usable - Self.continuedHeaderHeight
        }
        for _ in summary.steps.indices {
            if (page.steps.isEmpty ? Self.tableHeaderHeight : 0) + Self.rowHeight > space { startNewPage() }
            if page.steps.isEmpty { space -= Self.tableHeaderHeight }
            page.steps = page.steps.lowerBound..<page.steps.upperBound + 1; space -= Self.rowHeight
        }
        for _ in summary.warnings.indices {
            if (page.notes.isEmpty ? Self.notesHeadingHeight : 0) + Self.noteHeight > space { startNewPage() }
            if page.notes.isEmpty { space -= Self.notesHeadingHeight }
            page.notes = page.notes.lowerBound..<page.notes.upperBound + 1; space -= Self.noteHeight
        }
        pages.append(page)
    }
}

/// The worksheet's fixed print colors (paper is always white, whatever the screen's light or dark mode).
private enum Paper {
    static let ink = Color(nsColor: Theme.fixed(0x2E2520))
    static let secondary = Color(nsColor: Theme.fixed(0x6B5A4C))
    static let rule = Color(nsColor: Theme.fixed(0xE2D6C3))
    static let stripe = Color(nsColor: Theme.fixed(0xFAF6EF))
    static let stop = Color(nsColor: Theme.fixed(0xB0532F))
}

/// One printed page of the worksheet, at full paper size.
struct WorksheetPage: View {
    let content: WorksheetContent
    let layout: WorksheetLayout
    let index: Int
    let speed: Int
    private var page: WorksheetLayout.Page { layout.pages[index] }
    private var summary: ProductionSummary { content.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.first { header; picture } else { continuedHeader }
            if !page.steps.isEmpty { table }
            if !page.notes.isEmpty { notes }
            Spacer(minLength: 0)
            footer
        }
        .padding(WorksheetLayout.margin)
        .frame(width: layout.pageSize.width, height: layout.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Paper.ink)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRODUCTION WORKSHEET").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Paper.secondary)
            Text(content.name).font(Theme.heading(22)).lineLimit(1)
            Text("\(content.date.formatted(date: .long, time: .omitted)) · Hoop \(content.hoop.label) · \(summary.fabric.title)")
                .font(Theme.body(9)).foregroundStyle(Paper.secondary)
            HStack(spacing: 6) {
                tile("Size", Preferences.shared.unit.size(summary.width, summary.height))
                tile("Stitches", summary.stitchCount.formatted())
                tile("Thread steps", "\(summary.steps.count)")
                tile("Stops", "\(summary.stops)")
                tile("Trims", "\(summary.trims)")
                tile("Est. time", ProductionSummary.duration(summary.sewingMinutes(speed: speed)))
            }.padding(.top, 8)
        }.frame(height: WorksheetLayout.headerHeight, alignment: .topLeading)
    }
    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 7, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(Paper.secondary)
            Text(value).font(Theme.body(11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Paper.rule, lineWidth: 0.75))
    }

    /// The stitches, drawn like the canvas draws them, on the fabric color, with a + at the hoop's center.
    private var picture: some View {
        VStack(alignment: .leading, spacing: 0) {
            Canvas { context, size in
                let plan = content.plan, scale = WorksheetLayout.pointsPerMillimeter * layout.pictureScale
                let points = plan.commands.filter { $0.op == .stitch }.map(\.point)
                guard let first = points.first else { return }
                let low = points.reduce(first) { Point(min($0.x, $1.x), min($0.y, $1.y)) }
                let high = points.reduce(first) { Point(max($0.x, $1.x), max($0.y, $1.y)) }
                let middle = (low + high) * 0.5
                // Design y points up; SwiftUI's y points down.
                func spot(_ p: Point) -> CGPoint { CGPoint(x: size.width / 2 + (p.x - middle.x) * scale, y: size.height / 2 - (p.y - middle.y) * scale) }
                var path = Path(), thread = -1, previous: Point?
                func stroke() { if thread >= 0 && plan.threads.indices.contains(thread) { context.stroke(path, with: .color(Color(nsColor: plan.threads[thread].nsColor)), style: StrokeStyle(lineWidth: max(0.3, 1.1 * layout.pictureScale), lineCap: .round)) }; path = Path() }
                for command in plan.commands {
                    if command.op == .stitch {
                        if command.thread != thread { stroke(); thread = command.thread }
                        if let previous { path.move(to: spot(previous)); path.addLine(to: spot(command.point)) }
                    }
                    if command.op == .stitch || command.op == .jump { previous = command.point }
                }
                stroke()
                let center = spot(Point(0, 0))
                if CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4).contains(center) {
                    var cross = Path(); cross.move(to: CGPoint(x: center.x - 6, y: center.y)); cross.addLine(to: CGPoint(x: center.x + 6, y: center.y))
                    cross.move(to: CGPoint(x: center.x, y: center.y - 6)); cross.addLine(to: CGPoint(x: center.x, y: center.y + 6))
                    context.stroke(cross, with: .color(Paper.ink.opacity(0.6)), lineWidth: 0.6)
                }
            }
            .frame(height: layout.pictureHeight)
            .background(Color(nsColor: Theme.fixed(content.fabric)))
            .overlay(Rectangle().stroke(Paper.rule, lineWidth: 0.75))
            caption
        }
    }
    /// Under the picture: a scale bar (10 mm, or ½ in when working in inches) and what scale the picture is printed at.
    private var caption: some View {
        let inches = Preferences.shared.unit == .inches
        let barMillimeters = inches ? 12.7 : 10, barLabel = inches ? "½ in" : "10 mm"
        return HStack(spacing: 6) {
            Canvas { context, size in
                let length = barMillimeters * WorksheetLayout.pointsPerMillimeter * layout.pictureScale, y = size.height / 2
                var bar = Path(); bar.move(to: CGPoint(x: 0.5, y: y)); bar.addLine(to: CGPoint(x: 0.5 + length, y: y))
                for x in [0.5, 0.5 + length] { bar.move(to: CGPoint(x: x, y: y - 3)); bar.addLine(to: CGPoint(x: x, y: y + 3)) }
                context.stroke(bar, with: .color(Paper.ink), lineWidth: 0.75)
            }.frame(width: barMillimeters * WorksheetLayout.pointsPerMillimeter * layout.pictureScale + 1, height: 10)
            Text(barLabel).font(Theme.body(8, weight: .semibold))
            Text(layout.pictureScale >= 0.999 ? "Actual size: print at 100% and the bar measures \(barLabel). + marks the hoop center."
                                              : "Scaled to \(Int((layout.pictureScale * 100).rounded(.down)))% to fit the page. + marks the hoop center.")
                .font(Theme.body(8)).foregroundStyle(Paper.secondary)
        }.frame(height: WorksheetLayout.captionHeight)
    }

    private var continuedHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(content.name).font(Theme.heading(14)).lineLimit(1)
            Text("continued").font(Theme.body(9)).foregroundStyle(Paper.secondary)
        }.frame(height: WorksheetLayout.continuedHeaderHeight, alignment: .topLeading)
    }

    /// The thread steps, one row each, with an empty box to tick when the step is done.
    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("DONE").frame(width: 30, alignment: .leading)
                Text("STEP").frame(width: 28, alignment: .leading)
                Text("THREAD").frame(width: 200, alignment: .leading)
                Text("STITCHES").frame(width: 60, alignment: .trailing)
                Text("SEWS").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 7, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(Paper.secondary)
            .frame(height: WorksheetLayout.tableHeaderHeight, alignment: .bottom).padding(.bottom, 0)
            Paper.rule.frame(height: 0.75)
            ForEach(Array(page.steps), id: \.self) { index in row(summary.steps[index]) }
        }
    }
    private func row(_ step: ProductionSummary.Step) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).stroke(Paper.ink, lineWidth: 0.75).frame(width: 10, height: 10).frame(width: 30, alignment: .leading)
            Text("\(step.number)").font(Theme.body(10, weight: .bold)).frame(width: 28, alignment: .leading)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: step.color.nsColor)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Paper.ink.opacity(0.3), lineWidth: 0.5)).frame(width: 14, height: 14)
                // Name and color number (or hex for a plain color), with the brand underneath for chart threads.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(step.color.name).font(Theme.body(10, weight: .semibold)).lineLimit(1)
                        Text(step.color.code ?? String(format: "#%06X", step.color.hex)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Paper.secondary)
                    }
                    if let brand = step.color.brand { Text(brand).font(Theme.body(7.5)).foregroundStyle(Paper.secondary).lineLimit(1) }
                }
            }.frame(width: 200, alignment: .leading)
            Text(step.stitches.formatted()).font(Theme.body(10).monospacedDigit()).frame(width: 60, alignment: .trailing)
            HStack(spacing: 6) {
                Text(step.parts.joined(separator: ", ")).font(Theme.body(9)).foregroundStyle(Paper.secondary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if step.stopAfter {
                    Text("THEN STOP").font(.system(size: 7, weight: .bold, design: .rounded)).foregroundStyle(Color.white)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(Paper.stop, in: RoundedRectangle(cornerRadius: 3))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: WorksheetLayout.rowHeight)
        .background(step.number % 2 == 0 ? Paper.stripe : Color.white)
        .overlay(alignment: .bottom) { Paper.rule.frame(height: 0.5) }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTES").font(.system(size: 7, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(Paper.secondary)
                .frame(height: WorksheetLayout.notesHeadingHeight, alignment: .bottomLeading).padding(.bottom, 0)
            ForEach(Array(page.notes), id: \.self) { index in
                Text("• " + summary.warnings[index]).font(Theme.body(8.5)).lineLimit(2).frame(height: WorksheetLayout.noteHeight, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text("Sewing time estimated at \(speed.formatted()) stitches per minute, plus \(Int(ProductionSummary.secondsPerTrim)) s per trim and \(Int(ProductionSummary.secondsPerThreadChange / 60)) min per thread change or stop.")
            Spacer()
            Text("Page \(index + 1) of \(layout.pages.count)")
        }
        .font(Theme.body(7.5)).foregroundStyle(Paper.secondary)
        .frame(height: WorksheetLayout.footerHeight, alignment: .bottom)
    }

}

/// The preview dialog: the machine speed for the time estimate, and the pages as they'll print.
struct WorksheetView: View {
    let content: WorksheetContent
    let pageSize: CGSize
    /// The speed the dialog starts with; `speedChanged` hears each valid new speed.
    let initialSpeed: Int
    let speedChanged: (Int) -> Void
    let finish: (Bool) -> Void
    @State private var speedText = ""

    /// The typed speed, or nil while it isn't a whole number in range.
    private var typedSpeed: Int? { Int(speedText.filter(\.isNumber)).flatMap { ProductionSummary.speeds.contains($0) ? $0 : nil } }
    private var speed: Int { typedSpeed ?? initialSpeed }

    var body: some View {
        let layout = WorksheetLayout(summary: content.summary, pageSize: pageSize)
        let scale = min(1, 600 / pageSize.width)
        DialogFrame(eyebrow: "Production worksheet", title: content.name,
                    subtitle: "\(layout.pages.count) \(layout.pages.count == 1 ? "page" : "pages") · \(content.summary.steps.count) thread \(content.summary.steps.count == 1 ? "step" : "steps") · estimated sewing time \(ProductionSummary.duration(content.summary.sewingMinutes(speed: speed))). Print it, or choose PDF › Save as PDF in the print dialog.",
                    primary: "Print…", finish: finish) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Machine speed").font(Theme.body(13, weight: .semibold))
                    TextField("Speed", text: $speedText).textFieldStyle(.roundedBorder).frame(width: 70)
                    Stepper("Machine speed", onIncrement: { step(50) }, onDecrement: { step(-50) }).labelsHidden()
                    Text("stitches per minute").font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                    if typedSpeed == nil {
                        Text("Enter \(ProductionSummary.speeds.lowerBound)–\(ProductionSummary.speeds.upperBound.formatted())").font(Theme.body(12, weight: .semibold)).foregroundStyle(Color.orange)
                    }
                }
                Text("Use the speed your machine is set to. The estimate adds time for trims, thread changes and stops.")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(layout.pages.indices, id: \.self) { index in
                            WorksheetPage(content: content, layout: layout, index: index, speed: speed)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: pageSize.width * scale, height: pageSize.height * scale, alignment: .topLeading)
                                .background(Rectangle().fill(Color.white).shadow(color: .black.opacity(0.15), radius: 4, y: 1))   // a shadow on the paper's edge only
                        }
                    }.padding(10).frame(maxWidth: .infinity)
                }
                .frame(height: 480)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear { speedText = "\(initialSpeed)" }
        .onChange(of: speedText) { if let typedSpeed { speedChanged(typedSpeed) } }
    }
    private func step(_ amount: Int) {
        let next = min(max(speed + amount, ProductionSummary.speeds.lowerBound), ProductionSummary.speeds.upperBound)
        speedText = "\(next)"
    }
}

@MainActor enum WorksheetPrinter {
    /// Draws every page into one PDF document, in memory.
    static func pdf(content: WorksheetContent, pageSize: CGSize, speed: Int) -> Data? {
        let layout = WorksheetLayout(summary: content.summary, pageSize: pageSize)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for index in layout.pages.indices {
            // ImageRenderer turns a SwiftUI view into drawing commands; `render` hands them a PDF page to draw on.
            let renderer = ImageRenderer(content: WorksheetPage(content: content, layout: layout, index: index, speed: speed))
            renderer.render { _, draw in pdf.beginPDFPage(nil); draw(pdf); pdf.endPDFPage() }
        }
        pdf.closePDF()
        return data as Data
    }

    /// Opens the Mac print dialog for the worksheet. Pages print at 100% so the picture keeps its actual size.
    static func print(content: WorksheetContent, speed: Int) throws {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo   // copy() returns Any; it's always an NSPrintInfo
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        guard let data = pdf(content: content, pageSize: info.paperSize, speed: speed), let document = PDFDocument(data: data),
              let operation = document.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
            throw DesignError.invalid("The worksheet couldn't be prepared for printing.")
        }
        operation.jobTitle = content.name
        operation.run()
    }
}
