// Set Up Your Machine: the welcome a new user sees on OpenHoop's very first launch, and again from Help › Set Up
// Your Machine…. It asks which brand of machine they sew on, which hoop new designs should start in, and whether the
// machine cuts the thread between parts, and keeps the answers as preferences: the hoop for new designs, the format
// exports start in, and whether exporting suggests Stop at Jumps.
import AppKit
import SwiftUI
import EmbroideryCore

/// The machine brands the welcome offers, each with its hoops and the file format its machines read.
enum MachineBrand: String, CaseIterable, Identifiable {
    case brother, janome, viking, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .brother: return "Brother / Baby Lock"
        case .janome: return "Janome / Elna"
        case .viking: return "Husqvarna Viking / Pfaff"
        case .other: return "Other"
        }
    }
    /// The hoops to choose from: the brand's own (HoopPresets.swift), or every one for Other.
    var hoops: [HoopPreset] {
        switch self {
        case .brother: return HoopPreset.all.filter { $0.brand == "Brother" }
        case .janome: return HoopPreset.all.filter { $0.brand == "Janome" }
        case .viking: return HoopPreset.all.filter { $0.brand == "Husqvarna Viking / Pfaff" }
        case .other: return HoopPreset.all
        }
    }
    /// The export format its machines read, as an ExportFormatPicker id; nil for Other, where the person picks one.
    var format: String? {
        switch self {
        case .brother: return "pes6"
        case .janome: return "jef"
        case .viking: return "vp3"
        case .other: return nil
        }
    }
}

/// The welcome's answers.
struct MachineSetup: Equatable {
    var brand: MachineBrand
    var hoop: HoopPreset
    /// An ExportFormatPicker id ("pes6", "jef"…).
    var format: String
    /// Whether the machine cuts the thread between parts by itself; nil when they're not sure.
    var cutsThreads: Bool?

    /// The answers saved last time, or a starting guess from the hoop and format already in use (Brother's 4 × 4 in
    /// hoop and PES 6 when there's nothing to go on).
    init(from data: PreferenceData) {
        let used = data.newDesignHoop?.preset
        let brand = data.machineBrand.flatMap(MachineBrand.init(rawValue:))
            ?? MachineBrand.allCases.first { $0 != .other && used.map($0.hoops.contains) == true } ?? .brother
        self.brand = brand
        hoop = used.flatMap { brand.hoops.contains($0) ? $0 : nil } ?? brand.hoops[0]
        format = data.exportFormat ?? brand.format ?? "pes6"
        cutsThreads = data.cutsThreads
    }

    /// Picks a brand: its first hoop (unless the chosen one is also its own) and its format.
    mutating func choose(_ brand: MachineBrand) {
        self.brand = brand
        if !brand.hoops.contains(hoop) { hoop = brand.hoops[0] }
        if let format = brand.format { self.format = format }
    }

    /// Writes the answers into `data`: new designs start in the hoop (until another hoop is chosen for a design,
    /// unless Settings pins one), exports start in the format, and the brand and thread cutting are remembered.
    func apply(to data: inout PreferenceData) {
        data.machineBrand = brand.rawValue
        data.newDesignHoop = hoop.hoop
        data.exportFormat = format
        data.cutsThreads = cutsThreads
    }

    /// The note the export check shows when the machine doesn't cut threads and some parts of `design` end in a jump
    /// with no stop (in `plan`, compiled from it); nil otherwise.
    static func jumpStopTip(cutsThreads: Bool?, design: Design, plan: StitchPlan) -> String? {
        guard cutsThreads == false else { return nil }
        var trial = design
        let jumps = trial.addJumpStops(using: plan, in: nil)
        guard jumps > 0 else { return nil }
        return "Your machine doesn't cut threads, and \(jumps) part\(jumps == 1 ? " ends" : "s end") in a jump with no stop. Stop at Jumps (in the Threads panel) makes the machine pause after each one so you can snip the thread."
    }
}

/// The welcome: brand, hoop, (for Other) format, and thread cutting. On the first launch its buttons are Start Blank
/// and Open the Sample Design, and both keep the answers; from the Help menu they're Cancel and Save.
struct MachineSetupView: View {
    let firstLaunch: Bool
    @State var setup: MachineSetup
    /// Called with the answers and whether the main button was chosen.
    let done: (MachineSetup, Bool) -> Void

    var body: some View {
        DialogFrame(eyebrow: firstLaunch ? "Welcome to OpenHoop" : "Your machine", title: "Which machine do you sew on?",
                    subtitle: "New designs will start in its hoop and save in its format. Help › Set Up Your Machine… brings this back.",
                    primary: firstLaunch ? "Open the Sample Design" : "Save", secondary: firstLaunch ? "Start Blank" : "Cancel",
                    finish: { done(setup, $0) }) {
            VStack(alignment: .leading, spacing: 18) {
                question("Brand") {
                    Picker("Brand", selection: Binding(get: { setup.brand }, set: { setup.choose($0) })) {
                        ForEach(MachineBrand.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                question("Hoop for new designs", hint: "Pick another for any one design under Sewing area.") {
                    Picker("Hoop for new designs", selection: $setup.hoop) {
                        ForEach(setup.brand.hoops) { Text(setup.brand == .other ? "\($0.brand) · \($0.menuTitle)" : $0.menuTitle).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                if setup.brand == .other {
                    question("File format", hint: "Your machine's manual lists the formats it reads.") {
                        Picker("File format", selection: $setup.format) {
                            ForEach(ExportFormatPicker.choices, id: \.id) { Text($0.title).tag($0.id) }
                        }.labelsHidden().fixedSize()
                    }
                }
                question("Does it cut the thread between parts by itself?",
                         hint: setup.cutsThreads == false ? "Then exporting will suggest Stop at Jumps, so the machine pauses for you to snip the thread."
                               : "Many home machines, such as the Brother SE600, don't: the thread is left across the fabric to snip.") {
                    Picker("Cuts threads", selection: $setup.cutsThreads) {
                        Text("Yes").tag(Bool?.some(true)); Text("No").tag(Bool?.some(false)); Text("Not sure").tag(Bool?.none)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }
    /// One question: its title, the control, and an optional line of explanation.
    private func question<Control: View>(_ title: String, hint: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.body(13, weight: .bold))
            control()
            if let hint { Text(hint).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

extension GuidedDialog {
    /// Shows Set Up Your Machine and saves the answers: on the first launch whichever button closes it, otherwise
    /// only Save. Returns true for the main button (Open the Sample Design, or Save).
    static func machineSetup(firstLaunch: Bool) -> Bool {
        let preferences = Preferences.shared
        var answers = MachineSetup(from: preferences.data)
        let chosen = run(width: 620) { finish in
            MachineSetupView(firstLaunch: firstLaunch, setup: answers) { setup, primary in answers = setup; finish(primary) }
        }
        if chosen || firstLaunch { answers.apply(to: &preferences.data); preferences.save() }
        return chosen
    }
}
