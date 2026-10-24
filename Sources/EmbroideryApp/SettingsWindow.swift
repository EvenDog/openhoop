// The Settings window: a sidebar of short pages (Look, Measuring, Tools & player, New designs, Machine, Updates and
// Keyboard shortcuts). Each page is a heading and cards of rows: a setting's name and a one-line hint on the left, its control
// on the right, and the longer explanation when the pointer rests on it.
import SwiftUI
import EmbroideryCore

/// The pages of the Settings window, in sidebar order.
enum SettingsPage: String, CaseIterable, Identifiable {
    case look, measuring, tools, newDesigns, machine, updates, shortcuts
    var id: Self { self }
    var title: String {
        switch self {
        case .look: return "Look"
        case .measuring: return "Measuring"
        case .tools: return "Tools & player"
        case .newDesigns: return "New designs"
        case .machine: return "Machine"
        case .updates: return "Updates"
        case .shortcuts: return "Keyboard shortcuts"
        }
    }
    /// The line under the page's heading.
    var note: String {
        switch self {
        case .look: return "How OpenHoop and its canvas look."
        case .measuring: return "Units, the grid, and the steps Snap moves points by."
        case .tools: return "Where the tools sit, and the stitch player's speeds."
        case .newDesigns: return "What a blank new design and newly drawn objects start with."
        case .machine: return "Your machine, for time estimates."
        case .updates: return "Getting new versions of OpenHoop."
        case .shortcuts: return "Assign a key to any command. Your shortcuts stay with you."
        }
    }
    /// The page's icon in the sidebar (an SF Symbol name).
    var symbol: String {
        switch self {
        case .look: return "circle.lefthalf.filled"
        case .measuring: return "ruler"
        case .tools: return "slider.horizontal.3"
        case .newDesigns: return "circle.circle"
        case .machine: return "speedometer"
        case .updates: return "arrow.down.circle"
        case .shortcuts: return "keyboard"
        }
    }
}

/// Which Settings page shows. Other parts of the app can open a page by setting it first (the stitch player's Change
/// Speed Buttons… opens Tools & player).
@MainActor final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var page = SettingsPage.look
}

struct SettingsView: View {
    @ObservedObject var navigation = SettingsNavigation.shared
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Theme.cardBorder.frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(navigation.page.title).font(Theme.heading(24))
                    Text(navigation.page.note).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                }
                .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
                if navigation.page == .shortcuts {
                    ShortcutSettings()
                } else {
                    // Short pages, but a small window may still need to scroll.
                    ScrollView {
                        page(navigation.page).padding(.horizontal, 28).padding(.bottom, 24)
                            .frame(maxWidth: 640, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card)
        }
        .frame(minWidth: 1100, minHeight: 600)   // the Keyboard shortcuts page needs the width
        .foregroundStyle(Theme.ink)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { page in
                let chosen = page == navigation.page
                Button { navigation.page = page } label: {
                    HStack(spacing: 9) {
                        Image(systemName: page.symbol).font(.system(size: 13)).frame(width: 18)
                        Text(page.title).font(Theme.body(13, weight: chosen ? .bold : .regular))
                    }
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(chosen ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(chosen ? Theme.onAccent : Theme.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(10).padding(.top, 8)
        .frame(width: 210).frame(maxHeight: .infinity)
        .background(Theme.ground)
    }
    @ViewBuilder private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .look: LookSettings()
        case .measuring: MeasuringSettings()
        case .tools: ToolsSettings()
        case .newDesigns: NewDesignSettings()
        case .machine: MachineSettings()
        case .updates: UpdateSettings()
        case .shortcuts: EmptyView()   // shown full size above
        }
    }
}

/// A captioned card of settings rows. Put `RowDivider()` between rows.
struct SettingsCard<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption.uppercased()).font(Theme.caption).tracking(0.8).foregroundStyle(Theme.inkSecondary).padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        }
        .padding(.bottom, 14)
    }
}

