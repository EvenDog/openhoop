// The reference picture's place in the sewing order: moving it a step at a time (whole groups at once), and keeping
// it between the same objects when objects are added, removed or reordered.
import XCTest
@testable import EmbroideryCore

final class ArtworkLayerTests: XCTestCase {
    private func design(_ names: [String], layer: Int?) -> Design {
        var design = Design()
        design.objects = names.map { RunObject(name: $0, nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))]) }
        design.artwork = Artwork(data: Data([1]), name: "Logo", width: 20, height: 20); design.artwork?.layer = layer
        return design
    }
    private func under(_ design: Design) -> [String] { design.objects.prefix(design.artworkLayer).map(\.name) }

    func testPictureStartsUnderEverythingAndMovesAStepAtATime() {
        var d = design(["A", "B", "C"], layer: nil)
        XCTAssertEqual(d.artworkLayer, 0, "older files and new pictures: under everything")
        d.moveArtwork(by: -1); XCTAssertEqual(d.artworkLayer, 0, "can't go above the top")
        d.moveArtwork(by: 1); d.moveArtwork(by: 1); XCTAssertEqual(under(d), ["A", "B"])
        d.moveArtwork(by: 1); d.moveArtwork(by: 1); XCTAssertEqual(d.artworkLayer, 3, "over everything, and no further")
        d.moveArtwork(by: -1); XCTAssertEqual(under(d), ["A", "B"])
        d.artwork?.layer = 99; XCTAssertEqual(d.artworkLayer, 3, "an out-of-range place is read as the nearest end")
    }

    func testGroupedObjectsCountAsOneStep() {
        var d = design(["A", "W", "o", "r", "d", "B"], layer: 1)
        let word = UUID(); for i in 1...4 { d.objects[i].groupID = word }
        d.moveArtwork(by: 1); XCTAssertEqual(under(d), ["A", "W", "o", "r", "d"], "past the whole word")
        d.moveArtwork(by: -1); XCTAssertEqual(under(d), ["A"], "and back over all of it")
    }

    func testAddingAndRemovingObjectsKeepsItsNeighbours() {
        let start = design(["A", "B", "C", "D"], layer: 2)   // A, B under; C, D over
        var added = start; added.objects.append(RunObject(name: "E", nodes: [])); added.keepArtworkPlace(from: start)
        XCTAssertEqual(under(added), ["A", "B"], "a new object goes on top")
        var removedUnder = start; removedUnder.objects.remove(at: 0); removedUnder.keepArtworkPlace(from: start)
        XCTAssertEqual(under(removedUnder), ["B"], "C doesn't slide under when A goes")
        var removedOver = start; removedOver.objects.remove(at: 2); removedOver.keepArtworkPlace(from: start)
        XCTAssertEqual(under(removedOver), ["A", "B"])
        var copied = start; copied.objects.insert(RunObject(name: "B copy", nodes: []), at: 2); copied.keepArtworkPlace(from: start)
        XCTAssertEqual(under(copied), ["A", "B"], "a copy pasted after B goes on top of the picture")
    }

    func testReorderingPassesThePictureAndUndoPutsItBack() {
        let start = design(["A", "B", "C"], layer: 2)
        var reordered = start; reordered.objects.swapAt(1, 2); reordered.keepArtworkPlace(from: start)
        XCTAssertEqual(under(reordered), ["A", "C"], "C moved earlier past the picture, like a row in the list")
        var removed = start; removed.objects.remove(at: 0); removed.keepArtworkPlace(from: start)
        var undone = start; undone.keepArtworkPlace(from: removed)
        XCTAssertEqual(under(undone), ["A", "B"], "Undo brings back the exact place")
    }
}
