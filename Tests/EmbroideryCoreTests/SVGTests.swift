import XCTest
@testable import EmbroideryCore

final class SVGTests:XCTestCase {
    func load(_ body:String,attributes:String="width='40mm' height='40mm' viewBox='0 0 40 40'")throws->SVGImportResult {
        try SVGImporter.load(Data("<svg xmlns='http://www.w3.org/2000/svg' \(attributes)>\(body)</svg>".utf8))
    }
    func testPhysicalUnitsAndViewBox()throws {
        let imported=try load("<rect width='100' height='50'/>",attributes:"width='2in' height='1in' viewBox='0 0 100 50'")
        XCTAssertEqual(imported.width,50.8,accuracy:0.001);XCTAssertEqual(imported.height,25.4,accuracy:0.001)
        XCTAssertEqual(imported.objects[0].kind,.vector)
        let xs=imported.objects[0].nodes.map{$0.point.x};XCTAssertEqual(xs.min()!,-25.4,accuracy:0.001)
    }
    func testVectorsNeverGenerateStitchesUntilAssigned()throws {
        var design=Design();design.objects=try load("<rect width='20' height='10'/>").objects
        let unstitched=try StitchEngine.compile(design)
        XCTAssertEqual(unstitched.stitchCount,0);XCTAssertTrue(unstitched.warnings[0].contains("unstitched"))
        design.objects[0].digitizing=DigitizingSettings(kind:.fill)
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount,100)
    }
    func testEvenOddAndNonzeroNestedRings()throws {
        let path="M0 0H30V30H0Z M10 10H20V20H10Z"
        let even=try load("<path fill-rule='evenodd' d='\(path)'/>")
        XCTAssertEqual(even.objects.count,1);XCTAssertEqual(even.objects[0].holes?.count,1)
        let nonzero=try load("<path fill-rule='nonzero' d='\(path)'/>")
        XCTAssertEqual(nonzero.objects.count,1);XCTAssertNil(nonzero.objects[0].holes)
    }
    func testOppositeWindingAndNestedIsland()throws {
        let imported=try load("<path d='M0 0H30V30H0Z M10 10V20H20V10Z M12 12H18V18H12Z'/>")
        XCTAssertEqual(imported.objects.count,2)
        XCTAssertEqual(imported.objects.compactMap(\.holes).flatMap{$0}.count,1)
    }
    func testOverlapResolvedByFillRule()throws {
        let d="M0 0H20V20H0Z M10 0H30V20H10Z"
        let objects=try load("<path d='\(d)'/>").objects
        XCTAssertEqual(objects.count,1)
        XCTAssertEqual(abs(AreaGeometry.area(objects[0].nodes.map(\.point))),600,accuracy:0.01)
    }
    func testInheritedStyleAndNestedTransforms()throws {
        let imported=try load("<g fill='#f00' transform='translate(10,5)'><g transform='scale(2,3)'><rect width='5' height='4' style='fill:#123456'/></g></g>")
        XCTAssertEqual(imported.width,10,accuracy:0.001);XCTAssertEqual(imported.height,12,accuracy:0.001)
        XCTAssertEqual(imported.objects[0].color.hex,0x123456)
    }
    func testTransformOrderAndRotationCenter()throws {
        let m=try SVGReader.transform("translate(10,20) scale(2) rotate(90)")
        let p=m.apply(Point(1,0));XCTAssertEqual(p.x,10,accuracy:1e-8);XCTAssertEqual(p.y,22,accuracy:1e-8)
    }
    func testRelativeCommandsAndImplicitLineNumbers()throws {
        var parser=SVGPathParser("m1e1,5 10-2 h3 v4 l-2 0z",matrix:SVGMatrix())
        let paths=try parser.parse();XCTAssertTrue(paths[0].closed)
        XCTAssertEqual(paths[0].points,[Point(10,5),Point(20,3),Point(23,3),Point(23,7),Point(21,7)])
    }
    func testBezierAndReflectedControls()throws {
        var parser=SVGPathParser("M0 0 C0 10 10 10 10 0 S20 -10 20 0 Q25 10 30 0 T40 0",matrix:SVGMatrix())
        let points=try parser.parse()[0].points
        XCTAssertEqual(points.last,Point(40,0));XCTAssertGreaterThan(points.count,40)
        XCTAssertEqual(points.map(\.y).max()!,7.5,accuracy:0.03);XCTAssertEqual(points.map(\.y).min()!,-7.5,accuracy:0.03)
    }
    func testArcAndCompactFlags()throws {
        var parser=SVGPathParser("M0 0 A10 10 0 0110 10",matrix:SVGMatrix())
        let points=try parser.parse()[0].points
        XCTAssertEqual(points.last,Point(10,10));XCTAssertGreaterThan(points.count,8)
        for p in points{XCTAssertEqual(p.distance(to:Point(0,10)),10,accuracy:0.001)}
    }
    func testBasicShapesAndRoundedRect()throws {
        let result=try load("<g fill='none' stroke='blue'><rect width='10' height='8' rx='2'/><circle cx='20' cy='20' r='4'/><ellipse cx='30' cy='10' rx='3' ry='5'/><line x1='1' y1='1' x2='5' y2='5'/><polyline points='1,2 3,4 5,6'/><polygon points='1,1 4,1 2,3'/></g>")
        XCTAssertEqual(result.objects.count,6)
        // The rounded rectangle keeps its corners as curves: two nodes per corner, joined by Bézier handles.
        XCTAssertEqual(result.objects[0].nodes.count,8);XCTAssertGreaterThan(result.objects[0].outlinePaths[0].count,12)
        XCTAssertTrue(result.objects[0].closed);XCTAssertFalse(result.objects[3].closed)
        XCTAssertTrue(result.warnings.contains{$0.contains("centerlines")})
    }
    func testAspectRatioNoneAndMeet()throws {
        let body="<rect width='10' height='10'/>"
        let meet=try load(body,attributes:"width='40mm' height='20mm' viewBox='0 0 10 10'")
        let none=try load(body,attributes:"width='40mm' height='20mm' viewBox='0 0 10 10' preserveAspectRatio='none'")
        XCTAssertEqual(meet.width,20,accuracy:0.001);XCTAssertEqual(none.width,40,accuracy:0.001)
    }
    func testUnsupportedContentReportedAndMaskedGroupSkipped()throws {
        let result=try load("<text>logo</text><use href='#x'/><g clip-path='url(#x)'><rect width='30' height='30'/></g><rect width='5' height='5'/>")
        XCTAssertEqual(result.objects.count,1);XCTAssertEqual(result.width,5,accuracy:0.001)
        XCTAssertTrue(result.warnings.contains{$0.contains("<text>")});XCTAssertTrue(result.warnings.contains{$0.contains("clip-path")})
    }
    func testDTDExternalEntitiesAndPaintServersRejected() {
        XCTAssertThrowsError(try SVGImporter.load(Data("<!DOCTYPE svg [<!ENTITY x SYSTEM 'file:///private/tmp/secret'>]><svg>&x;</svg>".utf8)))
        XCTAssertThrowsError(try load("<rect width='5' height='5' fill='url(#gradient)'/>"))
    }
    func testMalformedPathAndNonfiniteTransformRejectWholeImport() {
        for d in ["L1 2","M0 0C1 2","M0 0A1 2 0 3 0 1 2","M0 0L1e999 2","M0 0Z 1 2"]{XCTAssertThrowsError(try load("<path d='\(d)'/>"))}
        XCTAssertThrowsError(try load("<rect width='5' height='5' transform='scale(1e20)'/>"))
    }
    func testGeometryRoundTripRetainsVectorAndHoles()throws {
        var design=Design();design.objects=try load("<path fill-rule='evenodd' d='M0 0H30V30H0Z M10 10H20V20H10Z'/>").objects
        let loaded=try JSONDecoder().decode(Design.self,from:JSONEncoder().encode(design));try loaded.validate()
        XCTAssertEqual(loaded,design);XCTAssertEqual(loaded.objects[0].holes?.count,1)
    }
    func testHiddenParentsStayHidden()throws {
        let result=try load("<g display='none'><rect width='30' height='30'/></g><rect width='5' height='5'/>")
        XCTAssertEqual(result.width,5,accuracy:0.001)
    }
    func testRunningAssignmentPreservesEveryHoleBoundary()throws {
        let object=try load("<path fill-rule='evenodd' d='M0 0H30V30H0Z M10 10H20V20H10Z'/>").objects[0]
        let paths=object.runningOutlines()
        XCTAssertEqual(paths.count,2);XCTAssertEqual(paths[0].id,object.id)
        XCTAssertTrue(paths.allSatisfy{$0.kind == .run && $0.closed && $0.holes == nil})
        XCTAssertEqual(paths[1].nodes,object.holes![0]);XCTAssertNotEqual(paths[0].id,paths[1].id)
    }

    func testTouchingSeparateOutlinesStaySeparateAndCanBeFilled()throws {
        let result=try load("<path d='M0 0H20V20H0Z M20 20H30V30H20Z'/>")
        XCTAssertEqual(result.objects.count,2)
        var design=Design();design.objects=result.objects
        for i in design.objects.indices {
            XCTAssertNil(design.objects[i].holes)
            design.objects[i].digitizing=DigitizingSettings(kind:.fill)
        }
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount,100)
    }
    func testHoleSharingOuterEdgeBecomesNotch()throws {
        let result=try load("<path fill-rule='evenodd' d='M0 0H30V30H0Z M10 0H20V10H10Z'/>")
        XCTAssertEqual(result.objects.count,1);XCTAssertNil(result.objects[0].holes)
        XCTAssertEqual(abs(AreaGeometry.area(result.objects[0].nodes.map(\.point))),800,accuracy:0.001)
        var design=Design();design.objects=result.objects;design.objects[0].digitizing=DigitizingSettings(kind:.fill)
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount,100)
    }
    func testHoleTouchingAtPointIsRejectedBeforeImport() {
        XCTAssertThrowsError(try load("<path fill-rule='evenodd' d='M0 0H30V30H0Z M15 0L20 10H10Z'/>"))
    }
    func testPercentageDimensionsUseViewBoxWithWarning()throws {
        let result=try load("<rect width='96' height='48'/>",attributes:"width='100%' height='auto' viewBox='0 0 96 48'")
        XCTAssertEqual(result.width,25.4,accuracy:0.001)
        XCTAssertEqual(result.height,12.7,accuracy:0.001)
        XCTAssertTrue(result.warnings.contains{$0.contains("96 dpi")})
    }
    func testStylesheetsAndClassesCannotSilentlyChangePaint() {
        for body in ["<style>.x{fill:red}</style><rect width='5' height='5'/>","<defs><style>rect{fill:red}</style></defs><rect width='5' height='5'/>","<rect class='x' width='5' height='5'/>"] {
            XCTAssertThrowsError(try load(body))
        }
        XCTAssertThrowsError(try SVGImporter.load(Data("<?xml-stylesheet href='https://example.com/style.css'?><svg><rect width='5' height='5'/></svg>".utf8)))
    }
    func testLinkedArtworkAndZeroWidthStroke()throws {
        let result=try load("<a href='https://example.com'><rect width='5' height='5'/></a><path d='M0 0L30 30' fill='none' stroke='red' stroke-width='0'/>")
        XCTAssertEqual(result.objects.count,1);XCTAssertEqual(result.width,5,accuracy:0.001)
    }
    func testArcScaleBoundSupportsShearAndAnisotropy() {
        XCTAssertEqual(SVGMatrix(a:2,d:2).scale,2,accuracy:1e-10)
        XCTAssertEqual(SVGMatrix(a:4,d:0.25).scale,4,accuracy:1e-10)
        let matrix=SVGMatrix(a:2,b:1,c:3,d:4)
        for i in 0..<360 {
            let r=Double(i)*Double.pi/180
            XCTAssertLessThanOrEqual(matrix.apply(Point(cos(r),sin(r))).distance(to:Point(0,0)),matrix.scale+1e-10)
        }
    }
    func testCompoundSubpathLimitHasActionableError() {
        let paths=String(repeating:"M0 0H2V2H0Z ",count:1025)
        XCTAssertThrowsError(try load("<path d='\(paths)'/>")){error in
            XCTAssertTrue(error.localizedDescription.contains("1,024"))
        }
    }

    func testOversizedOutlineRejectsWholeImportWithSimplifyInstruction() {
        let points=(0..<2001).map{"\($0),\($0%2)"}.joined(separator:" ")
        XCTAssertThrowsError(try load("<rect width='5' height='5'/><polyline fill='none' stroke='red' points='\(points)'/>")){error in
            XCTAssertTrue(error.localizedDescription.contains("Simplify"))
        }
    }
    func testUnsupportedColorSyntaxHasActionableConversionMessage() {
        for paint in ["darkred","rgba(1,2,3,0.5)","hsl(120,50%,50%)","#1234","rgb(0 0 0 / 50%)"] {
            XCTAssertThrowsError(try load("<rect width='5' height='5' fill='\(paint)'/>")){error in
                XCTAssertTrue(error.localizedDescription.contains("#RRGGBB"))
            }
        }
    }

}
