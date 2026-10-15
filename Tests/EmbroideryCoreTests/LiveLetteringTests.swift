// Live lettering: text on an arc, and letters that remember their recipe so the text can be edited in place.
import XCTest
@testable import EmbroideryCore

final class LiveLetteringTests: XCTestCase {
    private let ink = ThreadColor.palette[0]
    private var embroideryFonts: [EmbroideryFont] { EmbroideryFont.all(in: EmbroideryFontTests.directory) }

    /// The average of a letter's outline points: a stand-in for where the letter sits.
    private func middle(_ object: RunObject) -> Point {
        let points = object.outlinePaths.flatMap { $0 }
        return points.reduce(Point(0, 0), +) * (1 / Double(points.count))
    }
    private func box(_ objects: [RunObject]) -> (min: Point, max: Point) {
        let points = objects.flatMap { $0.outlinePaths.flatMap { $0 } }
        return (Point(points.map(\.x).min()!, points.map(\.y).min()!), Point(points.map(\.x).max()!, points.map(\.y).max()!))
    }

    func testArchedLettersSitOnACircle() throws {
        for shape in [LetteringShape.archUp, .archDown] {
            let letters = try Lettering.shapes(text: "HHHHH", fontName: "Helvetica", height: 10, stitch: .fill, color: ink, shape: shape, radius: 40).objects
            XCTAssertEqual(letters.count, 5)
            let middles = letters.map(middle)
            // Every letter is turned whole, so all five middles are the same distance from the circle's center,
            // which lies on the vertical center line (x = 0), below the letters for arch up and above for arch down.
            let a = middles[0], c = middles[2]
            // Solve |a − (0, y)| = |c − (0, y)| for the center's height y.
            let y = (a.x * a.x + a.y * a.y - c.x * c.x - c.y * c.y) / (2 * (a.y - c.y))
            let distances = middles.map { $0.distance(to: Point(0, y)) }
            for d in distances { XCTAssertEqual(d, distances[0], accuracy: 0.05, "\(shape)") }
            if shape == .archUp { XCTAssertLessThan(y, c.y); XCTAssertGreaterThan(c.y, a.y, "The middle letter is highest") }
            else { XCTAssertGreaterThan(y, c.y); XCTAssertLessThan(c.y, a.y, "The middle letter is lowest") }
            // Fill rows turn with each letter: the outer letters' rows differ from the middle one's.
            XCTAssertGreaterThan(abs(Lettering.turned(letters[0].settings.angle, by: -letters[2].settings.angle)), 10)
            XCTAssertEqual(abs(Lettering.turned(letters[0].settings.angle, by: -letters[2].settings.angle)), abs(Lettering.turned(letters[4].settings.angle, by: -letters[2].settings.angle)), accuracy: 0.5)
        }
        // Straight lettering keeps every letter level.
        let straight = try Lettering.shapes(text: "HHH", fontName: "Helvetica", height: 10, stitch: .fill, color: ink).objects
        XCTAssertEqual(middle(straight[0]).y, middle(straight[2]).y, accuracy: 0.001)
        XCTAssertEqual(straight[0].settings.angle, straight[2].settings.angle)
    }

    func testArcsThatDoNotFitAreExplained() {
        XCTAssertThrowsError(try Lettering.shapes(text: "A long line of text", fontName: "Helvetica", height: 10, stitch: .fill, color: ink, shape: .archUp, radius: 15)) { error in
            XCTAssertTrue(error.localizedDescription.contains("too long"), error.localizedDescription)
        }
        XCTAssertThrowsError(try Lettering.shapes(text: "Hi", fontName: "Helvetica", height: 20, stitch: .fill, color: ink, shape: .archDown, radius: 20)) { error in
            XCTAssertTrue(error.localizedDescription.contains("too tight"), error.localizedDescription)
        }
    }

