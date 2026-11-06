// Finds the design files in a folder for the Design Library window: OpenHoop projects and machine files (PES, DST…),
// in its subfolders too, and narrows and orders them for a search. It only reads folder listings, never the files
// themselves, and never changes anything.
import Foundation

/// One design file the library found.
public struct LibraryFile: Hashable, Sendable {
    public var url: URL
    /// The machine format (PES, DST…), or nil for an OpenHoop project.
    public var format: MachineFormat?
    /// When the file last changed; the library uses it to notice a file was saved again and draw it anew.
    public var modified: Date
    public init(url: URL, format: MachineFormat?, modified: Date) { self.url = url; self.format = format; self.modified = modified }
    /// The file name without its extension, as the library shows it.
    public var name: String { url.deletingPathExtension().lastPathComponent }
}

/// The orders the library can show its designs in.
public enum LibrarySort: String, CaseIterable, Sendable {
    case name, newest
    public var title: String { self == .name ? "Name" : "Newest First" }
}

public enum DesignLibrary {
    /// The extension of OpenHoop's own project files (each one is a folder that Finder shows as a single file).
    public static let projectExtension = "stitchproj"
    /// The most files one folder lists, so a folder like a whole disk can't stall the library.
    public static let mostFiles = 5000

    /// Every design file in `folder` and its subfolders, at most `mostFiles` of them. Hidden files are skipped, and
    /// so is the inside of each project (it holds design.json and a picture, not designs of its own).
    public static func files(in folder: URL) -> [LibraryFile] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        // An enumerator walks the folder and every folder inside it, one entry at a time.
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var found: [LibraryFile] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = values?.isDirectory ?? false
            let modified = values?.contentModificationDate ?? .distantPast
            let suffix = url.pathExtension.lowercased()
            if suffix == projectExtension {
                found.append(LibraryFile(url: url, format: nil, modified: modified))
                if isFolder { walker.skipDescendants() }
            } else if !isFolder, let format = MachineFormat(rawValue: suffix) {
                found.append(LibraryFile(url: url, format: format, modified: modified))
            }
            if found.count >= mostFiles { break }
        }
        return found
    }

    /// The files whose names contain `search` (ignoring capitals and accents; an empty search keeps them all), in
    /// the order `sort` asks for. Names compare the way Finder does, so "Rose 2" comes before "Rose 10".
    public static func matching(_ files: [LibraryFile], search: String, sort: LibrarySort) -> [LibraryFile] {
        let words = search.trimmingCharacters(in: .whitespaces)
        let kept = words.isEmpty ? files : files.filter { $0.name.localizedStandardContains(words) }
        switch sort {
        case .name: return kept.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .newest: return kept.sorted { $0.modified > $1.modified }
        }
    }
}
