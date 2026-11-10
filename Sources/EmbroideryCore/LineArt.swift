// Line art: ready-made running-stitch drawings (dividers, a frame, a flower, a butterfly…) for the Add Line Art
// dialog. Each design is drawn as a few strokes in a 100 × 100 box (y pointing down, like a picture), then turned
// into running lines at the chosen size. Strokes that touch are joined into one continuous line (going back over
// a line already sewn where it must, as hand double running does), so only parts that float free need a jump.
// Each line is made of smooth curve nodes, so the stitches come out at the stitch length; all are one group.
import Foundation

public enum LineArtDesign: String, CaseIterable, Codable, Sendable {
    case heartDivider, scrollDivider, laurel, ovalFrame, flower, tulip, butterfly, heartSwirl, snowflake, sun, teacup, anchor, rosette

    public var title: String {
        switch self {
        case .heartDivider: return "Heart divider"; case .scrollDivider: return "Scroll divider"; case .laurel: return "Laurel branch"
        case .ovalFrame: return "Oval frame"; case .flower: return "Flower"; case .tulip: return "Tulip"; case .butterfly: return "Butterfly"
        case .heartSwirl: return "Heart with swirl"; case .snowflake: return "Snowflake"; case .sun: return "Sun"; case .teacup: return "Teacup"
        case .anchor: return "Anchor"; case .rosette: return "Rosette"
        }
    }
}

public enum LineArt {
    /// How wide a drawing can be made, and how wide it starts (mm).
    public static let sizes = 20.0...200.0
    public static let defaultSize = 60.0

    /// `design` as running lines `size` mm wide, centered on 0,0, in `color`, grouped. `bean`: each line is sewn
    /// three times (forward, back, forward) for a bolder line, except where it goes back over itself (the joins):
    /// those stretches are sewn once, as Make Redwork does, so they come out about as bold as the rest.
    public static func objects(_ design: LineArtDesign, size: Double, bean: Bool, color: ThreadColor) -> [RunObject] {
        let drawn = joined(strokes(design)), points = drawn.flatMap { $0 }
        let left = points.map(\.x).min() ?? 0, right = points.map(\.x).max() ?? 100
        let top = points.map(\.y).min() ?? 0, bottom = points.map(\.y).max() ?? 100
        let scale = size / max(1, right - left), middle = Point((left + right) / 2, (top + bottom) / 2)
        // From the drawing's box (y down) to millimeters (y up), centered on the drawing's middle.
        let strokes = ordered(drawn.map { $0.map { Point(($0.x - middle.x) * scale, (middle.y - $0.y) * scale) } })
        let group = UUID()
        return strokes.enumerated().map { index, stroke in
            let closed = stroke.count > 2 && stroke[0].distance(to: stroke[stroke.count - 1]) < 1e-6
            var line = RunObject(name: "\(design.title) \(index + 1)", nodes: nodes(closed ? Array(stroke.dropLast()) : stroke, closed: closed), color: color)
            line.closed = closed
            line.digitizing = DigitizingSettings(kind: .run)
            if bean { line.digitizing?.runPasses = 3; line.digitizing?.retraceOnce = true }
            line.stitchLength = bean ? 2.5 : 2
            line.groupID = group
            return line
        }
    }

