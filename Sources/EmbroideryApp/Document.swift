// NSDocument owns editable state, undo history, package storage and cancellable stitch generation.
import AppKit
import Combine
import EmbroideryCore

/// Where the pointer is over the canvas, in mm (nil when it's elsewhere). It's separate from EditorState so the
/// many pointer moves only redraw the status bar's readout, not every panel.
@MainActor final class PointerReadout: ObservableObject { @Published var position: Point? }

enum Tool: String, Codable { case select, run, satin, fill, hole, node, pan, entryExit, artwork,   // artwork: move and size the reference image
    openShape, closedShape, rectangle, ellipse, basicShape,
    freehandOpen, freehandClosed,   // Freehand shapes: press and drag, the line follows the pointer, letting go finishes
    knife,     // click points across shapes, then Return cuts them along that line
    stitchEdit,   // Edit Stitch: select, move, delete and add one object's needle points
    addAngles, removeAngles,   // add stitch angle lines to a fill (two clicks each), or click one to remove it
    branch,    // Branching: click where the branch starts, then where it ends (Return lets OpenHoop choose)
    zoomBox,   // drag a box to zoom into it, then go back to the tool before
    measure    // drag to measure a distance and angle
    /// The tools that place points one click at a time.
    var draws:Bool {[.run,.satin,.fill,.hole,.openShape,.closedShape,.knife].contains(self)}
    /// The tools that drag out a whole shape at once.
    var dragsShape:Bool {[.rectangle,.ellipse,.basicShape].contains(self)}
    /// True when the outline being drawn closes back on itself.
    var drawsClosed:Bool {[.fill,.hole,.closedShape,.freehandClosed,.rectangle,.ellipse,.basicShape].contains(self)}
    /// The tools that draw a stroke following the pointer.
    var freehand:Bool {[.freehandOpen,.freehandClosed].contains(self)}
    /// The tools whose new object takes the Next shape bar's choices: one stitch for an open shape, a fill and an
    /// outline for a closed one.
    var isShapeTool:Bool {[.openShape,.closedShape,.freehandOpen,.freehandClosed].contains(self)}
    var makesOpenShape:Bool {self == .openShape || self == .freehandOpen}
    /// The shape a drag draws: the Rectangle and Ellipse tools' own, or the one picked for Basic Shapes. nil for
    /// tools that don't drag out shapes.
    @MainActor var draggedShape:BasicShape? {
        switch self {case .rectangle:return .rectangle;case .ellipse:return .ellipse;case .basicShape:return Preferences.shared.shapes.basicShape;default:return nil}
    }
    /// The tool each tool command turns on.
    static let forCommand:[CommandID:Tool]=[.selectTool:.select,.runTool:.run,.satinTool:.satin,.fillTool:.fill,.holeTool:.hole,.nodeTool:.node,.panTool:.pan,
        .entryExitTool:.entryExit,.artworkTool:.artwork,.openShapeTool:.openShape,.closedShapeTool:.closedShape,.freehandOpenTool:.freehandOpen,.freehandClosedTool:.freehandClosed,.rectangleTool:.rectangle,.ellipseTool:.ellipse,.basicShapeTool:.basicShape,.zoomBoxTool:.zoomBox,.measureTool:.measure,.knifeTool:.knife,.branching:.branch,.addStitchAngles:.addAngles,.removeStitchAngles:.removeAngles,.editStitches:.stitchEdit]
}
struct NodeLocation:Equatable {var object:UUID;var ring:Int;var index:Int}
/// One needle point of an object's stitches, for Edit Stitch: which section (run of stitches) and which point in it.
struct StitchRef:Hashable {var section:Int;var index:Int}

