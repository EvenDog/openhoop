// Turning fills (stitch angles) over many shapes and line layouts (2026-10-18): each is sewn and measured, and
// must come out with no bare spot, no stitch laid twice over, no stitch too long, and no more jumps between rows
// than it has now (`jumps`: most are 0; the rest are listed with why). Every case is measured and the table printed
// before any failure is reported, so one bad case doesn't hide the others. With TURNING_DUMP=<dir> set, each
// case's shape, lines and rows are written to <dir>/<name>.json for plotting.
import XCTest
@testable import EmbroideryCore

final class TurningFillStressTests: XCTestCase {
    /// `refused`: the lines cross inside the shape, so the fill must be refused. `jumps`: how many steps over
    /// 3 mm between rows it's allowed (what it makes today; see the notes by each case that has any).
    struct Case { var name: String; var rings: [[Point]]; var lines: [[Point]]; var spacing = 0.2; var start: Point? = nil; var refused = false; var jumps = 0 }
    struct Result {
        var name: String, sections = 0, stitches = 0, bare = 0.0, doubled = 0.0, thin = 0.0, jumps = 0, maxJump = 0.0, maxStitch = 0.0
        var trims = -1, planJumps = -1, error: String? = nil, compileError: String? = nil
    }
    struct Cell: Hashable { let x: Int, y: Int }

    // MARK: shapes
    func pts(_ p: [(Double, Double)]) -> [Point] { p.map { Point($0.0, $0.1) } }
    func rect(_ w: Double, _ h: Double) -> [Point] { pts([(0, 0), (w, 0), (w, h), (0, h)]) }
    func circle(_ r: Double, centre: Point = Point(0, 0), n: Int = 72, clockwise: Bool = false) -> [Point] {
        (0..<n).map { k in let a = Double(clockwise ? -k : k) / Double(n) * 2 * .pi; return centre + Point(r * cos(a), r * sin(a)) }
    }
    func ln(_ a: (Double, Double), _ b: (Double, Double)) -> [Point] { [Point(a.0, a.1), Point(b.0, b.1)] }
    func unitv(_ p: Point) -> Point { p * (1 / max(1e-9, hypot(p.x, p.y))) }
    /// A band `half` mm either side of a polyline, with mitred corners.
    func band(_ centre: [Point], half: Double) -> [Point] {
        var left: [Point] = [], right: [Point] = []
        for i in centre.indices {
            let dIn = i > 0 ? unitv(centre[i] - centre[i - 1]) : unitv(centre[1] - centre[0])
            let dOut = i < centre.count - 1 ? unitv(centre[i + 1] - centre[i]) : dIn
            let n1 = Point(-dIn.y, dIn.x), n2 = Point(-dOut.y, dOut.x), bis = unitv(n1 + n2)
            let scale = half / max(0.3, bis.x * n1.x + bis.y * n1.y)
            left.append(centre[i] + bis * scale); right.append(centre[i] - bis * scale)
        }
        return left + right.reversed()
    }
    /// Three arms `half` wide and `length` long from the origin at the given angles (degrees).
    func yShape(angles: [Double], half: Double, length: Double) -> [Point] {
        var ring: [Point] = []
        for k in angles.indices {
            let a = angles[k] * .pi / 180, b = angles[(k + 1) % angles.count] * .pi / 180
            let d = Point(cos(a), sin(a)), n = Point(-sin(a), cos(a)), d2 = Point(cos(b), sin(b)), n2 = Point(-sin(b), cos(b))
            ring += [d * length - n * half, d * length + n * half]
            ring.append(TurningFill.meeting((n * half, n * half + d), (n2 * (-half), n2 * (-half) + d2))!)
        }
        return ring
    }
    func rotate(_ rings: [[Point]], _ degrees: Double) -> [[Point]] {
        let a = degrees * .pi / 180
        return rings.map { $0.map { Point($0.x * cos(a) - $0.y * sin(a), $0.x * sin(a) + $0.y * cos(a)) } }
    }
    func mirror(_ rings: [[Point]]) -> [[Point]] { rings.map { $0.map { Point(-$0.x, $0.y) } } }
    func shift(_ rings: [[Point]], _ by: Point) -> [[Point]] { rings.map { $0.map { $0 + by } } }