    /// Strokes that touch, joined into continuous lines: one per set of touching strokes. The strokes are cut into
    /// pieces wherever one touches another (within `tolerance`, in the drawing's 100-unit box), and each set is
    /// sewn as a route along its pieces that uses every piece once, plus the shortest pieces sewn a second time
    /// where a route can't otherwise go on (like hand double running). A line that comes back to its start is closed.
    static func joined(_ strokes: [[Point]], tolerance: Double = 0.6) -> [[Point]] {
        // Points no more than 0.5 apart, so a stroke crossing another always has a point near the crossing.
        let lines = strokes.filter { $0.count >= 2 }.map { stroke -> [Point] in
            var dense = [stroke[0]]
            for (a, b) in zip(stroke, stroke.dropFirst()) {
                let pieces = max(1, Int(ceil(a.distance(to: b) / 0.5)))
                for k in 1...pieces { dense.append(a + (b - a) * (Double(k) / Double(pieces))) }
            }
            return dense
        }
        func isClosed(_ line: [Point]) -> Bool { line.count > 2 && line[0].distance(to: line[line.count - 1]) < 1e-6 }
        // Junctions: places where a point of one stroke lies on another. `cuts[s]` holds where stroke s is cut, as a
        // position along it (point index plus the fraction of the way to the next point) and the junction's number.
        var junctions: [Point] = [], cuts = Array(repeating: [(at: Double, junction: Int)](), count: lines.count)
        func junction(_ p: Point) -> Int {
            if let near = junctions.firstIndex(where: { $0.distance(to: p) < tolerance }) { return near }
            junctions.append(p); return junctions.count - 1
        }
        for (a, line) in lines.enumerated() {
            for (b, other) in lines.enumerated() where b != a {
                // Each run of touching points (one stroke lying along another) counts once, at its closest point.
                var best: (i: Int, at: Double, point: Point, gap: Double)?, lastTouch = -10
                func keep() { if let touch = best { let j = junction(touch.point); cuts[a].append((Double(touch.i), j)); cuts[b].append((touch.at, j)) }; best = nil }
                for (i, p) in line.enumerated() {
                    var nearest: (at: Double, point: Point, gap: Double)?
                    for k in 0..<(other.count - 1) {
                        let q = AreaGeometry.projection(p, other[k], other[k + 1]), gap = q.distance(to: p)
                        if gap < (nearest?.gap ?? tolerance) {
                            let span = other[k].distance(to: other[k + 1])
                            nearest = (Double(k) + (span > 0 ? other[k].distance(to: q) / span : 0), q, gap)
                        }
                    }
                    guard let touch = nearest else { continue }
                    if i - lastTouch > 2 { keep() }
                    if touch.gap < (best?.gap ?? .infinity) { best = (i, touch.at, touch.point, touch.gap) }
                    lastTouch = i
                }
                keep()
            }
        }
        // Each open stroke's ends are junctions too, and a closed stroke touching nothing gets one at its start.
        for (s, line) in lines.enumerated() {
            if !isClosed(line) { cuts[s] += [(0, junction(line[0])), (Double(line.count - 1), junction(line[line.count - 1]))] }
            else if cuts[s].isEmpty { cuts[s].append((0, junction(line[0]))) }
        }
        // The pieces between neighbouring cuts, each ending exactly on its junctions.
        var pieces: [(from: Int, to: Int, points: [Point])] = []
        for (s, line) in lines.enumerated() {
            var sorted: [(at: Double, junction: Int)] = []
            for cut in cuts[s].sorted(by: { $0.at < $1.at }) where !(sorted.last.map { abs($0.at - cut.at) < 1e-6 || $0.junction == cut.junction && abs($0.at - cut.at) < 2 } ?? false) { sorted.append(cut) }
            // A closed stroke wraps round: its last piece runs from the last cut back to the first.
            let ends = isClosed(line) ? sorted + [(at: sorted[0].at + Double(line.count - 1), junction: sorted[0].junction)] : sorted
            for (a, b) in zip(ends, ends.dropFirst()) where b.at - a.at > 1e-6 {
                var points = [junctions[a.junction]]
                var k = Int(floor(a.at)) + 1
                while Double(k) < b.at { points.append(line[k % (line.count - 1)]); k += 1 }
                points.append(junctions[b.junction])
                if points.count == 2 && points[0].distance(to: points[1]) < 1e-6 { continue }
                pieces.append((a.junction, b.junction, points))
            }
        }
        return route(pieces, junctionCount: junctions.count)
    }

