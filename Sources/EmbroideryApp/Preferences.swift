// Shortcut profiles and workspace layouts are application preferences, never part of a design.
import AppKit
import Combine
import EmbroideryCore

/// Light or dark: follow the Mac's own setting (System Settings › Appearance), or always one of the two.
enum AppAppearance: String, Codable, CaseIterable {
    case system, light, dark
    /// What OpenHoop's windows use; nil follows the Mac.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct Workspace: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "Default"
    /// Where every panel is docked, tabbed or floating; nil until it's first changed, which means the standard layout.
    var panels: PanelLayout?

    /// `panels` is saved as "proPanels", its name from when OpenHoop also had a Guided view, so arrangements made in
    /// the Pro view then still open. (A Guided arrangement, saved as "panels", is left unread.)
    private enum CodingKeys: String, CodingKey { case id, name, panels = "proPanels" }

    /// The panel arrangement, repaired if needed.
    var panelLayout: PanelLayout { panels?.normalized() ?? .standard }
}

struct PreferenceData: Codable {
    var version = 1
    var profiles = [ShortcutProfile()]
    var activeProfile = 0
    var workspaces = [Workspace()]
    var workspace = Workspace()
    /// The surface around the hoop, as 0xRRGGBB; nil follows the light/dark theme. Optional so older files still load.
    var pasteboardColor: Int?
    /// The grid lines' color as 0xRRGGBB and how strong they are (0–1); nil means automatic (light lines on dark
    /// cloth, dark lines on light cloth).
    var gridColor: Int?
    var gridOpacity: Double?
    /// The machine speed (stitches per minute) last used for a production worksheet's time estimate; nil until set.
    var machineSpeed: Int?
    /// True puts the tools in a rail down the left side; nil or false keeps them across the top.
    var proToolsOnLeft: Bool?
    /// How far the arrow keys move the selection, in mm; nil means 1 mm.
    var nudgeDistance: Double?
    /// Whether the canvas shows stitches as thread (Thread View: true or nil) or as thin lines (false).
    var threadView: Bool?
    /// Whether typing a new width or height keeps the selection's proportions; nil means yes.
    var keepProportions: Bool?
    /// The thread chart last picked in Choose Thread from Chart, by name; nil until one is picked.
    var threadChart: String?
    /// The hoop new designs start with: the one last picked under Sewing area; nil means 100 × 100 mm.
    var newDesignHoop: Hoop?
    /// The width last used to turn a line into a satin column (Make satin column); nil means 3 mm.
    var satinLineWidth: Double?
    /// The stitch and shape choices the Open Shape, Closed Shape and shape tools use next; nil means the defaults.
    var shapes: ShapeSettings?
    /// The unit sizes and positions are shown and typed in; nil means millimeters.
    var lengthUnit: LengthUnit?
    /// Whether the canvas shows its rulers and guide lines; nil means yes.
    var showRulers: Bool?
    /// True when the design's palette is docked in the Threads panel; nil (the default) keeps it under the canvas.
    var paletteDocked: Bool?
    /// How tall the Pro Threads panel's In Sewing Order list was dragged to; nil means as tall as its steps need.
    var threadStepsHeight: Double?
    /// What the Show list and the grid were last switched to, so new and opened designs start the same way; nil
    /// until one is switched.
    var shown: ShownItems?
    /// Light, dark, or following the Mac's setting; nil means following the Mac.
    var appearance: AppAppearance?
    /// How far apart the grid's lines are, and how far Snap moves; nil means normal (10 mm and 1 mm, or ½ in and 0.05 in).
    var gridSize: GridSize?
    var snapSize: GridSize?
    /// The fabric type blank new designs start with; nil means woven.
    var newDesignFabric: FabricType?
    /// True when `newDesignHoop` was picked in Settings, so choosing another hoop for one design doesn't change it.
    var newDesignHoopPinned: Bool?
    /// Starting values for objects drawn with the digitizing and shape tools; nil keeps the built-in ones (2.5 mm
    /// line stitches, 3 mm fill stitches, 45° fill rows, 3% satin compensation).
    var lineStitchLength: Double?
    var fillStitchLength: Double?
    var fillAngle: Double?
    var satinPullPercent: Double?
    /// The stitch player's four speed buttons, in stitches per second (Settings › Tools & player); nil means the built-in ones.
    var speedPresets: [Double]?
    /// True when the stitch player's scissors button is lit: playing pauses at each trim, stop and thread change.
    var pauseAtTrims: Bool?
    /// The format last exported with, as an id from ExportFormatPicker ("pes6", "dst"…); nil means PES 6.
    var exportFormat: String?
}

