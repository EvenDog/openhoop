// Hoop presets: the common embroidery hoops for Brother, Janome and Husqvarna Viking / Pfaff machines, by their
// sewing area in mm. Sizes are from Embird's hoop list (embird.net/sw/embird/hoops.htm), checked against makers'
// and sellers' listings. Each is stored upright (the long side running front to back); "Turn sideways" swaps it.
import Foundation

public struct HoopPreset: Hashable, Sendable, Identifiable {
    public var brand: String
    /// The name people know the hoop by: inches for Brother, the hoop code for Janome, and for Viking/Pfaff its size
    /// (they often write the long side first, e.g. "240 × 150"; here every hoop is listed upright).
    public var name: String
    public var width: Double
    public var height: Double
    public var id: String { "\(brand) \(name)" }
    public var hoop: Hoop { Hoop(width: width, height: height, name: id) }
    /// The hoop menu's line for it, e.g. "5 × 7 in · 130 × 180 mm" (a size-named hoop is just its size).
    public var menuTitle: String { name.hasSuffix("mm") ? name : "\(name) · \(Hoop.mm(width)) × \(Hoop.mm(height)) mm" }

    public static let all: [HoopPreset] = [
        .init(brand: "Brother", name: "4 × 4 in", width: 100, height: 100),
        .init(brand: "Brother", name: "5 × 7 in", width: 130, height: 180),
        .init(brand: "Brother", name: "6 × 10 in", width: 160, height: 260),
        .init(brand: "Brother", name: "8 × 8 in", width: 200, height: 200),
        .init(brand: "Brother", name: "8 × 12 in", width: 200, height: 300),
        .init(brand: "Brother", name: "9.5 × 14 in", width: 240, height: 360),
        .init(brand: "Janome", name: "SQ14", width: 140, height: 140),
        .init(brand: "Janome", name: "RE20b", width: 140, height: 200),
        .init(brand: "Janome", name: "SQ20b", width: 200, height: 200),
        .init(brand: "Janome", name: "SQ23", width: 230, height: 230),
        .init(brand: "Janome", name: "RE28b", width: 200, height: 280),
        .init(brand: "Janome", name: "RE36b", width: 200, height: 360),
        .init(brand: "Husqvarna Viking / Pfaff", name: "100 × 100 mm", width: 100, height: 100),
        .init(brand: "Husqvarna Viking / Pfaff", name: "115 × 120 mm", width: 115, height: 120),
        .init(brand: "Husqvarna Viking / Pfaff", name: "200 × 200 mm", width: 200, height: 200),
        .init(brand: "Husqvarna Viking / Pfaff", name: "150 × 240 mm", width: 150, height: 240),
        .init(brand: "Husqvarna Viking / Pfaff", name: "200 × 260 mm", width: 200, height: 260),
        .init(brand: "Husqvarna Viking / Pfaff", name: "200 × 360 mm", width: 200, height: 360),
    ]
    /// The brands in list order, for grouping the hoop menu.
    public static var brands: [String] { all.map(\.brand).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
}

extension Hoop {
    /// The preset this hoop came from, if it still has that preset's size (either way round) and isn't oval.
    public var preset: HoopPreset? {
        guard let name, !oval, let preset = HoopPreset.all.first(where: { $0.id == name }) else { return nil }
        return (width, height) == (preset.width, preset.height) || (width, height) == (preset.height, preset.width) ? preset : nil
    }
    /// The name of a hoop of your own (Settings › New designs › My hoops): a name that isn't a preset's. A preset's
    /// name on a changed size is just a custom size.
    public var ownName: String? {
        guard let name, !name.isEmpty, !HoopPreset.all.contains(where: { $0.id == name }) else { return nil }
        return name
    }
    /// True when a preset hoop has been turned sideways (its long side now runs left to right).
    public var isSideways: Bool { preset.map { $0.width != $0.height && width == $0.height } ?? false }
    /// The hoop turned a quarter turn: width and height swap, and a preset keeps its name.
    public var turned: Hoop { Hoop(width: height, height: width, oval: oval, name: name) }
    /// "Brother 5 × 7 in · 130 × 180 mm", "Husqvarna Viking / Pfaff · 240 × 150 mm (sideways)", a hoop of your own
    /// ("Magnetic 5 × 5 · 130 × 130 mm"), or "Custom · 110 × 90 mm (oval)". The size is always the hoop's current
    /// width × height.
    public var label: String {
        let size = "\(Self.mm(width)) × \(Self.mm(height)) mm"
        guard let preset else { return "\(ownName ?? "Custom") · \(size)\(oval ? " (oval)" : "")" }
        let title = preset.name.hasSuffix("mm") ? preset.brand : preset.id   // a size-named hoop doesn't repeat its size
        return "\(title) · \(size)\(isSideways ? " (sideways)" : "")"
    }
    static func mm(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value) }
}
