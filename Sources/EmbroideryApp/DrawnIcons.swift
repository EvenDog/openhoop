// Icons OpenHoop draws itself, for tools no built-in Apple symbol shows well. Each has a name starting with
// "openhoop." that stands in for a symbol name (see CommandID.symbol), so one call shows either kind.
import AppKit
import CoreText
import SwiftUI

extension NSImage {
    /// One of OpenHoop's drawn icons, sized to sit beside text of `size` points, or nil if `name` isn't one of them.
    /// It's a template image, so it takes the color of the text around it, as Apple's symbols do.
    static func drawn(_ name: String, size: CGFloat) -> NSImage? {
        // Each icon is drawn on a 16 × 16 grid, with y running downward; `scale` turns grid units into points.
        let draw: (_ scale: CGFloat) -> Void
        switch name {
        case "openhoop.satin": draw = drawSatin
        case "openhoop.monogram": draw = drawMonogram
        default: return nil
        }
        let side = (size * 1.2).rounded()   // Apple's symbols are a little taller than the text they sit beside
        // flipped: true makes y run downward, as on the grid.
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            NSColor.black.set()
            draw(side / 16)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Satin column: two curved edges (a quarter circle each, inner and outer) joined by four rungs, like the left
    /// and right points you click along a column.
    private static func drawSatin(_ scale: CGFloat) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: (x - 1.4) * scale, y: (y - 1.3) * scale) }
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
        path.stroke()
    }

    /// Monogram: a serif M on a shield, like the Shield border in the Monogram dialog.
    private static func drawMonogram(_ scale: CGFloat) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale, y: y * scale) }
        let shield = NSBezierPath()
        shield.move(to: point(2.4, 2.2))
        shield.line(to: point(13.6, 2.2))
        shield.line(to: point(13.6, 8))
        shield.curve(to: point(8, 14.9), controlPoint1: point(13.6, 11.6), controlPoint2: point(10.8, 13.7))
        shield.curve(to: point(2.4, 8), controlPoint1: point(5.2, 13.7), controlPoint2: point(2.4, 11.6))
        shield.close()
        shield.lineWidth = 1.1 * scale
        shield.lineJoinStyle = .round
        shield.stroke()
        // The letter is the font's own outline for M, so it can be placed exactly: 5.6 units tall, its top at 5.4,
        // centered across. A font's y runs upward, so the outline is flipped on the way.
        let font = CTFontCreateWithName((NSFont(name: "Didot-Bold", size: 100) != nil ? "Didot-Bold" : "Georgia-Bold") as CFString, 100, nil)
        var character: UniChar = 0x4D, glyph: CGGlyph = 0   // 0x4D is "M"
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), let letter = CTFontCreatePathForGlyph(font, glyph, nil),
              let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = letter.boundingBoxOfPath, units = 5.6 / bounds.height
        var place = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: 8, y: 5.4)
            .scaledBy(x: units, y: -units)
            .translatedBy(x: -bounds.midX, y: -bounds.maxY)
        if let placed = letter.copy(using: &place) { context.addPath(placed); context.fillPath() }
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
