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
    var inspectorVisible = true
    var paletteVisible = true
    var inspectorOnLeft = false
    var objectsWidth = 220.0
    var inspectorWidth = 260.0
    /// Where every panel is docked, tabbed or floating. nil in settings saved before panels could be rearranged;
    /// `panelLayout` then builds the equivalent from the older fields above.
    var panels: PanelLayout?
    /// The Pro view's own panel arrangement; nil until it's first changed, which means the standard Pro layout.
    var proPanels: PanelLayout?

    /// The Pro view's panel arrangement, repaired if needed.
    var proPanelLayout: PanelLayout { proPanels?.normalized() ?? .pro }

    /// The Guided view's panel arrangement, repaired if needed.
    var panelLayout: PanelLayout {
        if let panels { return panels.normalized() }
        var layout = PanelLayout.standard
        if inspectorOnLeft { swap(&layout.left, &layout.right) }
        if !inspectorVisible { layout.hide(.properties) }
        if !paletteVisible { layout.hide(.threads); layout.hide(.player) }
        layout.leftWidth = inspectorOnLeft ? inspectorWidth : objectsWidth
        layout.rightWidth = inspectorOnLeft ? objectsWidth : inspectorWidth
        return layout.normalized()
    }
}

extension Workspace {
    /// Stores `layout` as the Pro or the Guided view's arrangement.
    mutating func setPanels(_ layout: PanelLayout, pro: Bool) { if pro { proPanels = layout } else { panels = layout } }
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
    /// True when the app shows the Pro view (everything on screen, compact); nil or false is the Guided view.
    var proView: Bool?
    /// Pro view: true puts the tools in a rail down the left side; nil or false keeps them across the top.
    var proToolsOnLeft: Bool?
    /// Guided view: true if "More settings" in Properties was left open.
    var guidedMoreOpen: Bool?
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
    /// Light, dark, or following the Mac's setting; nil means following the Mac.
    var appearance: AppAppearance?
}

@MainActor final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var data = PreferenceData()
    @Published var error: String?
    /// How fast the stitch player sews, in stitches per second (a machine sews about 12). It sits outside `data`,
    /// so it isn't saved: every launch starts at 120 again.
    @Published var playbackSpeed = 120.0
    static let playbackSpeeds = 1.0...5000.0
    var isRecording = false
    var recordHandler: ((KeyBinding) -> Void)?
    /// True when the Pro view is on. It's app-wide: every design window shows the same view.
    var isPro: Bool { data.proView ?? false }
    /// True when the Pro view's tools sit in a rail down the left side rather than in two rows across the top.
    var proToolsOnLeft: Bool { data.proToolsOnLeft ?? false }
    /// How far the arrow keys move the selection, in mm.
    var nudge: Double { data.nudgeDistance ?? 1 }
    /// The unit sizes and positions are shown and typed in (designs themselves always stay in millimeters).
    var unit: LengthUnit { data.lengthUnit ?? .millimeters }
    /// Light, dark, or following the Mac's setting (Settings › General › Appearance).
    var appearance: AppAppearance { data.appearance ?? .system }
    /// Switches every window to light, dark or the Mac's setting at once, and remembers it.
    func setAppearance(_ appearance: AppAppearance) {
        data.appearance = appearance; save(announce: false)
        NSApp.appearance = appearance.nsAppearance   // every window and panel redraws in the new colors
    }
    /// True when the canvas shows its rulers and guides (View › Show Rulers & Guides). It's app-wide and remembered.
    var showsRulers: Bool { data.showRulers ?? true }
    /// Shows or hides the rulers and guides in every design window. Guides stay in the design while hidden.
    func setShowRulers(_ on: Bool) { data.showRulers = on; save(announce: false) }   // the menus show its check mark as they open
    /// Switches between millimeters and inches for every window, and remembers it.
    func setUnit(_ unit: LengthUnit) { guard unit != self.unit else { return }; data.lengthUnit = unit; save() }
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
    /// Switches between the Guided and Pro views; every window updates, each view with its own panel arrangement.
    func setPro(_ on: Bool) { guard on != isPro else { return }; data.proView = on; save() }
    /// The current view's panel arrangement (shared by every design window).
    var panels: PanelLayout { isPro ? data.workspace.proPanelLayout : data.workspace.panelLayout }
    /// The current view's standard arrangement, where hidden panels go back to when shown again.
    var homeLayout: PanelLayout { isPro ? .pro : .standard }
    /// Changes the current view's panel arrangement and saves it; every window updates.
    func updatePanels(_ change: (inout PanelLayout) -> Void) {
        var layout = panels; change(&layout)
        guard layout != (isPro ? data.workspace.proPanels : data.workspace.panels) else { return }
        data.workspace.setPanels(layout, pro: isPro); save()
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