/// The thin line between two rows of a card.
struct RowDivider: View {
    var body: some View { Theme.divider.frame(height: 1) }
}

/// One setting: its name and a one-line hint on the left, its control on the right. `help` (or the hint) shows when the
/// pointer rests on it.
struct SettingsRow<Control: View>: View {
    let title: String
    let hint: String
    var help: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(13, weight: .semibold))
                Text(hint).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .help(help ?? hint)
    }
}

/// Look: light or dark, the surface around the hoop, the grid lines' color, and how Review Sewing Order shows the
/// steps still to sew.
private struct LookSettings: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(caption: "Windows") {
                SettingsRow(title: "Appearance", hint: "Light or dark for every OpenHoop window",
                            help: "Match Mac follows the Mac's own setting, including when it changes through the day.") {
                    Picker("Appearance", selection: Binding(get: { preferences.appearance }, set: { preferences.setAppearance($0) })) {
                        Text("Match Mac").tag(AppAppearance.system)
                        Text("Light").tag(AppAppearance.light)
                        Text("Dark").tag(AppAppearance.dark)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            SettingsCard(caption: "Canvas") {
                SettingsRow(title: "Around the hoop", hint: "The work surface behind every design's hoop",
                            help: "Automatic follows light or dark mode; Custom uses a color of your own.") {
                    HStack(spacing: 8) {
                        if let hex = preferences.data.pasteboardColor {
                            ColorPicker("Color", selection: Binding(get: { Color(nsColor: Theme.fixed(hex)) },
                                                                    set: { preferences.data.pasteboardColor = Theme.hex(of: $0); preferences.save() }), supportsOpacity: false)
                                .labelsHidden()
                        }
                        Picker("Around the hoop", selection: Binding(get: { preferences.data.pasteboardColor == nil },
                                                                     set: { automatic in preferences.data.pasteboardColor = automatic ? nil : 0xE8DCC8; preferences.save() })) {
                            Text("Automatic").tag(true)
                            Text("Custom").tag(false)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
                RowDivider()
                SettingsRow(title: "Grid lines", hint: "Automatic suits the fabric's color",
                            help: "Automatic draws light lines on dark cloth and dark lines on light cloth. With Custom, the color picker's opacity slider sets how strong the lines are.") {
                    HStack(spacing: 8) {
                        if let hex = preferences.data.gridColor {
                            ColorPicker("Color", selection: Binding(get: { Color(nsColor: Theme.fixed(hex).withAlphaComponent(preferences.data.gridOpacity ?? 0.4)) },
                                                                    set: { color in
                                                                        preferences.data.gridColor = Theme.hex(of: color)
                                                                        preferences.data.gridOpacity = Double(NSColor(color).alphaComponent)
                                                                        preferences.save()
                                                                    }), supportsOpacity: true)
                                .labelsHidden()
                        }
                        Picker("Grid lines", selection: Binding(get: { preferences.data.gridColor == nil },
                                                                set: { automatic in preferences.data.gridColor = automatic ? nil : 0xFFFFFF; preferences.data.gridOpacity = automatic ? nil : 0.4; preferences.save() })) {
                            Text("Automatic").tag(true)
                            Text("Custom").tag(false)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
                RowDivider()
                SettingsRow(title: "Reviewing the sewing order", hint: "How the steps still to sew look",
                            help: "In View › Review Sewing Order, Faded keeps the whole design in view; Hidden shows only what's sewn so far, like a sew-out paused at that step.") {
                    Picker("Steps still to sew", selection: Binding(get: { preferences.reviewHidesUnsewn }, set: { preferences.data.reviewHidesUnsewn = $0 ? true : nil; preferences.save() })) {
                        Text("Faded").tag(false)
                        Text("Hidden").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            Text("Fabric color is chosen per design: click empty canvas so nothing is selected, then look under Fabric in Properties.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 4)
        }
    }
}

/// Measuring: millimeters or inches, how far apart the grid's lines are, and Snap's step.
private struct MeasuringSettings: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(caption: "Units") {
                SettingsRow(title: "Sizes and positions", hint: "Stitch settings always stay in millimeters",
                            help: "How sizes and positions are shown and typed: design and hoop sizes, rulers, the grid, Measure and nudge. Stitch settings such as stitch length and row spacing always stay in millimeters. View › Use Inches switches too.") {
                    Picker("Units", selection: Binding(get: { preferences.unit }, set: { preferences.setUnit($0) })) {
                        Text("Millimeters").tag(LengthUnit.millimeters)
                        Text("Inches").tag(LengthUnit.inches)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            SettingsCard(caption: "Grid & snap") {
                SettingsRow(title: "Grid lines every", hint: "Zoomed in, the grid shows lines half as far apart") {
                    Picker("Grid lines every", selection: Binding(get: { preferences.gridSize }, set: { preferences.data.gridSize = $0; preferences.save() })) {
                        ForEach(GridSize.allCases, id: \.self) { size in Text(preferences.unit.gridLabel(size)).tag(size) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                RowDivider()
                SettingsRow(title: "Snap to", hint: "The steps Snap moves points by") {
                    Picker("Snap to", selection: Binding(get: { preferences.snapSize }, set: { preferences.data.snapSize = $0; preferences.save() })) {
                        ForEach(GridSize.allCases, id: \.self) { size in Text(preferences.unit.snapLabel(size)).tag(size) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }
}

/// Tools & player: where the tools sit, and the stitch player's four speed buttons.
private struct ToolsSettings: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(caption: "Tools") {
                SettingsRow(title: "Tools", hint: "Every tool is one click away either way") {
                    Picker("Tools", selection: Binding(get: { preferences.proToolsOnLeft },
                                                                set: { onLeft in preferences.data.proToolsOnLeft = onLeft ? true : nil; preferences.save() })) {
                        Text("Across the top").tag(false)
                        Text("Down the left").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            SettingsCard(caption: "Stitch player") {
                SettingsRow(title: "Speed buttons", hint: "Stitches per second. Right-click them for a one-off speed",
                            help: "The speed buttons in the stitch player at the end of the tool strip, in stitches per second (1–5,000). A machine sews about 12.") {
                    HStack(spacing: 6) {
                        ForEach(0..<preferences.speedPresets.count, id: \.self) { index in
                            TextField("Button \(index + 1)", value: Binding(get: { preferences.speedPresets[index] }, set: { preferences.setSpeedPreset(index, to: $0) }),
                                      format: .number.precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 56)
                                .accessibilityLabel("Speed button \(index + 1), stitches per second")
                        }
                        Button("Reset") { preferences.resetSpeedPresets() }.buttonStyle(ThemedButtonStyle()).fixedSize()
                            .disabled(preferences.data.speedPresets == nil).help("Back to 12, 120, 500 and 2,000")
                    }
                }
            }
        }
    }
}

/// New designs: the fabric and hoop a blank design starts with, and the starting values for drawn objects.
private struct NewDesignSettings: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(caption: "New designs") {
                SettingsRow(title: "Fabric", hint: "Sets starting density, compensation and underlay",
                            help: "What a blank new design starts with. Each design can change its own in the Design panel.") {
                    Picker("Fabric", selection: Binding(get: { preferences.data.newDesignFabric ?? .woven }, set: { preferences.data.newDesignFabric = $0; preferences.save() })) {
                        ForEach(FabricType.allCases, id: \.self) { fabric in Text("\(fabric.title) (\(fabric.examples))").tag(fabric) }
                    }
                    .labelsHidden().fixedSize()
                }
                RowDivider()
                SettingsRow(title: "Hoop", hint: "The one you used last, unless you pick one here") { hoopMenu }
            }
            MyHoopsCard()
            SettingsCard(caption: "New objects") {
                number("Line stitch length", hint: "Running stitches and outlines", unit: "mm", value: preferences.data.lineStitchLength ?? Preferences.builtInLineStitchLength, range: 0.3...10) { preferences.data.lineStitchLength = $0 }
                RowDivider()
                number("Fill stitch length", hint: "Tatami rows", unit: "mm", value: preferences.data.fillStitchLength ?? Preferences.builtInFillStitchLength, range: 0.3...10) { preferences.data.fillStitchLength = $0 }
                RowDivider()
                number("Fill angle", hint: "The direction of fill rows", unit: "°", value: preferences.data.fillAngle ?? Preferences.builtInFillAngle, range: -180...180) { preferences.data.fillAngle = $0 }
                RowDivider()
                number("Satin compensation", hint: "Extra width, as a share of each stitch", unit: "%", value: preferences.data.satinPullPercent ?? DigitizingSettings.defaultPullPercent, range: DigitizingSettings.pullPercentRange) { preferences.data.satinPullPercent = $0 }
            }
            Text("Row spacing, pull compensation and underlay come from the design's fabric instead, and lettering, monograms and imports keep their own.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 4)
        }
    }
    /// The hoop new designs start with: the one used last (each time a design's hoop is chosen, it's remembered), or
    /// one picked here, which stays until changed here.
    private var hoopMenu: some View {
        Menu {
            Button("The one I used last") { preferences.data.newDesignHoopPinned = nil; preferences.save() }
            HoopMenuItems { hoop in preferences.data.newDesignHoop = hoop; preferences.data.newDesignHoopPinned = true; preferences.save() }
        } label: {
            let hoop = preferences.data.newDesignHoop ?? Hoop()
            Text(preferences.data.newDesignHoopPinned == true ? hoop.label : "Last used (now \(hoop.label))").font(Theme.body(12, weight: .semibold))
        }
        .fixedSize()
        .help("The hoop blank new designs start with")
    }
    /// One number setting: a field and its unit. A typed value is saved straight away.
    private func number(_ title: String, hint: String, unit: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        SettingsRow(title: title, hint: hint) {
            HStack(spacing: 6) {
                NumberField(value: value, range: range, commit: { set($0); preferences.save() }, focusCanvas: {}).frame(width: 70, height: 22)
                Text(unit).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).frame(width: 22, alignment: .leading)
            }
        }
    }
}

/// Machine: how fast it sews, for the time estimates.
private struct MachineSettings: View {
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        SettingsCard(caption: "Speed") {
            SettingsRow(title: "Machine speed", hint: "For the time estimate in the status bar and on worksheets",
                        help: "Stitches per minute (\(ProductionSummary.speeds.lowerBound)–\(ProductionSummary.speeds.upperBound.formatted())). Home machines often sew 400–850.") {
                HStack(spacing: 6) {
                    TextField("Speed", value: Binding(get: { preferences.data.machineSpeed ?? ProductionSummary.defaultSpeed },
                                                      set: { preferences.data.machineSpeed = min(max($0, ProductionSummary.speeds.lowerBound), ProductionSummary.speeds.upperBound); preferences.save() }),
                              format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 70)
                    Text("stitches per minute").font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }
}

/// Updates: whether OpenHoop checks for new versions by itself, and a button to check now (Updates.swift).
private struct UpdateSettings: View {
    @State private var automatic = Updates.checksAutomatically
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        SettingsCard(caption: "New versions") {
            SettingsRow(title: "Check automatically", hint: "Once a day, when OpenHoop is open",
                        help: "OpenHoop asks openhoop.app whether there's a newer version. Nothing about you or your designs is sent. When there is one, it shows what's new and offers to install it; nothing installs without your OK.") {
                Toggle("Check automatically", isOn: Binding(get: { automatic }, set: { automatic = $0; Updates.checksAutomatically = $0 }))
                    .toggleStyle(.switch).labelsHidden()
            }
            RowDivider()
            SettingsRow(title: "This is version \(version)", hint: Updates.lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet") {
                Button("Check Now") { Updates.checkNow() }.buttonStyle(ThemedButtonStyle())
            }
        }
        .disabled(Updates.controller == nil)   // running outside the app bundle, which has no update feed
    }
}
