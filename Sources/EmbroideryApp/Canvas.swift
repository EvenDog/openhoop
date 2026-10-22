// The native drawing surface handles millimeter coordinates, tracing, node edits, and selection.
// During drags it draws a temporary snapshot, committing one document edit on mouse-up.
import AppKit
import Combine
import EmbroideryCore

extension ThreadColor {
    var nsColor: NSColor { NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1) }
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
    private var shapeStart: Point?    // while dragging out a rectangle, ellipse or basic shape: where the drag began
    private var freehandStroke: [Point]?   // while drawing with a Freehand tool: the points the pointer has passed through, in mm
    /// True while a rectangle, ellipse or basic shape is being dragged out.
    var isDraggingShape: Bool { shapeStart != nil }
    /// Escape mid-drag: forgets the shape being dragged (or the freehand stroke), so moving on and letting go add nothing.
    func cancelShapeDrag() { shapeStart = nil; freehandStroke = nil; needsDisplay = true }
    /// The markers shown on a selected object: where it starts and ends sewing, and a radial fill's center.
    private enum Marker { case start, end, center }
    private var draggedMarker: (object: UUID, kind: Marker)?   // a marker being dragged
    /// A resize handle being dragged (Select tool): which sides it moves (-1 left/bottom, 1 right/top, 0 neither), and
    /// the selection's box (mm) when the drag began.
    private var resizeDrag: (dx: Int, dy: Int, low: Point, high: Point)?
    /// A letter being moved with Edit Nodes: its lettering, its letter key, and its parts.
    private var letterDrag: (lettering: UUID, key: Int, parts: Set<UUID>)?
    private var artworkDrag: Int?   // adjusting the artwork: -1 moves it, 0…3 resizes from that corner
    private var hoopingDrag: Int?   // the hooping being dragged with the Hoopings tool
    private var zoomBox: (start: CGPoint, end: CGPoint)?   // the box being dragged with the Zoom Box tool, in canvas points
    private var selectBox: (start: CGPoint, end: CGPoint)?   // a box dragged from empty canvas with Select, in canvas points
    var measurement: (start: Point, end: Point)?   // the Measure tool's line, in mm; shown until the tool changes
    private var measuring = false   // true while that line is being dragged
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
    /// instead of turning it.
    private var fillAngleDrag: (object: UUID, pointer: Point, slideFrom: Point?)?
    /// A guide line being dragged: its place in the design's guides, which way it runs, whether it's being dragged out
    /// of a ruler (not added yet), and where the pointer is (its position reads out beside it).
    private var guideDrag: (index: Int, vertical: Bool, isNew: Bool, pointer: CGPoint)?
    /// The guide the pointer is over with Select (its place in the design's guides), shown by a ↔ or ↕ pointer.
    private(set) var hoveredGuide: Int?
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
            DispatchQueue.main.async { self?.needsDisplay = true; if self?.rulersShown == false { self?.moveRulerMarks(to: nil) } }
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
    /// and brightest half way along, so a satin column looks rounded and a fill shows each stitch. A soft shadow lifts
    /// the stitches off the cloth, and when zoomed in far enough, faint slanted marks show the thread's twist.
    /// Stitches are drawn in sewing order in batches of up to 48 in one thread, so later stitches lie over earlier
    /// ones while each batch costs only a few fills. Travel moves and needle points aren't drawn: the
    /// machine trims the travel, and the needle holes are hidden under the thread. Stitches off screen are skipped.
    /// `start` is where the needle stands before the first command (the end of the stitches drawn before these).
    private func drawThread(_ context: CGContext, _ commands: ArraySlice<StitchCommand>, from start: Point = Point(0, 0), threads: [ThreadColor], hidden: Set<UUID>, showUnderlay: Bool,
                            width: Double, visibleArea: CGRect, onScreen: (Point) -> CGPoint) {
        // The strand is built from stacked layers, each a little shorter, narrower and lighter than the one below,
        // which together shade it from dark ends to a bright middle. `tone` darkens (below 0) or lightens (above 0)
        // the thread's color; `breadth` is the layer's width as a fraction of the thread's; `trim` shortens it at each
        // end, as a fraction of the stitch's length.
        let layers: [(tone: Double, breadth: Double, trim: Double)] = [(-0.45, 1, 0), (-0.2, 0.95, 0.06), (0, 0.9, 0.14), (0.18, 0.8, 0.24), (0.32, 0.6, 0.34)]
        func shades(_ color: NSColor) -> [CGColor] {
            layers.map { ($0.tone < 0 ? color.blended(withFraction: -$0.tone, of: .black) : color.blended(withFraction: $0.tone, of: .white)) ?? color }.map(\.cgColor)
                + [(color.blended(withFraction: 0.35, of: .black) ?? color).withAlphaComponent(0.22).cgColor]   // last: the twist marks
        }
        let threadShades = threads.map { shades($0.nsColor) }, unknownShades = shades(.systemTeal)
        let shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        let shadowOffset = CGVector(dx: width * 0.25, dy: -width * 0.3)   // down and to the right, away from the top-left light
        let showTwist = width >= 5   // the marks would only blur into the color when the thread is drawn narrower
        let reach = visibleArea.insetBy(dx: -width, dy: -width)
        // Per layer, the batch's bulging middles (filled) and the lines along them (stroked with round caps, for
        // rounded ends about 70% as wide as the middle, so neighbouring stitches cover the cloth).
        var shadows = CGMutablePath(), twists = CGMutablePath()
        var middles = layers.map { _ in CGMutablePath() }, cores = layers.map { _ in CGMutablePath() }
        var batchThread: Int?, batchShades = unknownShades, batchCount = 0
        func drawBatch() {
            guard batchCount > 0 else { return }
            context.setFillColor(shadowColor); context.addPath(shadows); context.fillPath()
            for (index, layer) in layers.enumerated() {
                context.setFillColor(batchShades[index]); context.addPath(middles[index]); context.fillPath()
                context.setStrokeColor(batchShades[index]); context.setLineWidth(width * layer.breadth * 0.7); context.addPath(cores[index]); context.strokePath()
            }
            if showTwist { context.setStrokeColor(batchShades[layers.count]); context.setLineWidth(max(0.6, width * 0.07)); context.addPath(twists); context.strokePath() }
            shadows = CGMutablePath(); twists = CGMutablePath()
            middles = layers.map { _ in CGMutablePath() }; cores = layers.map { _ in CGMutablePath() }; batchCount = 0
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
            guard command.op == .stitch, command.objectID.map({ !hidden.contains($0) }) ?? true, showUnderlay || command.underlay != true else { continue }
            let a = onScreen(previous), b = onScreen(command.point)
            let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -0.5, dy: -0.5)
            guard box.intersects(reach) else { continue }
            if batchThread != command.thread || batchCount >= 48 {
                drawBatch(); batchThread = command.thread
                batchShades = threadShades.indices.contains(command.thread) ? threadShades[command.thread] : unknownShades
            }
            // `along` runs from a to b; `across` is at right angles to it.
            let along = CGVector(dx: b.x - a.x, dy: b.y - a.y), length = max(hypot(along.dx, along.dy), 0.001)
            let across = CGVector(dx: -along.dy / length, dy: along.dx / length)
            addLens(shadows, CGPoint(x: a.x + shadowOffset.dx, y: a.y + shadowOffset.dy), CGPoint(x: b.x + shadowOffset.dx, y: b.y + shadowOffset.dy), breadth: width * 1.1, across: across)
            for (index, layer) in layers.enumerated() {
                let start = CGPoint(x: a.x + along.dx * layer.trim, y: a.y + along.dy * layer.trim)
                let end = CGPoint(x: b.x - along.dx * layer.trim, y: b.y - along.dy * layer.trim)
                addLens(middles[index], start, end, breadth: width * layer.breadth, across: across)
                cores[index].move(to: start); cores[index].addLine(to: end)
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
        if state.tool != .measure { measurement = nil; measuring = false }
        hoveredGuide = nil
        window?.invalidateCursorRects(for: self); needsDisplay = true
    }
    /// The pointer the current tool uses on the canvas.
    private var toolCursor: NSCursor {
        state.tool == .pan || state.tool == .artwork ? .openHand : state.tool == .text ? .iBeam : state.tool.draws || state.tool.dragsShape || state.tool.freehand || state.tool == .entryExit || state.tool == .zoomBox || state.tool == .measure || state.tool == .branch || state.tool == .addAngles || state.tool == .removeAngles || state.tool == .stitchEdit ? .crosshair : .arrow
    }
    /// ↔ for an up-and-down guide, ↕ for a side-to-side one.
    private func guideCursor(vertical: Bool) -> NSCursor { vertical ? .resizeLeftRight : .resizeUpDown }
    /// With Select, the pointer turns ↔ or ↕ over a guide wherever a drag would grab it (no object under it), and back
    /// when it moves off. Cursor areas mustn't overlap the canvas's own (resetCursorRects), so the pointer is set
    /// directly, only when it moves on or off a guide.
    private func updateGuideCursor(at location: CGPoint) {
        let over = state.tool == .select && guideDrag == nil ? guide(near: location).flatMap { hit(model(location)) == nil ? $0 : nil } : nil
        guard over != hoveredGuide else { return }
        hoveredGuide = over
        if let over { guideCursor(vertical: state.design.guides![over].vertical).set() } else { toolCursor.set() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: toolCursor) }
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
    /// The reference image's rectangle on screen.
    func artworkRect(_ artwork: Artwork) -> CGRect {
        CGRect(x: screen(artwork.center).x - artwork.width * state.zoom / 2, y: screen(artwork.center).y - artwork.height * state.zoom / 2, width: artwork.width * state.zoom, height: artwork.height * state.zoom)
    }


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
            let rect = CGRect(x: screen(artwork.center).x - artwork.width * state.zoom / 2, y: screen(artwork.center).y - artwork.height * state.zoom / 2, width: artwork.width * state.zoom, height: artwork.height * state.zoom)
            image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: state.artworkOpacityPreview ?? artwork.opacity)   // live while its slider is dragged
            // While adjusting it, the image gets a frame and corner handles.
            if state.tool == .artwork {
                Theme.Canvas.handle.setStroke(); let frame = NSBezierPath(rect: rect); frame.lineWidth = 1.5; frame.stroke()
                for corner in artwork.corners.map(screen) {
                    let knob = NSBezierPath(rect: CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10))
                    NSColor.white.setFill(); knob.fill(); Theme.Canvas.handle.setStroke(); knob.lineWidth = 1.5; knob.stroke()
                }
            }
        }
        let artworkLayer = design.artworkLayer
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
        // to the preview's, drawn after the rest (PictureMenu.swift).
        let menuPreview = state.settingsPreview
        var hidden = userHidden.union(menuPreview?.objects ?? [])
        var previous = Point(0, 0)
        // This loop runs once per stitch (tens of thousands of times), and it runs on every frame of a window resize,
        // so everything it needs is read once up here: reading the editor state's @Published values or making a new
        // color inside the loop made each redraw too slow to keep up with the pointer.
        let plan = state.plan, zoom = state.zoom, center = origin, visibleArea = bounds
        let showUnderlay = state.showUnderlay, showNeedles = state.needles && zoom >= 3, threadView = Preferences.shared.threadView
        let showStitches = state.showStitches, showConnectors = state.showsConnectors, thinLines = showStitches && !threadView
        func onScreen(_ p: Point) -> CGPoint { CGPoint(x: center.x + p.x * zoom, y: center.y + p.y * zoom) }   // same as screen(_:)
        // Each thread's stitch color, made once: [normal, underlay (fainter)].
        func colors(_ threads: [ThreadColor]) -> [[CGColor]] { threads.map { thread in [0.95, 0.40].map { thread.nsColor.withAlphaComponent($0).cgColor } } }
        var threads = plan.threads, threadColors = colors(threads)
        let unknownThread = [0.95, 0.40].map { NSColor.systemTeal.withAlphaComponent($0).cgColor }
        // While reviewing the sewing order, the design is sewn up to the end of the step being looked at; otherwise
        // the stitch player says how much is sewn.
        let review = state.reviewStep?.step
        let commands = plan.commands.prefix(review?.commands.upperBound ?? Int(Double(plan.commands.count) * state.playback))
        context.setLineWidth(1.1); context.setLineCap(.round)
        var needles = CGMutablePath()
        var activeColor: CGColor?
        /// Draws `part` of the stitches (thread or thin lines, and travel moves), carrying on from where the last part ended.
        func drawStitches(_ part: ArraySlice<StitchCommand>) {
            if threadView && showStitches { drawThread(context, part, from: previous, threads: threads, hidden: hidden, showUnderlay: showUnderlay, width: max(1.2, 0.45 * zoom), visibleArea: visibleArea, onScreen: onScreen) }
            // The thin-line stitch view, travel moves dashed, and needle points (in either view).
            for command in part where thinLines || showConnectors || showNeedles {
                let visible = (command.objectID.map { !hidden.contains($0) } ?? true) && (showUnderlay || command.underlay != true)
                let p = onScreen(command.point)
                if command.op == .stitch && visible {
                    if thinLines {
                        let colors = threadColors.indices.contains(command.thread) ? threadColors[command.thread] : unknownThread
                        let color = colors[command.underlay == true ? 1 : 0]
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
        drawStitches(commands[..<split])
        if artworkLayer > 0 { drawArtwork() }
        drawStitches(commands[split...])
        if let menuPreview, let first = menuPreview.plan.commands.first {
            hidden = userHidden; threads = menuPreview.plan.threads; threadColors = colors(threads); previous = first.point
            drawStitches(menuPreview.plan.commands[...])
        }
        // On thread, each needle point gets a light ring so it shows on any thread color.
        if threadView && showStitches { context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor); context.setLineWidth(0.8); context.addPath(needles); context.strokePath() }
        context.setFillColor(Theme.Canvas.needle.cgColor); context.addPath(needles); context.fillPath()
        if state.showDensity { drawDensityMap(context) }
        if let review, let travel = review.travel { drawTravel(travel, to: review.start) }
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
                    // While an object shows a choice from a picture menu, its outline is terracotta, so it reads as a try-out.
                    let trying = menuPreview.map { !$0.kept && $0.objects.contains(object.id) } ?? false
                    (broken ? NSColor.systemRed : trying ? Theme.Canvas.previewOutline : selected ? Theme.Canvas.selection : object.color.nsColor.withAlphaComponent(0.4)).setStroke(); path.lineWidth = broken ? 2 : 1
                    if selected { path.setLineDash([2, 2], count: 2, phase: 0) }; path.stroke()
                }
            }
            // Where it starts and ends sewing (drawn before its nodes, so a node on the same spot stays on top).
            if selected {
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
            // A fill's stitch angle shows as a line across it with Edit Nodes; dragging an end turns the stitches.
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
        if !state.draft.isEmpty {
            var object=RunObject(name:"Draft",nodes:state.draft,color:state.currentColor)
            if state.tool == .satin {object.digitizing=DigitizingSettings(kind:.satin)}
            if state.tool.drawsClosed {object.closed=true}
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
        if state.tool == .select && !state.hasVersionMismatch, let box = selectionBox(in: design) { drawResizeHandles(box) }
        if state.tool == .node { for letter in letterHandles(in: design) { drawLetterHandle(letter.point, active: letterDrag?.key == letter.key && letterDrag?.lettering == letter.lettering) } }
        if state.tool == .branch, let start = state.branchPoints.first { drawMarker(start, label: "Branch start", color: Theme.Canvas.entry) }
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
    /// A letter's handle: a small diamond in the accent color (filled while it's being dragged).
    private func drawLetterHandle(_ p: CGPoint, active: Bool) {
        let diamond = NSBezierPath()
        diamond.move(to: CGPoint(x: p.x, y: p.y + 5)); diamond.line(to: CGPoint(x: p.x + 5, y: p.y)); diamond.line(to: CGPoint(x: p.x, y: p.y - 5)); diamond.line(to: CGPoint(x: p.x - 5, y: p.y)); diamond.close()
        (active ? Theme.Canvas.selection : NSColor.white).setFill(); diamond.fill()
        Theme.Canvas.selection.setStroke(); diamond.lineWidth = 1.5; diamond.stroke()
    }
    /// The resize handles: small dark squares with a white edge, so they show on any thread or fabric.
    private func drawResizeHandles(_ box: CGRect) {
        for handle in resizeHandles(box) {
            let square = NSBezierPath(rect: CGRect(x: handle.point.x - 3.5, y: handle.point.y - 3.5, width: 7, height: 7))
            NSColor(white: 0.2, alpha: 1).setFill(); square.fill(); NSColor.white.setStroke(); square.lineWidth = 1; square.stroke()
        }
    }
    /// While reviewing: the way from where the step before ended (a faint ×) to this step's start, dashed, with what
    /// happens on the way beside it, such as "Trim, then 18.6 mm".
    private func drawTravel(_ travel: SewingTravel, to start: Point) {
        let a = screen(travel.from), b = screen(start)
        let line = NSBezierPath(); line.move(to: a); line.line(to: b); line.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.7).setStroke(); line.lineWidth = 3.5; line.stroke()   // keeps it clear on any thread
        Theme.Canvas.handle.setStroke(); line.lineWidth = 1.5; line.setLineDash([5, 4], count: 2, phase: 0); line.stroke()
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current?.cgContext.setAlpha(0.5)
        drawEndMarker(travel.from)
        NSGraphicsContext.restoreGraphicsState()
        // The label sits beside the line's middle, on a light backing like the other canvas labels.
        let text = travel.summary(unit: Preferences.shared.unit), width = labelWidth(text, size: 11)
        let middle = CGPoint(x: (a.x + b.x) / 2 + 10, y: (a.y + b.y) / 2 - 9)
        Theme.Canvas.ruler.withAlphaComponent(0.92).setFill()
        let backing = NSBezierPath(roundedRect: CGRect(x: middle.x, y: middle.y, width: width + 12, height: 18), xRadius: 9, yRadius: 9)
        backing.fill(); Theme.Canvas.handle.setStroke(); backing.lineWidth = 0.75; backing.stroke()
        drawLabel(text, at: CGPoint(x: middle.x + 6, y: middle.y + 2), size: 11, color: Theme.Canvas.handle)
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
    /// Puts the rulers' pointer marks at `location` (on screen), or hides them for nil or with the rulers off. Each
    /// hides while the pointer is over the other ruler, so the corner where the rulers meet stays clear.
    private func moveRulerMarks(to location: CGPoint?) {
        guard let location, rulersShown else { topRulerMark.isHidden = true; leftRulerMark.isHidden = true; return }
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
        let location = convert(event.locationInWindow, from: nil)
        if state.tool == .zoomBox { zoomBox = (location, location); return }   // zooming works in older projects too
        // Dragging out of a ruler adds a guide: down from the top ruler a horizontal one, right from the left ruler a
        // vertical one. (The corner where the rulers meet does nothing.)
        let inTopRuler = overOwnRuler(location, vertical: false), inLeftRuler = overOwnRuler(location, vertical: true)
        if rulersShown && inTopRuler != inLeftRuler {
            guard !state.hasVersionMismatch else { return }
            guideDrag = ((state.design.guides ?? []).count, inLeftRuler, true, location); dragSnapshot = state.design
            guideCursor(vertical: inLeftRuler).set(); return
        }
        if state.tool == .measure { let point = snapped(model(location)); measurement = (point, point); measuring = true; needsDisplay = true; return }
        if state.tool == .text { state.addLettering(at: snapped(model(location))); return }
        if state.tool == .branch { state.addBranchPoint(snapped(model(location))); return }
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
        // With Edit Nodes, grabbing an end of a selected fill's stitch angle line starts swinging it (nodes and handles
        // still come first).
        if state.tool == .node, !state.hasVersionMismatch, nearestNode(model(location)) == nil, nearestHandle(model(location)) == nil,
           let fill = fillAngleEnd(near: model(location)) {
            fillAngleDrag = (fill, model(location), nil); dragSnapshot = state.design
            state.status = "Drag to turn the stitches · let go to keep the new angle"
            needsDisplay = true; return
        }
        guard !state.hasVersionMismatch else { return }
        let point = snapped(model(location))
        if state.tool.draws {
            if event.clickCount == 2 { state.finishPath(); return }
            // With nothing drawn yet, a click on an end of a selected open line (Running tool) or satin column (Satin
            // tool) picks it up there, to carry on drawing it.
            if state.draft.isEmpty, let end = continuableEnd(near: location) { state.continueDrawing(end.id, fromStart: end.fromStart); return }
            state.draft.append(PathNode(point, smooth: event.modifierFlags.contains(.control)))
            drawingHandle = state.draft.count - 1; return
        }
        if state.tool.dragsShape { shapeStart = point; return }
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
            // A corner handle resizes; anywhere on the image moves it; elsewhere nothing happens.
            guard let artwork = state.design.artwork, artwork.visible else { return }
            let corners = artwork.corners.map(screen)
            if let corner = corners.indices.first(where: { hypot(corners[$0].x - location.x, corners[$0].y - location.y) <= 9 }) { artworkDrag = corner }
            else if artworkRect(artwork).contains(location) { artworkDrag = -1 } else { return }
            dragStart = model(location); dragSnapshot = state.design; return
        }
        // Markers sit on top of everything, so grabbing one wins over selecting or setting a new point.
        if state.tool == .select || state.tool == .entryExit, let marker = nearestMarker(point) {
            draggedMarker = marker; dragStart = point; dragSnapshot = state.design; return
        }
        // A resize handle round the selection: dragging it resizes the selection from the opposite side or corner.
        if state.tool == .select, !state.hasVersionMismatch, let box = selectionBox(in: state.design),
           let handle = resizeHandles(box).first(where: { hypot($0.point.x - location.x, $0.point.y - location.y) <= 6 }) {
            resizeDrag = (handle.dx, handle.dy, model(CGPoint(x: box.minX, y: box.minY)), model(CGPoint(x: box.maxX, y: box.maxY)))
            dragStart = point; dragSnapshot = state.design; return
        }
        if state.tool == .entryExit { setEntryOrExit(at: point, exit: event.modifierFlags.contains(.option)); return }
        pointer=point
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
        // Pressing on the stitch angle line itself (between its ends) picks it up to move it somewhere else.
        if state.tool == .node, !state.hasVersionMismatch, let fill = fillAngleLine(near: model(location)) {
            fillAngleDrag = (fill, model(location), model(location)); dragSnapshot = state.design
            state.status = "Drag to move the stitch angle line · drag one of its ends to turn the stitches"
            needsDisplay = true; return
        }
        // With Select, a guide can be grabbed wherever no object is under the pointer.
        if state.tool == .select, !state.hasVersionMismatch, hit(point) == nil, let index = guide(near: location) {
            guideDrag = (index, state.design.guides![index].vertical, false, location); dragSnapshot = state.design
            guideCursor(vertical: state.design.guides![index].vertical).set()
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
            if event.modifierFlags.contains(.shift) { state.select(object.id, extend: true, single: single) }
            else if !state.selection.contains(object.id) || single { state.select(object.id, single: single) }
            dragStart = point; dragSnapshot = state.design
        } else if state.tool == .select {
            // Empty canvas: start a selection box. Shift keeps what's already selected.
            if !event.modifierFlags.contains(.shift) { state.selection = [] }
            selectBox = (location, location)
        } else { state.selection = [] }
    }
    override func rightMouseDown(with event: NSEvent) {
        state.focusCanvas()
        let point = snapped(model(convert(event.locationInWindow, from: nil)))
        if state.tool.draws && !state.hasVersionMismatch { state.draft.append(PathNode(point, smooth: true)) }
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
    override func mouseMoved(with event:NSEvent){pointer=model(convert(event.locationInWindow,from:nil));state.pointer.position=pointer;moveRulerMarks(to:convert(event.locationInWindow,from:nil));if state.angleStart != nil{needsDisplay=true};updateGuideCursor(at:convert(event.locationInWindow,from:nil))}
    override func mouseExited(with event: NSEvent) { state.pointer.position = nil; hoveredGuide = nil; moveRulerMarks(to: nil) }
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        state.pointer.position = model(location); moveRulerMarks(to: location)
        if let start = screenStart { pan = CGPoint(x: panStart.x + location.x - start.x, y: panStart.y + location.y - start.y); needsDisplay = true; return }
        if let box = zoomBox { zoomBox = (box.start, location); needsDisplay = true; return }
        if let box = selectBox { selectBox = (box.start, location); needsDisplay = true; return }
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
            } else {
                let angle = StitchAngleLine.angle(of: next.objects[i], toward: model(location))
                next.objects[i].digitizing?.angle = angle
            }
            fillAngleDrag = (drag.object, model(location), drag.slideFrom); preview = next; needsDisplay = true; return
        }
        if measuring, let line = measurement {
            measurement = (line.start, snapped(model(location)))
            state.status = "Measured " + Self.measurementText(from: line.start, to: measurement!.end, unit: Preferences.shared.unit)
            needsDisplay = true; return
        }
        if freehandStroke != nil {
            // The stroke follows the pointer; points closer than 0.1 mm are skipped (finishing smooths it anyway).
            let p = model(location)
            if freehandStroke!.last.map({ $0.distance(to: p) >= 0.1 }) ?? true { freehandStroke!.append(p); state.draft.append(PathNode(p)) }
            needsDisplay = true; return
        }
        if let start = shapeStart {
            // ⌘ keeps the shape even (a square, circle or regular shape); ⇧ grows it out
            // from where the drag began. Ellipses always grow from their center.
            let shape = state.tool.draggedShape ?? .rectangle
            let even = event.modifierFlags.contains(.command)
            let box = ShapeGeometry.box(from: start, to: snapped(model(location)), even: even, fromCenter: shape == .ellipse || event.modifierFlags.contains(.shift))
            let tooSmall = box.max.x - box.min.x < 1 || box.max.y - box.min.y < 1   // under 1 mm: still just a click
            state.draft = tooSmall ? [] : ShapeGeometry.nodes(shape, in: box, settings: Preferences.shared.shapes, keepProportions: even)
            needsDisplay = true; return
        }
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
        if let index = hoopingDrag, let before = dragSnapshot?.multiHooping?.hoopings, before.indices.contains(index) {
            next.multiHooping!.hoopings[index].center = before[index].center + (snapped(model(location)) - start)
            preview = next; needsDisplay = true; return
        }
        if let corner = artworkDrag, let artwork = next.artwork {
            next.artwork = artwork.adjusted(corner: corner, from: start, to: snapped(model(location)), free: event.modifierFlags.contains(.shift))
            preview = next; needsDisplay = true; return
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
        if measuring { measuring = false; return }
        if dropDragIfDesignChanged() { return }
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
            hoveredGuide = nil; toolCursor.set(); updateGuideCursor(at: convert(event.locationInWindow, from: nil)); return
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
            shapeStart = nil
            if state.draft.isEmpty { state.status = state.tool == .ellipse ? "Drag out the ellipse from its center: hold ⌘ for a circle." : "Drag to draw the shape: hold ⌘ to keep it even, ⇧ to draw it from the center." }
            else { state.finishShape(state.tool.draggedShape ?? .rectangle) }
            return
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
        if let drag = fillAngleDrag, drag.slideFrom == nil, let angle = preview?.objects.first(where: { $0.id == drag.object })?.settings.angle { state.status = "Stitch angle \(Int(angle))°" }
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
        draggedNode = nil; draggedHandle = nil; draggedMarker = nil; artworkDrag = nil; hoopingDrag = nil; nodeJustAdded = false; dragProblem = nil; resizeDrag = nil; letterDrag = nil; needsDisplay = true
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
    /// The selected, unlocked fill whose stitch angle line passes within reach of `p` (model mm), if any.
    private func fillAngleLine(near p: Point) -> UUID? {
        state.design.objects.first { object in
            guard state.selection.contains(object.id), !object.locked, object.lettering == nil, let ends = StitchAngleLine.ends(of: object) else { return false }
            return p.distance(to: AreaGeometry.projection(p, ends.0, ends.1)) <= 5 / state.zoom
        }?.id
    }
    /// The node within reach of `p` (model mm): the selected objects' nodes first, since they're the ones shown, and
    /// only if none is near, the nearest node of any other visible, unlocked object (clicking it selects that object).
    /// The selected line or satin the current tool can carry on, and which end, when `location` (on screen) is within
    /// 7 points of one of its end points: a line's first or last point, or either point of a column's first or last
    /// edge pair. Kept that small so a new column can still start just beside the last one.
    private func continuableEnd(near location: CGPoint) -> (id: UUID, fromStart: Bool)? {
        guard state.tool == .run || state.tool == .satin else { return nil }
        let kind: StitchKind = state.tool == .satin ? .satin : .run
        var best: (id: UUID, fromStart: Bool)?, distance = 7.0
        for object in state.design.objects where state.selection.contains(object.id) && object.visible && object.kind == kind && object.canContinueDrawing {
            let handles = object.continueHandles
            for (points, fromStart) in [(handles.start, true), (handles.end, false)] {
                for point in points {
                    let onScreen = screen(point), gap = hypot(onScreen.x - location.x, onScreen.y - location.y)
                    if gap < distance { distance = gap; best = (object.id, fromStart) }
                }
            }
        }
        return best
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
        guard state.tool == .node,let location=state.selectedNode,let object=state.design.objects.first(where:{$0.id==location.object}),!object.locked else{state.status="Select a node with N first.";return}
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
