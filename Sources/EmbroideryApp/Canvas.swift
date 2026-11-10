// The native drawing surface handles millimeter coordinates, tracing, node edits, and selection.
// During drags it draws a temporary snapshot, committing one document edit on mouse-up.
import AppKit
import Combine
import EmbroideryCore

extension ThreadColor {
    var nsColor: NSColor { NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1) }
}

/// Where a click with a drawing tool picks up a selected shape to keep drawing it: an end of an open line or satin
/// column (carried on past it), or a point of a closed outline (new points go in after it).
enum ContinuePick: Equatable {
    case end(UUID, fromStart: Bool)
    case after(UUID, index: Int)
    var id: UUID { switch self { case .end(let id, _), .after(let id, _): return id } }
}

final class DesignCanvas: NSView {
    let state: EditorState
    var pan = CGPoint.zero
    private var observation: AnyCancellable?
    private var preferencesObservation: AnyCancellable?   // redraws when Thread View is switched on or off
    private var dragStart: Point?
    private var screenStart: CGPoint?
    private var panStart = CGPoint.zero
    private var dragSnapshot: Design?
    /// The design's revision when the mouse went down. If it changes before the mouse is let go (Undo mid-drag), the
    /// drag began from an older design, so it's dropped rather than saving that older design back over the Undo.
    private var dragRevision = 0
    private var preview: Design?
    private var draggedNode: NodeLocation?
    /// While a node or handle drag would leave its object unable to sew: the object, why, and the status line from
    /// before the warning (shown again once the shape is sewable). It's outlined in red, since letting go there puts
    /// the node back.
    private var dragProblem: (object: UUID, problem: String, earlierStatus: String)?
    /// True while the dragged node was just added by pressing on an edge (it's saved as "Add Node").
    private var nodeJustAdded = false
    private var draggedHandle: (location: NodeLocation, outgoing: Bool)?   // a Bézier handle being dragged
    private var drawingHandle: Int?   // while tracing: the new draft node whose handles the drag is pulling out
    private var shapeStart: Point?    // while drawing a rectangle, ellipse or basic shape: where the press or first click was
    /// True after a click (no drag) that started a rectangle, ellipse or basic shape: the shape follows the pointer
    /// until the next click puts it down.
    private var shapeFollowsPointer = false
    private var freehandStroke: [Point]?   // while drawing with a Freehand tool: the points the pointer has passed through, in mm
    /// True while a rectangle, ellipse or basic shape is being dragged out with the mouse held down (not while one
    /// follows the pointer after a click).
    var isDraggingShape: Bool { shapeStart != nil && !shapeFollowsPointer }
    /// Escape mid-drag, or after a shape's first click: forgets the shape (or the freehand stroke), so moving on and
    /// letting go or clicking add nothing.
    func cancelShapeDrag() { shapeStart = nil; shapeFollowsPointer = false; freehandStroke = nil; needsDisplay = true }
    /// Sizes the rectangle, ellipse or basic shape being drawn from `start` to `location` (in the view), as the draft:
    /// none while it's under 1 mm across (still just a click). ⌘ keeps the shape even (a square, circle or regular
    /// shape); ⇧ grows it out from `start`. Ellipses always grow from their center.
    private func sizeShape(from start: Point, to location: NSPoint, flags: NSEvent.ModifierFlags) {
        let shape = state.tool.draggedShape ?? .rectangle
        let even = flags.contains(.command)
        let box = ShapeGeometry.box(from: start, to: snapped(model(location)), even: even, fromCenter: shape == .ellipse || flags.contains(.shift))
        let tooSmall = box.max.x - box.min.x < 1 || box.max.y - box.min.y < 1
        state.draft = tooSmall ? [] : ShapeGeometry.nodes(shape, in: box, settings: Preferences.shared.shapes, keepProportions: even)
        needsDisplay = true
    }
    /// The markers shown on a selected object: where it starts and ends sewing, and a radial fill's center.
    private enum Marker { case start, end, center }
    private var draggedMarker: (object: UUID, kind: Marker)?   // a marker being dragged
    /// A resize handle being dragged (Select tool): which sides it moves (-1 left/bottom, 1 right/top, 0 neither), and
    /// the selection's box (mm) when the drag began.
    private var resizeDrag: (dx: Int, dy: Int, low: Point, high: Point)?
    /// A rotate or skew drag: from just outside a corner (dx and dy both set, as for resizing) it turns the selection,
    /// from a skew handle on a side it leans it. Also the selection's box (mm) when the drag began.
    private var turnDrag: (dx: Int, dy: Int, low: Point, high: Point)?
    /// The handle pointer showing now (HandleCursors.swift), or nil while the tool's own pointer shows.
    private var shownHandleCursor: NSCursor?
    /// How near a handle's middle (in points) the pointer must be to use it. Near a corner three zones meet (the
    /// design, the corner square, and the rotate zone just outside), so a zone holds on a little once its pointer is
    /// showing: the pointer then changes only when it clearly moves out, instead of flickering on a border. That's
    /// called hysteresis. A press uses the same zones, so it always does what the pointer shows.
    private var handleReach: CGFloat { shownHandleCursor == nil ? 6 : shownHandleCursor === HandleCursor.rotate ? 4 : 9 }
    /// Where (on screen) a press landed on an object that was already selected. If the mouse comes up there without
    /// moving, the handles switch between resize and rotate/skew.
    private var clickAgainAt: CGPoint?
    /// A letter being moved with Edit Nodes: its lettering, its letter key, and its parts.
    private var letterDrag: (lettering: UUID, key: Int, parts: Set<UUID>)?
    /// An envelope handle being dragged with Edit Nodes: the lettering's recipe as the drag began, and the handle.
    private var envelopeDrag: (spec: LetteringSpec, handle: EnvelopeHandle)?
    private var artworkDrag: Int?   // adjusting the artwork: -1 moves it, 0…3 resizes from that corner
    private var artworkTurnDrag: Int?   // turning the artwork from outside a corner (0…3), or leaning it by a side (4…7)
    private var cropBox: (start: Point, end: Point)?   // while cropping: the box being dragged over the image (mm)
    /// Drops a crop box being dragged (Esc).
    func cancelCrop() { cropBox = nil; needsDisplay = true }
    private var hoopingDrag: Int?   // the hooping being dragged with the Hoopings tool
    private var zoomBox: (start: CGPoint, end: CGPoint)?   // the box being dragged with the Zoom Box tool, in canvas points
    private var selectBox: (start: CGPoint, end: CGPoint)?   // a box dragged from empty canvas with Select, in canvas points
    var measurement: (start: Point, end: Point)?   // the Measure tool's line, in mm; shown until the tool changes
    /// Where the Measure tool's line is up to: being dragged with the mouse held down; following the pointer after a
    /// click (click, move, click); or the mouse is still down on the click that put its end down. Nil otherwise.
    private enum MeasureStep { case dragging, following, placed }
    private var measureStep: MeasureStep?
    /// True after a Measure click (no drag): the line's end follows the pointer until the next click.
    var measureFollowsPointer: Bool { measureStep == .following }
    /// Escape while the line follows the pointer: forgets that line; the Measure tool stays on.
    func cancelMeasuring() { measurement = nil; measureStep = nil; needsDisplay = true }
    /// Moves the end of the Measure tool's line to `location` (in the view) and reads it out in the status bar.
    private func moveMeasurementEnd(to location: NSPoint) {
        guard let line = measurement else { return }
        measurement = (line.start, snapped(model(location)))
        state.status = "Measured " + Self.measurementText(from: line.start, to: measurement!.end, unit: Preferences.shared.unit)
        needsDisplay = true
    }
    // Edit Stitch: needle points being dragged (where the drag began, and the stitches before it), the stitches
    // as they'd be (shown while dragging), and a selection box being dragged.
    private var stitchDrag: (start: Point, sections: [StitchEdits.Section])?
    private var stitchPreview: [StitchEdits.Section]?
    private var stitchBox: (start: CGPoint, end: CGPoint)?
    /// A stitch angle line being dragged: its fill and index, which part (0 or 1: that end; nil: the whole line),
    /// and where the drag began.
    private var angleDrag: (object: UUID, index: Int, end: Int?, start: Point)?
    /// A fill's stitch angle line (StitchAngleLine) being swung by an end with Edit Nodes: the fill, and where the
    /// pointer is (the angle reads out beside it).
    /// `slideFrom` is where the pointer pressed when the line itself (not an end) was grabbed: the drag moves the line
    /// instead of turning it. `anchor` is the end that stays put while the other one is swung.
    private var fillAngleDrag: (object: UUID, pointer: Point, slideFrom: Point?, anchor: Point?)?
    /// A guide line being dragged: its place in the design's guides, which way it runs, whether it's being dragged out
    /// of a ruler (not added yet), and where the pointer is (its position reads out beside it).
    private var guideDrag: (index: Int, vertical: Bool, isNew: Bool, pointer: CGPoint)?
    /// The guide the pointer is over with Select (its place in the design's guides), shown by a ↔ or ↕ pointer.
    private(set) var hoveredGuide: Int?
    /// The place under the pointer where a click would pick up a selected shape to keep drawing it (continuePick), and
    /// the status line from before its hint showed, put back when the pointer moves off.
    private(set) var hoveredPick: ContinuePick?
    private var statusBeforeHint: String?
    /// A measurement as the Measure tool shows it: the distance in `unit`, and the angle from the start, counterclockwise
    /// from pointing right (the same way Rotate counts), e.g. "12.5 mm · 37°" or "0.49 in · 37°".
    static func measurementText(from start: Point, to end: Point, unit: LengthUnit = .millimeters) -> String {
        let dx = end.x - start.x, dy = end.y - start.y
        let degrees = (atan2(dy, dx) * 180 / .pi).rounded()
        return unit.text(hypot(dx, dy)) + String(format: " · %.0f°", degrees == -180 ? 180 : degrees)
    }
    /// While a panel's tab is dragged over the canvas: where it would land (a dock edge, or floating at a point).
    private enum PanelDropHint: Equatable { case dock(DockSide), float(CGPoint) }
    private var panelDropHint: PanelDropHint?
    private var pointer=Point(0,0)
    private var imageData: Data?
    private var image: NSImage?
    private var tracking: NSTrackingArea?
    /// The pointer's place on the rulers: a line on the top ruler at its x, and one on the left ruler at its y. They're
    /// small views of their own, so following the mouse moves them without redrawing every stitch.
    let topRulerMark = RulerMark(), leftRulerMark = RulerMark()
    init(state: EditorState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        state.canvas = self
        for mark in [topRulerMark, leftRulerMark] { mark.isHidden = true; addSubview(mark) }
        observation = state.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.needsDisplay = true } }
        preferencesObservation = Preferences.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true; if self?.rulersShown == false || !Preferences.shared.showsPointerMarks { self?.moveRulerMarks(to: nil) } }
        }
        registerForDraggedTypes([.string])   // panel tabs dragged onto the canvas (see Docking.swift)
    }

    // MARK: Dropping panels on the canvas: near the left or right edge docks them there; anywhere else floats them.
    private func panelHint(_ sender: NSDraggingInfo) -> PanelDropHint? {
        guard PanelDrag.panel != nil else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        if point.x < 70 { return .dock(.left) }
        if point.x > bounds.width - 70 { return .dock(.right) }
        return .float(point)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { panelDropHint = panelHint(sender); needsDisplay = true; return panelDropHint == nil ? [] : .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { panelDropHint = panelHint(sender); needsDisplay = true; return panelDropHint == nil ? [] : .move }
    override func draggingExited(_ sender: NSDraggingInfo?) { panelDropHint = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { panelDropHint = nil; PanelDrag.panel = nil; needsDisplay = true }
        guard let panel = PanelDrag.panel, let hint = panelHint(sender), let window else { return false }
        Preferences.shared.updatePanels { layout in
            switch hint {
            case .dock(let side): layout.move(panel, to: .newGroup(side, at: layout.groups(side).count))
            case .float:
                // A new floating window with its top-left corner near the pointer.
                // Compact panels get a window that fits them; the others a roomier one.
                let screen = window.convertPoint(toScreen: sender.draggingLocation), height = (panel.compact ?? 360) + 50
                layout.move(panel, to: .float(x: screen.x - 40, y: screen.y - height + 20, width: 300, height: height))
            }
        }
        return true
    }
    /// The drop preview: a bar along the edge that would dock the panel, or the outline of the floating window.
    private func drawPanelDropHint() {
        guard let hint = panelDropHint else { return }
        Theme.Canvas.handle.withAlphaComponent(0.85).setFill(); Theme.Canvas.handle.setStroke()
        switch hint {
        case .dock(let side):
            NSBezierPath(roundedRect: CGRect(x: side == .left ? 4 : bounds.width - 10, y: 8, width: 6, height: bounds.height - 16), xRadius: 3, yRadius: 3).fill()
            drawLabel(side == .left ? "Dock on the left" : "Dock on the right", at: CGPoint(x: side == .left ? 16 : bounds.width - 130, y: bounds.midY), size: 12, color: Theme.Canvas.handle)
        case .float(let point):
            let height = (PanelDrag.panel?.compact ?? 360) + 50
            let outline = NSBezierPath(roundedRect: CGRect(x: point.x - 40, y: point.y - height + 20, width: 300, height: height), xRadius: 12, yRadius: 12)
            outline.lineWidth = 2; outline.setLineDash([6, 4], count: 2, phase: 0); outline.stroke()
            drawLabel("Float here", at: CGPoint(x: point.x - 28, y: point.y - 22), size: 12, color: Theme.Canvas.handle)
        }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override var acceptsFirstResponder: Bool { true }
    var origin: CGPoint { CGPoint(x: bounds.midX + pan.x, y: bounds.midY + pan.y) }
    func screen(_ p: Point) -> CGPoint { CGPoint(x: origin.x + p.x * state.zoom, y: origin.y + p.y * state.zoom) }
    func model(_ p: CGPoint) -> Point { Point((p.x - origin.x) / state.zoom, (p.y - origin.y) / state.zoom) }
    /// With Snap on: `p` on a guide within 6 points on screen, otherwise on the nearest snap step (normally a whole
    /// millimeter, or 0.05 in when working in inches; Settings › Measuring › Grid & snap changes it).
    func snapped(_ p: Point) -> Point {
        guard state.snap else { return p }
        let onGuide = Guide.snap(p, to: rulersShown ? state.design.guides ?? [] : [], reach: 6 / state.zoom)   // hidden guides don't catch points
        let unit = Preferences.shared.unit
        let size = Preferences.shared.snapSize
        return Point(onGuide.x ?? unit.snap(p.x, size: size), onGuide.y ?? unit.snap(p.y, size: size))
    }
    /// Thread View: draws each stitch as its own strand of thread `width` points wide (0.45 mm, a 40-weight thread lying
    /// flat), shaded like real thread: darkest where the thread dives into the cloth at each needle hole
    /// and brightest half way along, so a fill shows each stitch. Each stitch also shines according to its direction,
    /// the way thread catches a lamp (`sheenLevel`): brightest running across the light, dullest running along it,
    /// so a satin column looks rounded where it curves and you can see which way a fill runs. A soft shadow lifts
    /// the stitches off the cloth, and when zoomed in far enough, faint slanted marks show the thread's twist.
    /// Stitches are drawn in sewing order in batches of up to 48 in one thread, so later stitches lie over earlier
    /// ones while each batch costs only a few fills per sheen level. Travel moves and needle points aren't drawn: the
    /// machine trims the travel, and the needle holes are hidden under the thread. Stitches off screen are skipped.
    /// `start` is where the needle stands before the first command (the end of the stitches drawn before these).
    /// Static so the Color Blend dialog's preview can draw Thread View too.
    static func drawThread(_ context: CGContext, _ commands: ArraySlice<StitchCommand>, from start: Point = Point(0, 0), threads: [ThreadColor], hidden: Set<UUID>, underlay: UnderlayFilter,
                            width: Double, visibleArea: CGRect, onScreen: (Point) -> CGPoint) {
        // The strand is built from stacked layers, each a little shorter, narrower and lighter than the one below,
        // which together shade it from dark ends to a bright middle. `tone` darkens (below 0) or lightens (above 0)
        // the thread's color; `breadth` is the layer's width as a fraction of the thread's; `trim` shortens it at each
        // end, as a fraction of the stitch's length.
        // `sheen` is how far the layer's tone moves with the stitch's shine: from half of it below `tone` for a dull stitch
        // to half of it above for a shiny one, more for the layers nearer the top, so the highlight changes most.
        let layers: [(tone: Double, breadth: Double, trim: Double, sheen: Double)] = [(-0.45, 1, 0, 0.1), (-0.2, 0.95, 0.06, 0.2), (0, 0.9, 0.14, 0.3), (0.18, 0.8, 0.24, 0.4), (0.32, 0.6, 0.34, 0.5)]
        /// The layer colors (then the twist marks' color) for a thread `color` at sheen level `level`.
        func shades(_ color: NSColor, level: Int) -> [CGColor] {
            let shine = Double(level) / Double(Self.sheenLevels - 1) - 0.5   // -0.5 (dull) to 0.5 (shiny)
            // A dark thread shines less than a light one, as real thread does: the highlight (layers lightened towards white)
            // is a quarter as strong on black as on white, so black stays black and only glints.
            let rgb = color.usingColorSpace(.sRGB) ?? color
            let lightness = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            let lift = 0.25 + 0.75 * lightness
            return layers.map { layer -> CGColor in
                let tone = layer.tone + layer.sheen * shine
                return ((tone < 0 ? color.blended(withFraction: -tone, of: .black) : color.blended(withFraction: min(tone * lift, 1), of: .white)) ?? color).cgColor
            } + [(color.blended(withFraction: 0.35, of: .black) ?? color).withAlphaComponent(0.22).cgColor]   // last: the twist marks
        }
        func allLevels(_ color: NSColor) -> [[CGColor]] { (0..<Self.sheenLevels).map { shades(color, level: $0) } }
        let threadShades = threads.map { allLevels($0.nsColor) }, unknownShades = allLevels(.systemTeal)
        let shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        let shadowOffset = CGVector(dx: width * 0.25, dy: -width * 0.3)   // down and to the right, away from the top-left light
        let showTwist = width >= 5   // the marks would only blur into the color when the thread is drawn narrower
        let reach = visibleArea.insetBy(dx: -width, dy: -width)
        // Per sheen level and layer, the batch's bulging middles (filled) and the lines along them (stroked with round
        // caps, for rounded ends about 70% as wide as the middle, so neighbouring stitches cover the cloth). A batch
        // keeps its sheen levels apart rather than starting a new batch whenever the level changes: stitches turn
        // all the time (the short turn at the end of each fill row), and new batches would multiply the drawing.
        func emptyPaths() -> [[CGMutablePath]] { (0..<Self.sheenLevels).map { _ in layers.map { _ in CGMutablePath() } } }
        var shadows = CGMutablePath(), twists = CGMutablePath()
        var middles = emptyPaths(), cores = emptyPaths(), levelsUsed = Set<Int>()
        var batchThread: Int?, batchShades = unknownShades, batchCount = 0
        func drawBatch() {
            guard batchCount > 0 else { return }
            context.setFillColor(shadowColor); context.addPath(shadows); context.fillPath()
            let levels = levelsUsed.sorted()
            for (index, layer) in layers.enumerated() {
                for level in levels {
                    context.setFillColor(batchShades[level][index]); context.addPath(middles[level][index]); context.fillPath()
                    context.setStrokeColor(batchShades[level][index]); context.setLineWidth(width * layer.breadth * 0.7); context.addPath(cores[level][index]); context.strokePath()
                }
            }
            if showTwist { context.setStrokeColor(batchShades[0][layers.count]); context.setLineWidth(max(0.6, width * 0.07)); context.addPath(twists); context.strokePath() }
            shadows = CGMutablePath(); twists = CGMutablePath()
            middles = emptyPaths(); cores = emptyPaths(); levelsUsed = []; batchCount = 0
        }
        // Adds a lens from `start` to `end`, `breadth` wide at the middle: two curves bowing out on either side. A
        // quadratic curve reaches only half way to its control point, so a control point one full breadth out makes
        // the lens one breadth wide.
        func addLens(_ path: CGMutablePath, _ start: CGPoint, _ end: CGPoint, breadth: Double, across: CGVector) {
            let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: middle.x + across.dx * breadth, y: middle.y + across.dy * breadth))
            path.addQuadCurve(to: start, control: CGPoint(x: middle.x - across.dx * breadth, y: middle.y - across.dy * breadth))
        }
        context.setLineCap(.round)
        var previous = start
        for command in commands {
            defer { previous = command.point }
            guard command.op == .stitch, command.objectID.map({ !hidden.contains($0) }) ?? true, underlay.shows(command) else { continue }
            let a = onScreen(previous), b = onScreen(command.point)
            let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -0.5, dy: -0.5)
            guard box.intersects(reach) else { continue }
            // `along` runs from a to b; `across` is at right angles to it.
            let along = CGVector(dx: b.x - a.x, dy: b.y - a.y), length = max(hypot(along.dx, along.dy), 0.001)
            if batchThread != command.thread || batchCount >= 48 {
                drawBatch(); batchThread = command.thread
                batchShades = threadShades.indices.contains(command.thread) ? threadShades[command.thread] : unknownShades
            }
            let level = Self.sheenLevel(along: along)
            levelsUsed.insert(level)
            let across = CGVector(dx: -along.dy / length, dy: along.dx / length)
            addLens(shadows, CGPoint(x: a.x + shadowOffset.dx, y: a.y + shadowOffset.dy), CGPoint(x: b.x + shadowOffset.dx, y: b.y + shadowOffset.dy), breadth: width * 1.1, across: across)
            for (index, layer) in layers.enumerated() {
                let start = CGPoint(x: a.x + along.dx * layer.trim, y: a.y + along.dy * layer.trim)
                let end = CGPoint(x: b.x - along.dx * layer.trim, y: b.y - along.dy * layer.trim)
                addLens(middles[level][index], start, end, breadth: width * layer.breadth, across: across)
                cores[level][index].move(to: start); cores[level][index].addLine(to: end)
            }
            if showTwist {
                // Short slanted marks across the strand every 0.55 thread widths, shrinking toward the ends.
                let unit = CGVector(dx: along.dx / length, dy: along.dy / length), slant = width * 0.35
                var distance = width * 0.5
                while distance < length - width * 0.5 {
                    let half = width * 0.3 * sin(Double.pi * distance / length)
                    let center = CGPoint(x: a.x + unit.dx * distance, y: a.y + unit.dy * distance)
                    twists.move(to: CGPoint(x: center.x - across.dx * half - unit.dx * slant, y: center.y - across.dy * half - unit.dy * slant))
                    twists.addLine(to: CGPoint(x: center.x + across.dx * half + unit.dx * slant, y: center.y + across.dy * half + unit.dy * slant))
                    distance += width * 0.55
                }
            }
            batchCount += 1
        }
        drawBatch()
    }
    /// How many steps Thread View's sheen is rounded to, so stitches running nearly the same way share a batch.
    static let sheenLevels = 6
    /// How much a stitch running along `along` (on screen, y up) catches a light from the top left, as a level from 0
    /// (running straight towards the light: dull) to `sheenLevels - 1` (running straight across it: shiny). Thread
    /// shines most where its fibres face the light side-on, as polyester and rayon do under a lamp. The power curve
    /// keeps most stitches near dull and saves the brightest levels for those close to square-on.
    static func sheenLevel(along: CGVector) -> Int {
        let length = hypot(along.dx, along.dy)
        guard length > 0 else { return 0 }
        // Towards the light: up and to the left. The cross product's size is the sine of the angle between the two.
        let light = CGVector(dx: -1 / 2.0.squareRoot(), dy: 1 / 2.0.squareRoot())
        let across = abs(along.dx * light.dy - along.dy * light.dx) / length
        return Int((pow(across, 1.6) * Double(sheenLevels - 1)).rounded())
    }
    /// Zooms to `zoom` (kept within 0.5–60) so the spot under `anchor` (a point in the canvas; its middle if nil)
    /// stays where it is on screen.
    func setZoom(_ zoom: Double, keeping anchor: CGPoint? = nil) {
        let anchor = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY), spot = model(anchor), zoom = min(60, max(0.5, zoom))
        state.zoom = zoom
        // Solves screen(spot) == anchor for the pan: bounds.mid + pan + spot × zoom = anchor.
        pan = CGPoint(x: anchor.x - bounds.midX - spot.x * zoom, y: anchor.y - bounds.midY - spot.y * zoom)
        needsDisplay = true
    }
    /// Zooms so a box (mm) fills the canvas, 50 points in from each side, with its middle in the middle.
    func zoom(to box: (min: Point, max: Point)) {
        let width = max(box.max.x - box.min.x, 1), height = max(box.max.y - box.min.y, 1)   // a box under 1 mm zooms as if 1 mm
        let zoom = min(60, max(0.5, min((bounds.width - 100) / width, (bounds.height - 100) / height)))
        let middle = (box.min + box.max) * 0.5
        state.zoom = zoom; pan = CGPoint(x: -middle.x * zoom, y: -middle.y * zoom); needsDisplay = true
    }
    /// The zoom (screen points per mm) at which the design shows at its real size on the window's display, worked out
    /// from the physical width the display reports to macOS; nil if it reports none (as some projectors don't).
    var realSizeZoom: Double? {
        guard let screen = window?.screen ?? NSScreen.main,
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        let millimeters = CGDisplayScreenSize(display).width
        return millimeters > 0 ? screen.frame.width / millimeters : nil
    }
    func fit() {
        state.zoom = min(max(1, fitZoom(bounds.size)), 30)
        let area = Self.sewingArea(state.design), middle = (area.min + area.max) * 0.5
        pan = CGPoint(x: -middle.x * state.zoom, y: -middle.y * state.zoom); needsDisplay = true
    }
    /// Where stitches may go, in mm: the hoop around the center, or every hooping of a multi-hooped design.
    static func sewingArea(_ design: Design) -> (min: Point, max: Point) {
        let w = design.hoop.width / 2, h = design.hoop.height / 2, hoopings = design.multiHooping?.hoopings ?? []
        guard !hoopings.isEmpty else { return (Point(-w, -h), Point(w, h)) }
        return (Point(hoopings.map(\.center.x).min()! - w, hoopings.map(\.center.y).min()! - h), Point(hoopings.map(\.center.x).max()! + w, hoopings.map(\.center.y).max()! + h))
    }
    /// The zoom at which the hoop (or all the hoopings) just fits a canvas of `size`, 50 points in from each side;
    /// negative when it's tiny.
    private func fitZoom(_ size: CGSize) -> Double {
        let area = Self.sewingArea(state.design)
        return min((size.width - 100) / (area.max.x - area.min.x), (size.height - 100) / (area.max.y - area.min.y))
    }
    // When the canvas area grows or shrinks (the window is resized, or panels are shown, hidden or resized), the zoom
    // and pan scale by how much the fitted zoom changed, so the view stays framed the same way: a fitted hoop still
    // fits, and a zoomed-in corner stays in view, just bigger or smaller.
    override func setFrameSize(_ newSize: NSSize) {
        let before = fitZoom(frame.size)
        super.setFrameSize(newSize)
        let after = fitZoom(newSize)
        guard before > 0, after > 0, before != after else { return }   // skips the first layout, when the canvas starts at no size
        let scale = after / before
        state.zoom = min(60, max(0.5, state.zoom * scale))
        pan = CGPoint(x: pan.x * scale, y: pan.y * scale)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
    }
    /// Called whenever the tool changes: the Measure tool's line goes, and the pointer takes the new tool's shape.
    func toolDidChange() {
        if state.tool != .measure { measurement = nil; measureStep = nil }
        hoveredGuide = nil; hoveredPick = nil; statusBeforeHint = nil
        window?.invalidateCursorRects(for: self); needsDisplay = true
    }
    /// The pointer the current tool uses on the canvas.
    private var toolCursor: NSCursor {
        state.tool == .pan || state.tool == .artwork ? .openHand : state.tool == .text ? .iBeam : state.tool.draws || state.tool.dragsShape || state.tool.freehand || state.tool == .entryExit || state.tool == .zoomBox || state.tool == .measure || state.tool == .branch || state.tool == .wreath || state.tool == .paintStitches || state.tool == .addAngles || state.tool == .removeAngles || state.tool == .stitchEdit ? .crosshair : .arrow
    }
    /// ↔ for an up-and-down guide, ↕ for a side-to-side one.
    private func guideCursor(vertical: Bool) -> NSCursor { vertical ? .resizeLeftRight : .resizeUpDown }
    /// The pointer the canvas wants right now: a handle's (rotate, resize, skew), ↔ or ↕ over or dragging a guide, a
    /// pointing hand where a click carries on a shape, or else the tool's own.
    private var wantedCursor: NSCursor {
        if let cursor = shownHandleCursor { return cursor }
        if let drag = guideDrag { return guideCursor(vertical: drag.vertical) }
        if let over = hoveredGuide, let guides = state.design.guides, guides.indices.contains(over) { return guideCursor(vertical: guides[over].vertical) }
        if hoveredPick != nil { return .pointingHand }
        return toolCursor
    }
    /// Shows `wantedCursor`, and makes it the canvas's pointer for macOS too (resetCursorRects). That matters:
    /// macOS puts a view's own pointer back whenever something in the window moves or changes, which here is on
    /// every mouse move (the ruler marks follow the pointer, and the x/y readout changes). If the canvas's own pointer
    /// were still the tool's, it would keep flicking back to it between moves.
    private func showWantedCursor() {
        wantedCursor.set()
        window?.invalidateCursorRects(for: self)
    }
    /// With Select, the pointer turns ↔ or ↕ over a guide wherever a drag would grab it (no object under it), and back
    /// when it moves off.
    private func updateGuideCursor(at location: CGPoint) {
        let over = state.tool == .select && guideDrag == nil ? guide(near: location).flatMap { hit(model(location)) == nil ? $0 : nil } : nil
        guard over != hoveredGuide else { return }
        hoveredGuide = over
        showWantedCursor()
    }
    /// With a drawing tool and nothing drawn yet, pointing at a place where a click picks up the selected shape (an end
    /// of a line or column, a point of a closed outline) fills in its marker, turns the pointer into a hand and says in
    /// the status line what a click does. Moving off puts back the tool's pointer and the status line from before.
    /// `location` nil means the pointer left the canvas.
    func updateContinueHover(at location: CGPoint?) {
        let over = state.draft.isEmpty ? location.flatMap(continuePick(near:)) : nil
        guard over != hoveredPick else { return }
        hoveredPick = over; needsDisplay = true
        if let over, let object = state.design.objects.first(where: { $0.id == over.id }) {
            if statusBeforeHint == nil { statusBeforeHint = state.status }
            switch over {
            case .end(_, let fromStart): state.status = "Click to carry on ‘\(object.name)’ from its \(fromStart ? "start" : "end")."
            case .after: state.status = "Click to add points to ‘\(object.name)’ between this point and the next one (marked)."
            }
        } else if let saved = statusBeforeHint { state.status = saved; statusBeforeHint = nil }
        showWantedCursor()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: wantedCursor) }
    /// The grid lines' color: the custom one from Settings, or automatically light lines on dark cloth and dark lines
    /// on light cloth. The default linen (no fabric color) follows light or dark mode, as it always has.
    static func gridColor(fabric: Int?, custom: Int?, opacity: Double?) -> NSColor {
        if let custom { return Theme.fixed(custom).withAlphaComponent(opacity ?? 0.4) }
        guard let fabric else { return Theme.Canvas.grid }
        // Perceived brightness (0–255): green looks brightest, blue darkest.
        let brightness = Double((fabric >> 16) & 255) * 0.299 + Double((fabric >> 8) & 255) * 0.587 + Double(fabric & 255) * 0.114
        return brightness < 128 ? NSColor.white.withAlphaComponent(0.25) : Theme.Canvas.gridOnLight
    }

    /// The objects to fade: with the Hoopings tool and a hooping picked in its list, everything the other hoopings sew.
    private func fadedByHooping(_ design: Design) -> Set<UUID> {
        guard state.tool == .hooping, let picked = state.selectedHooping, let assignment = state.hoopingAssignment,
              assignment.objects.indices.contains(picked) else { return [] }
        return Set(design.objects.map(\.id)).subtracting(assignment.objects[picked])
    }
    /// A multi-hooped design's hoopings: each a dashed outline in its own color, with its number in the top left
    /// corner and a small target at its center. The picked one is drawn bolder.
    private func drawHoopings(_ design: Design) {
        let w = design.hoop.width * state.zoom, h = design.hoop.height * state.zoom
        for (index, hooping) in (design.multiHooping?.hoopings ?? []).enumerated() {
            let color = Theme.Canvas.hooping(index), picked = state.selectedHooping == index, c = screen(hooping.center)
            let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            let outline = design.hoop.oval ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            color.setStroke(); outline.lineWidth = picked ? 3 : 2; outline.setLineDash([9, 6], count: 2, phase: 0); outline.stroke()
            let target = NSBezierPath(ovalIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14))
            target.move(to: CGPoint(x: c.x - 11, y: c.y)); target.line(to: CGPoint(x: c.x + 11, y: c.y))
            target.move(to: CGPoint(x: c.x, y: c.y - 11)); target.line(to: CGPoint(x: c.x, y: c.y + 11))
            target.lineWidth = 1.2; target.stroke()
            let badge = CGRect(x: rect.minX + 8, y: rect.maxY - 30, width: 22, height: 22)
            color.setFill(); NSBezierPath(ovalIn: badge).fill()
            let number = NSAttributedString(string: "\(index + 1)", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white])
            number.draw(at: CGPoint(x: badge.midX - number.size().width / 2, y: badge.midY - number.size().height / 2))
        }
    }
    /// The reference image's outline on screen: a rectangle, or the slanted shape a turned or skewed image takes.
    func artworkOutline(_ artwork: Artwork) -> NSBezierPath {
        let corners = artwork.corners.map(screen), outline = NSBezierPath()
        outline.move(to: corners[0]); for corner in corners.dropFirst() { outline.line(to: corner) }; outline.close()
        return outline
    }
    /// The image's skew handles on screen: the middles of its own bottom, right, top and left sides (handles 4…7 in
    /// `Artwork.turned`).
    private func artworkSideHandles(_ artwork: Artwork) -> [CGPoint] {
        let corners = artwork.corners
        return (0..<4).map { screen((corners[$0] + corners[($0 + 1) % 4]) * 0.5) }
    }
    /// Which corner of the reference image (0…3, as in `Artwork.corners`) the pointer is just outside, with Move &
    /// Size Artwork: within 24 points of it but off its handle and off the image. A drag there rotates the image.
    /// While ↻ shows, the zone holds on 4 points further out and 3 points onto the image (see `handleReach`).
    private func artworkRotateCorner(at location: CGPoint) -> Int? {
        let holding = shownHandleCursor === HandleCursor.rotate
        guard state.tool == .artwork, !state.croppingArtwork, let artwork = state.design.artwork, artwork.visible, !artworkContains(artwork, location, inset: holding ? 3 : 0) else { return nil }
        let corners = artwork.corners.map(screen), reach = artworkHandleReach, outer: CGFloat = holding ? 28 : 24
        return corners.indices.first { let distance = hypot(corners[$0].x - location.x, corners[$0].y - location.y); return distance > reach && distance <= outer }
    }
    /// True when `location` (on screen) is on the image, at least `inset` points in from its edges (measured along
    /// its own sides).
    private func artworkContains(_ artwork: Artwork, _ location: CGPoint, inset: CGFloat) -> Bool {
        let own = artwork.local(model(location)), margin = Double(inset) / state.zoom
        return abs(own.x) < artwork.width / 2 - margin && abs(own.y) < artwork.height / 2 - margin
    }
    /// The reference image's handles are bigger than a selection's (9 points), and hold on the same way.
    private var artworkHandleReach: CGFloat { shownHandleCursor == nil ? 9 : shownHandleCursor === HandleCursor.rotate ? 7 : 12 }


    override func draw(_ dirtyRect: NSRect) {
        (Preferences.shared.data.pasteboardColor.map(Theme.fixed) ?? Theme.Canvas.pasteboard).setFill(); bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let design = preview ?? state.design
        let hoop = CGRect(x: origin.x - design.hoop.width * state.zoom / 2, y: origin.y - design.hoop.height * state.zoom / 2, width: design.hoop.width * state.zoom, height: design.hoop.height * state.zoom)
        let hoopPath = design.hoop.oval ? NSBezierPath(ovalIn: hoop) : NSBezierPath(roundedRect: hoop, xRadius: 3, yRadius: 3)
        // A multi-hooped design shows one piece of cloth under all its hoopings, with no hoop ring: the hoopings are
        // drawn as outlines over the stitches (drawHoopings).
        let multi = !(design.multiHooping?.hoopings ?? []).isEmpty
        let areaMM = Self.sewingArea(design), area = CGRect(x: screen(areaMM.min).x, y: screen(areaMM.min).y, width: (areaMM.max.x - areaMM.min.x) * state.zoom, height: (areaMM.max.y - areaMM.min.y) * state.zoom)
        // Wooden hoop ring around the cloth, drawn at a fixed on-screen thickness whatever the zoom.
        let ringRect = hoop.insetBy(dx: -16, dy: -16)
        let ring = design.hoop.oval ? NSBezierPath(ovalIn: ringRect) : NSBezierPath(roundedRect: ringRect, xRadius: 20, yRadius: 20)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -4); shadow.set()
        // Linen cloth stretched inside the ring; the ring's inner rim and clasp sit on top of it.
        let clothRect = multi ? area.insetBy(dx: -14, dy: -14) : hoop.insetBy(dx: -10, dy: -10)
        let cloth = design.hoop.oval && !multi ? NSBezierPath(ovalIn: clothRect) : NSBezierPath(roundedRect: clothRect, xRadius: multi ? 10 : 14, yRadius: multi ? 10 : 14)
        // The design's own fabric color if one was chosen, else the default linen.
        let fabric = design.fabricColor.map(Theme.fixed) ?? Theme.Canvas.fabric
        if multi { fabric.setFill(); cloth.fill() } else { Theme.Canvas.wood.setStroke(); ring.lineWidth = 12; ring.stroke() }   // the shadow falls under the ring, or the bare cloth
        NSGraphicsContext.restoreGraphicsState()
        fabric.setFill(); cloth.fill()
        drawWeave(in: cloth, color: design.fabricColor == nil ? Theme.Canvas.weave : weaveColor(for: fabric), context: context)
        Theme.Canvas.woodEdge.setStroke(); cloth.lineWidth = 2; cloth.stroke()
        if !multi { Theme.Canvas.clasp.setFill(); NSBezierPath(roundedRect: CGRect(x: ringRect.midX - 22, y: ringRect.maxY - 2, width: 44, height: 12), xRadius: 4, yRadius: 4).fill() }
        // The reference picture, drawn here under everything unless it's been moved down the sewing order; then it's
        // drawn after the stitches of the objects under it (ArtworkLayer.swift).
        func drawArtwork() {
            guard let artwork = design.artwork, artwork.visible else { return }
            if imageData != artwork.data { imageData = artwork.data; image = NSImage(data: artwork.data) }
            // Drawn level round its own center, with the drawing turned, flipped or leaned by the image's two arrows
            // (an affine transform: each point goes to x times one arrow plus y times the other).
            let axes = artwork.axes, middle = screen(artwork.center)
            NSGraphicsContext.saveGraphicsState()
            let placing = NSAffineTransform()
            placing.transformStruct = NSAffineTransformStruct(m11: axes.x.x, m12: axes.x.y, m21: axes.y.x, m22: axes.y.y, tX: middle.x, tY: middle.y)
            placing.concat()
            let rect = CGRect(x: -artwork.width * state.zoom / 2, y: -artwork.height * state.zoom / 2, width: artwork.width * state.zoom, height: artwork.height * state.zoom)
            // A cropped image draws just its shown part (NSImage counts from its bottom-left corner, as crops do).
            let source = artwork.crop.map { crop in image.map { CGRect(x: crop.left * $0.size.width, y: crop.bottom * $0.size.height, width: (crop.right - crop.left) * $0.size.width, height: (crop.top - crop.bottom) * $0.size.height) } ?? .zero } ?? .zero
            image?.draw(in: rect, from: source, operation: .sourceOver, fraction: state.artworkOpacityPreview ?? artwork.opacity)   // live while its slider is dragged
            NSGraphicsContext.restoreGraphicsState()
            // While adjusting it, the image gets a frame and squares on its corners that resize it; once it's clicked,
            // diamonds on its sides lean it. While it's rotated, a cross marks the middle it turns about.
            if state.tool == .artwork {
                Theme.Canvas.handle.setStroke(); let frame = artworkOutline(artwork); frame.lineWidth = 1.5; frame.stroke()
                // While cropping there are no handles, just the box being dragged, along the image's own sides.
                if state.croppingArtwork {
                    if let box = cropBox, let kept = artwork.cropped(from: box.start, to: box.end) {
                        let outline = artworkOutline(kept)
                        NSColor.white.withAlphaComponent(0.25).setFill(); outline.fill()
                        Theme.Canvas.handle.setStroke(); outline.lineWidth = 2; outline.setLineDash([6, 4], count: 2, phase: 0); outline.stroke()
                    }
                    return
                }
                for p in artwork.corners.map(screen) {
                    let knob = NSBezierPath(rect: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                    NSColor.white.setFill(); knob.fill(); Theme.Canvas.handle.setStroke(); knob.lineWidth = 1.5; knob.stroke()
                }
                if state.artworkSkewHandles { for p in artworkSideHandles(artwork) { drawSkewHandle(p, color: Theme.Canvas.handle) } }
                if let handle = artworkTurnDrag, handle < 4 { drawPivot(middle) }
            }
        }
        let artworkLayer = state.artworkOnTop ? design.objects.count : design.artworkLayer   // on top: over every object
        if artworkLayer == 0 { drawArtwork() }
        if state.grid {
            context.saveGState(); context.addPath(multi ? CGPath(rect: area, transform: nil) : hoopPath.cgPathCopy); context.clip()
            let preferences = Preferences.shared.data
            context.setStrokeColor(Self.gridColor(fabric: design.fabricColor, custom: preferences.gridColor, opacity: preferences.gridOpacity).cgColor); context.setLineWidth(0.5)
            // Millimeters: a line every 10 mm (5 mm zoomed in) from the hoop's edge. Inches: every ½ in (¼ in zoomed in),
            // counted from the hoop's center like the rulers, so a line falls on each whole inch. (Those are the normal
            // size; Settings › Measuring › Grid & snap can make them finer or coarser.)
            let inches = Preferences.shared.unit == .inches
            let spacing = Preferences.shared.unit.gridSpacing(Preferences.shared.gridSize) / (state.zoom < 3 ? 1 : 2)
            func first(_ low: Double) -> Double { inches ? (low / spacing).rounded(.up) * spacing : low }
            let low = areaMM.min, high = areaMM.max
            for x in stride(from: first(low.x), through: high.x, by: spacing) { context.move(to: screen(Point(x, low.y))); context.addLine(to: screen(Point(x, high.y))) }
            for y in stride(from: first(low.y), through: high.y, by: spacing) { context.move(to: screen(Point(low.x, y))); context.addLine(to: screen(Point(high.x, y))) }
            context.strokePath(); context.restoreGState()
        }
        // A dashed "stitched" outline marks the sewing area inside the cloth.
        if !multi { Theme.Canvas.sewingArea.setStroke(); hoopPath.lineWidth = 1.2; hoopPath.setLineDash([6, 4], count: 2, phase: 0); hoopPath.stroke() }
        let userHidden = Set(design.objects.filter { !state.isShown($0) }.map(\.id))
        // Pointing at a choice in a picture menu (Fill style, Pattern): the selected objects' own stitches give way
        // to the preview's (PictureMenu.swift), drawn where their own would be in the sewing order, so whatever is sewn
        // after them still lies on top and only their stitches change.
        let menuPreview = state.settingsPreview
        var hidden = userHidden.union(menuPreview?.objects ?? [])
        var previous = Point(0, 0)
        // This loop runs once per stitch (tens of thousands of times), and it runs on every frame of a window resize,
        // so everything it needs is read once up here: reading the editor state's @Published values or making a new
        // color inside the loop made each redraw too slow to keep up with the pointer.
        let plan = state.plan, zoom = state.zoom, center = origin, visibleArea = bounds
        let underlay = UnderlayFilter(view: state.underlayView, selection: state.selection), showNeedles = state.needles && zoom >= 3, threadView = Preferences.shared.threadView
        let showStitches = state.showStitches, showConnectors = state.showsConnectors, thinLines = showStitches && !threadView
        func onScreen(_ p: Point) -> CGPoint { CGPoint(x: center.x + p.x * zoom, y: center.y + p.y * zoom) }   // same as screen(_:)
        // Each thread's stitch color, made once: [normal, underlay (fainter)].
        func colors(_ threads: [ThreadColor]) -> [[CGColor]] { threads.map { thread in [0.95, 0.40].map { thread.nsColor.withAlphaComponent($0).cgColor } } }
        var threads = plan.threads, threadColors = colors(threads)
        let unknownThread = [0.95, 0.40].map { NSColor.systemTeal.withAlphaComponent($0).cgColor }
        // While reviewing the sewing order one step at a time, the design is sewn up to the end of the step being
        // looked at; otherwise (and for the whole route) the stitch player says how much is sewn.
        let review = state.reviewShowsRoute ? nil : state.reviewStep?.step
        let commands = plan.commands.prefix(review?.commands.upperBound ?? Int(Double(plan.commands.count) * state.playback))
        // In the stitch view (Thread View off) each stitch is a hairline, one screen pixel wide, so a fill's rows stay
        // apart and show which way they run; the selected objects' stitches are drawn in the highlight blue, so they
        // stand out from the rest (their underlay fainter, as usual).
        context.setLineWidth(1 / max(1, window?.backingScaleFactor ?? 1)); context.setLineCap(.round)
        let selectedObjects = state.selection
        let highlight = [0.95, 0.40].map { Theme.Canvas.stitchHighlight.withAlphaComponent($0).cgColor }
        var needles = CGMutablePath()
        var activeColor: CGColor?
        /// Draws `part` of the stitches (thread or thin lines, and travel moves), carrying on from where the last part ended.
        func drawStitches(_ part: ArraySlice<StitchCommand>) {
            if threadView && showStitches { Self.drawThread(context, part, from: previous, threads: threads, hidden: hidden, underlay: underlay, width: max(1.2, 0.45 * zoom), visibleArea: visibleArea, onScreen: onScreen) }
            // The thin-line stitch view, travel moves dashed, and needle points (in either view).
            for command in part where thinLines || showConnectors || showNeedles {
                let visible = (command.objectID.map { !hidden.contains($0) } ?? true) && underlay.shows(command)
                let p = onScreen(command.point)
                if command.op == .stitch && visible {
                    if thinLines {
                        let colors = command.objectID.map(selectedObjects.contains) == true ? highlight
                            : threadColors.indices.contains(command.thread) ? threadColors[command.thread] : unknownThread
                        let color = colors[command.underlay == true && !underlay.showsAlone(command) ? 1 : 0]   // underlay faint, unless it's shown on its own
                        if activeColor !== color {context.strokePath();context.setStrokeColor(color);activeColor=color}   // !== : the very same color object, a cheap check
                        context.move(to: onScreen(previous)); context.addLine(to: p)
                    }
                    if showNeedles && visibleArea.contains(p) { needles.addEllipse(in: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2)) }
                } else if command.op == .jump && visible && showConnectors && previous.distance(to: command.point) > 0.1 {
                    context.strokePath();activeColor=nil
                    context.saveGState(); context.setStrokeColor(Theme.Canvas.jump.cgColor); context.setLineDash(phase: 0, lengths: [3, 5]); context.move(to: onScreen(previous)); context.addLine(to: p); context.strokePath(); context.restoreGState()
                }
                previous = command.point
            }
            context.strokePath(); activeColor = nil
            if !(thinLines || showConnectors || showNeedles), let last = part.last { previous = last.point }   // the loop above didn't run
        }
        // The objects under the picture, then the picture, then the rest. Commands come in sewing order, so the
        // first command of an object over the picture splits them.
        let over = Set(design.objects[artworkLayer...].map(\.id))
        let split = artworkLayer == 0 ? commands.startIndex : commands.firstIndex { $0.objectID.map(over.contains) ?? false } ?? commands.endIndex
        // With a hooping picked in the Hoopings list, what the other hoopings sew is drawn faint first, then the picked
        // hooping's stitches as usual.
        let faded = fadedByHooping(design)
        if !faded.isEmpty {
            let shown = hidden
            hidden = shown.union(design.objects.map(\.id).filter { !faded.contains($0) })
            context.saveGState(); context.setAlpha(0.22); context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawStitches(commands[...])
            context.endTransparencyLayer(); context.restoreGState()
            hidden = shown.union(faded); previous = Point(0, 0); needles = CGMutablePath()
        }
        // Reviewing with Faded (Settings › Look): the steps still to sew are drawn faint first, under what's sewn.
        if let review, !Preferences.shared.reviewHidesUnsewn, commands.endIndex < plan.commands.endIndex {
            previous = review.end
            context.saveGState(); context.setAlpha(0.22); context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawStitches(plan.commands[commands.endIndex...])
            context.endTransparencyLayer(); context.restoreGState()
            previous = Point(0, 0); needles = CGMutablePath()
        }
        // Each tried object's preview stitches, with where its own stitches start in the design's (or the end, for one
        // that has none yet), in sewing order.
        var tried: [(start: Int, stitches: ArraySlice<StitchCommand>)] = []
        if let menuPreview {
            let previewCommands = menuPreview.plan.commands
            for id in menuPreview.objects {
                guard let first = previewCommands.firstIndex(where: { $0.objectID == id }),
                      let last = previewCommands.lastIndex(where: { $0.objectID == id }) else { continue }
                tried.append((plan.commands.firstIndex { $0.objectID == id } ?? plan.commands.endIndex, previewCommands[first...last]))
            }
            tried.sort { $0.start < $1.start }
        }
        /// Draws one tried object's preview stitches, in the preview's own threads, then carries on where the design was.
        func drawTried(_ stitches: ArraySlice<StitchCommand>) {
            let resume = (previous, hidden, threads, threadColors)
            hidden = userHidden; threads = menuPreview?.plan.threads ?? threads; threadColors = colors(threads); previous = stitches.first!.point
            drawStitches(stitches)
            (previous, hidden, threads, threadColors) = resume
        }
        /// Draws `part` of the design's stitches with each tried object's preview slotted in where its stitches start.
        func drawWithTried(_ part: ArraySlice<StitchCommand>) {
            var from = part.startIndex
            for (start, stitches) in tried where part.indices.contains(start) {
                drawStitches(part[from..<start]); drawTried(stitches); from = start
            }
            drawStitches(part[from...])
        }
        drawWithTried(commands[..<split])
        if artworkLayer > 0 { drawArtwork() }
        drawWithTried(commands[split...])
        for (start, stitches) in tried where start == plan.commands.endIndex { drawTried(stitches) }
        // On thread, each needle point gets a light ring so it shows on any thread color.
        if threadView && showStitches { context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor); context.setLineWidth(0.8); context.addPath(needles); context.strokePath() }
        context.setFillColor(Theme.Canvas.needle.cgColor); context.addPath(needles); context.fillPath()
        if state.showDensity { drawDensityMap(context) }
        if let review, let travel = review.travel, let index = state.reviewStep?.index {
            drawTravel(travel, to: review.start, warned: state.sewingWarnings[index] != nil)
        }
        let sewn = sewnEnds()
        let unplaced = Set(state.hoopingAssignment?.unplaced ?? [])
        for object in design.objects where state.isShown(object) {
            let selected = state.selection.contains(object.id)
            if object.kind == .vector || selected || state.showOutlines || state.busy || state.generationError != nil || preview != nil || unplaced.contains(object.id) {
                for points in object.outlinePaths where !points.isEmpty {
                    let path = NSBezierPath(); path.move(to: screen(points[0])); for point in points.dropFirst() { path.line(to: screen(point)) }
                    // Selected objects get a thin dotted outline in one neutral color, so it shows on any thread. One that
                    // can't be sewn (the stitch error), or would be if a node drag let go here, is outlined in red instead.
                    let broken = state.brokenObjects.contains(object.id) || dragProblem?.object == object.id || unplaced.contains(object.id)
                    if object.guideFor != nil {
                        // A fill's guide line: long dashes in the handle color, bolder while selected.
                        Theme.Canvas.handle.setStroke(); path.lineWidth = selected ? 2 : 1.5
                        path.setLineDash([6, 4], count: 2, phase: 0); path.stroke(); continue
                    }
                    (broken ? NSColor.systemRed : selected ? Theme.Canvas.selection : object.color.nsColor.withAlphaComponent(0.4)).setStroke(); path.lineWidth = broken ? 2 : 1
                    if selected { path.setLineDash([2, 2], count: 2, phase: 0) }; path.stroke()
                }
            }
            // Where it starts and ends sewing, and a radial fill's Center or a ripple's Target, only while editing: with
            // Edit Nodes or the Start & End tool (drawn before its nodes, so a node on the same spot stays on top).
            if selected && Self.showsEnds(state.tool) {
                let ends = markerPoints(object, sewn: sewn, few: fewSelected(in: design))
                drawStartMarker(ends.start)
                drawEndMarker(ends.end)
                drawMarker(radialCenter(object), label: object.kind == .run ? "Target" : "Center", color: Theme.Canvas.handle)
            }
            // Nodes show only with Edit Nodes, the one tool that can move them.
            if selected && state.tool == .node && !object.locked && object.kind != .raw && object.lettering == nil {
                for (ring,nodes) in ([object.nodes]+(object.holes ?? [])).enumerated() {
                    for (index,node) in nodes.enumerated() {
                        let p=screen(node.point),rect=CGRect(x:p.x-3.5,y:p.y-3.5,width:7,height:7)
                        let shape=node.smooth ? NSBezierPath(ovalIn:rect):NSBezierPath(rect:rect)
                        let active=state.selectedNode == NodeLocation(object:object.id,ring:ring-1,index:index)
                        (active ? NSColor.systemOrange:NSColor.white).setFill();shape.fill();object.color.nsColor.setStroke();shape.lineWidth=1.5;shape.stroke()
                    }
                }
                // The selected smooth node shows its Bézier handles while the Node tool is active.
                if state.tool == .node, let location=state.selectedNode, location.object==object.id, let handles=effectiveHandles(object,location) {
                    for handle in [handles.incoming,handles.outgoing].compactMap({$0}) {
                        let n=screen(nodePoint(object,location)),h=screen(handle)
                        let arm=NSBezierPath();arm.move(to:n);arm.line(to:h);Theme.Canvas.handle.setStroke();arm.lineWidth=1;arm.stroke()
                        let knob=NSBezierPath(ovalIn:CGRect(x:h.x-4,y:h.y-4,width:8,height:8));NSColor.white.setFill();knob.fill();Theme.Canvas.handle.setStroke();knob.lineWidth=1.5;knob.stroke()
                    }
                }
            }
            // A fill's stitch angle shows as a line across it with Edit Nodes; dragging an end turns the stitches, while
            // the other end stays put.
            if selected && state.tool == .node && !object.locked && object.lettering == nil, let ends = StitchAngleLine.ends(of: object) {
                drawAngleLine(ends.0, ends.1, selected: fillAngleDrag?.object == object.id)
            }
            // Stitch angle lines show while they can be changed: with Edit Nodes and the stitch angle tools.
            if selected && [.node, .addAngles, .removeAngles].contains(state.tool) {
                for (index, line) in (object.settings.angleLines ?? []).enumerated() where line.count == 2 {
                    let chosen = state.selectedAngle.map { $0.object == object.id && $0.index == index } ?? false
                    drawAngleLine(line[0], line[1], selected: chosen)
                }
            }
        }
        if routeShown { drawRoute(state.sewingSteps, current: state.reviewStep?.index) }
        if state.draft.isEmpty { drawContinueMarkers(design) }
        if !state.draft.isEmpty {
            var object=RunObject(name:"Draft",nodes:state.draft,color:state.currentColor)
            if state.tool == .satin {object.digitizing=DigitizingSettings(kind:.satin)}
            if state.tool.drawsClosed {object.closed=true}
            if let shape=state.tool.draggedShape {object.holes=ShapeGeometry.holes(shape,around:state.draft,settings:Preferences.shared.shapes)}   // a frame shows its hole too
            for points in object.outlinePaths where !points.isEmpty {
                let line=NSBezierPath();line.move(to:screen(points[0]));for p in points.dropFirst(){line.line(to:screen(p))}
                (state.tool == .knife ? Theme.Canvas.handle : state.currentColor.nsColor).setStroke();line.lineWidth=2;line.stroke()   // a knife line isn't thread
            }
            for (index,node) in state.draft.enumerated() where !state.tool.dragsShape && !state.tool.freehand {   // a shape or stroke being dragged shows just its outline
                let p=screen(node.point);state.currentColor.nsColor.setFill();NSBezierPath(ovalIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)).fill()
                // Handles pulled out while tracing are shown so the curve's shape is easy to judge.
                for handle in [node.inHandle,node.outHandle].compactMap({$0}) {
                    let h=screen(handle),arm=NSBezierPath();arm.move(to:p);arm.line(to:h);Theme.Canvas.handle.setStroke();arm.lineWidth=1;arm.stroke()
                    let knob=NSBezierPath(ovalIn:CGRect(x:h.x-3.5,y:h.y-3.5,width:7,height:7));NSColor.white.setFill();knob.fill();Theme.Canvas.handle.setStroke();knob.stroke()
                }
                if state.tool == .satin {drawLabel("\(index/2+1)\(index%2==0 ? "L":"R")",at:CGPoint(x:p.x+5,y:p.y+5),size:9)}
            }
        }
        let hoopSize = Preferences.shared.unit.size(design.hoop.width, design.hoop.height, decimals: Preferences.shared.unit == .inches ? 1 : 0)
        if multi {
            drawHoopings(design)
            let count = design.multiHooping!.hoopings.count
            drawLabel("\(count) HOOPING\(count == 1 ? "" : "S")  ·  \(hoopSize) HOOP", at: CGPoint(x: area.minX, y: area.minY - 40), size: 10)
        } else {
            drawLabel(hoopSize + "  ·  SEWING AREA", at: CGPoint(x: hoop.minX, y: hoop.minY - 44), size: 10)
        }
        if state.tool == .measure, let line = measurement { drawMeasurement(line) }
        if state.tool == .stitchEdit { drawStitchEdit() }
        if state.tool == .addAngles, let start = state.angleStart { drawAngleLine(start, pointer); drawAngleReading(start, pointer, at: pointer) }   // the line being added follows the pointer
        // While a stitch angle line is dragged, its angle shows beside the pointer.
        // The line may be gone if the design changed under the drag (an undo while the mouse is held down).
        if let drag = angleDrag, let lines = (preview ?? state.design).objects.first(where: { $0.id == drag.object })?.settings.angleLines,
           lines.indices.contains(drag.index), lines[drag.index].count == 2 {
            let line = lines[drag.index]
            drawAngleReading(line[0], line[1], at: drag.end.map { line[$0] } ?? (line[0] + line[1]) * 0.5)
        }
        if let drag = fillAngleDrag, drag.slideFrom == nil, let object = (preview ?? state.design).objects.first(where: { $0.id == drag.object }),
           let ends = StitchAngleLine.ends(of: object) { drawAngleReading(ends.0, ends.1, at: drag.pointer) }
        // The route has no resize handles: they'd cover its numbers.
        if state.tool == .select && !state.hasVersionMismatch && !routeShown, let box = selectionBox(in: design) {
            drawResizeHandles(box, skew: state.skewHandles)
        }
        if let drag = turnDrag, drag.dx != 0 && drag.dy != 0 { drawPivot(screen((drag.low + drag.high) * 0.5)) }   // while rotating
        if state.tool == .node { for envelope in envelopes(in: design) { drawEnvelope(envelope.spec) } }
        if state.tool == .node { for letter in letterHandles(in: design) { drawLetterHandle(letter.point, active: letterDrag?.key == letter.key && letterDrag?.lettering == letter.lettering) } }
        if state.tool == .branch, let start = state.branchPoints.first { drawMarker(start, label: "Branch start", color: Theme.Canvas.entry) }
        if state.tool == .wreath { drawWreathPreview() }
        if state.tool == .paintStitches { drawStitchPaint() }
        if state.tool == .scatter { drawScatterPreview() }
        if let box = zoomBox ?? selectBox {
            let rect = NSBezierPath(rect: CGRect(x: min(box.start.x, box.end.x), y: min(box.start.y, box.end.y), width: abs(box.end.x - box.start.x), height: abs(box.end.y - box.start.y)))
            Theme.Canvas.handle.setStroke(); rect.lineWidth = 1; rect.setLineDash([4, 3], count: 2, phase: 0); rect.stroke()
        }
        if rulersShown { drawGuides(design.guides ?? []); drawRulers(context) }
        drawPanelDropHint()
        if design.objects.isEmpty && state.draft.isEmpty && design.artwork == nil {
            // The hint sits on the fabric, so dark cloth gets light text.
            let onDark = design.fabricColor.map { hex in Double((hex >> 16) & 255) * 0.299 + Double((hex >> 8) & 255) * 0.587 + Double(hex & 255) * 0.114 < 128 } ?? false
            let hint = onDark ? NSColor(white: 0.92, alpha: 0.85) : Theme.Canvas.label
            drawLabel("A new design starts with a line.", at: CGPoint(x: bounds.midX - 124, y: bounds.midY + 15), size: 17, color: hint)
            drawLabel("Press \(Preferences.shared.key(.runTool)) to digitize  ·  \(Preferences.shared.key(.importImage)) to import artwork", at: CGPoint(x: bounds.midX - 126, y: bounds.midY - 12), size: 12, color: hint)
        }
    }
    /// Edit Stitch: a press on a needle point selects it (Shift or ⌘ adds or removes it) and starts dragging the
    /// selection; Option-click on a stitch adds a needle point there; a press elsewhere starts a selection box.
    private func stitchEditDown(_ location: CGPoint, event: NSEvent) {
        let p = model(location), sections = state.stitchSections, reach = 6 / state.zoom
        let adding = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        defer { needsDisplay = true }
        if event.modifierFlags.contains(.option) { state.insertStitch(at: p, reach: reach); return }
        var best: (ref: StitchRef, distance: Double)?
        for (s, section) in sections.enumerated() {
            for (i, q) in section.points.enumerated() { let d = q.distance(to: p); if d <= reach, best == nil || d < best!.distance { best = (StitchRef(section: s, index: i), d) } }
        }
        guard let hit = best?.ref else {
            if !adding { state.selectedStitches = [] }
            stitchBox = (location, location); return
        }
        if adding { if state.selectedStitches.contains(hit) { state.selectedStitches.remove(hit) } else { state.selectedStitches.insert(hit) } }
        else if !state.selectedStitches.contains(hit) { state.selectedStitches = [hit] }
        if state.selectedStitches.contains(hit) { stitchDrag = (p, sections) }
    }
    /// Edit Stitch's view of its object: the stitches as thin lines and each needle point as a small square (orange
    /// when selected), plus the selection box while it's dragged.
    private func drawStitchEdit() {
        let sections = stitchPreview ?? state.stitchSections
        let lines = NSBezierPath(); lines.lineWidth = 1
        for section in sections where !section.points.isEmpty { lines.move(to: screen(section.points[0])); for p in section.points.dropFirst() { lines.line(to: screen(p)) } }
        Theme.Canvas.handle.withAlphaComponent(0.7).setStroke(); lines.stroke()
        let plain = NSBezierPath(), chosen = NSBezierPath()
        for (s, section) in sections.enumerated() {
            for (i, p) in section.points.enumerated() {
                let q = screen(p), square = CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)
                (state.selectedStitches.contains(StitchRef(section: s, index: i)) ? chosen : plain).appendRect(square)
            }
        }
        NSColor.white.setFill(); plain.fill(); Theme.Canvas.handle.setStroke(); plain.lineWidth = 1; plain.stroke()
        NSColor.systemOrange.setFill(); chosen.fill(); NSColor.black.setStroke(); chosen.lineWidth = 1; chosen.stroke()
        if let box = stitchBox {
            let rect = NSBezierPath(rect: CGRect(x: min(box.start.x, box.end.x), y: min(box.start.y, box.end.y), width: abs(box.end.x - box.start.x), height: abs(box.end.y - box.start.y)))
            Theme.Canvas.handle.setStroke(); rect.lineWidth = 1; rect.setLineDash([4, 3], count: 2, phase: 0); rect.stroke()
        }
    }
    /// Guide lines across the whole canvas. While one is dragged, its position (or "remove" over its ruler) shows
    /// beside the pointer.
    private func drawGuides(_ guides: [Guide]) {
        Theme.Canvas.guide.setStroke()
        for guide in guides {
            let line = NSBezierPath(), at = screen(Point(guide.position, guide.position))
            if guide.vertical { line.move(to: CGPoint(x: at.x, y: bounds.minY)); line.line(to: CGPoint(x: at.x, y: bounds.maxY)) }
            else { line.move(to: CGPoint(x: bounds.minX, y: at.y)); line.line(to: CGPoint(x: bounds.maxX, y: at.y)) }
            line.lineWidth = 1; line.stroke()
        }
        guard let drag = guideDrag, let guide = (preview?.guides ?? []).indices.contains(drag.index) ? preview?.guides?[drag.index] : nil else { return }
        let text = overOwnRuler(drag.pointer, vertical: drag.vertical) ? (drag.isNew ? "Let go to cancel" : "Let go to remove")
            : "\(guide.vertical ? "X" : "Y") \(Preferences.shared.unit.short(guide.position))"
        let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
        Theme.Canvas.ruler.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: CGRect(x: drag.pointer.x + 10, y: drag.pointer.y + 6, width: width + 12, height: 18), xRadius: 4, yRadius: 4).fill()
        drawLabel(text, at: CGPoint(x: drag.pointer.x + 16, y: drag.pointer.y + 7), size: 11)
    }
    /// True when `location` (on screen) is over the ruler a guide comes from: the left one for a vertical guide, the
    /// top one for a horizontal guide.
    private func overOwnRuler(_ location: CGPoint, vertical: Bool) -> Bool { vertical ? location.x <= 27 : location.y >= bounds.height - 23 }
    /// The guide within 4 points of `location` on screen, as its place in the design's guides.
    private func guide(near location: CGPoint) -> Int? {
        guard rulersShown else { return nil }   // hidden guides can't be grabbed
        return (state.design.guides ?? []).indices.first { index in
            let guide = state.design.guides![index], at = screen(Point(guide.position, guide.position))
            return abs(guide.vertical ? at.x - location.x : at.y - location.y) <= 4
        }
    }
    /// A stitch angle line: a thin line with a small square at each end.
    /// A selected line is drawn thicker, in orange.
    private func drawAngleLine(_ a: Point, _ b: Point, selected: Bool = false) {
        let p = screen(a), q = screen(b), line = NSBezierPath(); line.move(to: p); line.line(to: q)
        // A white edge under the line keeps it visible on dark thread.
        NSColor.white.withAlphaComponent(0.85).setStroke(); line.lineWidth = selected ? 4.5 : 3.2; line.stroke()
        (selected ? NSColor.systemOrange : Theme.Canvas.handle).setStroke(); line.lineWidth = selected ? 2.5 : 1.2; line.stroke()
        for end in [p, q] {
            let knob = NSBezierPath(rect: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8))
            Theme.Canvas.exit.setFill(); knob.fill(); Theme.Canvas.handle.setStroke(); knob.lineWidth = 1; knob.stroke()
        }
    }
    /// A stitch angle line's direction, in degrees from 0 to 179 counted counterclockwise from pointing right (as the
    /// fill's Angle is), on a light backing next to `point`.
    private func drawAngleReading(_ a: Point, _ b: Point, at point: Point) {
        guard a.distance(to: b) > 0.01 else { return }
        let degrees = Int((atan2(b.y - a.y, b.x - a.x) * 180 / .pi + 360).rounded()) % 180   // a line points both ways, so 180° is 0°
        let text = "\(degrees)°", p = screen(point)
        let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
        Theme.Canvas.ruler.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: CGRect(x: p.x + 10, y: p.y + 6, width: width + 12, height: 18), xRadius: 4, yRadius: 4).fill()
        drawLabel(text, at: CGPoint(x: p.x + 16, y: p.y + 7), size: 11)
    }
    /// The Measure tool's line: small cross ticks at each end, and the distance and angle on a light backing.
    private func drawMeasurement(_ line: (start: Point, end: Point)) {
        let a = screen(line.start), b = screen(line.end)
        let path = NSBezierPath(); path.move(to: a); path.line(to: b)
        for p in [a, b] { path.move(to: CGPoint(x: p.x - 5, y: p.y)); path.line(to: CGPoint(x: p.x + 5, y: p.y)); path.move(to: CGPoint(x: p.x, y: p.y - 5)); path.line(to: CGPoint(x: p.x, y: p.y + 5)) }
        Theme.Canvas.handle.setStroke(); path.lineWidth = 1.5; path.stroke()
        let text = Self.measurementText(from: line.start, to: line.end, unit: Preferences.shared.unit)
        let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
        Theme.Canvas.ruler.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: CGRect(x: b.x + 10, y: b.y + 6, width: width + 12, height: 18), xRadius: 4, yRadius: 4).fill()
        drawLabel(text, at: CGPoint(x: b.x + 16, y: b.y + 7), size: 11)
    }
    /// Faint crossing threads so the hoop reads as cloth. Spaced in screen points, so the texture stays fine at any zoom.
    /// Threads of a picked fabric: a little darker than the cloth, or a little lighter on dark cloth.
    private func weaveColor(for fabric: NSColor) -> NSColor {
        let c = fabric.usingColorSpace(.sRGB) ?? fabric
        let light = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.5
        return c.blended(withFraction: light ? 0.08 : 0.10, of: light ? .black : .white) ?? c
    }
    private func drawWeave(in cloth: NSBezierPath, color: NSColor, context: CGContext) {
        let area = cloth.bounds.intersection(bounds)
        guard !area.isNull else { return }
        context.saveGState(); context.addPath(cloth.cgPathCopy); context.clip()
        context.setStrokeColor(color.cgColor); context.setLineWidth(0.6)
        for x in stride(from: area.minX, through: area.maxX, by: 3) { context.move(to: CGPoint(x: x, y: area.minY)); context.addLine(to: CGPoint(x: x, y: area.maxY)) }
        for y in stride(from: area.minY, through: area.maxY, by: 3) { context.move(to: CGPoint(x: area.minX, y: y)); context.addLine(to: CGPoint(x: area.maxX, y: y)) }
        context.strokePath(); context.restoreGState()
    }
    /// A small labeled dot showing where the selected object starts or ends sewing.
    /// The density map worked out for the stitches of one compiled revision (worked out again only when they change).
    private var densityCache: (revision: Int, cells: [(corner: Point, level: DensityMap.Level)])?
    /// The density map over the stitches: each heavy 1 mm square tinted yellow and each too-dense one red.
    private func drawDensityMap(_ context: CGContext) {
        if densityCache?.revision != state.compiledRevision { densityCache = (state.compiledRevision, DensityMap.cells(state.plan)) }
        for cell in densityCache?.cells ?? [] {
            let a = screen(cell.corner), b = screen(cell.corner + Point(1, 1))
            context.setFillColor((cell.level == .tooDense ? NSColor.systemRed : NSColor.systemYellow).withAlphaComponent(0.5).cgColor)
            context.fill(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
        }
    }
    /// Up to this many selected objects show where they start and end even without points set (more would crowd the
    /// canvas, as when a whole word is selected); points that were set always show.
    static let fewForMarkers = 10
    /// Where each selected object's stitches really begin and end, read from the stitch plan.
    private func sewnEnds() -> [UUID: (first: Point, last: Point)] {
        var ends: [UUID: (first: Point, last: Point)] = [:]
        for command in state.plan.commands where command.op == .stitch {
            guard let id = command.objectID, state.selection.contains(id) else { continue }
            ends[id] = (ends[id]?.first ?? command.point, command.point)
        }
        return ends
    }
    /// Where a selected object's Start and End markers go: where its stitches really begin and end (from `sewn`), or
    /// where a point was set when the stitches aren't worked out yet or that marker is being dragged. With many
    /// objects selected (`few` false), only points that were set.
    private func markerPoints(_ object: RunObject, sewn: [UUID: (first: Point, last: Point)], few: Bool) -> (start: Point?, end: Point?) {
        let dragging = draggedMarker?.object == object.id ? draggedMarker?.kind : nil
        let set = (start: object.entry, end: object.exit.map { object.sewnEnd ?? $0 })
        var ends = set
        if dragging == nil, let real = sewn[object.id] { ends = (object.entry != nil || few ? real.first : nil, object.exit != nil || few ? real.last : nil) }
        // Lettering is one object: it shows where its first letter starts and its last letter ends.
        if let id = object.lettering?.id {
            let parts = state.design.letteringObjects(id)
            return (object.id == parts.first?.id ? ends.start : nil, object.id == parts.last?.id ? ends.end : nil)
        }
        return ends
    }
    /// True when few enough objects are selected for every one to show where it starts and ends (lettering counts
    /// as one).
    private func fewSelected(in design: Design) -> Bool {
        let chosen = design.objects.filter { state.selection.contains($0.id) }
        return chosen.filter { $0.lettering == nil }.count + Set(chosen.compactMap { $0.lettering?.id }).count <= Self.fewForMarkers
    }
    /// True for the tools that show a selected object's Start and End markers: Edit Nodes and the Start & End tool.
    static func showsEnds(_ tool: Tool) -> Bool { tool == .node || tool == .entryExit }
    /// The start marker: a green crosshair, a small ring with four arms straight out (+).
    private func drawStartMarker(_ point: Point?) { drawCrosshair(point, color: Theme.Canvas.startMarker, diagonal: false) }
    /// The end marker: a red crosshair with its arms turned to a cross (×).
    private func drawEndMarker(_ point: Point?) { drawCrosshair(point, color: Theme.Canvas.endMarker, diagonal: true) }
    /// A crosshair on `point`, like a needle's aim: a ring with four arms, open in the middle so the exact stitch
    /// shows through. A white edge under the color keeps it clear on any thread, light or dark. Start and end tell
    /// themselves apart by color and by the arms' angle, so they need no label.
    private func drawCrosshair(_ point: Point?, color: NSColor, diagonal: Bool) {
        guard let point else { return }
        let p = screen(point), ring = NSBezierPath(ovalIn: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11))
        let unit: CGFloat = diagonal ? 0.75 : 1   // diagonal arms are shortened so they reach about as far as straight ones
        let directions: [(CGFloat, CGFloat)] = diagonal ? [(1, 1), (-1, 1), (1, -1), (-1, -1)] : [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let arms = NSBezierPath()
        for (dx, dy) in directions {
            arms.move(to: CGPoint(x: p.x + dx * unit * 2.5, y: p.y + dy * unit * 2.5)); arms.line(to: CGPoint(x: p.x + dx * unit * 8, y: p.y + dy * unit * 8))
        }
        arms.lineCapStyle = .round
        // All the white edges first, then all the color on top, so no white edge cuts across a colored arm.
        NSColor.white.setStroke(); ring.lineWidth = 4; ring.stroke(); arms.lineWidth = 5; arms.stroke()
        color.setStroke(); ring.lineWidth = 2; ring.stroke(); arms.lineWidth = 2.5; arms.stroke()
    }
    /// The selection's box on screen: around every selected, shown, unlocked object's outline. Nil when nothing
    /// that can be resized is selected.
    private func selectionBox(in design: Design) -> CGRect? {
        let points = design.objects.filter { state.selection.contains($0.id) && !$0.locked && state.isShown($0) }.flatMap { $0.outlinePaths.flatMap { $0 } }
        guard let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max() else { return nil }
        let a = screen(Point(x0, y0)), b = screen(Point(x1, y1))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    /// The 8 resize handles round `box` (on screen), a few points outside it: the corners and the middle of each side,
    /// with which sides each moves (-1 left/bottom, 1 right/top, 0 neither). A side too short for three handles has
    /// just its corners.
    private func resizeHandles(_ box: CGRect) -> [(point: CGPoint, dx: Int, dy: Int)] {
        let gap: CGFloat = 6
        var handles: [(point: CGPoint, dx: Int, dy: Int)] = []
        for dx in -1...1 { for dy in -1...1 where dx != 0 || dy != 0 {
            if (dx == 0 && box.width < 24) || (dy == 0 && box.height < 24) { continue }
            let x = dx < 0 ? box.minX - gap : dx > 0 ? box.maxX + gap : box.midX, y = dy < 0 ? box.minY - gap : dy > 0 ? box.maxY + gap : box.midY
            handles.append((CGPoint(x: x, y: y), dx, dy))
        } }
        return handles
    }
    /// The handle of each letter of the selected, unlocked lettering (on screen, below the middle of the letter), with
    /// the lettering, the letter key and the letter's parts. Lettering saved before letters had keys (one line only)
    /// is split into letters by its parts' names: a part named "… (part 2)" or later belongs to the letter before.
    /// Keys then count letters the way the fonts do: embroidery fonts count each letter placed, Mac fonts every
    /// character, spaces included.
    private func letterHandles(in design: Design) -> [(point: CGPoint, lettering: UUID, key: Int, parts: Set<UUID>)] {
        var handles: [(point: CGPoint, lettering: UUID, key: Int, parts: Set<UUID>)] = []
        let chosen = design.objects.filter { state.selection.contains($0.id) && !$0.locked && $0.visible && $0.lettering != nil }
        for id in Set(chosen.compactMap { $0.lettering?.id }) {
            let parts = design.letteringObjects(id)
            guard let spec = parts.first?.lettering, parts.allSatisfy({ $0.letterKey != nil }) || spec.lines.count == 1 else { continue }
            // For older lettering: where each letter that has stitches sits in the text, for Mac fonts' keys.
            let places = Array(spec.lines.first ?? "").enumerated().filter { !$0.element.isWhitespace }.map(\.offset)
            var letters: [(key: Int, objects: [RunObject])] = [], counted = -1
            for object in parts {
                let continues = object.name.contains(" (part ") && !object.name.contains(" (part 1)")
                if object.letterKey == nil && !continues { counted += 1 }
                let key = object.letterKey ?? (spec.fontKind == .system ? (places.indices.contains(counted) ? places[counted] : counted) : counted)
                if let index = letters.firstIndex(where: { $0.key == key }) { letters[index].objects.append(object) } else { letters.append((key, [object])) }
            }
            for letter in letters {
                let points = letter.objects.flatMap { $0.outlinePaths.flatMap { $0 } }
                guard let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min() else { continue }
                let p = screen(Point((x0 + x1) / 2, y0))
                handles.append((CGPoint(x: p.x, y: p.y - 8), id, letter.key, Set(letter.objects.map(\.id))))
            }
        }
        return handles
    }
    /// The selected, unlocked straight lettering that has an envelope, each once (its first letter's recipe).
    private func envelopes(in design: Design) -> [(id: UUID, spec: LetteringSpec)] {
        var seen = Set<UUID>(), found: [(id: UUID, spec: LetteringSpec)] = []
        for object in design.objects where state.selection.contains(object.id) && !object.locked && object.visible {
            guard let spec = object.lettering, spec.shape == .straight, spec.envelope?.box?.count == 2, seen.insert(spec.id).inserted else { continue }
            found.append((spec.id, spec))
        }
        return found
    }
    /// Where a point of the lettering's own frame (mm, as it was built) is on the design: placed by its markers, as the
    /// letters were.
    private func placed(_ p: Point, _ spec: LetteringSpec) -> Point {
        spec.anchor + (spec.alongMarker - spec.anchor) * (p.x / 10) + (spec.upMarker - spec.anchor) * (p.y / 10)
    }
    /// The reverse of `placed`: where a design point is in the lettering's own frame.
    private func unplaced(_ q: Point, _ spec: LetteringSpec) -> Point {
        let a = (spec.alongMarker - spec.anchor) * 0.1, b = (spec.upMarker - spec.anchor) * 0.1, d = q - spec.anchor
        let det = a.x * b.y - a.y * b.x
        guard abs(det) > 1e-12 else { return Point(0, 0) }
        return Point((d.x * b.y - d.y * b.x) / det, (a.x * d.y - a.y * d.x) / det)
    }
    /// The recipe with the dragged envelope handle under the pointer at `target` (only up and down, or for Perspective
    /// only sideways). Shift moves its partner the opposite way, ⌘ the same way. Moves stay within the allowed range.
    private func bentEnvelope(_ drag: (spec: LetteringSpec, handle: EnvelopeHandle), to target: Point, flags: NSEvent.ModifierFlags) -> LetteringSpec? {
        guard var envelope = drag.spec.envelope, let box = envelope.box, box.count == 2, drag.spec.height > 0 else { return nil }
        var still = envelope; still.setMove(drag.handle, 0)
        let base = still.spot(drag.handle, low: box[0], high: box[1], height: drag.spec.height), here = unplaced(target, drag.spec)
        let moved = (envelope.kind.slides ? here.x - base.x : here.y - base.y) / drag.spec.height
        let clamp = { (value: Double) in min(max(value, LetteringEnvelope.moves.lowerBound), LetteringEnvelope.moves.upperBound) }
        let change = clamp(moved) - envelope.move(drag.handle)
        envelope.setMove(drag.handle, clamp(moved))
        let partner = envelope.kind.partner(of: drag.handle)
        if flags.contains(.shift) { envelope.setMove(partner, clamp(envelope.move(partner) - change)) }
        else if flags.contains(.command) { envelope.setMove(partner, clamp(envelope.move(partner) + change)) }
        var spec = drag.spec; spec.envelope = envelope
        return spec
    }
    /// Each of the lettering's envelope handles, on screen.
    private func envelopeHandles(_ spec: LetteringSpec) -> [(handle: EnvelopeHandle, point: CGPoint)] {
        guard let envelope = spec.envelope, let box = envelope.box, box.count == 2 else { return [] }
        return envelope.kind.handles.map { ($0, screen(placed(envelope.spot($0, low: box[0], high: box[1], height: spec.height), spec))) }
    }
    /// An envelope: its bent box as a thin dashed outline, and its handles as small rings.
    private func drawEnvelope(_ spec: LetteringSpec) {
        guard let envelope = spec.envelope, let box = envelope.box, box.count == 2 else { return }
        let steps = 32
        func edge(_ top: Bool) -> [CGPoint] { (0...steps).map { screen(placed(envelope.warp(Point(box[0].x + (box[1].x - box[0].x) * Double($0) / Double(steps), top ? box[1].y : box[0].y), low: box[0], high: box[1], height: spec.height), spec)) } }
        let top = edge(true), bottom = edge(false)
        let outline = NSBezierPath(); outline.move(to: top[0])
        for p in top.dropFirst() { outline.line(to: p) }
        for p in bottom.reversed() { outline.line(to: p) }
        outline.close()
        Theme.Canvas.selection.setStroke(); outline.lineWidth = 1; outline.setLineDash([4, 3], count: 2, phase: 0); outline.stroke()
        for (handle, p) in envelopeHandles(spec) {
            let ring = NSBezierPath(ovalIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
            (envelopeDrag?.spec.id == spec.id && envelopeDrag?.handle == handle ? Theme.Canvas.selection : NSColor.white).setFill(); ring.fill()
            Theme.Canvas.selection.setStroke(); ring.lineWidth = 1.5; ring.stroke()
        }
    }
    /// A letter's handle: a small diamond in the accent color (filled while it's being dragged).
    private func drawLetterHandle(_ p: CGPoint, active: Bool) {
        let diamond = NSBezierPath()
        diamond.move(to: CGPoint(x: p.x, y: p.y + 5)); diamond.line(to: CGPoint(x: p.x + 5, y: p.y)); diamond.line(to: CGPoint(x: p.x, y: p.y - 5)); diamond.line(to: CGPoint(x: p.x - 5, y: p.y)); diamond.close()
        (active ? Theme.Canvas.selection : NSColor.white).setFill(); diamond.fill()
        Theme.Canvas.selection.setStroke(); diamond.lineWidth = 1.5; diamond.stroke()
    }
    /// The resize handles: small dark squares with a white edge, so they show on any thread or fabric. With `skew`,
    /// the ones on the sides are skew diamonds instead.
    private func drawResizeHandles(_ box: CGRect, skew: Bool = false) {
        for handle in resizeHandles(box) {
            if skew && (handle.dx == 0 || handle.dy == 0) { drawSkewHandle(handle.point); continue }
            let square = NSBezierPath(rect: CGRect(x: handle.point.x - 3.5, y: handle.point.y - 3.5, width: 7, height: 7))
            NSColor(white: 0.2, alpha: 1).setFill(); square.fill(); NSColor.white.setStroke(); square.lineWidth = 1; square.stroke()
        }
    }
    /// The point something turns around while it's rotated: a ring and cross, with a white edge so it shows on
    /// dark thread.
    private func drawPivot(_ c: CGPoint) {
        let pivot = NSBezierPath(ovalIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
        pivot.move(to: CGPoint(x: c.x - 7, y: c.y)); pivot.line(to: CGPoint(x: c.x + 7, y: c.y))
        pivot.move(to: CGPoint(x: c.x, y: c.y - 7)); pivot.line(to: CGPoint(x: c.x, y: c.y + 7))
        NSColor.white.setStroke(); pivot.lineWidth = 3; pivot.stroke()
        NSColor(white: 0.2, alpha: 1).setStroke(); pivot.lineWidth = 1.2; pivot.stroke()
    }
    /// A skew handle: a diamond, white with a dark edge.
    private func drawSkewHandle(_ p: CGPoint, color: NSColor = NSColor(white: 0.2, alpha: 1)) {
        let shape = NSBezierPath()
        shape.move(to: CGPoint(x: p.x, y: p.y + 5)); shape.line(to: CGPoint(x: p.x + 5, y: p.y)); shape.line(to: CGPoint(x: p.x, y: p.y - 5)); shape.line(to: CGPoint(x: p.x - 5, y: p.y)); shape.close()
        NSColor.white.setFill(); shape.fill(); color.setStroke(); shape.lineWidth = 1.5; shape.stroke()
    }
    /// Which corner of the selection the pointer is just outside, where a drag rotates: within 22 points of a corner
    /// handle but not on it, and not over the selection's box. Nil anywhere else, or when nothing can be rotated.
    /// While ↻ shows, the zone holds on 4 points further out and 3 points into the box (see `handleReach`).
    private func rotateCorner(at location: CGPoint) -> (dx: Int, dy: Int)? {
        let holding = shownHandleCursor === HandleCursor.rotate
        guard state.tool == .select, !state.hasVersionMismatch, !routeShown, let box = selectionBox(in: state.design),
              !(holding ? box.insetBy(dx: 3, dy: 3) : box).contains(location) else { return nil }
        let reach = handleReach, outer: CGFloat = holding ? 26 : 22
        return resizeHandles(box).first { handle in
            let distance = hypot(handle.point.x - location.x, handle.point.y - location.y)
            return handle.dx != 0 && handle.dy != 0 && distance > reach && distance <= outer
        }.map { ($0.dx, $0.dy) }
    }
    /// The pointer for the handle under `location` with Select, showing what a drag there does: a curved double
    /// arrow just outside a corner (rotate), a diagonal arrow on a corner square (resize), ↔ or ↕ on a side square
    /// (stretch) or ⇄ on a skew diamond. Nil anywhere else.
    func handleCursor(at location: CGPoint) -> NSCursor? {
        if state.tool == .artwork { return artworkHandleCursor(at: location) }
        guard state.tool == .select, !state.hasVersionMismatch, !routeShown, let box = selectionBox(in: state.design) else { return nil }
        let reach = handleReach
        if let handle = resizeHandles(box).first(where: { hypot($0.point.x - location.x, $0.point.y - location.y) <= reach }) {
            if handle.dx != 0 && handle.dy != 0 { return HandleCursor.diagonal(rising: handle.dx == handle.dy) }
            if state.skewHandles { return handle.dy != 0 ? HandleCursor.skewSideways : HandleCursor.skewUpDown }
            return handle.dx != 0 ? .resizeLeftRight : .resizeUpDown
        }
        return rotateCorner(at: location) != nil ? HandleCursor.rotate : nil
    }
    /// The same for the reference image with Move & Size Artwork. Its corners and sides turn with it, so a corner's
    /// arrow follows which way the corner lies from the middle, and a side's ⇄ or ⇅ which way the side runs.
    private func artworkHandleCursor(at location: CGPoint) -> NSCursor? {
        guard let artwork = state.design.artwork, artwork.visible, !state.croppingArtwork else { return nil }   // cropping shows no handles
        let corners = artwork.corners.map(screen), middle = screen(artwork.center)
        let reach = artworkHandleReach
        func near(_ p: CGPoint) -> Bool { hypot(p.x - location.x, p.y - location.y) <= reach }
        if let corner = corners.first(where: near) { return HandleCursor.diagonal(rising: (corner.x - middle.x) * (corner.y - middle.y) > 0) }
        if state.artworkSkewHandles, let side = artworkSideHandles(artwork).firstIndex(where: near) {
            let a = corners[side], b = corners[(side + 1) % 4]
            return abs(b.x - a.x) >= abs(b.y - a.y) ? HandleCursor.skewSideways : HandleCursor.skewUpDown
        }
        return artworkRotateCorner(at: location) != nil ? HandleCursor.rotate : nil
    }
    /// Shows the handle's pointer while the pointer is over one, and the tool's pointer again once it moves off.
    private func updateHandleCursor(at location: CGPoint) {
        guard turnDrag == nil, resizeDrag == nil, artworkTurnDrag == nil, artworkDrag == nil else { return }   // during a drag the pointer stays what it was
        let cursor = handleCursor(at: location)
        guard cursor !== shownHandleCursor else { return }
        shownHandleCursor = cursor
        showWantedCursor()
    }
    /// While reviewing: the way from where the step before ended (a faint ×) to this step's start, dashed, with what
    /// happens on the way beside it, such as "Trim, then 18.6 mm".
    private func drawTravel(_ travel: SewingTravel, to start: Point, warned: Bool) {
        let color = warned ? Theme.Canvas.exit : Theme.Canvas.handle   // terracotta for a move worth a second look
        let a = screen(travel.from), b = screen(start)
        let line = NSBezierPath(); line.move(to: a); line.line(to: b); line.lineCapStyle = .round
        Theme.Canvas.ruler.withAlphaComponent(0.7).setStroke(); line.lineWidth = 3.5; line.stroke()   // keeps it clear on any thread, light or dark
        color.setStroke(); line.lineWidth = warned ? 2 : 1.5; line.setLineDash([5, 4], count: 2, phase: 0); line.stroke()
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current?.cgContext.setAlpha(0.5)
        drawEndMarker(travel.from)
        NSGraphicsContext.restoreGraphicsState()
        // The label sits beside the line's middle, on a light backing like the other canvas labels.
        let text = travel.summary(unit: Preferences.shared.unit), width = labelWidth(text, size: 11)
        let middle = CGPoint(x: (a.x + b.x) / 2 + 10, y: (a.y + b.y) / 2 - 9)
        Theme.Canvas.ruler.withAlphaComponent(0.92).setFill()
        let backing = NSBezierPath(roundedRect: CGRect(x: middle.x, y: middle.y, width: width + 12, height: 18), xRadius: 9, yRadius: 9)
        backing.fill(); color.setStroke(); backing.lineWidth = 0.75; backing.stroke()
        drawLabel(text, at: CGPoint(x: middle.x + 6, y: middle.y + 2), size: 11, color: color)
    }
    /// True while Review shows the whole route.
    private var routeShown: Bool { state.reviewing && state.reviewShowsRoute }
    /// How big a route badge is (its radius, in points on screen).
    static let routeBadgeRadius: CGFloat = 9
    /// Where the route's numbered badges go: on each step's start (`starts`, on screen) unless that would cover a badge
    /// already placed. Then it tries places round the start, first straight out from the middle of all the starts,
    /// then turning a twelfth of the way round at a time, a little farther out on each ring, and takes the first
    /// clear one. (If none is clear in six rings, it stays on its start.)
    static func routeBadges(_ starts: [CGPoint], radius: CGFloat = routeBadgeRadius) -> [CGPoint] {
        guard !starts.isEmpty else { return [] }
        let middle = CGPoint(x: starts.map(\.x).reduce(0, +) / CGFloat(starts.count), y: starts.map(\.y).reduce(0, +) / CGFloat(starts.count))
        var badges: [CGPoint] = []
        func isClear(_ spot: CGPoint) -> Bool { !badges.contains { hypot($0.x - spot.x, $0.y - spot.y) < radius * 2 + 2 } }
        for start in starts {
            let outward = start == middle ? CGFloat.pi / 2 : atan2(start.y - middle.y, start.x - middle.x)
            let rings = (1...6).lazy.flatMap { ring in (0..<12).lazy.map { turn -> CGPoint in
                // Turns alternate sides (0, +1, -1, +2, -2…) so the badge stays as near to straight out as it can.
                let angle = outward + CGFloat((turn + 1) / 2) * (turn % 2 == 0 ? -1 : 1) * .pi / 6, distance = CGFloat(ring) * radius * 1.3
                return CGPoint(x: start.x + cos(angle) * distance, y: start.y + sin(angle) * distance)
            } }
            badges.append(isClear(start) ? start : rings.first(where: isClear) ?? start)
        }
        return badges
    }
    /// Review's route: from each step's end, an arrow to where the next step starts (dashed for a trim, dotted for a
    /// thread change, a thin line for a jump that isn't trimmed; a thread carried straight on has none), and each
    /// step's number in a badge at its start. A badge moved aside has a short line back to its start, marked with a
    /// green dot. The step being looked at has a bigger badge. Moves with a warning, and their steps' badges, are
    /// terracotta.
    private func drawRoute(_ steps: [SewingStep], current: Int?) {
        let radius = Self.routeBadgeRadius, starts = steps.map { screen($0.start) }, badges = Self.routeBadges(starts)
        let warnings = state.sewingWarnings
        for (index, step) in steps.enumerated() {
            guard let travel = step.travel, travel.trimmed || travel.jumped || travel.colorChange else { continue }
            let a = screen(travel.from), b = starts[index], length = hypot(b.x - a.x, b.y - a.y)
            // The arrow stops at the badge's edge, or just short of the start's dot when the badge moved aside.
            let gap = badges[index] == b ? radius + 2 : 4
            guard length > gap + 6 else { continue }
            let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length, tip = CGPoint(x: b.x - ux * gap, y: b.y - uy * gap)
            let line = NSBezierPath(); line.move(to: a); line.line(to: tip); line.lineCapStyle = .round
            Theme.Canvas.ruler.withAlphaComponent(0.6).setStroke(); line.lineWidth = 3; line.stroke()   // keeps it clear on any thread, light or dark
            let warned = warnings[index] != nil
            let color = warned ? Theme.Canvas.exit : travel.colorChange ? Theme.Canvas.label : Theme.Canvas.handle
            color.setStroke(); color.setFill()
            line.lineWidth = (travel.colorChange ? 1.4 : travel.trimmed ? 1.5 : 1) + (warned ? 0.8 : 0)
            if travel.colorChange { line.setLineDash([1, 3.5], count: 2, phase: 0) } else if travel.trimmed { line.setLineDash([5, 3], count: 2, phase: 0) }
            line.stroke()
            let head = NSBezierPath(); head.move(to: tip)
            head.line(to: CGPoint(x: tip.x - ux * 7 - uy * 3.5, y: tip.y - uy * 7 + ux * 3.5))
            head.line(to: CGPoint(x: tip.x - ux * 7 + uy * 3.5, y: tip.y - uy * 7 - ux * 3.5)); head.close(); head.fill()
        }
        for (index, (start, spot)) in zip(starts, badges).enumerated() {
            if spot != start {
                let leader = NSBezierPath(); leader.move(to: start); leader.line(to: spot)
                Theme.Canvas.handle.setStroke(); leader.lineWidth = 1; leader.stroke()
                Theme.Canvas.startMarker.setFill(); NSBezierPath(ovalIn: CGRect(x: start.x - 2.5, y: start.y - 2.5, width: 5, height: 5)).fill()
            }
            let size = index == current ? radius + 3 : radius
            let badge = NSBezierPath(ovalIn: CGRect(x: spot.x - size, y: spot.y - size, width: size * 2, height: size * 2))
            // Denim (or terracotta, warned) in light and dark alike, so the white number always reads.
            Theme.fixed(warnings[index] == nil ? 0x34507A : 0xB0532F).setFill(); badge.fill()
            NSColor.white.setStroke(); badge.lineWidth = index == current ? 2.5 : 1.5; badge.stroke()
            let number = NSAttributedString(string: "\(index + 1)", attributes: [.font: NSFont.systemFont(ofSize: index == current ? 11 : 9.5, weight: .bold), .foregroundColor: NSColor.white])
            number.draw(at: CGPoint(x: spot.x - number.size().width / 2, y: spot.y - number.size().height / 2))
        }
    }
    /// Wreath: the copies it would add, as dashed outlines, and its center.
    private func drawWreathPreview() {
        guard let center = state.wreathCenter else { return }
        if let preview = state.wreathPreview {
            let made = Set(state.design.objects.map(\.id))
            for object in preview.objects where !made.contains(object.id) {
                for points in object.outlinePaths where points.count >= 2 {
                    let line = NSBezierPath(); line.move(to: screen(points[0])); for p in points.dropFirst() { line.line(to: screen(p)) }
                    object.color.nsColor.withAlphaComponent(0.7).setStroke(); line.lineWidth = 1.5; line.setLineDash([4, 3], count: 2, phase: 0); line.stroke()
                }
            }
        }
        drawMarker(center, label: "Center", color: Theme.Canvas.handle)
    }
    /// Paint Stitches: each traced part tinted by the stitch it will get (Leave out: just a dashed outline), so the
    /// picture underneath reads like a paint-by-numbers sheet.
    private func drawStitchPaint() {
        guard let trace = state.stitchPaint else { return }
        for (index, patch) in trace.patches.enumerated() {
            let path = NSBezierPath(); path.windingRule = .evenOdd
            for ring in patch.region where ring.count >= 3 {
                path.move(to: screen(ring[0])); for p in ring.dropFirst() { path.line(to: screen(p)) }; path.close()
            }
            let stitch = state.paintedStitch(index)
            if stitch != .leaveOut { stitch.tint.withAlphaComponent(0.5).setFill(); path.fill() }
            stitch.tint.setStroke(); path.lineWidth = state.paintChoices[index] == nil ? 1 : 2   // set by hand: a bolder edge
            if stitch == .leaveOut { path.setLineDash([4, 3], count: 2, phase: 0) }
            path.stroke()
        }
    }
    /// Scatter's copies as dashed outlines in their thread colors, where Apply would put them.
    private func drawScatterPreview() {
        guard let preview = state.scatterPreview?.design else { return }
        let made = Set(state.design.objects.map(\.id))
        for object in preview.objects where !made.contains(object.id) {
            for points in object.outlinePaths where points.count >= 2 {
                let line = NSBezierPath(); line.move(to: screen(points[0])); for p in points.dropFirst() { line.line(to: screen(p)) }
                object.color.nsColor.withAlphaComponent(0.7).setStroke(); line.lineWidth = 1.5; line.setLineDash([4, 3], count: 2, phase: 0); line.stroke()
            }
        }
    }
    private func drawMarker(_ point: Point?, label: String, color: NSColor) {
        guard let point else { return }
        let p = screen(point), dot = NSBezierPath(ovalIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        color.setFill(); dot.fill(); NSColor.white.setStroke(); dot.lineWidth = 2; dot.stroke()
        // A light backing keeps the label readable on top of dark stitches.
        let width = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium)]).width
        Theme.Canvas.ruler.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: CGRect(x: p.x + 8, y: p.y - 8, width: width + 8, height: 15), xRadius: 4, yRadius: 4).fill()
        drawLabel(label, at: CGPoint(x: p.x + 12, y: p.y - 7), size: 10)
    }
    /// With the Start & End tool: sets where the single selected object starts (or, with Option, ends) sewing.
    /// If nothing suitable is selected, the click selects the object under the pointer first.
    private func setEntryOrExit(at point: Point, exit: Bool) {
        // One object selected: the click places its point. Several (such as the parts of a laydown or a word, which are
        // grouped): the click places the point of the selected part under the pointer, even one lying under other
        // objects, and selects just that part.
        let target = state.selection.count == 1 ? state.selected : state.selection.count > 1 ? hit(point, among: state.selection) : nil
        // Lettering is one object: its start goes on its first letter and its end on its last, wherever the click.
        if let spec = state.selectedLettering ?? target?.lettering, !state.design.letteringObjects(spec.id).contains(where: \.locked) {
            state.edit(exit ? "Set End Point" : "Set Start Point") { design in if exit { design.setLetteringEnd(spec.id, point) } else { design.setLetteringStart(spec.id, point) } }
            state.selection = Set(state.design.letteringObjects(spec.id).map(\.id))
            state.status = exit ? "End point set: the lettering finishes on its last letter, at the nearest place to it."
                                : "Start point set: the lettering starts on its first letter, at the nearest place to it. Option-click to set where it ends."
        } else if let object = target, object.kind != .raw, object.kind != .vector, !object.locked {
            state.selection = [object.id]
            state.editSelected(exit ? "Set End Point" : "Set Start Point") { if exit { $0.exit = point } else { $0.entry = point } }
            state.status = exit ? "End point set: the stitching finishes there." : "Start point set. Option-click to set where it ends."
        } else if let object = hit(point) {
            // Just this object, not its whole group: start and end points belong to one object at a time.
            state.select(object.id, single: true)
            state.status = object.kind == .raw ? "Imported stitches keep their own sewing order." : "Now click where \(object.name) should start sewing."
        } else { state.status = "Select one object, then click where it should start sewing." }
    }
    // Redraw with the other palette as soon as the Mac switches between light and dark mode.
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    private func drawLabel(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor = Theme.Canvas.label) {
        (text as NSString).draw(at: point, withAttributes: [.font: labelFont(size), .foregroundColor: color])
    }
    /// The rounded font canvas labels use.
    private func labelFont(_ size: CGFloat) -> NSFont {
        let rounded = NSFont.systemFont(ofSize: size, weight: .medium).fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
        return rounded ?? NSFont.systemFont(ofSize: size, weight: .medium)
    }
    /// How wide a label drawn by `drawLabel` is, in points.
    private func labelWidth(_ text: String, size: CGFloat) -> CGFloat { (text as NSString).size(withAttributes: [.font: labelFont(size)]).width }
    /// An inch ruler's label for a position in mm, e.g. "1.5". Labels fall on whole and half inches, so the position is
    /// rounded to the nearest half first: adding up steps leaves tiny errors, and one just below zero would read "-0".
    static func inchRulerLabel(_ millimeters: Double) -> String {
        let halves = (LengthUnit.inches.shown(millimeters) * 2).rounded()
        let inches = halves == 0 ? 0 : halves / 2   // rounding -0.0000001 gives -0, which would print with its minus sign
        return inches.formatted(.number.precision(.fractionLength(0...1)))
    }
    /// True when the rulers and guides are shown (View › Show Rulers & Guides).
    var rulersShown: Bool { Preferences.shared.showsRulers }
    /// Puts the rulers' pointer marks at `location` (on screen), or hides them for nil, with the rulers off, or with
    /// the marks switched off in Settings. Each hides while the pointer is over the other ruler, so the corner where
    /// the rulers meet stays clear.
    private func moveRulerMarks(to location: CGPoint?) {
        guard let location, rulersShown, Preferences.shared.showsPointerMarks else { topRulerMark.isHidden = true; leftRulerMark.isHidden = true; return }
        topRulerMark.frame = CGRect(x: location.x.rounded() - 0.5, y: bounds.height - 23, width: 1, height: 23)
        leftRulerMark.frame = CGRect(x: 0, y: location.y.rounded() - 0.5, width: 27, height: 1)
        topRulerMark.isHidden = location.x < 27
        leftRulerMark.isHidden = location.y > bounds.height - 23
    }
    private func drawRulers(_ context: CGContext) {
        Theme.Canvas.ruler.setFill()
        CGRect(x: 0, y: bounds.height - 23, width: bounds.width, height: 23).fill()
        CGRect(x: 0, y: 0, width: 27, height: bounds.height).fill()
        // A label every 20 mm (10 mm zoomed in), or every inch (½ in zoomed in).
        let unit = Preferences.shared.unit
        let step = unit == .inches ? (state.zoom < 3 ? 25.4 : 12.7) : (state.zoom < 3 ? 20.0 : 10.0)
        func label(_ mm: Double) -> String { unit == .inches ? Self.inchRulerLabel(mm) : String(Int(mm)) }
        let minimum = floor(model(.zero).x / step) * step, maximum = model(CGPoint(x: bounds.maxX, y: 0)).x
        // Labels that would land on the other ruler are skipped, so the corner where the rulers meet stays clear.
        // Labels that would run off the right edge are skipped too, rather than drawn cut in half.
        for x in stride(from: minimum, through: maximum, by: step) {
            let p = screen(Point(x, 0)), text = label(x)
            if p.x >= 27 && p.x + 3 + labelWidth(text, size: 9) <= bounds.width { drawLabel(text, at: CGPoint(x: p.x + 3, y: bounds.height - 18), size: 9) }
        }
        let minY = floor(model(.zero).y / step) * step, maxY = model(CGPoint(x: 0, y: bounds.maxY)).y
        for y in stride(from: minY, through: maxY, by: step) { let p = screen(Point(0, y)); if p.y + 14 <= bounds.height - 23 { drawLabel(label(y), at: CGPoint(x: 3, y: p.y + 2), size: 8) } }
    }
    override func mouseDown(with event: NSEvent) {
        state.focusCanvas()
        dragRevision = state.revision
        clickAgainAt = nil
        let location = convert(event.locationInWindow, from: nil)
        if state.tool == .zoomBox { zoomBox = (location, location); return }   // zooming works in older projects too
        // Dragging out of a ruler adds a guide: down from the top ruler a horizontal one, right from the left ruler a
        // vertical one. (The corner where the rulers meet does nothing.)
        let inTopRuler = overOwnRuler(location, vertical: false), inLeftRuler = overOwnRuler(location, vertical: true)
        if rulersShown && inTopRuler != inLeftRuler {
            guard !state.hasVersionMismatch else { return }
            guideDrag = ((state.design.guides ?? []).count, inLeftRuler, true, location); dragSnapshot = state.design
            showWantedCursor(); return
        }
        if state.tool == .measure {
            if measureStep == .following, let line = measurement {
                // The second click of click, move, click puts the line's end down where the pointer is. One right on
                // top of the first click (under 3 screen points away) is ignored, and the line keeps following.
                let point = snapped(model(location))
                guard line.start.distance(to: point) * state.zoom >= 3 else { return }
                moveMeasurementEnd(to: location); measureStep = .placed; return
            }
            let point = snapped(model(location)); measurement = (point, point); measureStep = .dragging; needsDisplay = true; return
        }
        if state.tool == .text { state.addLettering(at: snapped(model(location))); return }
        if state.tool == .branch { state.addBranchPoint(snapped(model(location))); return }
        if state.tool == .scatter { return }   // its choices are all in Properties
        if state.tool == .paintStitches { state.paintPatch(at: model(location)); return }
        if state.tool == .wreath {
            state.wreathCenter = snapped(model(location))
            state.status = "Wreath · Click again to move the center · Return or Apply makes it · Esc cancels"; return
        }
        if state.tool == .stitchEdit { stitchEditDown(location, event: event); return }
        // Clicking a stitch angle line (with Edit nodes or the angle tools) selects it, so Delete removes it. While a
        // new line is half drawn, the click finishes it instead.
        state.selectedAngle = nil
        if [.node, .addAngles, .removeAngles].contains(state.tool), state.angleStart == nil, !state.hasVersionMismatch,
           state.tool != .node || (nearestNode(model(location)) == nil && nearestHandle(model(location)) == nil),   // nodes and handles come first
           let angle = state.angleLine(near: model(location), reach: 6 / state.zoom) {
            if state.tool == .removeAngles { state.removeAngleLine(angle.object, angle.index); return }
            state.selectedAngle = angle; state.status = "Stitch angle selected · drag an end to swing it, or the middle to slide it · \(Preferences.shared.key(.delete)) removes it"
            // Grabbing near an end's square swings that end; anywhere else on the line slides the whole line.
            let p = model(location), line = state.design.objects.first { $0.id == angle.object }?.settings.angleLines?[angle.index] ?? []
            let end = line.indices.first { line[$0].distance(to: p) <= 6 / state.zoom }
            angleDrag = (angle.object, angle.index, end, snapped(p)); dragSnapshot = state.design
            needsDisplay = true; return
        }
        if state.tool == .addAngles || state.tool == .removeAngles { state.clickForAngle(snapped(model(location)), reach: 9 / state.zoom); return }
        // With Edit Nodes, grabbing an end of a selected fill's stitch angle line starts swinging it around its other
        // end (nodes and handles still come first). A double-click puts the line back across the shape.
        if state.tool == .node, !state.hasVersionMismatch, nearestNode(model(location)) == nil, nearestHandle(model(location)) == nil,
           let fill = fillAngleEnd(near: model(location)),
           let ends = state.design.objects.first(where: { $0.id == fill }).flatMap(StitchAngleLine.ends(of:)) {
            if event.clickCount == 2 { resetFillAngleLine(fill); return }
            let p = model(location), anchor = ends.0.distance(to: p) < ends.1.distance(to: p) ? ends.1 : ends.0   // the end not grabbed
            fillAngleDrag = (fill, p, nil, anchor); dragSnapshot = state.design
            state.status = "Drag to turn the stitches · the other end stays put · let go to keep the new angle"
            needsDisplay = true; return
        }
        guard !state.hasVersionMismatch else { return }
        let point = snapped(model(location))
        if state.tool.draws {
            if event.clickCount == 2 { state.finishPath(); return }
            // With nothing drawn yet, a click on an end of a selected open line (Running tool) or satin column (Satin
            // tool) picks it up there, to carry on drawing it; a click on a point of a selected closed outline (Fill or
            // Closed Shape tool) picks it up there, to draw more points into it.
            if state.draft.isEmpty, let pick = continuePick(near: location) {
                // The hover hint is done with: the status line now explains continuing, and the marker gives way to the drawing.
                hoveredPick = nil; statusBeforeHint = nil; showWantedCursor()
                switch pick {
                case .end(let id, let fromStart): state.continueDrawing(id, fromStart: fromStart)
                case .after(let id, let index): state.drawInto(id, after: index)
                }
                return
            }
            state.addDraftPoint(point, smooth: event.modifierFlags.contains(.control), reach: 3 / state.zoom)   // 3 screen points
            drawingHandle = state.draft.count - 1; return
        }
        if state.tool.dragsShape {
            // The second click of click, move, click puts the shape down where the pointer is. One too close to the
            // first click to make a shape is ignored, and the shape keeps following.
            if shapeFollowsPointer, let start = shapeStart {
                sizeShape(from: start, to: location, flags: event.modifierFlags)
                guard !state.draft.isEmpty else { return }
                cancelShapeDrag(); state.finishShape(state.tool.draggedShape ?? .rectangle); return
            }
            shapeStart = point; return
        }
        // Freehand ignores Snap: a stroke pulled onto grid points would be jagged.
        if state.tool.freehand { freehandStroke = [model(location)]; state.draft = [PathNode(model(location))]; return }
        if state.tool == .pan { screenStart = location; panStart = pan; return }
        if state.tool == .hooping {
            // A click picks the hooping under it (where they overlap, the one whose center is nearest) and starts
            // dragging it; a click outside them all picks none.
            let p = model(location), hoopings = state.design.multiHooping?.hoopings ?? []
            let w = state.design.hoop.width / 2, h = state.design.hoop.height / 2
            let under = hoopings.indices.filter { abs(p.x - hoopings[$0].center.x) <= w && abs(p.y - hoopings[$0].center.y) <= h }
            state.selectedHooping = under.min { hoopings[$0].center.distance(to: p) < hoopings[$1].center.distance(to: p) }
            if let picked = state.selectedHooping { hoopingDrag = picked; dragStart = point; dragSnapshot = state.design }
            needsDisplay = true; return
        }
        if state.tool == .artwork {
            // A corner handle resizes; just outside a corner rotates; once the image is clicked, a side's diamond
            // leans it. Anywhere on the image moves it, and a click there without moving shows or hides the diamonds.
            // Elsewhere nothing happens.
            guard let artwork = state.design.artwork, artwork.visible else { return }
            if state.croppingArtwork { cropBox = (model(location), model(location)); return }   // a box starts anywhere
            let reach = artworkHandleReach
            func near(_ p: CGPoint) -> Bool { hypot(p.x - location.x, p.y - location.y) <= reach }
            let sides = state.artworkSkewHandles ? artworkSideHandles(artwork) : []
            if let corner = artwork.corners.map(screen).firstIndex(where: near) { artworkDrag = corner }
            else if let side = sides.firstIndex(where: near) { artworkTurnDrag = 4 + side }
            else if let corner = artworkRotateCorner(at: location) { artworkTurnDrag = corner }
            else if artworkOutline(artwork).contains(location) { artworkDrag = -1; clickAgainAt = location } else { return }
            dragStart = model(location); dragSnapshot = state.design; return
        }
        // Markers sit on top of everything, so grabbing one wins over setting a new point. (Edit Nodes grabs them further
        // down; with Select none show, so none can be grabbed.)
        if state.tool == .entryExit, let marker = nearestMarker(point) {
            draggedMarker = marker; dragStart = point; dragSnapshot = state.design; return
        }
        // A resize handle round the selection: dragging it resizes the selection from the opposite side or corner.
        // With the rotate and skew handles showing, a corner turns it and a side leans it instead.
        if state.tool == .select, !state.hasVersionMismatch, !routeShown, let box = selectionBox(in: state.design),
           let handle = resizeHandles(box).first(where: { hypot($0.point.x - location.x, $0.point.y - location.y) <= handleReach }) {
            let low = model(CGPoint(x: box.minX, y: box.minY)), high = model(CGPoint(x: box.maxX, y: box.maxY))
            let side = handle.dx == 0 || handle.dy == 0
            if state.skewHandles && side { turnDrag = (handle.dx, handle.dy, low, high); dragStart = model(location) }   // leaning ignores Snap
            else { resizeDrag = (handle.dx, handle.dy, low, high); dragStart = point }
            dragSnapshot = state.design; return
        }
        // Just outside a corner, a drag rotates the selection round the middle of its box.
        if let corner = rotateCorner(at: location), let box = selectionBox(in: state.design) {
            turnDrag = (corner.dx, corner.dy, model(CGPoint(x: box.minX, y: box.minY)), model(CGPoint(x: box.maxX, y: box.maxY)))
            dragStart = model(location); dragSnapshot = state.design; return
        }
        if state.tool == .entryExit { setEntryOrExit(at: point, exit: event.modifierFlags.contains(.option)); return }
        pointer=point
        // With Edit Nodes, an envelope's handle bends the lettering's envelope.
        if state.tool == .node, !state.hasVersionMismatch,
           let found = envelopes(in: state.design).lazy.compactMap({ envelope in self.envelopeHandles(envelope.spec).first { hypot($0.point.x - location.x, $0.point.y - location.y) <= 7 }.map { (envelope.spec, $0.handle) } }).first {
            envelopeDrag = (found.0, found.1); dragStart = point; dragSnapshot = state.design
            state.status = "Drag to bend the envelope · Shift bends the \(found.0.envelope!.kind.slides ? "other end" : "opposite edge") the other way · ⌘ the same way"; return
        }
        // With Edit Nodes, a letter's handle moves just that letter (lettering has no nodes to drag).
        if state.tool == .node, !state.hasVersionMismatch, let letter = letterHandles(in: state.design).first(where: { hypot($0.point.x - location.x, $0.point.y - location.y) <= 7 }) {
            letterDrag = (letter.lettering, letter.key, letter.parts); dragStart = point; dragSnapshot = state.design
            state.status = "Drag to move this letter · it stays put when you change the lettering's text, font or size"; return
        }
        // Handles sit on top of nodes, so they are checked first. Both are picked where the pointer really is: the
        // snapped point can sit nearer a neighbouring node, which would grab the wrong one.
        if state.tool == .node, let handle=nearestHandle(model(location)) {
            draggedHandle=handle;dragStart=point;dragSnapshot=state.design;return
        }
        if state.tool == .node, let location=nearestNode(model(location)) {
            state.selection=[location.object];state.selectedNode=location
            draggedNode=location;dragStart=point;dragSnapshot=state.design;return
        }
        // Then a selected object's start, end or center marker, before the press would add a node or move the shape.
        if state.tool == .node, let marker = nearestMarker(point) {
            draggedMarker = marker; dragStart = point; dragSnapshot = state.design; return
        }
        // Pressing on a selected object's edge adds a corner node there; keep holding to drag it into place. It's
        // saved, with the drag, when the mouse is let go. (A satin gets a new rung, saved straight away.)
        if state.tool == .node, !state.hasVersionMismatch, let edge=edge(near:model(location),reach:6/state.zoom) {
            let added=addingNode(on:edge,smooth:false,to:state.design)
            guard let node=added.node else{state.edit("Add Rung"){$0=added.design};return}
            dragSnapshot=added.design;preview=added.design;draggedNode=node;dragStart=point;nodeJustAdded=true;return
        }
        // Pressing on the stitch angle line itself (between its ends) picks it up to move it somewhere else; a
        // double-click puts it back across the shape.
        if state.tool == .node, !state.hasVersionMismatch, let fill = fillAngleLine(near: model(location)) {
            if event.clickCount == 2 { resetFillAngleLine(fill); return }
            fillAngleDrag = (fill, model(location), model(location), nil); dragSnapshot = state.design
            state.status = "Drag to move the stitch angle line · drag one of its ends to turn the stitches"
            needsDisplay = true; return
        }
        // With Select, a guide can be grabbed wherever no object is under the pointer.
        if state.tool == .select, !state.hasVersionMismatch, hit(point) == nil, let index = guide(near: location) {
            guideDrag = (index, state.design.guides![index].vertical, false, location); dragSnapshot = state.design
            showWantedCursor()
            state.status = "Drag the guide · let go over its ruler to remove it"; return
        }
        if let object = hit(point) {
            // Double-clicking lettering opens it for editing (after the mouse is released, so the dialog doesn't
            // start in the middle of a click).
            if state.tool == .select, event.clickCount == 2, object.monogram != nil {
                state.select(object.id); DispatchQueue.main.async { AppDelegate.shared.perform(.editMonogram) }; return
            }
            if state.tool == .select, event.clickCount == 2, object.lettering != nil {
                state.select(object.id); DispatchQueue.main.async { AppDelegate.shared.perform(.editLettering) }; return
            }
            let single = event.modifierFlags.contains(.option)   // Option-click picks one member of a group
            // A plain click on what's already selected may switch its handles (decided on mouse up, if it didn't move).
            if state.tool == .select, !adding(event), !single, state.selection.contains(object.id) { clickAgainAt = location }
            if adding(event) { state.select(object.id, extend: true, single: single) }
            else if !state.selection.contains(object.id) || single { state.select(object.id, single: single) }
            dragStart = point; dragSnapshot = state.design
        } else if state.tool == .select {
            // Empty canvas: start a selection box. Shift (or Control or ⌘) keeps what's already selected.
            if !adding(event) { state.selection = [] }
            selectBox = (location, location)
        } else { state.selection = [] }
    }
    /// True for a click that adds to the selection (or takes a selected object out of it): Shift-, Control- or ⌘-click.
    private func adding(_ event: NSEvent) -> Bool { !event.modifierFlags.isDisjoint(with: [.shift, .control, .command]) }
    override func rightMouseDown(with event: NSEvent) {
        state.focusCanvas()
        let point = snapped(model(convert(event.locationInWindow, from: nil)))
        if state.tool.draws && !state.hasVersionMismatch { state.addDraftPoint(point, smooth: true, reach: 3 / state.zoom) }
        // Right-click on a point switches it between corner and smooth. It's picked where the pointer really is, as a
        // left-click is (Snap could otherwise pick its neighbour).
        else if state.tool == .node,let location=nearestNode(model(convert(event.locationInWindow,from:nil))) {
            state.selection=[location.object];state.selectedNode=location
            state.setSelectedNode(smooth:!(state.selectedPathNode?.smooth ?? true))
        }
        // Right-click on a selected object's edge adds a curve node: drag it and the edge bends smoothly through it.
        else if state.tool == .node,!state.hasVersionMismatch,let edge=edge(near:model(convert(event.locationInWindow,from:nil)),reach:6/state.zoom) {
            let added=addingNode(on:edge,smooth:true,to:state.design)
            state.edit(added.node == nil ? "Add Rung":"Add Curve Node"){$0=added.design}
            if let node=added.node{state.selectedNode=node;state.status="Curve node added · drag it and the edge bends smoothly through it"}
        }
    }
    override func mouseMoved(with event:NSEvent){pointer=model(convert(event.locationInWindow,from:nil));state.pointer.position=pointer;if shapeFollowsPointer,let start=shapeStart,state.tool.dragsShape{sizeShape(from:start,to:convert(event.locationInWindow,from:nil),flags:event.modifierFlags)};if measureStep == .following,state.tool == .measure{moveMeasurementEnd(to:convert(event.locationInWindow,from:nil))};moveRulerMarks(to:convert(event.locationInWindow,from:nil));if state.angleStart != nil{needsDisplay=true};updateGuideCursor(at:convert(event.locationInWindow,from:nil));updateHandleCursor(at:convert(event.locationInWindow,from:nil));updateContinueHover(at:convert(event.locationInWindow,from:nil))}
    override func mouseExited(with event: NSEvent) { state.pointer.position = nil; hoveredGuide = nil; moveRulerMarks(to: nil); updateContinueHover(at: nil) }
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        state.pointer.position = model(location); moveRulerMarks(to: location)
        if let start = screenStart { pan = CGPoint(x: panStart.x + location.x - start.x, y: panStart.y + location.y - start.y); needsDisplay = true; return }
        if let box = zoomBox { zoomBox = (box.start, location); needsDisplay = true; return }
        if let box = selectBox { selectBox = (box.start, location); needsDisplay = true; return }
        if let box = cropBox { cropBox = (box.start, model(location)); needsDisplay = true; return }
        if state.tool == .paintStitches { state.paintPatch(at: model(location)); return }   // dragging paints every part it crosses
        if dropDragIfDesignChanged() { return }
        if let drag = guideDrag, var next = dragSnapshot {
            let p = model(location), raw = drag.vertical ? p.x : p.y
            let position = state.snap ? Preferences.shared.unit.snap(raw) : (raw * 10).rounded() / 10   // a snap step with Snap on, else 0.1 mm
            var guides = next.guides ?? []
            if drag.isNew { guides.append(Guide(vertical: drag.vertical, position: position)) } else { guides[drag.index].position = position }
            next.guides = guides; preview = next; guideDrag?.pointer = location; needsDisplay = true; return
        }
        if let drag = stitchDrag {
            let delta = snapped(model(location)) - snapped(drag.start)
            var moved = drag.sections
            for ref in state.selectedStitches where moved.indices.contains(ref.section) && moved[ref.section].points.indices.contains(ref.index) { moved[ref.section].points[ref.index] = moved[ref.section].points[ref.index] + delta }
            stitchPreview = moved; needsDisplay = true; return
        }
        if let box = stitchBox { stitchBox = (box.start, location); needsDisplay = true; return }
        if let drag = angleDrag, var next = dragSnapshot, let i = next.objects.firstIndex(where: { $0.id == drag.object }),
           var line = next.objects[i].digitizing?.angleLines?[drag.index] {
            let delta = snapped(model(location)) - drag.start
            if let end = drag.end { line[end] = line[end] + delta } else { line = line.map { $0 + delta } }
            next.objects[i].digitizing?.angleLines?[drag.index] = line
            preview = next; needsDisplay = true; return
        }
        if let drag = fillAngleDrag, var next = dragSnapshot, let i = next.objects.firstIndex(where: { $0.id == drag.object }) {
            if let from = drag.slideFrom, let center = StitchAngleLine.center(of: next.objects[i]) {
                next.objects[i].digitizing?.angleLineCenter = snapped(center + (model(location) - from))   // only where it's drawn
            } else if let anchor = drag.anchor {
                StitchAngleLine.swing(&next.objects[i], from: anchor, to: model(location))   // the grabbed end follows the pointer
            }
            fillAngleDrag = (drag.object, model(location), drag.slideFrom, drag.anchor); preview = next; needsDisplay = true; return
        }
        if measureStep == .dragging { moveMeasurementEnd(to: location); return }
        if measureStep == .placed { return }   // the click that put the line down: a wobble doesn't move it
        if freehandStroke != nil {
            // The stroke follows the pointer; points closer than 0.1 mm are skipped (finishing smooths it anyway).
            let p = model(location)
            if freehandStroke!.last.map({ $0.distance(to: p) >= 0.1 }) ?? true { freehandStroke!.append(p); state.draft.append(PathNode(p)) }
            needsDisplay = true; return
        }
        if let start = shapeStart, !shapeFollowsPointer { sizeShape(from: start, to: location, flags: event.modifierFlags); return }
        if let index = drawingHandle, state.draft.indices.contains(index) {
            // A tiny wobble is still a click (a corner); past a few screen points the drag pulls out the node's handles.
            let target = snapped(model(location))
            if target.distance(to: state.draft[index].point) * state.zoom > 4 { state.draft[index].pullHandles(toward: target) }
            needsDisplay = true; return
        }
        guard let start = dragStart, var next = dragSnapshot else { return }
        if let drag = resizeDrag {
            let target = snapped(model(location)), width = drag.high.x - drag.low.x, height = drag.high.y - drag.low.y
            // Each side the handle moves follows the pointer; the opposite side (or corner) stays where it was.
            var sx = drag.dx == 0 || width < 0.01 ? 1 : (drag.dx > 0 ? target.x - drag.low.x : drag.high.x - target.x) / width
            var sy = drag.dy == 0 || height < 0.01 ? 1 : (drag.dy > 0 ? target.y - drag.low.y : drag.high.y - target.y) / height
            // A corner keeps the proportions unless Shift is held: both sides follow whichever moved further.
            let corner = drag.dx != 0 && drag.dy != 0
            if corner && !event.modifierFlags.contains(.shift) { let s = abs(sx - 1) > abs(sy - 1) ? sx : sy; sx = s; sy = s }
            sx = max(0.05, sx); sy = max(0.05, sy)   // never flipped over or squashed to nothing
            let anchor = Point(drag.dx > 0 ? drag.low.x : drag.high.x, drag.dy > 0 ? drag.low.y : drag.high.y)
            preview = EditorState.scaling(next, ids: state.editableSelection, about: anchor, sx: sx, sy: sy)
            state.status = "Size \(Preferences.shared.unit.size(width * sx, height * sy))" + (corner ? " · ⇧ stretches freely" : "")
            needsDisplay = true; return
        }
        if let drag = turnDrag {
            let p = model(location), ids = state.editableSelection, step = event.modifierFlags.contains(.shift) ? 15.0 : 1
            let low = Point(min(drag.low.x, drag.high.x), min(drag.low.y, drag.high.y)), high = Point(max(drag.low.x, drag.high.x), max(drag.low.y, drag.high.y))
            if drag.dx != 0 && drag.dy != 0 {
                // A corner turns the selection round the middle of its box by the angle the pointer has swung through,
                // in whole degrees (counterclockwise is positive, as in the Rotate box).
                let center = (low + high) * 0.5
                let swung = (atan2(p.y - center.y, p.x - center.x) - atan2(start.y - center.y, start.x - center.x)) * 180 / .pi
                let degrees = (remainder(swung, 360) / step).rounded() * step   // remainder keeps it within -180…180
                next.rotate(ids, by: degrees, around: center)
                state.status = "Rotate \(Int(degrees))° · ⇧ turns in steps of 15°"
            } else {
                // The top or bottom handle leans the selection sideways, the left or right one up and down. The opposite
                // side stays put, and the dragged side follows the pointer.
                let vertical = drag.dx != 0
                let anchor = vertical ? (drag.dx > 0 ? low.x : high.x) : (drag.dy > 0 ? low.y : high.y)
                let reach = (vertical ? (drag.dx > 0 ? high.x : low.x) : (drag.dy > 0 ? high.y : low.y)) - anchor   // anchor to dragged side
                guard abs(reach) > 0.01 else { return }
                let moved = vertical ? p.y - start.y : p.x - start.x
                let degrees = min(60, max(-60, (atan(moved / reach) * 180 / .pi / step).rounded() * step))   // as far as the Skew box goes
                next.skew(ids, by: degrees, around: vertical ? Point(anchor, 0) : Point(0, anchor), vertical: vertical)
                state.status = "Skew \(Int(degrees))° · ⇧ leans in steps of 15°"
            }
            preview = next; needsDisplay = true; return
        }
        if let index = hoopingDrag, let before = dragSnapshot?.multiHooping?.hoopings, before.indices.contains(index) {
            next.multiHooping!.hoopings[index].center = before[index].center + (snapped(model(location)) - start)
            preview = next; needsDisplay = true; return
        }
        if let handle = artworkTurnDrag, let artwork = next.artwork {
            let turned = artwork.turned(handle: handle, from: start, to: model(location), step: event.modifierFlags.contains(.shift) ? 15 : 1)
            next.artwork = turned.artwork
            state.status = (handle < 4 ? "Rotate \(Int(turned.degrees))° · ⇧ turns" : "Skew \(Int(turned.degrees))° · ⇧ leans") + " in steps of 15°"
            preview = next; needsDisplay = true; return
        }
        if let corner = artworkDrag, let artwork = next.artwork {
            next.artwork = artwork.adjusted(corner: corner, from: start, to: snapped(model(location)), free: event.modifierFlags.contains(.shift))
            preview = next; needsDisplay = true; return
        }
        if let drag = envelopeDrag {
            if let spec = bentEnvelope(drag, to: snapped(model(location)), flags: event.modifierFlags),
               let color = next.letteringObjects(spec.id).first?.color, let letters = try? spec.build(color: color, embroideryFonts: EmbroideryFontLibrary.fonts) {
                next.replaceLettering(spec.id, with: letters, embroideryFonts: EmbroideryFontLibrary.fonts); preview = next
            }
            needsDisplay = true; return
        }
        if let letter = letterDrag {
            let delta = snapped(model(location)) - start
            for index in next.objects.indices where letter.parts.contains(next.objects[index].id) { next.objects[index].transform { $0 + delta } }
            preview = next; needsDisplay = true; return
        }
        if let marker = draggedMarker, let index = next.objects.firstIndex(where: { $0.id == marker.object }) {
            let target = snapped(model(location))
            switch marker.kind {
            // A word's start and end belong to the whole lettering (its recipe, its first and last letter).
            case .start: if let id = next.objects[index].lettering?.id { next.setLetteringStart(id, target) } else { next.objects[index].entry = target }
            case .end: if let id = next.objects[index].lettering?.id { next.setLetteringEnd(id, target) } else { next.objects[index].exit = target }
            case .center: next.objects[index].digitizing?.radialCenter = target
            }
            preview = next; needsDisplay = true; return
        }
        if let handle = draggedHandle {
            dragHandle(handle, to: snapped(model(location)), in: &next, independent: event.modifierFlags.contains(.option))
            preview = next; checkDragProblem(handle.location.object); needsDisplay = true; return
        }
        let delta = snapped(model(location)) - start
        for index in next.objects.indices where state.selection.contains(next.objects[index].id) && !next.objects[index].locked {
            if let node=draggedNode,next.objects[index].id==node.object {
                // transform moves the node's handles too, so the curve keeps its shape around the moved node.
                if node.ring<0{next.objects[index].nodes[node.index].transform{$0+delta}}
                else{next.objects[index].holes![node.ring][node.index].transform{$0+delta}}
            } else if draggedNode == nil {next.objects[index].transform{$0+delta}}
        }
        preview = next
        if let node = draggedNode { checkDragProblem(node.object) }
        needsDisplay = true
    }
    /// Checks, while a node or handle is dragged, whether letting go here would leave `id` unable to sew (the same
    /// check as on mouse-up, which puts the node back). If so, the object is outlined in red and the status bar says
    /// why, so the node going back is never a surprise.
    private func checkDragProblem(_ id: UUID) {
        let before = dragSnapshot?.objects.first { $0.id == id }, after = preview?.objects.first { $0.id == id }
        let problem = before.flatMap { StitchEngine.shapeProblem($0) == nil ? after.flatMap(StitchEngine.shapeProblem) : nil }
        if let problem, let after {
            let earlierStatus = dragProblem?.earlierStatus ?? state.status
            if dragProblem?.problem != problem { state.status = "Let go here and the node goes back: \(after.name) couldn't be sewn. \(problem)" }
            dragProblem = (id, problem, earlierStatus)
        } else if let earlier = dragProblem {
            dragProblem = nil; state.status = earlier.earlierStatus
        }
    }
    override func mouseUp(with event: NSEvent) {
        if let step = measureStep, guideDrag == nil {
            switch step {
            case .dragging:
                // Under 3 screen points long, it was a click, not a drag: the line's end follows the pointer until the next click.
                if let line = measurement, line.start.distance(to: line.end) * state.zoom < 3 {
                    measureStep = .following
                    state.status = "Move to the other point, then click to measure · Esc cancels"
                } else { measureStep = nil }
            case .placed: measureStep = nil
            case .following: break   // letting go of a click right on the first one: the line keeps following
            }
            return
        }
        if dropDragIfDesignChanged() { return }
        if let drag = envelopeDrag {
            if let spec = bentEnvelope(drag, to: snapped(model(convert(event.locationInWindow, from: nil))), flags: event.modifierFlags), spec != drag.spec {
                state.rebuildLettering(spec, action: "Shape Envelope")
            }
            envelopeDrag = nil; preview = nil; dragStart = nil; dragSnapshot = nil; needsDisplay = true; return
        }
        if let letter = letterDrag {
            // The move becomes the letter's nudge, measured along the lettering's baseline and up, as a share of its
            // height; rebuilding puts it there (and keeps it there through later changes).
            if let start = dragStart, var spec = dragSnapshot?.objects.first(where: { $0.lettering?.id == letter.lettering })?.lettering {
                let delta = snapped(model(convert(event.locationInWindow, from: nil))) - start
                let along = (spec.alongMarker - spec.anchor) * 0.1, up = (spec.upMarker - spec.anchor) * 0.1
                let nudge = Point(delta.x * along.x + delta.y * along.y, delta.x * up.x + delta.y * up.y) * (1 / max(0.1, spec.height))
                if hypot(delta.x, delta.y) > 0.01 {
                    var offsets = spec.letterOffsets ?? [:]
                    offsets[letter.key] = (offsets[letter.key] ?? Point(0, 0)) + nudge
                    spec.letterOffsets = offsets
                    state.rebuildLettering(spec, action: "Move Letter")
                }
            }
            letterDrag = nil; preview = nil; dragStart = nil; dragSnapshot = nil; needsDisplay = true; return
        }
        if resizeDrag != nil {
            if let preview { state.document?.replace(preview, action: "Resize Objects") }
            resizeDrag = nil; preview = nil; dragStart = nil; dragSnapshot = nil; needsDisplay = true; return
        }
        if let drag = turnDrag {
            if let preview { state.document?.replace(preview, action: drag.dx != 0 && drag.dy != 0 ? "Rotate Objects" : "Skew Objects") }
            turnDrag = nil; preview = nil; dragStart = nil; dragSnapshot = nil; needsDisplay = true; return
        }
        if let handle = artworkTurnDrag {
            if let preview { state.document?.replace(preview, action: handle < 4 ? "Rotate Artwork" : "Skew Artwork") }
            artworkTurnDrag = nil; preview = nil; dragStart = nil; dragSnapshot = nil; needsDisplay = true; return
        }
        if let drag = guideDrag {
            // Let go over its own ruler, a guide is removed (or, if it was just dragged out, never added).
            let removing = overOwnRuler(convert(event.locationInWindow, from: nil), vertical: drag.vertical)
            var next = preview
            if removing {
                next = drag.isNew ? nil : dragSnapshot
                next?.guides?.remove(at: drag.index); if next?.guides?.isEmpty == true { next?.guides = nil }
            }
            if let next {
                state.status = removing ? "Guide removed." : "Guide at \(drag.vertical ? "X" : "Y") \(Preferences.shared.unit.short(next.guides![drag.index].position)) · drag it back onto the ruler to remove it"
                state.document?.replace(next, action: drag.isNew ? "Add Guide" : removing ? "Remove Guide" : "Move Guide")
            }
            guideDrag = nil; preview = nil; dragSnapshot = nil; needsDisplay = true
            // Back to the tool's pointer, or ↔/↕ if the pointer is still over a guide.
            hoveredGuide = nil; showWantedCursor(); updateGuideCursor(at: convert(event.locationInWindow, from: nil)); return
        }
        if stitchDrag != nil {
            if let moved = stitchPreview { state.setStitches(moved, action: "Move Stitches") }
            stitchDrag = nil; stitchPreview = nil; needsDisplay = true; return
        }
        if let box = stitchBox {
            // Every needle point inside the box joins the selection.
            let a = model(box.start), b = model(box.end)
            let (lo, hi) = (Point(min(a.x, b.x), min(a.y, b.y)), Point(max(a.x, b.x), max(a.y, b.y)))
            for (s, section) in state.stitchSections.enumerated() { for (i, p) in section.points.enumerated() where p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y { state.selectedStitches.insert(StitchRef(section: s, index: i)) } }
            stitchBox = nil; needsDisplay = true
            if !state.selectedStitches.isEmpty { state.status = "\(state.selectedStitches.count) needle point\(state.selectedStitches.count == 1 ? "" : "s") selected · Drag to move · \(Preferences.shared.key(.delete)) deletes" }
            return
        }
        if let box = cropBox {
            // Letting go crops to the box (a box under 1 mm, such as a click, keeps cropping).
            cropBox = nil; needsDisplay = true
            if let artwork = state.design.artwork, let kept = artwork.cropped(from: box.start, to: model(convert(event.locationInWindow, from: nil))) {
                state.croppingArtwork = false
                state.edit("Crop Artwork") { $0.artwork = kept }
                state.status = "Cropped · Uncrop in the Reference image panel brings the rest back"
            }
            return
        }
        if let box = selectBox {
            selectBox = nil; needsDisplay = true
            // A click (a box under 4 points) on empty canvas only clears the selection, already done on mouse down.
            if abs(box.end.x - box.start.x) >= 4 || abs(box.end.y - box.start.y) >= 4 { selectObjects(inside: box) }
            return
        }
        if let box = zoomBox {
            // A click (or a box under 6 points) zooms in 2× around the pointer; a box fills the canvas.
            zoomBox = nil
            if abs(box.end.x - box.start.x) < 6 && abs(box.end.y - box.start.y) < 6 { setZoom(state.zoom * 2, keeping: box.start) }
            else {
                let a = model(box.start), b = model(box.end)
                zoom(to: (Point(min(a.x, b.x), min(a.y, b.y)), Point(max(a.x, b.x), max(a.y, b.y))))
            }
            state.tool = state.toolBeforeZoom; state.status = "Zoomed. \(Preferences.shared.key(.zoomFit)) fits the hoop again."
            window?.invalidateCursorRects(for: self); return
        }
        if let stroke = freehandStroke { freehandStroke = nil; state.finishFreehand(stroke); return }
        if shapeStart != nil {
            if shapeFollowsPointer { return }   // letting go of a click that didn't put the shape down
            if state.draft.isEmpty {
                // A click, not a drag: the shape follows the pointer until the next click.
                shapeFollowsPointer = true
                state.status = (state.tool == .ellipse ? "Move out from the center, then click to put the ellipse down · ⌘ for a circle" : "Move to size the shape, then click to put it down · ⌘ keeps it even · ⇧ from the center") + " · Esc cancels"
            } else { cancelShapeDrag(); state.finishShape(state.tool.draggedShape ?? .rectangle) }
            return
        }
        // A click that didn't move, on what was already selected, switches between resize and rotate/skew handles.
        if let pressed = clickAgainAt {
            clickAgainAt = nil
            let here = convert(event.locationInWindow, from: nil)
            if hypot(here.x - pressed.x, here.y - pressed.y) < 3, state.tool == .artwork {
                state.artworkSkewHandles.toggle(); preview = nil   // a click, not a move
                state.status = state.artworkSkewHandles ? "Skew the image · drag a diamond on a side to lean it · ⇧ in steps of 15° · click it again to hide them" : "Drag a corner to resize the image · just outside a corner to rotate · click it to skew"
                needsDisplay = true
            } else if hypot(here.x - pressed.x, here.y - pressed.y) < 3 {
                state.skewHandles.toggle()
                state.status = state.skewHandles ? "Skew · drag a diamond on a side to lean the selection · ⇧ in steps of 15° · click again to stretch" : "Drag a corner to resize · just outside a corner to rotate · click the selection again to skew"
                needsDisplay = true
            }
        }
        let action = hoopingDrag != nil ? "Move Hooping" : angleDrag != nil ? "Move Stitch Angle" : fillAngleDrag.map { $0.slideFrom == nil ? "Fill Angle" : "Move Stitch Angle Line" } ?? artworkDrag.map { $0 < 0 ? "Move Artwork" : "Resize Artwork" } ?? draggedMarker.map { $0.kind == .end ? "Move End Point" : $0.kind == .start ? "Move Start Point" : "Move Radial Center" } ?? (draggedHandle != nil ? "Shape Curve" : draggedNode == nil ? "Move Objects" : nodeJustAdded ? "Add Node" : "Move Node")
        // A node or handle drag that leaves its object unable to sew (a satin rung crossing a rail, a fill's edge
        // crossing itself) goes back, unless the object was already broken (then any edit may be the fix).
        if let next = preview, let id = draggedNode?.object ?? draggedHandle?.location.object,
           let before = dragSnapshot?.objects.first(where: { $0.id == id }), let after = next.objects.first(where: { $0.id == id }),
           StitchEngine.shapeProblem(before) == nil, let problem = StitchEngine.shapeProblem(after) {
            state.status = "That would leave \(after.name) unable to sew, so it went back. \(problem)"
            preview = nil
        }
        // A stitch angle line moved so it would cross another inside the fill goes back too.
        if let drag = angleDrag, let after = preview?.objects.first(where: { $0.id == drag.object }), let problem = after.angleLineProblem {
            state.status = "That went back. \(problem)"
            preview = nil
        }
        // Said before the change is saved, so a message from saving it (such as hand edits being replaced) wins.
        if let drag = fillAngleDrag, drag.slideFrom == nil, let angle = preview?.objects.first(where: { $0.id == drag.object })?.settings.angle { state.status = "Stitch angle \(Int(angle.rounded()) % 180)°" }   // the angle can have decimals now: round, not cut off
        if let preview { state.document?.replace(preview, action: action) }
        if nodeJustAdded, let node = draggedNode { state.selectedNode = node; state.status = "Node added · drag it to reshape · right-click an edge for a curve node" }
        nodeJustAdded = false
        preview = nil; angleDrag = nil; fillAngleDrag = nil; dragStart = nil; dragSnapshot = nil; draggedNode = nil; draggedHandle = nil; drawingHandle = nil; draggedMarker = nil; artworkDrag = nil; hoopingDrag = nil; screenStart = nil; dragProblem = nil; needsDisplay = true
    }
    /// Cancels a drag of objects, nodes, markers, angle lines, artwork or stitches when the design changed since the
    /// mouse went down (Undo pressed mid-drag). Returns true if it did.
    private func dropDragIfDesignChanged() -> Bool {
        guard state.revision != dragRevision, stitchDrag != nil || dragSnapshot != nil else { return false }
        stitchDrag = nil; stitchPreview = nil; preview = nil; dragSnapshot = nil; dragStart = nil; angleDrag = nil; fillAngleDrag = nil; guideDrag = nil
        draggedNode = nil; draggedHandle = nil; draggedMarker = nil; artworkDrag = nil; hoopingDrag = nil; nodeJustAdded = false; dragProblem = nil; resizeDrag = nil; turnDrag = nil; artworkTurnDrag = nil; letterDrag = nil; envelopeDrag = nil; needsDisplay = true
        state.status = "The design changed during the drag, so the drag was cancelled."
        return true
    }
    /// Moves one Bézier handle to `target`. Both handles are first fixed at their current positions (smooth nodes
    /// start with automatic ones). Unless `independent` (Option held), the opposite handle swings to stay in a straight
    /// line through the node, keeping its own length, so the curve passes smoothly through the node.
    private func dragHandle(_ handle: (location: NodeLocation, outgoing: Bool), to target: Point, in design: inout Design, independent: Bool) {
        guard let objectIndex = design.objects.firstIndex(where: { $0.id == handle.location.object }),
              let current = effectiveHandles(design.objects[objectIndex], handle.location) else { return }
        func update(_ node: inout PathNode) {
            node.inHandle = current.incoming; node.outHandle = current.outgoing
            let other = handle.outgoing ? node.inHandle : node.outHandle
            if handle.outgoing { node.outHandle = target } else { node.inHandle = target }
            // Corner nodes keep their sharp angle: their handles always move independently.
            guard !independent, node.smooth, let other else { return }
            let pulled = target - node.point, length = hypot(pulled.x, pulled.y)
            guard length > 0.0001 else { return }
            let keep = other.distance(to: node.point)
            let mirrored = node.point - pulled * (keep / length)
            if handle.outgoing { node.inHandle = mirrored } else { node.outHandle = mirrored }
        }
        if handle.location.ring < 0 { update(&design.objects[objectIndex].nodes[handle.location.index]) }
        else { update(&design.objects[objectIndex].holes![handle.location.ring][handle.location.index]) }
    }
    /// The node list a node's curve is drawn from (its outline or hole ring, or its satin rail),
    /// whether that list closes into a loop, and the node's position in it.
    private func curveContext(_ object: RunObject, _ location: NodeLocation) -> (nodes: [PathNode], closed: Bool, index: Int)? {
        if location.ring >= 0 {
            guard let holes = object.holes, holes.indices.contains(location.ring), holes[location.ring].indices.contains(location.index) else { return nil }
            return (holes[location.ring], true, location.index)
        }
        guard object.nodes.indices.contains(location.index) else { return nil }
        if object.kind == .satin { return (object.nodes.enumerated().filter { $0.offset % 2 == location.index % 2 }.map(\.element), false, location.index / 2) }
        return (object.nodes, object.kind == .fill || object.closed, location.index)
    }
    private func nodePoint(_ object: RunObject, _ location: NodeLocation) -> Point {
        curveContext(object, location).map { $0.nodes[$0.index].point } ?? Point(0, 0)
    }
    /// The handles a node shows. A smooth node shows its own handles, or the automatic ones its curve already uses;
    /// a corner node (for example from an imported SVG) shows only the handles it actually has.
    /// A handle is nil where no curve uses it (before the first node or after the last of an open path).
    private func effectiveHandles(_ object: RunObject, _ location: NodeLocation) -> (incoming: Point?, outgoing: Point?)? {
        guard object.kind != .raw, let (nodes, closed, index) = curveContext(object, location), nodes.count >= 2 else { return nil }
        let node = nodes[index]
        guard node.smooth || node.hasHandles else { return nil }
        let automatic = node.smooth ? RunningEngine.automaticHandles(nodes, closed: closed, index: index) : (incoming: node.point, outgoing: node.point)
        let incoming = node.inHandle ?? (node.smooth ? automatic.incoming : nil), outgoing = node.outHandle ?? (node.smooth ? automatic.outgoing : nil)
        return (closed || index > 0 ? incoming : nil, closed || index < nodes.count - 1 ? outgoing : nil)
    }
    /// The Start, End or Center marker of a selected, unlocked object under the pointer, if any.
    private func nearestMarker(_ p: Point) -> (object: UUID, kind: Marker)? {
        let reach = 9 / state.zoom
        let sewn = sewnEnds(), few = fewSelected(in: state.design)
        for object in state.design.objects.reversed() where state.selection.contains(object.id) && !object.locked && object.visible {
            let ends = markerPoints(object, sewn: sewn, few: few)
            if let start = ends.start, start.distance(to: p) < reach { return (object.id, .start) }
            if let end = ends.end, end.distance(to: p) < reach { return (object.id, .end) }
            if let center = radialCenter(object), center.distance(to: p) < reach { return (object.id, .center) }
        }
        return nil
    }
    /// Where a radial fill's rays fan out from, or a ripple line's copies shrink toward (the middle of the shape
    /// unless moved); nil for other objects.
    private func radialCenter(_ object: RunObject) -> Point? {
        if object.kind == .run, object.settings.runStyle == .ripple, let path = object.outlinePaths.first, path.count >= 2 {
            return object.settings.radialCenter ?? RunningStyles.rippleTarget(path, closed: object.closed)
        }
        guard object.kind == .fill, object.settings.fillStyle == .radial, object.nodes.count >= 3 else { return nil }
        return object.settings.radialCenter ?? AreaGeometry.centroid(AreaGeometry.ring(object.nodes))
    }
    private func nearestHandle(_ p: Point) -> (location: NodeLocation, outgoing: Bool)? {
        guard let location = state.selectedNode, let object = state.design.objects.first(where: { $0.id == location.object }),
              !object.locked, object.visible, let handles = effectiveHandles(object, location) else { return nil }
        let reach = 9 / state.zoom
        if let out = handles.outgoing, out.distance(to: p) < reach { return (location, true) }
        if let incoming = handles.incoming, incoming.distance(to: p) < reach { return (location, false) }
        return nil
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) { state.zoom = min(60, max(0.5, state.zoom * pow(1.02, event.scrollingDeltaY))) }
        else { pan.x -= event.scrollingDeltaX; pan.y += event.scrollingDeltaY; needsDisplay = true }
    }
    override func magnify(with event: NSEvent) { state.zoom = min(60, max(0.5, state.zoom * (1 + event.magnification))) }
    override func keyDown(with event: NSEvent) { if !AppDelegate.shared.route(event) { super.keyDown(with: event) } }
    /// The selected, unlocked fill whose stitch angle line has an end within reach of `p` (model mm), if any.
    private func fillAngleEnd(near p: Point) -> UUID? {
        state.design.objects.first { object in
            guard state.selection.contains(object.id), !object.locked, object.lettering == nil, let ends = StitchAngleLine.ends(of: object) else { return false }
            return min(ends.0.distance(to: p), ends.1.distance(to: p)) <= 6 / state.zoom
        }?.id
    }
    /// Puts a fill's stitch angle line back where it starts out: across the whole shape, through its middle, as one
    /// undo step. The angle (and so the stitches) stays as it is.
    private func resetFillAngleLine(_ id: UUID) {
        guard let object = state.design.objects.first(where: { $0.id == id }),
              object.settings.angleLineCenter != nil || object.settings.angleLineLength != nil else {
            state.status = "The stitch angle line already crosses the whole shape."; return
        }
        state.edit("Reset Stitch Angle Line") { design in
            guard let i = design.objects.firstIndex(where: { $0.id == id }) else { return }
            design.objects[i].digitizing?.angleLineCenter = nil; design.objects[i].digitizing?.angleLineLength = nil
        }
        state.status = "Stitch angle line reset: it crosses the whole shape again, through the middle. The angle stays."
        needsDisplay = true
    }
    /// The selected, unlocked fill whose stitch angle line passes within reach of `p` (model mm), if any.
    private func fillAngleLine(near p: Point) -> UUID? {
        state.design.objects.first { object in
            guard state.selection.contains(object.id), !object.locked, object.lettering == nil, let ends = StitchAngleLine.ends(of: object) else { return false }
            return p.distance(to: AreaGeometry.projection(p, ends.0, ends.1)) <= 5 / state.zoom
        }?.id
    }
    /// The node within reach of `p` (model mm): the selected objects' nodes first, since they're the ones shown, and
    /// only if none is near, the nearest node of any other visible, unlocked object (clicking it selects that object).
    /// Where a click at `location` (on screen) picks up a selected shape the current tool can keep drawing: within 7
    /// points of one of its pick-up points (continuePicks), the nearest. Kept that small so a new shape can still start
    /// just beside the last one.
    private func continuePick(near location: CGPoint) -> ContinuePick? {
        var best: ContinuePick?, distance = 7.0
        for object in continuableObjects(state.design) {
            for (pick, points) in continuePicks(object) {
                for point in points {
                    let onScreen = screen(point), gap = hypot(onScreen.x - location.x, onScreen.y - location.y)
                    if gap < distance { distance = gap; best = pick }
                }
            }
        }
        return best
    }
    /// The selected shapes the current tool can keep drawing: lines (Running tool) or satin columns (Satin tool) from
    /// their ends, and fills or closed lines (Fill or Closed Shape tool) from any point of their outline.
    private func continuableObjects(_ design: Design) -> [RunObject] {
        let selected = design.objects.filter { state.selection.contains($0.id) && $0.visible }
        switch state.tool {
        case .run, .satin:
            let kind: StitchKind = state.tool == .satin ? .satin : .run
            return selected.filter { $0.kind == kind && $0.canContinueDrawing }
        case .fill, .closedShape: return selected.filter(\.canDrawInto)
        default: return []
        }
    }
    /// The places a click picks `object` up, each with the points it shows a ring on: an open line's or column's two
    /// ends (a column's end is both points of its end pair), or each point of a closed outline.
    private func continuePicks(_ object: RunObject) -> [(ContinuePick, [Point])] {
        if object.closed { return object.nodes.indices.map { (.after(object.id, index: $0), [object.nodes[$0].point]) } }
        let handles = object.continueHandles
        return [(.end(object.id, fromStart: true), handles.start), (.end(object.id, fromStart: false), handles.end)]
    }
    /// A small ring on each place continuePick would pick up, filled in under the pointer, so it's plain that clicking
    /// there carries the shape on. Under the pointer on a closed outline, the next point is filled in too, with a dashed
    /// line to it: the side the new points will go.
    private func drawContinueMarkers(_ design: Design) {
        func ring(_ point: Point, radius: CGFloat, filled: Bool) {
            let p = screen(point), shape = NSBezierPath(ovalIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            (filled ? Theme.Canvas.handle : NSColor.white).setFill(); shape.fill()
            Theme.Canvas.handle.setStroke(); shape.lineWidth = 1.5; shape.stroke()
        }
        for object in continuableObjects(design) {
            for (pick, points) in continuePicks(object) {
                for point in points { ring(point, radius: pick == hoveredPick ? 6 : 4.5, filled: pick == hoveredPick) }
            }
            if case .after(let id, let index) = hoveredPick, id == object.id, object.nodes.indices.contains(index) {
                let from = object.nodes[index].point, to = object.nodes[(index + 1) % object.nodes.count].point
                let side = NSBezierPath(); side.move(to: screen(from)); side.line(to: screen(to))
                Theme.Canvas.handle.setStroke(); side.lineWidth = 2; side.setLineDash([5, 4], count: 2, phase: 0); side.stroke()
                ring(from, radius: 6, filled: true); ring(to, radius: 5, filled: true)
            }
        }
    }
    private func nearestNode(_ p:Point)->NodeLocation? {
        func nearest(selected: Bool) -> NodeLocation? {
            var best:NodeLocation?,distance=9/state.zoom
            // Lettering has letter handles instead of nodes (see letterHandles).
            for object in state.design.objects.reversed() where object.visible && !object.locked && object.kind != .raw && object.lettering == nil && state.selection.contains(object.id) == selected {
                for (ring,nodes) in ([object.nodes]+(object.holes ?? [])).enumerated(){for (i,node) in nodes.enumerated(){let d=node.point.distance(to:p);if d<distance{distance=d;best=NodeLocation(object:object.id,ring:ring-1,index:i)}}}
            }
            return best
        }
        return nearest(selected: true) ?? nearest(selected: false)
    }
    func deleteNode() {
        guard state.tool == .node,let location=state.selectedNode,state.selectedPathNode != nil,let object=state.design.objects.first(where:{$0.id==location.object}),!object.locked else{state.status="Select a node with N first.";return}
        if object.kind == .satin {
            guard object.nodes.count>4 else{state.status="Satin requires at least two pairs.";return}
            let pair=location.index/2*2
            state.editSelected("Delete Satin Pair"){$0.nodes.removeSubrange(pair...(pair+1))}
        } else {
            let nodes=location.ring<0 ? object.nodes:object.holes![location.ring]
            guard nodes.count>(object.kind == .fill ? 3:2) else{state.status="Keep enough nodes to define this path.";return}
            state.editSelected("Delete Node"){object in if location.ring<0{object.nodes.remove(at:location.index)}else{object.holes![location.ring].remove(at:location.index)}}
        }
        state.selectedNode=nil
    }
    /// The edge of a selected, unlocked object nearest `p`, within `reach` mm: the object, the ring (-1 the outline,
    /// 0… a hole), the segment and the nearest point on it. For a satin, the centerline between two rungs.
    private func edge(near p: Point, reach: Double) -> (id: UUID, ring: Int, index: Int, point: Point)? {
        var candidate: (id: UUID, ring: Int, index: Int, point: Point)?, distance = reach
        for object in state.design.objects where state.selection.contains(object.id) && !object.locked && object.kind != .raw && object.lettering == nil {
            if object.kind == .satin {
                for i in stride(from:0,to:object.nodes.count-2,by:2) {
                    let a=(object.nodes[i].point+object.nodes[i+1].point)*0.5,b=(object.nodes[i+2].point+object.nodes[i+3].point)*0.5
                    let d=p.distance(to:AreaGeometry.projection(p,a,b))
                    if d<distance{distance=d;candidate=(object.id,-1,i,.init(0,0))}
                }
            } else {
                for (ring,nodes) in ([object.nodes]+(object.holes ?? [])).enumerated(){for (i,segment) in RunningEngine.flatten(nodes,closed:object.kind == .fill || object.closed).enumerated(){for (a,b) in zip(segment,segment.dropFirst()){let q=AreaGeometry.projection(p,a,b),d=p.distance(to:q);if d<distance{distance=d;candidate=(object.id,ring-1,i,q)}}}}
            }
        }
        return candidate
    }
    /// `design` with a node added on `edge`: a corner (`smooth` false), a curve node (true), or whatever keeps the
    /// curve exactly (nil). A satin gets a new rung instead. Also returns where the new node is (nil for a satin rung).
    private func addingNode(on edge: (id: UUID, ring: Int, index: Int, point: Point), smooth: Bool?, to design: Design) -> (design: Design, node: NodeLocation?) {
        var next = design
        guard let i = next.objects.firstIndex(where: { $0.id == edge.id }) else { return (design, nil) }
        let object = next.objects[i], index = edge.index
        if object.kind == .satin {
            let l=(object.nodes[index].point+object.nodes[index+2].point)*0.5,r=(object.nodes[index+1].point+object.nodes[index+3].point)*0.5
            next.objects[i].nodes.insert(contentsOf:[PathNode(l,smooth:smooth == true),PathNode(r,smooth:smooth == true)],at:index+2)
            return (next, nil)
        }
        // insertingNode keeps curves exactly as they were; `smooth` then makes the new node a corner or a curve node.
        let closed=edge.ring>=0 || object.kind == .fill || object.closed
        if edge.ring<0 {
            let added=RunningEngine.insertingNode(object.nodes,closed:closed,segment:index,near:edge.point,smooth:smooth)
            next.objects[i].nodes=added.nodes; return (next, NodeLocation(object:edge.id,ring:-1,index:added.index))
        }
        let added=RunningEngine.insertingNode(object.holes![edge.ring],closed:true,segment:index,near:edge.point,smooth:smooth)
        next.objects[i].holes![edge.ring]=added.nodes; return (next, NodeLocation(object:edge.id,ring:edge.ring,index:added.index))
    }
    /// Insert Node (a key): adds a node on the selected edge nearest the pointer, keeping the curve's shape.
    func insertNode() {
        guard state.tool == .node else{state.status="Use \(Preferences.shared.key(.nodeTool)), then point at an edge and press \(Preferences.shared.key(.insertNode)).";return}
        guard let edge=edge(near:pointer,reach:12/state.zoom) else{state.status="Point close to a selected edge (or a satin centerline) before inserting.";return}
        let added=addingNode(on:edge,smooth:nil,to:state.design)
        state.edit("Insert Node"){$0=added.design}
    }
    /// The topmost shown object under `p` (model mm), only looking at the objects in `ids` when given.
    /// Adds every shown, unlocked object lying wholly inside `box` (on screen) to the selection. A group counts only
    /// when all of its members are inside, so a box picks whole groups, as a click does.
    private func selectObjects(inside box: (start: CGPoint, end: CGPoint)) {
        let a = model(box.start), b = model(box.end)
        let (low, high) = (Point(min(a.x, b.x), min(a.y, b.y)), Point(max(a.x, b.x), max(a.y, b.y)))
        let inside = Set(state.design.objects.filter { object in
            let points = object.outlinePaths.flatMap { $0 }
            return state.isShown(object) && !object.locked && !points.isEmpty
                && points.allSatisfy { $0.x >= low.x && $0.x <= high.x && $0.y >= low.y && $0.y <= high.y }
        }.map(\.id))
        let picked = inside.filter { state.design.groupMembers(of: $0).isSubset(of: inside) }
        state.selection.formUnion(picked); state.selectedNode = nil
        state.status = state.selection.isEmpty ? "Nothing lies wholly inside the box." : "\(state.selection.count) object\(state.selection.count == 1 ? "" : "s") selected"
    }
    private func hit(_ p: Point, among ids: Set<UUID>? = nil) -> RunObject? {
        state.design.objects.reversed().first { object in
            guard state.isShown(object), ids?.contains(object.id) ?? true else { return false }   // what can't be seen can't be clicked
            if (object.kind == .fill || (object.kind == .vector && object.closed)),AreaGeometry.contains(p,rings:([object.nodes]+(object.holes ?? [])).map{AreaGeometry.ring($0)}){return true}
            return object.outlinePaths.contains{segment in zip(segment,segment.dropFirst()).contains{a,b in p.distance(to:AreaGeometry.projection(p,a,b))<8/state.zoom}}
        }
    }

}