    func cases() throws -> [Case] {
        var all: [Case] = []
        let cornerLines = [ln((1.7, 30.6), (6.6, 39.3)), ln((52.7, 34.0), (58.6, 23.9))]
        let r = rect(60, 40.9)
        all.append(Case(name: "rect corner lines", rings: [r], lines: cornerLines))
        all.append(Case(name: "rect corner lines reversed points", rings: [r], lines: cornerLines.map { $0.reversed() }))
        all.append(Case(name: "rect corner lines spacing 0.5", rings: [r], lines: cornerLines, spacing: 0.5))
        all.append(Case(name: "rect near-parallel", rings: [r], lines: [ln((10, 0), (10.5, 40)), ln((50, 0), (49.5, 40))], jumps: 2))   // tatami's first row along an edge almost parallel to it is a sliver
        all.append(Case(name: "rect parallel", rings: [r], lines: [ln((10, 0), (10, 40)), ln((50, 0), (50, 40))]))
        all.append(Case(name: "rect parallel 4", rings: [r], lines: [10.0, 20, 35, 50].map { ln(($0, 5), ($0, 30)) }))
        // Five lines all pointing at one spot 60 mm below the rectangle, and the same with the spot moved a little per line.
        func spoke(_ x: Double, hub: Point) -> [Point] { let u = unitv(Point(x, 20) - hub); return [hub + u * 60, hub + u * 100] }
        all.append(Case(name: "rect 5 lines one hub", rings: [r], lines: [5.0, 17.5, 30, 42.5, 55].map { spoke($0, hub: Point(30, -60)) }))
        all.append(Case(name: "rect 5 lines near hubs", rings: [r], lines: [5.0, 17.5, 30, 42.5, 55].enumerated().map { spoke($1, hub: Point(30 + Double($0) * 3, -60 - Double($0) * 5)) }))
        all.append(Case(name: "rect line through vertex", rings: [r], lines: [ln((0, 0), (10, 40.9)), cornerLines[1]]))
        all.append(Case(name: "rect line along edge", rings: [r], lines: [ln((0, 5), (0, 30)), cornerLines[1]]))
        all.append(Case(name: "rect line grazes corner 0.3", rings: [r], lines: [ln((-1, 39.6), (1, 41.6)), cornerLines[1]], jumps: 1))   // short fan rows in that corner
        all.append(Case(name: "rect line grazes corner 0.05", rings: [r], lines: [ln((-1, 39.85), (1, 41.85)), cornerLines[1]]))
        all.append(Case(name: "rect duplicate line", rings: [r], lines: cornerLines + [cornerLines[0]]))
        all.append(Case(name: "rect lines meet on edge", rings: [rect(40, 40)], lines: [ln((15, 30), (20, 40)), ln((25, 30), (20, 40))], refused: true))
        all.append(Case(name: "rect lines meet 0.1 outside", rings: [rect(40, 40)], lines: [ln((15, 30), (20, 40.1)), ln((25, 30), (20, 40.1))]))
        all.append(Case(name: "rect lines meet 0.1 inside", rings: [rect(40, 40)], lines: [ln((15, 30), (20, 39.9)), ln((25, 30), (20, 39.9))], refused: true))
        all.append(Case(name: "rect short line", rings: [r], lines: [ln((30, 20), (30, 20.005)), cornerLines[1]]))
        all.append(Case(name: "rect line misses shape", rings: [r], lines: [ln((100, 100), (110, 100)), cornerLines[1]]))

        let elbow = pts([(0, 0), (40, 0), (40, 10), (10, 10), (10, 40), (0, 40)])
        all.append(Case(name: "elbow", rings: [elbow], lines: [ln((-2, 30), (12, 30)), ln((30, -2), (30, 12))]))
        all.append(Case(name: "elbow lines near corner", rings: [elbow], lines: [ln((-2, 12), (12, 12)), ln((12, -2), (12, 12))]))
        let elbowLines = [ln((-2, 30), (12, 30)), ln((-1, -1), (11, 11)), ln((30, -2), (30, 12))]   // the middle one corner to corner
        all.append(Case(name: "elbow 3 lines", rings: [elbow], lines: elbowLines))
        all.append(Case(name: "elbow 3 lines rotated 37", rings: rotate([elbow], 37), lines: rotate(elbowLines, 37)))
        all.append(Case(name: "elbow 3 lines mirrored", rings: mirror([elbow]), lines: mirror(elbowLines)))
        all.append(Case(name: "elbow corner cut off", rings: [elbow], lines: [ln((-2, 30), (12, 30)), ln((-3, 13), (13, -3)), ln((30, -2), (30, 12))], jumps: 3))   // the middle piece touches all three lines: straight rows

        let bent = pts([(-19, 7.1), (-31, 27.5), (-12.7, 27.5), (7, 0.3), (-1.4, -14), (-31.2, -11.7), (-32.8, 8.7)])
        let bentLines = [ln((-26.5, 9.5), (-24.7, -18.5)), ln((-26.6, 15.7), (-0.2, 35.9)), ln((-24.7, 11.5), (17.3, -17.6))]
        all.append(Case(name: "bent", rings: [bent], lines: bentLines, start: Point(-31, -11), jumps: 1))   // tatami's sliver row along the left edge
        all.append(Case(name: "bent from top", rings: [bent], lines: bentLines, start: Point(-31, 27), jumps: 1))
        all.append(Case(name: "bent rotated 120", rings: rotate([bent], 120), lines: rotate(bentLines, 120), jumps: 1))
        all.append(Case(name: "bent mirrored", rings: mirror([bent]), lines: mirror(bentLines), jumps: 1))
        all.append(Case(name: "bent spacing 0.5", rings: [bent], lines: bentLines, spacing: 0.5))

        let u = pts([(0, 0), (50, 0), (50, 40), (40, 40), (40, 10), (10, 10), (10, 40), (0, 40)])
        // One line across the left arm reaches across the right arm too, so it cuts both.
        let uLines = [ln((-2, 30), (12, 30)), ln((-1, -1), (11, 11)), ln((25, -2), (25, 12)), ln((39, 11), (51, -1))]
        all.append(Case(name: "U 4 lines", rings: [u], lines: uLines))
        all.append(Case(name: "U 4 lines from right", rings: [u], lines: uLines, start: Point(45, 38)))
        all.append(Case(name: "U 2 lines", rings: [u], lines: [uLines[0], uLines[2]]))
        all.append(Case(name: "U arm lines tilted", rings: [u], lines: [ln((-2, 30), (12, 31)), ln((25, -2), (25, 12)), ln((38, 31), (52, 30))]))
        all.append(Case(name: "U rotated 200", rings: rotate([u], 200), lines: rotate(uLines, 200)))

        let snake = band(pts([(0, 0), (30, 20), (0, 40), (30, 60)]), half: 5)
        let snakeLines = [ln((5, 8), (11, -1)), ln((27, 24), (33, 16)), ln((15, 26), (15, 34)), ln((5, 36), (-2, 44)), ln((27, 44), (33, 36)), ln((15, 46), (15, 54))]
        all.append(Case(name: "snake 6 lines", rings: [snake], lines: snakeLines, refused: true))
        all.append(Case(name: "snake 3 lines", rings: [snake], lines: [snakeLines[0], snakeLines[2], snakeLines[5]], jumps: 4))   // the middle line, stretched across, cuts the other two bends too
        all.append(Case(name: "snake rotated 45", rings: rotate([snake], 45), lines: rotate(snakeLines, 45), refused: true))

        let ring = [circle(20), circle(10, clockwise: true)]
        func radial(_ d: Double) -> [Point] { let a = d * .pi / 180; return [Point(8 * cos(a), 8 * sin(a)), Point(22 * cos(a), 22 * sin(a))] }
        all.append(Case(name: "ring 4 radial", rings: ring, lines: [0.0, 90, 180, 270].map(radial)))
        all.append(Case(name: "ring 6 radial", rings: ring, lines: [0.0, 60, 120, 180, 240, 300].map(radial)))
        all.append(Case(name: "ring 3 radial uneven", rings: ring, lines: [10.0, 60, 200].map(radial)))
        all.append(Case(name: "ring 2 radial", rings: ring, lines: [0.0, 90].map(radial)))
        all.append(Case(name: "ring 1 radial", rings: ring, lines: [45.0].map(radial), jumps: 2))   // plain tatami rows round a hole
        all.append(Case(name: "ring 2 level lines", rings: ring, lines: [ln((-22, 15), (22, 15)), ln((-22, -15), (22, -15))], jumps: 2))   // straight rows round the hole
        all.append(Case(name: "ring 2 lines off centre", rings: ring, lines: [ln((9, 3), (21, 3)), ln((3, 9), (3, 21))]))
        all.append(Case(name: "ring 4 radial spacing 0.5", rings: ring, lines: [0.0, 90, 180, 270].map(radial), spacing: 0.5))

        let holed = [rect(60, 40), pts([(25, 15), (35, 15), (35, 25), (25, 25)]).reversed()]
        all.append(Case(name: "rect with hole corner lines", rings: holed, lines: cornerLines, jumps: 1))   // rows split by the hole
        all.append(Case(name: "rect with hole line through hole", rings: holed, lines: [ln((30, -2), (30, 42)), cornerLines[1]], jumps: 2))
        all.append(Case(name: "rect with hole 2 lines through hole", rings: holed, lines: [ln((30, -2), (30, 42)), ln((-2, 20), (62, 20))]))

        let leaf = (0...40).map { Point(Double($0), -12 * sin(.pi * Double($0) / 40)) } + (1..<40).reversed().map { Point(Double($0), 12 * sin(.pi * Double($0) / 40)) }
        all.append(Case(name: "leaf 3 lines", rings: [leaf], lines: [ln((10, -5), (10.9, 5)), ln((20, -5), (20, 5)), ln((30, -5), (29.1, 5))]))
        all.append(Case(name: "leaf veins one hub", rings: [leaf], lines: [ln((8, -3), (9.7, 0)), ln((20, -3), (20, 3)), ln((32, -3), (30.3, 0))]))
        all.append(Case(name: "leaf 1 line", rings: [leaf], lines: [ln((20, -5), (20, 5))]))

        let disc = [circle(20)]
        all.append(Case(name: "circle 1 line", rings: disc, lines: [ln((-5, -5), (5, 5))]))
        all.append(Case(name: "circle 2 lines", rings: disc, lines: [ln((-15, -5), (-12, 5)), ln((15, -5), (12, 5))]))
        all.append(Case(name: "circle 3 lines", rings: disc, lines: [ln((-12, -5), (-12, 5)), ln((-2, -5), (2, 6)), ln((12, -5), (12, 5))]))
        all.append(Case(name: "circle 2 lines nearly crossing", rings: disc, lines: [ln((-5, 0), (-5, 19.9)), ln((5, 0), (-4.9, 19.9))], jumps: 2))   // 3.3 mm steps where the rows converge

        let y = yShape(angles: [90, 210, 330], half: 5, length: 35)
        func across(_ d: Double, at s: Double) -> [Point] { let a = d * .pi / 180; let c = Point(s * cos(a), s * sin(a)), n = Point(-sin(a), cos(a)) * 7; return [c - n, c + n] }
        all.append(Case(name: "Y 3 arm lines", rings: [y], lines: [90.0, 210, 330].map { across($0, at: 20) }, jumps: 4))   // the middle touches three lines: straight rows, then a jump to the last arm
        all.append(Case(name: "Y 3 arm lines near centre", rings: [y], lines: [90.0, 210, 330].map { across($0, at: 9) }, jumps: 2))
        all.append(Case(name: "Y 2 arm lines", rings: [y], lines: [90.0, 210].map { across($0, at: 20) }))

        let star = (0..<10).map { k -> Point in let a = Double(k) * .pi / 5 + .pi / 2, r = k % 2 == 0 ? 25.0 : 10.0; return Point(r * cos(a), r * sin(a)) }
        all.append(Case(name: "star 2 parallel lines", rings: [star], lines: [ln((-5, 5), (5, 5)), ln((-5, -5), (5, -5))], jumps: 2))   // rows split by the points, as tatami's are
        all.append(Case(name: "star 2 lines", rings: [star], lines: [ln((-5, 5), (5, 5)), ln((-5, -9.8), (5, -6.2))], jumps: 1))
        all.append(Case(name: "star 1 line", rings: [star], lines: [ln((-5, 5), (5, 5))], jumps: 1))

        all.append(Case(name: "thin bar 1 mm", rings: [rect(40, 1)], lines: [ln((10, -1), (10.3, 2)), ln((20, -1), (20, 2)), ln((30, -1), (29.7, 2))]))
        all.append(Case(name: "thin bar 1 mm spacing 0.5", rings: [rect(40, 1)], lines: [ln((10, -1), (10.3, 2)), ln((20, -1), (20, 2)), ln((30, -1), (29.7, 2))], spacing: 0.5))
        all.append(Case(name: "tiny square 2 mm", rings: [rect(2, 2)], lines: [ln((0.7, -1), (0.7, 3)), ln((1.4, -1), (1.7, 3))]))
        all.append(Case(name: "long bar 10 lines", rings: [rect(200, 10)], lines: (0..<10).map { k in let x = 15 + Double(k) * 19, a = (90 - Double(k) * 5) * .pi / 180; return [Point(x, 5) - Point(cos(a), sin(a)) * 6, Point(x, 5) + Point(cos(a), sin(a)) * 6] }))

        let crescent = try AreaGeometry.subtracting([circle(20, centre: Point(8, 0), clockwise: true)], from: [circle(25)])[0]
        let cLines = [ln((0, 17), (0.5, 27)), ln((-20, 12), (-12, 20)), ln((-26, 0), (-10, 0)), ln((-20, -12), (-12, -20)), ln((0, -17), (0.5, -27))]
        all.append(Case(name: "crescent 5 lines", rings: crescent, lines: cLines, jumps: 6))   // each tip's line, stretched across, cuts the other tip too
        all.append(Case(name: "crescent 3 lines", rings: crescent, lines: [cLines[0], cLines[2], cLines[4]]))
        all.append(Case(name: "crescent rotated 90", rings: rotate(crescent, 90), lines: rotate(cLines, 90), jumps: 5))

        let comb = pts([(0, 0), (60, 0), (60, 40), (49, 40), (49, 15), (44, 15), (44, 40), (32, 40), (32, 15), (27, 15), (27, 40), (15, 40), (15, 15), (10, 15), (10, 40), (0, 40)])
        all.append(Case(name: "comb 4 parallel lines", rings: [comb], lines: [5.0, 21, 38, 55].map { ln(($0, 20), ($0, 35)) }, jumps: 3))   // tatami starts the rows past each slot at the far end
        all.append(Case(name: "comb 4 tilted lines", rings: [comb], lines: [5.0, 21, 38, 55].enumerated().map { k, x in let a = (84 + Double(k) * 4) * .pi / 180; return [Point(x, 25) - Point(cos(a), sin(a)) * 8, Point(x, 25) + Point(cos(a), sin(a)) * 8] }, jumps: 5))

        let dumbbell = pts([(-10, -10), (10, -10), (10, -2), (30, -2), (30, -10), (50, -10), (50, 10), (30, 10), (30, 2), (10, 2), (10, 10), (-10, 10)])
        all.append(Case(name: "dumbbell 3 lines", rings: [dumbbell], lines: [ln((0, -12), (0, 12)), ln((20, -3), (20, 3)), ln((40, -12), (42, 12))], jumps: 1))   // a row right along the step's edge
        all.append(Case(name: "dumbbell diagonal", rings: [dumbbell], lines: [ln((-5, -5), (5, 5)), ln((40, -12), (40, 12))], jumps: 2))   // fan rows split by the bar
        all.append(Case(name: "dumbbell blobs only", rings: [dumbbell], lines: [ln((0, -12), (0, 12)), ln((40, -12), (40, 12))]))

        // The notch shape from the app (2026-10-17), as the existing tests use it, with its two line layouts.
        let notchPoints = [(-26.51, 28.28), (-23.33, 39.93), (-9.1, 24.42), (-19.1, 11.36), (-37.69, 15.71), (-39.45, 29.28), (-30.44, 26.92), (-30.91, 37.79), (-28.02, 39.76), (-26.37, 36.73), (-27.08, 35.16)]
        let smooth = [false, false, false, false, false, true, false, false, true, true, false]
        let notch = try AreaGeometry.offset([AreaGeometry.ring(zip(notchPoints, smooth).map { PathNode(Point($0.0.0, $0.0.1), smooth: $0.1) })], by: 0.2)
        all.append(Case(name: "notch 2 lines", rings: notch, lines: [ln((-35.0, 36.08), (-34.81, 10.28)), ln((-26.15, 33.91), (-14.37, 34.18))], jumps: 3))   // rows split by the notch
        all.append(Case(name: "notch lines meet at notch", rings: notch, lines: [ln((-35.0, 36.07), (-34.81, 10.27)), ln((-26.15, 33.91), (-7.87, 27.96))], jumps: 6))
        return all
    }

