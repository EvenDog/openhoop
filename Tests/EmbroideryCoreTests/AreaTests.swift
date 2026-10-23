import XCTest
@testable import EmbroideryCore

final class AreaTests:XCTestCase {
    func rectangle(_ width:Double=30,_ height:Double=20)->RunObject {
        var o=RunObject(name:"Fill",nodes:[Point(0,0),Point(width,0),Point(width,height),Point(0,height)].map{PathNode($0)})
        o.digitizing=DigitizingSettings(kind:.fill);o.digitizing?.expansion=0;o.digitizing?.angle=0;o.digitizing?.underlay = .none;o.stitchLength=3;return o
    }
    func satin(_ width:Double=4)->RunObject {
        var o=RunObject(name:"Satin",nodes:[Point(0,0),Point(width,0),Point(0,20),Point(width,20)].map{PathNode($0)})
        o.digitizing=DigitizingSettings(kind:.satin);return o
    }
    func assertContained(_ result:ObjectStitches,_ rings:[[Point]],length:Double=3,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertFalse(result.sections.isEmpty,file:file,line:line)
        for section in result.sections {for (a,b) in zip(section.points,section.points.dropFirst()) {
            XCTAssertTrue(AreaGeometry.segmentInside(a,b,rings:rings),"Escaped region: \(a) -> \(b)",file:file,line:line)
            XCTAssertLessThanOrEqual(a.distance(to:b),length+0.0001,file:file,line:line)
        }}
    }
    func testFillHoleNeverGetsSewnAcross() throws {
        var o=rectangle();o.holes=[[Point(10,5),Point(20,5),Point(20,15),Point(10,15)].map{PathNode($0)}]
        let result=try AreaEngine.fill(o)
        XCTAssertGreaterThan(result.sections.count,1)
        assertContained(result,([o.nodes]+o.holes!).map{AreaGeometry.ring($0)})
    }
    func testConcaveFillConnectorsStayInside() throws {
        var o=rectangle();o.nodes=[Point(0,0),Point(20,0),Point(20,20),Point(14,20),Point(14,6),Point(6,6),Point(6,20),Point(0,20)].map{PathNode($0)}
        o.digitizing?.angle=23
        assertContained(try AreaEngine.fill(o),[AreaGeometry.ring(o.nodes)])
    }
    func testExpansionAppliedOnceAndHoleContracts() throws {
        var o=rectangle();o.digitizing?.expansion=0.2;o.holes=[[Point(10,5),Point(20,5),Point(20,15),Point(10,15)].map{PathNode($0)}]
        let region=try AreaGeometry.offset(([o.nodes]+o.holes!).map{AreaGeometry.ring($0)},by:0.2)
        XCTAssertEqual(region.flatMap{$0}.map(\.x).min()!,-0.2,accuracy:0.001)
        XCTAssertTrue(AreaGeometry.contains(Point(10.1,10),rings:region))
        XCTAssertFalse(AreaGeometry.contains(Point(10.3,10),rings:region))
        assertContained(try AreaEngine.fill(o),region)
    }
    func testSatinCompensationAndCenterUnderlay() throws {
        var object=satin();object.digitizing?.underlay = .center;object.digitizing?.pullPercent=nil   // the fixed base compensation only
        let result=try AreaEngine.satin(object)
        XCTAssertTrue(result.sections.first!.underlay)
        let top=result.sections.last!.points
        XCTAssertEqual(top[0].x,-0.2,accuracy:0.00001);XCTAssertEqual(top[1].x,4.2,accuracy:0.00001)
        XCTAssertEqual(top.count,102)
        XCTAssertTrue(zip(top,top.dropFirst()).allSatisfy{$0.distance(to:$1)<10})
    }
    func testCrossingSatinAndOverwideSatinRejected() {
        var o=satin();o.nodes[2].point=Point(4,20);o.nodes[3].point=Point(0,20)
        // Over-wide satin is refused only with Split wide satin off (new satins split it instead; see SatinToolsTests).
        var wide=satin(10);wide.digitizing?.autoSplit=nil
        XCTAssertThrowsError(try AreaEngine.satin(o));XCTAssertThrowsError(try AreaEngine.satin(wide))
    }
    func testCollapsedUnderlayIsReported() throws {
        var o=rectangle(0.3,10);o.digitizing?.underlay = .edge;o.digitizing?.secondUnderlay = .tatami
        let result=try AreaEngine.fill(o)
        XCTAssertTrue(result.warnings.contains{$0.contains("collapsed")});XCTAssertTrue(result.sections.allSatisfy{!$0.underlay})
    }
    func testInvalidHolesAndBowTieRejected() {
        var o=rectangle();o.holes=[[Point(25,5),Point(35,5),Point(35,15),Point(25,15)].map{PathNode($0)}]
        XCTAssertThrowsError(try AreaEngine.fill(o))
        o=rectangle();o.nodes=[Point(0,0),Point(20,20),Point(0,20),Point(20,0)].map{PathNode($0)}
        XCTAssertThrowsError(try AreaEngine.fill(o))
    }
    func testFillUnderlayRespectsHoleAndInset() throws {
        var o=rectangle();o.holes=[[Point(10,5),Point(20,5),Point(20,15),Point(10,15)].map{PathNode($0)}];o.digitizing?.underlay = .edge;o.digitizing?.secondUnderlay = .tatami
        let result=try AreaEngine.fill(o),region=try AreaGeometry.offset(([o.nodes]+o.holes!).map{AreaGeometry.ring($0)},by:-0.4)
        assertContained(ObjectStitches(sections:result.sections.filter(\.underlay)),region,length:2.5)
    }
    func testSamplerIsDeterministicAndInHoop() throws {
        let design=Design.stitchSampler(),a=try StitchEngine.compile(design),b=try StitchEngine.compile(design)
        XCTAssertEqual(a,b);XCTAssertGreaterThan(a.stitchCount,2000);XCTAssertTrue(a.outsidePoints.allSatisfy{design.hoop.contains($0)})
        XCTAssertTrue(a.commands.contains{$0.underlay == true});XCTAssertEqual(a.commands.filter{$0.op == .colorChange}.count,1)
    }
    func testLegacyRunningObjectDecodes() throws {
        var design=Design.sample();design.schemaVersion=1;design.engineVersion="run-1"
        let bytes=try JSONEncoder().encode(design),loaded=try JSONDecoder().decode(Design.self,from:bytes)
        XCTAssertEqual(loaded.engineVersion,"run-1");XCTAssertEqual(loaded.objects[0].kind,.run)
        XCTAssertEqual(try StitchEngine.compile(loaded).stitchCount,162)
    }
    func testTransformIncludesHoles() {
        var o=rectangle();o.holes=[[PathNode(Point(1,2))]];o.transform{$0+Point(7,8)}
        XCTAssertEqual(o.holes![0][0].point,Point(8,10));XCTAssertEqual(o.nodes[0].point,Point(7,8))
    }
    func testCancellationStopsAreaCompilation() async throws {
        let task=Task.detached {try Task.checkCancellation();return try StitchEngine.compile(Design.stitchSampler())};task.cancel()
        do{_ = try await task.value;XCTFail("Expected cancellation")}catch is CancellationError{}catch{XCTFail("Wrong error: \(error)")}
    }
    func testExcessivelyLongSatinRejectedBeforeSampling() {
        var object=satin();object.nodes[2].point.y=2000;object.nodes[3].point.y=2000
        XCTAssertThrowsError(try AreaEngine.satin(object)) { error in
            XCTAssertTrue(error.localizedDescription.contains("5,000 edge pairs"))
        }
    }
    /// A corner 0.1 mm from the start used to be sewn as a 0.1 mm stitch (with a warning). Stitches under 0.3 mm are
    /// now merged into the next one, so nothing tiny is sewn and there's nothing to warn about; the line still
    /// starts and ends where it did.
    func testTinyRunningCornerIsMergedAway() throws {
        var design=Design();design.objects=[RunObject(name:"Tiny",nodes:[Point(0,0),Point(0.1,0),Point(2,0)].map{PathNode($0)})]
        let plan=try StitchEngine.compile(design)
        let points=plan.commands.filter{$0.op == .stitch}.map(\.point)
        XCTAssertFalse(plan.warnings.contains{$0.contains("shorter than")})
        XCTAssertTrue(zip(points,points.dropFirst()).allSatisfy{$0.distance(to:$1)>=0.3},"\(points)")
        XCTAssertEqual(points.first,Point(0,0));XCTAssertEqual(points.last,Point(2,0))
    }
    /// Only stitches under 0.3 mm go, and never a section's first or last point.
    func testSmallStitchCleanupKeepsEndsAndLongerStitches() {
        let cleaned=StitchEngine.withoutSmallStitches([Point(0,0),Point(0.1,0),Point(1,0),Point(1.2,0),Point(3,0),Point(3.1,0)])
        XCTAssertEqual(cleaned,[Point(0,0),Point(1,0),Point(3.1,0)],"0.1 and 1.2 are too close to the point kept before them; 3 is too close to the end, which stays")
        XCTAssertEqual(StitchEngine.withoutSmallStitches([Point(0,0),Point(0.1,0)]),[Point(0,0),Point(0.1,0)],"two points are left alone")
    }

