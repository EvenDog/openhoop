// Guide lines (not the ruler guides): a line drawn over a fill or beside some lettering is turned into an
// unstitched guide linked to it. A guided fill's rows follow it, and lettering on a line sits along it. The guide
// stays an ordinary object, so Edit Nodes reshapes it; after every edit the fill or lettering follows its new path.
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
        var line = try takeGuide(lineID, for: fillID)
        let fill = objects[objects.firstIndex { $0.id == fillID }!]
        line.name = "\(fill.name) · guide"
        // In the fill's group (a new one for the two of them when it has none), just after it.
        let group = fill.groupID ?? UUID()
        let at = objects.firstIndex { $0.id == fillID }!
        objects[at].groupID = group; line.groupID = group
        objects[at].digitizing?.fillStyle = .guided
        objects.insert(line, at: at + 1)
        syncGuides()
    }

    /// Sets the lettering `id` along the line `lineID`: the lettering's shape becomes On a line, rebuilt along the
    /// line's path, and the line stops sewing and becomes its guide, in its group just after its last letter.
    /// Throws, saying why, when they aren't lettering and an open line, or the letters can't be built along it.
    public mutating func putLettering(_ id: UUID, onLine lineID: UUID, embroideryFonts: [EmbroideryFont]) throws {
        let letters = letteringObjects(id)
        guard var spec = letters.first?.lettering, let color = letters.first?.color else { throw DesignError.invalid("Select some lettering and a line.") }
        guard !letters.contains(where: \.locked) else { throw DesignError.invalid("Unlock the letters first.") }
        guard let lineIndex = objects.firstIndex(where: { $0.id == lineID }) else { throw DesignError.invalid("Select some lettering and a line.") }
        spec.shape = .onLine; spec.path = objects[lineIndex].outlinePaths.first
        if abs(spec.currentHeight - spec.height) > 0.05 { spec.height = spec.currentHeight }   // resized letters keep their size
        // Build first, so nothing changes when the letters can't go on this line.
        let built = try spec.build(color: color, embroideryFonts: embroideryFonts)
        var line = try takeGuide(lineID, for: id)
        line.name = "“\(spec.text.replacingOccurrences(of: "\n", with: " "))” · line"
        replaceLettering(id, with: built)
        let group = letteringObjects(id).first?.groupID ?? UUID()
        for i in objects.indices where objects[i].lettering?.id == id { objects[i].groupID = group }
        line.groupID = group
        objects.insert(line, at: objects.lastIndex { $0.lettering?.id == id }! + 1)
    }

    /// Takes the open line `lineID` out of the objects, turned into an unstitched guide for `target`. Any other guide
    /// `target` had goes back to being a plain unstitched line.
    private mutating func takeGuide(_ lineID: UUID, for target: UUID) throws -> RunObject {
        guard let lineIndex = objects.firstIndex(where: { $0.id == lineID }), [.run, .vector].contains(objects[lineIndex].kind),
              !objects[lineIndex].closed, objects[lineIndex].lettering == nil, objects[lineIndex].monogram == nil else {
            throw DesignError.invalid("The guide must be an open line (not a closed outline or lettering). Draw one with the line tool.")
        }
        for i in objects.indices where objects[i].guideFor == target { objects[i].guideFor = nil }
        var line = objects.remove(at: objects.firstIndex { $0.id == lineID }!)
        line.digitizing = DigitizingSettings(kind: .vector)
        line.guideFor = target
        line.entry = nil; line.exit = nil; line.stitchEdits = nil; line.branchID = nil
        return line
    }

    /// Brings guided fills and lettering on a line up to date with their guide lines. Each fill takes its guide's
    /// current path; lettering whose guide was reshaped is rebuilt along it (embroidery fonts are looked up in
    /// `embroideryFonts`). A guide whose fill or lettering is gone, or whose lettering is no longer On a line, stays an
    /// unstitched line, no longer linked. A fill or lettering whose guide was deleted keeps the last path, so it
    /// sews as before. Returns why any lettering couldn't be rebuilt (it's left as it was).
    @discardableResult
    public mutating func syncGuides(embroideryFonts: [EmbroideryFont] = []) -> [String] {
        guard objects.contains(where: { $0.guideFor != nil }) else { return [] }
        let fills = Dictionary(objects.enumerated().filter { $0.element.kind == .fill }.map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let onLine = Set(objects.compactMap { $0.lettering?.shape == .onLine ? $0.lettering?.id : nil })
        var guided: Set<UUID> = [], reshaped: [(id: UUID, path: [Point])] = []
        for i in objects.indices {
            guard let target = objects[i].guideFor else { continue }
            // Linked to something that isn't there (or a second guide for the same thing): just an unstitched line.
            guard objects[i].kind == .vector, fills[target] != nil || onLine.contains(target), !guided.contains(target) else { objects[i].guideFor = nil; continue }
            guided.insert(target)
            let path = objects[i].outlinePaths.first ?? []
            if let f = fills[target] {
                if objects[f].digitizing?.guideLine != path { objects[f].digitizing?.guideLine = path }
            } else { reshaped.append((target, path)) }
        }
        var problems: [String] = []
        for (id, path) in reshaped {
            let letters = letteringObjects(id)
            // Moving the letters and their guide together moves the stored path too: only a reshaped guide rebuilds.
            guard var spec = letters.first?.lettering, let color = letters.first?.color, !Self.samePath(spec.path, path), !letters.contains(where: \.locked) else { continue }
            spec.path = path
            if abs(spec.currentHeight - spec.height) > 0.05 { spec.height = spec.currentHeight }
            do { replaceLettering(id, with: try spec.build(color: color, embroideryFonts: embroideryFonts)) }
            catch { problems.append("“\(spec.text)”: \(error.localizedDescription)") }
        }
        return problems
    }

    /// True when two paths are the same within a hundredth of a millimetre.
    static func samePath(_ a: [Point]?, _ b: [Point]) -> Bool {
        guard let a, a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.distance(to: $1) < 0.01 }
    }

    /// After copying objects (`copies` maps each original's id, and each original lettering's id, to its copy's),
    /// links each copied guide to the copy of what it guided. A guide copied alone is just an unstitched line.
    public mutating func relinkCopiedGuides(_ copies: [UUID: UUID]) {
        let made = Set(copies.values)
        for i in objects.indices where made.contains(objects[i].id) {
            if let old = objects[i].guideFor { objects[i].guideFor = copies[old] }
        }
    }
}