    // MARK: measuring
    func measure(_ c: Case) -> Result {
        var result = Result(name: c.name)
        let rows: [[Point]]
        do { rows = try TurningFill.rows(in: c.rings, angleLines: c.lines, spacing: c.spacing, length: 3, start: c.start) }
        catch { result.error = "\(error)".prefix(60).description; return result }
        result.sections = rows.count
        let stitches = rows.flatMap { zip($0, $0.dropFirst()).map { ($0, $1) } }
        result.stitches = stitches.count
        result.maxStitch = stitches.map { $0.0.distance(to: $0.1) }.max() ?? 0
        let hops = zip(rows, rows.dropFirst()).map { $0.last!.distance(to: $1.first!) }
        result.jumps = hops.filter { $0 > 3 }.count
        result.maxJump = hops.max() ?? 0
        // Thread laid, sampled every 0.1 mm along each stitch, into 0.5 mm cells.
        var samples: [Cell: [(Point, Double)]] = [:]
        for (a, b) in stitches {
            let d = a.distance(to: b), n = max(1, Int(ceil(d / 0.1)))
            for k in 0..<n {
                let p = a + (b - a) * ((Double(k) + 0.5) / Double(n))
                samples[Cell(x: Int(floor(p.x / 0.5)), y: Int(floor(p.y / 0.5))), default: []].append((p, d / Double(n)))
            }
        }
        // Test points on a 0.5 mm grid inside the shape, well in from its edge.
        var inset = (try? AreaGeometry.offset(c.rings, by: -0.5)) ?? []
        if inset.isEmpty { inset = (try? AreaGeometry.offset(c.rings, by: -0.2)) ?? c.rings }
        let all = c.rings.flatMap { $0 }
        let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!, minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!
        var tested = 0, bare = 0, doubled = 0, thin = 0
        // Bare: nothing within 0.45 mm (at wider spacings 1.4 rows: where a fan's rows converge, every other pair
        // stops short, so a spot can be most of two rows from the nearest).
        let expected = 1 / c.spacing, bareLimit = max(0.45, 1.4 * c.spacing)
        for x in stride(from: minX + 0.25, to: maxX, by: 0.5) { for y in stride(from: minY + 0.25, to: maxY, by: 0.5) {
            let p = Point(x, y)
            guard AreaGeometry.contains(p, rings: inset) else { continue }
            tested += 1
            var nearest = Double.infinity, thread = 0.0
            let cx = Int(floor(x / 0.5)), cy = Int(floor(y / 0.5))
            for dx in -2...2 { for dy in -2...2 { for (q, w) in samples[Cell(x: cx + dx, y: cy + dy)] ?? [] {
                nearest = min(nearest, q.distance(to: p))
                if abs(q.x - x) < 0.5 && abs(q.y - y) < 0.5 { thread += w }
            }}}
            if nearest > bareLimit { bare += 1 } else if thread > 1.7 * expected { doubled += 1 } else if thread < 0.5 * expected { thin += 1 }
        }}
        if tested > 0 { result.bare = 100 * Double(bare) / Double(tested); result.doubled = 100 * Double(doubled) / Double(tested); result.thin = 100 * Double(thin) / Double(tested) }
        // The whole design, as the app sews it: how many trims and jumps.
        var object = RunObject(name: c.name, nodes: c.rings[0].map { PathNode($0) })
        if c.rings.count > 1 { object.holes = c.rings.dropFirst().map { $0.map { PathNode($0) } } }
        object.closed = true; object.stitchLength = 3
        object.digitizing = DigitizingSettings(kind: .fill); object.digitizing?.angleLines = c.lines
        object.digitizing?.underlay = UnderlayStyle.none; object.digitizing?.expansion = 0
        object.digitizing?.spacing = c.spacing * 2; object.digitizing?.spacingAcrossTwoRows = true
        var design = Design(); design.objects = [object]
        do {
            let plan = try StitchEngine.compile(design)
            result.trims = plan.commands.filter { $0.op == .trim }.count
            result.planJumps = plan.commands.filter { $0.op == .jump }.count
        } catch { result.compileError = "\(error)".prefix(60).description }
        if let dir = ProcessInfo.processInfo.environment["TURNING_DUMP"] {
            func js(_ ps: [Point]) -> String { "[" + ps.map { "[\($0.x),\($0.y)]" }.joined(separator: ",") + "]" }
            let json = "{\"rings\":[\(c.rings.map(js).joined(separator: ","))],\"lines\":[\(c.lines.map(js).joined(separator: ","))],\"rows\":[\(rows.map(js).joined(separator: ","))]}"
            try? json.write(toFile: "\(dir)/\(c.name.replacingOccurrences(of: " ", with: "_")).json", atomically: true, encoding: .utf8)
        }
        return result
    }

