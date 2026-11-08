// Groups inside groups: grouping whole groups wraps them in a new group around them, so Ungroup takes off one layer
// at a time and gives the inner groups back. An object's own group (groupID, which lettering, monograms and the like
// use to find their parts) stays the innermost; the groups around it are its outerGroups. What a click selects and
// what moves together is the outermost group. A project with groups inside groups is file version 23.
import XCTest
@testable import EmbroideryCore

final class NestedGroupTests: XCTestCase {
    private func square(_ name: String, _ x: Double) -> RunObject {
        var object = RunObject(name: name, nodes: ShapeGeometry.nodes(.rectangle, in: (Point(x, 0), Point(x + 5, 5))))
        object.closed = true; object.digitizing = DigitizingSettings(kind: .fill)
        return object
    }
    /// Four squares: a and b grouped, c and d grouped.
    private func twoGroups() -> Design {
        var design = Design()
        design.objects = ["a", "b", "c", "d"].enumerated().map { square($1, Double($0) * 10) }
        let ids = design.objects.map(\.id)
        design.groupObjects([ids[0], ids[1]]); design.groupObjects([ids[2], ids[3]])
        return design
    }

    func testGroupingGroupsWrapsThemAndUngroupUnwrapsOneLayer() throws {
        var design = twoGroups()
        let ids = design.objects.map(\.id), inner = design.objects.map(\.groupID)
        XCTAssertEqual(design.groupMembers(of: ids[0]), [ids[0], ids[1]])
        XCTAssertFalse(design.needsSchemaTwentyThree, "plain groups are nothing new")
        design.groupObjects(Set(ids))
        XCTAssertEqual(design.groupMembers(of: ids[0]), Set(ids), "a click selects the whole outer group")
        XCTAssertEqual(design.objects.map(\.groupID), inner, "each keeps its own group")
        XCTAssertEqual(Set(design.objects.compactMap(\.topGroup)).count, 1)
        XCTAssertTrue(design.needsSchemaTwentyThree)
        XCTAssertEqual(design.groupLevels(of: ids[2]), [Set(ids), [ids[2], ids[3]], [ids[2]]], "outer group, its inner group, the object")
        // Ungroup takes off the outer layer only: the two inner groups come back.
        XCTAssertTrue(design.ungroupObjects([ids[0]]).ungrouped)
        XCTAssertEqual(design.groupMembers(of: ids[0]), [ids[0], ids[1]])
        XCTAssertEqual(design.groupMembers(of: ids[3]), [ids[2], ids[3]])
        XCTAssertFalse(design.needsSchemaTwentyThree)
        XCTAssertTrue(design.objects.allSatisfy { $0.outerGroups == nil })
    }

    func testThreeLevelsDeep() throws {
        var design = twoGroups()
        let ids = design.objects.map(\.id)
        design.groupObjects([ids[0], ids[1], ids[2], ids[3]])
        var loose = square("e", 50); loose.id = UUID()
        design.objects.append(loose)
        design.groupObjects(Set(ids + [loose.id]))
        XCTAssertEqual(design.groupLevels(of: ids[1]).count, 4, "outermost, middle, inner group, the object")
        XCTAssertEqual(design.groupLevels(of: loose.id), [Set(ids + [loose.id]), [loose.id]], "the loose square joined directly")
        _ = design.ungroupObjects([loose.id])
        XCTAssertEqual(design.groupMembers(of: loose.id), [loose.id])
        XCTAssertEqual(design.groupMembers(of: ids[0]), Set(ids), "the middle layer is the outermost now")
    }

    func testGroupingPartOfAGroupTakesItOut() throws {
        var design = twoGroups()
        let ids = design.objects.map(\.id)
        // Only a (not b) with c and d: a leaves its group; c and d's whole group is wrapped.
        design.groupObjects([ids[0], ids[2], ids[3]])
        XCTAssertEqual(design.groupMembers(of: ids[1]), [ids[1]], "b is on its own now")
        XCTAssertEqual(design.groupMembers(of: ids[0]), [ids[0], ids[2], ids[3]])
        XCTAssertEqual(design.groupLevels(of: ids[2]), [[ids[0], ids[2], ids[3]], [ids[2], ids[3]], [ids[2]]])
        XCTAssertEqual(design.groupLevels(of: ids[0]), [[ids[0], ids[2], ids[3]], [ids[0]]])
    }

    func testANestedGroupStaysTogetherInTheSewingOrderAndCopiesKeepTheirLayers() throws {
        var design = twoGroups()
        let ids = design.objects.map(\.id)
        design.groupObjects(Set(ids))
        // The sewing order keeps the whole outer group together: one run, never split; arranging moves it as one.
        design.objects.append(square("loose", 60))
        XCTAssertEqual(design.sewingUnits, [0..<4, 4..<5])
        XCTAssertEqual(design.arrangeUnits(ids).count, 1)
        let originals = design.objects
        let pasted = Set(design.paste(design.copying(Set(ids))))   // (the four squares, not the loose one)
        let copies = design.objects.filter { pasted.contains($0.id) }
        XCTAssertEqual(Set(copies.compactMap(\.topGroup)).count, 1, "the copies share one outer group")
        XCTAssertNotEqual(copies[0].topGroup, originals[0].topGroup, "a new one")
        XCTAssertEqual(Set(copies.compactMap(\.groupID)).count, 2, "and two inner groups")
        XCTAssertTrue(Set(copies.compactMap(\.groupID)).isDisjoint(with: Set(originals.compactMap(\.groupID))))
    }

    func testFileVersion23() throws {
        var design = twoGroups()
        let ids = design.objects.map(\.id)
        design.groupObjects(Set(ids))
        design.schemaVersion = 23
        XCTAssertNoThrow(try design.validate())
        let saved = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(saved.objects.map(\.outerGroups), design.objects.map(\.outerGroups))
        design.objects[0].groupID = nil
        XCTAssertThrowsError(try design.validate(), "an object in outer groups has a group of its own")
    }
}
