// The command catalog is the single source for tools, menus, and configurable keyboard shortcuts.
// Keeping conflict detection outside AppKit makes focus and binding rules independently testable.
import Foundation

public enum CommandContext: String, Codable, Sendable { case canvas, drawing, list, text }
public struct KeyBinding: Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: Int
    public init(_ key: String, _ modifiers: Int = 0) { self.key = key.lowercased(); self.modifiers = modifiers & 15 }
    public var display: String {
        let special = ["escape": "Esc", "return": "↩", "delete": "⌫", "space": "Space", "left": "←", "right": "→", "up": "↑", "down": "↓", "home": "Home", "end": "End", "tab": "⇥"]
        return (modifiers & 8 != 0 ? "⌃" : "") + (modifiers & 4 != 0 ? "⌥" : "") + (modifiers & 2 != 0 ? "⇧" : "") + (modifiers & 1 != 0 ? "⌘" : "") + (special[key] ?? key.uppercased())
    }
    public var valid: Bool { !key.isEmpty && key.count <= 16 && modifiers >= 0 && modifiers <= 15 }
}

public enum CommandID: String, Codable, CaseIterable, Sendable {
    case new, open, save, saveAs, close, importImage, importSVG, importMachine, exportPES, exportMachine, exportDST, exportEXP, exportJEF, exportVP3, exportXXX, exportPEC, exportThreadList, productionWorksheet, sample, stitchSampler, settings
    case selectTool, artworkTool, runTool, satinTool, fillTool, holeTool, removeHoles, nodeTool, panTool, entryExitTool, autoStartPoints, clearStartEnd, lettering, editLettering, autoDigitize, satinBorder, applique, done, finishPath, cancelPath, removePoint, insertNode, deleteNode, renameObject, convertFill, convertRun, convertSatin, toggleUnderlay, showUnderlay, focusSpacing, focusAngle
    case openShapeTool, closedShapeTool, freehandOpenTool, freehandClosedTool, rectangleTool, ellipseTool, basicShapeTool, knifeTool, weldObjects, smoothShapes, laydown, branching, addStitchAngles, removeStitchAngles, editStitches, addMonogram, editMonogram
    case undo, redo, delete, selectAll, sequenceBySelection, alignLeft, alignCentersVertically, alignRight, alignTop, alignCentersHorizontally, alignBottom, alignCenters, spaceAcross, spaceDown, duplicate, mirrorH, mirrorV, rotateLeft, rotateRight, earlier, later, closePath, lockObject, hideObject, tieIn, tieOut, trimAfter, stopAfter, group, ungroup, threadChart, cutObjects, copyObjects, pasteObjects
    case zoomIn, zoomOut, zoomFit, zoomDesign, zoomBoxTool, zoomActual, zoomSelected, showStitches, showOutlines, showConnectors, hideOthers, measureTool, grid, snap, clearGuides, needles, threadView, artwork, inspector, palette, restoreWorkspace, saveWorkspace, proView
    case panelSewingOrder, panelDesign, panelReference, panelPlayer, nextTab, previousTab
    case nudgeLeft, nudgeRight, nudgeUp, nudgeDown, play, rewind, focusLength
    public var exportFormat:MachineFormat? {
        switch self {
        case .exportPES:return .pes;case .exportDST:return .dst;case .exportEXP:return .exp
        case .exportJEF:return .jef;case .exportVP3:return .vp3;case .exportXXX:return .xxx;case .exportPEC:return .pec
        default:return nil
        }
    }
    public var isExport:Bool {exportFormat != nil || self == .exportMachine || self == .exportThreadList}
    public var title: String {
        switch self {
        case .importMachine:return "Import Machine File…"
        case .importSVG:return "Import SVG Outlines…"
        case .exportMachine:return "Export Machine File…"
        case .exportDST:return "Export DST…";case .exportEXP:return "Export EXP…";case .exportJEF:return "Export JEF…"
        case .exportVP3:return "Export VP3…";case .exportXXX:return "Export XXX…";case .exportPEC:return "Export PEC…"
        case .exportThreadList:return "Export Thread List…"
        case .productionWorksheet:return "Production Worksheet…"
        case .stitchSampler:return "Open Satin + Fill Sampler"
        case .removeHoles:return "Remove All Fill Holes"
        case .satinTool:return "Satin Column";case .fillTool:return "Tatami Fill";case .holeTool:return "Add Fill Hole"
        case .insertNode:return "Insert Node at Pointer";case .deleteNode:return "Delete Selected Node"
        case .renameObject:return "Rename Object…";case .convertFill:return "Convert to Tatami Fill";case .convertRun:return "Convert to Running Stitch";case .convertSatin:return "Make Satin Column from Line"
        case .toggleUnderlay:return "Toggle Underlay";case .showUnderlay:return "Show Underlay Stitches";case .focusSpacing:return "Focus Row Spacing";case .focusAngle:return "Focus Fill Angle"
        case .new: return "New Design"; case .open: return "Open Project…"; case .save: return "Save"; case .saveAs: return "Save As…"
        case .close: return "Close Window"
        case .tieIn: return "Toggle Tie In"; case .tieOut: return "Toggle Tie Off"; case .trimAfter: return "Toggle Trim After"; case .stopAfter: return "Toggle Stop After"
        case .importImage: return "Import Reference Image…"; case .exportPES: return "Export PES…"; case .sample: return "Open Sample Design"
        case .settings: return "Settings…"; case .selectTool: return "Select"; case .runTool: return "Running Stitch"
        case .nodeTool: return "Edit Nodes"; case .panTool: return "Pan"; case .entryExitTool: return "Start & End Points"; case .autoStartPoints: return "Auto Start Points"; case .clearStartEnd: return "Clear Start & End Points"; case .lettering: return "Add Lettering…"; case .editLettering: return "Edit Lettering…"; case .autoDigitize: return "Auto-Digitize Artwork…"; case .satinBorder: return "Add Satin Border…"; case .applique: return "Make Appliqué…"; case .artworkTool: return "Move & Size Artwork"; case .done: return "Done (Back to Select)"; case .finishPath: return "Finish Path"; case .cancelPath: return "Cancel Path"
        case .openShapeTool: return "Digitize Open Shape"; case .closedShapeTool: return "Digitize Closed Shape"
        case .freehandOpenTool: return "Freehand Open Shape"; case .freehandClosedTool: return "Freehand Closed Shape"
        case .rectangleTool: return "Rectangle"; case .ellipseTool: return "Ellipse"; case .basicShapeTool: return "Basic Shapes"
        case .knifeTool: return "Knife"; case .weldObjects: return "Weld"; case .smoothShapes: return "Smooth Shapes"; case .laydown: return "Add Laydown…"; case .branching: return "Branching"; case .addStitchAngles: return "Add Stitch Angles"; case .removeStitchAngles: return "Remove Stitch Angles"; case .editStitches: return "Edit Stitches"; case .addMonogram: return "Add Monogram…"; case .editMonogram: return "Edit Monogram…"
        case .removePoint: return "Remove Last Point"; case .undo: return "Undo"; case .redo: return "Redo"; case .delete: return "Delete Selection"
        case .selectAll: return "Select All"; case .duplicate: return "Duplicate"; case .mirrorH: return "Mirror Horizontally"
        case .mirrorV: return "Mirror Vertically"; case .rotateLeft: return "Rotate Left 90°"; case .rotateRight: return "Rotate Right 90°"
        case .earlier: return "Sew Earlier"; case .later: return "Sew Later"; case .sequenceBySelection: return "Sequence by Selection Order";
        case .alignLeft: return "Align Left"; case .alignCentersVertically: return "Align Centers Vertically"; case .alignRight: return "Align Right"
        case .alignTop: return "Align Top"; case .alignCentersHorizontally: return "Align Centers Horizontally"; case .alignBottom: return "Align Bottom"
        case .alignCenters: return "Align Centers"; case .spaceAcross: return "Space Evenly Across"; case .spaceDown: return "Space Evenly Down" case .closePath: return "Toggle Closed Path"
        case .lockObject: return "Lock / Unlock Object"; case .hideObject: return "Show / Hide Object"; case .group: return "Group"; case .ungroup: return "Ungroup"
        case .threadChart: return "Choose Thread from Chart…"
        case .cutObjects: return "Cut"; case .copyObjects: return "Copy"; case .pasteObjects: return "Paste"
        case .zoomIn: return "Zoom In"; case .zoomOut: return "Zoom Out"; case .zoomFit: return "Fit Hoop"
        case .zoomBoxTool: return "Zoom Box"; case .zoomActual: return "Zoom 1:1 (Real Size)"; case .zoomSelected: return "Zoom to Selected"; case .zoomDesign: return "Zoom to Design"
        case .showStitches: return "Show Stitches"; case .showOutlines: return "Show Outlines"; case .showConnectors: return "Show Connectors (Travel)"; case .hideOthers: return "Hide Unselected"; case .measureTool: return "Measure"
        case .grid: return "Show Grid"; case .snap: return "Snap to Grid"; case .clearGuides: return "Clear Guides"; case .needles: return "Show Needle Points"; case .threadView: return "Thread View"
        case .artwork: return "Show Reference Image"; case .inspector: return "Properties Panel"; case .palette: return "Threads Panel"
        case .panelSewingOrder: return "Sewing Order Panel"; case .panelDesign: return "Design Panel"; case .panelReference: return "Reference Image Panel"; case .panelPlayer: return "Stitch Player Panel"
        case .proView: return "Pro View"
        case .nextTab: return "Show Next Design Tab"; case .previousTab: return "Show Previous Design Tab"
        case .restoreWorkspace: return "Reset Panel Layout"; case .saveWorkspace: return "Save Panel Layout…"
        case .nudgeLeft: return "Nudge Left"; case .nudgeRight: return "Nudge Right"; case .nudgeUp: return "Nudge Up"; case .nudgeDown: return "Nudge Down"
        case .play: return "Play / Pause Stitch Preview"; case .rewind: return "Rewind Stitch Preview"; case .focusLength: return "Focus Stitch Length"
        }
    }
    /// What the command does, in a sentence, for its hover tooltip on tool strips and toolbar buttons. No `default`
    /// case, so a new command can't be added without one.
    public var explanation: String {
        switch self {
        // Files
        case .new: return "Start a new, empty design in its own tab."
        case .open: return "Open a saved OpenHoop project (.stitchproj)."
        case .save: return "Save this design as an OpenHoop project, the file you keep editing."
        case .saveAs: return "Save this design as a project under a new name or in a new place."
        case .close: return "Close the design on screen (its tab)."
        case .importImage: return "Bring in a PNG or JPEG to trace over. It's only a guide: it never sews."
        case .importSVG: return "Bring in an SVG drawing as outlines, at its real size, ready to turn into stitches."
        case .importMachine: return "Bring in stitches from a machine file (PES, DST, JEF and more) into this design."
        case .exportPES: return "Save the stitches as a PES file for Brother and Babylock machines."
        case .exportMachine: return "Save the stitches as a machine file, in the format you choose."
        case .exportDST: return "Save the stitches as a DST file (Tajima), which most machines read."
        case .exportEXP: return "Save the stitches as an EXP file (Melco and Bernina)."
        case .exportJEF: return "Save the stitches as a JEF file (Janome)."
        case .exportVP3: return "Save the stitches as a VP3 file (Husqvarna Viking and Pfaff)."
        case .exportXXX: return "Save the stitches as an XXX file (Singer)."
        case .exportPEC: return "Save the stitches as a PEC file (older Brother machines)."
        case .exportThreadList: return "Save a list of the design's threads, in sewing order."
        case .productionWorksheet: return "A page to keep beside the machine: a picture of the design, its size and its threads in order."
        case .sample: return "Open a small ready-made design to try things on."
        case .stitchSampler: return "Open a design showing satin and fill side by side, to compare settings."
        case .settings: return "Change OpenHoop's settings: keyboard shortcuts, colors and more."
        // Drawing and digitizing
        case .selectTool: return "Click to pick an object, Shift-click to add more, drag to move them."
        case .artworkTool: return "Move the reference image, or drag a corner to resize it."
        case .runTool: return "Draw a line of single stitches: click corners, drag for curves, Return to finish."
        case .satinTool: return "Draw a satin column (smooth, shiny stitches side to side): click a point on each side, all the way along."
        case .fillTool: return "Draw a shape filled with rows of stitches: trace its outline and press Return."
        case .holeTool: return "Trace a hole inside the selected fill, left unstitched."
        case .removeHoles: return "Take all the holes out of the selected fill, so it fills solid."
        case .nodeTool: return "Reshape the selected object: drag its points and their curve handles."
        case .panTool: return "Drag to slide the view around the hoop."
        case .entryExitTool: return "Click where the selected object starts sewing; Option-click where it ends."
        case .autoStartPoints: return "Start every object where the one before it ended, to make travel between them shorter."
        case .clearStartEnd: return "Let OpenHoop choose where the selected object starts and ends again."
        case .lettering: return "Add text, in an embroidery font or a Mac font."
        case .editLettering: return "Change the selected text's words, font, size or shape."
        case .autoDigitize: return "Trace the reference image into fills automatically, one per color."
        case .satinBorder: return "Add a satin column around the outside of the selected shape, like the edge of a patch."
        case .applique: return "Sew a piece of fabric on in this shape, instead of filling it with stitches."
        case .done: return "Finish with the current tool and go back to Select."
        case .finishPath: return "Finish the line or shape you're drawing."
        case .cancelPath: return "Throw away the line or shape you're drawing."
        case .removePoint: return "Take back the last point you clicked."
        case .insertNode: return "Add a point to the selected outline, under the pointer."
        case .deleteNode: return "Remove the selected point from the outline."
        case .renameObject: return "Give the selected object a name of your own."
        case .convertFill: return "Turn the selected outline into a tatami fill."
        case .convertRun: return "Turn the selected shape into a running-stitch outline."
        case .convertSatin: return "Turn the selected line into a satin column centered on it."
        case .toggleUnderlay: return "Switch the selected objects' underlay (the holding layer sewn first) on or off."
        case .showUnderlay: return "Show or hide the underlay stitches on the canvas."
        case .focusSpacing: return "Jump to the row spacing setting."
        case .focusAngle: return "Jump to the fill angle setting."
        case .openShapeTool: return "Draw an open line and give it the stitch picked in the Next shape bar: running, bean or satin."
        case .closedShapeTool: return "Draw a closed shape and give it the stitches picked in the Next shape bar: a fill, an outline, or both."
        case .freehandOpenTool: return "Press and drag to draw an open line that follows the pointer; it gets the Next shape bar's stitch."
        case .freehandClosedTool: return "Press and drag to draw a closed shape that follows the pointer; it gets the Next shape bar's stitches."
        case .rectangleTool: return "Drag out a rectangle, corner to corner. Hold ⌘ for a square."
        case .ellipseTool: return "Drag out an ellipse from its center. Hold ⌘ for a circle."
        case .basicShapeTool: return "Drag out a polygon, star, heart or arrow, picked in the Next shape bar."
        case .knifeTool: return "Cut shapes in two: click points across them and press Return."
        case .weldObjects: return "Join overlapping shapes into one fill."
        case .smoothShapes: return "Remove points that barely shape the selected outlines, to tidy them."
        case .laydown: return "Add a light, open fill under the design that flattens towel, fleece or velvet pile."
        case .branching: return "Sew touching objects in one go: the needle travels inside them instead of trimming between them."
        case .addStitchAngles: return "Draw lines across a fill to set which way its stitches run; they turn smoothly between lines."
        case .removeStitchAngles: return "Click a fill's stitch angle line to remove it."
        case .editStitches: return "Move, delete or add individual needle points of the selected object."
        case .addMonogram: return "Add one to three initials in a classic layout, with ornaments and a border."
        case .editMonogram: return "Change the selected monogram's initials, font, layout or border."
        // Editing and arranging
        case .undo: return "Take back the last change."
        case .redo: return "Put back the change you just undid."
        case .delete: return "Delete the selected objects."
        case .selectAll: return "Select every object that isn't locked or hidden."
        case .sequenceBySelection: return "Sew the selected objects one after another, in the order you clicked them."
        case .alignLeft: return "Line up the selected objects' left edges with the one you selected last."
        case .alignCentersVertically: return "Line up the selected objects' centers in a column, under the one you selected last."
        case .alignRight: return "Line up the selected objects' right edges with the one you selected last."
        case .alignTop: return "Line up the selected objects' tops with the one you selected last."
        case .alignCentersHorizontally: return "Line up the selected objects' centers in a row, with the one you selected last."
        case .alignBottom: return "Line up the selected objects' bottoms with the one you selected last."
        case .alignCenters: return "Put the selected objects' centers on the center of the one you selected last."
        case .spaceAcross: return "Make the gaps between the selected objects equal, left to right. The outer two stay put."
        case .spaceDown: return "Make the gaps between the selected objects equal, top to bottom. The outer two stay put."
        case .duplicate: return "Make a copy of the selection, just beside it."
        case .mirrorH: return "Flip the selection left to right."
        case .mirrorV: return "Flip the selection upside down."
        case .rotateLeft: return "Turn the selection a quarter turn counterclockwise."
        case .rotateRight: return "Turn the selection a quarter turn clockwise."
        case .earlier: return "Sew the selection one step earlier."
        case .later: return "Sew the selection one step later."
        case .closePath: return "Join the selected line's ends into a closed loop, or open it again."
        case .lockObject: return "Lock the selection so it can't be moved or changed by accident, or unlock it."
        case .hideObject: return "Hide the selection on the canvas while you work, or show it again. Hidden objects still sew."
        case .tieIn: return "Tiny locking stitches at the start, so the thread can't pull out."
        case .tieOut: return "Tiny locking stitches at the end, so the thread can't unravel."
        case .trimAfter: return "Cut the thread after this object, before the machine moves on."
        case .stopAfter: return "Pause the machine after this object, such as to change fabric or thread."
        case .group: return "Group the selection so it moves, turns and resizes together."
        case .ungroup: return "Split the selected group back into separate objects."
        case .threadChart: return "Pick a real thread by brand and color number for the current color."
        case .cutObjects: return "Remove the selection and keep a copy to paste."
        case .copyObjects: return "Copy the selection, to paste here or into another design."
        case .pasteObjects: return "Add the copied objects to this design."
        // Viewing
        case .zoomIn: return "Make everything bigger on screen, to look closer."
        case .zoomOut: return "Make everything smaller on screen, to see more of the hoop."
        case .zoomFit: return "Show the whole hoop."
        case .zoomBoxTool: return "Drag a box around the part to look at; a click zooms in around the pointer."
        case .zoomActual: return "Show the design at its real size on your screen."
        case .zoomSelected: return "Zoom until the selection fills the view."
        case .zoomDesign: return "Zoom until the whole design fills the view."
        case .showStitches: return "Show or hide the stitches."
        case .showOutlines: return "Show or hide every object's outline, to check shapes against the artwork."
        case .showConnectors: return "Show or hide the dashed travel moves between parts of the design."
        case .hideOthers: return "Show only the selected objects, to work on one part of a busy design."
        case .measureTool: return "Drag between two points to read the distance in mm and its angle."
        case .grid: return "Show or hide the millimeter grid."
        case .snap: return "Make clicks and drags jump to the nearest grid line, or onto a guide close by."
        case .clearGuides: return "Remove every guide line. Drag from a ruler to add one, and back onto it to remove one."
        case .needles: return "Show or hide a dot at every needle point."
        case .threadView: return "Draw each stitch as real thread, to see how the design will look sewn."
        case .artwork: return "Show or hide the reference image."
        case .inspector: return "Show or hide the Properties panel."
        case .palette: return "Show or hide the Threads panel."
        case .restoreWorkspace: return "Put the panels back where they started."
        case .saveWorkspace: return "Keep the current panel layout to come back to."
        case .proView: return "Switch between Guided (everyday settings) and Pro (everything at once)."
        case .panelSewingOrder: return "Show or hide the Sewing order panel: every object, in the order it sews."
        case .panelDesign: return "Show or hide the Design panel: fabric, hoop and holding the fabric."
        case .panelReference: return "Show or hide the Reference image panel."
        case .panelPlayer: return "Show or hide the Stitch player panel."
        case .nextTab: return "Switch to the design in the next tab along."
        case .previousTab: return "Switch to the design in the tab before this one."
        case .nudgeLeft: return "Move the selection a little to the left."
        case .nudgeRight: return "Move the selection a little to the right."
        case .nudgeUp: return "Move the selection a little up."
        case .nudgeDown: return "Move the selection a little down."
        case .play: return "Watch the design sew, stitch by stitch, or pause it."
        case .rewind: return "Take the stitch player back to the very first stitch."
        case .focusLength: return "Jump to the stitch length setting."
        }
    }
    public var category: String {
        switch self {
        case .new, .open, .save, .saveAs, .close, .importImage, .importSVG, .importMachine, .exportPES, .exportMachine, .exportDST, .exportEXP, .exportJEF, .exportVP3, .exportXXX, .exportPEC, .exportThreadList, .productionWorksheet, .sample, .stitchSampler: return "File"
        case .selectTool, .runTool, .satinTool, .fillTool, .holeTool, .nodeTool, .panTool, .entryExitTool, .autoStartPoints, .clearStartEnd, .lettering, .editLettering, .autoDigitize, .satinBorder, .applique, .done, .artworkTool, .finishPath, .cancelPath, .removePoint, .openShapeTool, .closedShapeTool, .freehandOpenTool, .freehandClosedTool, .rectangleTool, .ellipseTool, .basicShapeTool, .knifeTool, .laydown, .branching, .addStitchAngles, .removeStitchAngles, .editStitches, .addMonogram, .editMonogram: return "Digitizing"
        case .settings, .inspector, .palette, .restoreWorkspace, .saveWorkspace, .panelSewingOrder, .panelDesign, .panelReference, .panelPlayer, .nextTab, .previousTab: return "Workspace"
        case .zoomIn, .zoomOut, .zoomFit, .zoomDesign, .zoomBoxTool, .zoomActual, .zoomSelected, .showStitches, .showOutlines, .showConnectors, .hideOthers, .measureTool, .grid, .snap, .clearGuides, .needles, .threadView, .artwork, .play, .rewind, .proView: return "View"
        default: return "Edit"
        }
    }
    public var appWide: Bool { [.new, .open, .save, .saveAs, .close, .settings].contains(self) }
    public var contexts: Set<CommandContext> {
        if appWide { return [.canvas, .drawing, .list, .text] }
        if [.finishPath, .cancelPath, .removePoint].contains(self) { return [.drawing] }
        if [.holeTool, .removeHoles, .insertNode, .deleteNode, .renameObject, .convertFill, .convertRun, .convertSatin, .toggleUnderlay, .focusSpacing, .focusAngle, .delete, .selectAll, .sequenceBySelection, .alignLeft, .alignCentersVertically, .alignRight, .alignTop, .alignCentersHorizontally, .alignBottom, .alignCenters, .spaceAcross, .spaceDown, .duplicate, .mirrorH, .mirrorV, .rotateLeft, .rotateRight, .earlier, .later, .closePath, .lockObject, .hideObject, .group, .ungroup, .threadChart, .cutObjects, .copyObjects, .pasteObjects, .clearStartEnd, .lettering, .editLettering, .autoDigitize, .satinBorder, .applique, .done, .focusLength, .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .weldObjects, .smoothShapes, .laydown, .branching, .addMonogram, .editMonogram].contains(self) { return [.canvas, .list] }
        return [.canvas, .drawing, .list]
    }
    public var repeats: Bool { [.nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .zoomIn, .zoomOut].contains(self) }
    /// The keys a command starts with, chosen so people used to other embroidery software find the usual keys.
    /// Function keys get a letter too, because Mac keyboards need fn for F1–F12.
    /// Modifiers add up: 1 = ⌘, 2 = ⇧, 4 = ⌥, 8 = ⌃.
    public var defaults: [KeyBinding] {
        switch self {
        // File
        case .new: return [.init("n", 1)]; case .open: return [.init("o", 1)]; case .save: return [.init("s", 1)]
        case .saveAs: return [.init("s", 3)]; case .close: return [.init("w", 1)]; case .settings: return [.init(",", 1)]
        case .importImage: return [.init("i", 1)]; case .importSVG: return [.init("i", 3)]; case .importMachine: return [.init("o", 5)]
        case .exportPES: return [.init("e", 1)]; case .exportMachine: return [.init("e", 2), .init("e", 3)]
        case .productionWorksheet: return [.init("p", 1)]
        // Digitizing tools
        case .selectTool: return [.init("o")]
        case .nodeTool: return [.init("h")]
        case .panTool: return [.init("p")]
        case .runTool: return [.init("n", 2), .init("f8")]
        case .satinTool: return [.init("a", 2), .init("f4")]
        case .convertSatin: return [.init("i", 2), .init("f6")]
        case .fillTool: return [.init("f3"), .init("f", 4)]
        case .convertFill: return [.init("m", 2)]
        case .applique: return [.init("f7"), .init("q", 4)]
        case .lettering: return [.init("a")]
        case .satinBorder: return [.init("o", 3)]
        case .toggleUnderlay: return [.init("u")]
        case .done: return [.init("escape")]   // while drawing, Escape cancels the path instead
        case .finishPath: return [.init("return")]; case .cancelPath: return [.init("escape")]
        case .removePoint, .delete: return [.init("delete")]
        // More tools, on ⌥ and ⇧⌥ keys
        case .artworkTool: return [.init("d", 4)]; case .holeTool: return [.init("h", 4)]; case .autoDigitize: return [.init("m", 4)]
        case .entryExitTool: return [.init("e", 4)]; case .editLettering: return [.init("l", 4)]; case .threadChart: return [.init("t", 4)]
        case .insertNode: return [.init("i", 6)]; case .deleteNode: return [.init("delete", 2)]; case .showUnderlay: return [.init("u", 2)]
        case .openShapeTool: return [.init("o", 4)]; case .closedShapeTool: return [.init("s", 4)]
        case .freehandOpenTool: return [.init("o", 6)]; case .freehandClosedTool: return [.init("s", 6)]   // ⇧ added to the Open and Closed Shape keys
        case .rectangleTool: return [.init("r", 4)]; case .ellipseTool: return [.init("j", 4)]; case .basicShapeTool: return [.init("b", 4)]
        case .knifeTool: return [.init("k", 4)]; case .weldObjects: return [.init("w", 4)]; case .smoothShapes: return [.init("n", 4)]
        case .laydown: return [.init("l", 6)]
        case .addStitchAngles: return [.init("h", 8)]; case .removeStitchAngles: return [.init("h", 10)]   // ⌃H, because ⌘H hides the app on a Mac
        case .branching: return [.init("i")]   // Insert Node moved to ⇧⌥I for it
        case .editStitches: return [.init("e")]
        case .addMonogram: return [.init("m", 6)]
        // Editing
        case .undo: return [.init("z", 1)]; case .redo: return [.init("y", 1), .init("z", 3)]
        case .selectAll: return [.init("a", 1)]; case .duplicate: return [.init("d", 1)]
        case .group: return [.init("g", 1)]; case .ungroup: return [.init("u", 1)]; case .lockObject: return [.init("k")]
        case .mirrorH: return [.init("1", 1)]; case .mirrorV: return [.init("1", 4)]
        case .cutObjects: return [.init("x", 1)]; case .copyObjects: return [.init("c", 1)]; case .pasteObjects: return [.init("v", 1)]
        case .nudgeLeft: return [.init("left")]; case .nudgeRight: return [.init("right")]; case .nudgeUp: return [.init("up")]; case .nudgeDown: return [.init("down")]
        // View
        case .zoomIn: return [.init("z"), .init("=", 1)]; case .zoomOut: return [.init("z", 2), .init("-", 1)]; case .zoomFit: return [.init("0", 4)]
        case .zoomBoxTool: return [.init("b")]; case .zoomActual: return [.init("1")]; case .zoomSelected: return [.init("0", 2)]; case .zoomDesign: return [.init("0")]
        case .showStitches: return [.init("s")]; case .showOutlines: return [.init("l")]; case .showConnectors: return [.init("c", 2)]; case .hideOthers: return [.init("s", 2)]
        case .measureTool: return [.init("m")]
        case .grid: return [.init("g", 2)]; case .snap: return [.init("g", 3)]; case .needles: return [.init(".")]
        case .threadView: return [.init("t")]
        case .artwork: return [.init("d")]
        case .play: return [.init("space"), .init("r", 2)]; case .rewind: return [.init("home")]
        case .proView: return [.init("p", 5)]; case .inspector: return [.init("i", 5)]
        // Design tabs, as in Safari: ⌃⇥ / ⌃⇧⇥ or ⇧⌘] / ⇧⌘[
        case .nextTab: return [.init("tab", 8), .init("]", 3)]; case .previousTab: return [.init("tab", 10), .init("[", 3)]
        default: return []
        }
    }
    /// The keys commands had in the first set of defaults (only commands whose keys changed since), so a saved
    /// profile can tell which keys the person never changed and move just those to the new defaults.
    static let firstDefaults: [CommandID: [KeyBinding]] = [
        .importMachine: [.init("o", 3)], .exportMachine: [.init("e", 3)], .selectTool: [.init("v")], .nodeTool: [.init("n")],
        .panTool: [.init("h")], .runTool: [.init("r")], .satinTool: [.init("s")], .convertSatin: [.init("s", 2)], .fillTool: [.init("f")],
        .convertFill: [], .applique: [.init("a", 4)], .lettering: [.init("t")], .satinBorder: [.init("b", 2)], .artworkTool: [.init("a")],
        .holeTool: [.init("o")], .autoDigitize: [.init("a", 2)], .entryExitTool: [.init("e")], .editLettering: [.init("t", 2)],
        .threadChart: [.init("c")], .redo: [.init("z", 3)], .ungroup: [.init("g", 3)], .lockObject: [], .mirrorH: [], .mirrorV: [],
        .zoomIn: [.init("=", 1)], .zoomOut: [.init("-", 1)], .zoomFit: [.init("0", 1)], .grid: [.init("g")], .snap: [.init("g", 2)],
        .needles: [.init("p")], .artwork: [.init("b")], .play: [.init("space")], .rewind: []
    ]
    public var symbol: String {
        switch self {
        case .satinTool:return "line.3.horizontal";case .fillTool:return "square.fill";case .holeTool:return "circle.dashed"
        case .selectTool: return "cursorarrow"; case .runTool: return "point.topleft.down.to.point.bottomright.curvepath"
        case .nodeTool: return "point.3.connected.trianglepath.dotted"; case .panTool: return "hand.draw"; case .entryExitTool: return "flag"; case .autoStartPoints: return "wand.and.stars"; case .clearStartEnd: return "flag.slash"; case .lettering: return "textformat"; case .editLettering: return "character.cursor.ibeam"; case .autoDigitize: return "wand.and.rays"; case .satinBorder: return "circle.circle"; case .applique: return "scissors"; case .done: return "checkmark.circle"; case .artworkTool: return "photo"
        case .importImage: return "photo.badge.plus"; case .exportPES: return "square.and.arrow.up"; case .productionWorksheet: return "doc.text"; case .save: return "square.and.arrow.down"
        case .zoomFit: return "arrow.up.left.and.arrow.down.right"; case .zoomBoxTool: return "plus.magnifyingglass"; case .zoomActual: return "1.magnifyingglass"; case .zoomSelected: return "viewfinder"; case .zoomDesign: return "square.dashed";
        case .showStitches: return "point.topleft.down.to.point.bottomright.curvepath.fill"; case .showOutlines: return "rectangle.dashed"; case .showConnectors: return "line.diagonal"; case .hideOthers: return "eye.square"; case .measureTool: return "ruler"; case .sequenceBySelection: return "list.number"
        case .alignLeft: return "align.horizontal.left"; case .alignCentersVertically: return "align.horizontal.center"; case .alignRight: return "align.horizontal.right"
        case .alignTop: return "align.vertical.top"; case .alignCentersHorizontally: return "align.vertical.center"; case .alignBottom: return "align.vertical.bottom"
        case .alignCenters: return "plus.square.dashed"; case .spaceAcross: return "distribute.horizontal.center"; case .spaceDown: return "distribute.vertical.center"; case .settings: return "gearshape"; case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"; case .grid: return "grid"; case .snap: return "scope"; case .needles: return "circle.dotted"; case .threadView: return "eye"
        case .play: return "play.fill"; case .proView: return "slider.horizontal.3"; case .showUnderlay: return "square.stack"; case .group: return "square.on.square"; case .ungroup: return "square.dashed"; case .threadChart: return "swatchpalette"
        case .openShapeTool: return "scribble"; case .closedShapeTool: return "lasso"; case .freehandOpenTool: return "pencil.line"; case .freehandClosedTool: return "pencil.and.scribble"; case .rectangleTool: return "rectangle"; case .ellipseTool: return "oval"; case .basicShapeTool: return "star"
        case .knifeTool: return "square.split.diagonal"; case .weldObjects: return "square.on.circle"; case .smoothShapes: return "point.topleft.down.curvedto.point.bottomright.up"; case .laydown: return "square.grid.3x3"; case .branching: return "arrow.triangle.branch"; case .addStitchAngles: return "angle"; case .removeStitchAngles: return "eraser.line.dashed"; case .editStitches: return "point.3.filled.connected.trianglepath.dotted"; case .addMonogram: return "seal"; case .editMonogram: return "pencil.and.outline"
        default: return "circle"
        }
    }
}