    /// Fill rows clipped to a scrap at a sharp corner used to sew as one tiny stitch (and warn); scraps under 0.3 mm
    /// are left out when the rows are made.
    func testFillsLeaveOutRowScrapsAtSharpCorners() throws {
        for (style,size) in [(FillStyle.tatami,30.0),(.radial,8),(.contour,8)] {
            var star=RunObject(name:"Star",nodes:ShapeGeometry.nodes(.star,in:(Point(-size/2,-size/2),Point(size/2,size/2))))
            star.closed=true;star.digitizing=DigitizingSettings(kind:.fill);star.digitizing?.fillStyle=style;star.stitchLength=3
            var design=Design();design.objects=[star]
            XCTAssertFalse(try StitchEngine.compile(design).warnings.contains{$0.contains("shorter than 0.3")},"\(style) \(size) mm star")
        }
    }

    func testZigzagUnderlayFitsTrueInsetForStraightAndTaperedColumns() throws {
        for tapered in [false,true] {
            var object=satin();object.digitizing?.underlay = .zigzag
            if tapered {object.nodes[2].point.x=1;object.nodes[3].point.x=3}
            let result=try AreaEngine.satin(object)
            let under=result.sections.filter(\.underlay)
            XCTAssertEqual(under.count,1)
            XCTAssertGreaterThan(under.first?.points.count ?? 0,20)
            XCTAssertGreaterThan(under.first?.points.map(\.y).max() ?? 0,18)
            XCTAssertLessThan(under.first?.points.map(\.y).min() ?? 20,2)
            XCTAssertFalse(result.warnings.contains{$0.contains("omitted")})
            let nodes=[object.nodes[0],object.nodes[2],object.nodes[3],object.nodes[1]]
            let inset=try AreaGeometry.offset([AreaGeometry.ring(nodes)],by:-0.4)
            assertContained(ObjectStitches(sections:under),inset,length:2.5)
        }
    }
    func testZigzagUnderlayCollapseStillWarns() throws {
        var object=satin(0.6);object.digitizing?.underlay = .zigzag
        let result=try AreaEngine.satin(object)
        XCTAssertFalse(result.sections.contains(where: \.underlay))
        XCTAssertTrue(result.warnings.contains{$0.contains("omitted")})
    }

