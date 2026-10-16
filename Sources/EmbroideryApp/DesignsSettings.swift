// Settings › Designs: what blank new designs and newly drawn objects start with, and how fast the machine sews (for
// time estimates). Each design can still change its own fabric and hoop afterwards, in the Design panel.
import SwiftUI
import EmbroideryCore

struct DesignsSettings: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Designs").font(Theme.heading(28))
                card("New designs", note: "What a blank new design starts with. Each design can change its own in the Design panel.") {
                    HStack {
                        Text("Fabric").font(Theme.body(13)); Spacer()
                        Picker("Fabric", selection: Binding(get: { preferences.data.newDesignFabric ?? .woven }, set: { preferences.data.newDesignFabric = $0; preferences.save() })) {
                            ForEach(FabricType.allCases, id: \.self) { fabric in Text("\(fabric.title) (\(fabric.examples))").tag(fabric) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    HStack {
                        Text("Hoop").font(Theme.body(13)); Spacer()
                        hoopMenu
                    }
                }
                card("New objects", note: "Starting values for lines, fills and satins you draw. Row spacing, pull compensation and underlay come from the design's fabric type instead, and lettering, monograms and imports keep their own.") {
                    row("Line stitch length", "mm", value: preferences.data.lineStitchLength ?? Preferences.builtInLineStitchLength, range: 0.3...10) { preferences.data.lineStitchLength = $0 }
                    row("Fill stitch length", "mm", value: preferences.data.fillStitchLength ?? Preferences.builtInFillStitchLength, range: 0.3...10) { preferences.data.fillStitchLength = $0 }
                    row("Fill angle", "°", value: preferences.data.fillAngle ?? Preferences.builtInFillAngle, range: -180...180) { preferences.data.fillAngle = $0 }
                    row("Satin compensation", "% of width", value: preferences.data.satinPullPercent ?? DigitizingSettings.defaultPullPercent, range: DigitizingSettings.pullPercentRange) { preferences.data.satinPullPercent = $0 }
                }
                card("Machine", note: "How fast your machine sews, for the time estimate in the status bar and on production worksheets.") {
                    HStack {
                        Text("Speed").font(Theme.body(13)); Spacer()
                        TextField("Speed", value: Binding(get: { preferences.data.machineSpeed ?? ProductionSummary.defaultSpeed },
                                                          set: { preferences.data.machineSpeed = min(max($0, ProductionSummary.speeds.lowerBound), ProductionSummary.speeds.upperBound); preferences.save() }),
                                  format: .number)
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 84)
                            .help("Stitches per minute (\(ProductionSummary.speeds.lowerBound)–\(ProductionSummary.speeds.upperBound.formatted())). Home machines often sew 400–850.")
                        Text("stitches per minute").font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).frame(width: 130, alignment: .leading)
                    }
                }
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Theme.ink).background(Theme.ground)
    }

    /// The hoop new designs start with: the one used last (each time a design's hoop is chosen, it's remembered), or
    /// one picked here, which stays until changed here.
    private var hoopMenu: some View {
        Menu {
            Button("The one I used last") { preferences.data.newDesignHoopPinned = nil; preferences.save() }
            ForEach(HoopPreset.brands, id: \.self) { brand in
                Section(brand) {
                    ForEach(HoopPreset.all.filter { $0.brand == brand }) { preset in
                        Button(preset.menuTitle) { preferences.data.newDesignHoop = preset.hoop; preferences.data.newDesignHoopPinned = true; preferences.save() }
                    }
                }
            }
        } label: {
            let hoop = preferences.data.newDesignHoop ?? Hoop()
            Text(preferences.data.newDesignHoopPinned == true ? hoop.label : "The one I used last (now \(hoop.label))").font(Theme.body(12, weight: .semibold))
        }
        .fixedSize()
        .help("The hoop blank new designs start with")
    }

    /// A settings card: a bold title, a short explanation, then its controls.
    private func card<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.body(14, weight: .bold))
            Text(note).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(16).frame(maxWidth: 520, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    /// One number setting: its name, a field, and its unit. A typed value is saved straight away.
    private func row(_ title: String, _ unit: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(Theme.body(13)); Spacer()
            NumberField(value: value, range: range, commit: { set($0); preferences.save() }, focusCanvas: {}).frame(width: 84, height: 22)
            Text(unit).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).frame(width: 130, alignment: .leading)
        }
    }
}
