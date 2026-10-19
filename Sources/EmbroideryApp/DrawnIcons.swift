// Icons OpenHoop draws itself, for tools no built-in Apple symbol shows well. Each has a name starting with
// "openhoop." that stands in for a symbol name (see CommandID.symbol), so one call shows either kind.
import AppKit
import SwiftUI

extension NSImage {
    /// One of OpenHoop's drawn icons, sized to sit beside text of `size` points, or nil if `name` isn't one of them.
    /// It's a template image, so it takes the color of the text around it, as Apple's symbols do.
    static func drawn(_ name: String, size: CGFloat) -> NSImage? {
        guard name == "openhoop.satin" else { return nil }
        let side = (size * 1.2).rounded()   // Apple's symbols are a little taller than the text they sit beside
        // flipped: true makes y run downward, as in the 16 × 16 sketch these points come from.
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let scale = side / 16
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: (x - 1.4) * scale, y: (y - 1.3) * scale) }
            // Satin column: two curved edges (a quarter circle each, inner and outer) joined by four rungs, like
            // the left and right points you click along a column.
            let center = (x: 14.5, y: 14.5), inner = 5.0, outer = 10.5
            let path = NSBezierPath()
            for radius in [inner, outer] {
                path.move(to: point(center.x - radius, center.y))
                path.appendArc(withCenter: point(center.x, center.y), radius: radius * scale, startAngle: 180, endAngle: 270)
            }
            for rung in 0..<4 {
                let angle = (180 + (Double(rung) + 0.5) * 90 / 4) * .pi / 180
                path.move(to: point(center.x + inner * cos(angle), center.y + inner * sin(angle)))
                path.line(to: point(center.x + outer * cos(angle), center.y + outer * sin(angle)))
            }
            path.lineWidth = 1.35 * scale
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension Image {
    /// A built-in symbol by name, or OpenHoop's drawn icon for an "openhoop." name. `size` is the font size the icon
    /// sits beside (built-in symbols take theirs from `.font`, which callers still set).
    static func symbol(_ name: String, size: CGFloat) -> Image {
        guard let drawn = NSImage.drawn(name, size: size) else { return Image(systemName: name) }
        return Image(nsImage: drawn).renderingMode(.template)
    }
}
