// A point placed twice on the same spot (a corner, then a curve point) used to bend the curve out and back in a
// tiny loop there, so a fill with it couldn't sew ("Outline edges cross or touch").
import XCTest
@testable import EmbroideryCore

final class DoubledPointTests: XCTestCase {
    func testAPointPlacedTwiceMakesNoLoop() throws {
        // A cloud drawn by hand: points 5 and 6 are on the same spot, the first a corner, the second a curve point.
        let cloud = [
            PathNode(Point(-26.9090, 16.5784), smooth: true),
            PathNode(Point(-24.4813, 22.5879), smooth: true),
            PathNode(Point(-19.0880, 24.2686), smooth: true),
            PathNode(Point(-14.9803, 22.2227), smooth: true),
            PathNode(Point(-12.9962, 18.1155), smooth: false),
            PathNode(Point(-12.9962, 18.1155), smooth: true),
            PathNode(Point(-10.1282, 18.6720), smooth: true),
            PathNode(Point(-2.8441, 17.9548), smooth: true),
            PathNode(Point(0.3456, 12.9851), smooth: true),
            PathNode(Point(2.6630, 12.3220), smooth: true),
            PathNode(Point(7.0672, 7.5696), smooth: true),
            PathNode(Point(2.9136, 3.7275), smooth: true),
            PathNode(Point(-1.5959, 4.7750), smooth: true),
            PathNode(Point(-4.0399, 1.3104), smooth: true),
            PathNode(Point(-8.6009, -0.1858), smooth: true),
            PathNode(Point(-14.1511, 1.5107), smooth: true),
            PathNode(Point(-15.8859, -0.2314), smooth: true),
            PathNode(Point(-19.6952, -1.4140), smooth: false),
            PathNode(Point(-25.8147, 2.0843), smooth: true),
            PathNode(Point(-28.4977, 1.3803), smooth: true),
            PathNode(Point(-37.9352, 3.8140), smooth: true),
            PathNode(Point(-37.9594, 13.0090), smooth: true),
            PathNode(Point(-32.1131, 16.5916), smooth: false),
        ]
        XCTAssertEqual(cloud[4].point, cloud[5].point)
        XCTAssertNoThrow(try AreaGeometry.validate([AreaGeometry.ring(cloud)]), "the outline doesn't cross itself")
        var fill = RunObject(name: "Cloud", nodes: cloud, color: .palette[0])
        fill.closed = true; fill.digitizing = DigitizingSettings(kind: .fill)
        var design = Design(); design.objects = [fill]
        XCTAssertGreaterThan(try StitchEngine.compile(design).stitchCount, 100, "the fill sews")
    }

    func testTheStretchBetweenTwoPointsOnTheSameSpotIsJustThatSpot() {
        let nodes = [PathNode(Point(0, 0)), PathNode(Point(10, 0)), PathNode(Point(10, 0), smooth: true), PathNode(Point(10, 10))]
        let (a, b, c, d) = RunningEngine.controls(nodes, closed: false, segment: 1)
        XCTAssertEqual([a, b, c, d], [Point(10, 0), Point(10, 0), Point(10, 0), Point(10, 0)])
    }
}