private extension NSBezierPath {
    var cgPathCopy: CGPath {
        let path = CGMutablePath(); let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: points) {
            case .moveTo: path.move(to: points[0]); case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath(); default: break
            }
        }
        return path
    }
}

/// A thin line on a ruler showing where the pointer is (DesignCanvas moves it). It never takes clicks: they go to the
/// canvas under it.
final class RulerMark: NSView {
    override func draw(_ dirtyRect: NSRect) { Theme.Canvas.pointerMark.setFill(); bounds.fill() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The four ways the canvas can show underlay: with everything (the usual), not at all, or on its own (the stitching on
/// top left out) for every object or only for the selected ones.
enum UnderlayView: Hashable { case shown, hidden, onlyAll, onlySelected }

/// Which stitches the canvas draws, by whether they're underlay, for the current UnderlayView and selection.
struct UnderlayFilter {
    var view: UnderlayView
    var selection: Set<UUID> = []
    /// Every stitch, underlay included (the Color Blend preview, and the canvas as usual).
    static let all = UnderlayFilter(view: .shown)
    /// True when the underlay-only view covers `command`'s object: every object, or a selected one.
    private func onlyUnderlay(_ command: StitchCommand) -> Bool {
        view == .onlyAll || (view == .onlySelected && command.objectID.map(selection.contains) == true)
    }
    /// True for stitches that are drawn: in an underlay-only view, an object it covers shows just its underlay.
    func shows(_ command: StitchCommand) -> Bool {
        let isUnderlay = command.underlay == true
        if view == .hidden { return !isUnderlay }
        return isUnderlay || !onlyUnderlay(command)
    }
    /// True for underlay stitches shown on their own, which are drawn as strongly as top stitching, not faint.
    func showsAlone(_ command: StitchCommand) -> Bool { command.underlay == true && onlyUnderlay(command) }
}
