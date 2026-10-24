// Lettering envelopes: the box round a word is bent into another shape and the letters are stretched to fill it,
// like printing the word on rubber and pulling the rubber. Bridge bends the top and bottom edges into curves, Pennant
// tapers the word toward one end, Perspective slants the box's sides, and Diamond bends the edges to a point.
import Foundation

/// The shapes an envelope can bend lettering into.
public enum EnvelopeKind: String, Codable, CaseIterable, Sendable {
    case bridge, pennant, perspective, diamond
    public var title: String { rawValue.capitalized }
    /// The handles this kind has. Bridge: the middle of the top and bottom edges. Pennant and Perspective: the four
    /// corners. Diamond: all six.
    public var handles: [EnvelopeHandle] {
        let places: [Int] = self == .bridge ? [1] : self == .diamond ? [0, 1, 2] : [0, 2]
        return [true, false].flatMap { top in places.map { EnvelopeHandle(top: top, place: $0) } }
    }
    /// True when the handles move sideways (Perspective); the others move up and down.
    public var slides: Bool { self == .perspective }
    /// The handle a Shift- or ⌘-drag moves along with `handle`: for Perspective the other end of the same edge,
    /// for the others the same place on the other edge.
    public func partner(of handle: EnvelopeHandle) -> EnvelopeHandle {
        slides ? EnvelopeHandle(top: handle.top, place: 2 - handle.place) : EnvelopeHandle(top: !handle.top, place: handle.place)
    }
    /// Where a new envelope's handles start (as a share of the letter height, as `LetteringEnvelope` keeps them), so
    /// choosing one shows its shape straight away: Bridge arches up, Pennant tapers to the right, Perspective narrows
    /// the top, Diamond comes to a point above and below.
    var startingMoves: (top: [Double], bottom: [Double]) {
        switch self {
        case .bridge: return ([0, 0.35, 0], [0, 0.35, 0])
        case .pennant: return ([0, 0, -0.25], [0, 0, 0.25])
        case .perspective: return ([0.4, 0, -0.4], [0, 0, 0])
        case .diamond: return ([0, 0.3, 0], [0, -0.3, 0])
        }
    }
}

/// One of an envelope's handles: on the top or bottom edge, at its left end (0), middle (1) or right end (2).
public struct EnvelopeHandle: Hashable, Sendable {
    public var top: Bool
    public var place: Int
    public init(top: Bool, place: Int) { self.top = top; self.place = place }
    public var title: String { (top ? "Top" : "Bottom") + " " + ["left", "middle", "right"][place] }
}

/// An envelope on a piece of lettering: its shape and how far each handle has been moved from the lettering's box.
public struct LetteringEnvelope: Codable, Hashable, Sendable {
    public var kind: EnvelopeKind
    /// How far each handle has moved, as a share of the letter height (so the envelope grows and shrinks with the
    /// lettering): the top edge's left end, middle and right end, then the bottom edge's. Up is positive, or right for
    /// Perspective. Places a kind has no handle at stay 0.
    public var top: [Double]
    public var bottom: [Double]
    /// The lettering's box when it was last built (mm, before it was placed on the design): its lower-left and
    /// upper-right corners. The app draws the handles from it.
    public var box: [Point]?
    /// How far a handle can move, as a share of the letter height.
    public static let moves = -3.0...3.0

    /// A new envelope of `kind`, its handles where that kind starts them.
    public init(kind: EnvelopeKind) {
        self.kind = kind
        (top, bottom) = kind.startingMoves
    }

    /// How far `handle` has moved (a share of the letter height).
    public func move(_ handle: EnvelopeHandle) -> Double { (handle.top ? top : bottom)[handle.place] }
    public mutating func setMove(_ handle: EnvelopeHandle, _ value: Double) {
        if handle.top { top[handle.place] = value } else { bottom[handle.place] = value }
    }

    /// Where `handle` sits (mm, in the lettering's own frame) for a box from `low` to `high` and letters `height` tall.
    public func spot(_ handle: EnvelopeHandle, low: Point, high: Point, height: Double) -> Point {
        let base = Point(low.x + Double(handle.place) * (high.x - low.x) / 2, handle.top ? high.y : low.y)
        let amount = move(handle) * height
        return base + (kind.slides ? Point(amount, 0) : Point(0, amount))
    }

    /// The point `u` of the way along the top or bottom edge (0 at the left end, 1 at the right). Bridge's edges are
    /// smooth curves through its three points; the others are straight between them. Pennant and Perspective have
    /// no middle handle, so their edges run straight from end to end.
    func edge(top: Bool, at u: Double, low: Point, high: Point, height: Double) -> Point {
        let left = spot(EnvelopeHandle(top: top, place: 0), low: low, high: high, height: height)
        let right = spot(EnvelopeHandle(top: top, place: 2), low: low, high: high, height: height)
        let middle = kind == .pennant || kind == .perspective ? (left + right) * 0.5 : spot(EnvelopeHandle(top: top, place: 1), low: low, high: high, height: height)
        if kind == .bridge {
            // The curve through all three points (a parabola: left at u = 0, middle at ½, right at 1).
            return left * ((1 - u) * (1 - 2 * u)) + middle * (4 * u * (1 - u)) + right * (u * (2 * u - 1))
        }
        return u < 0.5 ? left + (middle - left) * (2 * u) : middle + (right - middle) * (2 * u - 1)
    }

