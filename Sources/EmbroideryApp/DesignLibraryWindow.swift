// The Design Library window (Window › Design Library…): the folders you add down the left, and the designs in the
// one picked as pictures on the right, each with its size, stitches and colors. Double-click opens a design: a
// project as itself, a machine file (PES, DST…) as a new untitled design, so the file itself is never changed.
// Finding the files is DesignLibrary.swift (EmbroideryCore); this file reads them, draws them and opens them.
import AppKit
import EmbroideryCore
import SwiftUI

/// What reading one design file found. It's made away from the main thread, so it holds the picture as PNG bytes
/// (or the stitches to draw one from) rather than an image, which can only be drawn on the main thread.
struct LibraryReading: Sendable {
    var picturePNG: Data?
    /// The design's objects, for drawing a picture when the file has none saved (machine files, older projects).
    var objects: [RunObject] = []
    var width: Double?
    var height: Double?
    var stitches: Int?
    var colors: Int?
    /// Why the file couldn't be read, shown on its card instead of a picture.
    var problem: String?

    /// Reads `file`. This is slow work (a machine file goes through the format helper), so it runs in the background.
    static func read(_ file: LibraryFile) -> LibraryReading {
        if let format = file.format { return machine(file.url, format: format) }
        return project(file.url)
    }

    /// A machine file's stitches as objects, one per thread color, the way File › Import Machine Stitches makes them.
    static func objects(of url: URL, format: MachineFormat) throws -> (objects: [RunObject], response: ImportResponse) {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else { throw DesignError.invalid("This file is larger than 5 MB.") }
        let response = try Exporter.readMachine(try Data(contentsOf: url), format: format)
        let objects = try MachineImport.objects(from: response.plan!, format: format.rawValue, name: url.deletingPathExtension().lastPathComponent)
        return (objects, response)
    }

    private static func machine(_ url: URL, format: MachineFormat) -> LibraryReading {
        var reading = LibraryReading()
        do {
            let (objects, response) = try objects(of: url, format: format)
            reading.objects = objects
            reading.width = response.width; reading.height = response.height
            reading.stitches = response.stitchCount ?? response.plan?.stitchCount
            reading.colors = Set(objects.map(\.color)).count
        } catch {
            reading.problem = "Can't read this file"
        }
        return reading
    }

    private static func project(_ folder: URL) -> LibraryReading {
        var reading = LibraryReading()
        // The picture OpenHoop saves inside every project (the one Finder shows too).
        reading.picturePNG = try? Data(contentsOf: folder.appendingPathComponent("QuickLook/Thumbnail.png"))
        let json = folder.appendingPathComponent("design.json")
        // Very big designs are left at just their picture: decoding tens of megabytes for one card would hold up the rest.
        guard (try? json.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) ?? .max < 20_000_000,
              let bytes = try? Data(contentsOf: json), let design = try? JSONDecoder().decode(Design.self, from: bytes) else {
            if reading.picturePNG == nil { reading.problem = "Can't read this project" }
            return reading
        }
        if reading.picturePNG == nil { reading.objects = design.objects }
        // The stitches saved with the project (when it has them) give the count, colors and size.
        let points: [Point]
        if let plan = design.cachedPlan, plan.stitchCount > 0 {
            reading.stitches = plan.stitchCount
            reading.colors = Set(plan.threads).count
            points = plan.commands.filter { $0.op == .stitch }.map(\.point)
        } else {
            // Saved without its stitches: the shapes' outlines still give the size and colors (but not a stitch count).
            if !design.objects.isEmpty { reading.colors = Set(design.objects.map(\.color)).count }
            points = design.objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        }
        if let left = points.map(\.x).min(), let right = points.map(\.x).max(), let bottom = points.map(\.y).min(), let top = points.map(\.y).max() {
            reading.width = right - left; reading.height = top - bottom
        }
        return reading
    }
}

/// A design's card details, ready to show: the reading above with its picture drawn.
struct LibraryDetails {
    var picture: NSImage?
    var reading: LibraryReading

    @MainActor init(_ reading: LibraryReading) {
        self.reading = reading
        if let png = reading.picturePNG { picture = NSImage(data: png) }
        else if !reading.objects.isEmpty, let png = StitchThumbnail.png(of: reading.objects) { picture = NSImage(data: png) }
    }
}

/// Everything the library window shows and remembers: the folders, the files in the one on show, and what's been
/// read from them so far. Details stay while OpenHoop runs, so reopening the window or a folder is quick; a file
/// saved again since has a new date, which makes it a new entry and so it's read again.
@MainActor final class DesignLibraryModel: ObservableObject {
    @Published private(set) var folders: [URL]
    /// The folder whose designs are on show.
    @Published private(set) var folder: URL?
    @Published private(set) var files: [LibraryFile] = []
    @Published private(set) var details: [LibraryFile: LibraryDetails] = [:]
    @Published private(set) var scanning = false
    @Published var search = ""
    @Published var sort = LibrarySort.name
    @Published var selected: LibraryFile?
    /// The folder listing and reading under way, cancelled when another folder is picked.
    private var work: Task<Void, Never>?
    /// How many files are read at the same time.
    private static let readersAtOnce = 4

