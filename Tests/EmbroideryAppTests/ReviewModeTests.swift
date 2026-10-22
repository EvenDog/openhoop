// Checks Review Sewing Order: stepping selects each step in turn, a drawing tool finishes the review, the canvas
// draws the steps still to sew faded or not at all, the route draws everything and its numbers never overlap,
// warnings mark their steps, and the travel label and warnings read as intended.
import XCTest
import AppKit
@testable import EmbroideryCore   // for SewingTravel's memberwise initializer
@testable import EmbroideryApp

final class ReviewModeTests: XCTestCase {
    /// Three short lines side by side, far enough apart to be trimmed between.
    @MainActor private func threeLines() throws -> EditorState {
        _ = NSApplication.shared
        let state = EditorState()
        state.design.objects = (0..<3).map { i in
            RunObject(name: "Line \(i + 1)", nodes: [PathNode(Point(Double(i) * 20 - 30, 0)), PathNode(Point(Double(i) * 20 - 20, 0))])
        }
        state.plan = try StitchEngine.compile(state.design)
        return state
    }

    @MainActor func testSteppingSelectsEachStepInTurn() throws {
        let state = try threeLines(), ids = state.design.objects.map(\.id)
        state.reviewing = true
        XCTAssertNil(state.reviewStep, "nothing selected yet")
        state.stepReview(by: 1)
        XCTAssertEqual(state.selection, [ids[0]], "on from nothing: the first step")
        state.stepReview(by: 1); state.stepReview(by: 1); state.stepReview(by: 1)
        XCTAssertEqual(state.selection, [ids[2]], "stops at the last step")
        XCTAssertEqual(state.reviewStep?.index, 2)
        XCTAssertEqual(state.status, "Step 3 of 3: Line 3.")
        state.stepReview(by: -1)
        XCTAssertEqual(state.selection, [ids[1]])
        state.selection = [ids[0]]   // clicking a step in Sewing order jumps to it
        XCTAssertEqual(state.reviewStep?.index, 0)
    }

    @MainActor func testDrawingToolsFinishTheReview() throws {
        let state = try threeLines()
        state.reviewing = true
        state.tool = .entryExit
        XCTAssertTrue(state.reviewing, "setting start and end points is part of reviewing")
        state.tool = .select
        state.tool = .run
        XCTAssertFalse(state.reviewing)
    }

