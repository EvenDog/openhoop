// One window holds every open design as a tab. Each design gets a DesignPane (its tool strip, docks, canvas and
// status bar); the window shows one pane at a time. The tab strip in the title bar lists the designs and switches
// between them. OpenHoop draws these tabs itself because macOS won't hide its own tab bar once two tabs are open.
import AppKit
import SwiftUI
import EmbroideryCore

/// Everything one design shows inside the window: the tool strip on top; the left dock, canvas and right dock side
/// by side; the status bar below.
@MainActor final class DesignPane: NSViewController {
    let document: DesignDocument
    var state: EditorState { document.state }
    let split = NSSplitViewController()
    let leftDock: NSSplitViewItem
    let rightDock: NSSplitViewItem
    let canvasItem: NSSplitViewItem
    /// The panel layout last shown in this pane, so unchanged preferences don't move the dock dividers.
    private var shownLayout: PanelLayout?
    /// False until the pane has been on screen once; the first showing fits the hoop in the window.
    var hasBeenShown = false

    init(document: DesignDocument) {
        self.document = document
        let state = document.state
        // The canvas fills its area, above the palette strip (0 tall while the palette is docked in the Threads panel).
        // Nothing floats over the canvas: the tool's choices, such as the next shape's, are in the Properties panel.
        let canvas = DesignCanvas(state: state), paletteStrip = NSHostingView(rootView: PaletteStrip(state: state))
        let canvasArea = NSView()
        for part in [canvas, paletteStrip] { part.translatesAutoresizingMaskIntoConstraints = false; canvasArea.addSubview(part) }
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: canvasArea.topAnchor), canvas.leadingAnchor.constraint(equalTo: canvasArea.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: canvasArea.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: paletteStrip.topAnchor),
            paletteStrip.leadingAnchor.constraint(equalTo: canvasArea.leadingAnchor), paletteStrip.trailingAnchor.constraint(equalTo: canvasArea.trailingAnchor), paletteStrip.bottomAnchor.constraint(equalTo: canvasArea.bottomAnchor)
        ])
        let canvasVC = NSViewController(); canvasVC.view = canvasArea
        leftDock = NSSplitViewItem(viewController: NSHostingController(rootView: DockColumn(side: .left, state: state)))
        rightDock = NSSplitViewItem(viewController: NSHostingController(rootView: DockColumn(side: .right, state: state)))
        canvasItem = NSSplitViewItem(viewController: canvasVC)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func loadView() {
        view = NSView()
        for dock in [leftDock, rightDock] { dock.minimumThickness = 180; dock.maximumThickness = 500; dock.canCollapse = true; dock.holdingPriority = .init(260) }
        canvasItem.minimumThickness = 350
        split.splitView.isVertical = true; split.splitView.dividerStyle = .thin
        [leftDock, canvasItem, rightDock].forEach { split.addSplitViewItem($0) }
        addChild(split)
        let statusBar = NSHostingView(rootView: FooterPanel(state: state))
        // The tool strip is docked directly under the title bar and spans the full width.
        let toolStrip = NSHostingView(rootView: ToolStrip(state: state))
        // Under it, on the left, the Pro view's tool rail when that's picked in Settings (0 wide otherwise). Its
        // width comes from SwiftUI; its height is whatever the window gives it, so it never makes the window taller.
        let toolRail = NSHostingView(rootView: ToolStrip(state: state, rail: true))
        toolRail.sizingOptions = [.minSize, .maxSize]
        for part in [toolStrip, toolRail, split.view, statusBar] { part.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(part) }
        NSLayoutConstraint.activate([
            toolStrip.topAnchor.constraint(equalTo: view.topAnchor), toolStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor), toolStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolRail.topAnchor.constraint(equalTo: toolStrip.bottomAnchor), toolRail.leadingAnchor.constraint(equalTo: view.leadingAnchor), toolRail.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            split.view.topAnchor.constraint(equalTo: toolStrip.bottomAnchor), split.view.leadingAnchor.constraint(equalTo: toolRail.trailingAnchor), split.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), split.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor), statusBar.heightAnchor.constraint(equalToConstant: 29)
        ])
    }

    /// Shows the saved panel layout in the docks: empty docks fold away, and dock widths are set the first time and
    /// whenever the saved widths change (for example after Reset Panel Layout).
    func applyWorkspace() {
        let layout = Preferences.shared.panels
        guard layout != shownLayout else { return }
        let widthsChanged = shownLayout.map { $0.leftWidth != layout.leftWidth || $0.rightWidth != layout.rightWidth } ?? true
        shownLayout = layout
        leftDock.isCollapsed = layout.left.isEmpty; rightDock.isCollapsed = layout.right.isEmpty
        guard widthsChanged else { return }
        split.view.layoutSubtreeIfNeeded()
        if !layout.left.isEmpty { split.splitView.setPosition(layout.leftWidth, ofDividerAt: 0) }
        if !layout.right.isEmpty, split.splitView.bounds.width > 700 { split.splitView.setPosition(split.splitView.bounds.width - layout.rightWidth, ofDividerAt: 1) }
    }
    /// The panel layout with this pane's current dock widths, for saving.
    func capturePanels() -> PanelLayout {
        var layout = Preferences.shared.panels
        if !leftDock.isCollapsed { layout.leftWidth = leftDock.viewController.view.frame.width }
        if !rightDock.isCollapsed { layout.rightWidth = rightDock.viewController.view.frame.width }
        return layout.normalized()
    }
}