    init() {
        folders = (Preferences.shared.data.libraryFolders ?? []).map { URL(fileURLWithPath: $0) }
        folder = folders.first
    }

    /// The files on show, after the search and in the chosen order.
    var shown: [LibraryFile] { DesignLibrary.matching(files, search: search, sort: sort) }

    /// Asks for a folder and adds it (unless it's already there), then shows it.
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Add"; panel.message = "Choose a folder of designs. Folders inside it are included too."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !folders.contains(url) { folders.append(url); saveFolders() }
        show(url)
    }

    /// Takes a folder out of the library. The folder and its files stay where they are.
    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }; saveFolders()
        if folder == url { show(folders.first) }
    }

    func show(_ url: URL?) {
        folder = url; selected = nil; files = []
        refresh()
    }

    /// Lists the folder on show again (finding designs saved since), then reads the files not read yet, in the
    /// order they're shown, so the top of the window fills in first.
    func refresh() {
        work?.cancel()
        guard let folder else { files = []; scanning = false; return }
        scanning = true
        work = Task {
            // Task.detached runs the listing away from the main thread, so the window stays responsive.
            let found = await Task.detached { DesignLibrary.files(in: folder) }.value
            guard !Task.isCancelled else { return }
            files = found; scanning = false
            await read(shown.filter { details[$0] == nil })
        }
    }

    /// Reads `waiting`, a few files at a time, and shows each one's details as soon as it's read.
    private func read(_ waiting: [LibraryFile]) async {
        // A task group runs several pieces of work at the same time and hands back each result as it finishes.
        await withTaskGroup(of: (LibraryFile, LibraryReading).self) { group in
            var next = 0
            while next < min(Self.readersAtOnce, waiting.count) {
                let file = waiting[next]; next += 1
                group.addTask { (file, LibraryReading.read(file)) }
            }
            for await (file, reading) in group {
                if Task.isCancelled { group.cancelAll(); return }
                details[file] = LibraryDetails(reading)
                // One finished, so start the next.
                if next < waiting.count {
                    let file = waiting[next]; next += 1
                    group.addTask { (file, LibraryReading.read(file)) }
                }
            }
        }
    }

    private func saveFolders() {
        Preferences.shared.data.libraryFolders = folders.map(\.path)
        Preferences.shared.save()
    }
}

