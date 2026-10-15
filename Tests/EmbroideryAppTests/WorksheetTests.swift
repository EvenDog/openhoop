// The production worksheet's pages: pictures print at actual size when they fit, long thread lists continue onto
// more pages, and the PDF has one page per layout page with the worksheet's text on it.
import XCTest
import AppKit
import PDFKit
import EmbroideryCore
@testable import EmbroideryApp

final class WorksheetTests: XCTestCase {
    private let letter = CGSize(width: 612, height: 792)

    /// A summary with `steps` thread steps and `notes` warnings, for a design of the given size.
    private func summary(width: Double, height: Double, steps: Int, notes: Int = 0) -> ProductionSummary {
        var summary = ProductionSummary(plan: StitchPlan(), design: Design())
        summary.width = width; summary.height = height
        summary.steps = (0..<steps).map { .init(number: $0 + 1, color: .palette[$0 % 8], stitches: 100, parts: ["Part \($0 + 1)"], stopAfter: false) }
        summary.warnings = (0..<notes).map { "Warning \($0 + 1)" }
        return summary
    }

    func testPictureIsActualSizeWhenItFits() {
        XCTAssertEqual(WorksheetLayout(summary: summary(width: 100, height: 100, steps: 3), pageSize: letter).pictureScale, 1)
        // 300 mm doesn't fit across a Letter page (7.5 in, about 190 mm, between the margins and padding).
        let wide = WorksheetLayout(summary: summary(width: 300, height: 50, steps: 3), pageSize: letter)
        XCTAssertLessThan(wide.pictureScale, 0.65)
        XCTAssertEqual(300 * WorksheetLayout.pointsPerMillimeter * wide.pictureScale, 612 - 2 * 36 - 2 * WorksheetLayout.picturePadding, accuracy: 0.01)
    }

    func testLongThreadListsContinueOnMorePages() {
        let short = WorksheetLayout(summary: summary(width: 100, height: 100, steps: 4, notes: 2), pageSize: letter)
        XCTAssertEqual(short.pages.count, 1)
        let long = WorksheetLayout(summary: summary(width: 100, height: 100, steps: 40, notes: 6), pageSize: letter)
        XCTAssertGreaterThan(long.pages.count, 1)
        XCTAssertEqual(long.pages.map(\.first), [true] + Array(repeating: false, count: long.pages.count - 1))
        // Every step and note appears exactly once, in order, and every page fits on the paper.
        XCTAssertEqual(long.pages.flatMap { Array($0.steps) }, Array(0..<40))
        XCTAssertEqual(long.pages.flatMap { Array($0.notes) }, Array(0..<6))
        for page in long.pages {
            var height = 2 * WorksheetLayout.margin + WorksheetLayout.footerHeight
            height += page.first ? WorksheetLayout.headerHeight + long.pictureHeight + WorksheetLayout.captionHeight : WorksheetLayout.continuedHeaderHeight
            if !page.steps.isEmpty { height += WorksheetLayout.tableHeaderHeight + CGFloat(page.steps.count) * WorksheetLayout.rowHeight }
            if !page.notes.isEmpty { height += WorksheetLayout.notesHeadingHeight + CGFloat(page.notes.count) * WorksheetLayout.noteHeight }
            XCTAssertLessThanOrEqual(height, letter.height)
        }
    }

    @MainActor func testPDFHasEveryPage() throws {
        _ = NSApplication.shared
        let design = Design.sample()
        let plan = try StitchEngine.compile(design)
        var content = WorksheetContent(name: "Sample", hoop: design.hoop, plan: plan, summary: ProductionSummary(plan: plan, design: design), fabric: 0xF5F0E6)
        let data = try XCTUnwrap(WorksheetPrinter.pdf(content: content, pageSize: letter, speed: 600))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, letter)
        let text = document.page(at: 0)?.string ?? ""
        XCTAssertTrue(text.contains("PRODUCTION WORKSHEET"), text)
        XCTAssertTrue(text.contains(plan.stitchCount.formatted()), text)
        XCTAssertTrue(text.contains("Page 1 of 1"), text)

        content.summary.steps = summary(width: 1, height: 1, steps: 40).steps
        XCTAssertEqual(PDFDocument(data: try XCTUnwrap(WorksheetPrinter.pdf(content: content, pageSize: letter, speed: 600)))?.pageCount,
                       WorksheetLayout(summary: content.summary, pageSize: letter).pages.count)
    }

    /// A thread matched to a chart prints its color number and brand, so you know which spool to load.
    @MainActor func testChartThreadsPrintBrandAndNumber() throws {
        _ = NSApplication.shared
        let design = Design.sample()
        let plan = try StitchEngine.compile(design)
        var content = WorksheetContent(name: "Sample", hoop: design.hoop, plan: plan, summary: ProductionSummary(plan: plan, design: design), fabric: 0xF5F0E6)
        content.summary.steps[0].color = ThreadColor("Teal Green", 0x008777, brand: "Brother (machine palette)", code: "3")
        let text = PDFDocument(data: try XCTUnwrap(WorksheetPrinter.pdf(content: content, pageSize: letter, speed: 600)))?.page(at: 0)?.string ?? ""
        // (PDF text extraction can space out letters of the thread name, so the test checks the brand and hex instead.)
        XCTAssertTrue(text.contains("Brother (machine palette)"), text)
        XCTAssertFalse(text.contains("#008777"), "A chart thread shows its number instead of its hex color")
        XCTAssertTrue(text.contains("#DC6552"), "Plain colors still show their hex color")
    }
}