/// Which design tab is picked next when one closes: the one to its right, else the one to its left.
/// Returns nil when the closed tab was the last one.
func tabToSelect(afterClosing closed: Int, count: Int) -> Int? {
    guard count > 1 else { return nil }
    return closed < count - 1 ? closed : closed - 1
}

/// What the tab strip shows; the window keeps it up to date and handles the clicks.
@MainActor final class TabStripModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: ObjectIdentifier
        var title: String
        var edited: Bool
    }
    @Published var tabs: [Tab] = []
    @Published var selected: ObjectIdentifier?
    var onSelect: (ObjectIdentifier) -> Void = { _ in }
    var onClose: (ObjectIdentifier) -> Void = { _ in }
}

/// The design tabs in the title bar: one rounded tab per design (an orange dot means unsaved changes, × closes
/// it), then + for a new design.
struct TabStripView: View {
    @ObservedObject var model: TabStripModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs) { tab in TabButton(tab: tab, selected: tab.id == model.selected, model: model) }
            Button { AppDelegate.shared.perform(.new) } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
            .help("New design  \(Preferences.shared.label(.new))").accessibilityLabel("New design")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel("Open designs")
    }
}

/// One design's tab. The whole tab selects the design; the × closes it (shown on the chosen tab, and on others
/// when the pointer is over them).
private struct TabButton: View {
    let tab: TabStripModel.Tab
    let selected: Bool
    @ObservedObject var model: TabStripModel
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 7) {
            if tab.edited { Circle().fill(Theme.primaryAction).frame(width: 7, height: 7).accessibilityLabel("Unsaved changes") }
            Text(tab.title).lineLimit(1).truncationMode(.middle)
                .font(Theme.body(12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
            Spacer(minLength: 0)
            Button { model.onClose(tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
            .opacity(selected || hovering ? 1 : 0)
            .help("Close \(tab.title)").accessibilityLabel("Close \(tab.title)")
        }
        .padding(.leading, 12).padding(.trailing, 4)
        .frame(minWidth: 80, maxWidth: 200, minHeight: 28, maxHeight: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.cardBorder : (hovering ? Theme.divider : .clear)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.controlBorder : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { model.onSelect(tab.id) }
        .onHover { hovering = $0 }
        .help(tab.title)
        .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.onSelect(tab.id) }
    }
}

extension NSToolbarItem.Identifier {
    /// The design tabs in the title bar.
    static let designTabs = NSToolbarItem.Identifier("designTabs")
}

extension Notification.Name {
    /// Posted when a design's name or unsaved-changes state changes, so its tab can update.
    static let designTabsChanged = Notification.Name("OpenHoopDesignTabsChanged")
}