    /// One continuous line per connected set of `pieces` (each runs between two junctions): a route that uses every
    /// piece, sewing the shortest extra pieces a second time where the route would otherwise get stuck.
    private static func route(_ pieces: [(from: Int, to: Int, points: [Point])], junctionCount: Int) -> [[Point]] {
        func length(_ points: [Point]) -> Double { zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }
        // Which pieces meet at each junction.
        var meeting = Array(repeating: [Int](), count: junctionCount)
        for (i, piece) in pieces.enumerated() { meeting[piece.from].append(i); meeting[piece.to].append(i) }
        // The connected sets of pieces.
        var setOf = Array(repeating: -1, count: pieces.count), sets: [[Int]] = []
        for start in pieces.indices where setOf[start] < 0 {
            var stack = [start], members: [Int] = []; setOf[start] = sets.count
            while let i = stack.popLast() {
                members.append(i)
                for j in meeting[pieces[i].from] + meeting[pieces[i].to] where setOf[j] < 0 { setOf[j] = sets.count; stack.append(j) }
            }
            sets.append(members)
        }
        return sets.map { members in
            var used = members   // pieces to sew (a piece sewn twice appears twice)
            // Junctions where an odd number of pieces meet: a route must start or end at one of them, or sew a piece twice.
            var degree: [Int: Int] = [:]
            for i in members { degree[pieces[i].from, default: 0] += 1; degree[pieces[i].to, default: 0] += 1 }
            var odd = degree.filter { $0.value % 2 == 1 }.map(\.key).sorted()
            /// The shortest way between junctions along the pieces: its pieces, and its length.
            func shortest(_ a: Int, _ b: Int) -> (pieces: [Int], length: Double) {
                var best: [Int: Double] = [a: 0], via: [Int: Int] = [:], done: Set<Int> = []
                while let here = best.filter({ !done.contains($0.key) }).min(by: { $0.value < $1.value })?.key {
                    if here == b { break }
                    done.insert(here)
                    for i in meeting[here] where setOf[i] == setOf[members[0]] {
                        let there = pieces[i].from == here ? pieces[i].to : pieces[i].from, d = best[here]! + length(pieces[i].points)
                        if d < best[there] ?? .infinity { best[there] = d; via[there] = i }
                    }
                }
                var path: [Int] = [], at = b
                while at != a, let i = via[at] { path.append(i); at = pieces[i].from == at ? pieces[i].to : pieces[i].from }
                return (path, best[b] ?? .infinity)
            }
            // Pair up odd junctions, closest pairs first, leaving the two furthest apart as the route's ends.
            while odd.count > 2 {
                var pick: (Int, Int, [Int], Double)?
                for x in 0..<odd.count { for y in (x + 1)..<odd.count {
                    let way = shortest(odd[x], odd[y])
                    if way.length < (pick?.3 ?? .infinity) { pick = (x, y, way.pieces, way.length) }
                } }
                guard let (x, y, way, _) = pick else { break }
                used += way; odd.remove(at: y); odd.remove(at: x)
            }
            // Walk the route (Hierholzer's way: go until stuck, then splice in loops from junctions passed earlier).
            var unused = Array(repeating: 0, count: pieces.count)
            for i in used { unused[i] += 1 }
            let start = odd.first ?? pieces[members[0]].from
            var stack: [(junction: Int, piece: Int?)] = [(start, nil)], walk: [(junction: Int, piece: Int?)] = []
            while let top = stack.last {
                if let i = meeting[top.junction].first(where: { unused[$0] > 0 }) {
                    unused[i] -= 1
                    stack.append((pieces[i].from == top.junction ? pieces[i].to : pieces[i].from, i))
                } else { walk.append(stack.removeLast()) }
            }
            walk.reverse()
            // The walk as points: each piece the way it's travelled.
            var line: [Point] = []
            for (k, step) in walk.enumerated() where k > 0 {
                guard let i = step.piece else { continue }
                let forward = pieces[i].from == walk[k - 1].junction
                let points = forward ? pieces[i].points : pieces[i].points.reversed()
                line += line.isEmpty ? points : Array(points.dropFirst())
            }
            return line
        }
    }

    /// The strokes in sewing order: each next one is the nearest to where the last one ended (an open one turned round
    /// if its far end is nearer), so the jumps between them are short.
    static func ordered(_ strokes: [[Point]]) -> [[Point]] {
        var left = strokes.filter { $0.count >= 2 }, result: [[Point]] = []
        var at = left.first?.first ?? Point(0, 0)
        while !left.isEmpty {
            var best = 0, flip = false, nearest = Double.infinity
            for (i, stroke) in left.enumerated() {
                let closed = stroke[0].distance(to: stroke[stroke.count - 1]) < 1e-6
                if stroke[0].distance(to: at) < nearest { nearest = stroke[0].distance(to: at); best = i; flip = false }
                if !closed && stroke[stroke.count - 1].distance(to: at) < nearest { nearest = stroke[stroke.count - 1].distance(to: at); best = i; flip = true }
            }
            let next = flip ? Array(left[best].reversed()) : left[best]
            result.append(next); at = next[next.count - 1]; left.remove(at: best)
        }
        return result
    }