    func testManyShapesAndLineLayouts() throws {
        var table = ["case | sections | stitches | bare% | doubled% | thin% | jumps>3mm | longest jump | longest stitch | trims | error"], problems: [String] = []
        for c in try cases() {
            let r = measure(c)
            table.append(String(format: "%@ | %d | %d | %.1f | %.1f | %.1f | %d | %.1f | %.2f | %d | %@", r.name, r.sections, r.stitches, r.bare, r.doubled, r.thin, r.jumps, r.maxJump, r.maxStitch, r.trims, r.error ?? r.compileError ?? ""))
            if c.refused {
                if r.error == nil { problems.append("\(c.name): should be refused, the lines cross inside") }
                continue
            }
            if let error = r.error ?? r.compileError { problems.append("\(c.name): \(error)"); continue }
            if r.bare > 0 { problems.append("\(c.name): \(r.bare)% bare") }
            if r.doubled > 8 { problems.append("\(c.name): \(r.doubled)% sewn twice over") }
            if r.thin > 3 { problems.append("\(c.name): \(r.thin)% thin") }
            if r.maxStitch > 3.6 { problems.append("\(c.name): a \(r.maxStitch) mm stitch") }   // a fan row stopping short can run 0.6 over
            if r.jumps > c.jumps { problems.append("\(c.name): \(r.jumps) jumps over 3 mm (longest \(r.maxJump)), \(c.jumps) allowed") }
        }
        let report = table.joined(separator: "\n")
        print("TURNING-FILL-REPORT\n" + report + "\nEND-REPORT")
        if let dir = ProcessInfo.processInfo.environment["TURNING_DUMP"] { try? report.write(toFile: "\(dir)/report.txt", atomically: true, encoding: .utf8) }
        for problem in problems { XCTFail(problem) }
    }
}
