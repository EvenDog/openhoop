// Hoops of your own: named once in Settings › New designs › My hoops, then listed at the top of every hoop menu.
// Also the hoop menus' shared items, so the Design panel's menu and the one in Settings always list the same hoops.
import SwiftUI
import EmbroideryCore

/// The items of a hoop menu: your own hoops first, then the common hoops by brand, then a way to add or edit your own.
/// `choose` gets the hoop picked.
struct HoopMenuItems: View {
    @ObservedObject var preferences = Preferences.shared
    var choose: (Hoop) -> Void
    var body: some View {
        if !preferences.myHoops.isEmpty {
            Section("My hoops") {
                ForEach(preferences.myHoops, id: \.self) { hoop in Button(hoop.label) { choose(hoop) } }
            }
        }
        ForEach(HoopPreset.brands, id: \.self) { brand in
            Section(brand) {
                ForEach(HoopPreset.all.filter { $0.brand == brand }) { preset in Button(preset.menuTitle) { choose(preset.hoop) } }
            }
        }
        Divider()
        Button(preferences.myHoops.isEmpty ? "Add a Hoop of My Own…" : "Edit My Hoops…") {
            SettingsNavigation.shared.page = .newDesigns
            AppDelegate.shared.showSettings()
        }
    }
}

/// Settings › New designs › My hoops: each hoop of your own with its name, sewing-area size and shape, and Add Hoop.
struct MyHoopsCard: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        SettingsCard(caption: "My hoops") {
            // Names are unique, so they identify the rows.
            ForEach(Array(preferences.myHoops.enumerated()), id: \.element.name) { index, hoop in
                if index > 0 { RowDivider() }
                MyHoopRow(hoop: hoop)
            }
            if !preferences.myHoops.isEmpty { RowDivider() }
            HStack(spacing: 16) {
                Text("Hoops you add here appear at the top of every hoop menu. The size is the area the machine can sew in.")
                    .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Add Hoop") { add() }.buttonStyle(ThemedButtonStyle())
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
    /// Adds a 100 × 100 mm hoop named "My hoop" (numbered if that's taken), ready to rename and resize.
    private func add() {
        let name = Preferences.uniqueHoopName("My hoop", among: preferences.myHoops.compactMap(\.name)) ?? "My hoop"
        preferences.setMyHoops(preferences.myHoops + [Hoop(width: 100, height: 100, name: name)])
    }
}

/// One of your hoops: its name (saved when you press Return or leave the field), width × height, oval, and delete.
private struct MyHoopRow: View {
    let hoop: Hoop
    @ObservedObject var preferences = Preferences.shared
    @State private var draftName = ""
    @FocusState private var editingName: Bool
    var body: some View {
        HStack(spacing: 6) {
            TextField("Name", text: $draftName).textFieldStyle(.roundedBorder).frame(width: 190)
                .focused($editingName)
                .onSubmit(commitName)
                .onChange(of: editingName) { _, editing in if !editing { commitName() } }
            Spacer(minLength: 12)
            NumberField(value: hoop.width, range: 1...1000, unit: preferences.unit, commit: { value in update { $0.width = value } }, focusCanvas: {}).frame(width: 64, height: 22)
            Text("×").foregroundStyle(Theme.inkSecondary)
            NumberField(value: hoop.height, range: 1...1000, unit: preferences.unit, commit: { value in update { $0.height = value } }, focusCanvas: {}).frame(width: 64, height: 22)
            Text(preferences.unit.symbol).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).frame(width: 22, alignment: .leading)
            Toggle("Oval", isOn: Binding(get: { hoop.oval }, set: { oval in update { $0.oval = oval } })).toggleStyle(.checkbox).font(Theme.body(12))
            Button { preferences.setMyHoops(preferences.myHoops.filter { $0 != hoop }) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete this hoop. Designs already using it keep their size.")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .onAppear { draftName = hoop.name ?? "" }
    }
    /// Changes this hoop in the saved list.
    private func update(_ change: (inout Hoop) -> Void) {
        var hoops = preferences.myHoops
        guard let index = hoops.firstIndex(of: hoop) else { return }
        change(&hoops[index]); preferences.setMyHoops(hoops)
    }
    /// Saves the typed name: tidied and made unique, or the old name back if it was left empty.
    private func commitName() {
        let others = preferences.myHoops.filter { $0 != hoop }.compactMap(\.name)
        guard let name = Preferences.uniqueHoopName(draftName, among: others) else { draftName = hoop.name ?? ""; return }
        draftName = name
        if name != hoop.name { update { $0.name = name } }
    }
}
