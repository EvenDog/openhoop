// Guide lines for guided fills: a line drawn over a fill is turned into an unstitched guide linked to it, and the
// fill's rows follow its path. The guide stays an ordinary object, so Edit Nodes reshapes it; after every edit the
// fill picks up the guide's new path.
import Foundation

extension Design {
    /// Makes the line `lineID` the guide of the fill `fillID`, and makes that a guided fill. The line stops sewing
    /// (it becomes an unstitched line, drawn dashed) and joins the fill's group, right after the fill, so they select
    /// and move together. A guide the fill had before goes back to being a plain unstitched line. Throws, saying why,
    /// when the two aren't an open line and a fill.
    public mutating func useAsFillGuide(line lineID: UUID, fill fillID: UUID) throws {
        guard let fillIndex = objects.firstIndex(where: { $0.id == fillID }), objects[fillIndex].kind == .fill else {
            throw DesignError.invalid("Select a fill and a line drawn over it.")
        }
        guard let lineIndex = objects.firstIndex(where: { $0.id == lineID }), [.run, .vector].contains(objects[lineIndex].kind),
              !objects[lineIndex].closed, objects[lineIndex].lettering == nil, objects[lineIndex].monogram == nil else {
            throw DesignError.invalid("The guide must be an open line (not a closed outline or lettering). Draw one with the line tool.")
        }
        for i in objects.indices where objects[i].guideFor == fillID { objects[i].guideFor = nil }
        var line = objects.remove(at: lineIndex)
        let fill = objects[objects.firstIndex { $0.id == fillID }!]
        line.digitizing = DigitizingSettings(kind: .vector)
        line.guideFor = fillID; line.name = "\(fill.name) · guide"
        line.entry = nil; line.exit = nil; line.stitchEdits = nil; line.branchID = nil
        // In the fill's group (a new one for the two of them when it has none), just after it.
        let group = fill.groupID ?? UUID()
        let at = objects.firstIndex { $0.id == fillID }!
        objects[at].groupID = group; line.groupID = group
        objects[at].digitizing?.fillStyle = .guided
        objects.insert(line, at: at + 1)
        syncGuides()
    }

    /// Brings guided fills up to date with their guide lines: each fill takes its guide's current path. A guide whose
    /// fill is gone stays an unstitched line, no longer linked. A fill whose guide was deleted keeps the last path,
    /// so it sews as before.
    public mutating func syncGuides() {
        guard objects.contains(where: { $0.guideFor != nil }) else { return }
        let fills = Dictionary(objects.enumerated().filter { $0.element.kind == .fill }.map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        var guided: Set<UUID> = []
        for i in objects.indices {
            guard let fillID = objects[i].guideFor else { continue }
            // Linked to something that isn't there (or a second guide for the same fill): just an unstitched line.
            guard objects[i].kind == .vector, let f = fills[fillID], !guided.contains(fillID) else { objects[i].guideFor = nil; continue }
            guided.insert(fillID)
            let path = objects[i].outlinePaths.first ?? []
            if objects[f].digitizing?.guideLine != path { objects[f].digitizing?.guideLine = path }
        }
    }

    /// After copying objects (`copies` maps each original's id to its copy's), links each copied guide to the copy of
    /// its fill. A guide copied without its fill is just an unstitched line.
    public mutating func relinkCopiedGuides(_ copies: [UUID: UUID]) {
        let made = Set(copies.values)
        for i in objects.indices where made.contains(objects[i].id) {
            if let old = objects[i].guideFor { objects[i].guideFor = copies[old] }
        }
    }
}
