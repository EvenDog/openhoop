// Editable design data uses millimeters, with the origin at the hoop center and Y pointing up.
// Geometry is saved independently of the generated needle movements.
import Foundation

public struct Point: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static func + (a: Self, b: Self) -> Self { .init(a.x + b.x, a.y + b.y) }
    public static func - (a: Self, b: Self) -> Self { .init(a.x - b.x, a.y - b.y) }
    public static func * (a: Self, b: Double) -> Self { .init(a.x * b, a.y * b) }
    public func distance(to p: Self) -> Double { hypot(x - p.x, y - p.y) }
    public var finite: Bool { x.isFinite && y.isFinite }
}

public struct PathNode: Codable, Hashable, Sendable {
    public var point: Point
    public var smooth: Bool
    /// Optional Bézier handles, as absolute positions in millimeters. `inHandle` shapes the curve arriving at
    /// this node and `outHandle` the curve leaving it. When nil, a smooth node uses the automatic curve shape.
    /// Nil handles are left out of saved files, so projects without handles keep their old format.
    public var inHandle: Point?
    public var outHandle: Point?
    public init(_ point: Point, smooth: Bool = false, inHandle: Point? = nil, outHandle: Point? = nil) {
        self.point = point; self.smooth = smooth; self.inHandle = inHandle; self.outHandle = outHandle
    }
    public var hasHandles: Bool { inHandle != nil || outHandle != nil }
    /// The same node walked in the opposite direction (as when a satin rail is reversed): its handles swap roles.
    public var reversedDirection: PathNode { PathNode(point, smooth: smooth, inHandle: outHandle, outHandle: inHandle) }
    /// Moves the node and its handles together, so mirroring or rotating keeps the curve's shape.
    public mutating func transform(_ body: (Point) -> Point) {
        point = body(point); inHandle = inHandle.map(body); outHandle = outHandle.map(body)
    }
    /// Pen-style drawing: dragging away from a new node toward `p` makes it smooth, with its outgoing handle at
    /// `p` and its incoming handle mirrored on the other side, so the curve flows through the node.
    public mutating func pullHandles(toward p: Point) {
        smooth = true; outHandle = p; inHandle = point + (point - p)
    }
    /// Switches between corner and smooth. Corners have no handles, so switching to corner removes them.
    public mutating func toggleSmooth() {
        smooth.toggle()
        if !smooth { inHandle = nil; outHandle = nil }
    }
}

