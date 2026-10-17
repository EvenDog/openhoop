// Satin from a center line: turns a running line or outline into a satin column of a chosen width centered on it,
// so a column can be drawn as one line instead of clicking left/right edge pairs. The result is an ordinary satin
// (edge pairs) that can be reshaped afterwards like any other.
import Foundation

public enum SatinLine {
    public static let widths = 0.8...10.0
    public static let defaultWidth = 3.0

    /// True for objects that can become a satin column this way: running lines and unstitched outlines.
    public static func canConvert(_ object: RunObject) -> Bool {
        object.rawStitches == nil && (object.kind == .run || object.kind == .vector) && object.nodes.count >= 2
    }

    /// `object` turned into a satin column `width` mm wide centered on its path, keeping its name, id, thread and
    /// place. Sharp turns are rounded just enough for the satin to turn. Throws, with a reason, if it can't sew.
    public static func column(from object: RunObject, width: Double) throws -> RunObject {
        guard canConvert(object) else { throw DesignError.invalid("‘\(object.name)’ isn't a line. Satin from a center line needs a running stitch or outline.") }
        guard widths.contains(width) else { throw DesignError.invalid("Satin width must be between 0.8 and 10 mm.") }
        var satin = object
        satin.nodes = object.closed
            ? try SatinBorder.edgePairs(around: AreaGeometry.ring(object.nodes), width: width, name: object.name)
            : try openPairs(along: RunningEngine.flatten(object.nodes).flatMap { $0 }, width: width, name: object.name)
        satin.digitizing = DigitizingSettings(kind: .satin)
        satin.holes = nil; satin.entry = nil; satin.exit = nil
        do { _ = try AreaEngine.satin(satin) } catch {
            throw DesignError.invalid("A \(width.formatted()) mm satin doesn't fit along ‘\(object.name)’: \(error.localizedDescription) Try a narrower width or smoother turns.")
        }
        return satin
    }

    /// Edge pairs (left rail first in each pair) for an open center line: corners rounded to at least half the width
    /// plus 0.6 mm (so stitches on the inside of a turn can't cross), then a pair wherever the line bends (within
    /// 0.1 mm) and at least every 10 mm, so the column has few pairs to drag when reshaping it.
    static func openPairs(along path: [Point], width: Double, name: String) throws -> [PathNode] {
        var line: [Point] = []
        for p in path where line.last.map({ $0.distance(to: p) > 0.01 }) ?? true { line.append(p) }
        guard line.count >= 2, AreaGeometry.pathLength(line) >= 1 else { throw DesignError.invalid("‘\(name)’ is too short for a satin column.") }
        let half = width / 2
        let center = limited(simplified(evenlySpaced(filleted(line, radius: half + 0.6), spacing: 0.4), tolerance: 0.1), spacing: 10)
        var nodes: [PathNode] = []
        func normal(_ a: Point, _ b: Point) -> Point { let d = b - a, l = hypot(d.x, d.y); return l > 0 ? Point(-d.y / l, d.x / l) : Point(0, 1) }
        for i in center.indices {
            // Ends use their segment's normal; points between use the average of both, stretched slightly at bends
            // so the rails stay half the width from the center line.
            let before = i > 0 ? normal(center[i - 1], center[i]) : nil, after = i < center.count - 1 ? normal(center[i], center[i + 1]) : nil
            var direction = (before ?? after!) + (after ?? before!)
            let length = hypot(direction.x, direction.y)
            direction = length > 1e-9 ? direction * (1 / length) : (before ?? after!)
            let reference = before ?? after!
            let stretch = 1 / max(0.5, direction.x * reference.x + direction.y * reference.y)
            nodes.append(PathNode(center[i] + direction * (half * stretch)))   // left rail
            nodes.append(PathNode(center[i] - direction * (half * stretch)))   // right rail
        }
        return nodes
    }

