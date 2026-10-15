// Choose Thread from Chart (C): pick a real thread (brand, color number, name) from a thread chart for the current
// thread and the selection, or match every thread in the design to its closest chart thread at once.
// Charts are the machine palettes bundled with the app plus any GIMP palette (.gpl) files you import.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import EmbroideryCore

/// Where thread charts come from: the ones bundled in the app, then the ones you imported (kept in
/// ~/Library/Application Support/Embroidery/ThreadCharts). An imported chart with a bundled chart's name replaces it.
@MainActor enum ThreadChartLibrary {
    static var importedFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Embroidery/ThreadCharts", isDirectory: true)
    }
    /// Every chart, bundled first, each group in name order.
    static func charts() -> [ThreadChart] {
        let bundled = Bundle.main.resourceURL.map { ThreadChart.all(in: $0.appendingPathComponent("ThreadCharts")) } ?? []
        let imported = ThreadChart.all(in: importedFolder)
        return bundled.filter { chart in !imported.contains { $0.name == chart.name } } + imported
    }
    /// Checks that `url` is a readable palette, then keeps a copy so the chart is there next time. Returns the chart.
    static func importChart(from url: URL) throws -> ThreadChart {
        let data = try Data(contentsOf: url)
        guard data.count <= ThreadChart.maxBytes else { throw DesignError.invalid("That palette file is too large to be a thread chart.") }
        let chart = try ThreadChart.parse(String(decoding: data, as: UTF8.self), fallbackName: url.deletingPathExtension().lastPathComponent)
        try FileManager.default.createDirectory(at: importedFolder, withIntermediateDirectories: true)
        // Saved under the chart's own name (slashes and colons can't be in file names), so importing it again replaces it.
        let fileName = chart.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".gpl"
        try data.write(to: importedFolder.appendingPathComponent(fileName), options: .atomic)
        return chart
    }
}

/// What the dialog was closed with.
enum ThreadChartChoice {
    case use(ThreadColor)        // set the current thread and recolor the selection
    case matchAll(ThreadChart)   // match every thread in the design to this chart
}

extension GuidedDialog {
    /// Shows the thread chart dialog. `designThreads` are the design's threads in sewing order, for Match All's preview.
    static func threadChart(current: ThreadColor, designThreads: [ThreadColor]) -> ThreadChartChoice? {
        var choice: ThreadChartChoice?   // the dialog's closure writes the result here before it closes
        let confirmed = run(width: 760) { finish in
            ThreadChartView(current: current, designThreads: designThreads) { picked in choice = picked; finish(picked != nil) }
        }
        return confirmed ? choice : nil
    }
}

struct ThreadChartView: View {
    let current: ThreadColor
    let designThreads: [ThreadColor]
    let done: (ThreadChartChoice?) -> Void
    @State private var charts = ThreadChartLibrary.charts()
    @State private var chartName = Preferences.shared.data.threadChart ?? ""
    @State private var matchAll = false
    @State private var search = ""
    @State private var picked: ThreadColor?
    @State private var importError: String?

    /// The chosen chart: the one last used if it's still there, otherwise the first.
    private var chart: ThreadChart? { charts.first { $0.name == chartName } ?? charts.first }

