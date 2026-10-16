// The unit lengths are shown and typed in: millimeters or inches (Settings › General, or View › Use Inches).
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

    /// Where Snap puts a position (mm): on the nearest whole millimeter, or the nearest 0.05 in (1.27 mm).
    func snap(_ millimeters: Double) -> Double {
        let step = self == .inches ? 1.27 : 1
        return (millimeters / step).rounded() * step
    }
}
