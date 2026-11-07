// The outlines behind most of the Basic Shapes tool's picture grid: geometric shapes, badges, nature and objects.
// Each is one closed outline drawn in small coordinates (about 0 to 1, y pointing up, counterclockwise) in its own
// natural proportions; ShapeGeometry.place stretches or fits it into the box the user drags out.

import Foundation

enum ShapeLibrary {
    /// The outline of `shape` in its own small coordinates. Only for the library's shapes: rectangle, ellipse,
    /// polygon, star, heart, arrow and the frames are drawn by ShapeGeometry, and get an empty outline here.
    static func outline(_ shape: BasicShape) -> [PathNode] {
        switch shape {
        // Geometric
        case .triangle: return corners([(0, 0), (1, 0), (0.5, 0.866)])
        case .rightTriangle: return corners([(0, 0), (1, 0), (0, 1)])
        case .diamond: return corners([(0.35, 0), (0.7, 0.5), (0.35, 1), (0, 0.5)])
        case .parallelogram: return corners([(0, 0), (0.75, 0), (1, 0.6), (0.25, 0.6)])
        case .trapezoid: return corners([(0, 0), (1, 0), (0.78, 0.6), (0.22, 0.6)])
        case .roundedSquare:
            var outline = OutlineBuilder(Point(0.2, 0))
            outline.line(Point(0.8, 0)); outline.arc(around: Point(0.8, 0.2), to: Point(1, 0.2))
            outline.line(Point(1, 0.8)); outline.arc(around: Point(0.8, 0.8), to: Point(0.8, 1))
            outline.line(Point(0.2, 1)); outline.arc(around: Point(0.2, 0.8), to: Point(0, 0.8))
            outline.line(Point(0, 0.2)); outline.arc(around: Point(0.2, 0.2), to: Point(0.2, 0))
            return outline.closed
        case .cross:
            let a = 1.0 / 3, b = 2.0 / 3   // the arms are a third of the width
            return corners([(a, 0), (b, 0), (b, a), (1, a), (1, b), (b, b), (b, 1), (a, 1), (a, b), (0, b), (0, a), (a, a)])
        case .chevron: return corners([(0, 0), (0.45, 0), (1, 0.5), (0.45, 1), (0, 1), (0.55, 0.5)])
        case .doubleArrow:
            return corners([(0, 0.25), (0.25, 0), (0.25, 0.15), (0.75, 0.15), (0.75, 0), (1, 0.25), (0.75, 0.5), (0.75, 0.35), (0.25, 0.35), (0.25, 0.5)])

        // Badges & labels
        case .shield:
            // Straight sides curving in to a point at the bottom, and a top that dips a little in the middle.
            return [
                PathNode(Point(0, 1), inHandle: Point(0.25, 0.92)),
                PathNode(Point(0, 0.6), outHandle: Point(0, 0.28)),
                PathNode(Point(0.425, 0), inHandle: Point(0.1, 0.12), outHandle: Point(0.75, 0.12)),
                PathNode(Point(0.85, 0.6), inHandle: Point(0.85, 0.28)),
                PathNode(Point(0.85, 1), outHandle: Point(0.6, 0.92))
            ]
        case .scallop: return bumpyRing(count: 12, reach: 0.85, bump: 0.25)
        case .starburst: return starRing(points: 16, inner: 0.82)
        case .banner: return corners([(0, 0), (1, 0), (0.9, 0.16), (1, 0.32), (0, 0.32), (0.1, 0.16)])   // V notches at both ends
        case .tag: return corners([(0.28, 0), (1, 0), (1, 0.56), (0.28, 0.56), (0, 0.28)])
        case .speechBubble:
            // A rounded box with a pointed tail at the bottom left.
            var outline = OutlineBuilder(Point(0.18, 0.22))
            outline.line(Point(0.25, 0.22), Point(0.12, 0), Point(0.45, 0.22), Point(0.82, 0.22))
            outline.arc(around: Point(0.82, 0.4), to: Point(1, 0.4)); outline.line(Point(1, 0.82))
            outline.arc(around: Point(0.82, 0.82), to: Point(0.82, 1)); outline.line(Point(0.18, 1))
            outline.arc(around: Point(0.18, 0.82), to: Point(0, 0.82)); outline.line(Point(0, 0.4))
            outline.arc(around: Point(0.18, 0.4), to: Point(0.18, 0.22))
            return outline.closed

        // Nature
        case .teardrop:
            // A round bottom (a circle of radius 0.35; kappa × 0.35 ≈ 0.193) rising to a point at the top.
            return [
                PathNode(Point(0.35, 1), inHandle: Point(0.45, 0.8), outHandle: Point(0.25, 0.8)),
                PathNode(Point(0, 0.35), smooth: true, inHandle: Point(0, 0.6), outHandle: Point(0, 0.157)),
                PathNode(Point(0.35, 0), smooth: true, inHandle: Point(0.157, 0), outHandle: Point(0.543, 0)),
                PathNode(Point(0.7, 0.35), smooth: true, inHandle: Point(0.7, 0.157), outHandle: Point(0.7, 0.6))
            ]
        case .moon:
            // A circle with a smaller one cut out of its right side: round the outer circle the long way (by the
            // left), then back along the cut-out circle's edge.
            let outer = (center: Point(0, 0), radius: 1.0), cut = (center: Point(0.45, 0.25), radius: 0.85)
            let top = meeting(outer.center, outer.radius, cut.center, cut.radius, awayFrom: Point(0, -10))
            let bottom = meeting(outer.center, outer.radius, cut.center, cut.radius, awayFrom: Point(0, 10))
            var outline = OutlineBuilder(top)
            outline.arc(around: outer.center, to: bottom)
            outline.arc(around: cut.center, to: top, clockwise: true)
            return outline.closed
        case .cloud:
            // A flat bottom with four overlapping round puffs along the top, from the right puff round to the left.
            let puffs = [(Point(0.8, 0.22), 0.22), (Point(0.6, 0.48), 0.28), (Point(0.32, 0.45), 0.25), (Point(0.17, 0.2), 0.2)]
            let middle = Point(0.5, 0.2)
            var outline = OutlineBuilder(Point(0.17, 0))
            outline.line(Point(0.8, 0))
            for (index, puff) in puffs.enumerated() {
                let next = index + 1 < puffs.count ? puffs[index + 1] : nil
                let end = next.map { meeting(puff.0, puff.1, $0.0, $0.1, awayFrom: middle) } ?? Point(0.17, 0)
                outline.arc(around: puff.0, to: end)
            }
            return outline.closed
        case .leaf:
            // A pointed leaf on a slant, from a short stem at the bottom left to its tip at the top right.
            return [
                PathNode(Point(0, 0)),
                PathNode(Point(0.14, 0.09), outHandle: Point(0.65, 0.12)),
                PathNode(Point(1, 1), inHandle: Point(0.97, 0.45), outHandle: Point(0.45, 0.97)),
                PathNode(Point(0.09, 0.14), inHandle: Point(0.12, 0.65))
            ]
        case .flower: return bumpyRing(count: 5, reach: 0.6, bump: 0.4)
        case .pineTree:
            return corners([(0.42, 0), (0.58, 0), (0.58, 0.12), (0.95, 0.12), (0.66, 0.42), (0.85, 0.42), (0.62, 0.7), (0.76, 0.7), (0.5, 1),
                            (0.24, 0.7), (0.38, 0.7), (0.15, 0.42), (0.34, 0.42), (0.05, 0.12), (0.42, 0.12)])
        case .lightning: return corners([(0.55, 1), (0.15, 0.42), (0.45, 0.42), (0.3, 0), (0.85, 0.58), (0.55, 0.58), (0.78, 1)])
        case .sun:
            // A round middle with eight pointed rays: each ray is a triangle standing on the circle, joined to the
            // next by an arc of the circle.
            let rays = 8, body = 0.6, halfBase = Double.pi / Double(rays) * 0.45
            let angle = { (ray: Int) in Double.pi / 2 + 2 * Double.pi * Double(ray) / Double(rays) }
            let at = { (a: Double, r: Double) in Point(cos(a), sin(a)) * r }
            var outline = OutlineBuilder(at(angle(0) - halfBase, body))
            for ray in 0..<rays {
                outline.line(at(angle(ray), 1), at(angle(ray) + halfBase, body))
                outline.arc(around: Point(0, 0), to: at(angle(ray + 1) - halfBase, body))
            }
            return outline.closed

        // Objects
        case .apple:
            // Two round shoulders either side of a short stem, a round body and a slight dip underneath.
            return smoothLoop([(0.54, 0.84), (0.58, 1.08), (0.5, 1.08), (0.46, 0.84), (0.24, 0.94), (0, 0.6), (0.22, 0.02), (0.5, 0.06),
                               (0.78, 0.02), (1, 0.6), (0.76, 0.94)], corners: [0, 1, 2, 3])
        case .fish:
            // A round body facing left, and a forked tail on the right.
            return smoothLoop([(0, 0.5), (0.3, 0.14), (0.62, 0.24), (0.76, 0.42), (1, 0.1), (0.9, 0.5), (1, 0.9), (0.76, 0.58), (0.62, 0.76),
                               (0.3, 0.86)], corners: [3, 4, 5, 6, 7])
        case .bone:
            // A straight shaft with two round knobs at each end.
            let r = 0.11, knobs = (leftBottom: Point(0.11, 0.1), leftTop: Point(0.11, 0.3), rightBottom: Point(0.89, 0.1), rightTop: Point(0.89, 0.3))
            let shaft = (bottom: 0.15, top: 0.25), middle = Point(0.5, 0.2)
            let reach = sqrt(r * r - 0.05 * 0.05)   // how far along the shaft's edge each knob reaches
            var outline = OutlineBuilder(Point(knobs.leftBottom.x + reach, shaft.bottom))
            outline.line(Point(knobs.rightBottom.x - reach, shaft.bottom))
            outline.arc(around: knobs.rightBottom, to: meeting(knobs.rightBottom, r, knobs.rightTop, r, awayFrom: middle))
            outline.arc(around: knobs.rightTop, to: Point(knobs.rightTop.x - reach, shaft.top))
            outline.line(Point(knobs.leftTop.x + reach, shaft.top))
            outline.arc(around: knobs.leftTop, to: meeting(knobs.leftTop, r, knobs.leftBottom, r, awayFrom: middle))
            outline.arc(around: knobs.leftBottom, to: Point(knobs.leftBottom.x + reach, shaft.bottom))
            return outline.closed
        case .egg:
            // Wider below the middle than above it.
            return [
                PathNode(Point(0.39, 0), smooth: true, inHandle: Point(0.17, 0), outHandle: Point(0.61, 0)),
                PathNode(Point(0.78, 0.42), smooth: true, inHandle: Point(0.78, 0.18), outHandle: Point(0.78, 0.72)),
                PathNode(Point(0.39, 1), smooth: true, inHandle: Point(0.6, 1), outHandle: Point(0.18, 1)),
                PathNode(Point(0, 0.42), smooth: true, inHandle: Point(0, 0.72), outHandle: Point(0, 0.18))
            ]
        // Geometric (added with the second set of shapes)
        case .semicircle:
            var outline = OutlineBuilder(Point(0, 0))
            outline.line(Point(1, 0)); outline.arc(around: Point(0.5, 0), to: Point(0, 0))
            return outline.closed
        case .arch:
            // A doorway: straight sides and a round top.
            var outline = OutlineBuilder(Point(0, 0))
            outline.line(Point(0.7, 0), Point(0.7, 0.65)); outline.arc(around: Point(0.35, 0.65), to: Point(0, 0.65))
            return outline.closed
        case .kite: return corners([(0.35, 0), (0.7, 0.62), (0.35, 1), (0, 0.62)])
        case .capsule:
            // A pill: a rectangle with half-round ends.
            var outline = OutlineBuilder(Point(0.2, 0))
            outline.line(Point(0.8, 0)); outline.arc(around: Point(0.8, 0.2), to: Point(0.8, 0.4))
            outline.line(Point(0.2, 0.4)); outline.arc(around: Point(0.2, 0.2), to: Point(0.2, 0))
            return outline.closed
        // Badges & labels
        case .pennant: return corners([(0, 0), (0.06, 0), (0.06, 0.12), (1, 0.32), (0.06, 0.52), (0.06, 0.6), (0, 0.6)])   // a flag on a short pole
        case .plaque:
            // A rectangle with a quarter circle scooped out of each corner (arcs round the corner, clockwise).
            let r = 0.12, w = 1.0, h = 0.6
            var outline = OutlineBuilder(Point(r, 0))
            outline.line(Point(w - r, 0)); outline.arc(around: Point(w, 0), to: Point(w, r), clockwise: true)
            outline.line(Point(w, h - r)); outline.arc(around: Point(w, h), to: Point(w - r, h), clockwise: true)
            outline.line(Point(r, h)); outline.arc(around: Point(0, h), to: Point(0, h - r), clockwise: true)
            outline.line(Point(0, r)); outline.arc(around: Point(0, 0), to: Point(r, 0), clockwise: true)
            return outline.closed
        case .ticket:
            // A rectangle with a half-round notch in the middle of each end.
            let r = 0.1, w = 1.0, h = 0.5
            var outline = OutlineBuilder(Point(0, 0))
            outline.line(Point(w, 0), Point(w, h / 2 - r)); outline.arc(around: Point(w, h / 2), to: Point(w, h / 2 + r), clockwise: true)
            outline.line(Point(w, h), Point(0, h), Point(0, h / 2 + r)); outline.arc(around: Point(0, h / 2), to: Point(0, h / 2 - r), clockwise: true)
            return outline.closed
        // Nature
        case .butterfly:
            // Four rounded wings, with points where they meet the body at the top, bottom and sides.
            return smoothLoop([(0.5, 0.66), (0.4, 0.74), (0.1, 0.95), (0, 0.7), (0.22, 0.5), (0.08, 0.2), (0.3, 0.02), (0.45, 0.2), (0.5, 0.1),
                               (0.55, 0.2), (0.7, 0.02), (0.92, 0.2), (0.78, 0.5), (1, 0.7), (0.9, 0.95), (0.6, 0.74)], corners: [0, 4, 8, 12])
        case .mushroom:
            return smoothLoop([(0.38, 0), (0.62, 0), (0.6, 0.4), (0.95, 0.4), (0.82, 0.75), (0.5, 0.88), (0.18, 0.75), (0.05, 0.4), (0.4, 0.4)],
                              corners: [0, 1, 2, 3, 7, 8])
        case .tulip:
            // A cup with three points on a straight stem.
            return smoothLoop([(0.45, 0), (0.55, 0), (0.55, 0.32), (0.78, 0.4), (0.92, 0.75), (0.95, 1), (0.72, 0.82), (0.5, 1.02), (0.28, 0.82),
                               (0.05, 1), (0.08, 0.75), (0.22, 0.4), (0.45, 0.32)], corners: [0, 1, 2, 5, 7, 9, 12])
        case .cactus:
            // A round-topped trunk with an arm curving up on each side, the right one lower. Each arm goes out along
            // its underside, up, and back down its inner side to the trunk.
            return smoothLoop([(0.38, 0), (0.62, 0), (0.62, 0.24), (0.9, 0.28), (0.95, 0.7), (0.86, 0.72), (0.83, 0.38), (0.62, 0.35), (0.62, 0.92),
                               (0.5, 1), (0.38, 0.92), (0.38, 0.6), (0.17, 0.62), (0.14, 0.86), (0.05, 0.84), (0.08, 0.55), (0.38, 0.5)],
                              corners: [0, 1, 2, 7, 8, 10, 11, 16])
        case .mountains: return corners([(0, 0), (1, 0), (0.8, 0.45), (0.68, 0.3), (0.45, 0.8), (0.3, 0.52), (0.2, 0.35)])
        // Objects
        case .house: return corners([(0.1, 0), (0.9, 0), (0.9, 0.55), (1, 0.55), (0.5, 1), (0, 0.55), (0.1, 0.55)])
        case .crown: return corners([(0.08, 0), (0.92, 0), (1, 0.7), (0.74, 0.42), (0.5, 0.82), (0.26, 0.42), (0, 0.7)])
        case .bell:
            return smoothLoop([(0, 0.08), (1, 0.08), (0.84, 0.3), (0.78, 0.7), (0.56, 0.9), (0.56, 1), (0.44, 1), (0.44, 0.9), (0.22, 0.7), (0.16, 0.3)],
                              corners: [0, 1, 4, 5, 6, 7])
        case .balloon:
            // A round balloon with a small knot at the bottom.
            return smoothLoop([(0.44, 0.02), (0.56, 0.02), (0.52, 0.12), (0.78, 0.3), (0.9, 0.62), (0.72, 0.92), (0.5, 0.98), (0.28, 0.92), (0.1, 0.62),
                               (0.22, 0.3), (0.48, 0.12)], corners: [0, 1, 2, 10])
        case .tShirt:
            return corners([(0.2, 0), (0.8, 0), (0.8, 0.55), (0.92, 0.48), (1, 0.7), (0.72, 0.9), (0.62, 0.9), (0.5, 0.8), (0.38, 0.9), (0.28, 0.9), (0, 0.7),
                            (0.08, 0.48), (0.2, 0.55)])
        case .cupcake:
            // A straight-sided cake with a round frosting top that overhangs it a little.
            return smoothLoop([(0.22, 0), (0.78, 0), (0.88, 0.45), (0.98, 0.52), (0.82, 0.78), (0.5, 0.95), (0.18, 0.78), (0.02, 0.52), (0.12, 0.45)],
                              corners: [0, 1, 2, 8])
        case .lightBulb:
            return smoothLoop([(0.38, 0), (0.62, 0), (0.62, 0.2), (0.66, 0.34), (0.86, 0.58), (0.84, 0.84), (0.5, 1), (0.16, 0.84), (0.14, 0.58),
                               (0.34, 0.34), (0.38, 0.2)], corners: [0, 1, 2, 10])
        case .iceCream:
            // A pointed cone with a round scoop on top.
            return smoothLoop([(0.5, 0), (0.78, 0.5), (0.95, 0.62), (0.78, 0.92), (0.5, 1), (0.22, 0.92), (0.05, 0.62), (0.22, 0.5)], corners: [0, 1, 7])
        case .rectangle, .ellipse, .polygon, .star, .heart, .arrow, .ring, .squareFrame, .roundedFrame, .scallopFrame: return []
        }
    }