@MainActor final class EditorState: ObservableObject {
    weak var document: DesignDocument?
    weak var canvas: DesignCanvas?
    // The summary reads names and the fabric from the design too, so a design change clears it even when the
    // stitches can't be worked out (or aren't ready yet).
    @Published var design = Design() { didSet { planFacts = nil } }
    @Published var plan = StitchPlan() { didSet { planFacts = nil } }
    let pointer = PointerReadout()
    /// Numbers read from the current plan, worked out once per plan (a plan can have a million commands).
    private var planFacts: (summary: ProductionSummary, counts: [UUID: Int])?
    private var facts: (summary: ProductionSummary, counts: [UUID: Int]) {
        if let planFacts { return planFacts }
        let facts = (ProductionSummary(plan: plan, design: design), plan.stitchCountsByObject)
        planFacts = facts; return facts
    }
    /// The plan's stitch, thread, trim and stop counts, size and thread steps (as on the production worksheet).
    var summary: ProductionSummary { facts.summary }
    /// How many stitches each object sews.
    var stitchCounts: [UUID: Int] { facts.counts }
    @Published var selection: Set<UUID> = [] {
        didSet {
            // Keep the click order: drop what left the selection, then add what joined it. Objects that joined
            // together (a group, Select All) go in their sewing order.
            let joined = selection.subtracting(oldValue)
            selectionOrder.removeAll { !selection.contains($0) }
            if !joined.isEmpty { selectionOrder += design.objects.map(\.id).filter(joined.contains) }
            if let angle = selectedAngle, !selection.contains(angle.object) { selectedAngle = nil }
        }
    }
    /// The selected objects in the order they were selected (for Sequence by Selection Order and aligning).
    private(set) var selectionOrder: [UUID] = []
    @Published var tool: Tool = .select {
        // Angle lines only show with Edit Nodes or the angle tools; on any other, none can stay chosen (or Delete
        // would remove a line you can't see).
        didSet { if ![.node, .addAngles, .removeAngles].contains(tool) { selectedAngle = nil }; canvas?.toolDidChange() }
    }
    /// While the Zoom Box tool is on: the tool to go back to once the box is drawn.
    var toolBeforeZoom: Tool = .select
    @Published var selectedNode:NodeLocation?
    @Published var holeTarget:UUID?
    /// With Add or Remove Stitch Angles: the fill whose angle lines are being changed, and the first point of the
    /// line being added.
    var angleTarget:UUID?
    @Published var angleStart:Point?
    /// The stitch angle line clicked (a fill and which of its lines), which Delete removes; nil when none is.
    @Published var selectedAngle:(object:UUID,index:Int)?
    @Published var showUnderlay=true
    @Published var draft: [PathNode] = [] {
        didSet { if draft != oldValue { document?.draftDidChange() } }
    }
    @Published var currentColor = ThreadColor.palette[0]
    @Published var grid = true
    @Published var snap = false
    @Published var needles = true
    // What the canvas shows (the Show list). They're view choices, so they aren't saved or undone.
    @Published var showStitches = true
    @Published var showOutlines = false   // every object's outline, not just the selection's
    /// Travel moves between parts: nil until switched with ⇧C, and until then shown in the stitch view and hidden
    /// in Thread View. Once switched, the choice holds in both views.
    @Published var connectors: Bool?
    @Published var hideOthers = false   // show only the selection
    var showsConnectors: Bool { connectors ?? !Preferences.shared.threadView }
    /// True if the canvas shows the object: it isn't hidden, and if Hide Unselected is on, it's selected (with
    /// nothing selected, everything shows).
    func isShown(_ object: RunObject) -> Bool { object.visible && (!hideOthers || selection.isEmpty || selection.contains(object.id)) }
    @Published var busy = false
    @Published var exporting = false
    @Published var generationError: String?
    /// The objects that can't be sewn while there's a stitch error: outlined in red, while the rest show fresh stitches.
    @Published var brokenObjects: Set<UUID> = []
    @Published var zoom = 5.0
    @Published var playback = 1.0
    @Published var playing = false
    @Published var status = "Choose Running Stitch (\(Preferences.shared.key(.runTool))) to begin tracing."
    var revision = 0
    var compiledRevision = -1
    var selected: RunObject? { design.objects.first { selection.contains($0.id) } }
    var hasVersionMismatch: Bool { design.engineVersion != Design.engineVersion }
    func focusCanvas() { canvas?.window?.makeFirstResponder(canvas) }
    // MARK: Artwork opacity slider
    /// The artwork's opacity while its slider is dragged: the canvas shows it live, and letting go saves it as one
    /// step you can undo (rather than one for every little movement of the slider).
    @Published var artworkOpacityPreview: Double?
    private var draggingArtworkOpacity = false
    /// A new value from the slider. Outside a drag (such as from the keyboard) it's saved straight away.
    func previewArtworkOpacity(_ value: Double) {
        artworkOpacityPreview = value
        if !draggingArtworkOpacity { saveArtworkOpacity() }
    }
    /// The slider's drag starting (true) or ending (false); the end saves the last value.
    func artworkOpacitySlider(editing: Bool) {
        draggingArtworkOpacity = editing
        if !editing { saveArtworkOpacity() }
    }
    private func saveArtworkOpacity() {
        guard let value = artworkOpacityPreview else { return }
        artworkOpacityPreview = nil
        if value != design.artwork?.opacity { edit("Artwork Opacity") { $0.artwork?.opacity = value } }
    }
    /// Changes the design as one step you can undo. Returns false (and says why) in an older project, which must be
    /// regenerated before it can be edited, so callers don't report a change that didn't happen.
    @discardableResult func edit(_ name: String, _ block: (inout Design) -> Void) -> Bool {
        guard !hasVersionMismatch else { status = "Regenerate this older project before editing."; return false }
        var next = design; block(&next); document?.replace(next, action: name)
        if !playing { playback = 1 }   // after an edit, show the whole design rather than a paused part of it
        return true
    }
    func editSelected(_ name: String, _ block: (inout RunObject) -> Void) {
        edit(name) { next in for index in next.objects.indices where selection.contains(next.objects[index].id) && !next.objects[index].locked { block(&next.objects[index]) } }
    }
    /// The selected point (Edit Nodes), if it still exists.
    var selectedPathNode: PathNode? {
        guard let location = selectedNode, let object = design.objects.first(where: { $0.id == location.object }) else { return nil }
        let nodes = location.ring < 0 ? object.nodes : (object.holes ?? []).indices.contains(location.ring) ? object.holes![location.ring] : []
        return nodes.indices.contains(location.index) ? nodes[location.index] : nil
    }
    /// Makes the selected point a smooth (curve) point or a sharp corner, as one undoable step. A corner loses its
    /// handles; a new smooth point starts with automatic ones that follow its neighbours.
    func setSelectedNode(smooth: Bool) {
        guard let location = selectedNode, let node = selectedPathNode,
              design.objects.first(where: { $0.id == location.object })?.locked == false else {
            status = "Choose \(Preferences.shared.key(.nodeTool)) and click a point first, then switch it between corner and smooth."; return
        }
        guard node.smooth != smooth else { return }
        edit(smooth ? "Make Smooth Point" : "Make Corner Point") { design in
            guard let i = design.objects.firstIndex(where: { $0.id == location.object }) else { return }
            if location.ring < 0 { design.objects[i].nodes[location.index].toggleSmooth() } else { design.objects[i].holes?[location.ring][location.index].toggleSmooth() }
        }
        status = smooth ? "Smooth point: the outline curves through it. Drag its handles to shape the curve." : "Corner point: the outline turns sharply here."
    }
    func finishPath() {
        guard !hasVersionMismatch else{return}
        if let shape=tool.draggedShape {
            // Return while the mouse is still dragging out the shape does nothing (letting go adds it). A shape
            // left unfinished, as when a draft is restored after a crash, is added as it is.
            if canvas?.isDraggingShape != true {finishShape(shape)}
            return
        }
        if tool == .knife {cutAlongDraft();return}
        let minimum=tool == .satin ? 4 : [.fill,.hole,.closedShape,.freehandClosed].contains(tool) ? 3:2
        guard draft.count>=minimum else{status="Place at least \(minimum) points to finish.";return}
        if tool == .satin && draft.count%2 != 0{status="Complete the right edge of this satin pair before finishing.";return}
        if tool == .hole {
            guard let id=holeTarget,let target=design.objects.first(where:{$0.id==id && $0.kind == .fill && !$0.locked}) else{status="Select an unlocked fill before adding a hole.";return}
            var candidate=target;candidate.holes=(candidate.holes ?? [])+[draft]
            do{try AreaGeometry.validate(([candidate.nodes]+(candidate.holes ?? [])).map{AreaGeometry.ring($0)})}catch{status=error.localizedDescription;return}
            edit("Add Fill Hole"){d in if let i=d.objects.firstIndex(where:{$0.id==id}){d.objects[i]=candidate}}
            draft=[];selection=[id];tool = .select;holeTarget=nil;status="Hole added. Its boundary can be edited with N.";return
        }
        if tool.isShapeTool {
            // The stitch picked for Open or Closed Shape goes on the new object (a closed shape can get a fill and an
            // outline: two objects); it's named after that stitch.
            let shapes=Preferences.shared.shapes,name="Shape \(design.objects.count+1)"
            var made:[RunObject]
            do {
                if tool.makesOpenShape {made=[try ShapeStitching.openShape(draft,stitch:shapes.openStitch,satinWidth:satinLineWidth,name:name,color:currentColor)]}
                else {made=try ShapeStitching.closedShape(draft,fill:shapes.closedFill,outline:shapes.closedOutline,satinWidth:satinLineWidth,name:name,color:currentColor)}
            } catch{status=error.localizedDescription;return}
            let title="\(made[0].stitchTitle) \(design.objects.count+1)"
            for index in made.indices {made[index].name=index==0 ? title:"\(title) outline"}
            addDrawn(made,action:(tool.freehand ? "Freehand" : "Digitize")+(tool.makesOpenShape ? " Open Shape" : " Closed Shape"));return
        }
        let kind:StitchKind=tool == .satin ? .satin : tool == .fill ? .fill:.run
        var object=RunObject(name:"\(kind.title) \(design.objects.count+1)",nodes:draft,color:currentColor)
        if kind != .run {object.digitizing=DigitizingSettings(kind:kind);object.closed=kind == .fill;object.stitchLength=kind == .fill ? 3:2.5}
        object=design.withFabric(Preferences.shared.withNewObjectDefaults(object))   // Settings' starting values, then the design's fabric values
        edit("Draw \(kind.title)"){$0.objects.append(object)}
        draft=[];selection=[object.id];selectedNode=nil;status="\(kind.title) added. Keep drawing, or press \(Preferences.shared.key(.selectTool)) to select."
    }
    /// Add or Remove Stitch Angles: a click at `point`. Adding takes two clicks per line, across the fill, and adds
    /// it (one undoable step each); removing takes away the line within `reach` mm of the click.
    func clickForAngle(_ point: Point, reach: Double) {
        guard let id = angleTarget, let object = design.objects.first(where: { $0.id == id }) else { status = "Select one fill first."; return }
        let lines = object.settings.angleLines ?? []
        if tool == .removeAngles {
            guard let index = lines.indices.min(by: { gap(point, lines[$0]) < gap(point, lines[$1]) }), gap(point, lines[index]) <= reach else { status = "Click on one of the fill's stitch angle lines to remove it."; return }
            removeAngleLine(id, index)
            return
        }
        guard let start = angleStart else { angleStart = point; status = "Now click on the other side of the fill · Esc when done"; return }
        angleStart = nil
        guard start.distance(to: point) > 0.5 else { status = "Click two points further apart, across the fill."; return }
        guard edit("Add Stitch Angle", { design in if let i = design.objects.firstIndex(where: { $0.id == id }) { design.objects[i].digitizing?.angleLines = lines + [[start, point]] } }) else { return }
        status = "Stitch angle added: the stitches run along it and turn between lines. Click two more points for another, or press Esc when done."
    }
    // MARK: Edit Stitch
    /// The object whose stitches Edit Stitch is changing, and the needle points selected in it.
    var stitchEditTarget: UUID?
    @Published var selectedStitches: Set<StitchRef> = []
    private var sectionsCache: (key: String, sections: [StitchEdits.Section])?
    /// The target's stitches as Edit Stitch shows them: its edited stitches, or fresh ones worked out from it.
    var stitchSections: [StitchEdits.Section] {
        guard let id = stitchEditTarget, let index = design.objects.firstIndex(where: { $0.id == id }) else { return [] }
        let object = design.objects[index]
        let key = object.stitchSignature + "|" + String(object.stitchEdits?.hashValue ?? 0)
        if let cache = sectionsCache, cache.key == key { return cache.sections }
        let sections: [StitchEdits.Section]
        if let edits = object.stitchEdits, object.hasCurrentStitchEdits { sections = edits.sections }
        else { sections = ((try? StitchEngine.fresh(object, under: Array(design.objects[(index + 1)...])))?.sections ?? []).map { StitchEdits.Section(points: $0.points, underlay: $0.underlay, joined: $0.joined) } }
        sectionsCache = (key, sections); return sections
    }
    /// Starts Edit Stitch on the one selected object.
    func startStitchEdit() {
        guard selection.count == 1, let object = selected, [.run, .satin, .fill].contains(object.kind), !object.locked else { status = "Select one unlocked running line, satin or fill to edit its stitches."; return }
        stitchEditTarget = object.id; selectedStitches = []; tool = .stitchEdit
        status = "Edit Stitch · Click needle points to select (Shift adds) or drag a box · Drag to move · \(Preferences.shared.key(.delete)) deletes · Option-click a stitch to add a point · Esc when done"
    }
    /// Saves new stitches for the target as one undoable edit; they sew until its shape or settings change.
    func setStitches(_ sections: [StitchEdits.Section], action: String) {
        guard let id = stitchEditTarget else { return }
        let kept = sections.filter { $0.points.count >= 2 }
        edit(action) { design in
            if let i = design.objects.firstIndex(where: { $0.id == id }) { design.objects[i].stitchEdits = StitchEdits(sections: kept, signature: design.objects[i].stitchSignature) }
        }
    }
    /// Deletes the selected needle points; a run of stitches left with fewer than two points goes too.
    func deleteSelectedStitches() {
        guard !selectedStitches.isEmpty else { status = "Click needle points to select them first."; return }
        let removed = selectedStitches.count
        var sections = stitchSections
        for s in sections.indices { sections[s].points = sections[s].points.enumerated().filter { !selectedStitches.contains(StitchRef(section: s, index: $0.offset)) }.map(\.element) }
        selectedStitches = []
        setStitches(sections, action: "Delete Stitches")
        status = "Deleted \(removed) needle point\(removed == 1 ? "" : "s"). The edited stitches sew until the shape or a setting changes."
    }
    /// Adds a needle point at `point` on the stitch within `reach` mm of it, and selects it.
    func insertStitch(at point: Point, reach: Double) {
        var sections = stitchSections, best: (section: Int, index: Int, distance: Double)?
        for (s, section) in sections.enumerated() {
            for i in section.points.indices.dropLast() {
                let d = point.distance(to: AreaGeometry.projection(point, section.points[i], section.points[i + 1]))
                if d <= reach, best == nil || d < best!.distance { best = (s, i + 1, d) }
            }
        }
        guard let best else { status = "Option-click on a stitch to add a needle point there."; return }
        sections[best.section].points.insert(AreaGeometry.projection(point, sections[best.section].points[best.index - 1], sections[best.section].points[best.index]), at: best.index)
        setStitches(sections, action: "Add Stitch")
        selectedStitches = [StitchRef(section: best.section, index: best.index)]
        status = "Needle point added. Drag it to place it."
    }
    /// Removes one of a fill's stitch angle lines, as one undoable step.
    func removeAngleLine(_ id: UUID, _ index: Int) {
        guard let object = design.objects.first(where: { $0.id == id }), let count = object.settings.angleLines?.count, index < count else { return }
        guard !object.locked else { status = "Unlock the fill to change its stitch angles."; return }
        guard edit("Remove Stitch Angle", { design in if let i = design.objects.firstIndex(where: { $0.id == id }) { design.objects[i].digitizing?.angleLines?.remove(at: index); if design.objects[i].digitizing?.angleLines?.isEmpty == true { design.objects[i].digitizing?.angleLines = nil } } }) else { return }
        selectedAngle = nil
        status = count == 1 ? "Stitch angle removed. The fill's rows are straight again." : "Stitch angle removed."
    }
    /// The selected fill's stitch angle line within `reach` mm of `point`, if any, for clicking to select it.
    func angleLine(near point: Point, reach: Double) -> (object: UUID, index: Int)? {
        for object in design.objects where selection.contains(object.id) && !object.locked {
            let lines = object.settings.angleLines ?? []
            if let index = lines.indices.min(by: { gap(point, lines[$0]) < gap(point, lines[$1]) }), gap(point, lines[index]) <= reach { return (object.id, index) }
        }
        return nil
    }
    /// How far `p` is from a two-point line.
    private func gap(_ p: Point, _ line: [Point]) -> Double { p.distance(to: AreaGeometry.projection(p, line[0], line[1])) }
    /// Branching: the objects being branched, and the start and end points given so far (nil where Return let
    /// OpenHoop choose).
    var branchTargets: Set<UUID> = []
    @Published var branchPoints: [Point?] = []
    /// Starts Branching on the selection: next come the clicks for its start and end.
    func startBranching() {
        let targets = editableSelection.filter { id in design.objects.contains { $0.id == id && [.run, .satin, .fill].contains($0.kind) } }
        guard targets.count >= 2 else { status = "Select two or more fills, satins or lines to branch."; return }
        branchTargets = targets; branchPoints = []; tool = .branch
        status = "Branching · Click where the branch should start (Return lets OpenHoop choose) · Esc cancels"
    }
    /// Takes the branch's start, then its end (nil: Return, let OpenHoop choose), then branches the objects as one
    /// undoable edit and selects them.
    func addBranchPoint(_ point: Point?) {
        branchPoints.append(point)
        guard branchPoints.count == 2 else { status = "Now click where it should end (Return lets OpenHoop choose) · Esc cancels"; return }
        let (entry, exit) = (branchPoints[0], branchPoints[1])
        branchPoints = []; tool = .select
        var next = design
        do {
            let ids = try next.branch(branchTargets, entry: entry, exit: exit)
            guard !ids.isEmpty else { status = "Select two or more unlocked fills, satins or lines to branch."; return }
            guard edit("Branching", { $0 = next }) else { return }
            selection = Set(ids); selectedNode = nil
            status = "Branched \(ids.count) objects in \(next.objects.first { $0.id == ids[0] }?.color.name ?? "one thread"). Where they touch, the needle travels inside them instead of trimming. Ungroup to undo the branch."
        } catch { status = error.localizedDescription }
    }
    /// Knife: cuts the selected objects (or, with nothing selected, everything on show) along the line just drawn,
    /// as one undoable edit, and selects the pieces. The Knife stays on for the next cut.
    func cutAlongDraft() {
        guard draft.count >= 2 else { status = "Click at least two points across what to cut, then press Return."; return }
        let line = RunningEngine.flatten(draft).flatMap { $0 }
        let targets = selection.isEmpty ? Set(design.objects.filter { isShown($0) && !$0.locked }.map(\.id)) : editableSelection
        var next = design
        do {
            let pieces = try next.cut(targets, along: line)
            draft = []
            guard !pieces.isEmpty else { status = "Nothing was cut: draw the line right across a shape, from outside it to outside it."; return }
            guard edit("Knife", { $0 = next }) else { return }
            selection = Set(pieces); selectedNode = nil
            status = "Cut into \(pieces.count) pieces, each keeping its stitch settings and color. Draw another line, or press Esc when done."
        } catch { status = error.localizedDescription }
    }
    /// Adds the shape just dragged out with the Rectangle, Ellipse or Basic Shapes tool (its outline is in `draft`),
    /// with the Closed Shape stitch on it.
    func finishShape(_ shape:BasicShape) {
        guard !hasVersionMismatch,draft.count>=3 else{draft=[];return}
        let shapes=Preferences.shared.shapes
        do {
            let made=try ShapeStitching.closedShape(draft,fill:shapes.closedFill,outline:shapes.closedOutline,satinWidth:satinLineWidth,name:"\(shape.title) \(design.objects.count+1)",color:currentColor)
            addDrawn(made,action:"Draw \(shape.title)")
        } catch {draft=[];status=error.localizedDescription}
    }
    /// A freehand stroke let go: smooths it to a few nodes and adds it like an Open or Closed Shape. Too short a
    /// stroke (a click, or a wobble) adds nothing.
    func finishFreehand(_ points:[Point]) {
        draft=FreehandStroke.nodes(points,closed:tool == .freehandClosed)
        if draft.count < (tool == .freehandClosed ? 3:2) {draft=[];status="Press and drag to draw freehand: the line follows the pointer until you let go.";return}
        finishPath()
    }
    /// The width (mm) of satin lines and satin outlines drawn with the shape tools.
    private var satinLineWidth:Double {Preferences.shared.data.satinLineWidth ?? SatinLine.defaultWidth}
    /// Adds newly drawn objects (a shape, or a shape's fill and its outline) with Settings' starting values and the design's fabric values,
    /// selects them and clears the draft.
    private func addDrawn(_ objects:[RunObject],action:String) {
        let objects=objects.map{design.withFabric(Preferences.shared.withNewObjectDefaults($0))}
        edit(action){$0.objects+=objects}
        draft=[];selection=Set(objects.map(\.id));selectedNode=nil
        status="\(objects[0].name)\(objects.count>1 ? " and its outline" : "") added. Keep drawing, or press \(Preferences.shared.key(.selectTool)) to select."
    }
    func resizeSelection(width:Double?=nil,height:Double?=nil) {
        let points=design.objects.filter{selection.contains($0.id) && !$0.locked}.flatMap{$0.outlinePaths.flatMap{$0}}
        guard let x0=points.map(\.x).min(),let x1=points.map(\.x).max(),let y0=points.map(\.y).min(),let y1=points.map(\.y).max() else{return}
        let sx=width.map{$0/max(0.001,x1-x0)} ?? 1,sy=height.map{$0/max(0.001,y1-y0)} ?? 1,center=Point((x0+x1)/2,(y0+y1)/2)
        if design.objects.contains(where:{selection.contains($0.id) && $0.kind == .raw}){status="Resizing imported stitches changes density and stitch lengths; stitches are not regenerated."}
        let resized=Self.scaling(design,ids:editableSelection,about:center,sx:sx,sy:sy)
        edit("Resize Objects"){$0=resized}
    }
    /// `design` with the unlocked objects in `ids` scaled by `sx` across and `sy` up, about `anchor` (mm): their
    /// shapes and points, hand-edited stitches, and a fill's angle, so its rows keep their direction on the cloth.
    static func scaling(_ design:Design,ids:Set<UUID>,about anchor:Point,sx:Double,sy:Double) -> Design {
        var result=design
        for index in result.objects.indices where ids.contains(result.objects[index].id) && !result.objects[index].locked {
            result.objects[index].transform{p in let q=p-anchor;return anchor+Point(q.x*sx,q.y*sy)}
            if result.objects[index].kind == .fill {let r=result.objects[index].settings.angle * .pi/180;result.objects[index].digitizing?.angle=atan2(sin(r)*sy,cos(r)*sx)*180 / .pi}
            result.objects[index].refreshStitchEdits()   // edited stitches were resized with it
        }
        return result
    }
    /// The selected objects that edits change (locked ones stay put).
    var editableSelection: Set<UUID> { Set(design.objects.filter { selection.contains($0.id) && !$0.locked }.map(\.id)) }
    /// Moves the selection so the center of its box lands at the given x and/or y (mm), as one undoable edit.
    func moveSelection(centerX: Double? = nil, centerY: Double? = nil) {
        let ids = editableSelection
        guard let box = design.bounds(of: ids) else { return }
        let delta = Point(centerX.map { $0 - (box.min.x + box.max.x) / 2 } ?? 0, centerY.map { $0 - (box.min.y + box.max.y) / 2 } ?? 0)
        guard delta != Point(0, 0) else { return }
        edit("Move Objects") { $0.move(ids, by: delta) }
    }
    /// Turns the selection by any angle (positive is counterclockwise) around the center of its box, as one
    /// undoable edit. Fill rows turn with it.
    func rotateSelection(by degrees: Double) {
        let ids = editableSelection
        guard degrees != 0, let box = design.bounds(of: ids) else { return }
        edit("Rotate Objects") { $0.rotate(ids, by: degrees, around: (box.min + box.max) * 0.5) }
    }
    /// Skews the selection by `degrees` around the middle of its box, as one undoable edit.
    func skewSelection(by degrees: Double) {
        let ids = editableSelection
        guard degrees != 0, let box = design.bounds(of: ids) else { return }
        edit("Skew Objects") { $0.skew(ids, by: degrees, around: (box.min + box.max) * 0.5) }
    }
    /// Mirrors or rotates the selection (by 90°) around the center of its bounds, as one undoable edit.
    /// Locked objects don't move, so they are left out of the pivot too (matching resizeSelection).
    func mirrorOrRotateSelection(_ command: CommandID) {
        let selected = design.objects.filter { selection.contains($0.id) && !$0.locked }.flatMap{$0.kind == .raw ? $0.outlinePaths.flatMap{$0}:$0.allNodes.map(\.point)}
        guard let first = selected.first else { return }
        let center = Point(((selected.map(\.x).min() ?? first.x) + (selected.map(\.x).max() ?? first.x)) / 2, ((selected.map(\.y).min() ?? first.y) + (selected.map(\.y).max() ?? first.y)) / 2)
        editSelected(command.title) { object in
            object.transform {point in
                let p=point-center
                let q=command == .mirrorH ? Point(-p.x,p.y) : command == .mirrorV ? Point(p.x,-p.y) : command == .rotateLeft ? Point(-p.y,p.x) : Point(p.y,-p.x)
                return q+center
            }
            if object.kind == .fill {
                let a=object.settings.angle
                let angle=command == .mirrorH ? 180-a : command == .mirrorV ? -a : command == .rotateLeft ? a+90:a-90
                object.digitizing?.angle=(angle+540).truncatingRemainder(dividingBy:360)-180
            }
            object.refreshStitchEdits()   // edited stitches were mirrored or turned with it
        }
    }
    /// The object clicked last: where a Shift-click range in the object lists starts.
    private var selectionAnchor: UUID?
    /// Selects an object, or its whole group unless `single` (Option-click) asks for just that one. Lettering is
    /// always selected whole: it's one object, and Edit Nodes moves its letters (Break Apart Lettering splits it).
    /// `extend` (Shift-click on the canvas, ⌘-click in the lists) adds it to, or removes it from, the current selection.
    func select(_ id: UUID, extend: Bool = false, single: Bool = false) {
        selectedNode=nil
        let members = single && !isLettering(id) ? [id] : design.groupMembers(of: id)
        if extend { if selection.contains(id) { selection.subtract(members) } else { selection.formUnion(members) } }
        else { selection = members }
        selectionAnchor = id
        focusCanvas()
    }
    /// Shift-click in the object lists: selects every object in sewing order from the one clicked last through `id`,
    /// with their whole groups unless `single`. With no earlier click to start from, it selects just `id`.
    func selectRange(to id: UUID, single: Bool = false) {
        let ids = design.objects.map(\.id)
        guard let anchor = selectionAnchor, let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: id) else { select(id, single: single); return }
        selectedNode = nil
        selection = Set(ids[min(from, to)...max(from, to)].flatMap { single && !isLettering($0) ? [$0] : design.groupMembers(of: $0) })
        focusCanvas()   // the anchor stays put, so the next Shift-click redraws the range from the same object
    }
    /// A click on a row of the object lists, read the Mac way: Shift-click selects a range in sewing order, ⌘-click
    /// adds or removes one, and Option-click (or `single`, for a row inside an opened group) picks one group member.
    func listClick(_ id: UUID, single: Bool = false) {
        let flags = NSEvent.modifierFlags, single = single || flags.contains(.option)
        if flags.contains(.shift) { selectRange(to: id, single: single) } else { select(id, extend: flags.contains(.command), single: single) }
    }
    /// Auto Start Points: each object starts where the previous one finishes, shortening travel between parts.
    /// Works in the background, then applies the result as one undoable edit and reports the travel saved.
    func autoStartPoints() {
        guard !hasVersionMismatch, draft.isEmpty else { status = "Finish the current path and regenerate older projects first."; return }
        let snapshot = design, startRevision = revision, before = StitchEngine.travelLength(plan)
        status = "Working out start points…"
        Task {
            do {
                let (next, after) = try await Task.detached(priority: .userInitiated) {
                    let next = try StitchEngine.autoStartPoints(snapshot)
                    return (next, StitchEngine.travelLength(try StitchEngine.compile(next)))
                }.value
                guard startRevision == revision else { status = "The design changed meanwhile. Run Auto Start Points again."; return }
                guard next != design else { status = "Start points already follow the sewing order."; return }
                edit("Auto Start Points") { $0 = next }
                let unit = Preferences.shared.unit
                status = "Start points set. Travel between parts: \(unit.text(before, decimals: 0)) → \(unit.text(after, decimals: 0)). Adjust any with the Start & End tool."
            } catch { status = error.localizedDescription }
        }
    }
    /// Removes the start and end points from the selected objects, as one undoable edit.
    func clearStartEnd() {
        guard design.objects.contains(where: { selection.contains($0.id) && ($0.entry != nil || $0.exit != nil) }) else {
            status = "The selection has no start or end points to clear."; return
        }
        let words = Set(design.objects.filter { selection.contains($0.id) }.compactMap { $0.lettering?.id })
        edit("Clear Start & End") { design in
            for i in design.objects.indices where self.selection.contains(design.objects[i].id) && !design.objects[i].locked { design.objects[i].entry = nil; design.objects[i].exit = nil }
            for id in words { design.setLetteringStart(id, nil); design.setLetteringEnd(id, nil) }   // and lettering's recipe
        }
        status = "Start and end points cleared. The selection sews in its default order again."
    }
    /// Puts the selected objects (two or more) into one new group, as one undoable edit.
    func groupSelection() {
        guard selection.count >= 2 else { status = "Select two or more objects to group."; return }
        let group = UUID()
        edit("Group") { design in for i in design.objects.indices where selection.contains(design.objects[i].id) { design.objects[i].groupID = group } }
        status = "Grouped \(selection.count) objects. Click any of them to select the group; Option-click picks one."
    }
    /// Removes every group that has a selected member. Ungrouped letters become plain shapes: they forget their
    /// lettering recipe, since editing the text would pull them back together.
    func ungroupSelection() {
        // Lettering stays one object: Ungroup leaves it alone (Break Apart Lettering is the way to split it).
        let letteringGroups = Set(design.objects.filter { selection.contains($0.id) && $0.lettering != nil }.compactMap(\.groupID))
        let groups = Set(design.objects.filter { selection.contains($0.id) }.compactMap(\.groupID)).subtracting(letteringGroups)
        let breakApart = Preferences.shared.label(.breakApartLettering).isEmpty ? "Break Apart Lettering" : "Break Apart Lettering (\(Preferences.shared.label(.breakApartLettering)))"
        guard !groups.isEmpty else {
            status = letteringGroups.isEmpty ? "The selection isn't grouped." : "Lettering stays one object. To turn it into separate shapes, use \(breakApart)."
            return
        }
        var hadMonogram = false
        edit("Ungroup") { design in
            for i in design.objects.indices where design.objects[i].groupID.map(groups.contains) == true {
                design.objects[i].groupID = nil; design.objects[i].branchID = nil   // ungrouped branches sew separately again
                if design.objects[i].monogram != nil { design.objects[i].monogram = nil; hadMonogram = true }
            }
        }
        status = "Ungrouped. Objects keep their place in the sewing order." + (hadMonogram ? " The monogram's parts are now plain shapes; it can't be edited as a monogram any more." : "")
            + (letteringGroups.isEmpty ? "" : " Lettering stays one object; use \(breakApart) to split it.")
    }
    /// The lettering, when the selection is exactly one piece of lettering (all its letters).
    var selectedLettering: LetteringSpec? {
        let chosen = design.objects.filter { selection.contains($0.id) }
        guard let spec = chosen.first?.lettering, chosen.allSatisfy({ $0.lettering?.id == spec.id }) else { return nil }
        return spec
    }
    /// True when `id` is a letter of a piece of lettering.
    func isLettering(_ id: UUID) -> Bool { design.objects.first { $0.id == id }?.lettering != nil }
    /// Break Apart Lettering: turns the selected lettering into plain shapes (still grouped, so they move together
    /// until ungrouped). Its text can't be edited any more, but each letter can be reshaped. One undoable step.
    func breakApartLettering() {
        let ids = Set(design.objects.filter { selection.contains($0.id) && $0.lettering != nil }.map(\.id))
        guard !ids.isEmpty else { status = "Select some lettering first."; return }
        edit("Break Apart Lettering") { design in
            for i in design.objects.indices where ids.contains(design.objects[i].id) { design.objects[i].lettering = nil; design.objects[i].letterKey = nil }
        }
        status = "The lettering is now \(ids.count) separate shapes, grouped. Edit Nodes reshapes each letter; Ungroup separates them."
    }
    /// Rebuilds the lettering with `spec.id` from `spec` (new text, font, size, spacing, baseline or letter nudges),
    /// in the same place and thread, as one undoable step, and selects it. Says why in the status line and returns
    /// false if it can't be built.
    @discardableResult func rebuildLettering(_ spec: LetteringSpec, action: String = "Edit Lettering") -> Bool {
        let old = design.letteringObjects(spec.id)
        guard let color = old.first?.color else { return false }
        guard !old.contains(where: \.locked) else { status = "Unlock the letters before editing the lettering."; return false }
        do {
            let letters = try spec.build(color: color, embroideryFonts: EmbroideryFontLibrary.fonts)
            var candidate = design
            let ids = candidate.replaceLettering(spec.id, with: letters)
            try candidate.validate()
            edit(action) { $0 = candidate }
            selection = Set(ids); selectedNode = nil
            if let warning = letters.warnings.first { status = warning }
            return true
        } catch { status = error.localizedDescription; return false }
    }
    /// Copies the selection 3 mm down-right and selects the copies. Copied groups become new, separate groups,
    /// and copied lettering becomes separate lettering that can be edited on its own.
    func duplicateSelection() {
        var ids: Set<UUID> = [], newGroups: [UUID: UUID] = [:], newLettering: [UUID: UUID] = [:]
        edit("Duplicate Objects") { design in
            for object in design.objects.filter({ selection.contains($0.id) }) {
                var copy = object; copy.id = UUID(); copy.name += " copy"; copy.locked = false
                copy.transform{$0+Point(3,-3)}
                if let old = copy.groupID { if newGroups[old] == nil { newGroups[old] = UUID() }; copy.groupID = newGroups[old] }
            if let old = copy.branchID { if newGroups[old] == nil { newGroups[old] = UUID() }; copy.branchID = newGroups[old] }   // a separate branch too
                if let old = copy.lettering?.id { if newLettering[old] == nil { newLettering[old] = UUID() }; copy.lettering?.id = newLettering[old]! }
                if let old = copy.monogram?.id { if newLettering[old] == nil { newLettering[old] = UUID() }; copy.monogram?.id = newLettering[old]! }   // a separate monogram too
                ids.insert(copy.id); design.objects.append(copy)
            }
        }; selection = ids
    }
}

