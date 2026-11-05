// Keeping stitch settings changed in Properties when lettering is rebuilt (new text, font, size, shape...). The
// changes aren't stored anywhere: they're found by comparing the letters with the same lettering freshly built from
// its recipe, so whatever differs was changed by hand, and then put on the rebuilt letters.

import Foundation

enum LetterSettings {
    /// Settings changed by hand on one part: setting name → its value (nil where it was cleared). "angle" holds a
    /// turn from the font's own angle; "stitchLength" is the object's stitch length.
    typealias Changes = [String: NSObject?]
    /// Settings that aren't carried over: the stitch kind (a part converted to another kind is a different part), and
    /// what belongs to one letter's shape or place: its fill angle (carried as a turn instead), stitch angle lines,
    /// and a radial fill's center.
    static let skipped: Set<String> = ["kind", "angle", "radialCenter", "angleLines", "angleLineCenter", "guideLine"]

    /// Where each part sits: its letter (line × 1000 + place) and its place among that letter's parts, in sewing order.
    private struct Place: Hashable { var letter: Int; var part: Int }
    private static func places(_ objects: [RunObject]) -> [Place?] {
        var seen: [Int: Int] = [:]
        return objects.map { object in
            guard let letter = object.letterKey else { return nil }
            defer { seen[letter, default: 0] += 1 }
            return Place(letter: letter, part: seen[letter] ?? 0)
        }
    }

    /// `fresh` (the rebuilt lettering) with the settings changed by hand on `current` (its objects before) put back.
    /// `built` is the old recipe freshly built, so a part of `current` that differs from its twin in `built` (same
    /// place, same stitch kind) was changed by hand:
    /// - a change every such part of one stitch kind shares goes on every part of that kind in `fresh`;
    /// - other changes go on the same place in `fresh`, but only on lines in `sameLines` (whose text is unchanged):
    ///   letters are counted by glyph, so after new text that place could hold another letter.
    static func kept(current: [RunObject], built: [RunObject], fresh: [RunObject], sameLines: Set<Int>) -> [RunObject] {
        let builtPlaces = places(built)
        var twin: [Place: Int] = [:]
        for (index, place) in builtPlaces.enumerated() { if let place { twin[place] = index } }
        var perPart: [Place: (kind: StitchKind, changes: Changes)] = [:], byKind: [StitchKind: [Changes]] = [:]
        for (object, place) in zip(current, places(current)) {
            guard let place, let index = twin[place], built[index].kind == object.kind else { continue }
            let found = changes(object, from: built[index])
            perPart[place] = (object.kind, found)
            byKind[object.kind, default: []].append(found)
        }
        // Changes all parts of a kind share: those in the first part's that every other part has too.
        let shared = byKind.mapValues { list in list[0].filter { key, value in list.allSatisfy { $0.keys.contains(key) && $0[key]! == value } } }
        return zip(fresh, places(fresh)).map { object, place in
            var result = object
            if let changes = shared[object.kind], !changes.isEmpty { result = applying(changes, to: result) }
            if let place, sameLines.contains(place.letter / 1000), let own = perPart[place], own.kind == object.kind, !own.changes.isEmpty {
                result = applying(own.changes, to: result)
            }
            return result
        }
    }

    /// `object`'s settings as a dictionary (setting name → value, as saved in a project), plus its stitch length.
    private static func dictionary(_ object: RunObject) -> [String: NSObject] {
        // JSONEncoder writes the settings the way a project file saves them; JSONSerialization reads that back as a
        // dictionary, so settings can be compared and copied by name without listing them all here.
        guard let settings = object.digitizing, let data = try? JSONEncoder().encode(settings),
              var values = (try? JSONSerialization.jsonObject(with: data)) as? [String: NSObject] else { return [:] }
        values["stitchLength"] = object.stitchLength as NSNumber
        return values
    }
    /// What was changed by hand on `object`, compared with `fresh`, its twin as the font makes it.
    private static func changes(_ object: RunObject, from fresh: RunObject) -> Changes {
        let mine = dictionary(object), font = dictionary(fresh)
        var found: Changes = [:]
        for key in Set(mine.keys).union(font.keys) where !skipped.contains(key) && mine[key] != font[key] { found[key] = .some(mine[key]) }
        let turn = Lettering.turned(object.settings.angle, by: -fresh.settings.angle)
        if abs(turn) >= 0.01 { found["angle"] = .some(NSNumber(value: (turn * 100).rounded() / 100)) }
        return found
    }
    /// `object` with `changes` made to its settings.
    private static func applying(_ changes: Changes, to object: RunObject) -> RunObject {
        var object = object, values = dictionary(object)
        for (key, value) in changes where key != "angle" {
            if let value { values[key] = value } else { values.removeValue(forKey: key) }
        }
        if let length = values.removeValue(forKey: "stitchLength") as? NSNumber { object.stitchLength = length.doubleValue }
        if let data = try? JSONSerialization.data(withJSONObject: values), let settings = try? JSONDecoder().decode(DigitizingSettings.self, from: data) {
            object.digitizing = settings
        }
        if case let turn as NSNumber = changes["angle"] ?? nil {
            let angle = object.settings.angle   // read first: Swift won't read and change the object in one statement
            object.digitizing?.angle = Lettering.turned(angle, by: turn.doubleValue)
        }
        return object
    }
}
