// Lettering envelopes: the four shapes bend the box round a word as their handles say, the letters follow, the
// envelope survives editing the text and scales with the letters, and files with one are saved as version 9.
import XCTest
@testable import EmbroideryCore

final class LetteringEnvelopeTests: XCTestCase {
    private let ink = ThreadColor.palette[0]
    private var embroideryFonts: [EmbroideryFont] { EmbroideryFont.all(in: EmbroideryFontTests.directory) }
    private let low = Point(-20, -5), high = Point(20, 5)

    /// The box round a set of objects' outlines.
    private func box(_ objects: [RunObject]) -> (min: Point, max: Point) {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        return (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
    }
    /// The highest outline point of the objects whose middle lies between `from` and `to` across.
    private func top(_ objects: [RunObject], from: Double, to: Double) -> Double {
        objects.flatMap { $0.outlinePaths.flatMap { $0 } }.filter { $0.x >= from && $0.x <= to }.map(\.y).max()!
    }

    func testAnEnvelopeLeftAsItIsChangesNothing() {
        for kind in EnvelopeKind.allCases {
            var envelope = LetteringEnvelope(kind: kind); envelope.top = [0, 0, 0]; envelope.bottom = [0, 0, 0]
            for p in [Point(-20, -5), Point(3, 1.5), Point(20, 5), Point(-7, 4)] {
                XCTAssertEqual(envelope.warp(p, low: low, high: high, height: 10).distance(to: p), 0, accuracy: 1e-9, kind.title)
            }
        }
    }

    func testEachShapeMovesItsHandlesAndBendsTheEdges() {
        // Bridge: both middles up 3.5 mm (0.35 of a 10 mm letter); the ends stay; the edges curve smoothly between.
        let bridge = LetteringEnvelope(kind: .bridge)
        XCTAssertEqual(bridge.kind.handles.count, 2)
        XCTAssertEqual(bridge.warp(Point(0, 5), low: low, high: high, height: 10).y, 8.5, accuracy: 1e-9)
        XCTAssertEqual(bridge.warp(Point(0, -5), low: low, high: high, height: 10).y, -1.5, accuracy: 1e-9)
        XCTAssertEqual(bridge.warp(Point(-20, 5), low: low, high: high, height: 10).y, 5, accuracy: 1e-9)
        XCTAssertEqual(bridge.warp(Point(-10, 5), low: low, high: high, height: 10).y, 5 + 3.5 * 0.75, accuracy: 1e-9, "Halfway out, a curve is ¾ of the way up")
        // Diamond: the same middles, but straight edges to a point, so halfway out is halfway up.
        var diamond = LetteringEnvelope(kind: .diamond); diamond.top = [0, 0.35, 0]
        XCTAssertEqual(diamond.kind.handles.count, 6)
        XCTAssertEqual(diamond.warp(Point(-10, 5), low: low, high: high, height: 10).y, 5 + 3.5 * 0.5, accuracy: 1e-9)
        // Pennant: the right end's corners move; the edges stay straight, so the word tapers.
        let pennant = LetteringEnvelope(kind: .pennant)
        XCTAssertEqual(pennant.warp(Point(20, 5), low: low, high: high, height: 10), Point(20, 2.5))
        XCTAssertEqual(pennant.warp(Point(20, -5), low: low, high: high, height: 10), Point(20, -2.5))
        XCTAssertEqual(pennant.warp(Point(0, 5), low: low, high: high, height: 10).y, 3.75, accuracy: 1e-9)
        // Perspective: the top corners slide in, so the box's sides lean and a point's height stays put.
        let perspective = LetteringEnvelope(kind: .perspective)
        XCTAssertTrue(perspective.kind.slides)
        XCTAssertEqual(perspective.warp(Point(-20, 5), low: low, high: high, height: 10), Point(-16, 5))
        XCTAssertEqual(perspective.warp(Point(20, 5), low: low, high: high, height: 10), Point(16, 5))
        XCTAssertEqual(perspective.warp(Point(-20, -5), low: low, high: high, height: 10), Point(-20, -5))
        XCTAssertEqual(perspective.warp(Point(-20, 0), low: low, high: high, height: 10), Point(-18, 0))
        // Shift- and ⌘-drags move a partner: across the edges, or (Perspective) the other end of the same edge.
        XCTAssertEqual(EnvelopeKind.bridge.partner(of: EnvelopeHandle(top: true, place: 1)), EnvelopeHandle(top: false, place: 1))
        XCTAssertEqual(EnvelopeKind.perspective.partner(of: EnvelopeHandle(top: true, place: 0)), EnvelopeHandle(top: true, place: 2))
    }

    func testBentMacFontLetteringFollowsTheBridgeAndKeepsItThroughEdits() throws {
        var spec = LetteringSpec(text: "HIHIH", fontKind: .system, font: "Helvetica-Bold", height: 10)
        let plain = try spec.build(color: ink, embroideryFonts: []).objects
        spec.envelope = LetteringEnvelope(kind: .bridge)
        let bent = try spec.build(color: ink, embroideryFonts: []).objects
        let plainBox = box(plain), bentBox = box(bent)
        XCTAssertGreaterThan(top(bent, from: -2, to: 2), top(plain, from: -2, to: 2) + 3, "The middle of the word rises with the top edge")
        XCTAssertEqual(top(bent, from: plainBox.min.x, to: plainBox.min.x + 1), top(plain, from: plainBox.min.x, to: plainBox.min.x + 1), accuracy: 0.6, "The ends stay")
        XCTAssertEqual(bentBox.min.x, plainBox.min.x, accuracy: 0.01)
        XCTAssertEqual(bent[0].lettering?.envelope?.box?.count, 2, "The box it filled is kept for the handles")
        // The long straight sides of the H were cut into pieces so they could bend.
        XCTAssertGreaterThan(bent[0].nodes.count, plain[0].nodes.count)
        var design = Design(); design.objects = bent
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 300)
        XCTAssertTrue(design.needsSchemaNine)
        // Changing the text rebuilds the new word in the same envelope.
        var edited = try XCTUnwrap(bent[0].lettering); edited.text = "HIH"
        let rebuilt = try edited.build(color: ink, embroideryFonts: []).objects
        XCTAssertEqual(rebuilt[0].lettering?.envelope?.kind, .bridge)
        XCTAssertGreaterThan(top(rebuilt, from: -2, to: 2), top(try LetteringSpec(text: "HIH", fontKind: .system, font: "Helvetica-Bold", height: 10).build(color: ink, embroideryFonts: []).objects, from: -2, to: 2) + 3)
        // Arched lettering keeps its envelope but isn't bent by it.
        var arched = edited; arched.shape = .archUp
        let archedObjects = try arched.build(color: ink, embroideryFonts: []).objects
        var plainArch = arched; plainArch.envelope = nil
        XCTAssertEqual(archedObjects.map(\.nodes), try plainArch.build(color: ink, embroideryFonts: []).objects.map(\.nodes))
    }

