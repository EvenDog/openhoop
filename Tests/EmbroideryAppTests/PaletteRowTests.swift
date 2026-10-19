// Choosing a thread recolors the selection and keeps the thread in the design's palette as one Undo step; a thread
// objects sew in can't be taken out of the palette.
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class PaletteRowTests: XCTestCase {
    @MainActor func testChoosingAThreadRecolorsAndAddsItAsOneUndoStep() throws {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        let line = RunObject(name: "Line", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))], color: ThreadColor.palette[0])
        state.edit("Add") { $0.objects = [line] }
        state.selection = [line.id]
        document.undoManager?.removeAllActions()   // in a test everything is one event; start the history here

        let poppy = ThreadColor("Poppy", 0xE0241B, brand: "Isacord Polyester", code: "1703")
        state.chooseThread(poppy)
        XCTAssertEqual(state.currentColor, poppy)
        XCTAssertEqual(state.design.objects[0].color, poppy)
        XCTAssertEqual(state.design.paletteThreads.last, poppy)

        state.removeFromPalette(poppy)
        XCTAssertTrue(state.design.paletteThreads.contains(poppy), "the line sews in it, so it stays")

        document.undoManager?.undo()
        XCTAssertEqual(document.state.design.objects[0].color, ThreadColor.palette[0], "one Undo puts the color back")
        XCTAssertFalse(document.state.design.paletteThreads.contains(poppy), "and takes the thread out of the palette with it")
    }
}