    /// Straight-sided outline through `points` (x, y pairs).
    static func corners(_ points: [(Double, Double)]) -> [PathNode] { points.map { PathNode(Point($0.0, $0.1)) } }

    /// A smooth closed curve through `points`, except at the `corners` (indexes), which stay sharp. Each smooth
    /// point's handles run parallel to the line between its two neighbours, a sixth of that line's length each way
    /// (the usual way to draw a smooth curve through given points, called a Catmull-Rom spline).
    static func smoothLoop(_ points: [(Double, Double)], corners: Set<Int>) -> [PathNode] {
        let p = points.map { Point($0.0, $0.1) }
        return p.indices.map { i in
            guard !corners.contains(i) else { return PathNode(p[i]) }
            let along = (p[(i + 1) % p.count] - p[(i + p.count - 1) % p.count]) * (1.0 / 6)
            return PathNode(p[i], smooth: true, inHandle: p[i] - along, outHandle: p[i] + along)
        }
    }

    /// A star with `points` points round the middle, the inner corners at `inner` × the outer ones' distance.
    static func starRing(points: Int, inner: Double) -> [PathNode] {
        (0..<(points * 2)).map { i in
            let angle = Double.pi / 2 + Double.pi * Double(i) / Double(points), radius = i % 2 == 0 ? 1 : inner
            return PathNode(Point(cos(angle), sin(angle)) * radius)
        }
    }