public struct ThreadColor: Codable, Hashable, Sendable {
    public var name: String
    public var hex: Int
    /// The thread maker and its color number, when the thread was matched to a thread chart (ThreadCharts.swift).
    /// Both are optional, so projects saved before thread charts existed open unchanged.
    public var brand: String?
    public var code: String?
    public init(_ name: String, _ hex: Int, brand: String? = nil, code: String? = nil) {
        self.name = name; self.hex = hex; self.brand = brand; self.code = code
    }
    /// "Madeira Polyneon 1610" for a chart thread, or nil for a plain color.
    public var chartLabel: String? {
        let parts = [brand, code].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    public static let palette: [Self] = [
        .init("Ocean", 0x167C80), .init("Coral", 0xDC6552), .init("Ink", 0x293742),
        .init("Gold", 0xCCA550), .init("Fern", 0x72966B), .init("Violet", 0x8774B3),
        .init("Rose", 0xCA839C), .init("Ivory", 0xE8DDCB)
    ]
}

public struct RunObject: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var nodes: [PathNode]
    public var color: ThreadColor
    public var stitchLength = 2.5
    public var closed = false
    public var visible = true
    public var locked = false
    public var tieIn = true
    public var tieOut = true
    public var trimAfter = true
    /// With trimAfter on: true cuts the thread however close the next object starts; nil (older files too) cuts it
    /// only when the next object starts at least the design's trim distance away. `trimRule` reads both as one choice.
    public var trimAlways: Bool?
    public var stopAfter = false
    // Optional additions allow v0.1 running projects to decode without rewriting them.
    public var digitizing: DigitizingSettings?
    public var holes: [[PathNode]]?
    public var rawStitches: RawStitchBlock?
    /// Optional points (mm) where this object should start and end sewing. The stitch engine picks the
    /// sewing direction, starting node or fill corner that best matches them; nil keeps the default order.
    public var entry: Point?
    public var exit: Point?
    /// Objects sharing a group ID are selected and moved together. Grouping never changes the stitches.
    public var groupID: UUID?
    /// For letters made by the lettering tool: the recipe to rebuild them when the text is edited.
    public var lettering: LetteringSpec?
    /// For letters made by the lettering tool: which letter this part belongs to, as line × 1000 + the letter's place
    /// in its line (the key `LetteringSpec.letterOffsets` uses). Edit Nodes moves a letter's parts together by it.
    public var letterKey: Int?
    /// Objects sharing a branch ID were branched (Branching.swift): one after another in the same thread, they're
    /// joined by travel runs instead of trims.
    public var branchID: UUID?
    /// Stitches edited by hand with Edit Stitch (StitchEdits.swift), or nil.
    public var stitchEdits: StitchEdits?
    /// For the parts of a monogram (Monogram.swift): the recipe to rebuild it.
    public var monogram: MonogramSpec?
    /// Set on an unstitched line that guides a fill: the fill's id. A guided fill's rows follow it (GuidedFill.swift).
    public var guideFor: UUID?
    public var kind: StitchKind { rawStitches != nil ? .raw : digitizing?.kind ?? .run }
    public var settings: DigitizingSettings { digitizing ?? DigitizingSettings(kind: .run) }
    /// What the stitches are called in lists: the stitch kind, naming the fill style for fills (such as "Contour Fill").
    public var stitchTitle: String {
        if kind == .run, let style = settings.runStyle, style != .running { return style.title }
        if kind == .run && (settings.runPasses ?? 1) > 1 { return "Bean" }
        return kind == .fill && (settings.fillStyle ?? .tatami) != .tatami ? "\(settings.fillStyle!.title) Fill" : kind.title
    }
    public var allNodes: [PathNode] { if let raw=rawStitches{return [PathNode(raw.start)]+raw.commands.map{PathNode($0.point)}};return nodes + (holes ?? []).flatMap { $0 } }
    public mutating func transform(_ body: (Point) -> Point) {
        if rawStitches != nil {rawStitches!.start=body(rawStitches!.start);for i in rawStitches!.commands.indices{rawStitches!.commands[i].point=body(rawStitches!.commands[i].point)}}
        for i in nodes.indices { nodes[i].transform(body) }
        if holes != nil { for r in holes!.indices { for i in holes![r].indices { holes![r][i].transform(body) } } }
        entry = entry.map(body); exit = exit.map(body)
        lettering?.transform(body); monogram?.transform(body)
        if let center = digitizing?.radialCenter { digitizing?.radialCenter = body(center) }
        if let lines = digitizing?.angleLines { digitizing?.angleLines = lines.map { $0.map(body) } }
        if let guide = digitizing?.guideLine { digitizing?.guideLine = guide.map(body) }
        if let center = digitizing?.angleLineCenter { digitizing?.angleLineCenter = body(center) }
        // Edited stitches move with the object, and still count as made from it.
        if stitchEdits != nil { for s in stitchEdits!.sections.indices { stitchEdits!.sections[s].points = stitchEdits!.sections[s].points.map(body) } }
        refreshStitchEdits()
    }
    /// A copy whose nodes are ordered to begin at the chosen start point (running and satin only).
    /// Open running paths and satin columns sew from whichever end is nearer `entry`; closed running
    /// outlines start at the point on the outline nearest it. With only an end point, the object is ordered to
    /// finish there instead: an open one starts at its other end, a closed one starts (and so ends) nearest it.
    /// Without either point the object is returned unchanged.
    public func sewingOrder() -> RunObject {
        guard let target = entry ?? exit, rawStitches == nil, nodes.count >= 2 else { return self }
        let finishAtTarget = entry == nil   // only an end point is set
        var copy = self
        switch kind {
        case .run, .vector:
            if closed {
                // Find the point on the outline nearest the start marker, split the curve there (the shape is
                // unchanged), and begin sewing from that new node.
                var ring = RunningEngine.withExplicitHandles(nodes, closed: true)
                var best = (segment: 0, t: 0.0, distance: Double.infinity)
                for i in ring.indices {
                    let (a, b, c, d) = RunningEngine.controls(ring, closed: true, segment: i)
                    for step in 0...64 {
                        let t = Double(step) / 64, distance = RunningEngine.bezierPoint(a, b, c, d, t).distance(to: target)
                        if distance < best.distance { best = (i, t, distance) }
                    }
                }
                var start = best.t >= 0.999 ? (best.segment + 1) % ring.count : best.segment
                if best.t > 0.001 && best.t < 0.999 {
                    let (a, b, c, d) = RunningEngine.controls(ring, closed: true, segment: best.segment)
                    let (left, right) = RunningEngine.split(a, b, c, d, at: best.t)
                    ring[best.segment].outHandle = left.1
                    ring[(best.segment + 1) % ring.count].inHandle = right.2
                    ring.insert(PathNode(left.3, smooth: true, inHandle: left.2, outHandle: right.1), at: best.segment + 1)
                    start = best.segment + 1
                }
                copy.nodes = Array(ring[start...] + ring[..<start])
            } else if (nodes.last!.point.distance(to: target) < nodes.first!.point.distance(to: target)) != finishAtTarget {
                copy.nodes = nodes.reversed().map(\.reversedDirection)
            }
        case .satin:
            // Compare the column's two ends by the middle of their first and last edge pairs.
            guard nodes.count >= 4 else { return self }
            if closed {
                // A closed column (such as a border) starts at whichever edge pair is nearest the start marker.
                let nearest = stride(from: 0, to: nodes.count - 1, by: 2).min { ((nodes[$0].point + nodes[$0 + 1].point) * 0.5).distance(to: target) < ((nodes[$1].point + nodes[$1 + 1].point) * 0.5).distance(to: target) }!
                copy.nodes = Array(nodes[nearest...] + nodes[..<nearest])
                return copy
            }
            let first = (nodes[0].point + nodes[1].point) * 0.5, last = (nodes[nodes.count - 2].point + nodes[nodes.count - 1].point) * 0.5
            if (last.distance(to: target) < first.distance(to: target)) != finishAtTarget {
                // Reverse the order of the edge pairs, keeping each pair's left/right order.
                copy.nodes = stride(from: nodes.count - 2, through: 0, by: -2).flatMap { [nodes[$0].reversedDirection, nodes[$0 + 1].reversedDirection] }
            }
        case .fill, .raw: break   // fills choose their corner inside AreaEngine.fill
        }
        return copy
    }
    /// Where an open line or satin column really finishes sewing, once its start and end points have chosen which
    /// way it runs: the line's last node, or the middle of the column's last edge pair. Its End marker shows here,
    /// since it can only finish at an end. Nil for anything else.
    public var sewnEnd: Point? {
        guard !closed, rawStitches == nil else { return nil }
        let ordered = sewingOrder().nodes
        switch kind {
        case .run where ordered.count >= 2:
            // An end point on the line part way along: the line comes back to finish there, so the marker stays put.
            if let exit, let line = try? RunningEngine.stitches(for: sewingOrder()), RunningEngine.tail(along: line, to: exit, closed: false) != nil { return nil }
            return ordered.last!.point
        case .satin where ordered.count >= 4:
            // Part way along, the column is sewn in two halves that finish there, so the marker stays put.
            if satinEndsPartWay { return nil }
            return (ordered[ordered.count - 2].point + ordered[ordered.count - 1].point) * 0.5
        default: return nil
        }
    }
    /// True when an open satin's end point is more than 1 mm from both ends of the column, measured along its middle:
    /// the column is then sewn in two halves that meet there (see `AreaEngine.satin`).
    public var satinEndsPartWay: Bool {
        guard kind == .satin, !closed, let exit, nodes.count >= 4, nodes.count % 2 == 0 else { return false }
        let middle = stride(from: 0, to: nodes.count, by: 2).map { (nodes[$0].point + nodes[$0 + 1].point) * 0.5 }
        let place = AreaGeometry.alongPath(exit, middle)
        return place.along > 1 && place.total - place.along > 1
    }
    public func runningOutlines()->[RunObject] {
        guard rawStitches==nil else{return [self]}
        var outer=self
        if kind == .satin {outer.nodes=nodes.enumerated().filter{$0.offset%2==0}.map(\.element)+nodes.enumerated().filter{$0.offset%2==1}.map(\.element).reversed().map(\.reversedDirection);outer.closed=true}
        outer.digitizing=nil;outer.holes=nil
        var result=[outer]
        // A closed satin (a border) is a ring: its two rails become two separate loops.
        if kind == .satin && closed {
            outer.nodes=nodes.enumerated().filter{$0.offset%2==0}.map(\.element)
            var inner=outer;inner.id=UUID();inner.name=name+" inner";inner.nodes=nodes.enumerated().filter{$0.offset%2==1}.map(\.element)
            result=[outer,inner]
        }
        for (i,hole) in (holes ?? []).enumerated() {var path=outer;path.id=UUID();path.name=name+" hole \(i+1)";path.nodes=hole;path.closed=true;result.append(path)}
        return result
    }
    public var outlinePaths: [[Point]] {
        switch kind {
        case .raw:
            guard let raw=rawStitches else{return []}
            var paths:[[Point]]=[],path=[raw.start]
            for command in raw.commands {
                if command.op == .stitch {path.append(command.point)}
                else if command.op == .jump {if path.count>1{paths.append(path)};path=[command.point]}
            }
            if path.count>1{paths.append(path)};return paths
        case .run, .vector: return ([nodes]+(holes ?? [])).map{RunningEngine.flatten($0,closed:closed).flatMap{$0}}
        case .fill: return ([nodes]+(holes ?? [])).map{AreaGeometry.ring($0)}.map{$0 + Array($0.prefix(1))}
        case .satin:
            let left=nodes.enumerated().filter{$0.offset%2==0}.map(\.element),right=nodes.enumerated().filter{$0.offset%2==1}.map(\.element)
            return [RunningEngine.flatten(left,closed:closed).flatMap{$0},RunningEngine.flatten(right,closed:closed).flatMap{$0}] + stride(from:0,to:nodes.count-1,by:2).map{[nodes[$0].point,nodes[$0+1].point]}
        }
    }
    public init(name: String, nodes: [PathNode], color: ThreadColor = .palette[0]) {
        self.name = name; self.nodes = nodes; self.color = color
    }
}

