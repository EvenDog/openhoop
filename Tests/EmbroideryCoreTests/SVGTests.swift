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
    /// The way Illustrator saves SVG by default: a <style> block in <defs>, shapes colored by class.
    func testStyleBlockClassesColorShapes()throws {
        let result=try load("<defs><style>.cls-1{fill:#e63946;}.cls-2{fill:none;stroke:#1d3557;stroke-width:2px;}</style></defs><rect class='cls-1' width='10' height='10'/><path class='cls-2' d='M0 20L30 20'/>")
        XCTAssertEqual(result.objects.count,2)
        XCTAssertEqual(result.objects[0].color.hex,0xe63946);XCTAssertTrue(result.objects[0].closed)
        XCTAssertEqual(result.objects[1].color.hex,0x1d3557);XCTAssertFalse(result.objects[1].closed)
    }
    /// Attributes lose to style rules, which lose to style="…"; among rules #id beats .class beats a tag name, and
    /// the later rule wins a tie. A shape can have several classes.
    func testStyleRulesFollowCSSPriority()throws {
        let css="<style>rect{fill:#000001} .a{fill:#000002} .b{fill:#000003} #top{fill:#000004} rect.a{fill:#000005}</style>"
        let result=try load(css+"""
            <rect fill='#0000ff' width='5' height='5'/>
            <rect class='a' x='6' width='5' height='5'/>
            <rect class='a b' x='12' width='5' height='5'/>
            <circle class='b' cx='22' cy='3' r='2'/>
            <rect id='top' class='a' x='26' width='5' height='5'/>
            <rect class='a' style='fill:#000006' x='32' width='5' height='5'/>
            """)
        XCTAssertEqual(result.objects.map(\.color.hex),[0x000001,0x000005,0x000005,0x000003,0x000004,0x000006])
    }
    func testStyleBlockAfterTheShapesStillApplies()throws {
        let result=try load("<g class='leaf'><rect width='5' height='5'/></g><style><![CDATA[ /* green */ .leaf { fill: green } ]]></style>")
        XCTAssertEqual(result.objects[0].color.hex,0x008000)
    }
    func testStyleRulesCanHideShapes()throws {
        let result=try load("<style>.hidden{display:none}</style><rect width='5' height='5'/><rect class='hidden' x='10' width='5' height='5'/>")
        XCTAssertEqual(result.objects.count,1)
    }
    /// Rules with selectors this importer doesn't match (combinators, pseudo-classes, @-blocks) are skipped with a
    /// warning; the simple rules beside them still apply.
    func testComplexStyleRulesAreSkippedWithWarning()throws {
        let result=try load("<style>@media print{.a{fill:blue}} g > .a{fill:blue} .a:hover{fill:blue} .a{fill:red}</style><g><rect class='a' width='5' height='5'/></g>")
        XCTAssertEqual(result.objects[0].color.hex,0xff0000)
        XCTAssertTrue(result.warnings.contains{$0.contains("style rules")})
    }
    func testExternalStylesheetsAreRefused() {
        XCTAssertThrowsError(try SVGImporter.load(Data("<?xml-stylesheet href='https://example.com/style.css'?><svg><rect width='5' height='5'/></svg>".utf8)))
        XCTAssertThrowsError(try load("<style>@import url('https://example.com/style.css');</style><rect width='5' height='5'/>"))
    }
    // MARK: <use> and symbols

    func testUseDrawsTheReferencedShapeMoved()throws {
        let result=try load("<defs><rect id='r' width='5' height='5' fill='red'/><circle id='c' r='2'/></defs><use href='#r'/><use xlink:href='#r' x='10' fill='blue'/><use href='#c' x='30' y='30' fill='green'/>",
                            attributes:"xmlns:xlink='http://www.w3.org/1999/xlink' width='40mm' height='40mm' viewBox='0 0 40 40'")
        XCTAssertEqual(result.objects.count,3,"Shapes in <defs> are drawn only where a <use> points at them")
        // The rect's own fill wins over the <use>'s; the circle has none, so it takes the <use>'s.
        XCTAssertEqual(result.objects.map(\.color.hex),[0xff0000,0xff0000,0x008000])
        func left(_ object:RunObject)->Double{object.outlinePaths.flatMap{$0}.map(\.x).min()!}
        XCTAssertEqual(left(result.objects[1])-left(result.objects[0]),10,accuracy:0.001)
        XCTAssertEqual(left(result.objects[2])-left(result.objects[0]),28,accuracy:0.01)
    }
    func testSymbolIsScaledToTheUseSize()throws {
        let result=try load("<symbol id='s' viewBox='0 0 10 10'><rect width='10' height='10'/></symbol><use href='#s' width='20' height='20'/>")
        XCTAssertEqual(result.objects.count,1,"A symbol is drawn only through a <use>")
        XCTAssertEqual(result.width,20,accuracy:0.001)
    }
    func testUseLoopsAndMissingTargets()throws {
        XCTAssertThrowsError(try load("<g id='g'><rect width='5' height='5'/><use href='#g'/></g>"))
        let result=try load("<rect width='5' height='5'/><use href='#nothing'/>")
        XCTAssertEqual(result.objects.count,1)
        XCTAssertTrue(result.warnings.contains{$0.contains("<use>")})
    }

    // MARK: Gradients

    /// Sews `object` as the fill it becomes when Fill is pressed (no underlay, so only the gradient rows count) and
    /// returns how many of its stitches land on each side of `split`, measured along `axis`.
    func stitchesEachSide(_ object:RunObject,axis:KeyPath<Point,Double>,split:Double)throws->(low:Int,high:Int) {
        var fill=object;fill.digitizing=DigitizingSettings.fill(from:object.digitizing);fill.digitizing?.underlay = .none;fill.closed=true
        var design=Design();design.objects=[fill]
        let points=try StitchEngine.compile(design).commands.filter{$0.op == .stitch}.map(\.point)
        return (points.filter{$0[keyPath:axis]<split}.count,points.filter{$0[keyPath:axis]>split}.count)
    }
    /// A two-color gradient becomes two stacked outlines: the start color solid at the start and sheer at the end,
    /// the end color the other way round. Pressing Fill keeps that.
    func testLinearGradientBecomesTwoBlendingFills()throws {
        let result=try load("<defs><linearGradient id='g'><stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/></linearGradient></defs><rect width='30' height='10' fill='url(#g)'/>")
        XCTAssertEqual(result.objects.map(\.color.hex),[0xff0000,0x0000ff])
        XCTAssertTrue(result.objects.allSatisfy{$0.kind == .vector},"Still outlines until Fill is pressed")
        let red=try stitchesEachSide(result.objects[0],axis:\.x,split:0),blue=try stitchesEachSide(result.objects[1],axis:\.x,split:0)
        XCTAssertGreaterThan(red.low,red.high*2,"Red is solid on the left, where the gradient starts")
        XCTAssertGreaterThan(blue.high,blue.low*2,"Blue is solid on the right")
    }
    /// The way some drawing apps save gradients: one holds the stops, another points at it (href) and sets the
    /// direction in user units. Stop colors may come from style="…" or a class.
    func testGradientStopsThroughHrefInUserUnits()throws {
        let result=try load("<style>.end{stop-color:#0000ff}</style><defs><linearGradient id='base'><stop offset='0' style='stop-color:#ff0000'/><stop class='end' offset='1'/></linearGradient><linearGradient id='g' href='#base' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='0' y2='20'/></defs><rect width='20' height='20' fill='url(#g)'/>")
        XCTAssertEqual(result.objects.map(\.color.hex),[0xff0000,0x0000ff])
        let red=try stitchesEachSide(result.objects[0],axis:\.y,split:0)
        XCTAssertGreaterThan(red.high,red.low*2,"Red is solid at the top, where the gradient starts (SVG y runs down, the canvas up)")
    }
    func testRadialGradientBecomesItsMiddleColor()throws {
        let result=try load("<radialGradient id='g'><stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/></radialGradient><circle r='5' fill='url(#g)'/>")
        XCTAssertEqual(result.objects.count,1)
        XCTAssertEqual(result.objects[0].color.hex,0x800080)
        XCTAssertNotEqual(result.objects[0].settings.fillStyle,.gradient)
        XCTAssertTrue(result.warnings.contains{$0.lowercased().contains("radial")})
    }
    func testGradientWithMoreColorsBlendsItsEnds()throws {
        let result=try load("<linearGradient id='g'><stop offset='0' stop-color='red'/><stop offset='0.5' stop-color='orange'/><stop offset='1' stop-color='yellow'/></linearGradient><rect width='10' height='10' fill='url(#g)'/>")
        XCTAssertEqual(result.objects.map(\.color.hex),[0xff0000,0xffff00])
        XCTAssertTrue(result.warnings.contains{$0.contains("middle")})
    }
    func testFillFromAPlainOutlineIsAPlainFill() {
        XCTAssertEqual(DigitizingSettings.fill(from:DigitizingSettings(kind:.vector)),DigitizingSettings(kind:.fill))
        XCTAssertEqual(DigitizingSettings.fill(from:nil),DigitizingSettings(kind:.fill))
    }

    func testAllCSSColorNames()throws {
        let result=try load("<rect fill='CornflowerBlue' width='5' height='5'/><rect fill='rebeccapurple' x='6' width='5' height='5'/><rect fill='darkred' x='12' width='5' height='5'/>")
        XCTAssertEqual(result.objects.map(\.color.hex),[0x6495ed,0x663399,0x8b0000])
        XCTAssertEqual(SVGStyles.colorNames.count,148)
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
        for paint in ["rgba(1,2,3,0.5)","hsl(120,50%,50%)","#1234","rgb(0 0 0 / 50%)"] {
            XCTAssertThrowsError(try load("<rect width='5' height='5' fill='\(paint)'/>")){error in
                XCTAssertTrue(error.localizedDescription.contains("#RRGGBB"))
            }
        }
    }

}