    /// A stroke drawn as many close points, as a few curve nodes: one at every corner (where the line turns by more
    /// than 35°) and the ends, and others wherever the line has run 6 mm or turned 40° since the last node. Each node's
    /// handles follow the line's direction there, a third of the way to the next node, so the curves match the drawing.
    static func nodes(_ points: [Point], closed: Bool) -> [PathNode] {
        var p: [Point] = []
        for point in points where p.last.map({ $0.distance(to: point) > 1e-9 }) ?? true { p.append(point) }
        if closed, p.count > 1, p[0].distance(to: p[p.count - 1]) < 1e-9 { p.removeLast() }
        guard p.count >= 2 else { return p.map { PathNode($0) } }
        let n = p.count
        func at(_ i: Int) -> Point { p[(i % n + n) % n] }
        func unit(_ v: Point) -> Point { let size = hypot(v.x, v.y); return size > 1e-12 ? v * (1 / size) : Point(0, 0) }
        func turn(_ i: Int) -> Double {
            guard closed || (i > 0 && i < n - 1) else { return 0 }
            let a = unit(at(i) - at(i - 1)), b = unit(at(i + 1) - at(i))
            return acos(max(-1, min(1, a.x * b.x + a.y * b.y)))
        }
        let cornerAngle = 35 * Double.pi / 180
        var keep: [Int] = [0], run = 0.0, turned = 0.0
        for i in 1..<n {
            run += at(i).distance(to: at(i - 1)); turned += turn(i)
            let corner = turn(i) > cornerAngle
            if corner || i == n - 1 || run >= 6 || turned >= 40 * Double.pi / 180 { keep.append(i); run = 0; turned = 0 }
        }
        if closed, keep.last == n - 1, at(n - 1).distance(to: at(0)) < 1e-9 { keep.removeLast() }
        return keep.enumerated().map { m, i in
            let corner = turn(i) > cornerAngle
            let incoming = unit(at(i) - at(i - 1)), outgoing = unit(at(i + 1) - at(i))
            let smooth = unit(incoming + outgoing)
            let previous = m > 0 ? keep[m - 1] : (closed ? keep[keep.count - 1] : nil)
            let next = m < keep.count - 1 ? keep[m + 1] : (closed ? keep[0] : nil)
            let inHandle = previous.map { at(i) - (corner ? incoming : smooth) * (at(i).distance(to: at($0)) / 3) }
            let outHandle = next.map { at(i) + (corner ? outgoing : smooth) * (at(i).distance(to: at($0)) / 3) }
            // Open ends take the direction of the one piece they have.
            if !closed && i == 0 { return PathNode(at(i), outHandle: next.map { at(i) + outgoing * (at(i).distance(to: at($0)) / 3) }) }
            if !closed && i == n - 1 { return PathNode(at(i), inHandle: previous.map { at(i) - unit(at(i) - at(i - 1)) * (at(i).distance(to: at($0)) / 3) }) }
            return PathNode(at(i), smooth: !corner, inHandle: inHandle, outHandle: outHandle)
        }
    }

    // MARK: The drawings (in a 100 × 100 box, y down)

