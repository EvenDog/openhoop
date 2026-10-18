// The unit lengths are shown and typed in: millimeters or inches (Settings › Measuring, or View › Use Inches).
// Designs always store millimeters; this converts only at the edges, where a length is shown or typed, so switching
// units never changes a design. Stitch settings (stitch length, spacing, satin widths…) always stay in millimeters.
import Foundation

enum LengthUnit: String, Codable, CaseIterable, Sendable {
    case millimeters, inches

    /// The label after a length: "mm" or "in".
    var symbol: String { self == .inches ? "in" : "mm" }
    /// How many millimeters one of this unit is.
    var millimetersPerUnit: Double { self == .inches ? 25.4 : 1 }
    /// A length in millimeters, converted to this unit for showing.
    func shown(_ millimeters: Double) -> Double { millimeters / millimetersPerUnit }
    /// A length typed in this unit, converted back to millimeters.
    func millimeters(_ shown: Double) -> Double { shown * millimetersPerUnit }

    /// A length with its unit and a fixed number of decimals, e.g. "12.5 mm" or "0.49 in". Inches get one more
    /// decimal than millimeters, since an inch is 25 times longer.
    func text(_ millimeters: Double, decimals: Int = 1) -> String { number(millimeters, decimals: decimals) + " " + symbol }
    /// A width and height, e.g. "100.0 × 100.0 mm" or "3.94 × 3.94 in".
    func size(_ width: Double, _ height: Double, decimals: Int = 1) -> String {
        number(width, decimals: decimals) + " × " + number(height, decimals: decimals) + " " + symbol
    }
    /// A length with its unit and no trailing zeros, e.g. "25 mm" or "1.5 in", for labels next to sliders and steppers.
    func short(_ millimeters: Double) -> String {
        let value = shown(millimeters)
        return (self == .inches ? value.formatted(.number.precision(.fractionLength(0...2))) : value.formatted()) + " " + symbol
    }
    /// Just the number of `text`, without the unit.
    func number(_ millimeters: Double, decimals: Int = 1) -> String {
        String(format: "%.\(self == .inches ? decimals + 1 : decimals)f", shown(millimeters))
    }

    /// Where Snap puts a position (mm): on the nearest step of `size` (normally a whole millimeter, or 0.05 in).
    func snap(_ millimeters: Double, size: GridSize = .normal) -> Double {
        let step = snapStep(size)
        return (millimeters / step).rounded() * step
    }
    /// How far apart the grid's lines are, in mm: 5, 10 or 20 mm, or ¼, ½ or 1 in. (Zoomed in, the grid shows lines
    /// half as far apart.)
    func gridSpacing(_ size: GridSize) -> Double {
        switch size {
        case .fine: return self == .inches ? 6.35 : 5
        case .normal: return self == .inches ? 12.7 : 10
        case .coarse: return self == .inches ? 25.4 : 20
        }
    }
    /// How far Snap's steps are apart, in mm: 0.5, 1 or 2 mm, or 0.025, 0.05 or 0.1 in.
    func snapStep(_ size: GridSize) -> Double {
        switch size {
        case .fine: return self == .inches ? 0.635 : 0.5
        case .normal: return self == .inches ? 1.27 : 1
        case .coarse: return self == .inches ? 2.54 : 2
        }
    }
}

extension LengthUnit {
    /// The grid spacing of `size` as Settings shows it, e.g. "10 mm" or "½ in".
    func gridLabel(_ size: GridSize) -> String {
        self == .inches ? ["¼ in", "½ in", "1 in"][GridSize.allCases.firstIndex(of: size)!] : short(gridSpacing(size))
    }
    /// The snap step of `size` as Settings shows it, e.g. "1 mm" or "0.05 in".
    func snapLabel(_ size: GridSize) -> String {
        self == .inches ? ["0.025 in", "0.05 in", "0.1 in"][GridSize.allCases.firstIndex(of: size)!] : short(snapStep(size))
    }
}

/// A size for the grid's lines or Snap's steps (Settings › Measuring › Grid & snap). Each is a round number in either
/// unit, so the same choice suits millimeters and inches.
enum GridSize: String, Codable, CaseIterable, Sendable {
    case fine, normal, coarse
}