    func testCurvedSatinZigzagStaysInsideInset() throws {
        var object=Design.stitchSampler().objects[1];object.digitizing?.underlay = .zigzag
        let result=try AreaEngine.satin(object),under=result.sections.filter(\.underlay)
        XCTAssertEqual(under.count,1);XCTAssertGreaterThan(under.first?.points.count ?? 0,40)
        XCTAssertFalse(result.warnings.contains{$0.contains("omitted")})
        let left=object.nodes.enumerated().filter{$0.offset%2==0}.map(\.element)
        let right=object.nodes.enumerated().filter{$0.offset%2==1}.map(\.element)
        let region=RunningEngine.flatten(left).flatMap{$0}+RunningEngine.flatten(right).flatMap{$0}.reversed()
        let inset=try AreaGeometry.offset([region],by:-object.settings.inset)
        assertContained(ObjectStitches(sections:under),inset,length:2.5)
    }


    /// A row whose stitch grid lands a hair from the edge used to end in a sliver stitch. Now the two end stitches
    /// share that length: none under 0.3 mm, none over the stitch length.
    func testFillRowsNeverEndInASliver() throws {
        var design=Design();design.objects=[rectangle(30.1,20)]   // grid points at 30 mm, 0.1 mm from the right edge
        let stitches=try StitchEngine.compile(design).commands.filter{$0.op == .stitch}
        let alongRows=zip(stitches,stitches.dropFirst()).filter{abs($0.point.y-$1.point.y)<0.000001 && $0.point.distance(to:$1.point)>0.000001}
        XCTAssertFalse(alongRows.isEmpty)
        for (a,b) in alongRows {
            XCTAssertGreaterThanOrEqual(a.point.distance(to:b.point),0.3,"\(a.point) → \(b.point)")
            XCTAssertLessThanOrEqual(a.point.distance(to:b.point),3.0001)
        }
    }
    /// The lock stitches at the start of a line used to go halfway along its first stitch, so a 0.2 mm first stitch
    /// made a 0.1 mm lock. They're now 0.6 mm measured along the stitches.
    func testLockStitchesAreNeverSlivers() throws {
        var line=RunObject(name:"Line",nodes:[Point(0,0),Point(0.2,0),Point(10,0)].map{PathNode($0)});line.stitchLength=2.5
        XCTAssertTrue(line.tieIn && line.tieOut)
        var design=Design();design.objects=[line]
        let points=try StitchEngine.compile(design).commands.filter{$0.op == .stitch}.map(\.point)
        XCTAssertEqual(points[1].distance(to:points[0]),0.6,accuracy:0.0001,"the lock goes 0.6 mm along the line")
        XCTAssertEqual(points[2].distance(to:points[0]),0,accuracy:0.0001,"and back to the start")
        XCTAssertEqual(points[points.count-2].distance(to:points.last!),0.6,accuracy:0.0001,"the same at the end")
    }