/// The window's contents: folders on the left, a search bar and the design cards on the right.
struct DesignLibraryView: View {
    @ObservedObject var model: DesignLibraryModel
    @ObservedObject private var preferences = Preferences.shared
    /// Opens a design (a project as itself, a machine file as a new design).
    var open: (LibraryFile) -> Void
    /// Adds a machine file's stitches to the design in the front design window; nil when no design is open.
    var addToDesign: (LibraryFile) -> Void
    var canAddToDesign: () -> Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Rectangle().fill(Theme.cardBorder).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Theme.divider).frame(height: 1)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.ground)
        .frame(minWidth: 640, minHeight: 420)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOLDERS").font(Theme.caption).foregroundStyle(Theme.inkSecondary).padding(.horizontal, 14).padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) { ForEach(model.folders, id: \.self) { folderRow($0) } }
            }
            Button { model.addFolder() } label: { Label("Add Folder…", systemImage: "plus") }
                .buttonStyle(.borderless).foregroundStyle(Theme.accent).padding(14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card)
    }

    private func folderRow(_ url: URL) -> some View {
        let picked = url == model.folder
        return Button { model.show(url) } label: {
            Label(url.lastPathComponent, systemImage: "folder").font(Theme.body(13)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(picked ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(picked ? Theme.accent : Theme.ink).padding(.horizontal, 6)
        .help(url.path)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Remove from Library") { model.removeFolder(url) }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSecondary)
                TextField("Search names", text: $model.search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.controlBorder))
            .frame(maxWidth: 260)
            Picker("Sort", selection: $model.sort) { ForEach(LibrarySort.allCases, id: \.self) { Text($0.title).tag($0) } }
                .labelsHidden().fixedSize()
            Spacer()
            if model.folder != nil {
                Text(countText).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Look again for designs added to this folder")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var countText: String {
        if model.scanning { return "Looking…" }
        let shown = model.shown.count, all = model.files.count
        return shown == all ? "\(all) design\(all == 1 ? "" : "s")" : "\(shown) of \(all)"
    }

    @ViewBuilder private var content: some View {
        let shown = model.shown
        if model.folders.isEmpty {
            message("Add a folder of designs to see them here as pictures.", addButton: true)
        } else if shown.isEmpty {
            if model.scanning { ProgressView() }
            else { message(model.files.isEmpty ? "No designs in this folder." : "No designs match “\(model.search)”.", addButton: false) }
        } else {
            ScrollView {
                // .adaptive fits as many columns as the window's width allows, each 170–240 points wide.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 14)], spacing: 14) {
                    ForEach(shown, id: \.self) { card($0) }
                }
                .padding(14)
            }
        }
    }

    private func message(_ text: String, addButton: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(Theme.inkSecondary)
            Text(text).font(Theme.body(14)).foregroundStyle(Theme.inkSecondary)
            if addButton { Button("Add Folder…") { model.addFolder() } }
        }
    }

    private func card(_ file: LibraryFile) -> some View {
        let details = model.details[file], picked = model.selected == file
        return VStack(alignment: .leading, spacing: 3) {
            // A clear square the picture sits in, so every card is the same height, with or without a picture yet.
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let picture = details?.picture {
                        Image(nsImage: picture).resizable().interpolation(.high).scaledToFit()
                    } else if let problem = details?.reading.problem {
                        VStack(spacing: 6) { Image(systemName: "exclamationmark.triangle"); Text(problem).font(Theme.body(11)) }.foregroundStyle(Theme.inkSecondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .overlay(alignment: .topLeading) { if let format = file.format { formatTag(format) } }
                .padding(.bottom, 3)
            Text(file.name).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
            Text(sizeLine(details)).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            Text(stitchLine(details)).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
        }
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(picked ? Theme.accent : Theme.cardBorder, lineWidth: picked ? 2 : 1))
        .contentShape(Rectangle())
        // A double-click opens; the single click alongside it picks the card straight away.
        .onTapGesture(count: 2) { open(file) }
        .simultaneousGesture(TapGesture().onEnded { model.selected = file })
        .help(file.url.path)
        .contextMenu {
            Button(file.format == nil ? "Open" : "Open as New Design") { open(file) }
            if file.format != nil { Button("Add to Current Design") { addToDesign(file) }.disabled(!canAddToDesign()) }
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
    }

    /// "92.0 × 88.0 mm", or a dash until it's known.
    private func sizeLine(_ details: LibraryDetails?) -> String {
        guard let width = details?.reading.width, let height = details?.reading.height else { return "–" }
        return preferences.unit.size(width, height)
    }

    /// A machine file's format ("PES") in a small tag on its picture; OpenHoop's own projects have none.
    private func formatTag(_ format: MachineFormat) -> some View {
        Text(format.title).font(Theme.caption).foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.cardBorder))
            .padding(5)
    }

    /// "12,345 stitches · 5 colors", or a dash until it's known.
    private func stitchLine(_ details: LibraryDetails?) -> String {
        var parts: [String] = []
        if let stitches = details?.reading.stitches { parts.append("\(stitches.formatted()) stitches") }
        if let colors = details?.reading.colors { parts.append("\(colors) color\(colors == 1 ? "" : "s")") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}

/// The one Design Library window, made the first time it's opened and kept (with what it has read) after it's closed.
@MainActor final class DesignLibraryWindow {
    static let shared = DesignLibraryWindow()
    let model = DesignLibraryModel()
    private var window: NSWindow?

    /// Window › Design Library…: brings the window forward and looks again for designs added since it was last open.
    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Design Library"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DesignLibraryView(model: model, open: { [weak self] in self?.open($0) },
                                                                           addToDesign: { [weak self] in self?.addToDesign($0) },
                                                                           canAddToDesign: { [weak self] in self?.frontDesign != nil }))
            // Remembers where the window was put and how big, between launches; the first time it's centered.
            if !window.setFrameUsingName("DesignLibrary") { window.center() }
            window.setFrameAutosaveName("DesignLibrary")
            self.window = window
        }
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The design in the front-most design window, behind the library: the one "Add to Current Design" adds to.
    private var frontDesign: EditorWindowController? {
        NSApp.orderedWindows.lazy.compactMap { $0.windowController as? EditorWindowController }.first
    }

    private func open(_ file: LibraryFile) {
        guard let format = file.format else {
            NSDocumentController.shared.openDocument(withContentsOf: file.url, display: true) { _, _, error in
                if let error { AppDelegate.shared.showError(error) }
            }
            return
        }
        Task {
            do {
                let (objects, _) = try await Task.detached { try LibraryReading.objects(of: file.url, format: format) }.value
                let document = DesignDocument()
                Preferences.shared.startNewDesign(&document.state.design)
                document.state.design.objects = objects
                try document.state.design.validate()
                // The file's name becomes the new design's name, which Save then suggests.
                document.displayName = file.name
                NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows()
                document.updateChangeCount(.changeDone)
                let hoop = document.state.design.hoop
                let fits = !objects.flatMap(\.allNodes).contains { !hoop.contains($0.point) }
                document.state.status = "Opened \(file.url.lastPathComponent) as a new design; the file itself is unchanged."
                    + (fits ? "" : " It's bigger than the hoop, so pick a larger hoop for it.")
            } catch {
                AppDelegate.shared.showError(error)
            }
        }
    }

    private func addToDesign(_ file: LibraryFile) {
        guard let editor = frontDesign else { return }
        editor.window?.makeKeyAndOrderFront(nil)
        AppDelegate.shared.importMachine(editor.state, file: file.url)
    }
}