    func testEnvelopeGrowsWithTheLetters() throws {
        var spec = LetteringSpec(text: "HH", fontKind: .system, font: "Helvetica-Bold", height: 10)
        spec.envelope = LetteringEnvelope(kind: .pennant)
        func taper(_ height: Double) throws -> Double {
            var sized = spec; sized.height = height
            let objects = try sized.build(color: ink, embroideryFonts: []).objects, b = box(objects)
            return (b.max.y - b.min.y) - (top(objects, from: b.max.x - 0.5, to: b.max.x) - objects.flatMap { $0.outlinePaths.flatMap { $0 } }.filter { $0.x >= b.max.x - 0.5 }.map(\.y).min()!)
        }
        XCTAssertEqual(try taper(20), try taper(10) * 2, accuracy: 0.3, "The right end tapers by the same share of a bigger word")
    }

    func testEmbroideryFontSatinsBendAndStillSew() throws {
        for kind in EnvelopeKind.allCases {
            var spec = LetteringSpec(text: "OPEN", fontKind: .embroidery, font: "small_font", height: 10)
            spec.envelope = LetteringEnvelope(kind: kind)
            let objects = try spec.build(color: ink, embroideryFonts: embroideryFonts).objects
            XCTAssertTrue(objects.contains { $0.kind == .satin })
            var design = Design(); design.objects = objects
            XCTAssertNoThrow(try design.validate())
            let plan = try StitchEngine.compile(design)
            XCTAssertGreaterThan(plan.stitchCount, 300, kind.title)
        }
    }

    func testCuttingIntoPiecesKeepsTheShape() {
        var fill = RunObject(name: "Bar", nodes: [Point(0, 0), Point(10, 0), Point(10, 2), Point(0, 2)].map { PathNode($0) })
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        let cut = fill.cutIntoPieces(1)
        XCTAssertEqual(cut.nodes.count, 10 + 2 + 10 + 2)
        XCTAssertTrue(cut.nodes.allSatisfy { $0.point.y == 0 || $0.point.y == 2 || $0.point.x == 0 || $0.point.x == 10 }, "Every new point lies on the old edges")
        var satin = RunObject(name: "Column", nodes: [Point(0, 0), Point(0, 3), Point(6, 0), Point(6, 3)].map { PathNode($0) })
        satin.digitizing = DigitizingSettings(kind: .satin)
        let column = satin.cutIntoPieces(1.5)
        XCTAssertEqual(column.nodes.count, 10, "Three new pairs across the column")
        XCTAssertEqual(column.nodes[2].point, Point(1.5, 0)); XCTAssertEqual(column.nodes[3].point, Point(1.5, 3))
    }

    func testBendingTooFarIsRefusedAndBadFilesAreRejected() throws {
        var spec = LetteringSpec(text: "HI", fontKind: .system, font: "Helvetica-Bold", height: 10)
        var envelope = LetteringEnvelope(kind: .bridge); envelope.top = [0, -1.2, 0]; envelope.bottom = [0, 0, 0]
        spec.envelope = envelope
        XCTAssertThrowsError(try spec.build(color: ink, embroideryFonts: []), "The top would come down through the bottom")
        spec.envelope = LetteringEnvelope(kind: .diamond)
        var design = Design(); design.objects = try spec.build(color: ink, embroideryFonts: []).objects
        XCTAssertNoThrow(try design.validate())
        design.objects[0].lettering?.envelope?.top = [0, 9, 0]
        XCTAssertThrowsError(try design.validate())
        design.objects[0].lettering?.envelope?.top = [0, .nan, 0]
        XCTAssertThrowsError(try design.validate())
        var plain = Design(); plain.objects = try LetteringSpec(text: "HI", fontKind: .system, font: "Helvetica-Bold", height: 10).build(color: ink, embroideryFonts: []).objects
        XCTAssertFalse(plain.needsSchemaNine)
    }
}
