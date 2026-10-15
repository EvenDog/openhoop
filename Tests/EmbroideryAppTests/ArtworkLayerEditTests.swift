// The reference picture's place in the sewing order through real edits: deleting an object under it, adding one, and
// Undo, all going through the document's single save point (replace).
import XCTest
import AppKit
import EmbroideryCore
@testable import EmbroideryApp

final class ArtworkLayerEditTests: XCTestCase {
    @MainActor func testPictureKeepsItsPlaceThroughEditsAndUndo() {
        _ = NSApplication.shared
        let document = DesignDocument(), state = document.state   // the document must stay alive: edits go through it
        document.undoManager?.groupsByEvent = false
        func step(_ name: String, _ change: (inout Design) -> Void) {
            document.undoManager?.beginUndoGrouping(); state.edit(name, change); document.undoManager?.endUndoGrouping()
        }
        func line(_ name: String) -> RunObject { RunObject(name: name, nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))]) }
        func under() -> [String] { state.design.objects.prefix(state.design.artworkLayer).map(\.name) }
        step("Setup") { $0.objects = ["A", "B", "C"].map(line); $0.artwork = Artwork(data: Data([1]), name: "Logo", width: 20, height: 20) }
        step("Move Reference Picture") { $0.moveArtwork(by: 1); $0.moveArtwork(by: 1) }
        XCTAssertEqual(under(), ["A", "B"])
        step("Delete A") { $0.objects.removeFirst() }
        XCTAssertEqual(under(), ["B"], "C stays over the picture")
        step("Add D") { $0.objects.append(line("D")) }
        XCTAssertEqual(under(), ["B"], "the new object goes on top")
        document.undoManager?.undo(); document.undoManager?.undo()
        XCTAssertEqual(under(), ["A", "B"], "Undo puts back the objects and the picture's place")
    }
}