    @MainActor func testFadedDrawsTheStepsStillToSewAndHiddenDoesNot() throws {
        let state = try threeLines()
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 400); state.canvas = canvas
        let saved = Preferences.shared.data.reviewHidesUnsewn
        defer { Preferences.shared.data.reviewHidesUnsewn = saved }   // never saved to the file
        /// The canvas drawn as an image.
        func render() -> Data {
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: rep); return rep.tiffRepresentation!
        }
        state.reviewing = true; state.stepReview(by: 1)
        Preferences.shared.data.reviewHidesUnsewn = nil
        let faded = render()
        Preferences.shared.data.reviewHidesUnsewn = true
        let hidden = render()
        XCTAssertNotEqual(faded, hidden, "Faded draws the lines still to sew; Hidden leaves them out")
        state.stepReview(by: 1); state.stepReview(by: 1)
        Preferences.shared.data.reviewHidesUnsewn = nil
        let lastFaded = render()
        Preferences.shared.data.reviewHidesUnsewn = true
        XCTAssertEqual(lastFaded, render(), "at the last step nothing is left to sew, so the two look the same")
    }

    @MainActor func testRouteShowsTheWholeDesignUntilAStepIsTaken() throws {
        let state = try threeLines()
        let canvas = DesignCanvas(state: state); canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 400); state.canvas = canvas
        func render() -> Data {
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: rep); return rep.tiffRepresentation!
        }
        state.reviewing = true; state.stepReview(by: 1)
        let step = render()
        state.reviewShowsRoute = true
        XCTAssertNotEqual(step, render(), "the route draws every step and the moves between them")
        state.stepReview(by: 1)
        XCTAssertFalse(state.reviewShowsRoute, "stepping shows the step")
    }

    func testRouteBadgesStayOnTheirStartsUnlessTheyWouldOverlap() {
        let radius = DesignCanvas.routeBadgeRadius
        let apart = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        XCTAssertEqual(DesignCanvas.routeBadges(apart), apart)
        // Six starts bunched within a few points of each other, as in the middle of a flower.
        let bunched = (0..<6).map { CGPoint(x: 200 + Double($0 % 3) * 4, y: 200 + Double($0 / 3) * 4) } + [CGPoint(x: 400, y: 400)]
        let badges = DesignCanvas.routeBadges(bunched)
        XCTAssertEqual(badges[0], bunched[0], "the first keeps its place")
        XCTAssertEqual(badges.last, bunched.last, "one far from the rest keeps its place")
        for i in badges.indices { for j in badges.indices where j > i {
            XCTAssertGreaterThanOrEqual(hypot(badges[i].x - badges[j].x, badges[i].y - badges[j].y), radius * 2, "badges \(i + 1) and \(j + 1) overlap")
        } }
    }

    @MainActor func testWarningsMarkTheirStepsAndShowingOneShowsItsStep() throws {
        _ = NSApplication.shared
        let state = EditorState()
        // Two lines in one thread with 20 mm between them: a long move.
        state.design.objects = [-40.0, -10.0].map { x in RunObject(name: "Line", nodes: [PathNode(Point(x, 0)), PathNode(Point(x + 10, 0))]) }
        state.plan = try StitchEngine.compile(state.design)
        let second = state.design.objects[1].id
        XCTAssertEqual(Array(state.sewingWarnings.keys), [1])
        XCTAssertEqual(state.warnedObjects, [second])
        state.reviewing = true; state.reviewShowsRoute = true
        state.showStep(1)   // clicking the warning in the route's list
        XCTAssertEqual(state.selection, [second])
        XCTAssertFalse(state.reviewShowsRoute, "it shows that step")
        XCTAssertEqual(SewingWarning.longMove(18.6).summary(after: "Petal 1", unit: .millimeters), "starts 18.6 mm from where Petal 1 ended")
        XCTAssertEqual(SewingWarning.untrimmedJump(6).summary(after: "Petal 1", unit: .millimeters), "jumps 6.0 mm from Petal 1 without a trim")
    }

    func testTravelSummaries() {
        func travel(length: Double, trimmed: Bool = false, jumped: Bool = false, colorChange: Bool = false, stopped: Bool = false) -> SewingTravel {
            SewingTravel(from: Point(0, 0), length: length, trimmed: trimmed, jumped: jumped, colorChange: colorChange, stopped: stopped)
        }
        XCTAssertEqual(travel(length: 18.62, trimmed: true, jumped: true).summary(unit: .millimeters), "Trim, then 18.6 mm")
        XCTAssertEqual(travel(length: 9, trimmed: true, jumped: true, colorChange: true).summary(unit: .millimeters), "Trim and thread change, then 9.0 mm")
        XCTAssertEqual(travel(length: 9, trimmed: true, jumped: true, colorChange: true, stopped: true).summary(unit: .millimeters), "Trim, stop and thread change, then 9.0 mm")
        XCTAssertEqual(travel(length: 6, jumped: true).summary(unit: .millimeters), "Jump of 6.0 mm, not trimmed")
        XCTAssertEqual(travel(length: 1).summary(unit: .millimeters), "Stitched across, 1.0 mm")
        XCTAssertEqual(travel(length: 0).summary(unit: .millimeters), "Carries straight on")
        XCTAssertEqual(travel(length: 25.4, trimmed: true, jumped: true).summary(unit: .inches), "Trim, then 1.00 in")
    }
}
