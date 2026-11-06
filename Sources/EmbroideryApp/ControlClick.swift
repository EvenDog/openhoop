// Control-click on a row of the sewing order list adds that row to the selection (or takes it out), as ⌘-click does.
// SwiftUI opens a row's right-click menu on Control-click too, so a thin AppKit view laid over the row catches
// Control-clicks first. Every other click, drag and right-click passes through it to the row underneath.
import SwiftUI
import AppKit

/// An invisible overlay that runs `action` on a Control-click and lets everything else through.
struct ControlClickCatcher: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> CatcherView { let view = CatcherView(); view.action = action; return view }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: () -> Void = {}
        /// AppKit asks which view is under the pointer before sending it a click. This view answers only for a
        /// Control-click; for anything else it says "not me" (nil), so the row underneath gets it as before.
        override func hitTest(_ point: NSPoint) -> NSView? { Self.catches(NSApp.currentEvent) ? super.hitTest(point) : nil }
        /// True for the clicks this view takes: a left click with Control held.
        static func catches(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            return event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        }
        override func mouseDown(with event: NSEvent) { action() }
        /// No menu on Control-click (a real right-click still reaches the row's menu, since it isn't caught).
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}