    func testEmbroideryFontsArchAndSew() throws {
        let spec = LetteringSpec(text: "BADGE", fontKind: .embroidery, font: "small_font", height: 8, shape: .archUp, radius: 30)
        let result = try spec.build(color: ink, embroideryFonts: embroideryFonts)
        XCTAssertTrue(result.objects.contains { $0.kind == .satin })
        var design = Design(); design.objects = result.objects
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 200)
        // The outer letters sit lower than the middle one.
        let middles = result.objects.map(middle)
        XCTAssertGreaterThan(middles[middles.count / 2].y, middles[0].y + 2)
    }

    func testRebuiltLetteringKeepsItsPlaceAndAngle() throws {
        let spec = LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica-Bold", height: 12)
        var letters = try spec.build(color: ink, embroideryFonts: []).objects
        XCTAssertTrue(letters.allSatisfy { $0.lettering == spec })
        // Turn the letters a quarter turn to the left and move them, as the rotate and nudge commands do.
        for i in letters.indices { letters[i].transform { p in Point(-p.y, p.x) + Point(20, -5) } }
        let moved = letters[0].lettering!
        XCTAssertEqual(moved.anchor, Point(20, -5))
        // Edit the text: the longer word is built in the same spot, still turned, so it's taller than wide.
        var edited = moved; edited.text = "Hello there"
        let rebuilt = try edited.build(color: ink, embroideryFonts: []).objects
        let (low, high) = box(rebuilt)
        XCTAssertEqual((low.x + high.x) / 2, 20, accuracy: 0.01); XCTAssertEqual((low.y + high.y) / 2, -5, accuracy: 0.01)
        XCTAssertGreaterThan(high.y - low.y, 3 * (high.x - low.x))
        // Fill rows turned with the letters (45° becomes 135°).
        XCTAssertEqual(rebuilt[0].settings.angle, 135, accuracy: 0.001)
    }

    func testMirroredLetteringStaysMirrored() throws {
        let spec = LetteringSpec(text: "R", fontKind: .system, font: "Helvetica-Bold", height: 12)
        var letters = try spec.build(color: ink, embroideryFonts: []).objects
        // Mirror left to right, as the Mirror command does (it also reflects fill rows).
        for i in letters.indices { letters[i].transform { Point(-$0.x, $0.y) }; let angle = letters[i].settings.angle; letters[i].digitizing?.angle = 180 - angle }
        let mirrored = letters[0].lettering!
        XCTAssertTrue(mirrored.matchesFreshBuild(letters, embroideryFonts: []), "Rebuilding reproduces the mirrored letter")
    }

    func testHandEditsAreNoticed() throws {
        let spec = LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica-Bold", height: 12)
        var letters = try spec.build(color: ink, embroideryFonts: []).objects
        // Turn right a quarter turn (fill rows too, as the Rotate command does), move and recolor.
        for i in letters.indices {
            letters[i].transform { p in Point(p.y, -p.x) + Point(3, 4) }
            let angle = letters[i].settings.angle; letters[i].digitizing?.angle = angle - 90; letters[i].color = .palette[3]
        }
        XCTAssertTrue(letters[0].lettering!.matchesFreshBuild(letters, embroideryFonts: []), "Moving, turning and recoloring aren't hand edits")
        var reshaped = letters; reshaped[0].nodes[0].point = reshaped[0].nodes[0].point + Point(0.5, 0)
        XCTAssertFalse(letters[0].lettering!.matchesFreshBuild(reshaped, embroideryFonts: []))
        var denser = letters; denser[1].digitizing?.spacing = 0.3
        XCTAssertFalse(letters[0].lettering!.matchesFreshBuild(denser, embroideryFonts: []))
        XCTAssertFalse(letters[0].lettering!.matchesFreshBuild(Array(letters.dropLast()), embroideryFonts: []))
    }

    func testResizedLetteringReportsItsNewHeight() throws {
        var spec = LetteringSpec(text: "H", fontKind: .system, font: "Helvetica", height: 10)
        spec.transform { $0 * 1.5 }
        XCTAssertEqual(spec.currentHeight, 15)
    }

    func testReplacingKeepsTheSewingOrderAndGroup() throws {
        let spec = LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica-Bold", height: 12)
        var design = Design()
        let before = RunObject(name: "Before", nodes: [PathNode(Point(0, 0)), PathNode(Point(10, 0))], color: ink)
        let after = RunObject(name: "After", nodes: [PathNode(Point(0, 5)), PathNode(Point(10, 5))], color: ink)
        design.objects = [before] + (try spec.build(color: ink, embroideryFonts: []).objects) + [after]
        let group = UUID()
        for i in design.objects.indices { design.objects[i].groupID = group }   // grouped with the lines around it
        var edited = spec; edited.text = "Hey"
        let ids = design.replaceLettering(spec.id, with: try edited.build(color: ink, embroideryFonts: []))
        XCTAssertEqual(design.objects.first?.name, "Before"); XCTAssertEqual(design.objects.last?.name, "After")
        XCTAssertEqual(Array(design.objects.dropFirst().dropLast().map(\.id)), ids)
        XCTAssertEqual(design.letteringObjects(spec.id).map(\.name), ["Letter H", "Letter e", "Letter y"])
        XCTAssertTrue(design.objects.allSatisfy { $0.groupID == group })
    }

    /// The bounds of the objects named "Letter <character>", in line order.
    private func letters(_ character: String, in objects: [RunObject]) -> [(min: Point, max: Point)] {
        objects.filter { $0.name == "Letter \(character)" }.map { box([$0]) }
    }

    func testLinesStackOnTheirBaselines() throws {
        var spec = LetteringSpec(text: "Hg\nHb", fontKind: .system, font: "Helvetica-Bold", height: 10)
        let objects = try spec.build(color: ink, embroideryFonts: []).objects
        let h = letters("H", in: objects)
        XCTAssertEqual(h.count, 2)
        // The second line's baseline is 1.4 × 10 mm lower, even though only the first line has a descender (g).
        XCTAssertEqual(h[0].min.y - h[1].min.y, 14, accuracy: 0.01)
        XCTAssertEqual(h[0].min.x, h[1].min.x, accuracy: 0.6, "Centered lines of similar width start in about the same place")
        XCTAssertEqual(Set(objects.map(\.groupID)).count, 1, "All lines are one group")
        // A blank line adds a line's worth of space; custom spacing is used.
        spec.text = "H\n\nH"; spec.lineSpacing = 2
        let spaced = letters("H", in: try spec.build(color: ink, embroideryFonts: []).objects)
        XCTAssertEqual(spaced[0].min.y - spaced[1].min.y, 40, accuracy: 0.01)
        // Blank lines at the start or end are ignored.
        spec.text = "\nH\n"; XCTAssertEqual(spec.lines, ["H"])
    }

    func testLinesLineUpLeftCenterOrRight() throws {
        var spec = LetteringSpec(text: "H\nHHHH", fontKind: .system, font: "Helvetica-Bold", height: 10)
        for alignment in LetteringAlignment.allCases {
            spec.alignment = alignment
            let h = letters("H", in: try spec.build(color: ink, embroideryFonts: []).objects)
            let short = h[0], long = h[1...].reduce((min: h[1].min, max: h[1].max)) { (Point(min($0.min.x, $1.min.x), 0), Point(max($0.max.x, $1.max.x), 0)) }
            switch alignment {
            case .left: XCTAssertEqual(short.min.x, long.min.x, accuracy: 0.01)
            case .right: XCTAssertEqual(short.max.x, long.max.x, accuracy: 0.01)
            case .center: XCTAssertEqual(short.min.x + short.max.x, long.min.x + long.max.x, accuracy: 0.01)
            }
        }
    }

    func testMultiLineEmbroideryFontSewsAndRebuilds() throws {
        let spec = LetteringSpec(text: "TEAM\nCAPTAIN", fontKind: .embroidery, font: "small_font", height: 8)
        let result = try spec.build(color: ink, embroideryFonts: embroideryFonts)
        XCTAssertGreaterThan(result.height, 8 * 1.4 + 7)
        var design = Design(); design.objects = result.objects
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 300)
        XCTAssertTrue(spec.matchesFreshBuild(result.objects, embroideryFonts: embroideryFonts))
        // The first line sews before the second.
        XCTAssertTrue(result.objects.first!.name.hasPrefix("Letter T")); XCTAssertTrue(result.objects.last!.name.hasPrefix("Letter N"))
    }

    func testCurvesAndTooManyLinesAreExplained() {
        var spec = LetteringSpec(text: "One\nTwo", fontKind: .system, font: "Helvetica", height: 10, shape: .archUp)
        XCTAssertThrowsError(try spec.build(color: ink, embroideryFonts: [])) { XCTAssertTrue($0.localizedDescription.contains("one line"), $0.localizedDescription) }
        spec.shape = .straight; spec.text = Array(repeating: "A", count: 11).joined(separator: "\n")
        XCTAssertThrowsError(try spec.build(color: ink, embroideryFonts: [])) { XCTAssertTrue($0.localizedDescription.contains("10 lines"), $0.localizedDescription) }
    }

    func testLetteringIsSavedWithTheProject() throws {
        var design = Design()
        design.objects = try LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica", height: 12, shape: .archDown, radius: 50).build(color: ink, embroideryFonts: []).objects
        let reopened = try JSONDecoder().decode(Design.self, from: try JSONEncoder().encode(design))
        XCTAssertEqual(reopened.objects.map(\.lettering), design.objects.map(\.lettering))
        XCTAssertEqual(reopened.objects.first?.lettering?.shape, .archDown)
    }
}
