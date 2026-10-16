// Basic shapes, freehand strokes, and the stitches the Open Shape and Closed Shape tools put on what you draw. Pick a stitch
// first (for closed shapes: a fill, an outline, or both), then draw an outline or drag out a shape, and the new
// object gets that stitch. Shapes are ordinary outlines made of nodes, so they can be reshaped, resized and restitched afterwards.
import Foundation

/// The shapes the Rectangle, Ellipse and Basic Shapes tools draw.
public enum BasicShape: String, Codable, CaseIterable, Sendable {
    case rectangle, ellipse, polygon, star, heart, arrow
    public var title: String { rawValue.capitalized }
    /// The shapes the Basic Shapes tool offers (Rectangle and Ellipse have tools of their own).
    public static let basicChoices: [BasicShape] = [.polygon, .star, .heart, .arrow]
}

/// The stitch the Open Shape tool puts on a new line.
public enum OpenShapeStitch: String, Codable, CaseIterable, Sendable {
    case running, bean, satin
    public var title: String {
        switch self { case .running: return "Running"; case .bean: return "Bean (triple run)"; case .satin: return "Satin line" }
    }
}

/// The choices the shape tools remember between uses. The app keeps them in its preferences, not in designs.
public struct ShapeSettings: Codable, Equatable, Sendable {
    public var openStitch = OpenShapeStitch.running
    /// What the Closed Shape and shape tools put on a new shape: a fill (nil for none) and an outline sewn on its
    /// edge (nil for none). One of them is always on: turning both off turns the other one back on.
    public var closedFill: FillStyle? = .tatami { didSet { if closedFill == nil && closedOutline == nil { closedOutline = .running } } }
    public var closedOutline: OpenShapeStitch? = nil { didSet { if closedOutline == nil && closedFill == nil { closedFill = .tatami } } }
    /// The shape the Basic Shapes tool draws (one of `BasicShape.basicChoices`).
    public var basicShape = BasicShape.star
    public var polygonSides = 6
    public var starPoints = 5
    /// How deep a star's points go: the inner corners' distance from the middle, as a share of the outer ones'.
    public var starInner = 0.5
    /// How round a rectangle's corners are, in mm (0 is square corners).
    public var cornerRadius = 0.0
    public init() {}
    public static let polygonSideRange = 3...12, starPointRange = 4...12, starInnerRange = 0.2...0.8, cornerRadiusRange = 0.0...20.0

    /// The next closed shape's stitches in words, such as "Tatami fill + satin outline".
    public var closedSummary: String {
        let outline = closedOutline.map { outline -> String in
            switch outline { case .running: return "running outline"; case .bean: return "bean outline"; case .satin: return "satin outline" }
        }
        guard let fill = closedFill else { return outline!.prefix(1).uppercased() + outline!.dropFirst() }   // one of them is always on
        return outline.map { "\(fill.title) fill + \($0)" } ?? "\(fill.title) fill"
    }