    var body: some View {
        DialogFrame(eyebrow: "Thread chart", title: matchAll ? "Match every thread to a chart" : "Choose a thread",
                    subtitle: "Thread charts list real threads by brand and color number. The number goes on the production worksheet, the thread list and into PES files, so you know which spool to load.",
                    primary: matchAll ? "Match All" : "Use Thread",
                    finish: { confirm in
                        guard confirm, let chart else { done(nil); return }
                        if matchAll { done(.matchAll(chart)) } else if let thread = picked ?? chart.nearest(to: current.hex).first { done(.use(thread)) }
                    }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Picker("Chart", selection: Binding(get: { chart?.name ?? "" }, set: { chartName = $0; picked = nil })) {
                        ForEach(charts) { Text("\($0.name) (\($0.threads.count))").tag($0.name) }
                    }.frame(width: 340)
                    Button("Import Chart…") { importChart() }.buttonStyle(ThemedButtonStyle())
                        .help("Add a GIMP palette (.gpl) thread chart, such as the brand charts Ink/Stitch publishes")
                    Spacer()
                }.font(Theme.body(13))
                if let importError { Text(importError).font(Theme.body(12)).foregroundStyle(Color.red).fixedSize(horizontal: false, vertical: true) }
                Picker("Apply to", selection: $matchAll) {
                    Text("Current thread and selection").tag(false)
                    Text("Every thread in the design").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 420)
                if let chart {
                    if matchAll { matchPreview(chart) } else { chooser(chart) }
                } else {
                    Text("No thread charts found. Import a .gpl palette file to add one.").foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .onChange(of: chartName) { _, name in Preferences.shared.data.threadChart = name; Preferences.shared.save() }
    }

    /// Picking one thread: the closest few to the current thread, then the whole chart (filtered by the search box).
    private func chooser(_ chart: ThreadChart) -> some View {
        let selected = picked ?? chart.nearest(to: current.hex).first
        let shown = search.isEmpty ? chart.threads : chart.threads.filter { ($0.name + " " + ($0.code ?? "")).localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("CLOSEST TO").font(Theme.caption).tracking(1).foregroundStyle(Theme.inkSecondary)
                swatch(current, size: 12)
                Text(current.chartLabel.map { "\(current.name) (\($0))" } ?? current.name).font(Theme.body(12, weight: .semibold))
            }
            HStack(spacing: 8) { ForEach(chart.nearest(to: current.hex, count: 4), id: \.self) { tile($0, selected: $0 == selected) } }
            TextField("Search by name or number", text: $search).textFieldStyle(.roundedBorder).frame(width: 260)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(shown, id: \.self) { tile($0, selected: $0 == selected) }
                }.padding(2)
            }.frame(height: 250)
            if shown.isEmpty { Text("No threads in this chart match “\(search)”.").font(Theme.body(12)).foregroundStyle(Theme.inkSecondary) }
        }
    }

    /// Match All: each of the design's threads next to the chart thread it will become.
    private func matchPreview(_ chart: ThreadChart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(designThreads, id: \.self) { thread in
                        HStack(spacing: 8) {
                            swatch(thread, size: 14); Text(thread.name).lineLimit(1).frame(width: 150, alignment: .leading)
                            Image(systemName: "arrow.right").foregroundStyle(Theme.inkSecondary)
                            if let match = chart.nearest(to: thread.hex).first {
                                swatch(match, size: 14); Text("\(match.code ?? "") \(match.name)").fontWeight(.semibold).lineLimit(1)
                            }
                        }.font(Theme.body(12))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 220)
            Text(designThreads.isEmpty ? "This design has no threads yet." : "Each thread becomes the closest-looking thread in \(chart.name). Locked objects keep their thread. You can undo this.")
                .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One chart thread as a clickable tile: its color, number and name. Double-click uses it straight away.
    private func tile(_ thread: ThreadColor, selected: Bool) -> some View {
        HStack(spacing: 7) {
            swatch(thread, size: 18)
            Text(thread.code ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkSecondary)
            Text(thread.name).font(Theme.body(12)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 5).frame(minWidth: 150, alignment: .leading)
        .background(selected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Theme.accent : Theme.controlBorder.opacity(0.6)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { done(.use(thread)) }
        .onTapGesture { picked = thread }
        .help(thread.chartLabel.map { "\($0) · \(thread.name)" } ?? thread.name)
    }

    private func swatch(_ thread: ThreadColor, size: CGFloat) -> some View {
        Circle().fill(Color(nsColor: thread.nsColor)).frame(width: size, height: size).overlay(Circle().strokeBorder(Color.black.opacity(0.25)))
    }

    /// Import Chart…: pick a .gpl file; on success it's added to the list and chosen.
    private func importChart() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gpl") ?? .data]
        panel.message = "Choose a GIMP palette (.gpl) thread chart."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let chart = try ThreadChartLibrary.importChart(from: url)
            charts = ThreadChartLibrary.charts(); chartName = chart.name; picked = nil; importError = nil
        } catch { importError = "Couldn't import that chart: \(error.localizedDescription)" }
    }
}
