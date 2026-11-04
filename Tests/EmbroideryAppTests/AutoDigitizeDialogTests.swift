// Checks that the Auto-Digitize dialog fits a 13-inch laptop screen (982 points tall, less the menu bar), with its
// colors and notes scrolling in a column of their own instead of making the dialog taller.
import XCTest
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import EmbroideryCore
@testable import EmbroideryApp

final class AutoDigitizeDialogTests: XCTestCase {
    @MainActor func testTheDialogFitsALaptopScreen() throws {
        _ = NSApplication.shared
        // A small red-and-white picture to show in the dialog.
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1); context.fillEllipse(in: CGRect(x: 8, y: 8, width: 48, height: 48))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let artwork = Artwork(data: data as Data, name: "Dot", width: 40, height: 40)

        let host = NSHostingView(rootView: AutoDigitizeView(artwork: artwork, options: AutoDigitizeOptions()) { _, _ in }.frame(width: 820))
        let height = host.fittingSize.height
        print("Auto-Digitize dialog height:", height)
        // 982 points of screen, less the menu bar (about 37) and the dialog window's title bar (about 28).
        XCTAssertLessThanOrEqual(height, 982 - 37 - 28 - 40, "leaves some room to spare")
    }
}