/// The canvas's view choices, remembered across designs and launches. Each is nil until it's first switched, which
/// keeps its built-in default (grid, needle points, stitches and underlay on; outlines and density off; connectors
/// following the view).
struct ShownItems: Codable, Equatable {
    var grid: Bool?
    var needles: Bool?
    var stitches: Bool?
    var outlines: Bool?
    var connectors: Bool?
    var underlay: Bool?
    var density: Bool?
}

@MainActor final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var data = PreferenceData()
    @Published var error: String?
    /// How fast the stitch player sews, in stitches per second (a machine sews about 12). It sits outside `data`,
    /// so it isn't saved: every launch starts at the second speed button again.
    @Published var playbackSpeed = 120.0
    static let playbackSpeeds = 1.0...5000.0
    /// The built-in speed buttons: about machine speed, the usual preview speed, fast, and very fast.
    static let builtInSpeedPresets: [Double] = [12, 120, 500, 2000]
    /// The stitch player's four speed buttons, in stitches per second.
    var speedPresets: [Double] {
        guard let saved = data.speedPresets, saved.count == Self.builtInSpeedPresets.count else { return Self.builtInSpeedPresets }
        return saved
    }
    /// Changes one speed button (kept within 1–5,000) and saves it. Changing the button the player is on changes
    /// the speed too, so the button stays lit.
    func setSpeedPreset(_ index: Int, to speed: Double) {
        var presets = speedPresets
        guard presets.indices.contains(index) else { return }
        let speed = min(max(speed.rounded(), Self.playbackSpeeds.lowerBound), Self.playbackSpeeds.upperBound)
        if playbackSpeed == presets[index] { playbackSpeed = speed }
        presets[index] = speed
        data.speedPresets = presets == Self.builtInSpeedPresets ? nil : presets
        save(announce: false)   // the player buttons watch these preferences, so nothing needs rebuilding
    }
    /// Puts the speed buttons back to the built-in ones; the player moves to the same button's new speed.
    func resetSpeedPresets() {
        if let index = speedPresets.firstIndex(of: playbackSpeed) { playbackSpeed = Self.builtInSpeedPresets[index] }
        data.speedPresets = nil; save(announce: false)
    }
    var isRecording = false
    var recordHandler: ((KeyBinding) -> Void)?
    /// True when the tools sit in a rail down the left side rather than in two rows across the top.
    var proToolsOnLeft: Bool { data.proToolsOnLeft ?? false }
    /// How far the arrow keys move the selection, in mm.
    var nudge: Double { data.nudgeDistance ?? 1 }
    /// The unit sizes and positions are shown and typed in (designs themselves always stay in millimeters).
    var unit: LengthUnit { data.lengthUnit ?? .millimeters }
    /// Light, dark, or following the Mac's setting (Settings › Look › Appearance).
    var appearance: AppAppearance { data.appearance ?? .system }
    /// Switches every window to light, dark or the Mac's setting at once, and remembers it.
    func setAppearance(_ appearance: AppAppearance) {
        data.appearance = appearance; save(announce: false)
        NSApp.appearance = appearance.nsAppearance   // every window and panel redraws in the new colors
    }
    /// True when the canvas shows its rulers and guides (View › Show Rulers & Guides). It's app-wide and remembered.
    var showsRulers: Bool { data.showRulers ?? true }
    /// True while the design's palette sits in a strip under the canvas (the default), false while it's docked.
    var paletteUnderCanvas: Bool { !(data.paletteDocked ?? false) }
    func setPaletteUnderCanvas(_ on: Bool) { data.paletteDocked = on ? nil : true; save(announce: false) }
    /// Shows or hides the rulers and guides in every design window. Guides stay in the design while hidden.
    func setShowRulers(_ on: Bool) { data.showRulers = on; save(announce: false) }   // the menus show its check mark as they open
    /// Switches between millimeters and inches for every window, and remembers it.
    func setUnit(_ unit: LengthUnit) { guard unit != self.unit else { return }; data.lengthUnit = unit; save() }
    /// The grid's line spacing and Snap's step (Settings › Measuring › Grid & snap).
    var gridSize: GridSize { data.gridSize ?? .normal }
    var snapSize: GridSize { data.snapSize ?? .normal }
    /// Gives a blank new design the hoop and fabric for new designs (Settings › New designs): the hoop used last, or the one
    /// picked there, and the fabric picked there (woven if none).
    func startNewDesign(_ design: inout Design) {
        if let hoop = data.newDesignHoop { design.hoop = hoop }
        design.fabricType = data.newDesignFabric
    }
    /// Remembers `hoop`, just chosen for a design, as the one new designs start with, unless a hoop for new designs
    /// was picked in Settings.
    func rememberHoop(_ hoop: Hoop) {
        guard data.newDesignHoopPinned != true else { return }
        data.newDesignHoop = hoop; save()
    }
    /// The built-in starting values for drawn objects, shown in Settings until they're changed.
    static let builtInLineStitchLength = 2.5, builtInFillStitchLength = 3.0, builtInFillAngle = 45.0
    /// A newly drawn object with the starting values from Settings › New designs › New objects: its stitch length, and a
    /// fill's angle or a satin's compensation. Only values changed in Settings are set, so the defaults the tools
    /// already use stay otherwise.
    func withNewObjectDefaults(_ object: RunObject) -> RunObject {
        var object = object
        switch object.kind {
        case .run: if let length = data.lineStitchLength { object.stitchLength = length }
        case .fill:
            if let length = data.fillStitchLength { object.stitchLength = length }
            if let angle = data.fillAngle { object.digitizing?.angle = angle }
        case .satin: if let pull = data.satinPullPercent { object.digitizing?.pullPercent = pull }
        default: break
        }
        return object
    }
    /// The stitch and shape choices for the next shape drawn (shared by every design window).
    var shapes: ShapeSettings { data.shapes ?? ShapeSettings() }
    /// Changes the shape tools' choices and saves them.
    func updateShapes(_ change: (inout ShapeSettings) -> Void) {
        var settings = shapes; change(&settings)
        guard settings != shapes else { return }
        data.shapes = settings; save(announce: false)   // nothing else depends on these, so windows and menus needn't rebuild
    }
    static let nudgeRange = 0.1...20.0
    /// True when the canvas shows stitches as thread (Thread View) rather than thin lines. It's app-wide and remembered.
    var threadView: Bool { data.threadView ?? true }
    /// Switches Thread View on or off for every design window and saves the choice.
    func setThreadView(_ on: Bool) { data.threadView = on; save(announce: false) }   // the menus show its check mark as they open, so needn't rebuild
    /// The Show list and grid choices new and opened designs start with.
    var shown: ShownItems { data.shown ?? ShownItems() }
    /// Saves a Show list or grid choice when it's switched.
    func updateShown(_ change: (inout ShownItems) -> Void) {
        var items = shown; change(&items)
        guard items != shown else { return }
        data.shown = items; save(announce: false)   // each design window already shows its own choice, so nothing needs rebuilding
    }
    /// The panel arrangement (shared by every design window).
    var panels: PanelLayout { data.workspace.panelLayout }
    /// Changes the panel arrangement and saves it; every window updates.
    func updatePanels(_ change: (inout PanelLayout) -> Void) {
        var layout = panels; change(&layout)
        guard layout != data.workspace.panels else { return }
        data.workspace.panels = layout; save()
    }
    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Embroidery", isDirectory: true).appendingPathComponent("preferences.json")
    }
    init() {
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                var loaded = try JSONDecoder().decode(PreferenceData.self, from: Data(contentsOf: file))
                guard loaded.version == 1, loaded.profiles.indices.contains(loaded.activeProfile) else { throw DesignError.invalid("Unsupported preferences file.") }
                for profile in loaded.profiles { try profile.validate() }
                // Profiles saved with older default keys move to the current ones once (keys the person set themselves stay),
                // and commands added since get their keys.
                var movedKeys = false
                for index in loaded.profiles.indices where loaded.profiles[index].upgrade() { movedKeys = true }
                data = loaded
                if movedKeys { save() }
            }
        } catch { self.error = "Preferences could not be loaded: \(error.localizedDescription)" }
        playbackSpeed = speedPresets[1]
    }
    var profile: ShortcutProfile { data.profiles[data.activeProfile] }
    func keys(_ command: CommandID) -> [KeyBinding] { profile.bindings[command.rawValue] ?? [] }
    func label(_ command: CommandID) -> String { keys(command).map(\.display).joined(separator: ", ") }
    /// A command's hover tooltip: its name and key, then what it does, as in "Knife (⌥K): Cut shapes in two…".
    func hint(_ command: CommandID) -> String {
        let keys = label(command), name = command.title.replacingOccurrences(of: "…", with: "")
        return name + (keys.isEmpty ? "" : " (\(keys))") + ": " + command.explanation
    }
    /// The first key set for a command, for hints like "press O to select"; the command's name if it has no key.
    func key(_ command: CommandID) -> String { keys(command).first?.display ?? command.title }
    /// Writes the preferences file. `announce` tells every window and the menus to rebuild for the new settings.
    func save(announce: Bool = true) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: file, options: .atomic)
            if announce { NotificationCenter.default.post(name: .preferencesChanged, object: nil) }
        } catch { self.error = error.localizedDescription }
    }
    func assign(_ key: KeyBinding, to command: CommandID, replacing: Bool) {
        if replacing {
            for other in profile.conflicts(key, for: command) { data.profiles[data.activeProfile].bindings[other.rawValue]?.removeAll { $0 == key } }
        }
        var keys = data.profiles[data.activeProfile].bindings[command.rawValue] ?? []
        if !keys.contains(key) { keys.append(key) }
        data.profiles[data.activeProfile].bindings[command.rawValue] = keys
        save()
    }
    func remove(_ command: CommandID, key: KeyBinding? = nil) {
        if let key { data.profiles[data.activeProfile].bindings[command.rawValue]?.removeAll { $0 == key } }
        else { data.profiles[data.activeProfile].bindings[command.rawValue] = [] }
        save()
    }
    func duplicateProfile(name: String) { var profile = self.profile; profile.id = UUID(); profile.name = name; data.profiles.append(profile); data.activeProfile = data.profiles.count - 1; save() }
    func importProfile(_ url: URL) throws {
        let bytes = try Data(contentsOf: url)
        guard bytes.count < 1_000_000 else { throw DesignError.invalid("Shortcut profile is too large.") }
        let wrapper = try JSONDecoder().decode(ProfileFile.self, from: bytes)
        guard wrapper.version == 1 else { throw DesignError.invalid("Unsupported shortcut profile version.") }
        var profile = wrapper.profile; try profile.validate(); profile.upgrade(); profile.id = UUID()
        data.profiles.append(profile); data.activeProfile = data.profiles.count - 1; save()
        let unknown = profile.bindings.keys.filter { CommandID(rawValue: $0) == nil }
        if !unknown.isEmpty { error = "Preserved \(unknown.count) unavailable command assignments for a later version." }
    }
    struct ProfileFile: Codable { var version = 1; var profile: ShortcutProfile }
}

extension Notification.Name { static let preferencesChanged = Notification.Name("EmbroideryPreferencesChanged") }

/// Normalize keys identically for recording and dispatch; ignore Caps Lock and Fn noise.
enum Keyboard {
    static func binding(_ event: NSEvent) -> KeyBinding? {
        let specials: [UInt16: String] = [36:"return", 76:"return", 53:"escape", 51:"delete", 117:"delete", 49:"space", 123:"left", 124:"right", 125:"down", 126:"up", 48:"tab",
            115:"home", 119:"end", 122:"f1", 120:"f2", 99:"f3", 118:"f4", 96:"f5", 97:"f6", 98:"f7", 100:"f8", 101:"f9", 109:"f10", 103:"f11", 111:"f12"]
        let key = specials[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.lowercased()
        guard let key, !key.isEmpty else { return nil }
        let flags = event.modifierFlags
        let modifiers = (flags.contains(.command) ? 1 : 0) | (flags.contains(.shift) ? 2 : 0) | (flags.contains(.option) ? 4 : 0) | (flags.contains(.control) ? 8 : 0)
        return KeyBinding(key, modifiers)
    }
}