    /// The outer edge of `count` equal circles (radius `bump`) spaced evenly round the middle, their centers `reach`
    /// from it, each overlapping its neighbours: a scalloped ring, or petals.
    static func bumpyRing(count: Int, reach: Double, bump: Double) -> [PathNode] {
        let centers = (0..<count).map { i -> Point in
            let angle = Double.pi / 2 + 2 * Double.pi * Double(i) / Double(count)
            return Point(cos(angle), sin(angle)) * reach
        }
        // Where each circle meets the next one, on the outside.
        let meets = (0..<count).map { meeting(centers[$0], bump, centers[($0 + 1) % count], bump, awayFrom: Point(0, 0)) }
        var outline = OutlineBuilder(meets[count - 1])
        for i in 0..<count { outline.arc(around: centers[i], to: meets[i]) }
        return outline.closed
    }

    /// Where the circle round `center1` (radius `radius1`) crosses the one round `center2`: of the two crossings,
    /// the one farther from `awayFrom`. The circles must overlap.
    static func meeting(_ center1: Point, _ radius1: Double, _ center2: Point, _ radius2: Double, awayFrom: Point) -> Point {
        let gap = center1.distance(to: center2)
        // `along` is how far from center1 (toward center2) the line through both crossings is; `aside` is how far
        // each crossing sits either side of the line between the centers.
        let along = (radius1 * radius1 - radius2 * radius2 + gap * gap) / (2 * gap), aside = sqrt(max(0, radius1 * radius1 - along * along))
        let direction = (center2 - center1) * (1 / gap), across = Point(-direction.y, direction.x)
        let foot = center1 + direction * along, one = foot + across * aside, other = foot - across * aside
        return one.distance(to: awayFrom) > other.distance(to: awayFrom) ? one : other
    }
}