    /// The strokes of `design`, each a list of close points; a closed stroke ends where it starts.
    static func strokes(_ design: LineArtDesign) -> [[Point]] {
        switch design {
        case .heartDivider:
            let left = bezier((50, 50), (40, 50), (30, 56), (22, 50)) + spiral(15, 46, 7.5, 1, 1.3, 0.15 * .pi, clockwise: true).dropFirst()
            return [heart(50, 47, 16), left] + mirrored([left])
        case .scrollDivider:
            let side = bezier((44, 50), (36, 40), (24, 62), (12, 50)) + spiral(8, 46, 5, 0.8, 1.2, 0.5, clockwise: true).dropFirst()
            return [side] + mirrored([side]) + [line((44, 50), (50, 44), (56, 50), (50, 56), (44, 50))]
        case .laurel:
            let stem = bezier((20, 85), (30, 55), (55, 25), (85, 15))
            var strokes = [stem]
            for k in 1...8 {
                let i = Int(Double(k) * Double(stem.count) / 9.5), a = angle(stem[i + 1] - stem[i])
                strokes += leaf(stem[i], 14, 6, a - 0.75, vein: false) + leaf(stem[i], 14, 6, a + 0.75, vein: false)
            }
            return strokes
        case .ovalFrame:
            let oval = (0...96).map { k -> Point in let t = 2 * Double.pi * Double(k) / 96; return Point(50 + 38 * cos(t), 50 + 28 * sin(t)) }
            let curl = bezier((50, 22), (44, 14), (36, 16), (36, 20)) + spiral(39, 19, 3, 0.5, 1, .pi).dropFirst()
            let top = [curl] + mirrored([curl])
            return [oval] + top + top.map { $0.map { Point($0.x, 100 - $0.y) } }
                + leaf(Point(12, 50), 10, 5, .pi, vein: false) + leaf(Point(88, 50), 10, 5, 0, vein: false)
        case .flower:
            var strokes: [[Point]] = []
            for k in 0..<5 {
                let a = -Double.pi / 2 + Double(k) * 2 * .pi / 5
                strokes += leaf(Point(50 + 4 * cos(a), 35 + 4 * sin(a)), 18, 12, a, vein: false)
            }
            // The stem starts at the flower's middle (between the two lower petals), so it sews on without a jump.
            return strokes + [circle(50, 35, 4, 24), bezier((50, 39), (48, 65), (52, 80), (50, 95))]
                + leaf(Point(50, 78), 18, 8, -Double.pi / 5) + leaf(Point(50, 72), 16, 7, .pi + .pi / 5)
        case .tulip:
            let cup = bezier((35, 30), (30, 50), (38, 62), (50, 62)) + bezier((50, 62), (62, 62), (70, 50), (65, 30)).dropFirst()
            return [cup, line((35, 30), (42, 40), (50, 26), (58, 40), (65, 30)), bezier((42, 40), (44, 50), (48, 56), (50, 62)),
                    bezier((50, 62), (50, 75), (49, 85), (50, 95))]
                + leaf(Point(50, 92), 26, 10, -Double.pi / 2 - 0.5) + leaf(Point(50, 88), 22, 9, -Double.pi / 2 + 0.55, vein: false)
        case .butterfly:
            let upper = bezier((50, 45), (40, 15), (10, 15), (18, 38)) + bezier((18, 38), (22, 50), (40, 50), (50, 50)).dropFirst()
            let lower = bezier((50, 50), (35, 55), (18, 70), (28, 78)) + bezier((28, 78), (38, 84), (46, 66), (50, 55)).dropFirst()
            let feeler = bezier((50, 38), (48, 28), (44, 22), (40, 20)) + spiral(39, 18, 2, 0.3, 0.9, 0.5).dropFirst()
            let spots = [circle(30, 32, 4, 20), circle(36, 66, 3, 16)]
            return [upper, lower, line((50, 38), (50, 70)), feeler] + spots + mirrored([upper, lower, feeler] + spots)
        case .heartSwirl:
            return [heart(45, 45, 50), bezier((45, 71.5), (52, 84), (75, 88), (80, 78)) + spiral(74, 74, 6, 0.8, 1.3, 0.2, clockwise: true).dropFirst()]
        case .snowflake:
            var strokes: [[Point]] = []
            for k in 0..<6 {
                let a = Double(k) * .pi / 3, c = cos(a), s = sin(a)
                func at(_ u: Double, _ v: Double) -> Point { Point(50 + u * c - v * s, 50 + u * s + v * c) }
                strokes += [[at(0, 0), at(40, 0)], [at(28, -9), at(18, 0), at(28, 9)], [at(37, -6), at(30, 0), at(37, 6)]]
            }
            return strokes + [circle(50, 50, 7, 6)]
        case .sun:
            var strokes = [circle(50, 50, 18, 64)]
            for k in 0..<12 {
                let a = Double(k) * .pi / 6
                func at(_ r: Double, _ angle: Double) -> Point { Point(50 + r * cos(angle), 50 + r * sin(angle)) }
                // The rays start on the circle, so the needle can run round it from one to the next without a jump.
                strokes.append(k % 2 == 0 ? [at(18, a), at(40, a)] : [at(18, a - 0.16), at(34, a), at(18, a + 0.16)])
            }
            return strokes + [arc(50, 50, 10, 0.5, .pi - 0.5, 20), circle(43, 45, 1.5, 10), circle(57, 45, 1.5, 10)]
        case .teacup:
            let cup = [Point(28, 45)] + bezier((28, 45), (28, 70), (40, 78), (50, 78)).dropFirst() + bezier((50, 78), (60, 78), (72, 70), (72, 45)).dropFirst() + [Point(28, 45)]
            // The steam rises from the rim, the handle meets the cup's side and the saucer touches its bottom, so the
            // needle can run from part to part along lines already sewn instead of jumping.
            let steam = [40.0, 50, 60].map { x in stride(from: 45.0, through: 14, by: -1).map { y in Point(x + 3 * sin((y - 40) / 5), y) } }
            return [cup, arc(72, 56, 7, -Double.pi / 2, .pi / 2, 24), bezier((16, 70), (30, 80), (70, 80), (84, 70))] + steam + [heart(50, 60, 10)]
        case .anchor:
            // An arrowhead on the hook's right end, pointing the way the hook runs there (mirrored for the left end).
            let x = 50 + 24 * cos(0.25), y = 58 + 24 * sin(0.25), along = Point(sin(0.25), -cos(0.25)), across = Point(cos(0.25), sin(0.25))
            let tip = [[Point(x, y) - along * 6 - across * 4, Point(x, y), Point(x, y) - along * 6 + across * 4]]
            return [line((50, 20), (50, 82)), circle(50, 14, 6, 32), line((36, 32), (64, 32)), arc(50, 58, 24, 0.25, .pi - 0.25, 40)] + tip + mirrored(tip)
        case .rosette:
            var strokes: [[Point]] = []
            for k in 0..<8 {
                let a = Double(k) * .pi / 4, b = a + .pi / 8
                strokes += leaf(Point(50 + 8 * cos(a), 50 + 8 * sin(a)), 30, 14, a, vein: false)
                strokes += leaf(Point(50 + 8 * cos(b), 50 + 8 * sin(b)), 18, 8, b, vein: false)
            }
            return strokes + [circle(50, 50, 8, 32), circle(50, 50, 3, 16)]
        }
    }

