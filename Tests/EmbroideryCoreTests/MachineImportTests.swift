import XCTest
@testable import EmbroideryCore

final class MachineImportTests:XCTestCase {
    func fixture()->StitchPlan {
        var plan=StitchPlan();plan.threads=[.palette[0],.palette[1]]
        plan.commands=[.init(.jump,Point(-10,5),thread:0),.init(.stitch,Point(-10,5),thread:0),.init(.stitch,Point(-7,8),thread:0),.init(.trim,Point(-7,8),thread:0),.init(.colorChange,Point(-7,8),thread:1),.init(.jump,Point(3,-4),thread:1),.init(.stitch,Point(3,-4),thread:1),.init(.stop,Point(3,-4),thread:1),.init(.stitch,Point(4,-3),thread:1),.init(.end,Point(4,-3),thread:1)]
        return plan
    }
    func imported(_ plan:StitchPlan)throws->Design {
        var design=Design();design.objects=try MachineImport.objects(from:plan,format:"pes",name:"Fixture");return design
    }
    func testRawImportDoesNotResampleOrAddTies()throws {
        let source=fixture(),design=try imported(source),result=try StitchEngine.compile(design)
        XCTAssertEqual(design.objects.count,2);XCTAssertTrue(design.objects.allSatisfy{$0.kind == .raw && !$0.tieIn && !$0.tieOut})
        XCTAssertEqual(result.commands.filter{$0.op == .stitch}.map(\.point),source.commands.filter{$0.op == .stitch}.map(\.point))
        XCTAssertEqual(result.commands.dropFirst().map(\.op),source.commands.map(\.op)) // one source-origin anchor
        XCTAssertEqual(result.threads,source.threads)
    }
    func testTransformIncludesStartAndEveryControlWithoutChangingOps()throws {
        var design=try imported(fixture());let original=design.objects[1].rawStitches!
        design.objects[1].transform{Point(-$0.y+2,$0.x-3)}
        let transformed=design.objects[1].rawStitches!
        XCTAssertEqual(transformed.start,Point(-original.start.y+2,original.start.x-3))
        XCTAssertEqual(transformed.commands.map(\.op),original.commands.map(\.op))
        XCTAssertEqual(transformed.commands.map(\.point),original.commands.map{Point(-$0.point.y+2,$0.point.x-3)})
        try design.validate();XCTAssertEqual(try StitchEngine.compile(design).stitchCount,4)
    }
    func testRecolorDoesNotRegenerateStitches()throws {
        var design=try imported(fixture());design.objects[1].color = .palette[5]
        let plan=try StitchEngine.compile(design)
        XCTAssertEqual(plan.stitchCount,4);XCTAssertEqual(plan.threads.last,.palette[5])
    }
    func testRepeatedSameColorAndEmptyBlocksKeepBoundaries()throws {
        var source=fixture();source.threads[1]=source.threads[0]
        source.commands.insert(.init(.colorChange,Point(-7,8),thread:1),at:5)
        let design=try imported(source),plan=try StitchEngine.compile(design)
        XCTAssertEqual(design.objects.count,3)
        XCTAssertTrue(design.objects[1].rawStitches!.commands.isEmpty)
        XCTAssertEqual(plan.commands.filter{$0.op == .colorChange}.count,2)
        XCTAssertEqual(plan.stitchCount,4)
    }
    func testCombinationAnchorsRawBlockInsteadOfSewingAcrossGap()throws {
        var design=try imported(fixture())
        var run=RunObject(name:"Run",nodes:[PathNode(Point(20,20)),PathNode(Point(25,20))]);run.tieIn=false;run.tieOut=false
        design.objects.insert(run,at:0)
        let plan=try StitchEngine.compile(design),id=design.objects[1].id
        let raw=plan.commands.filter{$0.objectID==id}
        XCTAssertEqual(raw.first?.op,.jump);XCTAssertEqual(raw.first?.point,Point(0,0))
        XCTAssertEqual(raw.filter{$0.op == .stitch}.map(\.point),[Point(-10,5),Point(-7,8)])
    }
    func testLongImportedStitchIsReportedAndRetained()throws {
        var plan=StitchPlan();plan.threads=[.palette[0]];plan.commands=[.init(.stitch,Point(20,0),thread:0),.init(.end,Point(20,0),thread:0)]
        let compiled=try StitchEngine.compile(imported(plan))
        XCTAssertEqual(compiled.stitchCount,1);XCTAssertTrue(compiled.warnings.contains{$0.contains("exceed 10 mm")})
    }
    func testRawProjectRoundTripAndOutlineSeparation()throws {
        let design=try imported(fixture()),data=try JSONEncoder().encode(design)
        let loaded=try JSONDecoder().decode(Design.self,from:data);try loaded.validate()
        XCTAssertEqual(loaded,design)
        XCTAssertEqual(loaded.objects[0].outlinePaths,[[Point(-10,5),Point(-10,5),Point(-7,8)]])
        XCTAssertEqual(loaded.objects[0].runningOutlines(),[loaded.objects[0]])
    }
    func testMalformedPlansAndControlsAreRejected() {
        var p=fixture();p.commands[0].thread=99;XCTAssertThrowsError(try imported(p))
        p=fixture();p.commands.removeLast();XCTAssertThrowsError(try imported(p))
        p=fixture();p.commands[1].thread=1;XCTAssertThrowsError(try imported(p))
        p=fixture();p.commands[3].point=Point(99,99);XCTAssertThrowsError(try imported(p))
        p=fixture();p.threads[0].hex = -1;XCTAssertThrowsError(try imported(p))
    }
    func testCorruptRawBlockCannotHideUnsupportedControlsOrGeometry()throws {
        var design=try imported(fixture());design.objects[0].rawStitches!.commands.append(RawStitch(.end,Point(0,0)))
        XCTAssertThrowsError(try design.validate())
        design=try imported(fixture());design.objects[0].nodes=[PathNode(Point(0,0))];XCTAssertThrowsError(try design.validate())
        design=try imported(fixture());design.objects[0].tieIn=true;XCTAssertThrowsError(try design.validate())
    }
    func testReorderingLaterRawBlockFirstOmitsLeadingColorChange()throws {
        var design=try imported(fixture());design.objects.reverse()
        let plan=try StitchEngine.compile(design)
        XCTAssertEqual(plan.commands.first?.op,.jump)
        XCTAssertEqual(plan.commands.first?.point,design.objects[0].rawStitches?.start)
        XCTAssertEqual(plan.commands.filter{$0.op == .stitch}.map(\.point),[Point(3,-4),Point(4,-3),Point(-10,5),Point(-7,8)])
        XCTAssertEqual(plan.commands.filter{$0.op == .colorChange}.count,1)
    }

}