public struct ShortcutProfile: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var bindings: [String: [KeyBinding]]
    /// Which set of default keys this profile was made with: nil for profiles saved with the first default keys, 2
    /// after, 3 once Branching took I from Insert Node.
    public var keySet: Int?
    public init(name: String = "My Shortcuts") {
        self.name = name
        bindings = Dictionary(uniqueKeysWithValues: CommandID.allCases.map { ($0.rawValue, $0.defaults) })
        keySet = 3
    }
    /// Moves a profile saved with the first default keys onto the second set, once. Only commands still on their old
    /// default key change; keys the person set themselves stay, and a new default that would clash with one of
    /// them is left out. Returns whether anything changed.
    @discardableResult public mutating func updateToSecondKeySet() -> Bool {
        guard keySet == nil else { return false }
        let untouched = CommandID.firstDefaults.filter { bindings[$0.key.rawValue] == $0.value }.map(\.key)
        for command in untouched { bindings[command.rawValue] = [] }
        for command in CommandID.allCases where untouched.contains(command) {
            bindings[command.rawValue] = command.defaults.filter { conflicts($0, for: command).isEmpty }
        }
        keySet = 2
        return true
    }
    /// Gives Branching the I key, once: Insert Node, which had I, moves to its new key
    /// (⇧⌥I) unless the person set its key themselves. Returns whether anything changed.
    @discardableResult public mutating func updateToBranchingKey() -> Bool {
        guard keySet == 2 else { return false }
        let insertNodeHadI = bindings[CommandID.insertNode.rawValue] == [.init("i")]
        if insertNodeHadI { bindings[CommandID.insertNode.rawValue] = [] }
        // Insert Node gets its new key only if it gave up I (a key cleared on purpose stays cleared).
        for command in [CommandID.insertNode, .branching] where bindings[command.rawValue] == nil || (command == .insertNode ? insertNodeHadI : bindings[command.rawValue] == []) {
            bindings[command.rawValue] = command.defaults.filter { conflicts($0, for: command).isEmpty }
        }
        keySet = 3
        return true
    }
    /// Brings a saved profile up to date: the moves above (each once, keeping keys the person set), then commands
    /// added since it was saved get their default keys where they're free. The moves come first, so new commands
    /// can have keys the moves freed. Returns whether any keys moved.
    @discardableResult public mutating func upgrade() -> Bool {
        let movedToSecondSet = updateToSecondKeySet(), movedForBranching = updateToBranchingKey()
        for command in CommandID.allCases where bindings[command.rawValue] == nil {
            bindings[command.rawValue] = command.defaults.filter { conflicts($0, for: command).isEmpty }
        }
        return movedToSecondSet || movedForBranching
    }
    public func conflicts(_ binding: KeyBinding, for command: CommandID) -> [CommandID] {
        CommandID.allCases.filter { $0 != command && !$0.contexts.isDisjoint(with: command.contexts) && (bindings[$0.rawValue] ?? []).contains(binding) }
    }
    public func command(for key: KeyBinding, context: CommandContext, repeating: Bool = false) -> CommandID? {
        CommandID.allCases.first { $0.contexts.contains(context) && (!repeating || $0.repeats) && (bindings[$0.rawValue] ?? []).contains(key) }
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, bindings.count < 1000 else { throw DesignError.invalid("Invalid shortcut profile.") }
        for (id, values) in bindings {
            guard values.count <= 20, values.allSatisfy(\.valid) else { throw DesignError.invalid("Invalid shortcut in \(id).") }
            if let command = CommandID(rawValue: id) {
                for value in values where !conflicts(value, for: command).isEmpty { throw DesignError.invalid("Conflicting assignment: \(value.display) for \(command.title).") }
            }
        }
    }
}