/// Draws an outline piece by piece (straight lines and circle arcs) from a starting point, as the nodes a shape is
/// made of.
struct OutlineBuilder {
    private(set) var nodes: [PathNode]
    init(_ start: Point) { nodes = [PathNode(start)] }
    private var current: Point { nodes[nodes.count - 1].point }

    /// Straight lines on to each of `points` in turn.
    mutating func line(_ points: Point...) { for point in points { nodes.append(PathNode(point)) } }

    /// An arc of the circle round `center`, from where the outline is now to `end` (the same distance from the
    /// center), counterclockwise unless `clockwise`. It's cut into pieces of at most a quarter circle, each one
    /// Bézier curve: handles 4/3 × tan(angle / 4) × the radius long make a curve that hugs the circle.
    mutating func arc(around center: Point, to end: Point, clockwise: Bool = false) {
        let start = current - center, radius = hypot(start.x, start.y)
        let from = atan2(start.y, start.x), to = atan2(end.y - center.y, end.x - center.x)
        // How far round to go, as an angle: negative for clockwise. A full turn is added or taken off as needed.
        var sweep = to - from
        if clockwise { while sweep >= 0 { sweep -= 2 * .pi } } else { while sweep <= 0 { sweep += 2 * .pi } }
        let pieces = Int((abs(sweep) / (.pi / 2)).rounded(.up)), step = sweep / Double(pieces)
        let handle = 4.0 / 3.0 * tan(step / 4) * radius   // negative when clockwise, which flips the handles' direction
        for piece in 0..<pieces {
            let a = from + step * Double(piece), b = a + step
            let point = piece == pieces - 1 ? end : center + Point(cos(b), sin(b)) * radius
            // Each handle points along the circle (at right angles to the radius) from its end of the piece.
            nodes[nodes.count - 1].outHandle = current + Point(-sin(a), cos(a)) * handle
            nodes.append(PathNode(point, inHandle: point - Point(-sin(b), cos(b)) * handle))
        }
    }

    /// The finished outline. A shape that ends back where it started has that last point merged into the first;
    /// nodes whose two handles point in opposite directions are marked smooth, so reshaping keeps them round.
    var closed: [PathNode] {
        var result = nodes
        if result.count > 1, result[result.count - 1].point.distance(to: result[0].point) < 1e-9 {
            let last = result.removeLast()
            result[0].inHandle = last.inHandle
        }
        for i in result.indices {
            guard let inHandle = result[i].inHandle, let outHandle = result[i].outHandle else { continue }
            let back = inHandle - result[i].point, ahead = outHandle - result[i].point
            let size = hypot(back.x, back.y) * hypot(ahead.x, ahead.y)
            result[i].smooth = size > 0 && abs(AreaGeometry.cross(back, ahead)) < 1e-6 * size && back.x * ahead.x + back.y * ahead.y < 0
        }
        return result
    }
}