    /// Font satins (relaxed checks) get short stitches too: around a tight curve, some stitches stop short of the
    /// crowded inner edge instead of all landing on it.
    func testFontSatinsStopShortOnTheInsideOfCurves() throws {
        var nodes:[PathNode]=[]
        for i in 0...12 {let angle=Double(i)/12 * .pi/2;nodes+=[PathNode(Point(cos(angle),sin(angle))),PathNode(Point(4*cos(angle),4*sin(angle)))]}   // inner radius 1, outer 4
        var object=RunObject(name:"Curve",nodes:nodes);object.digitizing=DigitizingSettings(kind:.satin)
        object.digitizing?.relaxedChecks=true;object.digitizing?.shortStitches=nil;object.digitizing?.expansion=0;object.digitizing?.underlay = .none;object.digitizing?.pullPercent=nil
        let top=try AreaEngine.satin(object).sections.filter{!$0.underlay}.flatMap(\.points)
        let inner=top.filter{$0.distance(to:Point(0,0))<2.5}
        XCTAssertTrue(inner.contains{$0.distance(to:Point(0,0))>1.5},"some inner ends stop a third of the way across")
        XCTAssertTrue(inner.contains{abs($0.distance(to:Point(0,0))-1)<0.01},"others still reach the inner edge")
    }
    func testBoundaryRouteGivesUpOnRoutesLongerThanAsked() {
        // A U: from the top of one arm to the other, the way round inside it is 60 mm (round the bottom, 100 mm).
        let u=[Point(0,0),Point(30,0),Point(30,30),Point(20,30),Point(20,10),Point(10,10),Point(10,30),Point(0,30)]
        XCTAssertEqual(AreaGeometry.boundaryRoute(Point(5,30),Point(25,30),rings:[u]).map(AreaGeometry.pathLength) ?? 0,60,accuracy:1e-9)
        XCTAssertEqual(AreaGeometry.boundaryRoute(Point(5,30),Point(25,30),rings:[u],longest:70).map(AreaGeometry.pathLength) ?? 0,60,accuracy:1e-9)
        XCTAssertNil(AreaGeometry.boundaryRoute(Point(5,30),Point(25,30),rings:[u],longest:50))
        XCTAssertNotNil(AreaGeometry.boundaryRoute(Point(1,0),Point(29,0),rings:[u]),"straight along the bottom")
        XCTAssertNil(AreaGeometry.boundaryRoute(Point(1,0),Point(29,0),rings:[u],longest:20),"a straight hop counts too")
    }
}

