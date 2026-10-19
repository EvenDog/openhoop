// The Threads panel's thread library: a chart menu (the basic colors, the machine palettes, the thread brands and
// the charts you imported), a search box, and every thread of the chosen chart as a swatch. Clicking a swatch sets
// the current thread and recolors the selection. The chart chosen here is the one Choose Thread from Chart opens with.
import SwiftUI
import EmbroideryCore

enum ThreadLibrary {
    /// What the eight basic colors are called in the chart menu. Choosing them stores no chart at all.
    static let basicName = "Basic colors"

    /// The threads the panel shows: the named chart's, or the basic colors when `name` isn't one of `charts`;
    /// with `search`, only those whose name or color number contains it.
    static func threads(chart name: String?, search: String, charts: [ThreadChart]) -> [ThreadColor] {
        let all = charts.first { $0.name == name }?.threads ?? ThreadColor.palette
        guard !search.isEmpty else { return all }
        return all.filter { ($0.name + " " + ($0.code ?? "")).localizedCaseInsensitiveContains(search) }
    }
}

struct ThreadLibraryView: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// The swatches' size, and how tall the scrolling grid must be and may grow (nil: as tall as the panel allows).
    var swatchSize: CGFloat = 24
    var minHeight: CGFloat? = nil
    var maxHeight: CGFloat? = nil
    @State private var charts = ThreadChartLibrary.charts()
    @State private var importedNames = ThreadChartLibrary.importedNames()
    @State private var search = ""

    /// The chosen chart, if the remembered name is one (otherwise the basic colors show).
    private var chart: ThreadChart? { charts.first { $0.name == preferences.data.threadChart } }

    var body: some View {
        let shown = ThreadLibrary.threads(chart: preferences.data.threadChart, search: search, charts: charts)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Picker("Chart", selection: Binding(get: { chart?.name ?? ThreadLibrary.basicName },
                                                   set: { name in preferences.data.threadChart = name == ThreadLibrary.basicName ? nil : name; preferences.save(); search = "" })) {
                    Text(ThreadLibrary.basicName).tag(ThreadLibrary.basicName)
                    ForEach(ThreadChartLibrary.sections(charts, imported: importedNames), id: \.title) { section in
                        Section(section.title) { ForEach(section.charts) { Text("\($0.name) (\($0.threads.count))").tag($0.name) } }
                    }
                }.labelsHidden().help("The thread chart shown below: a real brand's threads by color number, a machine's palette, or the basic colors")
                Button { AppDelegate.shared.perform(.threadChart) } label: {
                    Image(systemName: "swatchpalette").font(.system(size: 13)).frame(width: 24, height: 22)
                }.buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
                .help("Choose Thread from Chart (\(preferences.label(.threadChart))): the chart threads closest to the current one, or match every thread in the design at once")
            }.font(Theme.body(12))
            if chart != nil {
                TextField("Search by name or number", text: $search).textFieldStyle(.roundedBorder).font(Theme.body(12))
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchSize + 6), spacing: 6)], alignment: .leading, spacing: 8) {
                    ForEach(shown, id: \.self) { color in swatchButton(color) }
                }.padding(3)
            }.frame(minHeight: minHeight, maxHeight: maxHeight)
            if shown.isEmpty { Text("No threads in this chart match “\(search)”.").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary) }
        }
        .foregroundStyle(Theme.ink)
        // Choose Thread from Chart can import a chart or switch to another, so the list is read again after it.
        .onChange(of: preferences.data.threadChart) { _, _ in charts = ThreadChartLibrary.charts(); importedNames = ThreadChartLibrary.importedNames() }
    }

    /// One thread: a colored circle, ringed when it's the current thread; its name and number on hover.
    private func swatchButton(_ color: ThreadColor) -> some View {
        Button {
            state.currentColor = color; state.editSelected("Thread Color") { $0.color = color }; state.focusCanvas()
        } label: {
            Circle().fill(Color(nsColor: color.nsColor)).frame(width: swatchSize, height: swatchSize).overlay(Circle().strokeBorder(Theme.controlBorder))
                .overlay(Circle().strokeBorder(Theme.ink.opacity(state.currentColor == color ? 0.85 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help("\(color.chartLabel.map { "\(color.name) · \($0)" } ?? color.name): set the current thread and recolor the selection")
    }
}