    // MARK: Drawing helpers (all in the 100 × 100 box)

    private static func line(_ corners: (Double, Double)...) -> [Point] { corners.map { Point($0.0, $0.1) } }
    private static func angle(_ v: Point) -> Double { atan2(v.y, v.x) }
    /// A cubic Bézier curve from `a` to `d` with control points `b` and `c`, as 41 points.
    private static func bezier(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double), _ d: (Double, Double)) -> [Point] {
        (0...40).map { k in
            let t = Double(k) / 40, u = 1 - t
            return Point(u * u * u * a.0 + 3 * u * u * t * b.0 + 3 * u * t * t * c.0 + t * t * t * d.0,
                         u * u * u * a.1 + 3 * u * u * t * b.1 + 3 * u * t * t * c.1 + t * t * t * d.1)
        }
    }
    /// A spiral round (`x`, `y`) from radius `from` to `to` over `turns` turns, starting at angle `start`. In the
    /// drawing's box y points down, so `clockwise` turns the way a clock's hands do on screen.
    private static func spiral(_ x: Double, _ y: Double, _ from: Double, _ to: Double, _ turns: Double, _ start: Double, clockwise: Bool = false) -> [Point] {
        let sign = clockwise ? -1.0 : 1.0
        return (0...80).map { k in
            let t = Double(k) / 80, r = from + (to - from) * t, a = start + sign * 2 * .pi * turns * t
            return Point(x + r * cos(a), y + r * sin(a))
        }
    }
    private static func arc(_ x: Double, _ y: Double, _ r: Double, _ from: Double, _ to: Double, _ count: Int) -> [Point] {
        (0...count).map { k in let a = from + (to - from) * Double(k) / Double(count); return Point(x + r * cos(a), y + r * sin(a)) }
    }
    /// A circle as `count` points (and the first again, to close it).
    private static func circle(_ x: Double, _ y: Double, _ r: Double, _ count: Int = 64) -> [Point] { arc(x, y, r, 0, 2 * .pi, count) }
    /// The classic heart curve, `size` across, round (`x`, `y`), point down.
    private static func heart(_ x: Double, _ y: Double, _ size: Double) -> [Point] {
        (0...60).map { k in
            let t = 2 * Double.pi * Double(k) / 60
            let hx = 16 * pow(sin(t), 3), hy = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return Point(x + hx / 32 * size, y - hy / 32 * size)
        }
    }
    /// An almond-shaped leaf from `base`, `length` long and `width` wide, pointing at `direction` (radians), closed;
    /// with a `vein` from its base most of the way along.
    private static func leaf(_ base: Point, _ length: Double, _ width: Double, _ direction: Double, vein: Bool = true) -> [[Point]] {
        let c = cos(direction), s = sin(direction)
        func at(_ u: Double, _ v: Double) -> Point { Point(base.x + u * c - v * s, base.y + u * s + v * c) }
        let one = (0...20).map { k -> Point in let t = Double(k) / 20; return at(length * t, width / 2 * sin(.pi * t)) }
        let other = (0...20).reversed().map { k -> Point in let t = Double(k) / 20; return at(length * t, -width / 2 * sin(.pi * t)) }
        return [one + other.dropFirst()] + (vein ? [[at(0, 0), at(length * 0.8, 0)]] : [])
    }
    /// The strokes flipped left to right about the box's middle.
    private static func mirrored(_ strokes: [[Point]]) -> [[Point]] { strokes.map { $0.map { Point(100 - $0.x, $0.y) } } }
}
