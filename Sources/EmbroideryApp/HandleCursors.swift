// Pointers for the handles round a selection or the reference image, so the pointer shows what a drag will do:
// rotate, resize from a corner, or skew. (Stretching from a side uses the system's own ↔ and ↕.) macOS has no
// pointers for these, so they're drawn here in code.
import AppKit

/// Pointer pictures for the handles round a selection, drawn in code: black lines with a white edge, like the
/// system's own pointers, 24 points square.
enum HandleCursorArt {
    /// One line of a pointer: its path and, at each end that has one, an arrowhead pointing along it.
    struct Stroke { var path: NSBezierPath; var heads: [(tip: CGPoint, from: CGPoint)] }

    /// Draws `strokes` into a 24-point image: first everything wide in white (the edge), then narrow in black.
    static func image(_ strokes: [Stroke]) -> NSImage {
        NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            for (color, extra) in [(NSColor.white, 2.6), (NSColor.black, 0.0)] {
                color.setStroke(); color.setFill()
                for stroke in strokes {
                    stroke.path.lineWidth = 1.7 + extra; stroke.path.lineCapStyle = .round; stroke.path.lineJoinStyle = .round; stroke.path.stroke()
                    for head in stroke.heads {
                        let arrow = arrowhead(tip: head.tip, from: head.from)
                        arrow.lineWidth = extra; arrow.lineJoinStyle = .round
                        arrow.fill(); if extra > 0 { arrow.stroke() }
                    }
                }
            }
            return true
        }
    }
    /// A filled triangle with its point at `tip`, pointing away from `from`.
    static func arrowhead(tip: CGPoint, from: CGPoint) -> NSBezierPath {
        let angle = atan2(tip.y - from.y, tip.x - from.x), length: CGFloat = 5.5, half: CGFloat = 3.6
        let back = CGPoint(x: tip.x - cos(angle) * length, y: tip.y - sin(angle) * length)
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: CGPoint(x: back.x - sin(angle) * half, y: back.y + cos(angle) * half))
        path.line(to: CGPoint(x: back.x + sin(angle) * half, y: back.y - cos(angle) * half))
        path.close()
        return path
    }
    /// A straight line from `a` to `b` with arrowheads at both ends (ends pulled in so the heads finish at a and b).
    static func doubleArrow(_ a: CGPoint, _ b: CGPoint) -> Stroke {
        let d = hypot(b.x - a.x, b.y - a.y), u = CGPoint(x: (b.x - a.x) / d, y: (b.y - a.y) / d)
        let path = NSBezierPath(); path.move(to: CGPoint(x: a.x + u.x * 4, y: a.y + u.y * 4)); path.line(to: CGPoint(x: b.x - u.x * 4, y: b.y - u.y * 4))
        return Stroke(path: path, heads: [(a, b), (b, a)])
    }

    /// Rotate: an arc over the top, like ↶ and ↷ joined, with an arrowhead at each end following the curve down.
    static var rotate: NSImage {
        let center = CGPoint(x: 12, y: 10), radius: CGFloat = 7.5, right: CGFloat = -25, left: CGFloat = 205
        func point(_ degrees: CGFloat) -> CGPoint { CGPoint(x: center.x + radius * cos(degrees * .pi / 180), y: center.y + radius * sin(degrees * .pi / 180)) }
        let trim = 4.5 / radius * 180 / .pi   // the line stops where each arrowhead begins
        let path = NSBezierPath(); path.appendArc(withCenter: center, radius: radius, startAngle: right + trim, endAngle: left - trim)
        // Each head points along the circle at its end: clockwise at the right end, counterclockwise at the left.
        func head(_ degrees: CGFloat, clockwise: Bool) -> (tip: CGPoint, from: CGPoint) {
            let tip = point(degrees), r = degrees * .pi / 180, sign: CGFloat = clockwise ? 1 : -1
            return (tip, CGPoint(x: tip.x - sign * sin(r) * 5, y: tip.y + sign * cos(r) * 5))
        }
        return image([Stroke(path: path, heads: [head(right, clockwise: true), head(left, clockwise: false)])])
    }
    /// Resize from a corner: a diagonal double arrow, up-right/down-left (`rising`) or up-left/down-right.
    static func diagonal(rising: Bool) -> NSImage {
        image([rising ? doubleArrow(CGPoint(x: 5, y: 5), CGPoint(x: 19, y: 19)) : doubleArrow(CGPoint(x: 5, y: 19), CGPoint(x: 19, y: 5))])
    }
    /// Skew: two half-arrows sliding past each other, side to side (`sideways`, for the top and bottom handles) or up
    /// and down (for the left and right ones).
    static func skew(sideways: Bool) -> NSImage {
        func half(_ a: CGPoint, _ b: CGPoint) -> Stroke {
            let path = NSBezierPath(); path.move(to: a); path.line(to: CGPoint(x: b.x - (b.x - a.x) / max(1, hypot(b.x - a.x, b.y - a.y)) * 4, y: b.y - (b.y - a.y) / max(1, hypot(b.x - a.x, b.y - a.y)) * 4))
            return Stroke(path: path, heads: [(b, a)])
        }
        return sideways ? image([half(CGPoint(x: 4, y: 15), CGPoint(x: 20, y: 15)), half(CGPoint(x: 20, y: 9), CGPoint(x: 4, y: 9))])
                        : image([half(CGPoint(x: 9, y: 4), CGPoint(x: 9, y: 20)), half(CGPoint(x: 15, y: 20), CGPoint(x: 15, y: 4))])
    }
}

/// The handle pointers, made once. Their hot spot is the middle of the picture.
@MainActor enum HandleCursor {
    static let rotate = NSCursor(image: HandleCursorArt.rotate, hotSpot: NSPoint(x: 12, y: 12))
    static let rising = NSCursor(image: HandleCursorArt.diagonal(rising: true), hotSpot: NSPoint(x: 12, y: 12))
    static let falling = NSCursor(image: HandleCursorArt.diagonal(rising: false), hotSpot: NSPoint(x: 12, y: 12))
    static let skewSideways = NSCursor(image: HandleCursorArt.skew(sideways: true), hotSpot: NSPoint(x: 12, y: 12))
    static let skewUpDown = NSCursor(image: HandleCursorArt.skew(sideways: false), hotSpot: NSPoint(x: 12, y: 12))
    /// A corner's resize pointer: ↗↙ for a corner up-right or down-left of the middle, ↖↘ for the other two.
    static func diagonal(rising: Bool) -> NSCursor { rising ? Self.rising : falling }
}
