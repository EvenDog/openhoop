// A design's thread palette: the short, ordered row of threads you keep at hand while digitizing it, like the color
// bar in other embroidery software. It's saved with the design. Every thread an object uses is always in it, so a
// thread can only be taken out once nothing sews in it.
import Foundation

extension Design {
    /// The most threads a palette may hold (a file with more is refused as damaged).
    public static let paletteLimit = 500

    /// Each thread the design's objects sew in, once, in sewing order.
    public var usedThreads: [ThreadColor] {
        var seen = Set<ThreadColor>()
        return objects.map(\.color).filter { seen.insert($0).inserted }
    }

    /// The threads the palette shows, in order: the saved palette (the eight basic colors until it's first changed),
    /// then any thread an object uses that isn't in it yet, so a design opened from an older file, or recolored by
    /// Match All, still shows every thread it sews in.
    public var paletteThreads: [ThreadColor] {
        let kept = palette ?? ThreadColor.palette
        return kept + usedThreads.filter { !kept.contains($0) }
    }

    /// Adds `thread` to the end of the palette, unless it's already there.
    public mutating func addToPalette(_ thread: ThreadColor) {
        let threads = paletteThreads
        guard !threads.contains(thread), threads.count < Self.paletteLimit else { return }
        palette = threads + [thread]
    }

    /// Takes `thread` out of the palette. A thread an object still sews in stays (it would only come back).
    public mutating func removeFromPalette(_ thread: ThreadColor) {
        guard !usedThreads.contains(thread) else { return }
        let threads = paletteThreads
        guard threads.contains(thread) else { return }
        palette = threads.filter { $0 != thread }
    }

    /// Takes out every thread no object sews in, keeping the order of the rest.
    public mutating func removeUnusedFromPalette() {
        let used = Set(usedThreads)
        palette = paletteThreads.filter(used.contains)
    }
}
