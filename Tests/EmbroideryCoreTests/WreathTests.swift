// Wreath and kaleidoscope: copies placed round a center, mirrored in pairs for a kaleidoscope, grouped, and sewn in
// color blocks so the copies add no thread changes.
import XCTest
@testable import EmbroideryCore

final class WreathTests: XCTestCase {
    private let green = ThreadColor.palette[2], red = ThreadColor.palette[0]

    /// A small fill shaped like an L (so a mirror image looks different from a turned one), with its corner at `corner`.
    private func ell(_ name: String, at corner: Point, color: ThreadColor) -> RunObject {
        var object = RunObject(name: name, nodes: [Point(0, 0), Point(6, 0), Point(6, 2), Point(2, 2), Point(2, 8), Point(0, 8)].map { PathNode(corner + $0) }, color: color)
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill); object.digitizing?.angle = 30
        return object
    }
    /// The middle of an object's outline points.
    private func middle(_ object: RunObject) -> Point {
        let points = object.nodes.map(\.point)
        return points.reduce(Point(0, 0), +) * (1 / Double(points.count))
    }
    /// Signed area of an object's outline: positive counterclockwise. Mirroring flips the sign; turning doesn't.
    private func turning(_ object: RunObject) -> Double { AreaGeometry.area(object.nodes.map(\.point)) }

    func testCopiesGoEvenlyRoundTheCenterAndTurnTheirRows() throws {
        var design = Design()
        design.objects = [ell("Leaf", at: Point(20, 0), color: green)]
        let original = design.objects[0]
        let ids = try design.wreath([original.id], copies: 4, around: Point(0, 0), mirrored: false)
        XCTAssertEqual(ids.count, 4); XCTAssertEqual(design.objects.count, 4)
        XCTAssertEqual(ids[0], original.id, "The original stays, as the first copy")
        XCTAssertEqual(Set(ids).count, 4, "Every copy has its own id")
        let start = middle(original)
        for (k, id) in ids.enumerated() {
            let copy = try XCTUnwrap(design.objects.first { $0.id == id })
            let expected = AreaGeometry.rotate(start, degrees: Double(k) * 90)
            XCTAssertEqual(middle(copy).distance(to: expected), 0, accuracy: 1e-9, "Copy \(k + 1) sits a quarter turn further round")
            XCTAssertEqual(copy.settings.angle, Lettering.turned(30, by: Double(k) * 90), accuracy: 1e-9, "Its fill rows turn with it")
            XCTAssertEqual(turning(copy), turning(original), accuracy: 1e-9, "Turned, not mirrored")
        }
        XCTAssertEqual(design.objects[1].name, "Leaf 2")
        XCTAssertEqual(Set(design.objects.map(\.groupID)).count, 1, "The wreath is one group")
        XCTAssertNotNil(design.objects[0].groupID)
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100)
    }

    func testKaleidoscopeMirrorsEveryOtherCopyIntoPairs() throws {
        var design = Design()
        design.objects = [ell("Leaf", at: Point(20, 0), color: green)]
        let original = design.objects[0]
        let ids = try design.wreath([original.id], copies: 6, around: Point(0, 0), mirrored: true)
        let copies = try ids.map { id in try XCTUnwrap(design.objects.first { $0.id == id }) }
        // Seen from the center, the L's box sits at some angle; the mirror line is half a step (30°) further round.
        var alone = Design(); alone.objects = [original]
        let box = try XCTUnwrap(alone.bounds(of: [original.id]))
        let sitting = atan2((box.min.y + box.max.y) / 2, (box.min.x + box.max.x) / 2) * 180 / .pi, line = sitting + 30
        func reflected(_ p: Point) -> Point { AreaGeometry.rotate(Point(p.x, -p.y), degrees: 2 * line) }
        for (k, copy) in copies.enumerated() {
            XCTAssertEqual(turning(copy), k % 2 == 0 ? turning(original) : -turning(original), accuracy: 1e-9, "Copy \(k + 1) is \(k % 2 == 0 ? "turned" : "mirrored")")
            // Even copies: the original turned k × 60°. Odd ones: the original mirrored across the line, then turned (k − 1) × 60°.
            for (a, b) in zip(copy.nodes, original.nodes) {
                let expected = k % 2 == 0 ? AreaGeometry.rotate(b.point, degrees: Double(k) * 60) : AreaGeometry.rotate(reflected(b.point), degrees: Double(k - 1) * 60)
                XCTAssertEqual(a.point.distance(to: expected), 0, accuracy: 1e-9, "Copy \(k + 1)")
            }
        }
        XCTAssertEqual(copies[1].settings.angle, Lettering.turned(-30, by: 2 * line), accuracy: 1e-9)
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100)
    }

    func testCopiesSewInColorBlocksSoThreadChangesDontMultiply() throws {
        // Green leaf, red flower on top of it, then a green stem: three runs of color.
        var design = Design()
        design.objects = [ell("Leaf", at: Point(20, 0), color: green), ell("Flower", at: Point(22, 1), color: red), ell("Stem", at: Point(18, -3), color: green)]
        let others = ell("Elsewhere", at: Point(-40, -40), color: red)
        design.objects.insert(others, at: 0)
        let ids = try design.wreath(Set(design.objects.dropFirst().map(\.id)), copies: 3, around: Point(0, 0), mirrored: false)
        XCTAssertEqual(design.objects.first?.id, others.id, "Objects before the wreath keep their place")
        XCTAssertEqual(design.objects.dropFirst().map(\.id), ids, "The wreath sews where its first object did")
        let names = design.objects.dropFirst().map(\.name)
        XCTAssertEqual(names, ["Leaf", "Leaf 2", "Leaf 3", "Flower", "Flower 2", "Flower 3", "Stem", "Stem 2", "Stem 3"],
                       "Each color run is sewn round the whole circle before the next, keeping what lay on top")
        let threadChanges = zip(design.objects.dropFirst(), design.objects.dropFirst(2)).filter { $0.color != $1.color }.count
        XCTAssertEqual(threadChanges, 2, "No more thread changes than the three originals had")
    }

    func testCopiedLetteringAndBranchesStaySeparateAndLockedObjectsStayOut() throws {
        let spec = LetteringSpec(text: "Hi", fontKind: .system, font: "Helvetica-Bold", height: 8)
        var letters = try spec.build(color: red, embroideryFonts: []).objects
        for i in letters.indices { letters[i].transform { $0 + Point(15, 0) } }
        var a = ell("A", at: Point(20, 10), color: green), b = ell("B", at: Point(24, 10), color: green)
        let branch = UUID(); a.branchID = branch; b.branchID = branch
        var locked = ell("Locked", at: Point(30, 30), color: green); locked.locked = true
        var design = Design(); design.objects = letters + [a, b, locked]
        let ids = try design.wreath(Set(design.objects.map(\.id)), copies: 2, around: Point(0, 0), mirrored: false)
        XCTAssertEqual(ids.count, (letters.count + 2) * 2)
        XCTAssertEqual(design.objects.filter { $0.name == "Locked" }.count, 1, "A locked object isn't copied")
        XCTAssertNil(design.objects.first { $0.name == "Locked" }?.groupID, "and isn't put in the wreath")
        let wreath = design.objects.filter { ids.contains($0.id) }
        XCTAssertEqual(Set(wreath.compactMap(\.lettering?.id)).count, 2, "The copied word is its own lettering")
        XCTAssertEqual(Set(wreath.compactMap(\.branchID)).count, 2, "The copied branch is its own branch")
        // Each lettering's letters and each branch's objects still sew one after another.
        for key in Set(wreath.compactMap { $0.lettering?.id.uuidString } + wreath.compactMap { $0.branchID?.uuidString }) {
            let places = design.objects.indices.filter { design.objects[$0].lettering?.id.uuidString == key || design.objects[$0].branchID?.uuidString == key }
            XCTAssertEqual(places, Array(places.first!...places.last!))
        }
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100)
    }

    func testRefusesBadCounts() {
        var design = Design(); design.objects = [ell("Leaf", at: Point(20, 0), color: green)]
        let id = design.objects[0].id
        XCTAssertThrowsError(try design.wreath([id], copies: 1, around: Point(0, 0), mirrored: false))
        XCTAssertThrowsError(try design.wreath([id], copies: 101, around: Point(0, 0), mirrored: false))
        XCTAssertThrowsError(try design.wreath([id], copies: 5, around: Point(0, 0), mirrored: true), "A kaleidoscope needs an even count")
        XCTAssertThrowsError(try design.wreath([], copies: 4, around: Point(0, 0), mirrored: false))
        XCTAssertEqual(design.objects.count, 1, "Nothing changes when refused")
    }
}
