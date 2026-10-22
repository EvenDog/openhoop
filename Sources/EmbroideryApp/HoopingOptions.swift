// The Hoopings tool's choices at the top of Properties (ToolOptions.swift): a multi-hooped design's hoopings in
// sewing order and what each one sews, buttons to add, lay out and remove them, what fits no hooping, the
// alignment marks, and saving the hoopings for the machine. With multi-hooping off, a button to turn it on.
import SwiftUI
import EmbroideryCore

struct HoopingOptions: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolCaption(text: "MULTI-HOOPING")
            if let layout = state.design.multiHooping {
                Text("\(state.design.hoop.label). Each hooping is sewn as its own file, in this order.")
                    .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(layout.hoopings.indices, id: \.self) { row($0) }
                problems
                HStack(spacing: 4) {
                    Text("Add").font(Theme.body(12, weight: .semibold))
                    addButton("arrow.left", "Add a hooping to the left", dx: -1, dy: 0)
                    addButton("arrow.right", "Add a hooping to the right", dx: 1, dy: 0)
                    addButton("arrow.up", "Add a hooping above", dx: 0, dy: 1)
                    addButton("arrow.down", "Add a hooping below", dx: 0, dy: -1)
                }
                HStack(spacing: 6) {
                    Button("Auto layout") { state.autoLayoutHoopings() }.buttonStyle(ThemedButtonStyle())
                        .help("Put in the fewest hoopings that cover the design, overlapping by at least \(preferences.unit.short(Design.hoopingOverlap))")
                    Button("Remove") { state.removeHooping() }.buttonStyle(ThemedButtonStyle()).disabled(layout.hoopings.count < 2)
                        .help("Remove the picked hooping (or the last one)")
                }
                Divider()
                Toggle("Sew alignment marks", isOn: Binding(get: { layout.marks != nil }, set: { on in state.edit("Alignment Marks") { $0.multiHooping?.marks = on ? .box : nil } }))
                    .font(Theme.body(12)).toggleStyle(.checkbox)
                if let marks = layout.marks {
                    Picker("Style", selection: Binding(get: { marks }, set: { style in state.edit("Alignment Mark Style") { $0.multiHooping?.marks = style } })) {
                        ForEach(AlignmentMarkStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).fixedSize().font(Theme.body(12))
                }
                if !preferences.isPro {
                    Text("Small marks where two hoopings overlap. The next hooping sews the same marks first, then stops, so you can check they sit on the first ones before it sews on.")
                        .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Button("Save Hoopings for Machine…") { AppDelegate.shared.perform(.exportMachine) }
                    .buttonStyle(ThemedButtonStyle(prominent: true)).disabled(!(state.hoopingAssignment?.unplaced.isEmpty ?? false))
                    .help("Save one machine file per hooping, and a hooping sheet to print (\(preferences.label(.exportMachine)))")
            } else {
                Text("Sew a design bigger than your hoop in several hoopings, re-hooping the fabric between them.")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                Button("Turn on multi-hooping") { state.setMultiHooping(true) }.buttonStyle(ThemedButtonStyle(prominent: true))
            }
        }
        Divider()
    }
    /// One hooping in the list: its number in its canvas color, and what it sews. Clicking it fades what the others sew.
    private func row(_ index: Int) -> some View {
        let picked = state.selectedHooping == index
        return HStack(spacing: 10) {
            Text("\(index + 1)").font(Theme.body(12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Color(nsColor: Theme.Canvas.hooping(index)), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Hooping \(index + 1)").font(Theme.body(12, weight: .semibold))
                Text(summary(index)).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6).background(picked ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { state.selectedHooping = picked ? nil : index; state.canvas?.needsDisplay = true }
        .help(picked ? "Click to show every hooping again" : "Click to fade what the other hoopings sew")
    }
    /// What a hooping sews: "1,234 stitches · 2 threads", from the latest stitches.
    private func summary(_ index: Int) -> String {
        guard let ids = state.hoopingAssignment?.objects[safe: index], !ids.isEmpty else { return "Nothing to sew" }
        let stitches = ids.reduce(0) { $0 + (state.stitchCounts[$1] ?? 0) }
        let threads = Set(state.design.objects.filter { ids.contains($0.id) }.map(\.color)).count
        return "\(stitches.formatted()) stitches · \(threads) thread\(threads == 1 ? "" : "s")"
    }
    /// What needs fixing (objects that fit no hooping) and what to know (objects now sewn on top of others), in red
    /// and orange.
    @ViewBuilder private var problems: some View {
        if let assignment = state.hoopingAssignment {
            let unplaced = Self.names(assignment.unplaced.compactMap { id in state.design.objects.first { $0.id == id }?.name })
            if !unplaced.isEmpty {
                let many = unplaced.count > 1 || unplaced[0].hasSuffix("more")
                Label("\(unplaced.joined(separator: ", ")) fit\(many ? "" : "s") no hooping. Move a hooping, add one, or make \(many ? "them" : "it") smaller.", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.body(11)).foregroundStyle(Color.red).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Self.names(assignment.warnings), id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.circle").font(Theme.body(11)).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// `names` without the "(part 2)" that letters' parts carry, each once, at most three and then "and 4 more".
    static func names(_ names: [String]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for name in names {
            let plain = name.replacingOccurrences(of: #" \(part \d+\)"#, with: "", options: .regularExpression)
            if seen.insert(plain).inserted { result.append(plain) }
        }
        return result.count > 3 ? Array(result.prefix(3)) + ["and \(result.count - 3) more"] : result
    }
    private func addButton(_ symbol: String, _ help: String, dx: Double, dy: Double) -> some View {
        Button { state.addHooping(dx: dx, dy: dy) } label: { Image(systemName: symbol).frame(width: 18) }
            .buttonStyle(ThemedButtonStyle()).help(help)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension EditorState {
    /// Turns multi-hooping on, with hoopings laid out to cover the design (one in the middle if nothing sews yet), or
    /// off, back to one hooping. Either way the view zooms to show where stitches may go.
    func setMultiHooping(_ on: Bool) {
        let hoopings = design.autoHoopings(plan: plan)
        edit(on ? "Multi-hooping" : "Single Hooping") { $0.multiHooping = on ? MultiHooping(hoopings: hoopings.isEmpty ? [Hooping(center: Point(0, 0))] : hoopings) : nil }
        selectedHooping = nil
        canvas?.fit()
    }
    /// Adds a hooping beside the picked one (or the last): `dx` and `dy` say which side (-1, 0 or 1), and it overlaps
    /// its neighbour by `Design.hoopingOverlap`. The new one is picked.
    func addHooping(dx: Double, dy: Double) {
        guard let hoopings = design.multiHooping?.hoopings, let base = hoopings[safe: selectedHooping ?? hoopings.count - 1] else { return }
        let step = Point((design.hoop.width - Design.hoopingOverlap) * dx, (design.hoop.height - Design.hoopingOverlap) * dy)
        guard hoopings.count < MultiHooping.limit else { status = "A design can have at most \(MultiHooping.limit) hoopings."; return }
        edit("Add Hooping") { $0.multiHooping?.hoopings.append(Hooping(center: base.center + step)) }
        selectedHooping = hoopings.count
        canvas?.fit()
    }
    /// Removes the picked hooping (or the last one), keeping at least one.
    func removeHooping() {
        guard let hoopings = design.multiHooping?.hoopings, hoopings.count > 1 else { return }
        let index = selectedHooping.flatMap { hoopings.indices.contains($0) ? $0 : nil } ?? hoopings.count - 1
        edit("Remove Hooping") { _ = $0.multiHooping?.hoopings.remove(at: index) }
        selectedHooping = nil
        canvas?.fit()
    }
    /// Auto Layout: replaces the hoopings with the fewest that cover the design (MultiHooping.swift).
    func autoLayoutHoopings() {
        let hoopings = design.autoHoopings(plan: plan)
        guard !hoopings.isEmpty else { status = "Nothing sews yet, so there's nothing to lay hoopings out around."; return }
        edit("Auto Layout Hoopings") { $0.multiHooping?.hoopings = hoopings }
        selectedHooping = nil
        canvas?.fit()
        status = "\(hoopings.count) hooping\(hoopings.count == 1 ? "" : "s") cover the design."
    }
}