@MainActor final class DesignDocument: NSDocument {
    let state = EditorState()
    /// The stitches being worked out in the background: the plan, the objects that can't be sewn, and the error if any.
    private var generation: Task<(plan: StitchPlan, broken: Set<UUID>, error: String?), Error>?
    private var restoring = false
    private struct DraftSnapshot: Codable { var nodes: [PathNode]; var color: ThreadColor;var tool:Tool?;var holeTarget:UUID? }
    func draftDidChange() { if !restoring { updateChangeCount(.changeDone) } }
    override init() { super.init(); state.document = self; hasUndoManager = true }
    override class var autosavesInPlace: Bool { true }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
    /// A new or opened design joins the front design window as a tab, or gets a window of its own if none is open.
    override func makeWindowControllers() {
        if let host = EditorWindowController.tabHost() { host.addTab(for: self) } else { _ = EditorWindowController(document: self) }
        if !state.hasVersionMismatch { regenerate() }
    }
    /// Brings the design's tab forward (also when an already-open design is opened again).
    override func showWindows() {
        guard let host = EditorWindowController.host(of: self) else { super.showWindows(); return }
        if let pane = host.panes.first(where: { $0.document === self }) { host.select(pane) }
        host.showWindow(nil)
    }
    /// A closing design takes its tab out of the window first, so closing it never closes the other designs' window.
    override func close() {
        generation?.cancel()
        EditorWindowController.host(of: self)?.removeTab(for: self)
        super.close()
    }
    // Tabs show each design's name and an unsaved-changes dot, so they hear about both.
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        NotificationCenter.default.post(name: .designTabsChanged, object: self)
    }
    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        NotificationCenter.default.post(name: .designTabsChanged, object: self)
    }
    override var fileURL: URL? { didSet { NotificationCenter.default.post(name: .designTabsChanged, object: self) } }
    /// Replace a snapshot once per gesture, so dragging creates one useful undo step.
    func replace(_ next: Design, action: String) {
        guard next != state.design else { return }
        let previous = state.design
        undoManager?.registerUndo(withTarget: self) { doc in doc.replace(previous, action: action) }
        undoManager?.setActionName(action)
        // Schema 5 marks projects using Bézier handles or start/end points, so older versions refuse them instead of losing them.
        var updated=next
        // Stitches edited by hand last only while their object stays as it was; a new shape or setting means fresh
        // stitches (Undo brings the edits back).
        let lost=updated.dropStaleStitchEdits()
        updated.keepArtworkPlace(from:state.design)   // the reference picture stays between the same objects
        if updated.engineVersion==Design.engineVersion{updated.schemaVersion=updated.needsSchemaSix ? 6:updated.needsSchemaFive ? 5:4}
        state.design = updated; state.revision += 1
        if !lost.isEmpty { state.status = "\(lost.joined(separator: ", ")): stitches edited by hand were replaced by fresh ones, because the shape or settings changed. Undo (⌘Z) brings them back." }
        state.selection.formIntersection(Set(next.objects.map(\.id)))
        regenerate()
    }
    func regenerate() {
        generation?.cancel()
        let snapshot = state.design, revision = state.revision
        let recoveringFromError = state.generationError != nil
        state.busy = true; state.generationError = nil
        // If one object can't be sewn, the rest still get fresh stitches to show (BrokenObjects.swift), and the error
        // stays up so nothing can be exported until it's fixed.
        let task = Task.detached(priority: .userInitiated) { () throws -> (plan: StitchPlan, broken: Set<UUID>, error: String?) in
            do { return (try RunningEngine.compile(snapshot), [], nil) }
            catch is CancellationError { throw CancellationError() }
            catch {
                guard let shown = try? StitchEngine.compileSkippingBroken(snapshot), !shown.broken.isEmpty else { throw error }
                return (shown.plan, Set(shown.broken.keys), error.localizedDescription)
            }
        }
        generation = task
        Task { [weak self] in
            do {
                let result = try await task.value
                guard let self, self.state.revision == revision, !task.isCancelled else { return }
                self.state.plan = result.plan; self.state.brokenObjects = result.broken; self.state.busy = false
                if let error = result.error { self.state.generationError = error; return }   // not marked compiled: it's only a preview
                self.state.compiledRevision = revision
                if recoveringFromError {self.state.status = "Updated stitches ready."}
            } catch is CancellationError { }
            catch {
                guard let self, self.state.revision == revision else { return }
                self.state.generationError = error.localizedDescription; self.state.brokenObjects = []; self.state.busy = false
            }
        }
    }
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        var snapshot = state.design
        try snapshot.validate()
        if !state.hasVersionMismatch { snapshot.cachedPlan = state.compiledRevision == state.revision ? state.plan : nil }
        var children: [String: FileWrapper] = [:]
        if !state.draft.isEmpty {
            children["draft.json"] = FileWrapper(regularFileWithContents: try JSONEncoder().encode(DraftSnapshot(nodes: state.draft, color: state.currentColor,tool:state.tool == .zoomBox ? state.toolBeforeZoom : state.tool,holeTarget:state.holeTarget)))
        }
        if let image = snapshot.artwork?.data, !image.isEmpty {
            children["artwork.bin"] = FileWrapper(regularFileWithContents: image)
            snapshot.artwork?.data = Data()
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        children["design.json"] = FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
        // macOS looks for QuickLook/Thumbnail.png inside a package and shows it as the file's icon in Finder.
        if let thumbnail = StitchThumbnail.png(of: snapshot.objects) {
            children["QuickLook"] = FileWrapper(directoryWithFileWrappers: ["Thumbnail.png": FileWrapper(regularFileWithContents: thumbnail)])
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard let bytes = fileWrapper.fileWrappers?["design.json"]?.regularFileContents, bytes.count < 100_000_000 else { throw DesignError.invalid("The project is missing its design data or is too large.") }
        var design = try JSONDecoder().decode(Design.self, from: bytes)
        if design.artwork != nil {
            guard let image = fileWrapper.fileWrappers?["artwork.bin"]?.regularFileContents else { throw DesignError.invalid("The project is missing its reference artwork.") }
            design.artwork?.data = image
        }
        try design.validate()
        var draft: DraftSnapshot?
        if let bytes = fileWrapper.fileWrappers?["draft.json"]?.regularFileContents {
            guard bytes.count <= 10_000_000 else { throw DesignError.invalid("The unfinished path is too large.") }
            draft = try JSONDecoder().decode(DraftSnapshot.self, from: bytes)
            guard draft!.nodes.count <= 100_000, draft!.nodes.allSatisfy({ $0.point.finite && abs($0.point.x) <= 10_000 && abs($0.point.y) <= 10_000 }) else { throw DesignError.invalid("The unfinished path contains invalid geometry.") }
        }
        // Concurrent document reads are disabled above, so AppKit invokes this on the main thread.
        MainActor.assumeIsolated {
            restoring = true
            defer { restoring = false }
            generation?.cancel()
            state.busy = false; state.generationError = nil; state.compiledRevision = -1
            state.selection = [];state.selectedNode=nil;state.holeTarget=nil; state.playing = false; state.playback = 1
            state.design = design
            state.plan = design.cachedPlan ?? StitchPlan()
            state.draft = draft?.nodes ?? []
            if let draft { state.currentColor = draft.color; state.tool = draft.tool ?? .run;state.holeTarget=draft.holeTarget; state.status = "Unfinished path restored. Continue drawing, or press Enter to finish." }
            state.revision += 1
            if !windowControllers.isEmpty && !state.hasVersionMismatch { regenerate() }
        }
    }
}
