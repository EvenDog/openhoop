// Fabric presets: what the design will be sewn on (woven, knit, towel, heavy, felt). Each fabric sets starting
// values for fill density, pull compensation and underlay, and names the stabilizer to use. The values are common
// rules of thumb for home machines, meant to be tuned after a test sew-out, not measured results.
import Foundation

public enum FabricType: String, Codable, CaseIterable, Sendable {
    case woven, knit, towel, heavy, felt

    public var title: String {
        switch self {
        case .woven: return "Woven"
        case .knit: return "Knit"
        case .towel: return "Towel / fleece"
        case .heavy: return "Denim / canvas"
        case .felt: return "Felt / patch twill"
        }
    }
    /// Everyday examples, so people can tell which one they have.
    public var examples: String {
        switch self {
        case .woven: return "cotton, quilting cotton, twill shirts"
        case .knit: return "t-shirts, polos, sweatshirts"
        case .towel: return "terry towels, fleece, minky"
        case .heavy: return "denim, canvas bags, jackets"
        case .felt: return "felt, patch twill, stiff backing"
        }
    }
    /// What to hoop with it, for the worksheet and the Design panel.
    public var stabilizer: String {
        switch self {
        case .woven: return "Tear-away stabilizer."
        case .knit: return "Cut-away stabilizer: knits stretch, and tear-away lets the stitches distort."
        case .towel: return "Cut-away stabilizer, plus water-soluble topping on top so stitches don't sink into the pile."
        case .heavy: return "Tear-away stabilizer."
        case .felt: return "Tear-away stabilizer, or none for stiff felt."
        }
    }

    /// The fabric's values: fill row spacing, fill expansion, satin row spacing, satin compensation per side,
    /// fills' Underlay 2 (after an edge run), satin underlay, and underlay row spacing (mm). Woven matches the app's
    /// long-standing defaults.
    var values: (fillSpacing: Double, fillExpansion: Double, satinSpacing: Double, satinCompensation: Double,
                 fillSecondUnderlay: UnderlayStyle?, satinUnderlay: UnderlayStyle, underlaySpacing: Double) {
        switch self {
        case .woven: return (0.40, 0.20, 0.40, 0.20, .tatami, .center, 1.2)
        case .knit: return (0.45, 0.35, 0.40, 0.35, .tatami, .zigzag, 1.0)   // lighter top, more underlay and pull
        case .towel: return (0.35, 0.30, 0.35, 0.30, .tatami, .zigzag, 0.9)  // denser top so pile doesn't poke through
        case .heavy: return (0.40, 0.15, 0.40, 0.15, .tatami, .center, 1.2)  // stable: little pull
        case .felt: return (0.40, 0.10, 0.40, 0.10, nil, .center, 1.2)       // very stable: light underlay
        }
    }

    /// True for shapes a fabric changes: fills and cover satins. Running lines, imported stitches, lettering (rebuilt
    /// from its font, and checked against a fresh build to spot hand edits) and open zigzags such as appliqué
    /// tack-downs (row spacing over 1 mm) keep their own settings.
    public static func applies(to object: RunObject) -> Bool {
        guard object.rawStitches == nil, object.lettering == nil else { return false }
        switch object.kind {
        case .fill: return true
        case .satin: return object.settings.relaxedChecks != true && object.settings.spacing <= 1
        default: return false
        }
    }

    /// Sets this fabric's values on `settings` for a fill or satin (other kinds are left alone).
    public func apply(to settings: inout DigitizingSettings) {
        let v = values
        switch settings.kind {
        case .fill:
            settings.spacing = v.fillSpacing; settings.expansion = v.fillExpansion
            settings.underlay = .edge; settings.underlaySpacing = v.underlaySpacing
            settings.secondUnderlay = v.fillSecondUnderlay; if settings.secondUnderlay != nil { settings.secondSpacing = v.underlaySpacing }
        case .satin:
            settings.spacing = v.satinSpacing; settings.expansion = v.satinCompensation; settings.underlaySpacing = v.underlaySpacing
            // Auto underlay stays on Auto, with more support on fabrics that stretch; a chosen underlay gets the fabric's.
            if settings.underlay != .auto { settings.underlay = v.satinUnderlay }
            if settings.secondUnderlay != nil { settings.secondSpacing = v.underlaySpacing }
            settings.stretchyFabric = self == .knit || self == .towel ? true : nil
        default: break
        }
    }
}

extension Design {
    /// The design's fabric; nil (designs from before fabric types) behaves as woven.
    public var fabric: FabricType { fabricType ?? .woven }

    /// Gives a newly made object the design's fabric values, if it's a shape fabrics change.
    public func withFabric(_ object: RunObject) -> RunObject {
        guard FabricType.applies(to: object), var settings = object.digitizing else { return object }
        var adjusted = object; fabric.apply(to: &settings); adjusted.digitizing = settings
        return adjusted
    }

    /// How many unlocked shapes would change if the current fabric's values were applied to them.
    public var shapesNeedingFabric: Int { objects.filter { !$0.locked && withFabric($0) != $0 }.count }

    /// Applies the current fabric's values to every unlocked shape fabrics change. Returns how many changed.
    @discardableResult
    public mutating func applyFabricToAll() -> Int {
        var changed = 0
        for index in objects.indices where !objects[index].locked {
            let adjusted = withFabric(objects[index])
            if adjusted != objects[index] { objects[index] = adjusted; changed += 1 }
        }
        return changed
    }
}
