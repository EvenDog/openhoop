// AppKit owns document windows and event routing. SwiftUI is used only inside native panels.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import EmbroideryCore

/// A design window. It holds every open design as a tab (one DesignPane each) and shows the chosen one; the
/// window's NSDocument link always points at the design on screen, so saving, the Edited mark and undo follow it.
@MainActor final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    /// Open design windows, oldest first, so a new design can join the front one as a tab.
    private static var open: [EditorWindowController] = []
    private(set) var panes: [DesignPane] = []
    private(set) var selectedPane: DesignPane?
    /// The design on screen.
    var state: EditorState { selectedPane?.state ?? EditorState() }
    let tabModel = TabStripModel()
    private let container = NSViewController()
    private var floating: FloatingPanels?
    /// The floating panel layout last shown, so unchanged preferences don't rebuild the floating windows.
    private var floatingLayout: PanelLayout?
    private var observers: [NSObjectProtocol] = []
    /// True while the window's close button is closing every tab in turn.
    private var closingAll = false
    /// The design that was on screen when a background tab's × was clicked, shown again once that tab is closed.
    private weak var returnAfterClose: DesignPane?

    init(document: DesignDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1250, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 900, height: 600); window.title = "OpenHoop"; window.center()
        // One compact title bar row in the app's own color: window buttons, design tabs, then the toolbar buttons.
        window.toolbarStyle = .unifiedCompact; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.backgroundColor = NSColor(Theme.card); window.titlebarSeparatorStyle = .line
        window.tabbingMode = .disallowed   // OpenHoop's own tabs replace the macOS ones
        super.init(window: window)
        window.delegate = self
        container.view = NSView()
        window.contentViewController = container
        // The close button closes the tabs one at a time, so each design can ask to be saved.
        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(closeWindowClicked(_:))
        tabModel.onSelect = { [weak self] id in MainActor.assumeIsolated { if let pane = self?.panes.first(where: { ObjectIdentifier($0) == id }) { self?.select(pane) } } }
        tabModel.onClose = { [weak self] id in MainActor.assumeIsolated { if let pane = self?.panes.first(where: { ObjectIdentifier($0) == id }) { self?.closeTab(pane) } } }
        let toolbar = NSToolbar(identifier: "EmbroideryToolbar"); toolbar.delegate = self; toolbar.allowsUserCustomization = true; toolbar.autosavesConfiguration = true; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        // Restores the size and place the window was last left at. This comes after the content and toolbar,
        // because setting those resizes the window and would undo it.
        window.setFrameAutosaveName("DesignWindow")
        observers.append(NotificationCenter.default.addObserver(forName: .preferencesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyWorkspace(); self?.updateToolbarHints(); self?.state.canvas?.needsDisplay = true }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .designTabsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTabs() }
        })
        Self.open.append(self)
        addTab(for: document)
        DispatchQueue.main.async { [weak self] in
            self?.addDesignTabsOnce(toolbar)
            self?.removeImportImageOnce(toolbar)
        }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }

    /// The window a new or opened design joins as a tab: the front design window, if there is one.
    static func tabHost() -> EditorWindowController? {
        let front = NSApp.orderedWindows.lazy.compactMap { $0.windowController as? EditorWindowController }.first { !$0.panes.isEmpty }
        return front ?? open.last { !$0.panes.isEmpty }
    }
    /// The window showing `document` as a tab, if any.
    static func host(of document: DesignDocument) -> EditorWindowController? {
        open.first { $0.panes.contains { $0.document === document } }
    }

    /// Adds a design as a new tab and shows it.
    func addTab(for document: DesignDocument) {
        let pane = DesignPane(document: document)
        panes.append(pane)
        select(pane)
    }
    /// Shows a design's tab: its pane fills the window, the floating panels follow it, and the window's document
    /// link moves to it.
    func select(_ pane: DesignPane) {
        guard pane !== selectedPane, panes.contains(where: { $0 === pane }) else { refreshTabs(); return }
        if let old = selectedPane {
            Preferences.shared.data.workspace.panels = old.capturePanels()
            old.view.removeFromSuperview(); old.removeFromParent()
            old.document.removeWindowController(self)
        }
        selectedPane = pane
        container.addChild(pane)
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(pane.view)
        NSLayoutConstraint.activate([
            pane.view.topAnchor.constraint(equalTo: container.view.topAnchor), pane.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
            pane.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor), pane.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor)
        ])
        if !pane.document.windowControllers.contains(where: { $0 === self }) { pane.document.addWindowController(self) }
        // A design that reloaded from disk while its tab was in the background hasn't worked out its stitches yet.
        let state = pane.state
        if !state.busy, state.generationError == nil, !state.hasVersionMismatch, state.compiledRevision != state.revision { pane.document.regenerate() }
        window?.isDocumentEdited = pane.document.isDocumentEdited
        // Floating panels show the chosen design.
        floating?.closeAll(); floating = window.map { FloatingPanels(owner: $0, state: pane.state) }; floatingLayout = nil
        applyWorkspace()
        refreshTabs()
        let firstShowing = !pane.hasBeenShown
        pane.hasBeenShown = true
        DispatchQueue.main.async { [weak pane] in
            if firstShowing { pane?.state.canvas?.fit() }
            pane?.state.focusCanvas()
        }
    }
    /// Shows the tab to the right (+1) or left (-1) of the chosen one, wrapping around.
    func selectNeighbor(_ step: Int) {
        guard let current = selectedPane, let index = panes.firstIndex(where: { $0 === current }), panes.count > 1 else { return }
        select(panes[(index + step + panes.count) % panes.count])
    }
    /// Closes a design's tab, first asking to save it if needed. A tab with unsaved changes is shown while asking;
    /// closing a tab in the background leaves the design you're working on on screen.
    func closeTab(_ pane: DesignPane) {
        returnAfterClose = (pane === selectedPane || closingAll) ? nil : selectedPane
        if pane.document.isDocumentEdited { select(pane) }
        pane.document.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }
    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let returnTo = returnAfterClose; returnAfterClose = nil
        if shouldClose { document.close() }   // DesignDocument.close takes its tab out of this window
        else { closingAll = false }
        if let returnTo, panes.contains(where: { $0 === returnTo }) { select(returnTo) }
        if shouldClose, closingAll, let next = selectedPane { closeTab(next) }
    }
    /// Takes a closing design's tab out, showing its neighbor; the window closes with its last tab.
    func removeTab(for document: DesignDocument) {
        guard let index = panes.firstIndex(where: { $0.document === document }) else { return }
        let pane = panes[index]
        if pane === selectedPane {
            Preferences.shared.data.workspace.panels = pane.capturePanels()
            pane.view.removeFromSuperview(); pane.removeFromParent()
            document.removeWindowController(self)
            selectedPane = nil
        }
        panes.remove(at: index)
        if selectedPane == nil, let next = tabToSelect(afterClosing: index, count: panes.count + 1) { select(panes[next]) }
        refreshTabs()
        if panes.isEmpty { closingAll = false; Self.open.removeAll { $0 === self }; window?.close() }
    }
    /// The close button: close every tab, asking to save each; stops if one is cancelled.
    @objc private func closeWindowClicked(_ sender: Any?) {
        guard let first = selectedPane else { window?.close(); return }
        closingAll = true
        closeTab(first)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if panes.isEmpty { return true }
        closeWindowClicked(nil); return false
    }
    /// Updates the tab strip from the open designs.
    func refreshTabs() {
        // Tabs show the design's name without ".stitchproj", even when Finder is set to show extensions.
        let tabs = panes.map { TabStripModel.Tab(id: ObjectIdentifier($0), title: $0.document.fileURL?.deletingPathExtension().lastPathComponent ?? $0.document.displayName, edited: $0.document.isDocumentEdited) }
        if tabModel.tabs != tabs { tabModel.tabs = tabs }
        let selected = selectedPane.map(ObjectIdentifier.init)
        if tabModel.selected != selected { tabModel.selected = selected }
    }

    /// Shows the saved panel layout: the chosen design's docks, and the floating panel windows.
    func applyWorkspace() {
        selectedPane?.applyWorkspace()
        let layout = Preferences.shared.panels
        guard layout != floatingLayout else { return }
        floatingLayout = layout
        floating?.sync(layout)
    }
    /// The workspace with the docks' current widths, for saving.
    func captureWorkspace() -> Workspace {
        var workspace = Preferences.shared.data.workspace
        workspace.panels = selectedPane?.capturePanels() ?? Preferences.shared.panels
        return workspace
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.designTabs, .flexibleSpace, .space] + CommandID.allCases.filter { ![.finishPath, .cancelPath, .removePoint].contains($0) }.map { .init($0.rawValue) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // The design tabs take the free width; tools live in the docked tool strip, so the rest are document actions.
        // (Import Reference Image is left out: it's in the File menu, ⌘I, and the tool strip's artwork button.)
        [.designTabs, .init(CommandID.undo.rawValue), .init(CommandID.redo.rawValue), .space, .init(CommandID.exportMachine.rawValue)]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == .designTabs {
            // The tabs stretch to fill the room the other buttons leave (at least room for two tabs).
            let host = NSHostingView(rootView: TabStripView(model: tabModel))
            host.translatesAutoresizingMaskIntoConstraints = false
            let wide = host.widthAnchor.constraint(equalToConstant: 4000); wide.priority = .defaultLow
            NSLayoutConstraint.activate([host.widthAnchor.constraint(greaterThanOrEqualToConstant: 200), wide, host.heightAnchor.constraint(equalToConstant: 30)])
            let item = NSToolbarItem(itemIdentifier: identifier); item.view = host
            item.label = "Designs"; item.paletteLabel = "Design Tabs"; item.visibilityPriority = .high
            return item
        }
        guard let command = CommandID(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier); item.label = command.title; item.paletteLabel = command.title
        item.image = NSImage.drawn(command.symbol, size: 14) ?? NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.title)
        item.target = AppDelegate.shared; item.action = #selector(AppDelegate.toolbarAction(_:)); item.toolTip = Preferences.shared.hint(command)
        return item
    }
    func updateToolbarHints() {
        for item in window?.toolbar?.items ?? [] {
            if let command = CommandID(rawValue: item.itemIdentifier.rawValue) { item.toolTip = Preferences.shared.hint(command) }
        }
    }
    /// Toolbars remember their items, so the design tabs are added once to toolbars saved before them, at the front,
    /// in place of the flexible space that used to push the buttons apart.
    private func addDesignTabsOnce(_ toolbar: NSToolbar) {
        let key = "AddedDesignTabsToolbarItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !toolbar.items.contains(where: { $0.itemIdentifier == .designTabs }) else { return }
        if let spacer = toolbar.items.firstIndex(where: { $0.itemIdentifier == .flexibleSpace }) { toolbar.removeItem(at: spacer) }
        toolbar.insertItem(withItemIdentifier: .designTabs, at: 0)
    }
    /// Import Reference Image used to be one of the toolbar's buttons. Toolbars saved then lose it once, with the
    /// space after it; it can still be added back with Customize Toolbar.
    private func removeImportImageOnce(_ toolbar: NSToolbar) {
        let key = "RemovedImportImageToolbarItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == CommandID.importImage.rawValue }) else { return }
        toolbar.removeItem(at: index)
        if toolbar.items.indices.contains(index), toolbar.items[index].itemIdentifier == .space { toolbar.removeItem(at: index) }
    }
    func windowWillClose(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
        floating?.closeAll()
        Preferences.shared.data.workspace = captureWorkspace(); Preferences.shared.save()
        Self.open.removeAll { $0 === self }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static let shared = AppDelegate()
    private var settings: NSWindowController?
    private var monitor: Any?
    private var preferenceObserver: NSObjectProtocol?
    private var playbackTimer: Timer?
    /// The design window being worked in: the key window, or the window a key floating panel belongs to.
    var active: EditorWindowController? { (NSApp.keyWindow?.windowController ?? NSApp.keyWindow?.parent?.windowController) as? EditorWindowController }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Tool names and other hover labels show after 0.3 s instead of macOS's usual 1–2 s. NSInitialToolTipDelay
        // (in milliseconds) is an undocumented but long-standing AppKit setting; registering it here changes it for
        // OpenHoop only and saves nothing.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = Preferences.shared.appearance.nsAppearance   // Light, Dark or the Mac's setting, before any window opens
        NSWindow.allowsAutomaticWindowTabbing = false   // designs use OpenHoop's own tabs, not macOS window tabs
        Updates.start()   // before the menu, which offers Check for Updates… once the updater runs
        makeMenu()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                if event.window == self?.settings?.window, let capture = Preferences.shared.recordHandler, let key = Keyboard.binding(event) { capture(key); return true }
                // Escape cancels a dialog even while its text box has the keyboard: a text box otherwise keeps
                // Escape for word completion, so the dialog's Cancel never hears it. (Escape still ends an accent or
                // other character being composed first.) keyCode 53 is the Escape key.
                if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                   let dialog = NSApp.modalWindow, event.window === dialog,
                   let text = dialog.firstResponder as? NSTextView, !text.hasMarkedText() {
                    NSApp.stopModal(withCode: .cancel); return true
                }
                return self?.route(event) == true
            }
            return handled ? nil : event
        }
        preferenceObserver = NotificationCenter.default.addObserver(forName: .preferencesChanged, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.makeMenu() } }
        NSApp.activate(ignoringOtherApps: true)
        // The first launch on this Mac asks about the machine, once the blank design has opened behind it.
        if Preferences.shared.isFirstLaunch { DispatchQueue.main.async { MainActor.assumeIsolated { self.showMachineSetup(firstLaunch: true) } } }
    }
    /// Set Up Your Machine (MachineSetup.swift). After the first launch's welcome, the blank design that opened
    /// starts in the chosen hoop, or makes way for the sample design, which starts in that hoop too.
    func showMachineSetup(firstLaunch: Bool) {
        let openSample = GuidedDialog.machineSetup(firstLaunch: firstLaunch)
        guard firstLaunch else { return }
        let blanks = NSDocumentController.shared.documents.compactMap { $0 as? DesignDocument }
            .filter { $0.fileURL == nil && !$0.isDocumentEdited && $0.state.design.objects.isEmpty }
        if openSample {
            let sample = newDocument(sample: true)
            if let hoop = Preferences.shared.data.newDesignHoop { sample.state.design.hoop = hoop; sample.state.canvas?.fit() }
            for blank in blanks { blank.close() }
        } else {
            for blank in blanks { Preferences.shared.startNewDesign(&blank.state.design); blank.state.canvas?.fit() }
        }
    }
    @objc func setUpMachine(_ sender: Any?) { showMachineSetup(firstLaunch: false) }
    // AppKit asks for a blank design only when the app launches with no files to open (or the Dock icon is
    // clicked with no windows), so double-clicking a project no longer leaves an extra "Untitled" tab behind.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool { newDocument(sample: false); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSDocumentController.shared.closeAllDocuments(withDelegate: self, didCloseAllSelector: #selector(didCloseAll(_:didCloseAll:contextInfo:)), contextInfo: nil)
        return .terminateLater
    }
    @objc private func didCloseAll(_ controller: NSDocumentController, didCloseAll: Bool, contextInfo: UnsafeMutableRawPointer?) { NSApp.reply(toApplicationShouldTerminate: didCloseAll) }
    /// Make Test Swatches: the dialog picks a setting of the selected object and the values to try; the swatches
    /// open as a new design in the same hoop and fabric, ready to export and sew.
    private func makeTestSwatches(_ state: EditorState) {
        guard state.selection.count == 1, let object = state.selected, [.run, .satin, .fill].contains(object.kind) else {
            state.status = "Select one line, fill or satin first; the swatches are copies of it."; return
        }
        guard !SwatchSetting.available(for: object).isEmpty else {
            state.status = "\(object.stitchTitle) has no setting test swatches can step: its own sizes in Properties set its stitches."; return
        }
        guard var design = GuidedDialog.testSwatches(object, hoop: state.design.hoop) else { state.status = "Test swatches cancelled."; return }
        design.fabricType = state.design.fabricType; design.fabricColor = state.design.fabricColor
        let document = DesignDocument(); document.state.design = design
        NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows()
        document.updateChangeCount(.changeDone)
        document.state.status = "\(design.objects.count) test swatches, sewn in order. Each is named after its value."
    }
    @discardableResult func newDocument(sample: Bool, areaSampler:Bool=false) -> DesignDocument {
        let document = DesignDocument(); if sample { document.state.design = Design.sample() };if areaSampler {document.state.design=Design.stitchSampler()}
        // A blank design starts with the hoop and fabric for new designs (sample designs keep the ones they were made for).
        if !sample && !areaSampler { Preferences.shared.startNewDesign(&document.state.design) }
        NSDocumentController.shared.addDocument(document); document.makeWindowControllers(); document.showWindows()
        if sample || areaSampler { document.updateChangeCount(.changeDone) }
        return document
    }
    /// A window-scoped event route prevents canvas shortcuts from stealing normal text input.
    func route(_ event: NSEvent) -> Bool {
        guard NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil, let key = Keyboard.binding(event) else { return false }
        guard let editor = active else {
            guard key.modifiers & 1 != 0,
                  let command = Preferences.shared.profile.command(for: key, context: .text, repeating: event.isARepeat),
                  [.new, .open, .settings, .close].contains(command) else { return false }
            perform(command); return true
        }
        guard event.window == editor.window else { return false }
        let isText = editor.window?.firstResponder is NSTextView
        let context: CommandContext = isText ? .text : (editor.state.draft.isEmpty ? .canvas : .drawing)
        if isText && key.modifiers & 1 == 0 { return false }
        // While Branching waits for its start and end, Return lets OpenHoop choose the point.
        if editor.state.tool == .branch, key == KeyBinding("return") { editor.state.addBranchPoint(nil); return true }
        // With Wreath, Return makes it.
        if editor.state.tool == .wreath, key == KeyBinding("return") { editor.state.applyWreath(); return true }
        guard let command = Preferences.shared.profile.command(for: key, context: context, repeating: event.isARepeat) else { return false }
        // With Edit Nodes and a point selected, the Play key (Space) switches the point between corner and smooth instead.
        if command == .play, editor.state.tool == .node, editor.state.selectedPathNode != nil { perform(.toggleNodeType); return true }
        // With nothing selected, the nudge keys step the stitch player instead.
        if let step = command.stepWithoutSelection, editor.state.selection.isEmpty { perform(step); return true }
        perform(command); return true
    }
    @objc func applySavedLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let workspace = Preferences.shared.data.workspaces.first(where: { $0.id.uuidString == id }) else { return }
        Preferences.shared.data.workspace = workspace; Preferences.shared.save()
    }
    @objc func menuAction(_ sender: NSMenuItem) { if let id = sender.representedObject as? String, let command = CommandID(rawValue: id) { perform(command) } }
    @objc func toolbarAction(_ sender: NSToolbarItem) { if let command = CommandID(rawValue: sender.itemIdentifier.rawValue) { perform(command) } }
    @objc func textAction(_ sender: NSMenuItem) {
        guard let text = NSApp.keyWindow?.firstResponder as? NSTextView, let selector = sender.representedObject as? String else { return }
        NSApp.sendAction(Selector(selector), to: text, from: sender)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(textAction(_:)) { return NSApp.keyWindow?.firstResponder is NSTextView }
        guard let raw = menuItem.representedObject as? String, let command = CommandID(rawValue: raw) else { return true }
        if let panel = PanelID(command: command) { menuItem.state = Preferences.shared.panels.isVisible(panel) ? .on : .off; return true }
        if command == .threadView { menuItem.state = Preferences.shared.threadView ? .on : .off; return true }
        if command == .showRulers { menuItem.state = Preferences.shared.showsRulers ? .on : .off; return true }
        if command == .paletteUnderCanvas { menuItem.state = Preferences.shared.paletteUnderCanvas ? .on : .off; return true }
        if command == .useInches { menuItem.state = Preferences.shared.unit == .inches ? .on : .off; return true }
        if [.new, .open, .sample, .stitchSampler, .settings, .restoreWorkspace, .customizeTools].contains(command) { return true }
        if command == .close { return NSApp.keyWindow != nil }
        guard let state = active?.state else { return false }
        let shown: [CommandID: Bool] = [.reviewSewingOrder: state.reviewing, .showStitches: state.showStitches, .showOutlines: state.showOutlines, .showConnectors: state.showsConnectors, .hideOthers: state.hideOthers,
                                        .grid: state.grid, .snap: state.snap, .needles: state.needles, .showUnderlay: state.showUnderlay, .densityMap: state.showDensity]
        if let on = shown[command] { menuItem.state = on ? .on : .off; return true }
        if command == .cutObjects || command == .copyObjects { return !state.selection.isEmpty }
        if command == .pasteObjects { return NSPasteboard.general.data(forType: .init(ObjectClipboard.pasteboardType)) != nil }
        // Commands that act on the selection are greyed out while nothing is selected (Delete still works on a
        // selected stitch or stitch angle line).
        if command.needsSelection && state.selection.isEmpty && !(command == .delete && (state.tool == .stitchEdit || state.selectedAngle != nil)) { return false }
        if command.isExport || command == .productionWorksheet { return !state.busy && !state.exporting && !state.hasVersionMismatch && state.generationError == nil && state.compiledRevision == state.revision && state.draft.isEmpty && state.plan.stitchCount > 0 }
        return true
    }
    /// The commands that step the review of the sewing order, and which way: the arrow keys (also with nothing
    /// selected, when they'd step the stitch player) and Next and Previous Object.
    private static let reviewSteps: [CommandID: Int] = [.nudgeRight: 1, .nudgeDown: 1, .stepForward: 1, .nextObject: 1,
                                                        .nudgeLeft: -1, .nudgeUp: -1, .stepBackward: -1, .previousObject: -1]
    /// Commands that open a dialog and wait for it to close.
    private static let opensDialog: Set<CommandID> = [.laydown, .testSwatches, .addMonogram, .editMonogram, .autoDigitize, .satinBorder, .outlinesOffsets, .applique, .threadChart, .renameObject, .importImage, .createMotif]
    /// `now` is false unless the command was already put off by one beat (see below).
    func perform(_ command: CommandID, now: Bool = false) {
        // A dialog opened inside a SwiftUI button's action never updates (no typing, no setup), because SwiftUI
        // holds its screen updates until the action returns, and the action is waiting for the dialog. So these
        // commands open on the next pass of the main loop, after the click or key press has finished.
        // RunLoop.perform, not DispatchQueue.main.async: the main queue runs one job at a time, so a dialog opened
        // from a queued job would hold up every job queued while it's open (its text box's cursor and selection).
        if !now, Self.opensDialog.contains(command) { RunLoop.main.perform { MainActor.assumeIsolated { self.perform(command, now: true) } }; return }
        switch command {
        case .new: newDocument(sample: false); return
        case .sample: newDocument(sample: true); return
        case .stitchSampler:newDocument(sample:false,areaSampler:true);return
        case .open: NSDocumentController.shared.openDocument(nil); return
        case .settings: showSettings(); return
        case .close:
            // In a design window, close the design on screen (its tab); elsewhere, close the window.
            if let editor = active, let pane = editor.selectedPane { editor.closeTab(pane) } else { NSApp.keyWindow?.performClose(nil) }
            return
        case .nextTab: active?.selectNeighbor(1); return
        case .previousTab: active?.selectNeighbor(-1); return
        case .restoreWorkspace: Preferences.shared.data.workspace = Workspace(); Preferences.shared.save(); return
        case .customizeTools: customizeTools(); return
        case .paletteUnderCanvas:
            let on = !Preferences.shared.paletteUnderCanvas
            Preferences.shared.setPaletteUnderCanvas(on)
            active?.state.status = on ? "The thread palette is under the canvas." : "The thread palette is docked at the top of the Threads panel."
            return
        case .showRulers:
            let on = !Preferences.shared.showsRulers
            Preferences.shared.setShowRulers(on)
            active?.state.status = on ? "Rulers and guides shown." : "Rulers and guides hidden. Your guides are kept; \(Preferences.shared.key(.showRulers)) brings them back."
            return
        case .useInches:
            let inches = Preferences.shared.unit != .inches
            Preferences.shared.setUnit(inches ? .inches : .millimeters)
            active?.state.status = inches ? "Sizes and positions now show in inches. Stitch settings stay in millimeters." : "Sizes and positions now show in millimeters."
            return
        case .threadView:
            Preferences.shared.setThreadView(!Preferences.shared.threadView)
            active?.state.status = Preferences.shared.threadView ? "Thread View: stitches drawn as thread, as they'll sew." : "Stitch view: thin lines, with travel moves shown."
            return
        case .inspector, .palette, .panelSewingOrder, .panelDesign, .panelReference:
            // Show or hide a panel; showing a hidden one puts it back where it lives in the standard layout.
            guard let panel = PanelID(command: command) else { return }
            Preferences.shared.updatePanels { $0.isVisible(panel) ? $0.hide(panel) : $0.show(panel) }; return
        default: break
        }
        guard let editor = active, let document = editor.document as? DesignDocument else { return }
        let state = editor.state
        if state.reviewing {
            // While reviewing the sewing order, the arrow keys and Next and Previous Object step through it; the
            // stitch player's own commands finish the review first.
            if let delta = Self.reviewSteps[command] { state.stepReview(by: delta); return }
            if command == .play || command == .rewind || command.stitchStep != nil { state.reviewing = false }
        }
        switch command {
        case .save: document.save(nil)
        case .saveAs: document.saveAs(nil)
        case .importImage: importImage(state)
        case .importSVG: importSVG(state)
        case .importMachine: importMachine(state)
        case .productionWorksheet: productionWorksheet(state, name: document.fileURL?.deletingPathExtension().lastPathComponent ?? document.displayName)
        case .exportMachine, .exportThreadList:
            if command == .exportMachine && state.design.multiHooping != nil { exportHoopings(state, name: document.fileURL?.deletingPathExtension().lastPathComponent ?? document.displayName) }
            else { exportMachine(state, threadListOnly: command == .exportThreadList) }
        case .zoomBoxTool:
            // Unlike the other tools, Zoom Box works in the middle of drawing a path: the path waits, and the tool
            // it was being drawn with comes back once the box is drawn.
            if state.tool != .zoomBox { state.toolBeforeZoom = state.tool }
            state.tool = .zoomBox; state.status = "Drag a box around the part to zoom into · Click to zoom in 2× · Esc cancels"
            state.focusCanvas(); state.canvas?.window?.invalidateCursorRects(for: state.canvas!)
        case .selectTool, .runTool, .satinTool, .fillTool, .holeTool, .nodeTool, .panTool, .entryExitTool, .artworkTool, .openShapeTool, .closedShapeTool, .freehandOpenTool, .freehandClosedTool, .rectangleTool, .ellipseTool, .basicShapeTool, .hoopingsTool, .measureTool, .knifeTool, .addStitchAngles, .removeStitchAngles, .lettering:
            if !state.draft.isEmpty { state.status = "Finish the current path with Enter, or cancel with Escape, before changing tools."; return }
            if command == .artworkTool {
                guard let artwork = state.design.artwork else {
                    // No image yet: import one first, then move and size it. The file dialog waits for the next pass
                    // of the main loop, as the commands in opensDialog do.
                    RunLoop.main.perform { MainActor.assumeIsolated {
                        self.importImage(state)
                        if state.design.artwork != nil { self.perform(.artworkTool, now: true) }   // nil if cancelled
                    } }
                    return
                }
                guard artwork.visible else { state.status = "The reference image is hidden. Show it (\(Preferences.shared.key(.artwork))) to move and size it."; return }
            }
            if command == .holeTool {
                guard state.selection.count==1,let object=state.selected,object.kind == .fill,!object.locked else{state.status="Select one unlocked fill before adding a hole.";return}
                state.holeTarget=object.id
            } else {state.holeTarget=nil}
            if command == .addStitchAngles || command == .removeStitchAngles {
                guard state.selection.count==1,let object=state.selected,object.kind == .fill,[.tatami,.satin].contains(object.settings.fillStyle ?? .tatami),!object.locked else{state.status="Select one unlocked tatami or satin fill first.";return}
                if command == .removeStitchAngles && (object.settings.angleLines ?? []).isEmpty {state.status="This fill has no stitch angle lines to remove.";return}
                state.angleTarget=object.id
            } else {state.angleTarget=nil}
            state.angleStart=nil; state.selectedAngle=nil
            state.tool = Tool.forCommand[command] ?? .select
            state.toolPicked = NextShapeOptions.shows(state.tool)   // Properties switches to the tool's choices
            // A closed-shape tool starts with Outline: None; an outline picked then lasts until a tool is picked again.
            if NextShapeOptions.shows(state.tool) && !state.tool.makesOpenShape { Preferences.shared.updateShapes { $0.startWithoutOutline() } }
            switch state.tool {
            case .satin:state.status="Click left edge, then right edge, along the column · Drag while clicking to curve an edge · Enter finishes complete pairs"
            case .fill:state.status="Trace a closed fill outline · Click for corners, drag to pull out a curve · Enter to finish"
            case .hole:state.status="Trace a hole inside the selected fill · Enter to finish · Escape cancels"
            case .run:state.status="Click corners · Drag while clicking to pull out a curve · Secondary-click for an automatic curve · Enter to finish"
            case .node:state.status="Drag nodes · Click an edge to add a corner node, right-click for a curve node · Drag a node's handles to shape its curve (Option: one side) · Delete removes the selected node · Esc when done"
            case .artwork:state.status="Drag the image to move it · Drag a corner to resize (Shift: stretch) · Arrow keys nudge · Esc when done"
            case .entryExit:state.status="Click where the selected object should start sewing · Option-click sets where it ends · Drag a marker to move it · Esc when done"
            case .openShape:state.status="Open shape · Click corners · Drag or secondary-click for curves · Enter to finish"
            case .knife:state.status="Knife · Click points across what to cut (the selection, or anything if nothing is selected) · Return cuts · Esc cancels"
            case .addAngles:state.status="Add Stitch Angles · Click two points across the fill for each line; the stitches run along it · Esc when done"
            case .removeAngles:state.status="Remove Stitch Angles · Click a line to remove it · Esc when done"
            case .measure:state.status="Drag from one point to another to measure the distance and angle · Esc when done"
            case .hooping:state.status=state.design.multiHooping == nil ? "Hoopings · Turn on Multi-hooping in Properties to sew a design bigger than the hoop" : "Hoopings · Drag a hooping to move it · Click one to see what it sews · Esc when done"
            case .text:state.status="Add Lettering · Click where the lettering should go; then type it and pick a font in Properties · Esc cancels"
            case .closedShape:state.status="Closed shape · Click corners · Drag or secondary-click for curves · Enter to finish"
            case .freehandOpen:state.status="Freehand open shape · Press and drag; the line follows the pointer · Let go to finish · Esc cancels"
            case .freehandClosed:state.status="Freehand closed shape · Press and drag; the outline follows the pointer · Let go to finish, it closes itself · Esc cancels"
            case .ellipse:state.status="Drag out from the center · Hold ⌘ for a circle"
            case .rectangle,.basicShape:state.status="Drag to draw the shape · Hold ⌘ to keep it even · Hold ⇧ to draw it from the center"
            default:state.status="Select and drag objects. Shift-click to select more than one, or drag a box round them."
            }
            // Closed shapes say what stitches they'll get, so the Next Shape choices in Properties aren't missed.
            if state.tool == .closedShape || state.tool == .freehandClosed || state.tool.dragsShape {state.status+=" · Next shape: \(Preferences.shared.shapes.closedSummary) (change it in Properties)"}
            state.focusCanvas(); state.canvas?.window?.invalidateCursorRects(for: state.canvas!)
        case .finishPath: if state.tool != .zoomBox { state.finishPath() }
        case .reviewSewingOrder:
            if state.reviewing { state.reviewing = false; state.status = "Review finished."; return }
            playbackTimer?.invalidate(); state.playing = false; state.playback = 1
            if ![.select, .entryExit].contains(state.tool) { state.tool = .select }
            state.reviewing = true; state.reviewShowsRoute = false
            if state.reviewStep == nil { state.stepReview(by: 1) }   // nothing selected: start at the first step
            state.status = "Reviewing the sewing order · ← → step through it · click an object or a step to jump to it · Esc finishes"
            state.focusCanvas()
        case .done where state.reviewing && state.tool == .select:
            state.reviewing = false; state.status = "Review finished."
        case .done where state.tool == .zoomBox, .cancelPath where state.tool == .zoomBox:
            // Escape with Zoom Box on just puts the tool before it back (and keeps a path being drawn).
            state.tool = state.toolBeforeZoom; state.status = "Zoom cancelled."
            state.canvas?.window?.invalidateCursorRects(for: state.canvas!)
        case .done:
            // Escape when not drawing: stop the stitch player, show the whole design, and go back to Select.
            playbackTimer?.invalidate(); state.playing = false; state.playback = 1; state.holeTarget = nil; state.angleStart = nil
            state.stitchEditTarget = nil; state.selectedStitches = []
            if state.tool != .select { state.tool = .select; state.status = "Back to Select. Click an object to pick it, or press a tool's key to start." }
            state.focusCanvas(); state.canvas?.window?.invalidateCursorRects(for: state.canvas!)
        case .cancelPath: state.canvas?.cancelShapeDrag(); state.draft = [];state.holeTarget=nil;if state.tool == .hole{state.tool = .select}; state.status = "Path cancelled."
        case .removePoint: if !state.draft.isEmpty { state.draft.removeLast() }
        case .undo: if !state.draft.isEmpty { state.draft.removeLast() } else { document.undoManager?.undo() }
        case .redo: document.undoManager?.redo()
        case .delete where state.tool == .stitchEdit: state.deleteSelectedStitches()   // needle points, not the object
        case .delete where state.tool == .node && state.selectedNode != nil: state.canvas?.deleteNode()   // the selected point, not the object
        case .delete where state.selectedAngle != nil: state.removeAngleLine(state.selectedAngle!.object, state.selectedAngle!.index)   // a selected stitch angle line, not the whole fill
        case .delete: state.edit("Delete Objects") { $0.objects.removeAll { state.selection.contains($0.id) && !$0.locked } }
        case .selectAll: state.selection = Set(state.design.objects.filter { $0.visible && !$0.locked }.map(\.id)); state.focusCanvas()
        case .duplicate: state.duplicateSelection()
        case .group: state.groupSelection()
        case .autoStartPoints: state.autoStartPoints()
        case .editLettering: editLettering(state)
        case .breakApartLettering: state.breakApartLettering()
        case .autoDigitize: autoDigitize(state)
        case .satinBorder: addSatinBorder(state)
        case .outlinesOffsets: addOutlinesOffsets(state)
        case .applique: makeApplique(state)
        case .laydown: addLaydown(state)
        case .addMonogram: addMonogram(state)
        case .editMonogram: editMonogram(state)
        case .convertSatin: makeSatinColumn(state)
        case .threadChart: chooseThreadFromChart(state)
        case .createMotif: createMotif(state)
        case .cutObjects, .copyObjects: copyObjects(state, cut: command == .cutObjects)
        case .pasteObjects: pasteObjects(state)
        case .clearStartEnd: state.clearStartEnd()
        case .ungroup: state.ungroupSelection()
        case .mirrorH, .mirrorV, .rotateLeft, .rotateRight: state.mirrorOrRotateSelection(command)
        case .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown:
            let step = Preferences.shared.nudge   // the nudge distance, 1 mm unless changed
            let delta = Point(command == .nudgeLeft ? -step : command == .nudgeRight ? step : 0, command == .nudgeDown ? -step : command == .nudgeUp ? step : 0)
            // While adjusting the artwork, arrow keys move the image instead of the selection.
            if state.tool == .artwork { state.edit("Move Artwork") { design in if let center = design.artwork?.center { design.artwork?.center = center + delta } }; return }
            state.editSelected(command.title) { $0.transform{$0+delta} }
        case .earlier, .later:
            state.edit(command.title) { design in
                let indices = command == .earlier ? Array(design.objects.indices) : Array(design.objects.indices.reversed())
                for index in indices where state.selection.contains(design.objects[index].id) {
                    let neighbor = index + (command == .earlier ? -1 : 1)
                    if design.objects.indices.contains(neighbor) && !state.selection.contains(design.objects[neighbor].id) { design.objects.swapAt(index, neighbor) }
                }
            }
        case .sequenceBySelection:
            let order = state.selectionOrder
            guard order.count >= 2 else { state.status = "Shift-click two or more objects on the canvas (⌘-click in the sewing order list) in the order they should sew, then sequence them."; return }
            guard state.edit(command.title, { $0.sequence(order) }) else { return }
            state.status = "The \(order.count) selected objects now sew in the order you clicked them, from where the first of them sewed."
        case .sequenceByColor:
            let changes = { (design: Design) in zip(design.objects, design.objects.dropFirst()).filter { $0.color != $1.color }.count }
            let before = changes(state.design)
            var sorted = state.design
            guard sorted.sequenceByColor() else { state.status = "Each thread's objects already sew together."; return }
            guard state.edit(command.title, { $0 = sorted }) else { return }
            state.status = "Each thread's objects now sew together: \(before) thread change\(before == 1 ? "" : "s") down to \(changes(sorted))."
        case .alignLeft, .alignCentersVertically, .alignRight, .alignTop, .alignCentersHorizontally, .alignBottom, .alignCenters:
            let order = state.selectionOrder
            guard state.design.arrangeUnits(order).count >= 2 else { state.status = "Select two or more objects (or groups) to align. They line up with the one you select last."; return }
            let alignment: [CommandID: ObjectAlignment] = [.alignLeft: .left, .alignCentersVertically: .centersVertically, .alignRight: .right, .alignTop: .top,
                                                     .alignCentersHorizontally: .centersHorizontally, .alignBottom: .bottom, .alignCenters: .centers]
            guard state.edit(command.title, { $0.align(order, alignment[command]!) }) else { return }
            let last = state.design.objects.first { $0.id == order.last }?.name ?? "the last one"
            state.status = "Lined up with \(last), the last one selected."
        case .spaceAcross, .spaceDown:
            let order = state.selectionOrder
            guard state.design.arrangeUnits(order).count >= 3 else { state.status = "Select three or more objects (or groups) to space them evenly."; return }
            guard state.edit(command.title, { $0.spaceEvenly(order, across: command == .spaceAcross) }) else { return }
            state.status = "Spaced evenly; the outer two stayed put."
        case .editStitches:
            guard state.draft.isEmpty else { state.status = "Finish the current path with Enter, or cancel with Escape, first."; return }
            state.startStitchEdit(); state.focusCanvas(); state.canvas?.window?.invalidateCursorRects(for: state.canvas!)
        case .branching:
            guard state.draft.isEmpty else { state.status = "Finish the current path with Enter, or cancel with Escape, first."; return }
            state.startBranching(); state.focusCanvas(); state.canvas?.window?.invalidateCursorRects(for: state.canvas!)
        case .wreath:
            guard state.draft.isEmpty else { state.status = "Finish the current path with Enter, or cancel with Escape, first."; return }
            state.startWreath(); state.focusCanvas(); state.canvas?.window?.invalidateCursorRects(for: state.canvas!)
        case .removeOverlaps:
            guard state.draft.isEmpty else { state.status = "Finish the current path with Enter, or cancel with Escape, first."; return }
            state.removeOverlaps()
        case .weldObjects:
            var next = state.design
            do {
                let ids = try next.weld(state.editableSelection)
                guard !ids.isEmpty else { state.status = "Select two or more fills, closed outlines or satins to weld into one fill."; return }
                let top = state.design.objects.first { $0.id == ids[0] }?.name ?? "the topmost"
                guard state.edit(command.title, { $0 = next }) else { return }
                state.selection = Set(ids); state.selectedNode = nil
                state.status = ids.count == 1 ? "Welded into one fill with the settings of \(top), the topmost." : "Welded. Parts that don't touch became \(ids.count) separate fills."
            } catch { state.status = error.localizedDescription }
        case .smoothShapes:
            var next = state.design
            let removed = next.smoothShapes(state.editableSelection)
            guard removed > 0 else { state.status = state.selection.isEmpty ? "Select the shapes to smooth first." : "Nothing to smooth: every node shapes the outline."; return }
            guard state.edit(command.title, { $0 = next }) else { return }
            state.selectedNode = nil
            state.status = "Removed \(removed) node\(removed == 1 ? "" : "s") that barely shaped the outline (each within 0.2 mm). Smooth again to remove more."
        case .closePath: state.editSelected("Closed Path") { if $0.kind == .run || $0.kind == .vector {$0.closed.toggle()} }
        case .insertNode:state.canvas?.insertNode()
        case .deleteNode:state.canvas?.deleteNode()
        case .toggleNodeType:state.setSelectedNode(smooth:!(state.selectedPathNode?.smooth ?? true))
        case .renameObject:if let object=state.selected,let name=askName("Rename object",value:object.name){state.editSelected("Rename Object"){$0.name=name}}
        case .convertFill,.convertRun:
            guard state.draft.isEmpty else{return}
            guard !state.design.objects.contains(where:{state.selection.contains($0.id) && $0.kind == .raw}) else{state.status="Imported stitches cannot be converted into digitizing outlines. Trace a new object instead.";return}
            if command == .convertFill && state.design.objects.contains(where:{state.selection.contains($0.id) && $0.nodes.count<3}){state.status="Fill needs an outline with at least three nodes.";return}
            if command == .convertRun {
                var selected=state.selection
                state.edit(command.title){design in design.objects=design.objects.flatMap{object in
                    guard state.selection.contains(object.id),!object.locked else{return [object]}
                    let paths=object.runningOutlines();selected.formUnion(paths.map(\.id));return paths
                }}
                state.selection=selected;return
            }
            let fabricDesign=state.design
            state.editSelected(command.title){object in
                if object.kind == .satin {object.nodes=object.nodes.enumerated().filter{$0.offset%2==0}.map(\.element)+object.nodes.enumerated().filter{$0.offset%2==1}.map(\.element).reversed().map(\.reversedDirection);object.closed=true}
                if command == .convertFill{object.digitizing=DigitizingSettings(kind:.fill);object.closed=true;object.stitchLength=3;object=fabricDesign.withFabric(object)}
                else{object.digitizing=nil;object.holes=nil}
            }
        case .removeHoles:state.editSelected(command.title){if $0.kind == .fill{$0.holes=[]}}
        case .toggleUnderlay:state.editSelected(command.title){object in if object.kind == .satin || object.kind == .fill{var settings=object.settings;if settings.underlay == .none {settings.underlay=object.kind == .fill ? .edge:.auto;if object.kind == .fill {settings.secondUnderlay = .tatami}} else {settings.underlay = .none};object.digitizing=settings}}
        case .showUnderlay:state.showUnderlay.toggle()
        case .densityMap:
            state.showDensity.toggle()
            if state.showDensity {
                let cells = DensityMap.cells(state.plan), red = cells.filter { $0.level == .tooDense }.count, yellow = cells.count - red
                state.status = cells.isEmpty ? "Density map: no heavy or over-dense spots." : "Density map: \(red) mm² too dense (red: over 3 layers of thread, or needle holes piling up) · \(yellow) mm² heavy (yellow: over 2 layers)."
            }
        case .testSwatches: makeTestSwatches(state)
        case .useAsFillGuide: state.useSelectedLineAsFillGuide()
        case .putLetteringOnLine: state.putSelectedLetteringOnLine()
        case .tieIn: state.editSelected(command.title) { if $0.kind != .raw {$0.tieInRule = $0.tieIn ? .off : .always} }
        case .tieOut: state.editSelected(command.title) { if $0.kind != .raw {$0.tieOutRule = $0.tieOut ? .off : .always} }
        case .trimAfter: state.editSelected(command.title) { $0.trimAfter.toggle() }
        case .stopAfter: state.editSelected(command.title) { $0.stopAfter.toggle(); $0.stopForJump = nil }   // now a stop set by hand
        case .lockObject: state.edit("Object Lock") { design in for index in design.objects.indices where state.selection.contains(design.objects[index].id) { design.objects[index].locked.toggle() } }
        case .hideObject: state.edit("Object Visibility") { design in for index in design.objects.indices where state.selection.contains(design.objects[index].id) { design.objects[index].visible.toggle() } }
        case .zoomIn: state.zoom = min(60, state.zoom * 1.2)
        case .zoomOut: state.zoom = max(0.5, state.zoom / 1.2)
        case .zoomFit: state.canvas?.fit()
        case .zoomActual:
            guard let canvas = state.canvas, let zoom = canvas.realSizeZoom else { state.status = "This display doesn't report its size, so OpenHoop can't show real size on it."; return }
            canvas.setZoom(zoom); state.status = "Real size: a 10 mm stitch is 10 mm on this screen (as near as the display reports its size)."
        case .zoomDesign:
            guard let box = state.design.bounds(of: Set(state.design.objects.map(\.id))) else { state.canvas?.fit(); state.status = "The design is empty, so the hoop is shown."; return }
            state.canvas?.zoom(to: box)
        case .zoomSelected:
            guard let box = state.design.bounds(of: state.selection) else { state.status = "Select objects first, then zoom to them."; return }
            state.canvas?.zoom(to: box)
        case .grid: state.grid.toggle()
        case .snap: state.snap.toggle()
        case .clearGuides:
            guard !(state.design.guides ?? []).isEmpty else { state.status = "There are no guides. Drag from a ruler to add one."; return }
            guard !state.hasVersionMismatch else { state.status = "Regenerate this older project before changing its guides."; return }
            state.edit("Clear Guides") { $0.guides = nil }; state.status = "Guides cleared. Undo (⌘Z) brings them back."
        case .needles: state.needles.toggle()
        case .showStitches:
            state.showStitches.toggle()
            state.status = state.showStitches ? "Stitches shown." : "Stitches hidden\(state.showOutlines ? "" : ": press \(Preferences.shared.key(.showOutlines)) to see the outlines"). \(Preferences.shared.key(.showStitches)) shows them again."
        case .showOutlines: state.showOutlines.toggle(); state.status = state.showOutlines ? "Every object's outline shown." : "Outlines show only for the selection."
        case .showConnectors: state.connectors = !state.showsConnectors; state.status = state.showsConnectors ? "Connectors shown: the dashed travel moves between parts." : "Connectors hidden."
        case .hideOthers:
            if !state.hideOthers && state.selection.isEmpty { state.status = "Select what to keep in view first, then hide the rest."; return }
            state.hideOthers.toggle()
            state.status = state.hideOthers ? "Only the selection shows. Everything still sews; \(Preferences.shared.key(.hideOthers)) shows the rest again." : "Everything shown again."
        case .artwork: state.edit("Reference Visibility") { $0.artwork?.visible.toggle() }
        case .saveWorkspace:
            if let name = askName("Save workspace layout", value: "My Workspace") { var workspace = editor.captureWorkspace(); workspace.id = UUID(); workspace.name = name; Preferences.shared.data.workspaces.append(workspace); Preferences.shared.data.workspace = workspace; Preferences.shared.save() }
        case .focusLength,.focusSpacing,.focusAngle:
            let identifier=command == .focusLength ? "stitchLength":command == .focusSpacing ? "rowSpacing":"fillAngle"
            func find(_ view: NSView) -> NSView? { if view.identifier?.rawValue == identifier { return view }; for child in view.subviews { if let result = find(child) { return result } }; return nil }
            if let content = editor.window?.contentView, let field = find(content) as? NSTextField { editor.window?.makeFirstResponder(field); field.selectText(nil) }
        case .play:
            if state.playing { state.playing = false; playbackTimer?.invalidate() }
            else {
                if state.playback >= 1 { state.playback = 0 }; state.playing = true; playbackTimer?.invalidate()
                // 30 times a second, move on by 1/30 of the chosen stitches per second. The speed is read on every
                // tick, so changing it while playing takes effect at once.
                // With Pause at trims on (read on every tick too), the player stops where the machine would cut, stop
                // or change thread (PlayerPauses.swift), and Play carries on from there. Each pause is a playback
                // position that shows exactly the commands up to it (the canvas shows that fraction of the commands).
                let commandCount = Double(max(1, state.plan.commands.count))
                let pauses = state.plan.machinePauses.map { (Double($0) + 0.5) / commandCount }
                playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak state] timer in MainActor.assumeIsolated {
                    guard let state else { timer.invalidate(); return }
                    let next = min(1, state.playback + Preferences.shared.playbackSpeed / 30 / max(1, Double(state.plan.stitchCount)))
                    if Preferences.shared.data.pauseAtTrims == true, let pause = pauses.first(where: { $0 > state.playback && $0 <= next }) {
                        state.playback = pause; state.playing = false; timer.invalidate(); return
                    }
                    state.playback = next
                    if state.playback >= 1 { state.playing = false; timer.invalidate() }
                } }
            }
        case .rewind: playbackTimer?.invalidate(); state.playing = false; state.playback = 0
        case .stepForward, .stepBackward, .stepForward10, .stepBackward10, .nextColor, .previousColor, .nextObject, .previousObject, .nextTrim, .previousTrim, .toEnd:
            guard let step = command.stitchStep else { break }
            playbackTimer?.invalidate(); state.playing = false
            // The canvas shows Int(commands × playback) commands, so a position half way into a command shows
            // exactly the commands before it, as the player's pauses do.
            let total = state.plan.commands.count
            let position = state.plan.position(after: step, from: Int(Double(total) * state.playback))
            state.playback = position >= total ? 1 : (Double(position) + 0.5) / Double(max(1, total))
            let shown = state.plan.commands.prefix(position).lazy.filter { $0.op == .stitch }.count
            state.status = "Stitch \(shown.formatted()) of \(state.plan.stitchCount.formatted())."
        default: break
        }
    }
    func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            // The app's own cream title bar, like the design window's, rather than the system's grey one.
            window.title = "Settings"; window.titlebarAppearsTransparent = true; window.backgroundColor = NSColor(Theme.card)
            window.contentView = NSHostingView(rootView: SettingsView()); window.center(); settings = NSWindowController(window: window)
        }
        settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil)
    }
    func askName(_ title: String, value: String) -> String? {
        let alert = NSAlert(); alert.messageText = title; let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 300, height: 24); alert.accessoryView = field; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); return name.isEmpty ? nil : name
    }
    func showError(_ error: Error) { NSAlert(error: error).runModal() }
    private func importMachine(_ state:EditorState) {
        guard !state.hasVersionMismatch,state.draft.isEmpty else{state.status="Finish the current path and regenerate older projects before importing.";return}
        let panel=NSOpenPanel();panel.allowedContentTypes=MachineFormat.allCases.compactMap{UTType(filenameExtension:$0.rawValue)}
        panel.message="Import existing stitches: PES, PEC, DST, EXP, JEF, VP3 or XXX."
        guard panel.runModal() == .OK,let url=panel.url,let format=MachineFormat(rawValue:url.pathExtension.lowercased()) else{return}
        let revision=state.revision
        state.status="Reading machine stitches…"
        Task {
            do {
                let (response,objects)=try await Task.detached(priority:.userInitiated){
                    // Read at most one byte beyond the cap, including files replaced during import.
                    let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
                    let data=try file.read(upToCount:5_000_001) ?? Data()
                    let response=try Exporter.readMachine(data,format:format)
                    let objects=try MachineImport.objects(from:response.plan!,format:format.rawValue,name:url.deletingPathExtension().lastPathComponent)
                    return (response,objects)
                }.value
                guard revision==state.revision,state.draft.isEmpty else{throw DesignError.invalid("The design changed during import. Import the machine file again.")}
                let fitsHoop = !objects.flatMap(\.allNodes).contains(where:{!state.design.hoop.contains($0.point)})
                let report = ImportReport(kind: .machine(format), fileName: url.lastPathComponent, count: response.stitchCount ?? 0, blocks: objects.count, width: response.width ?? 0, height: response.height ?? 0, fitsHoop: fitsHoop, warnings: response.warnings ?? [], objects: objects)
                guard GuidedDialog.run(content: { ImportReportView(report: report, finish: $0) }) else{state.status="Machine import cancelled.";return}
                guard revision==state.revision,state.draft.isEmpty else{throw DesignError.invalid("The design changed. Import the file again.")}
                var next=state.design;next.schemaVersion=4;next.objects+=objects;try next.validate()
                state.edit("Import Machine Stitches"){$0=next};state.selection=Set(objects.map(\.id));state.selectedNode=nil;state.tool = .select;state.focusCanvas()
                state.status="Imported \(response.stitchCount ?? 0) stitches in \(objects.count) thread blocks. Move, recolor or combine them with your digitizing."
            } catch{showError(error);state.status="Machine import failed; design unchanged."}
        }
    }
    private func importSVG(_ state:EditorState) {
        guard !state.hasVersionMismatch,state.draft.isEmpty else{state.status="Finish the current path and regenerate older projects before importing.";return}
        let panel=NSOpenPanel();panel.allowedContentTypes=[.svg];panel.message="Import editable vector outlines. Assign stitches after import."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let revision=state.revision
        state.status="Reading SVG outlines…"
        Task {
            do {
                let result=try await Task.detached(priority:.userInitiated){
                    let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                    guard size<=5_000_000 else{throw DesignError.invalid("Choose an SVG under 5 MB.")}
                    return try SVGImporter.load(Data(contentsOf:url))
                }.value
                guard revision==state.revision,state.draft.isEmpty else{throw DesignError.invalid("The design changed during import. Import the SVG again.")}
                let fitsHoop = !(result.width>state.design.hoop.width || result.height>state.design.hoop.height)
                let report = ImportReport(kind: .svg, fileName: url.lastPathComponent, count: result.objects.count, blocks: result.objects.count, width: result.width, height: result.height, fitsHoop: fitsHoop, warnings: result.warnings, objects: result.objects)
                guard GuidedDialog.run(content: { ImportReportView(report: report, finish: $0) }) else{state.status="SVG import cancelled.";return}
                guard revision==state.revision,state.draft.isEmpty else{throw DesignError.invalid("The design changed. Import the SVG again.")}
                var candidate=state.design;candidate.schemaVersion=4;candidate.objects+=result.objects;try candidate.validate()
                state.edit("Import SVG"){$0=candidate};state.selection=Set(result.objects.map(\.id));state.tool = .select;state.focusCanvas()
                state.status="Imported \(result.objects.count) unstitched outlines. Assign a stitch type in Properties."
            } catch{showError(error);state.status="SVG import failed; design unchanged."}
        }
    }
    /// Edit Lettering: selects the whole lettering and puts the keyboard in its text box in Properties, where its
    /// text, font, size and shape are changed.
    private func editLettering(_ state: EditorState) {
        let selected = state.design.objects.filter { state.selection.contains($0.id) }
        guard let spec = (state.selected?.lettering ?? selected.lazy.compactMap(\.lettering).first) else {
            state.status = "Select lettering made with Add Lettering (\(Preferences.shared.key(.lettering))) first, then edit it. Ungrouped letters are plain shapes."; return
        }
        guard !state.design.letteringObjects(spec.id).contains(where: \.locked) else { state.status = "Unlock the letters before editing the lettering."; return }
        state.selection = Set(state.design.letteringObjects(spec.id).map(\.id)); state.selectedNode = nil; state.tool = .select
        state.focusLetteringText()
        state.status = "Type the new text. In Properties, click a font and press ↑ ↓ to try others."
    }
    /// Auto-Digitize Artwork: the dialog traces the reference image, then the fills are added as one step you can undo.
    private func autoDigitize(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before auto-digitizing."; return }
        guard let artwork = state.design.artwork else { state.status = "Import a reference image first (⌘I), then auto-digitize it."; return }
        guard let traced = GuidedDialog.autoDigitize(artwork) else { state.status = "Auto-digitize cancelled."; return }
        do {
            var candidate = state.design; candidate.objects += traced.objects.map(state.design.withFabric); try candidate.validate()
            state.edit("Auto-Digitize Artwork") { $0 = candidate }
            state.selection = Set(traced.objects.map(\.id)); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Added \(traced.objects.count) fills over your image. Press \(Preferences.shared.key(.artwork)) to hide the image and check the shapes; thin parts may suit satin or running stitch."
        } catch { showError(error) }
    }
    /// Add Satin Border: the dialog builds a border around each selected closed shape; each border is placed right
    /// after its shape in the sewing order, all in one step you can undo.
    private func addSatinBorder(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before adding a border."; return }
        let shapes = state.design.objects.filter { state.selection.contains($0.id) && !$0.locked && SatinBorder.canBorder($0) }
        guard !shapes.isEmpty else { state.status = "Select a fill or a closed outline first, then add a satin border."; return }
        guard let borders = GuidedDialog.satinBorder(shapes, color: state.currentColor) else { state.status = "Satin border cancelled."; return }
        do {
            var candidate = state.design
            for (source, border) in borders {
                guard let index = candidate.objects.firstIndex(where: { $0.id == source }) else { continue }
                candidate.objects.insert(candidate.withFabric(border), at: index + 1)
            }
            try candidate.validate()
            state.edit("Add Satin Border") { $0 = candidate }
            state.selection = Set(borders.map(\.border.id)); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Added \(borders.count) satin border\(borders.count == 1 ? "" : "s"). Each sews right after its shape; reorder or recolor it like any object."
        } catch { showError(error) }
    }
    /// Outlines & Offsets: the dialog builds the outlines around each selected closed shape; each shape's outlines
    /// are placed right after it in the sewing order, all in one step you can undo.
    private func addOutlinesOffsets(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before adding outlines."; return }
        let shapes = state.design.objects.filter { state.selection.contains($0.id) && !$0.locked && SatinBorder.canBorder($0) }
        guard !shapes.isEmpty else { state.status = "Select a fill or a closed outline first, then add outlines and offsets."; return }
        guard let made = GuidedDialog.outlinesOffsets(shapes, color: state.currentColor) else { state.status = "Outlines & Offsets cancelled."; return }
        do {
            var candidate = state.design
            for (source, outlines) in made {
                guard let index = candidate.objects.firstIndex(where: { $0.id == source }) else { continue }
                candidate.objects.insert(contentsOf: outlines.map { candidate.withFabric($0) }, at: index + 1)
            }
            try candidate.validate()
            state.edit("Add Outlines & Offsets") { $0 = candidate }
            let added = made.flatMap(\.outlines)
            state.selection = Set(added.map(\.id)); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Added \(added.count) outline\(added.count == 1 ? "" : "s"). Each sews right after its shape; reorder, recolor or reshape it like any object."
        } catch { showError(error) }
    }
    /// Add Monogram: the dialog builds the monogram, then it's added (centered in the hoop) as one step you can undo.
    private func addMonogram(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before adding a monogram."; return }
        guard let spec = GuidedDialog.monogram(color: state.currentColor) else { state.status = "Monogram cancelled."; return }
        do {
            let made = try spec.build(color: state.currentColor, embroideryFonts: EmbroideryFontLibrary.fonts).objects
            var candidate = state.design; candidate.objects += made; try candidate.validate()
            state.edit("Add Monogram") { $0 = candidate }
            state.selection = Set(made.map(\.id)); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Added the monogram as one group. Drag to move it; double-click it to change the initials, font, layout or border."
        } catch { showError(error) }
    }
    /// Edit Monogram: reopens the dialog with the selected monogram's recipe and rebuilds it in the same place and
    /// sewing-order position, as one step you can undo.
    private func editMonogram(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before editing the monogram."; return }
        guard let spec = state.design.objects.first(where: { state.selection.contains($0.id) && $0.monogram != nil })?.monogram?.asResized else {
            state.status = "Select a monogram made with Add Monogram (\(Preferences.shared.key(.addMonogram))) first."; return
        }
        let old = state.design.monogramObjects(spec.id)
        guard !old.contains(where: \.locked) else { state.status = "Unlock the monogram before editing it."; return }
        let color = old.first?.color ?? state.currentColor
        guard let edited = GuidedDialog.monogram(color: color, editing: spec) else { state.status = "Monogram unchanged."; return }
        do {
            let made = try edited.build(color: color, embroideryFonts: EmbroideryFontLibrary.fonts).objects
            var candidate = state.design; let ids = candidate.replaceMonogram(spec.id, with: made); try candidate.validate()
            state.edit("Edit Monogram") { $0 = candidate }
            state.selection = Set(ids); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Updated the monogram."
        } catch { showError(error) }
    }
    /// Add Laydown: the dialog works out light open fills under the selection (or the whole design), then they're
    /// added, sewn before what they lie under, as one step you can undo.
    private func addLaydown(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before adding a laydown."; return }
        let ids = state.selection
        guard state.design.objects.contains(where: { (ids.isEmpty || ids.contains($0.id)) && $0.kind != .vector }) else { state.status = "Add something that sews first; the laydown goes under it."; return }
        guard let laydown = GuidedDialog.laydown(state.design, under: ids, color: state.currentColor) else { state.status = "Laydown cancelled."; return }
        do {
            var candidate = state.design; candidate.addLaydown(laydown, under: ids); try candidate.validate()
            state.edit("Add Laydown") { $0 = candidate }
            state.selection = Set(laydown.map(\.id)); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Added a laydown in \(laydown.count) part\(laydown.count == 1 ? "" : "s"), grouped, sewn before what it lies under. Change its spacing or angle in Properties."
        } catch { showError(error) }
    }
    /// Create Motif…: the selected running lines become a motif of your own (Motifs.make), named in the dialog and
    /// kept in My motifs, ready to choose for any motif line or motif fill. The design itself doesn't change.
    private func createMotif(_ state: EditorState) {
        let lines = state.design.objects.filter { state.selection.contains($0.id) && $0.kind == .run }
        guard !lines.isEmpty else { state.status = "Select one or more running lines to make a motif from."; return }
        do {
            let motif = try Motifs.make(from: lines.map { RunningEngine.flatten($0.nodes, closed: $0.closed).flatMap { $0 } }, name: "My motif")
            guard let name = GuidedDialog.createMotif(motif, color: lines[0].color) else { state.status = "Create Motif cancelled."; return }
            let preferences = Preferences.shared
            var named = motif; named.name = Preferences.uniqueMotifName(name, among: preferences.myMotifs.map(\.name)) ?? motif.name
            preferences.setMyMotifs(preferences.myMotifs + [named])
            state.status = "Saved “\(named.name)” in My motifs. Choose it in Properties › Motif for a motif line or motif fill."
        } catch { state.status = error.localizedDescription }
    }
    /// How many times the current pasteboard contents have been pasted into the design they came from, so each
    /// paste there lands 3 mm further along instead of exactly on the last one.
    private var pasteRepeat = (changeCount: -1, count: 0)
    /// Copy (or Cut) puts the selected objects on the Mac's pasteboard, in sewing order. Cut then removes the unlocked
    /// ones, as one step you can undo; locked objects are copied but stay.
    private func copyObjects(_ state: EditorState, cut: Bool) {
        guard !state.selection.isEmpty else { state.status = "Select objects first, then \(cut ? "cut" : "copy") them."; return }
        let clipboard = state.design.copying(state.selection)
        guard let data = try? JSONEncoder().encode(clipboard) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents(); pasteboard.setData(data, forType: .init(ObjectClipboard.pasteboardType))
        let count = clipboard.objects.count, noun = count == 1 ? "object" : "objects"
        if cut {
            state.edit("Cut Objects") { $0.objects.removeAll { state.selection.contains($0.id) && !$0.locked } }
            state.selection = state.selection.filter { id in state.design.objects.contains { $0.id == id } }
            state.status = "Cut \(count) \(noun). Paste (⌘V) puts \(count == 1 ? "it" : "them") back here or in another design."
        } else {
            state.status = "Copied \(count) \(noun). Paste (⌘V) here or in another design."
        }
    }
    /// Paste adds the copied objects at the end of the sewing order and selects them. They land where they were
    /// copied from; pasted again into the design that still has the originals, each paste shifts 3 mm.
    private func pasteObjects(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before pasting."; return }
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .init(ObjectClipboard.pasteboardType)), data.count <= ObjectClipboard.maxBytes,
              let clipboard = try? JSONDecoder().decode(ObjectClipboard.self, from: data), clipboard.version == 1, !clipboard.objects.isEmpty
        else { state.status = "Nothing to paste: copy objects in a design first (⌘C)."; return }
        let originalsHere = clipboard.objects.contains { copied in state.design.objects.contains { $0.id == copied.id } }
        if pasteRepeat.changeCount != pasteboard.changeCount { pasteRepeat = (pasteboard.changeCount, 0) }
        if originalsHere { pasteRepeat.count += 1 }
        let shift = Double(originalsHere ? pasteRepeat.count : 0) * 3
        do {
            var candidate = state.design
            let ids = candidate.paste(clipboard, offset: Point(shift, -shift))
            try candidate.validate()   // the pasteboard is outside data: check it like a file being opened
            state.edit("Paste Objects") { $0 = candidate }
            state.selection = Set(ids); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Pasted \(ids.count) object\(ids.count == 1 ? "" : "s") at the end of the sewing order\(shift > 0 ? ", 3 mm along from the last" : "")."
        } catch { showError(error) }
    }
    /// Choose Thread from Chart: either sets the current thread to a chart thread and recolors the selection (like
    /// clicking a palette color), or matches every unlocked object's thread to the chart, as one step you can undo.
    private func chooseThreadFromChart(_ state: EditorState) {
        guard !state.hasVersionMismatch else { state.status = "Regenerate this older project before changing threads."; return }
        // The design's threads in sewing order, each once, for the Match All preview.
        var threads: [ThreadColor] = []
        for object in state.design.objects where !threads.contains(object.color) { threads.append(object.color) }
        guard let choice = GuidedDialog.threadChart(current: state.currentColor, designThreads: threads) else { state.status = "Thread chart closed without changes."; return }
        switch choice {
        case .use(let thread):
            state.chooseThread(thread)
            state.status = "Current thread: \(thread.name) (\(thread.chartLabel ?? "no number")). Anything selected now sews in it."
        case .matchAll(let chart):
            var changed = 0
            state.edit("Match Threads to Chart") { changed = $0.matchThreads(to: chart) }
            if let match = chart.nearest(to: state.currentColor.hex).first { state.currentColor = match }
            state.status = changed == 0 ? "Every thread already matches \(chart.name)." : "Matched \(changed) object\(changed == 1 ? "" : "s") to \(chart.name). Undo puts the old colors back."
        }
        state.focusCanvas()
    }
    /// Make Satin Column from Line: each selected running line or outline becomes a satin column of the width set
    /// in Properties (3 mm until changed), centered on it, in one step you can undo. Lines that can't take that
    /// width are left as they are and explained.
    private func makeSatinColumn(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects first."; return }
        let width = Preferences.shared.data.satinLineWidth ?? SatinLine.defaultWidth
        let lines = state.design.objects.filter { state.selection.contains($0.id) && !$0.locked && SatinLine.canConvert($0) }
        guard !lines.isEmpty else { state.status = "Select a running stitch line or outline first, then make it a satin column."; return }
        var columns: [UUID: RunObject] = [:], problems: [String] = []
        for line in lines {
            do { columns[line.id] = state.design.withFabric(try SatinLine.column(from: line, width: width)) } catch { problems.append(error.localizedDescription) }
        }
        if !columns.isEmpty { state.edit("Make Satin Column") { design in for i in design.objects.indices { if let column = columns[design.objects[i].id] { design.objects[i] = column } } } }
        let made = columns.isEmpty ? "" : "Made \(columns.count) satin column\(columns.count == 1 ? "" : "s") \(width.formatted()) mm wide. "
        state.status = made + (problems.first ?? "")
        state.focusCanvas()
    }
    /// Make Appliqué: the dialog turns each selected fill or closed outline into a placement line, tack-down and
    /// satin edge (grouped, in the shape's thread), which replace the shape at its place in the sewing order, all in
    /// one step you can undo.
    private func makeApplique(_ state: EditorState) {
        guard !state.hasVersionMismatch, state.draft.isEmpty else { state.status = "Finish the current path and regenerate older projects before making appliqué."; return }
        let shapes = state.design.objects.filter { state.selection.contains($0.id) && !$0.locked && SatinBorder.canBorder($0) }
        guard !shapes.isEmpty else { state.status = "Select a fill or a closed outline first, then make it appliqué."; return }
        guard let made = GuidedDialog.applique(shapes) else { state.status = "Appliqué cancelled."; return }
        do {
            var candidate = state.design
            for (source, parts) in made {
                guard let index = candidate.objects.firstIndex(where: { $0.id == source }) else { continue }
                candidate.objects.replaceSubrange(index...index, with: parts.map(candidate.withFabric))
            }
            try candidate.validate()
            state.edit("Make Appliqué") { $0 = candidate }
            state.selection = Set(made.flatMap { $0.parts.map(\.id) }); state.selectedNode = nil; state.tool = .select; state.focusCanvas()
            state.status = "Made \(made.count) appliqué\(made.count == 1 ? "" : "s"). The machine stops after each placement line (lay the fabric) and tack-down (trim it)."
        } catch { showError(error) }
    }
    private func importImage(_ state: EditorState) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.message = "Import a reference image to trace manually."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 50_000_000, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { throw DesignError.invalid("Choose a PNG or JPEG under 50 MB.") }
            let width = min(state.design.hoop.width * 0.8, state.design.hoop.height * 0.8 * image.size.width / image.size.height)
            state.edit("Import Reference") { $0.artwork = Artwork(data: data, name: url.lastPathComponent, width: width, height: width * image.size.height / image.size.width) }
            state.focusCanvas()
        } catch { showError(error) }
    }
    /// Saves a machine file, or the thread list: the save window's Format popup picks the format (and PES version),
    /// remembering the last one exported.
    private func exportMachine(_ state: EditorState, threadListOnly:Bool=false) {
        guard state.draft.isEmpty else {state.status="Finish or cancel the current path before exporting.";return}
        if let error=state.generationError {state.status=error;return}
        guard !state.busy,!state.exporting,!state.hasVersionMismatch,state.compiledRevision==state.revision,state.plan.stitchCount>0 else{state.status="Wait for current stitches before exporting.";return}
        let panel=NSSavePanel();panel.nameFieldStringValue="Design"
        let preferences=Preferences.shared
        let picker=ExportFormatPicker(panel:panel,threadListOnly:threadListOnly,remembered:preferences.data.exportFormat)
        panel.accessoryView=picker.accessoryView
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let choice=picker.choice
        if !threadListOnly && choice.id != preferences.data.exportFormat {preferences.data.exportFormat=choice.id;preferences.save(announce:false)}
        let revision=state.revision,plan=state.plan,hoop=state.design.hoop,version=choice.pesVersion,target=choice.format
        state.exporting=true;state.status="Encoding and checking \(target.title)…"
        Task {
            do {
                let response=try await Task.detached(priority:.userInitiated){try Exporter.prepare(plan:plan,hoop:hoop,pesVersion:version,format:target)}.value
                guard revision==state.revision else{throw DesignError.invalid("The design changed during export. Export the current revision again.")}
                let omitted=state.design.objects.filter{$0.kind == .vector && $0.guideFor == nil}.count
                // A machine that doesn't cut threads (Set Up Your Machine) gets a reminder about Stop at Jumps.
                let tip=threadListOnly ? nil:MachineSetup.jumpStopTip(cutsThreads:preferences.data.cutsThreads,design:state.design,plan:plan)
                let check=ExportCheck(format:target,stitchCount:response.stitchCount ?? 0,width:response.width ?? 0,height:response.height ?? 0,omittedOutlines:omitted,warnings:(response.warnings ?? [])+(tip.map{[$0]} ?? []),threadListOnly:threadListOnly,fileName:url.lastPathComponent)
                if GuidedDialog.run(content: { ExportCheckView(check: check, finish: $0) }) {
                    guard revision==state.revision else{throw DesignError.invalid("The design changed. Export it again.")}
                    let data:Data
                    if threadListOnly {guard let csv=response.threadCSV else{throw DesignError.invalid("The thread list is unavailable.")};data=Data(csv.utf8)}
                    else {data=response.bytes!}
                    try data.write(to:url,options:.atomic);state.status="Exported \(url.lastPathComponent)."
                } else{state.status="Export cancelled."}
            } catch{showError(error);state.status="Export failed; no new file was saved."}
            state.exporting=false
        }
    }

    /// Saves a multi-hooped design (MultiHooping.swift): one machine file per hooping, named after the name typed
    /// ("Towel – hooping 1 of 3.pes"), each encoded and read back like a single export, and the hooping sheet beside
    /// them as a PDF to print and keep at the machine. The hoopings are worked out first, in the background, so a
    /// problem with one shows before choosing where to save.
    private func exportHoopings(_ state: EditorState, name: String) {
        guard state.draft.isEmpty else { state.status = "Finish or cancel the current path before exporting."; return }
        if let error = state.generationError { state.status = error; return }
        guard !state.busy, !state.exporting, !state.hasVersionMismatch, state.compiledRevision == state.revision, state.plan.stitchCount > 0 else { state.status = "Wait for current stitches before exporting."; return }
        Task {
            guard let plans = await hoopingPlans(state) else { return }
            // A machine file needs stitches, so an empty hooping would stop every file being saved.
            if let problem = Design.emptyHoopingProblem(plans) { state.status = problem; return }
            saveHoopings(state, name: name, plans: plans)
        }
    }
    /// Works out each hooping's stitches (MultiHooping.swift) off the main thread, so the app stays responsive on a
    /// big design. Nil, with the reason in the status line, if they can't be made or the design changed meanwhile.
    private func hoopingPlans(_ state: EditorState) async -> [StitchPlan]? {
        let design = state.design, plan = state.plan, revision = state.revision
        state.exporting = true; state.status = "Working out the hoopings…"
        defer { state.exporting = false }
        do {
            let plans = try await Task.detached(priority: .userInitiated) { try design.hoopingPlans(plan: plan) }.value
            guard revision == state.revision else { state.status = "The design changed while the hoopings were worked out. Try again."; return nil }
            state.status = "\(plans.count) hooping\(plans.count == 1 ? "" : "s") worked out."
            return plans
        } catch { state.status = error.localizedDescription; return nil }
    }
    /// The rest of `exportHoopings`, once the hoopings are worked out: where to save, then encoding and checking.
    private func saveHoopings(_ state: EditorState, name: String, plans: [StitchPlan]) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        panel.message = "Each hooping is saved as its own file, named after this one, with a hooping sheet to print."
        let preferences = Preferences.shared
        let picker = ExportFormatPicker(panel: panel, threadListOnly: false, remembered: preferences.data.exportFormat)
        panel.accessoryView = picker.accessoryView
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let choice = picker.choice
        if choice.id != preferences.data.exportFormat { preferences.data.exportFormat = choice.id; preferences.save(announce: false) }
        let base = url.deletingPathExtension().lastPathComponent, folder = url.deletingLastPathComponent()
        let urls = plans.indices.map { folder.appendingPathComponent("\(base) – hooping \($0 + 1) of \(plans.count).\(choice.format.rawValue)") }
        let sheetURL = folder.appendingPathComponent("\(base) – hooping sheet.pdf")
        // The save window only asked about the name typed, so ask before replacing files named after it.
        let existing = (urls + [sheetURL]).filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty {
            let alert = NSAlert()
            alert.messageText = existing.count == 1 ? "Replace “\(existing[0].lastPathComponent)”?" : "Replace \(existing.count) files?"
            alert.informativeText = (existing.count == 1 ? "A file with that name" : existing.map(\.lastPathComponent).joined(separator: ", ") + ":") + " already in “\(folder.lastPathComponent)” will be replaced by this design's."
            alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { state.status = "Export cancelled."; return }
        }
        let sheet = hoopingSheet(state, plans: plans, name: base)
        let revision = state.revision, hoop = state.design.hoop, version = choice.pesVersion, target = choice.format
        state.exporting = true; state.status = "Encoding and checking \(plans.count) \(target.title) files…"
        Task {
            do {
                var responses: [ExportResponse] = []
                for plan in plans {
                    responses.append(try await Task.detached(priority: .userInitiated) { try Exporter.prepare(plan: plan, hoop: hoop, pesVersion: version, format: target) }.value)
                }
                guard revision == state.revision else { throw DesignError.invalid("The design changed during export. Export the current revision again.") }
                let omitted = state.design.objects.filter { $0.kind == .vector && $0.guideFor == nil }.count
                let warnings = responses.enumerated().flatMap { index, response in (response.warnings ?? []).map { "Hooping \(index + 1): \($0)" } }
                let check = ExportCheck(format: target, stitchCount: responses.reduce(0) { $0 + ($1.stitchCount ?? 0) },
                                        width: responses.map { $0.width ?? 0 }.max() ?? 0, height: responses.map { $0.height ?? 0 }.max() ?? 0,
                                        omittedOutlines: omitted, warnings: warnings, threadListOnly: false,
                                        fileName: "\(plans.count) files (\(urls[0].lastPathComponent)…) and \(sheetURL.lastPathComponent)")
                if GuidedDialog.run(content: { ExportCheckView(check: check, finish: $0) }) {
                    guard revision == state.revision else { throw DesignError.invalid("The design changed. Export it again.") }
                    for (response, url) in zip(responses, urls) { try response.bytes!.write(to: url, options: .atomic) }
                    guard let pdf = WorksheetPrinter.pdf(contents: sheet, pageSize: NSPrintInfo.shared.paperSize, speed: preferences.data.machineSpeed ?? ProductionSummary.defaultSpeed) else {
                        throw DesignError.invalid("The hooping files were saved, but the hooping sheet couldn't be made.")
                    }
                    try pdf.write(to: sheetURL, options: .atomic)
                    state.status = "Saved \(plans.count) hooping files and the hooping sheet."
                } else { state.status = "Export cancelled." }
            } catch { showError(error); state.status = "Export failed." }
            state.exporting = false
        }
    }
    /// The hooping sheet: one worksheet per hooping, in sewing order, each starting its notes with how to hoop (or
    /// re-hoop) the fabric for it.
    private func hoopingSheet(_ state: EditorState, plans: [StitchPlan], name: String) -> [WorksheetContent] {
        let marks = state.design.multiHooping?.marks != nil
        return plans.enumerated().map { index, plan in
            var summary = ProductionSummary(plan: plan, design: state.design)
            let notes: [String]
            if index == 0 {
                notes = ["Hooping 1 of \(plans.count): hoop the fabric for the first part of the design." + (marks && plans.count > 1 ? " It ends with alignment marks for the next hooping." : "")]
            } else if marks {
                notes = ["Hooping \(index + 1) of \(plans.count): re-hoop so the alignment marks already sewn sit inside the hoop. Before sewing, step to the first stitch and line the needle up over the first mark.",
                         "The marks sew first, then the machine stops: check they landed on the ones already sewn before sewing on."]
            } else {
                notes = ["Hooping \(index + 1) of \(plans.count): re-hoop the fabric for this part, lining it up with what's already sewn."]
            }
            summary.warnings.insert(contentsOf: notes, at: 0)
            return WorksheetContent(name: "\(name) – hooping \(index + 1) of \(plans.count)", hoop: state.design.hoop, plan: plan, summary: summary, fabric: state.design.fabricColor ?? 0xF5F0E6)
        }
    }

    /// Opens the production worksheet for the current stitches (for a multi-hooped design, the hooping sheet);
    /// Print… hands it to the Mac print dialog.
    private func productionWorksheet(_ state: EditorState, name: String) {
        guard state.draft.isEmpty else { state.status = "Finish or cancel the current path first."; return }
        if let error = state.generationError { state.status = error; return }
        guard !state.busy, !state.hasVersionMismatch, state.compiledRevision == state.revision, state.plan.stitchCount > 0 else { state.status = "Wait for the current stitches before making a worksheet."; return }
        guard !state.exporting else { state.status = "Wait for the export to finish."; return }
        if state.design.multiHooping != nil {
            Task {
                guard let plans = await hoopingPlans(state) else { return }
                showWorksheet(hoopingSheet(state, plans: plans, name: name))
            }
        } else {
            showWorksheet([WorksheetContent(name: name, hoop: state.design.hoop, plan: state.plan,
                                            summary: ProductionSummary(plan: state.plan, design: state.design), fabric: state.design.fabricColor ?? 0xF5F0E6)])
        }
    }
    /// The open Customize Tools window, if any.
    private var customizeWindow: NSWindow?
    /// View › Customize Tools…: opens a window just below the tool band for rearranging it. Every change shows on the
    /// band at once; Done keeps them and Cancel puts back the arrangement from when it opened. The window is a child of
    /// the design window, so it moves with it and the menus still act on that design.
    private func customizeTools() {
        // Already open: bring it forward (unless its design window has closed since, which takes it away too).
        if let open = customizeWindow, open.parent != nil { open.makeKeyAndOrderFront(nil); return }
        let preferences = Preferences.shared, original = preferences.toolArrangement
        // Wide enough for the groups to fit on two lines, if the screen allows.
        let width = min(1300, ((active?.window?.screen ?? NSScreen.main)?.visibleFrame.width ?? 1300) - 40)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.isReleasedWhenClosed = false
        let finish: (Bool) -> Void = { [weak self] keep in
            if !keep { preferences.setToolArrangement(original) }
            if let window = self?.customizeWindow { window.parent?.removeChildWindow(window); window.orderOut(nil) }
            self?.customizeWindow = nil
        }
        let host = NSHostingView(rootView: CustomizeToolsView(arrangement: original, changed: { preferences.setToolArrangement($0) }, finish: finish).frame(width: width))
        window.contentView = host
        window.setContentSize(host.fittingSize)
        if let design = active?.window {
            // Centered on the design window, its top just under the band (title bar about 52 points, band about 100).
            let screen = design.screen?.visibleFrame ?? design.frame
            let top = min(design.frame.maxY - 160, screen.maxY), size = window.frame.size
            window.setFrameOrigin(NSPoint(x: max(screen.minX, design.frame.midX - size.width / 2), y: max(screen.minY, top - size.height)))
            design.addChildWindow(window, ordered: .above)
        } else {
            window.center()
        }
        customizeWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    /// Shows the worksheet (one page per hooping, or just one), and prints it if asked.
    private func showWorksheet(_ contents: [WorksheetContent]) {
        let preferences = Preferences.shared
        var speed = preferences.data.machineSpeed ?? ProductionSummary.defaultSpeed
        let printing = GuidedDialog.run(width: 700) { finish in
            WorksheetView(contents: contents, pageSize: NSPrintInfo.shared.paperSize, initialSpeed: speed, speedChanged: { speed = $0 }, finish: finish)
        }
        if speed != preferences.data.machineSpeed { preferences.data.machineSpeed = speed; preferences.save() }
        guard printing else { return }
        do { try WorksheetPrinter.print(contents: contents, speed: speed) } catch { showError(error) }
    }

    /// The Digitize menu's submenus, one per toolbar group (Pick & Shape, Stitch, Shape, Add): the group's tools in
    /// toolbar order, with related commands next to the tool they go with.
    static let digitizeSections: [(title: String, commands: [CommandID])] = [
        ("Pick & Shape", [.selectTool, .nodeTool, .insertNode, .deleteNode, .toggleNodeType, .editStitches, .smoothShapes, .knifeTool, .weldObjects, .removeOverlaps, .branching,
                          .entryExitTool, .autoStartPoints, .clearStartEnd, .panTool, .artworkTool]),
        ("Stitch", [.runTool, .satinTool, .fillTool, .holeTool, .removeHoles, .addStitchAngles, .removeStitchAngles, .useAsFillGuide,
                    .convertRun, .convertSatin, .convertFill, .toggleUnderlay, .focusLength, .focusSpacing, .focusAngle]),
        ("Shape", [.openShapeTool, .closedShapeTool, .freehandOpenTool, .freehandClosedTool, .rectangleTool, .ellipseTool, .basicShapeTool,
                   .finishPath, .removePoint, .cancelPath]),
        ("Add", [.lettering, .editLettering, .breakApartLettering, .putLetteringOnLine, .addMonogram, .editMonogram, .satinBorder, .outlinesOffsets, .applique, .autoDigitize, .laydown, .wreath, .testSwatches])
    ]
    /// One line of a menu: a command, or a submenu of commands (its groups split by dividers).
    enum MenuEntry { case command(CommandID), submenu(String, [[CommandID]]) }
    /// Shorthand for a group of plain command lines.
    static func items(_ commands: CommandID...) -> [MenuEntry] { commands.map(MenuEntry.command) }
    /// The File, Edit, Digitize, View and Window menus. Each menu is a list of groups with a divider between them;
    /// long runs of related commands (aligning, zooming, the stitch player) sit in submenus so the menus stay short.
    static let menuLayout: [(title: String, groups: [[MenuEntry]])] = [
        ("File", [items(.new, .open, .sample, .stitchSampler), items(.close, .save, .saveAs),
                  items(.importImage, .importSVG, .importMachine), items(.exportMachine, .exportThreadList, .productionWorksheet)]),
        ("Edit", [items(.undo, .redo), items(.cutObjects, .copyObjects, .pasteObjects, .duplicate, .delete, .selectAll), items(.group, .ungroup),
                  [.submenu("Flip & Rotate", [[.mirrorH, .mirrorV], [.rotateLeft, .rotateRight]]),
                   .submenu("Align & Space", [[.alignLeft, .alignCentersVertically, .alignRight], [.alignTop, .alignCentersHorizontally, .alignBottom], [.alignCenters], [.spaceAcross, .spaceDown]]),
                   .submenu("Sewing Order", [[.earlier, .later], [.sequenceBySelection, .sequenceByColor]])],
                  items(.closePath, .lockObject, .hideObject, .renameObject, .threadChart, .createMotif)]),
        // One submenu per toolbar group, then a divider before Done.
        ("Digitize", [digitizeSections.map { .submenu($0.title, [$0.commands]) }, items(.done)]),
        ("View", [items(.threadView, .reviewSewingOrder),
                  [.submenu("Zoom", [[.zoomIn, .zoomOut], [.zoomFit, .zoomDesign, .zoomSelected, .zoomActual], [.zoomBoxTool]]),
                   .submenu("Show", [[.showStitches, .showOutlines, .showConnectors, .showUnderlay, .needles], [.artwork, .densityMap], [.hideOthers]]),
                   .submenu("Grid & Rulers", [[.grid, .snap], [.showRulers, .clearGuides], [.useInches]]),
                   .submenu("Stitch Player", [[.play, .rewind, .toEnd], [.stepForward, .stepBackward, .stepForward10, .stepBackward10],
                                              [.nextColor, .previousColor], [.nextObject, .previousObject], [.nextTrim, .previousTrim]])],
                  items(.measureTool, .hoopingsTool), items(.customizeTools)]),
        ("Window", [items(.nextTab, .previousTab), PanelID.allCases.map { .command($0.command) } + items(.paletteUnderCanvas), items(.saveWorkspace, .restoreWorkspace)])
    ]
    /// Adds a menu's groups to it, with a divider between groups; a submenu entry becomes an item that opens to the side.
    private func addGroups(_ groups: [[MenuEntry]], to menu: NSMenu) {
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for entry in group {
                switch entry {
                case .command(let command): menu.addItem(commandItem(command))
                case .submenu(let title, let commandGroups):
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = NSMenu(title: title)
                    addGroups(commandGroups.map { $0.map(MenuEntry.command) }, to: item.submenu!)
                    menu.addItem(item)
                }
            }
        }
    }
    private func makeMenu() {
        let menu = NSMenu()
        let app = NSMenuItem(); app.submenu = NSMenu(title: "OpenHoop"); menu.addItem(app)
        app.submenu?.addItem(withTitle: "About OpenHoop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        if let updates = Updates.menuItem() { app.submenu?.addItem(updates) }
        app.submenu?.addItem(commandItem(.settings)); app.submenu?.addItem(.separator())
        app.submenu?.addItem(withTitle: "Hide OpenHoop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.submenu?.addItem(withTitle: "Quit OpenHoop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for (name, groups) in Self.menuLayout {
            let item = NSMenuItem(); item.submenu = NSMenu(title: name); item.title = name; menu.addItem(item)
            addGroups(groups, to: item.submenu!)
            if name == "Window" {
                // Saved layouts, then the standard window items (Minimize, Zoom) that macOS adds to the Window menu.
                let saved = Preferences.shared.data.workspaces.filter { $0.panels != nil }
                if !saved.isEmpty {
                    let layouts = NSMenuItem(title: "Saved Layouts", action: nil, keyEquivalent: ""); layouts.submenu = NSMenu(title: "Saved Layouts")
                    for workspace in saved { let entry = NSMenuItem(title: workspace.name, action: #selector(applySavedLayout(_:)), keyEquivalent: ""); entry.target = self; entry.representedObject = workspace.id.uuidString; layouts.submenu?.addItem(entry) }
                    item.submenu?.addItem(layouts)
                }
                item.submenu?.addItem(.separator())
                NSApp.windowsMenu = item.submenu
            }
            if name == "Edit" {
                item.submenu?.addItem(.separator())
                // Text fields' own Cut, Copy and Paste (the Cut/Copy/Paste commands above work on design objects), in a
                // submenu: their keyboard shortcuts still work there, since macOS searches submenus for shortcuts too.
                let text = NSMenuItem(title: "Text Fields", action: nil, keyEquivalent: ""); text.submenu = NSMenu(title: "Text Fields"); item.submenu?.addItem(text)
                for (title, selector, key) in [("Cut Text", "cut:", "x"), ("Copy Text", "copy:", "c"), ("Paste Text", "paste:", "v")] { text.submenu?.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
                // Native text editing keeps Cmd-Z even if the document shortcut is customized.
                for (title, selector, key, modifiers) in [("Undo Text Edit", "undo:", "z", NSEvent.ModifierFlags.command), ("Redo Text Edit", "redo:", "z", [.command, .shift]), ("Select All Text", "selectAll:", "a", .command)] {
                    let textItem = NSMenuItem(title: title, action: #selector(textAction(_:)), keyEquivalent: key)
                    textItem.keyEquivalentModifierMask = modifiers; textItem.target = self; textItem.representedObject = selector; text.submenu?.addItem(textItem)
                }
            }
        }
        // Help: the user guide, reporting a problem and the website, all opened in the browser. Being the app's
        // helpMenu also gives it macOS's search field for finding menu commands.
        let help = NSMenuItem(); help.submenu = NSMenu(title: "Help"); help.title = "Help"; menu.addItem(help)
        for (title, address, key) in [("OpenHoop User Guide", "https://github.com/EvenDog/openhoop/blob/main/docs/USER-GUIDE.md", "?"),
                                      ("Getting Started", "https://github.com/EvenDog/openhoop/blob/main/docs/USER-GUIDE.md#getting-started", ""),
                                      ("Report a Problem…", "https://github.com/EvenDog/openhoop/issues/new/choose", ""),
                                      ("OpenHoop Website", "https://openhoop.app", "")] {
            let entry = NSMenuItem(title: title, action: #selector(openHelpLink(_:)), keyEquivalent: key)
            entry.target = self; entry.representedObject = address; help.submenu?.addItem(entry)
        }
        help.submenu?.addItem(.separator())
        let setup = NSMenuItem(title: "Set Up Your Machine…", action: #selector(setUpMachine(_:)), keyEquivalent: ""); setup.target = self
        help.submenu?.addItem(setup)
        NSApp.helpMenu = help.submenu
        NSApp.mainMenu = menu
    }
    /// Opens a Help menu item's web page in the browser.
    @objc func openHelpLink(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String, let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
    private func commandItem(_ command: CommandID) -> NSMenuItem {
        let label = Preferences.shared.label(command)
        let item = NSMenuItem(title: command.title + (label.isEmpty ? "" : "    " + label), action: #selector(menuAction(_:)), keyEquivalent: "")
        item.representedObject = command.rawValue; item.target = self
        // Canvas shortcuts deliberately have no live menu equivalent; the window router owns them.
        return item
    }
}

@main struct EmbroideryApplication {
    @MainActor static func main() {
        let app = NSApplication.shared; app.delegate = AppDelegate.shared; app.run()
    }
}

