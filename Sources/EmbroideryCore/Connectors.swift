// Connectors: how the needle gets from one object to the next, and when tie stitches lock the thread. Each object
// picks Jump (the frame moves without sewing) or Run (running stitches straight to the next object, which sews over
// them, so there's no trim and no tie), and when it ties in and off: never, always, or only when the move is far.
// The design sets what "far" means for ties, the tie stitches themselves, and the run's stitch length.
import Foundation

/// How the needle gets to the next object.
public enum Connector: String, Codable, CaseIterable, Sendable {
    case jump, run
    public var title: String { self == .jump ? "Jump" : "Run" }
}

/// How lettering's parts connect to one another: trim when far (the font's own trims), always trim, jump without
/// trimming, or run on to the next part.
public enum LetterConnector: String, Codable, CaseIterable, Sendable {
    case whenFar, always, jump, run
    public var title: String {
        switch self { case .whenFar: return "Trim when far"; case .always: return "Always trim"; case .jump: return "Jump, no trims"; case .run: return "Run" }
    }
}

/// When an object ties in or off: never, always, or only when the move to (or from) the next object is at least the
/// design's tie distance, or the thread is cut there anyway.
public enum TieRule: String, CaseIterable, Sendable {
    case off, always, whenFar
    public var title: String {
        switch self { case .off: return "Off"; case .always: return "Always"; case .whenFar: return "When far" }
    }
}

extension RunObject {
    /// `tieIn` and `tieInWhenFar` as one three-way choice.
    public var tieInRule: TieRule {
        get { !tieIn ? .off : tieInWhenFar == true ? .whenFar : .always }
        set { tieIn = newValue != .off; tieInWhenFar = newValue == .whenFar ? true : nil }
    }
    /// `tieOut` and `tieOutWhenFar` as one three-way choice.
    public var tieOutRule: TieRule {
        get { !tieOut ? .off : tieOutWhenFar == true ? .whenFar : .always }
        set { tieOut = newValue != .off; tieOutWhenFar = newValue == .whenFar ? true : nil }
    }
    /// How the needle gets to the next object (nil, in older files too, is a jump).
    public var connectorType: Connector {
        get { connector ?? .jump }
        set { connector = newValue == .jump ? nil : newValue }
    }
}

extension Design {
    public static let defaultTieDistance = 1.0, tieDistances = 0.1...20.0
    public static let defaultTieCount = 1, tieCounts = 1...3
    public static let defaultTieLength = 0.6, tieLengths = 0.3...1.5
    public static let defaultRunConnectorLength = 2.0, runConnectorLengths = 1.0...5.0
    /// True when the design sews differently with connector settings older versions don't know: a run connector, a
    /// "When far" tie, tie stitches other than one 0.6 mm stitch, or lettering with Between letters set. It's saved as
    /// version 11 so they refuse it.
    public var needsSchemaEleven: Bool {
        tieCount != nil || tieLength != nil
            || objects.contains { $0.connector == .run || $0.tieInWhenFar == true || $0.tieOutWhenFar == true || $0.lettering?.betweenLetters != nil }
    }
    /// Checks the connector settings' ranges.
    func validateConnectors() throws {
        guard tieDistance.map(Self.tieDistances.contains) ?? true else { throw DesignError.invalid("The tie distance must be between 0.1 and 20 mm.") }
        guard tieCount.map(Self.tieCounts.contains) ?? true else { throw DesignError.invalid("Tie stitches must be 1 to 3.") }
        guard tieLength.map(Self.tieLengths.contains) ?? true else { throw DesignError.invalid("The tie stitch length must be between 0.3 and 1.5 mm.") }
        guard runConnectorLength.map(Self.runConnectorLengths.contains) ?? true else { throw DesignError.invalid("The run connector's stitch length must be between 1 and 5 mm.") }
    }
}
