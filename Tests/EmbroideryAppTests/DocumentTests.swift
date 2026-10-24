import XCTest
import AppKit
import UniformTypeIdentifiers
import EmbroideryCore
@testable import EmbroideryApp

final class DocumentTests: XCTestCase {
    @MainActor func testDraftAndArtworkPersistWithoutDirtyingRead() throws {
        _ = NSApplication.shared
        let source = DesignDocument()
        source.state.design = Design.sample()
        source.state.design.artwork = Artwork(data: Data([1, 2, 3]), name: "fixture", width: 20, height: 20)
        source.state.draft = [PathNode(Point(1, 2)), PathNode(Point(3, 4), smooth: true)]
        source.state.currentColor = .palette[3]
        let wrapper = try source.fileWrapper(ofType: "Embroidery Project")
        let loaded = DesignDocument()
        try loaded.read(from: wrapper, ofType: "Embroidery Project")
        XCTAssertEqual(loaded.state.design.artwork?.data, Data([1, 2, 3]))
        XCTAssertEqual(loaded.state.draft, source.state.draft)
        XCTAssertEqual(loaded.state.currentColor, source.state.currentColor)
        XCTAssertFalse(loaded.isDocumentEdited)
    }

    /// Saving puts a picture of the design at QuickLook/Thumbnail.png, which Finder shows as the project's icon.
    /// The fabric stays cream even when the app is in Dark Mode.
    @MainActor func testSavedProjectCarriesACreamThumbnailForFinder() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .darkAqua)
        defer { app.appearance = previousAppearance }
        let document = DesignDocument()
        document.state.design = Design.sample()
        let wrapper = try document.fileWrapper(ofType: "Embroidery Project")
        let png = try XCTUnwrap(wrapper.fileWrappers?["QuickLook"]?.fileWrappers?["Thumbnail.png"]?.regularFileContents)
        let picture = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(picture.pixelsWide, 512)
        XCTAssertEqual(picture.pixelsHigh, 512)
        // A spot in the left margin, away from the rounded corners, shows bare fabric: cream F4EDE1. The allowance covers
        // color-space rounding; Dark Mode's brown (1F1A16) would miss by far more.
        let fabric = try XCTUnwrap(picture.colorAt(x: 16, y: 256)?.usingColorSpace(.sRGB))
        XCTAssertEqual(fabric.redComponent, 0xF4 / 255, accuracy: 0.04)
        XCTAssertEqual(fabric.greenComponent, 0xED / 255, accuracy: 0.04)
        XCTAssertEqual(fabric.blueComponent, 0xE1 / 255, accuracy: 0.04)
        let loaded = DesignDocument()
        try loaded.read(from: wrapper, ofType: "Embroidery Project")   // the extra folder doesn't trouble opening
        XCTAssertEqual(loaded.state.design.objects, document.state.design.objects)
    }

    /// Dragging the artwork opacity slider shows each value live, and letting go saves the last one as one undo step.
    @MainActor func testArtworkOpacitySliderSavesOnceWhenLetGo() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        state.design.artwork = Artwork(data: Data([1, 2, 3]), name: "fixture", width: 20, height: 20)
        state.artworkOpacitySlider(editing: true)
        state.previewArtworkOpacity(0.2); state.previewArtworkOpacity(0.7)
        XCTAssertEqual(state.artworkOpacityPreview, 0.7, "shown live")
        XCTAssertEqual(state.design.artwork?.opacity, 0.4, "not saved while dragging")
        state.artworkOpacitySlider(editing: false)
        XCTAssertNil(state.artworkOpacityPreview)
        XCTAssertEqual(state.design.artwork?.opacity, 0.7, "saved when let go")
        document.undoManager?.undo()
        XCTAssertEqual(state.design.artwork?.opacity, 0.4, "one undo step for the whole drag")
        state.previewArtworkOpacity(0.9)   // a change without a drag (such as from the keyboard) saves straight away
        XCTAssertEqual(state.design.artwork?.opacity, 0.9); XCTAssertNil(state.artworkOpacityPreview)
    }

    @MainActor func testMirrorPivotIgnoresLockedSelectedObjects() {
        _ = NSApplication.shared
        let document = DesignDocument()
        let free = RunObject(name: "Free", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 4))], color: .palette[0])
        var locked = RunObject(name: "Locked", nodes: [PathNode(Point(40, 0)), PathNode(Point(50, 4))], color: .palette[1])
        locked.locked = true
        document.state.design.objects = [free, locked]
        document.state.selection = [free.id, locked.id]
        document.state.mirrorOrRotateSelection(.mirrorH)
        // Locked objects are never moved, so they must not shift the pivot either: the free one flips in place.
        XCTAssertEqual(document.state.design.objects[0].nodes.map(\.point.x), [10, 0])
        XCTAssertEqual(document.state.design.objects[1].nodes.map(\.point.x), [40, 50])
    }

    /// Bending lettering into an envelope is one undoable rebuild, saved as file version 9 and reopened with it;
    /// taking the envelope off goes back to the version the rest needs.
    @MainActor func testLetteringEnvelopeSavesAsVersionNineAndReopens() throws {
        _ = NSApplication.shared
        let document = DesignDocument(); let state = document.state
        var design = Design()
        design.objects = try LetteringSpec(text: "HI", fontKind: .system, font: "Helvetica-Bold", height: 10).build(color: .palette[0], embroideryFonts: []).objects
        state.design = design   // set directly: changes made in one go in a test would undo as one step
        let plain = state.design
        var spec = try XCTUnwrap(plain.objects.first?.lettering)
        spec.envelope = LetteringEnvelope(kind: .bridge)
        XCTAssertTrue(state.rebuildLettering(spec, action: "Lettering Envelope"))
        XCTAssertEqual(state.design.schemaVersion, 9)
        let loaded = DesignDocument()
        try loaded.read(from: try document.fileWrapper(ofType: "Embroidery Project"), ofType: "Embroidery Project")
        XCTAssertEqual(loaded.state.design.objects.first?.lettering?.envelope?.kind, .bridge)
        document.undoManager?.undo()
        XCTAssertEqual(state.design.objects.map(\.nodes), plain.objects.map(\.nodes), "One undo takes the envelope off")
        XCTAssertLessThan(state.design.schemaVersion, 9)
        document.close(); loaded.close()
    }

    @MainActor func testBezierHandlesSaveAsSchemaFiveAndReopen() throws {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design = Design.sample()
        XCTAssertEqual(document.state.design.schemaVersion, 4)
        var curved = document.state.design
        curved.objects[2].nodes[1].outHandle = Point(8, -4)   // shape the sample's "Curved horizon"
        document.replace(curved, action: "Shape Curve")
        XCTAssertEqual(document.state.design.schemaVersion, 5)
        let loaded = DesignDocument()
        try loaded.read(from: try document.fileWrapper(ofType: "Embroidery Project"), ofType: "Embroidery Project")
        XCTAssertEqual(loaded.state.design.objects[2].nodes[1].outHandle, Point(8, -4))
        var straightened = loaded.state.design
        straightened.objects[2].nodes[1].toggleSmooth()
        loaded.replace(straightened, action: "Change Node Type")
        XCTAssertEqual(loaded.state.design.schemaVersion, 4, "Without handles the project stays readable by v0.5")
    }

    /// The object lists select the Mac way: Shift-click takes everything in sewing order from the object clicked last,
    /// ⌘-click (`extend`) adds or removes one, and a range takes whole groups unless Option asks for single objects.
    @MainActor func testShiftClickInTheListsSelectsARangeInSewingOrder() {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design.objects = (0..<5).map { RunObject(name: "Line \($0 + 1)", nodes: [PathNode(Point(Double($0) * 10, 0)), PathNode(Point(Double($0) * 10, 20))]) }
        let ids = document.state.design.objects.map(\.id)
        document.state.selectRange(to: ids[3])
        XCTAssertEqual(document.state.selection, [ids[3]], "with nothing clicked before, Shift-click selects just that object")
        document.state.select(ids[1])
        document.state.selectRange(to: ids[3])
        XCTAssertEqual(document.state.selection, [ids[1], ids[2], ids[3]])
        document.state.selectRange(to: ids[0])
        XCTAssertEqual(document.state.selection, [ids[0], ids[1]], "the range starts again from the same object, upward this time")
        document.state.select(ids[4], extend: true)
        XCTAssertEqual(document.state.selection, [ids[0], ids[1], ids[4]], "⌘-click adds one")
        document.state.select(ids[0], extend: true)
        XCTAssertEqual(document.state.selection, [ids[1], ids[4]], "⌘-click again removes it")
        // Lines 4 and 5 become a group: a range reaching line 4 takes line 5 too, unless Option picks single objects.
        document.state.selection = [ids[3], ids[4]]
        document.state.groupSelection()
        document.state.select(ids[1])
        document.state.selectRange(to: ids[3])
        XCTAssertEqual(document.state.selection, [ids[1], ids[2], ids[3], ids[4]])
        document.state.selectRange(to: ids[3], single: true)
        XCTAssertEqual(document.state.selection, [ids[1], ids[2], ids[3]])
    }

    @MainActor func testGroupSelectDuplicateAndUngroup() {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design = Design.sample()
        let ids = document.state.design.objects.map(\.id)
        document.state.selection = [ids[0], ids[2]]
        document.state.groupSelection()
        document.state.select(ids[0])
        XCTAssertEqual(document.state.selection, [ids[0], ids[2]], "Clicking one member selects the whole group")
        document.state.select(ids[2], single: true)
        XCTAssertEqual(document.state.selection, [ids[2]], "Option-click picks one member")
        document.state.select(ids[0])
        document.state.duplicateSelection()
        let copies = document.state.design.objects.suffix(2)
        XCTAssertEqual(Set(copies.compactMap(\.groupID)).count, 1)
        XCTAssertNotEqual(copies.first?.groupID, document.state.design.objects[0].groupID, "Copies form their own group")
        document.state.select(ids[0])
        document.state.ungroupSelection()
        XCTAssertNil(document.state.design.objects[0].groupID); XCTAssertNil(document.state.design.objects[2].groupID)
        XCTAssertNotNil(document.state.design.objects.last?.groupID, "Ungrouping one group leaves the copy's group alone")
    }

    @MainActor func testDuplicatedBranchIsItsOwnBranch() {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design = Design.sample()
        let branch = UUID()
        for i in 0..<2 { document.state.design.objects[i].branchID = branch }
        document.state.selection = Set(document.state.design.objects.prefix(2).map(\.id))
        document.state.duplicateSelection()
        let copies = document.state.design.objects.suffix(2).map(\.branchID)
        XCTAssertEqual(Set(copies).count, 1); XCTAssertNotNil(copies[0])
        XCTAssertNotEqual(copies[0], branch, "the copies are a new branch, not joined to the original")
    }

    @MainActor func testAutoStartPointsRunsInTheBackgroundAndIsOneUndoableEdit() async throws {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design = Design.sample()
        document.state.autoStartPoints()
        for _ in 0..<200 where document.state.design.objects[1].entry == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(document.state.design.objects[1].entry); XCTAssertNotNil(document.state.design.objects[2].entry)
        XCTAssertTrue(document.state.status.hasPrefix("Start points set"), document.state.status)
        XCTAssertEqual(document.state.design.schemaVersion, 5)
        document.undoManager?.undo()
        XCTAssertNil(document.state.design.objects[1].entry, "One undo removes every automatic start point")
    }

    @MainActor func testClearStartEndIsOneUndoableEditAndExplainsEmptySelections() {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design = Design.sample()
        let id = document.state.design.objects[0].id
        document.state.selection = [id]
        document.state.clearStartEnd()
        XCTAssertTrue(document.state.status.contains("no start or end points"))
        // Set the points directly (not as an undoable edit): edits made in one instant share an undo step.
        document.state.design.objects[0].entry = Point(1, 1); document.state.design.objects[0].exit = Point(2, 2)
        document.state.clearStartEnd()
        XCTAssertNil(document.state.design.objects[0].entry); XCTAssertNil(document.state.design.objects[0].exit)
        document.undoManager?.undo()
        XCTAssertEqual(document.state.design.objects[0].entry, Point(1, 1))
    }

    @MainActor func testFabricColorIsUndoableSavedAndOptional() throws {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design = Design.sample()
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(document.state.design), as: UTF8.self).contains("fabricColor"))
        document.state.edit("Fabric Color") { $0.fabricColor = 0x1C1C1E }
        let loaded = DesignDocument()
        try loaded.read(from: try document.fileWrapper(ofType: "Embroidery Project"), ofType: "Embroidery Project")
        XCTAssertEqual(loaded.state.design.fabricColor, 0x1C1C1E)
        XCTAssertEqual(loaded.state.design.schemaVersion, 4, "Fabric color is preview only, so v0.5 can still open the file")
        document.undoManager?.undo()
        XCTAssertNil(document.state.design.fabricColor)
        var bad = Design(); bad.fabricColor = 0x1000000
        XCTAssertThrowsError(try bad.validate())
    }

    func testPreferencesFromBeforeColorSettingsStillLoad() throws {
        let old = #"{"version":1,"profiles":[{"id":"8E1C3D52-6B44-4F1A-9C7B-3A2B1C0D9E8F","name":"My Shortcuts","bindings":{}}],"activeProfile":0,"workspaces":[],"workspace":{"id":"8E1C3D52-6B44-4F1A-9C7B-3A2B1C0D9E80","name":"Default","inspectorVisible":true,"paletteVisible":true,"inspectorOnLeft":false,"objectsWidth":220,"inspectorWidth":260}}"#
        let data = try JSONDecoder().decode(PreferenceData.self, from: Data(old.utf8))
        XCTAssertNil(data.pasteboardColor)
    }

    @MainActor func testRevertDuringGenerationProducesCurrentExportablePlan() async throws {
        _ = NSApplication.shared
        let document = DesignDocument()
        document.state.design = Design.sample()
        let saved = try document.fileWrapper(ofType: "Embroidery Project")
        let controller = NSWindowController(window: NSWindow())
        document.addWindowController(controller)
        document.state.selection = [document.state.design.objects[0].id]
        document.state.draft = [PathNode(Point(8, 9))]
        document.regenerate()
        try document.read(from: saved, ofType: "Embroidery Project")
        for _ in 0..<100 where document.state.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(document.state.busy)
        XCTAssertEqual(document.state.compiledRevision, document.state.revision)
        XCTAssertTrue(document.state.selection.isEmpty)
        XCTAssertTrue(document.state.draft.isEmpty)
        XCTAssertEqual(document.state.plan.stitchCount, 162)
        document.removeWindowController(controller)
    }

    func testHelperEarlyExitDoesNotTerminateEditor() {
        // Larger than a pipe buffer, ensuring an early child exit breaks the write.
        XCTAssertThrowsError(try Exporter.runHelper(bytes: Data(repeating: 32, count: 2_000_000), executable: URL(fileURLWithPath: "/usr/bin/false")))
    }
    @MainActor func testAreaDraftRestoresToolAndHoleTarget() throws {
        _ = NSApplication.shared
        for tool in [Tool.satin,.fill,.hole] {
            let source=DesignDocument();source.state.design=Design.stitchSampler()
            source.state.tool=tool;source.state.holeTarget=tool == .hole ? source.state.design.objects[0].id:nil
            source.state.draft=[PathNode(Point(1,2)),PathNode(Point(3,4))]
            let loaded=DesignDocument()
            try loaded.read(from:source.fileWrapper(ofType:"Embroidery Project"),ofType:"Embroidery Project")
            XCTAssertEqual(loaded.state.tool,tool)
            XCTAssertEqual(loaded.state.holeTarget,source.state.holeTarget)
            XCTAssertEqual(loaded.state.draft,source.state.draft)
            XCTAssertFalse(loaded.isDocumentEdited)
        }
    }

    @MainActor func testDraftSavedDuringZoomBoxRestoresTheDrawingTool() throws {
        _ = NSApplication.shared
        let source=DesignDocument();source.state.design=Design.stitchSampler()
        source.state.tool = .fill;source.state.draft=[PathNode(Point(1,2)),PathNode(Point(3,4))]
        source.state.toolBeforeZoom = .fill;source.state.tool = .zoomBox   // B pressed mid-path, then an autosave
        let loaded=DesignDocument()
        try loaded.read(from:source.fileWrapper(ofType:"Embroidery Project"),ofType:"Embroidery Project")
        XCTAssertEqual(loaded.state.tool, .fill, "the path comes back as a fill, not on the Zoom Box tool")
    }

    @MainActor func testLegacyProjectBlocksEditsUntilExplicitRegeneration() throws {
        _ = NSApplication.shared
        let source=DesignDocument();source.state.design=Design.sample()
        source.state.design.schemaVersion=1;source.state.design.engineVersion="run-1"
        source.state.design.cachedPlan=try StitchEngine.compile(source.state.design)
        let loaded=DesignDocument()
        try loaded.read(from:source.fileWrapper(ofType:"Embroidery Project"),ofType:"Embroidery Project")
        XCTAssertTrue(loaded.state.hasVersionMismatch)
        let original=loaded.state.design
        loaded.state.edit("Rename"){$0.objects[0].name="Changed"}
        XCTAssertEqual(loaded.state.design,original)
        XCTAssertEqual(loaded.state.plan.stitchCount,162)
        var regenerated=original;regenerated.engineVersion=Design.engineVersion
        loaded.replace(regenerated,action:"Regenerate")
        XCTAssertFalse(loaded.state.hasVersionMismatch)
        XCTAssertEqual(loaded.state.design.schemaVersion,4)
        loaded.close()
    }

    /// The newer tools can't change an older project either, and say so instead of reporting a change.
    @MainActor func testNewToolsDontClaimToChangeAnOlderProject() throws {
        _ = NSApplication.shared
        let source=DesignDocument();source.state.design=Design.sample()
        source.state.design.schemaVersion=1;source.state.design.engineVersion="run-1"
        source.state.design.cachedPlan=try StitchEngine.compile(source.state.design)
        let loaded=DesignDocument()
        try loaded.read(from:source.fileWrapper(ofType:"Embroidery Project"),ofType:"Embroidery Project")
        let state=loaded.state, original=state.design
        state.selection=Set(original.objects.prefix(2).map(\.id))
        state.startBranching(); state.addBranchPoint(nil); state.addBranchPoint(nil)
        XCTAssertEqual(state.design,original); XCTAssertTrue(state.status.contains("Regenerate"), state.status)
        XCTAssertFalse(state.edit("Rename"){$0.objects[0].name="Changed"}, "edit says it didn't happen")
        loaded.close()
    }

    /// Wreath: the tool waits for the center, previews the copies without changing the design, and makes them as
    /// one undoable step; a kaleidoscope keeps an even count.
    @MainActor func testWreathPreviewsThenMakesOneUndoableGroup() {
        _ = NSApplication.shared
        let document = DesignDocument(); let state = document.state
        state.design = Design.sample()
        let original = state.design, first = original.objects[0]
        state.selection = [first.id]
        state.startWreath()
        XCTAssertEqual(state.tool, .wreath); XCTAssertNil(state.wreathPreview, "No preview before the center is clicked")
        state.wreathCopies = 5; state.wreathMirrored = true
        XCTAssertEqual(state.wreathCopies, 6, "A kaleidoscope rounds up to an even count")
        state.wreathCenter = Point(0, 0)
        XCTAssertEqual(state.wreathPreview?.objects.count, original.objects.count + 5)
        XCTAssertEqual(state.design, original, "Previewing changes nothing")
        state.applyWreath()
        XCTAssertEqual(state.tool, .select)
        XCTAssertEqual(state.design.objects.count, original.objects.count + 5)
        XCTAssertEqual(state.selection.count, 6, "The whole wreath is selected")
        XCTAssertEqual(Set(state.design.objects.filter { state.selection.contains($0.id) }.map(\.groupID)).count, 1)
        document.undoManager?.undo()
        XCTAssertEqual(state.design, original, "One undo takes the whole wreath away")
        document.close()
    }

    func testEveryMachineSaveTypeHasItsExpectedExtension() {
        for format in MachineFormat.allCases {
            XCTAssertEqual(UTType(filenameExtension:format.rawValue)?.preferredFilenameExtension,format.rawValue)
        }
    }

    @MainActor func testVectorImportIsOneUndoStepAndPersistsUnstitched()throws {
        _ = NSApplication.shared
        let document=DesignDocument()
        let objects=try SVGImporter.load(Data("<svg><rect width='30' height='20'/></svg>".utf8)).objects
        document.undoManager?.groupsByEvent=false
        document.undoManager?.beginUndoGrouping()
        document.state.edit("Import SVG"){$0.objects+=objects}
        document.undoManager?.endUndoGrouping()
        document.undoManager?.undo();XCTAssertTrue(document.state.design.objects.isEmpty)
        document.undoManager?.redo();XCTAssertEqual(document.state.design.objects,objects)
        let loaded=DesignDocument()
        try loaded.read(from:document.fileWrapper(ofType:"Embroidery Project"),ofType:"Embroidery Project")
        XCTAssertEqual(loaded.state.design.objects[0].kind,.vector)
        XCTAssertEqual(loaded.state.design.schemaVersion,4);XCTAssertFalse(loaded.isDocumentEdited)
        XCTAssertEqual(try StitchEngine.compile(loaded.state.design).stitchCount,0)
        document.close();loaded.close()
    }

    @MainActor func testMachineImportUndoSaveAndRegenerationPreserveRawStitches()async throws {
        _ = NSApplication.shared
        var plan=StitchPlan();plan.threads=[.palette[0]]
        plan.commands=[.init(.jump,Point(-3,4),thread:0),.init(.stitch,Point(-3,4),thread:0),.init(.stitch,Point(2,5),thread:0),.init(.stop,Point(2,5),thread:0),.init(.end,Point(2,5),thread:0)]
        let objects=try MachineImport.objects(from:plan,format:"pes",name:"Raw fixture"),document=DesignDocument()
        document.undoManager?.groupsByEvent=false;document.undoManager?.beginUndoGrouping()
        document.state.edit("Import Machine Stitches"){$0.objects+=objects}
        document.undoManager?.endUndoGrouping()
        document.undoManager?.undo();XCTAssertTrue(document.state.design.objects.isEmpty)
        document.undoManager?.redo();XCTAssertEqual(document.state.design.objects,objects)
        for _ in 0..<100 where document.state.busy{try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertNil(document.state.generationError);XCTAssertEqual(document.state.plan.stitchCount,2)
        let loaded=DesignDocument();try loaded.read(from:document.fileWrapper(ofType:"Embroidery Project"),ofType:"Embroidery Project")
        for _ in 0..<100 where loaded.state.busy{try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertEqual(loaded.state.design.objects,objects);XCTAssertEqual(loaded.state.design.schemaVersion,4)
        XCTAssertEqual(loaded.state.plan.stitchCount,2)
        XCTAssertEqual(loaded.state.plan.commands.filter{$0.op == .stop}.count,1)
        XCTAssertFalse(loaded.isDocumentEdited);document.close();loaded.close()
    }

    func testBundledSevenFormatImportCompileExportReimport()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper=root.appendingPathComponent("dist/OpenHoop.app/Contents/Resources/format-helper/format-helper")
        guard FileManager.default.isExecutableFile(atPath:helper.path) else{throw DesignError.invalid("Build the app before running bundled format integration tests.")}
        func encode(_ plan:StitchPlan,_ format:MachineFormat)throws->Data {
            let request=try JSONEncoder().encode(ExportRequest(format:format.rawValue,pesVersion:6,plan:plan,hoop:Hoop()))
            let response=try JSONDecoder().decode(ExportResponse.self,from:Exporter.runHelper(bytes:request,executable:helper))
            guard response.ok,let bytes=response.bytes else{throw DesignError.invalid(response.error ?? "Export failed")};return bytes
        }
        func decode(_ bytes:Data,_ format:MachineFormat)throws->StitchPlan {
            let request=try JSONEncoder().encode(ImportRequest(format:format.rawValue,bytes:bytes))
            let response=try JSONDecoder().decode(ImportResponse.self,from:Exporter.runHelper(bytes:request,executable:helper))
            guard response.ok,let plan=response.plan else{throw DesignError.invalid(response.error ?? "Import failed")};return plan
        }
        var source=StitchPlan();source.threads=[.palette[0],.palette[1]]
        source.commands=[.init(.jump,Point(-5,-4),thread:0),.init(.stitch,Point(-5,-4),thread:0),.init(.stitch,Point(-3,-2),thread:0),.init(.trim,Point(-3,-2),thread:0),.init(.colorChange,Point(-3,-2),thread:1),.init(.jump,Point(1,1),thread:1),.init(.stitch,Point(1,1),thread:1),.init(.stop,Point(1,1),thread:1),.init(.stitch,Point(2,1),thread:1),.init(.end,Point(2,1),thread:1)]
        for format in MachineFormat.allCases {
            let imported=try decode(encode(source,format),format)
            var design=Design();design.objects=try MachineImport.objects(from:imported,format:format.rawValue,name:"Integration")
            let compiled=try StitchEngine.compile(design)
            let reopened=try decode(encode(compiled,format),format)
            XCTAssertEqual(reopened.commands.filter{$0.op == .stitch}.map(\.point),imported.commands.filter{$0.op == .stitch}.map(\.point),format.title)
            XCTAssertEqual(reopened.commands.filter{[.stop,.colorChange].contains($0.op)}.count,imported.commands.filter{[.stop,.colorChange].contains($0.op)}.count,format.title)
        }
    }


    /// The Pro view's summary (thread steps with object names, fabric) follows renames and fabric changes even
    /// while the stitches aren't worked out again, as when the new compile fails or is still running.
    @MainActor func testSummaryFollowsTheDesignWithoutANewPlan() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state
        var design = Design(); design.objects = [RunObject(name: "Leaf", nodes: [PathNode(Point(0, 0)), PathNode(Point(20, 0))], color: .palette[0])]
        state.design = design
        state.plan = try StitchEngine.compile(design)
        XCTAssertEqual(state.summary.steps.first?.parts, ["Leaf"])
        state.design.objects[0].name = "Stem"; state.design.fabricType = .towel
        XCTAssertEqual(state.summary.steps.first?.parts, ["Stem"])
        XCTAssertEqual(state.summary.fabric, .towel)
    }
}