public enum StitchKind: String, Codable, CaseIterable, Sendable { case run, satin, fill, vector, raw
    public var title:String {self == .raw ? "Imported stitches" : self == .vector ? "Vector · unstitched" : self == .run ? "Running" : self == .satin ? "Satin" : "Tatami Fill"}
}
public enum UnderlayStyle: String, Codable, CaseIterable, Sendable {case none, center, edge, zigzag, edgeAndSparse
    /// Satins only: picked from the column's width each time it sews (`DigitizingSettings.autoUnderlay`).
    case auto
    public var title:String {switch self {case .none:return "None";case .center:return "Center run";case .edge:return "Inset edge run";case .zigzag:return "Inset zigzag";case .edgeAndSparse:return "Edge + sparse fill";case .auto:return "Auto (by width)"}}
}
/// How a fill lays down its thread: straight rows (tatami), rings that follow the outline inward (contour), rays
/// fanning out from a center (radial), rows that ripple (wave), one wandering line that never crosses itself (stipple),
/// a small pattern tiled across the shape (motif), a grid of X's (cross stitch), rows that open up across the shape
/// (gradient), or satin stitches straight across it from edge to edge (satin).
public enum FillStyle: String, Codable, CaseIterable, Sendable {
    case tatami, contour, radial, wave, stipple, motif, crossStitch, gradient, guided, satin
    /// False for cross stitch, whose stitches are its squares' diagonals, set by the square size alone, and satin,
    /// whose stitches reach from edge to edge.
    public var usesStitchLength: Bool { self != .crossStitch && self != .satin }
    /// The styles a newly drawn shape can start with: all but Guided, which needs a guide line drawn afterwards.
    public static let forNewShapes = allCases.filter { $0 != .guided }
    public var title: String {
        switch self { case .tatami: return "Tatami"; case .contour: return "Contour"; case .radial: return "Radial"; case .wave: return "Wave"; case .stipple: return "Stipple"; case .motif: return "Motif"; case .crossStitch: return "Cross stitch"; case .gradient: return "Gradient"; case .guided: return "Guided"; case .satin: return "Satin" }
    }
    public var summary: String {
        switch self {
        case .tatami: return "Straight rows across the shape: the classic, flattest fill."
        case .contour: return "Rings that follow the outline inward, like ripples. Good for organic shapes and letters."
        case .radial: return "Stitches fan out from a center point, like sun rays. Good for flowers, suns and round badges."
        case .wave: return "Rows that ripple in a gentle wave instead of running straight."
        case .stipple: return "One wandering line that loops through the whole shape and never crosses itself: the quilting look, or a light background texture."
        case .motif: return "A small pattern (hearts, leaves, stars…) repeated in rows across the shape: a decorative, open fill."
        case .crossStitch: return "Little X's on a square grid, like hand cross-stitch. Only whole squares inside the shape get one, so the edge steps like a real cross-stitch."
        case .gradient: return "Tatami rows that start close together and open up across the shape, from solid to sheer: for shading, or for blending one thread color into another."
        case .guided: return "Rows that bend to follow a guide line drawn over the shape, evenly spaced: for hair, feathers, petals and anything that flows."
        case .satin: return "Smooth, shiny satin stitches straight across the shape from edge to edge, at the fill angle: for leaves, petals and small shapes. Wide parts are split so no stitch is too long."
        }
    }
}
/// How a running line is sewn: plain running stitch, or one of the decorative line stitches built along it
/// (RunningStyles.swift).
public enum RunStyle: String, Codable, CaseIterable, Sendable {
    case running, zigzag, blanket, backStitch, stemStitch, motif, ripple
    public var title: String {
        switch self { case .running: return "Running"; case .zigzag: return "Zigzag"; case .blanket: return "Blanket"; case .backStitch: return "Back stitch"; case .stemStitch: return "Stem stitch"; case .motif: return "Motif"; case .ripple: return "Ripple" }
    }
    public var summary: String {
        switch self {
        case .running: return "Plain running stitch along the line."
        case .zigzag: return "The needle swings from side to side along the line: a decorative edge, or a light tack-down."
        case .blanket: return "A running line with short prongs at regular spacing, like hand blanket stitch: the classic appliqué edge. On a closed shape the prongs point inward."
        case .backStitch: return "Each stitch goes forward two lengths and back one, for a solid line that looks hand-sewn."
        case .stemStitch: return "Like back stitch, but each stitch slants across the line, for a twisted rope look."
        case .motif: return "A small pattern (hearts, leaves, stars…) repeated along the line, joined by short runs."
        case .ripple: return "The line sewn again and again, each copy smaller and closer to a target point, like ripples on water: a closed shape spirals in, an open line fans out back and forth. Drag the Target dot to move where they shrink to."
        }
    }
    /// True for styles with a width across the line (and, for zigzag, blanket and motif, a spacing along it). For a
    /// motif they're its size and the gap between motifs.
    public var hasWidth: Bool { self == .zigzag || self == .blanket || self == .stemStitch || self == .motif }
    public var hasSpacing: Bool { self == .zigzag || self == .blanket || self == .motif }
    /// False for zigzag, whose stitches are set by its width and spacing alone (each one swings from one side to the
    /// other), so Properties doesn't offer a stitch length that would change nothing.
    public var usesStitchLength: Bool { self != .zigzag }
}
/// The small patterns motif runs and motif fills repeat (Motifs.swift draws them).
public enum Motif: String, Codable, CaseIterable, Sendable {
    case heart, leaf, diamond, star, scallop, circle
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
public struct DigitizingSettings: Codable, Hashable, Sendable {
    public var kind:StitchKind
    public var spacing=0.4
    public var expansion=0.2
    public var angle=45.0
    public var maximumSatin=10.0
    public var underlay:UnderlayStyle {
        // A second underlay needs a first one, of a different style (the same style twice would just sew it again).
        // Auto picks its own second underlay.
        didSet {if underlay == .none || underlay == .auto || underlay == secondUnderlay {secondUnderlay=nil}}
    }
    public var inset=0.4
    public var underlaySpacing=1.2
    /// Satin only: a second underlay layer, sewn after the first and before the top stitches (a second
    /// underlay, e.g. a center run then a zigzag). It uses the same inset and spacing as the first. nil (the default,
    /// and in older files) means none.
    public var secondUnderlay:UnderlayStyle?
    /// Satin only: extra pull compensation for each stitch, as a percentage of its width, on each side (on top of
    /// `expansion`), so wide parts of a column get more. nil (older files, fonts, tack-downs) means none.
    public var pullPercent:Double?
    /// 3% is a starting value, to be tuned after test sew-outs (5% made 6 mm satins sew 7 mm stitches, long enough to snag).
    public static let defaultPullPercent=3.0, pullPercentRange=0.0...20.0
    /// Satin only: true when the design's fabric stretches (knit, towel), so Auto underlay gives more support.
    /// Set by the fabric type; nil means a stable fabric.
    public var stretchyFabric:Bool?
    /// What Auto underlay sews for a satin whose average width is `width` mm: a center run under 2 mm, an inset edge
    /// run up to 4 mm, an edge run then a zigzag above that (common digitizing advice: center run for narrow
    /// columns, zigzag for wide ones). On stretchy fabric, columns from 2 mm get the edge run and zigzag. The 2 and
    /// 4 mm steps are starting values, to be tuned after test sew-outs.
    public static func autoUnderlay(width:Double,stretchy:Bool)->(first:UnderlayStyle,second:UnderlayStyle?) {
        if width<2 {return (.center,nil)}
        if width<4 && !stretchy {return (.edge,nil)}
        return (.edge,.zigzag)
    }
    /// True when the underlay spacing changes something: a fill's sparse rows (Edge + sparse), or a satin's center
    /// run or zigzag (as first or second underlay, or picked by Auto). An edge run alone has no rows to space.
    public func usesUnderlaySpacing(_ kind: StitchKind) -> Bool {
        if kind == .fill { return underlay == .edgeAndSparse }
        return [underlay, secondUnderlay ?? UnderlayStyle.none].contains { [.center, .zigzag, .auto].contains($0) }
    }
    /// True when an underlay layer runs inside the edge, so the underlay inset applies (a center run ignores it).
    public var usesUnderlayInset:Bool {[underlay,secondUnderlay ?? UnderlayStyle.none].contains{$0 != .none && $0 != .center}}
    /// True for satins converted from embroidery fonts: the satin engine skips the checks meant for hand-drawn
    /// columns (crossing or reversing rungs, rungs leaving the column, touching edges), because font designers
    /// deliberately fan and overlap stitches. nil (the default, and in older files) means the full checks.
    public var relaxedChecks:Bool?
    /// Fills only: how the rows are laid. nil (the default, and in older files) means straight tatami rows.
    public var fillStyle:FillStyle?
    /// Wave fills: the ripple's height (from crest to trough) and length, in mm. nil uses the defaults below.
    public var waveHeight:Double?
    public var waveLength:Double?
    public static let defaultWaveHeight=2.0, defaultWaveLength=12.0
    /// The wave sizes Properties offers and project files may hold, in mm.
    public static let waveHeightRange=0.5...10.0, waveLengthRange=3.0...50.0
    /// Radial fills: the point the stitches fan out from, in mm; ripple lines: the point the copies shrink toward.
    /// nil uses the middle of the shape (RunningStyles.rippleTarget for a ripple).
    public var radialCenter:Point?
    /// Ripple lines: how many times the line is sewn, each copy smaller. nil uses the default.
    public var rippleLines:Int?
    public static let defaultRippleLines=10, rippleLineRange=2...50
    /// Tatami fills: stitch angle lines (each two points, in mm) across the shape. Where there are any, the stitches
    /// run along them and turn gradually from one to the next (TurningFill.swift) instead of all at `angle`.
    public var angleLines:[[Point]]?
    /// Tatami and wave fills: where Edit Nodes draws the line showing `angle` (StitchAngleLine.swift), in mm; nil
    /// is the middle of the shape. Only where the line is drawn: it never changes the stitches.
    public var angleLineCenter:Point?
    /// Running stitch only: how many times each stitch is sewn, back and forth (3 or 5 is "bean stitch", a bold
    /// line). nil (the default, and in older files) means once.
    public var runPasses:Int?
    public static let runPassChoices=[1,3,5]
    /// Running lines only: the line stitch (nil, the default and in older files, means plain running stitch), and its
    /// width across the line and spacing along it in mm (nil uses the style's defaults below).
    public var runStyle:RunStyle?
    public var runWidth:Double?
    public var runSpacing:Double?
    /// Each line style's starting width and spacing (mm), and the sizes Properties offers and project files may hold.
    public static func defaultRunWidth(_ style:RunStyle)->Double {style == .blanket ? 2.5 : style == .stemStitch ? 1 : style == .motif ? 4 : 2}
    public static func defaultRunSpacing(_ style:RunStyle)->Double {style == .blanket ? 3 : style == .motif ? 1 : 1.5}
    /// Motif runs and motif fills: which pattern (nil means hearts).
    public var motif:Motif?
    /// Motif and cross stitch fills: the size of each motif or cross-stitch square, and (motif fills) the gap
    /// between motifs, in mm. nil uses the defaults below.
    public var patternSize:Double?
    public var patternGap:Double?
    public static func defaultPatternSize(_ style:FillStyle)->Double {style == .crossStitch ? 3 : 5}
    public static let defaultPatternGap=1.5, patternSizeRange=1.5...20.0, patternGapRange=0.0...10.0
    /// Gradient fills: the row spacing where the rows start (the densest end) and where they finish, in mm.
    public var gradientStart:Double?
    public var gradientEnd:Double?
    public static let defaultGradientStart=0.4, defaultGradientEnd=2.5, gradientSpacingRange=0.2...6.0
    /// Satin only: padding sewn lengthwise inside the column before the satin, so it stands up off the fabric.
    /// nil (the default, and in older files) means flat.
    public var raised:Bool?
    public static let runWidthRange=0.3...10.0, runSpacingRange=0.5...10.0
    /// Stipple fills: how far apart the wandering line's neighbouring passes are, in mm (nil uses the default). It's
    /// separate from the row spacing, which fabric types set for dense fills.
    public var stippleSpacing:Double?
    public static let defaultStippleSpacing=4.0, stippleSpacingRange=1.0...10.0
    /// Satin only: on the inside of a curve, where stitches crowd together, every other stitch stops short of the
    /// inner edge. nil (older files) means off, so existing designs sew as they did; new satins start with it on.
    public var shortStitches:Bool?
    /// Satin only: stitches longer than the maximum stitch are split into shorter ones, staggered like bricks,
    /// instead of the column being refused. nil (older files) means off; new satins start with it on.
    public var autoSplit:Bool?
    /// Satin fills: the longest stitch before it's split (with Auto split, which for fills is on unless set false).
    /// nil means `defaultSatinSplit`. Satin columns use `maximumSatin` instead.
    public var satinSplit:Double?
    /// True when `spacing` for tatami, wave and guided fills is measured across two rows (from a row to the next one
    /// sewn the same way, as embroidery software usually measures it), so the rows lie half of it apart. nil (older
    /// files) measures it from one row to the next; opening such a file converts it (Design.measureSpacingAcrossTwoRows).
    public var spacingAcrossTwoRows:Bool?
    public static let defaultSatinSplit=7.0
    public static let satinSplitRange=3.0...10.0
    /// Fills only: leave out the area that shapes sewn after this one cover (OverlapCutout.swift). nil (the default)
    /// means off: the whole fill sews.
    public var cutOutOverlaps:Bool?
    /// Guided fills: the path of the guide line the rows follow, in mm. It's copied from the fill's guide line (an
    /// unstitched line whose `guideFor` is this fill) after every edit (Design.syncGuides), and kept if that line is
    /// deleted, so the fill still sews the same way.
    public var guideLine:[Point]?
    public init(kind:StitchKind) {
        self.kind=kind;spacingAcrossTwoRows=true;underlay=kind == .vector ? .none : kind == .fill ? .edgeAndSparse : kind == .satin ? .auto : .center
        if kind == .satin {shortStitches=true;autoSplit=true;pullPercent=Self.defaultPullPercent}
    }
}

public struct Hoop: Codable, Hashable, Sendable {
    public var width = 100.0
    public var height = 100.0
    public var oval = false
    /// The hoop preset this size came from (a `HoopPreset.id`, like "Brother 5 × 7 in"); nil for a custom size.
    /// Optional so projects saved before hoop presets open unchanged.
    public var name: String?
    public init() {}
    public init(width: Double, height: Double, oval: Bool = false, name: String? = nil) {
        self.width = width; self.height = height; self.oval = oval; self.name = name
    }
    public func contains(_ p: Point, tolerance: Double = 0) -> Bool {
        guard width > 0, height > 0, p.finite else { return false }
        if oval { return pow(p.x / (width / 2 + tolerance), 2) + pow(p.y / (height / 2 + tolerance), 2) <= 1.0000001 }
        return abs(p.x) <= width / 2 + tolerance && abs(p.y) <= height / 2 + tolerance
    }
}

public struct Artwork: Codable, Equatable, Sendable {
    public var data: Data
    public var name: String
    public var center = Point(0, 0)
    public var width: Double
    public var height: Double
    public var opacity = 0.4
    public var visible = true
    /// Where the picture sits in the sewing order (ArtworkLayer.swift): how many objects, from the first sewn, are
    /// drawn under it. Nil (older files) is 0: under everything. It's only how the canvas draws; nothing is sewn.
    public var layer: Int?
    public init(data: Data, name: String, width: Double, height: Double) {
        self.data = data; self.name = name; self.width = width; self.height = height
    }
    /// The image's corners in millimeters, in order: bottom-left, bottom-right, top-right, top-left.
    public var corners: [Point] {
        let w = width / 2, h = height / 2
        return [Point(center.x - w, center.y - h), Point(center.x + w, center.y - h), Point(center.x + w, center.y + h), Point(center.x - w, center.y + h)]
    }
    /// The image after a drag from `start` to `point` (millimeters): corner -1 moves it; corner 0…3 resizes it from
    /// that corner while the opposite corner stays still. Resizing keeps the proportions, following whichever
    /// direction grew more, unless `free` (Shift) lets it stretch. It never gets smaller than 2 mm.
    public func adjusted(corner: Int, from start: Point, to point: Point, free: Bool) -> Artwork {
        var result = self
        guard corner >= 0 else { result.center = center + (point - start); return result }
        let anchor = corners[(corner + 2) % 4], dragged = corners[corner]
        let signX: Double = dragged.x > anchor.x ? 1 : -1, signY: Double = dragged.y > anchor.y ? 1 : -1
        var newWidth = max(2, (point.x - anchor.x) * signX), newHeight = max(2, (point.y - anchor.y) * signY)
        if !free {
            let scale = max(newWidth / width, newHeight / height)
            newWidth = width * scale; newHeight = height * scale
            if min(newWidth, newHeight) < 2 { let grow = 2 / min(newWidth, newHeight); newWidth *= grow; newHeight *= grow }
        }
        result.width = newWidth; result.height = newHeight
        result.center = Point(anchor.x + signX * newWidth / 2, anchor.y + signY * newHeight / 2)
        return result
    }
}

public struct Design: Codable, Equatable, Sendable {
    public static let engineVersion = "digitize-3"   // 3: travel runs join fill and satin sections inside the shape
    public var schemaVersion = 4
    public var engineVersion = Self.engineVersion
    public var hoop = Hoop()
    public var objects: [RunObject] = []
    public var artwork: Artwork?
    public var cachedPlan: StitchPlan?
    /// The fabric shown inside the hoop, as 0xRRGGBB; nil uses the default linen. Preview only: it never
    /// changes stitches or exports, so older versions can safely ignore it.
    public var fabricColor: Int?
    /// What the design will be sewn on (FabricPresets.swift); nil (older files) means woven. It sets starting values
    /// for new shapes and names the stabilizer on the worksheet; the stitches come from each shape's own settings.
    public var fabricType: FabricType?
    /// The basting box's margin in mm, or nil when it's off (FabricHolding.swift). It changes the stitches, so a
    /// design using it is saved as schema 5.
    public var basting: Double?
    /// How far (mm) the next object must start from the end of one whose trim is "When far" for the thread to be cut
    /// there; nil means `defaultTrimDistance`.
    public var trimDistance: Double?
    public static let defaultTrimDistance = 3.0
    public static let trimDistances = 0.5...20.0
    /// Guide lines dragged out of the rulers (Guide.swift), or nil for none. Like the fabric color they never change
    /// the stitches, so older versions can safely ignore them.
    public var guides: [Guide]?
    public init() {}
    /// The IDs of every object grouped with `id` (just `id` itself when it isn't grouped).
    public func groupMembers(of id: UUID) -> Set<UUID> {
        guard let group = objects.first(where: { $0.id == id })?.groupID else { return [id] }
        return Set(objects.filter { $0.groupID == group }.map(\.id))
    }
    /// Display names for groups with at least two members: "Group A", "Group B"… in sewing order.
    public var groupLabels: [UUID: String] {
        var counts: [UUID: Int] = [:], order: [UUID] = []
        for group in objects.compactMap(\.groupID) { if counts[group] == nil { order.append(group) }; counts[group, default: 0] += 1 }
        var labels: [UUID: String] = [:]
        for (index, group) in order.filter({ counts[$0]! >= 2 }).enumerated() {
            let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            labels[group] = "Group " + (index < 26 ? String(letters[index]) : String(index + 1))
        }
        return labels
    }
    /// True when any digitized node has Bézier handles.
    public var usesHandles: Bool {
        objects.contains { $0.rawStitches == nil && ($0.nodes.contains(where: \.hasHandles) || ($0.holes ?? []).contains { $0.contains(where: \.hasHandles) }) }
    }
    /// Projects using handles or start/end points are saved as schema 5, so older versions refuse them
    /// instead of silently ignoring data that changes the stitches.
    /// Closed satins (borders) count too: an older version would sew them with their last span missing.
    /// So do contour, radial and wave fills: an older version would sew them as straight rows. And satins with a
    /// second underlay, Auto underlay or compensation by width, which an older version would leave out.
    /// True when a design uses something added in file version 6 (line stitch styles; stipple, motif, cross stitch,
    /// gradient and guided fills, and guide lines; raised satin), so it's saved
    /// as version 6 and older versions of the app, which would sew those as plain stitches, refuse it instead.
    public var needsSchemaSix: Bool {
        objects.contains { ($0.kind == .run && ($0.settings.runStyle ?? .running) != .running)
            || $0.lettering.map { $0.letterSpacing != nil || !($0.letterOffsets ?? [:]).isEmpty || $0.entry != nil || $0.exit != nil || $0.shape == .onLine } == true
            || ($0.kind == .fill && [.stipple, .motif, .crossStitch, .gradient, .guided, .satin].contains($0.settings.fillStyle ?? .tatami)) || ($0.kind == .satin && $0.settings.raised == true)
            || $0.guideFor != nil }
    }
    public var needsSchemaFive: Bool { usesHandles || basting != nil || objects.contains { $0.branchID != nil || $0.stitchEdits != nil || $0.entry != nil || $0.exit != nil || ($0.kind == .satin && ($0.closed || $0.settings.relaxedChecks == true)) || ($0.kind == .fill && ($0.settings.fillStyle ?? .tatami) != .tatami) || ($0.kind == .run && ($0.settings.runPasses ?? 1) > 1) || ($0.kind == .satin && ($0.settings.shortStitches == true || $0.settings.autoSplit == true)) || ($0.kind == .fill && ($0.settings.cutOutOverlaps == true || !($0.settings.angleLines ?? []).isEmpty)) || ($0.kind == .satin && ($0.settings.secondUnderlay != nil || $0.settings.underlay == .auto || $0.settings.pullPercent != nil)) } }
    public static func sample() -> Self {
        var design = Self()
        var border = RunObject(name: "Patch outline", nodes: [Point(-30, -23), Point(30, -23), Point(30, 23), Point(-30, 23)].map { PathNode($0) })
        border.closed = true
        let mountain = RunObject(name: "Mountain trail", nodes: [Point(-24, -12), Point(-8, 14), Point(3, -2), Point(13, 10), Point(25, -12)].map { PathNode($0) }, color: .palette[1])
        let arc = RunObject(name: "Curved horizon", nodes: [PathNode(.init(-25, -16)), PathNode(.init(0, -11), smooth: true), PathNode(.init(25, -16))], color: .palette[2])
        design.objects = [border, mountain, arc]
        return design
    }
    public static func stitchSampler() -> Self {
        var design=Self()
        var fill=RunObject(name:"Tatami patch · hole",nodes:[Point(-30,-25),Point(30,-25),Point(30,25),Point(-30,25)].map{PathNode($0)},color:.palette[0])
        fill.digitizing=DigitizingSettings(kind:.fill);fill.stitchLength=3;fill.closed=true
        fill.holes=[[Point(-8,-6),Point(8,-6),Point(8,6),Point(-8,6)].map{PathNode($0)}]
        var satin=RunObject(name:"Satin ribbon",nodes:[Point(-25,32),Point(-25,37),Point(0,30),Point(0,36),Point(25,33),Point(25,38)].map{PathNode($0,smooth:true)},color:.palette[1])
        satin.digitizing=DigitizingSettings(kind:.satin)
        design.objects=[fill,satin];return design
    }