    private enum CodingKeys: String, CodingKey { case openStitch, closedFill, closedOutline, basicShape, polygonSides, starPoints, starInner, cornerRadius }
    /// Older versions saved one choice for closed shapes: a fill style, or "outline" for a running outline.
    private enum OlderKeys: String, CodingKey { case closedStitch }
    /// Reads saved choices forgivingly: these live in the preferences file, and one unreadable value would otherwise
    /// make the whole file unreadable (losing shortcuts and panel layouts on the next save). A value that's missing,
    /// unknown (say, from a newer version) or out of range falls back to its default or is brought into range.
    public init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` turns a value that can't be read into nil, and `?? x` then uses x instead.
        openStitch = (try? saved.decode(OpenShapeStitch.self, forKey: .openStitch)) ?? openStitch
        if saved.contains(.closedFill) || saved.contains(.closedOutline) {
            // A missing key means that part is off. (Plain assignments in an initializer don't run didSet, so both
            // being off, or unreadable, is checked by hand below.)
            closedFill = try? saved.decode(FillStyle.self, forKey: .closedFill)
            closedOutline = try? saved.decode(OpenShapeStitch.self, forKey: .closedOutline)
            if closedFill == nil && closedOutline == nil { closedFill = .tatami }
        } else if let older = try? decoder.container(keyedBy: OlderKeys.self).decode(String.self, forKey: .closedStitch) {
            if older == "outline" { closedFill = nil; closedOutline = .running }
            else { closedFill = FillStyle(rawValue: older) ?? .tatami }
        }
        if let shape = try? saved.decode(BasicShape.self, forKey: .basicShape), BasicShape.basicChoices.contains(shape) { basicShape = shape }
        polygonSides = Self.clamp((try? saved.decode(Int.self, forKey: .polygonSides)) ?? polygonSides, to: Self.polygonSideRange)
        starPoints = Self.clamp((try? saved.decode(Int.self, forKey: .starPoints)) ?? starPoints, to: Self.starPointRange)
        starInner = Self.clamp((try? saved.decode(Double.self, forKey: .starInner)) ?? starInner, to: Self.starInnerRange)
        cornerRadius = Self.clamp((try? saved.decode(Double.self, forKey: .cornerRadius)) ?? cornerRadius, to: Self.cornerRadiusRange)
    }
    /// `value` moved into `range` (NaN becomes the low end).
    private static func clamp<Value: Comparable>(_ value: Value, to range: ClosedRange<Value>) -> Value {
        value > range.lowerBound ? min(value, range.upperBound) : range.lowerBound
    }
}

public enum ShapeGeometry {
    /// The kappa constant: handles this far along (as a share of the radius) make a Bézier curve that closely matches
    /// a quarter circle.
    static let kappa = 0.5522847498

    /// The box a drag from `start` to `end` covers. `even` makes it square (the longer side wins); `fromCenter` grows
    /// it out from `start` in every direction instead of from a corner.
    public static func box(from start: Point, to end: Point, even: Bool, fromCenter: Bool) -> (min: Point, max: Point) {
        var dx = end.x - start.x, dy = end.y - start.y
        if even { let side = max(abs(dx), abs(dy)); dx = dx < 0 ? -side : side; dy = dy < 0 ? -side : side }
        if fromCenter { return (Point(start.x - abs(dx), start.y - abs(dy)), Point(start.x + abs(dx), start.y + abs(dy))) }
        return (Point(min(start.x, start.x + dx), min(start.y, start.y + dy)), Point(max(start.x, start.x + dx), max(start.y, start.y + dy)))
    }

    /// The outline of `shape` filling `box` (in mm, y pointing up). With `keepProportions`, polygons, stars, hearts and
    /// arrows keep their natural proportions and sit centered in the box instead of stretching to fill it.
    public static func nodes(_ shape: BasicShape, in box: (min: Point, max: Point), settings: ShapeSettings = ShapeSettings(), keepProportions: Bool = false) -> [PathNode] {
        switch shape {
        case .rectangle: return rectangle(box, cornerRadius: settings.cornerRadius)
        case .ellipse: return ellipse(box)
        case .polygon, .star:
            // Corners around a circle, starting at the top; a star alternates outer and inner corners.
            let count = shape == .polygon ? settings.polygonSides : settings.starPoints * 2
            let unit = (0..<count).map { i -> PathNode in
                let angle = Double.pi / 2 + 2 * Double.pi * Double(i) / Double(count)
                let radius = shape == .star && i % 2 == 1 ? settings.starInner : 1
                return PathNode(Point(cos(angle) * radius, sin(angle) * radius))
            }
            return place(unit, in: box, keepProportions: keepProportions)
        case .heart: return place(heart, in: box, keepProportions: keepProportions)
        case .arrow:
            let corners = [(0, 0.3), (0.6, 0.3), (0.6, 0.05), (1, 0.5), (0.6, 0.95), (0.6, 0.7), (0, 0.7)]
            return place(corners.map { PathNode(Point($0.0, $0.1)) }, in: box, keepProportions: keepProportions)
        }
    }

    /// Four corners, or with `cornerRadius` two nodes per corner joined by a quarter-circle curve. The radius is
    /// limited so the straight sides never shrink to nothing.
    static func rectangle(_ box: (min: Point, max: Point), cornerRadius: Double) -> [PathNode] {
        let (x0, y0, x1, y1) = (box.min.x, box.min.y, box.max.x, box.max.y)
        let r = min(cornerRadius, min(x1 - x0, y1 - y0) / 2 - 0.05)
        guard r >= 0.05 else { return [Point(x0, y0), Point(x1, y0), Point(x1, y1), Point(x0, y1)].map { PathNode($0) } }
        let k = kappa * r
        // Counterclockwise from the bottom left. Each corner is a pair of corner nodes whose handles only point into
        // the curve, so the sides between them stay straight.
        return [
            PathNode(Point(x0 + r, y0), inHandle: Point(x0 + r - k, y0)), PathNode(Point(x1 - r, y0), outHandle: Point(x1 - r + k, y0)),
            PathNode(Point(x1, y0 + r), inHandle: Point(x1, y0 + r - k)), PathNode(Point(x1, y1 - r), outHandle: Point(x1, y1 - r + k)),
            PathNode(Point(x1 - r, y1), inHandle: Point(x1 - r + k, y1)), PathNode(Point(x0 + r, y1), outHandle: Point(x0 + r - k, y1)),
            PathNode(Point(x0, y1 - r), inHandle: Point(x0, y1 - r + k)), PathNode(Point(x0, y0 + r), outHandle: Point(x0, y0 + r - k))
        ]
    }

    /// Four smooth nodes (right, top, left, bottom) whose handles make the curve between them a quarter ellipse.
    static func ellipse(_ box: (min: Point, max: Point)) -> [PathNode] {
        let center = Point((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2)
        let rx = (box.max.x - box.min.x) / 2, ry = (box.max.y - box.min.y) / 2, kx = kappa * rx, ky = kappa * ry
        let (cx, cy) = (center.x, center.y)
        return [
            PathNode(Point(cx + rx, cy), smooth: true, inHandle: Point(cx + rx, cy - ky), outHandle: Point(cx + rx, cy + ky)),
            PathNode(Point(cx, cy + ry), smooth: true, inHandle: Point(cx + kx, cy + ry), outHandle: Point(cx - kx, cy + ry)),
            PathNode(Point(cx - rx, cy), smooth: true, inHandle: Point(cx - rx, cy + ky), outHandle: Point(cx - rx, cy - ky)),
            PathNode(Point(cx, cy - ry), smooth: true, inHandle: Point(cx - kx, cy - ry), outHandle: Point(cx + kx, cy - ry))
        ]
    }

    /// A heart in a 1 × 1 square (y up): two round lobes meeting in a dip at the top, and a point at the bottom.
    /// Each lobe's top quarter is a circle of radius 0.25, so its handles are kappa × 0.25 ≈ 0.138 long.
    static let heart: [PathNode] = {
        let k = kappa * 0.25
        return [
            PathNode(Point(0.5, 0.73), inHandle: Point(0.5, 0.73 + k), outHandle: Point(0.5, 0.73 + k)),     // the dip
            PathNode(Point(0.25, 0.98), smooth: true, inHandle: Point(0.25 + k, 0.98), outHandle: Point(0.25 - k, 0.98)),
            PathNode(Point(0, 0.73), smooth: true, inHandle: Point(0, 0.73 + k), outHandle: Point(0, 0.55)),
            PathNode(Point(0.5, 0), inHandle: Point(0.22, 0.28), outHandle: Point(0.78, 0.28)),               // the point
            PathNode(Point(1, 0.73), smooth: true, inHandle: Point(1, 0.55), outHandle: Point(1, 0.73 + k)),
            PathNode(Point(0.75, 0.98), smooth: true, inHandle: Point(0.75 + k, 0.98), outHandle: Point(0.75 - k, 0.98))
        ]
    }()

    /// Moves and scales `unit` (a shape in any small coordinates) so its corner points fill `box`, or, with
    /// `keepProportions`, fit inside it centered without stretching.
    static func place(_ unit: [PathNode], in box: (min: Point, max: Point), keepProportions: Bool) -> [PathNode] {
        let xs = unit.map(\.point.x), ys = unit.map(\.point.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX, maxY > minY else { return unit }
        let width = box.max.x - box.min.x, height = box.max.y - box.min.y
        var sx = width / (maxX - minX), sy = height / (maxY - minY)
        if keepProportions { sx = min(sx, sy); sy = sx }
        // Centered: any space left over (when keeping proportions) is split evenly on both sides.
        let ox = box.min.x + (width - (maxX - minX) * sx) / 2, oy = box.min.y + (height - (maxY - minY) * sy) / 2
        return unit.map { node in var placed = node; placed.transform { Point(ox + ($0.x - minX) * sx, oy + ($0.y - minY) * sy) }; return placed }
    }
}

public enum ShapeStitching {
    /// A new line from the Open Shape tool with `stitch` on it. A satin line is `satinWidth` mm wide, centered on the
    /// line; throws, with a reason, if the line can't take a satin that wide.
    public static func openShape(_ nodes: [PathNode], stitch: OpenShapeStitch, satinWidth: Double, name: String, color: ThreadColor) throws -> RunObject {
        var line = RunObject(name: name, nodes: nodes, color: color)
        switch stitch {
        case .running: return line
        case .bean: line.digitizing = DigitizingSettings(kind: .run); line.digitizing?.runPasses = 3; return line
        case .satin: return try SatinLine.column(from: line, width: satinWidth)
        }
    }

    /// A new closed shape with `fill` and `outline` on it (either may be nil, not both): one object, or a fill and
    /// then an outline sewn on top of its edge, grouped so they move together. A satin outline is `satinWidth` mm
    /// wide, centered on the edge; throws, with a reason, if the shape can't take a satin that wide.
    public static func closedShape(_ nodes: [PathNode], fill: FillStyle?, outline: OpenShapeStitch?, satinWidth: Double = SatinLine.defaultWidth,
                                   name: String, color: ThreadColor) throws -> [RunObject] {
        var made: [RunObject] = []
        if let fill {
            var shape = RunObject(name: name, nodes: nodes, color: color); shape.closed = true
            shape.digitizing = DigitizingSettings(kind: .fill); shape.stitchLength = 3
            if fill != .tatami { shape.digitizing?.fillStyle = fill }   // nil already means tatami
            made.append(shape)
        }
        if let outline {
            var edge = RunObject(name: fill == nil ? name : "\(name) outline", nodes: nodes, color: color); edge.closed = true
            switch outline {
            case .running: break
            case .bean: edge.digitizing = DigitizingSettings(kind: .run); edge.digitizing?.runPasses = 3
            case .satin: edge = try SatinLine.column(from: edge, width: satinWidth)
            }
            made.append(edge)
        }
        if made.count > 1 { let group = UUID(); for index in made.indices { made[index].groupID = group } }
        return made
    }
}

/// The Freehand Open Shape and Freehand Closed Shape tools: a stroke that followed the pointer, turned into a few
/// smooth nodes so it can be reshaped like any other outline.
public enum FreehandStroke {
    /// How far (mm) the smoothed line may stray from the stroke. Larger means fewer nodes and a softer line.
    public static let tolerance = 0.3
    /// The stroke's points (mm, in the order drawn) as smooth nodes, with every node dropped whose loss keeps the
    /// curve within `tolerance` mm of the stroke. A closed stroke that came back near its start loses that tail,
    /// since a closed shape joins its last node to its first by itself. Too short a stroke gives back what it has.
    public static func nodes(_ points: [Point], closed: Bool, tolerance: Double = tolerance) -> [PathNode] {
        // Thin the stroke first: the pointer reports points a fraction of a millimeter apart, and the node reducer
        // compares every candidate against the curve, so it's much quicker on a line already down to its bends.
        var thinned: [Point] = []
        for p in points where thinned.last.map({ $0.distance(to: p) > 0.05 }) ?? true { thinned.append(p) }
        if closed { while thinned.count > 3, let last = thinned.last, last.distance(to: thinned[0]) <= tolerance * 3 { thinned.removeLast() } }
        let line = SatinLine.simplified(thinned, tolerance: tolerance / 3)
        return Design.reduced([line.map { PathNode($0, smooth: true) }], closed: closed, tolerance: tolerance)[0]
    }
}