    /// The open line with each corner replaced by a circular arc of `radius` (smaller where the segments beside the
    /// corner are too short to fit it; the satin check then explains if the turn is too tight).
    static func filleted(_ line: [Point], radius: Double) -> [Point] {
        guard line.count > 2 else { return line }
        var result = [line[0]]
        for i in 1..<(line.count - 1) {
            let a = line[i - 1], b = line[i], c = line[i + 1]
            let u = (a - b) * (1 / a.distance(to: b)), v = (c - b) * (1 / c.distance(to: b))
            let cosine = max(-1, min(1, u.x * v.x + u.y * v.y)), opening = acos(cosine)   // the angle inside the corner
            let turn = Double.pi - opening
            guard turn > 0.05 else { result.append(b); continue }   // nearly straight: nothing to round
            // The arc touches both segments `tangent` mm from the corner; its radius follows from the angle.
            let tangent = min(radius / tan(opening / 2), a.distance(to: b) / 2, c.distance(to: b) / 2)
            let r = tangent * tan(opening / 2)
            let bisector = (u + v) * (1 / hypot((u + v).x, (u + v).y))
            let middle = b + bisector * (r / sin(opening / 2))   // the arc's center
            let start = b + u * tangent, end = b + v * tangent
            let a0 = atan2(start.y - middle.y, start.x - middle.x)
            var sweep = atan2(end.y - middle.y, end.x - middle.x) - a0
            if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }
            let steps = max(2, Int(ceil(abs(sweep) * r / 0.4)))
            for k in 0...steps { let t = a0 + sweep * Double(k) / Double(steps); result.append(middle + Point(cos(t), sin(t)) * r) }
        }
        result.append(line[line.count - 1])
        return result
    }

    /// The line with points dropped where it runs straight: the classic Douglas–Peucker method keeps a point only if
    /// leaving it out would move the line more than `tolerance` mm. Both ends always stay.
    static func simplified(_ line: [Point], tolerance: Double) -> [Point] {
        guard line.count > 2 else { return line }
        var keep = [Bool](repeating: false, count: line.count); keep[0] = true; keep[line.count - 1] = true
        var spans = [(0, line.count - 1)]
        while let (first, last) = spans.popLast() {
            let a = line[first], b = line[last], length = a.distance(to: b)
            var farthest = -1, distance = tolerance
            for i in (first + 1)..<last {
                // Distance from the point to the straight line a–b (or to a, when a and b coincide).
                let d = length > 1e-9 ? abs(AreaGeometry.cross(b - a, line[i] - a)) / length : line[i].distance(to: a)
                if d > distance { distance = d; farthest = i }
            }
            if farthest >= 0 { keep[farthest] = true; spans += [(first, farthest), (farthest, last)] }
        }
        return line.indices.filter { keep[$0] }.map { line[$0] }
    }

    /// The line with extra points added so no two neighbors are more than `spacing` mm apart.
    static func limited(_ line: [Point], spacing: Double) -> [Point] {
        guard let first = line.first else { return line }
        var result = [first]
        for (a, b) in zip(line, line.dropFirst()) {
            let parts = max(1, Int(ceil(a.distance(to: b) / spacing)))
            for k in 1...parts { result.append(a + (b - a) * (Double(k) / Double(parts))) }
        }
        return result
    }

    /// Points evenly spaced along an open line about `spacing` apart, including both ends.
    static func evenlySpaced(_ line: [Point], spacing: Double) -> [Point] {
        let length = AreaGeometry.pathLength(line), count = max(1, Int(ceil(length / spacing))), step = length / Double(count)
        var result: [Point] = [], segment = 0, walked = 0.0
        for k in 0...count {
            let target = Double(k) * step
            while segment < line.count - 2 && walked + line[segment].distance(to: line[segment + 1]) < target {
                walked += line[segment].distance(to: line[segment + 1]); segment += 1
            }
            let a = line[segment], b = line[segment + 1], piece = a.distance(to: b)
            result.append(piece > 0 ? a + (b - a) * min(1, (target - walked) / piece) : a)
        }
        return result
    }
}

extension SatinLine {
    /// The width of an even-width satin, such as a satin border or a satin made from a line: the narrowest distance
    /// across it (its edge pairs are a little wider where it bends). nil for satins whose width varies, like most
    /// hand-drawn columns, and for lettering, which keep their own shape.
    public static func evenWidth(of object: RunObject) -> Double? {
        guard object.kind == .satin, object.rawStitches == nil, object.lettering == nil, object.monogram == nil,
              object.nodes.count >= 4, object.nodes.count % 2 == 0 else { return nil }
        let across = stride(from: 0, to: object.nodes.count, by: 2).map { object.nodes[$0].point.distance(to: object.nodes[$0 + 1].point) }
        // Within 8% (plus a hair for rounding) counts as even: borders and satin lines stay well inside that.
        guard let narrowest = across.min(), let widest = across.max(), narrowest > 0.1, widest <= narrowest * 1.08 + 0.05 else { return nil }
        return narrowest
    }

    /// `object`, an even-width satin, rebuilt `width` mm wide around the same center line (the middle of each edge
    /// pair), the way a border or a satin line is first made, so corners are rounded to suit the new width. Everything
    /// else about it stays. Throws, with a reason, if it isn't an even-width satin or can't sew that wide.
    public static func rewidth(_ object: RunObject, to width: Double) throws -> RunObject {
        guard evenWidth(of: object) != nil else { throw DesignError.invalid("‘\(object.name)’ isn't an even-width satin, so it has no single width to change.") }
        guard widths.contains(width) else { throw DesignError.invalid("Satin width must be between 0.8 and 10 mm.") }
        let center = stride(from: 0, to: object.nodes.count, by: 2).map { (object.nodes[$0].point + object.nodes[$0 + 1].point) * 0.5 }
        var satin = object
        satin.nodes = object.closed
            ? try SatinBorder.edgePairs(around: center, width: width, name: object.name)
            : try openPairs(along: center, width: width, name: object.name)
        do { _ = try AreaEngine.satin(satin) } catch {
            throw DesignError.invalid("A \(width.formatted()) mm satin doesn't fit along ‘\(object.name)’: \(error.localizedDescription) Try a narrower width.")
        }
        return satin
    }
}
