// Thread charts: lists of real threads (brand, color number, name, color) that a design's threads can be matched to,
// so the worksheet and machine files name the actual spool. Charts are GIMP palette files (.gpl), the format
// Ink/Stitch and many thread makers publish, so the charts bundled with the app and the ones you import read the same way.
import Foundation

public struct ThreadChart: Hashable, Sendable, Identifiable {
    /// The chart's name, which is also the brand stored on its threads (e.g. "Madeira Polyneon").
    public var name: String
    public var threads: [ThreadColor]
    public var id: String { name }
    public init(name: String, threads: [ThreadColor]) { self.name = name; self.threads = threads }

    /// Limits for imported files, so a wrong or damaged file can't flood the app.
    public static let maxBytes = 1_000_000, maxThreads = 5_000

    /// Reads a GIMP palette. The first line must be "GIMP Palette"; a "Name:" line names the chart (otherwise
    /// `fallbackName`, usually the file name). Each color line is "R G B name code": three numbers 0–255, then the
    /// thread's name. When the line has more than one word after the numbers and the last word contains a digit
    /// (like "1610" or "0015"), that word is the thread's color number. Lines starting with # are comments.
    /// Throws when the file isn't a palette or has no colors.
    public static func parse(_ text: String, fallbackName: String) throws -> ThreadChart {
        guard text.utf8.count <= maxBytes else { throw DesignError.invalid("That palette file is too large to be a thread chart.") }
        var lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "GIMP Palette" else {
            throw DesignError.invalid("That isn't a GIMP palette (.gpl) file: its first line should be “GIMP Palette”.")
        }
        lines.removeFirst()
        var name = fallbackName, threads: [ThreadColor] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("Columns:") { continue }
            if trimmed.hasPrefix("Name:") {
                // Ink/Stitch names its charts "Ink/Stitch: Madeira Polyneon"; keep the part after the last colon.
                let value = trimmed.dropFirst(5).split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                if !value.isEmpty { name = String(value.prefix(100)) }
                continue
            }
            let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard words.count >= 3, let r = Int(words[0]), let g = Int(words[1]), let b = Int(words[2]),
                  [r, g, b].allSatisfy({ (0...255).contains($0) }) else { continue }   // not a color line
            var rest = Array(words.dropFirst(3)), code: String?
            if rest.count >= 2, let last = rest.last, last.count <= 32, last.contains(where: \.isNumber) { code = last; rest.removeLast() }
            let threadName = rest.isEmpty ? String(format: "#%02X%02X%02X", r, g, b) : String(rest.joined(separator: " ").prefix(100))
            threads.append(ThreadColor(threadName, r << 16 | g << 8 | b, code: code))
            guard threads.count <= maxThreads else { throw DesignError.invalid("That palette has more than \(maxThreads.formatted()) colors.") }
        }
        guard !threads.isEmpty else { throw DesignError.invalid("That palette file has no colors in it.") }
        for index in threads.indices { threads[index].brand = name }
        return ThreadChart(name: name, threads: threads)
    }

    /// Every readable chart in a folder (files ending .gpl), sorted by name. Files that can't be read are skipped.
    public static func all(in folder: URL) -> [ThreadChart] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "gpl" }
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).flatMap { try? parse($0, fallbackName: url.deletingPathExtension().lastPathComponent) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The chart's threads closest in color to `hex`, closest first (at most `count` of them).
    public func nearest(to hex: Int, count: Int = 1) -> [ThreadColor] {
        Array(threads.enumerated().sorted { a, b in
            let da = Self.distance(a.element.hex, hex), db = Self.distance(b.element.hex, hex)
            return da != db ? da < db : a.offset < b.offset   // ties keep chart order, so results never shuffle
        }.prefix(count).map(\.element))
    }

    /// How different two colors look. This is the "red mean" formula: plain RGB distance, weighted the way the
    /// eye is more sensitive to green and to differences in reds or blues depending on how red the color is.
    /// Cheap, and close enough to tell thread colors apart.
    public static func distance(_ a: Int, _ b: Int) -> Double {
        let r1 = Double(a >> 16 & 255), g1 = Double(a >> 8 & 255), b1 = Double(a & 255)
        let r2 = Double(b >> 16 & 255), g2 = Double(b >> 8 & 255), b2 = Double(b & 255)
        let mean = (r1 + r2) / 2, dr = r1 - r2, dg = g1 - g2, db = b1 - b2
        return ((2 + mean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - mean) / 256) * db * db).squareRoot()
    }
}

extension Design {
    /// Matches every unlocked object's thread to the closest thread in `chart` (Match All). Returns how many objects
    /// changed thread. Objects that were the same color before stay the same thread after.
    @discardableResult
    public mutating func matchThreads(to chart: ThreadChart) -> Int {
        var changed = 0
        for index in objects.indices where !objects[index].locked {
            guard let match = chart.nearest(to: objects[index].color.hex).first, match != objects[index].color else { continue }
            objects[index].color = match; changed += 1
        }
        return changed
    }
}
