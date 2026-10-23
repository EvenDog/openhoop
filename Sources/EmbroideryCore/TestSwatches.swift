// Test swatches: copies of one object laid out in a grid, each with one setting stepped (row spacing 0.30, 0.35,
// 0.40…), so a single hoop sews the whole range side by side for comparing on the fabric.
import Foundation

/// A setting test swatches can step, and how it's read and written on an object.
public enum SwatchSetting: String, CaseIterable, Sendable {
    case rowSpacing, stitchLength, compensation, compensationPercent, angle, underlaySpacing

    public var title: String {
        switch self {
        case .rowSpacing: return "Row spacing"; case .stitchLength: return "Stitch length"; case .compensation: return "Compensation"
        case .compensationPercent: return "Compensation % of width"; case .angle: return "Fill angle"; case .underlaySpacing: return "Underlay spacing"
        }
    }
    /// The unit after a value: "mm", "%" or "°".
    public var unit: String { self == .compensationPercent ? "%" : self == .angle ? "°" : "mm" }
    /// The settings of `object` worth stepping: the ones that change its stitches (the same ones Properties shows),
    /// so no swatch run comes out as identical copies.
    public static func available(for object: RunObject) -> [SwatchSetting] {
        let s = object.settings
        switch object.kind {
        case .fill:
            let style = s.fillStyle ?? .tatami
            // Stipple, motif, cross stitch and gradient fills have spacings of their own, and the first three no underlay.
            let ownSpacing = [.stipple, .motif, .crossStitch, .gradient].contains(style), underlay = ![.stipple, .motif, .crossStitch].contains(style)
            return [ownSpacing ? nil : .rowSpacing, style.usesStitchLength ? .stitchLength : nil, .compensation,
                    StitchAngleLine.applies(to: object) ? .angle : nil, underlay && !s.spacedUnderlays.isEmpty ? .underlaySpacing : nil].compactMap { $0 }
        case .satin: return [.rowSpacing, .compensation, .compensationPercent, !s.spacedUnderlays.isEmpty ? .underlaySpacing : nil].compactMap { $0 }
        case .run: return (s.runStyle ?? .running).usesStitchLength ? [.stitchLength] : []
        default: return []
        }
    }
    /// The values each setting may take, and a sensible step for it.
    public var range: ClosedRange<Double> {
        switch self {
        case .rowSpacing: return 0.15...5; case .stitchLength: return 0.3...10; case .compensation: return 0...2
        case .compensationPercent: return DigitizingSettings.pullPercentRange; case .angle: return -180...180; case .underlaySpacing: return 0.5...5
        }
    }
    public var step: Double {
        switch self { case .rowSpacing: return 0.05; case .stitchLength: return 0.5; case .compensation: return 0.1; case .compensationPercent: return 1; case .angle: return 15; case .underlaySpacing: return 0.25 }
    }
    /// The setting's value on `object`.
    public func value(of object: RunObject) -> Double {
        let s = object.settings
        switch self {
        case .rowSpacing: return s.spacing; case .stitchLength: return object.stitchLength; case .compensation: return s.expansion
        case .compensationPercent: return s.pullPercent ?? 0; case .angle: return s.angle; case .underlaySpacing: return s.spacedUnderlays.first.flatMap { s.underlayLayer($0)?.spacing } ?? s.underlaySpacing
        }
    }
    /// `object` with this setting changed to `value`.
    public func applying(_ value: Double, to object: RunObject) -> RunObject {
        var copy = object
        if copy.digitizing == nil && self != .stitchLength { copy.digitizing = object.settings }
        switch self {
        case .rowSpacing: copy.digitizing?.spacing = value; case .stitchLength: copy.stitchLength = value; case .compensation: copy.digitizing?.expansion = value
        case .compensationPercent: copy.digitizing?.pullPercent = value; case .angle: copy.digitizing?.angle = value
        case .underlaySpacing: for number in object.settings.spacedUnderlays { copy.digitizing?.setUnderlay(number, spacing: value) }
        }
        return copy
    }
    /// A value as a swatch's name shows it, e.g. "0.35 mm" or "45°".
    public func label(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return unit == "mm" ? "\(number) mm" : "\(number)\(unit)"
    }
}

public enum TestSwatches {
    /// The values a swatch run steps through: `count` values from `start`, `step` apart.
    public static func values(start: Double, step: Double, count: Int) -> [Double] {
        (0..<max(1, count)).map { (start + Double($0) * step) * 1000 }.map { $0.rounded() / 1000 }
    }

    /// A design in `hoop` holding a copy of `object` for each value of `setting`, in a grid (as square as fits,
    /// filled row by row from the top left, 4 mm apart) centered on the hoop, sewn in the order of the values and
    /// named after them. Throws, saying why, when a value is out of range or the grid doesn't fit the hoop.
    public static func design(_ object: RunObject, setting: SwatchSetting, values: [Double], hoop: Hoop) throws -> Design {
        guard !values.isEmpty, values.count <= 25 else { throw DesignError.invalid("Make 1 to 25 swatches.") }
        if let bad = values.first(where: { !setting.range.contains($0) }) {
            throw DesignError.invalid("\(setting.label(bad)) is outside the \(setting.title.lowercased()) range (\(setting.label(setting.range.lowerBound))–\(setting.label(setting.range.upperBound))).")
        }
        let points = object.outlinePaths.flatMap { $0 }
        guard let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max() else {
            throw DesignError.invalid("This object has no shape to copy.")
        }
        let gap = 4.0, width = x1 - x0, height = y1 - y0
        let columns = Int(ceil(Double(values.count).squareRoot())), rows = Int(ceil(Double(values.count) / Double(columns)))
        let total = (width: Double(columns) * width + Double(columns - 1) * gap, height: Double(rows) * height + Double(rows - 1) * gap)
        guard total.width <= hoop.width - 4, total.height <= hoop.height - 4 else {
            throw DesignError.invalid("\(values.count) swatches of this size (\(Int(total.width.rounded())) × \(Int(total.height.rounded())) mm in all) don't fit the \(Int(hoop.width)) × \(Int(hoop.height)) mm hoop. Make fewer, or make the shape smaller.")
        }
        var design = Design(); design.hoop = hoop
        for (index, value) in values.enumerated() {
            let column = index % columns, row = index / columns
            // Each copy's top left corner, so the grid's middle lands on the hoop's middle (y points up).
            let left = -total.width / 2 + Double(column) * (width + gap), top = total.height / 2 - Double(row) * (height + gap)
            var copy = setting.applying(value, to: object)
            copy.id = UUID(); copy.groupID = nil; copy.lettering = nil; copy.letterKey = nil; copy.monogram = nil; copy.branchID = nil
            copy.entry = nil; copy.exit = nil; copy.stitchEdits = nil; copy.locked = false; copy.visible = true
            copy.transform { $0 + Point(left - x0, top - y1) }
            copy.name = "\(setting.title) \(setting.label(value))"
            design.objects.append(copy)
        }
        return design
    }
}