    /// Where a point of the unbent lettering goes: as far across the bent box, and as far up between its bottom and
    /// top edges, as it was in the box from `low` to `high`.
    public func warp(_ p: Point, low: Point, high: Point, height: Double) -> Point {
        let u = (p.x - low.x) / max(high.x - low.x, 1e-9), v = (p.y - low.y) / max(high.y - low.y, 1e-9)
        let bottomPoint = edge(top: false, at: u, low: low, high: high, height: height)
        let topPoint = edge(top: true, at: u, low: low, high: high, height: height)
        return bottomPoint + (topPoint - bottomPoint) * v
    }

    /// Refuses an envelope bent so far that the letters would fold over: the top edge must stay above the bottom
    /// by at least a fifth of the box's height everywhere, and the box's sides must not cross.
    func check(low: Point, high: Point, height: Double) throws {
        let boxHeight = high.y - low.y
        for step in 0...40 {
            let u = Double(step) / 40
            let topPoint = edge(top: true, at: u, low: low, high: high, height: height), bottomPoint = edge(top: false, at: u, low: low, high: high, height: height)
            guard topPoint.y - bottomPoint.y >= boxHeight * 0.2 else { throw DesignError.invalid("The envelope squeezes the letters too thin. Bring its handles back toward the lettering.") }
        }
        for top in [true, false] {
            let left = edge(top: top, at: 0, low: low, high: high, height: height), right = edge(top: top, at: 1, low: low, high: high, height: height)
            guard right.x - left.x >= (high.x - low.x) * 0.2 else { throw DesignError.invalid("The envelope squeezes the letters too narrow. Bring its handles back toward the lettering.") }
        }
    }

    /// `objects` (the lettering, unplaced) bent into the envelope, and the box they filled. Long straight edges are cut
    /// into pieces first so they can curve; curves bend through their handles.
    func bent(_ objects: [RunObject], height: Double) throws -> (objects: [RunObject], box: [Point]) {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        guard let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max(),
              x1 - x0 > 0.01, y1 - y0 > 0.01 else { return (objects, []) }
        let low = Point(x0, y0), high = Point(x1, y1)
        try check(low: low, high: high, height: height)
        let piece = max(0.5, min(1.5, height / 6))
        let bentObjects = objects.map { object in
            var object = object.cutIntoPieces(piece)
            object.transform { warp($0, low: low, high: high, height: height) }
            return object
        }
        return (bentObjects, [low, high])
    }
}

extension RunObject {
    /// The object with every straight stretch longer than `piece` mm cut into equal shorter ones by extra corner
    /// points, so an envelope can bend it; its shape is unchanged. A satin's columns are cut by extra edge pairs
    /// across the column where both edges run straight (not where one edge stands still, as at a fanned end).
    /// Curves are left as they are.
    func cutIntoPieces(_ piece: Double) -> RunObject {
        var object = self
        /// The ring or path `nodes` with extra corners on its long straight stretches.
        func cut(_ nodes: [PathNode], closed: Bool) -> [PathNode] {
            guard nodes.count >= 2 else { return nodes }
            var result: [PathNode] = []
            for i in nodes.indices {
                result.append(nodes[i])
                guard closed || i + 1 < nodes.count else { continue }
                let a = nodes[i], b = nodes[(i + 1) % nodes.count]
                guard a.outHandle == nil, b.inHandle == nil else { continue }
                let parts = Int(ceil(a.point.distance(to: b.point) / piece))
                for k in stride(from: 1, to: parts, by: 1) { result.append(PathNode(a.point + (b.point - a.point) * (Double(k) / Double(parts)))) }
            }
            return result
        }
        switch kind {
        case .satin:
            // Pairs of edge points, left then right. Between two pairs, new pairs go the same share along both edges.
            let pairs = stride(from: 0, to: nodes.count - 1, by: 2).map { (nodes[$0], nodes[$0 + 1]) }
            guard pairs.count >= 2 else { return object }
            var result: [PathNode] = []
            for i in pairs.indices {
                result += [pairs[i].0, pairs[i].1]
                guard closed || i + 1 < pairs.count else { continue }
                let (l0, r0) = pairs[i], (l1, r1) = pairs[(i + 1) % pairs.count]
                guard l0.outHandle == nil, l1.inHandle == nil, r0.outHandle == nil, r1.inHandle == nil,
                      min(l0.point.distance(to: l1.point), r0.point.distance(to: r1.point)) > 0.05 else { continue }
                let parts = Int(ceil(max(l0.point.distance(to: l1.point), r0.point.distance(to: r1.point)) / piece))
                for k in stride(from: 1, to: parts, by: 1) {
                    let t = Double(k) / Double(parts)
                    result += [PathNode(l0.point + (l1.point - l0.point) * t), PathNode(r0.point + (r1.point - r0.point) * t)]
                }
            }
            object.nodes = result
        case .raw:
            break
        default:
            object.nodes = cut(nodes, closed: closed || kind == .fill)
            object.holes = holes.map { $0.map { cut($0, closed: true) } }
        }
        return object
    }
}