    /// Reject corrupt or unreasonable input before it reaches the renderer or generator.
    public func validate() throws {
        guard (1...6).contains(schemaVersion) else { throw DesignError.invalid("This project uses an unsupported file version.") }
        guard hoop.width.isFinite, hoop.height.isFinite, (1...1000).contains(hoop.width), (1...1000).contains(hoop.height), (hoop.name?.count ?? 0) <= 100 else { throw DesignError.invalid("Hoop dimensions must be between 1 and 1,000 mm.") }
        guard objects.count <= 10_000, Set(objects.map(\.id)).count == objects.count else { throw DesignError.invalid("The object list is invalid or too large.") }
        guard basting.map(Self.bastingMargins.contains) ?? true else { throw DesignError.invalid("The basting box margin must be between 0 and 20 mm.") }
        guard trimDistance.map(Self.trimDistances.contains) ?? true else { throw DesignError.invalid("The trim distance must be between 0.5 and 20 mm.") }
        guard (guides ?? []).count <= Guide.limit, (guides ?? []).allSatisfy({ $0.position.isFinite && abs($0.position) <= 10_000 }) else { throw DesignError.invalid("The guide lines are invalid or too many.") }
        guard objects.reduce(0, { $0 + $1.allNodes.count }) <= 100_000 else { throw DesignError.invalid("This design exceeds the 100,000-node limit.") }
        for object in objects {
            if let edits = object.stitchEdits {
                guard edits.sections.count <= 10_000, edits.sections.reduce(0, { $0 + $1.points.count }) <= 1_000_000,
                      edits.sections.allSatisfy({ $0.points.allSatisfy { $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 } }) else { throw DesignError.invalid("\(object.name) has invalid edited stitches.") }
            }
            guard (0.3...10).contains(object.stitchLength), object.nodes.count <= 100_000,
                  object.allNodes.allSatisfy({ node in [node.point, node.inHandle, node.outHandle].allSatisfy { $0.map { $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 } ?? true } }) else {
                throw DesignError.invalid("Invalid geometry or stitch length in \(object.name).")
            }
            guard object.lettering?.path.map({ path in path.count <= 20_000 && path.allSatisfy { $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 } }) ?? true else {
                throw DesignError.invalid("Invalid lettering line in \(object.name).")
            }
            guard [object.entry, object.exit].allSatisfy({ $0.map { $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 } ?? true }) else {
                throw DesignError.invalid("Invalid start or end point in \(object.name).")
            }
            guard DigitizingSettings.runPassChoices.contains(object.settings.runPasses ?? 1) else { throw DesignError.invalid("Invalid number of running stitch passes in \(object.name).") }
            guard object.settings.runWidth.map(DigitizingSettings.runWidthRange.contains) ?? true, object.settings.runSpacing.map(DigitizingSettings.runSpacingRange.contains) ?? true,
                  object.settings.stippleSpacing.map(DigitizingSettings.stippleSpacingRange.contains) ?? true,
                  object.settings.rippleLines.map(DigitizingSettings.rippleLineRange.contains) ?? true,
                  object.settings.radialCenter.map({ $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 }) ?? true,
                  object.settings.patternSize.map(DigitizingSettings.patternSizeRange.contains) ?? true, object.settings.patternGap.map(DigitizingSettings.patternGapRange.contains) ?? true,
                  [object.settings.gradientStart, object.settings.gradientEnd].allSatisfy({ $0.map(DigitizingSettings.gradientSpacingRange.contains) ?? true }) else { throw DesignError.invalid("Invalid line stitch or pattern size in \(object.name).") }
            guard (0...0xffffff).contains(object.color.hex),object.color.name.count<=256,(object.color.brand?.count ?? 0)<=100,(object.color.code?.count ?? 0)<=100 else{throw DesignError.invalid("Invalid thread color.")}
            if let raw=object.rawStitches {
                guard object.nodes.isEmpty,(object.holes ?? []).isEmpty,object.digitizing==nil,MachineFormat(rawValue:raw.sourceFormat) != nil,
                      !object.tieIn,!object.tieOut,!object.closed,raw.commands.count<=100000 else{throw DesignError.invalid("Invalid imported stitch block.")}
                var previous=raw.start
                for command in raw.commands {
                    guard [.stitch,.jump,.trim,.stop].contains(command.op) else{throw DesignError.invalid("Invalid control in imported stitch block.")}
                    if command.op == .trim || command.op == .stop {guard command.point.distance(to:previous)<0.00001 else{throw DesignError.invalid("Imported control position is invalid.")}}
                    previous=command.point
                }
            } else if object.kind == .raw {throw DesignError.invalid("Imported stitch data is missing.")}
            if object.kind == .vector {
                guard object.allNodes.count<=2000,(object.holes?.count ?? 0)<=100 else{throw DesignError.invalid("Vector outline is too complex.")}
            }
            if object.kind == .satin || object.kind == .fill {
                let s=object.settings
                guard object.allNodes.count<=2000,(object.holes?.count ?? 0)<=100,
                      (0.15...10).contains(s.spacing),(0...2).contains(s.expansion),(-180...180).contains(s.angle),
                      (1...10).contains(s.maximumSatin),s.satinSplit.map(DigitizingSettings.satinSplitRange.contains) ?? true,(0...3).contains(s.inset),(0.5...5).contains(s.underlaySpacing),
                      object.kind == .fill ? [.none,.edge,.edgeAndSparse].contains(s.underlay) : [.none,.center,.edge,.zigzag,.auto].contains(s.underlay),
                      s.secondUnderlay.map({object.kind == .satin && s.underlay != .none && s.underlay != .auto && $0 != s.underlay && [.center,.edge,.zigzag].contains($0)}) ?? true,
                      s.pullPercent.map({object.kind == .satin && DigitizingSettings.pullPercentRange.contains($0)}) ?? true else {throw DesignError.invalid("Invalid digitizing settings in \(object.name).")}
                // The fill style's own settings: out-of-range values would make the fill engines overflow or run for ages.
                guard s.radialCenter.map({ $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 }) ?? true,
                      s.angleLineCenter.map({ $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 }) ?? true,
                      s.angleLines.map({ lines in lines.count <= 100 && lines.allSatisfy { $0.count == 2 && $0.allSatisfy { $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 } } }) ?? true,
                      s.guideLine.map({ line in line.count <= 20_000 && line.allSatisfy { $0.finite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 } }) ?? true,
                      s.waveHeight.map(DigitizingSettings.waveHeightRange.contains) ?? true,
                      s.waveLength.map(DigitizingSettings.waveLengthRange.contains) ?? true else {throw DesignError.invalid("Invalid fill style settings in \(object.name).")}
            }
        }
        if let fabricColor { guard (0...0xffffff).contains(fabricColor) else { throw DesignError.invalid("Invalid fabric color.") } }
        if let artwork {
            guard artwork.center.finite, artwork.width.isFinite, artwork.height.isFinite,
                  (0.1...10_000).contains(artwork.width), (0.1...10_000).contains(artwork.height),
                  (0...1).contains(artwork.opacity), artwork.data.count <= 50_000_000 else { throw DesignError.invalid("Invalid reference artwork.") }
        }
        if let plan = cachedPlan {
            guard plan.commands.count <= 1_000_000, plan.threads.count <= 10_000,
                  plan.commands.allSatisfy({ $0.point.finite && abs($0.point.x) <= 10_000 && abs($0.point.y) <= 10_000 && ($0.op == .end || plan.threads.indices.contains($0.thread)) }) else { throw DesignError.invalid("Invalid cached stitch preview.") }
        }
    }
}

public enum DesignError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum StitchOperation: String, Codable, Hashable, Sendable { case stitch, jump, trim, colorChange, stop, end }
public struct StitchCommand: Codable, Equatable, Sendable {
    public var op: StitchOperation
    public var point: Point
    public var thread: Int
    public var objectID: UUID?
    public var underlay: Bool?
    public init(_ op: StitchOperation, _ point: Point, thread: Int, objectID: UUID? = nil) {
        self.op = op; self.point = point; self.thread = thread; self.objectID = objectID
    }
}
public struct StitchPlan: Codable, Equatable, Sendable {
    public var commands: [StitchCommand] = []
    public var threads: [ThreadColor] = []
    public var warnings: [String] = []
    public init() {}
    public var stitchCount: Int { commands.lazy.filter { $0.op == .stitch }.count }
    public var outsidePoints: [Point] { commands.filter { $0.op == .stitch || $0.op == .jump }.map(\.point) }
}

/// When an object cuts its thread after sewing: never, always, or only when the next object starts far enough away
/// (the design's trim distance) that a plain stitch across would show.
public enum TrimRule: String, CaseIterable, Sendable {
    case off, always, whenFar
    public var title: String {
        switch self { case .off: return "Off"; case .always: return "Always"; case .whenFar: return "When far" }
    }
}

extension RunObject {
    /// `trimAfter` and `trimAlways` as one three-way choice.
    public var trimRule: TrimRule {
        get { !trimAfter ? .off : trimAlways == true ? .always : .whenFar }
        set { trimAfter = newValue != .off; trimAlways = newValue == .always ? true : nil }
    }
}

extension DigitizingSettings {
    /// The fill styles whose Row spacing is measured across two rows.
    public static let pairedRowStyles:[FillStyle]=[.tatami,.wave,.guided]
    /// The gap between neighbouring rows or passes, in mm: half the spacing for fills of those styles (when it's
    /// measured across two rows), otherwise the spacing itself.
    public var rowGap:Double { kind == .fill && spacingAcrossTwoRows == true && Self.pairedRowStyles.contains(fillStyle ?? .tatami) ? spacing/2 : spacing }
    /// What Row spacing means for these settings, for its help text.
    public var rowSpacingHelp:String {
        rowGap < spacing ? "Measured across two rows, from a row to the next one sewn the same way: 0.40 mm lays rows 0.20 mm apart. Smaller is denser and uses more stitches."
                         : "Gap between each pass of thread. Smaller gaps give fuller coverage and use more stitches."
    }
}

extension Design {
    /// Brings a design saved before Row spacing was measured across two rows up to date: those fills' spacing is
    /// doubled, so they sew exactly as before. Hand-edited stitches that matched their object still do.
    public mutating func measureSpacingAcrossTwoRows() {
        for i in objects.indices where objects[i].digitizing != nil && objects[i].digitizing!.spacingAcrossTwoRows != true {
            let edited = objects[i].hasCurrentStitchEdits
            if objects[i].kind == .fill && DigitizingSettings.pairedRowStyles.contains(objects[i].settings.fillStyle ?? .tatami) {
                objects[i].digitizing!.spacing = min(10, objects[i].digitizing!.spacing * 2)
            }
            objects[i].digitizing!.spacingAcrossTwoRows = true
            if edited { objects[i].refreshStitchEdits() }
        }
    }
}
