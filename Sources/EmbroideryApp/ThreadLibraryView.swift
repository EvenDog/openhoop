// The Threads panel's thread library: a chart menu (the basic colors, the machine palettes, the thread brands and
// the charts you imported), a search box, and every thread of the chosen chart as a swatch. Clicking a swatch sets
// the current thread, recolors the selection and adds the thread to the design's palette (PaletteRow.swift), which
// sits above the library while it's docked here. The chart chosen here is the one Choose Thread from Chart opens with.
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
    /// How the threads are laid out: a grid of swatches, or a list of rows (swatch, name, number) in this many columns.
    enum Layout { case grid, list(columns: Int) }
    var layout = Layout.grid
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
            if !preferences.paletteUnderCanvas { PaletteRow(state: state, placement: .docked); Divider().padding(.vertical, 2) }
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
                // Moves the design's palette between the strip under the canvas (highlighted) and the top of this panel.
                Button { AppDelegate.shared.perform(.paletteUnderCanvas) } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled").font(.system(size: 12)).frame(width: 24, height: 22)
                        .background(preferences.paletteUnderCanvas ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).foregroundStyle(preferences.paletteUnderCanvas ? Theme.accent : Theme.inkSecondary)
                .help(preferences.paletteUnderCanvas ? "The palette is under the canvas. Click to dock it at the top of this panel." : "Pop the palette out into a strip under the canvas")
            }.font(Theme.body(12))
            if chart != nil {
                TextField("Search by name or number", text: $search).textFieldStyle(.roundedBorder).font(Theme.body(12))
            }
            ScrollView {
                switch layout {
                case .grid:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchSize + 6), spacing: 6)], alignment: .leading, spacing: 8) {
                        ForEach(shown, id: \.self) { color in swatchButton(color) }
                    }.padding(3)
                case .list(let columns):
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), alignment: .leading, spacing: 2) {
                        ForEach(shown, id: \.self) { color in rowButton(color) }
                    }.padding(3)
                }
            }.frame(minHeight: minHeight, maxHeight: maxHeight)
            if shown.isEmpty { Text("No threads in this chart match “\(search)”.").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary) }
        }
        .foregroundStyle(Theme.ink)
        // Choose Thread from Chart can import a chart or switch to another, so the list is read again after it.
        .onChange(of: preferences.data.threadChart) { _, _ in charts = ThreadChartLibrary.charts(); importedNames = ThreadChartLibrary.importedNames() }
    }

    /// Makes `color` the current thread, recolors the selection and keeps it in the design's palette.
    private func choose(_ color: ThreadColor) { state.chooseThread(color); state.focusCanvas() }
    private func hint(_ color: ThreadColor) -> String {
        "\(color.chartLabel.map { "\(color.name) · \($0)" } ?? color.name): set the current thread and recolor the selection"
    }
    /// A colored circle, ringed when `color` is the current thread.
    private func swatch(_ color: ThreadColor, size: CGFloat) -> some View {
        Circle().fill(Color(nsColor: color.nsColor)).frame(width: size, height: size).overlay(Circle().strokeBorder(Theme.controlBorder))
            .overlay(Circle().strokeBorder(Theme.ink.opacity(state.currentColor == color ? 0.85 : 0), lineWidth: 2).padding(-3))
    }
    /// One thread in the grid: its swatch; its name and number on hover.
    private func swatchButton(_ color: ThreadColor) -> some View {
        Button { choose(color) } label: { swatch(color, size: swatchSize) }.buttonStyle(.plain).help(hint(color))
    }
    /// One thread in the list: its swatch, name and number in a row, the row tinted when it's the current thread.
    private func rowButton(_ color: ThreadColor) -> some View {
        Button { choose(color) } label: {
            HStack(spacing: 6) {
                swatch(color, size: 11).padding(.leading, 3)
                Text(color.name).font(Theme.body(11)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
                if let code = color.code { Text(code).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.inkSecondary) }
            }
            .frame(height: 20).padding(.trailing, 4)
            .background(state.currentColor == color ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(hint(color))
    }
}
