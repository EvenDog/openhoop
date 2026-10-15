// Draws OpenHoop's app icon on a denim tile: a machine embroidery hoop holding an open ring of even, machine-made
// satin stitches (the "open" in OpenHoop), with the design's edit points drawn over it as in the app.
// Drawn with the Mac's own graphics at every size macOS needs, then packed into an .icns with Apple's iconutil.
//
// Run:  swift scripts/make-icon.swift [output folder]
//   Writes <folder>/AppIcon.icns and <folder>/AppIcon-preview.png (1024 px). The folder defaults to Resources.
import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func gradient(_ a: Int, _ b: Int) -> CGGradient { CGGradient(colorsSpace: nil, colors: [color(a), color(b)] as CFArray, locations: [0, 1])! }
func point(_ center: CGPoint, _ angle: CGFloat, _ radius: CGFloat) -> CGPoint { CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius) }

/// The rounded-square tile macOS icons sit on (824 px with a 100 px margin), in denim with a soft shadow.
func tile(_ context: CGContext) {
    let path = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.28))
    context.addPath(path); context.setFillColor(color(0x2C3E5C)); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(path); context.clip()
    context.drawLinearGradient(gradient(0x3A5277, 0x22324C), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()
}

/// An open ring of satin stitches, the way a machine sews them: every stitch straight across the column and evenly
/// spaced, with crisp edges. The gap runs from `gapStart` to `gapEnd` (radians, counterclockwise).
func satinRing(_ context: CGContext, center: CGPoint, inner: CGFloat, outer: CGFloat, gapStart: CGFloat, gapEnd: CGFloat) {
    let sweep = 2 * .pi - (gapEnd - gapStart), count = Int(sweep * (inner + outer) / 2 / 9)   // a stitch every 9 px
    context.setLineCap(.butt)
    for k in 0...count {
        let t = gapEnd + sweep * CGFloat(k) / CGFloat(count)
        context.setStrokeColor(color(0xC25E36)); context.setLineWidth(7.5)
        context.move(to: point(center, t, inner)); context.addLine(to: point(center, t, outer)); context.strokePath()
        context.setStrokeColor(color(0xE8956C, 0.7)); context.setLineWidth(2.5)   // the sheen along each stitch
        context.move(to: point(center, t, inner + 4)); context.addLine(to: point(center, t, outer - 4)); context.strokePath()
    }
    // Crisp rails along both edges.
    context.setStrokeColor(color(0x8E3F22)); context.setLineWidth(3)
    for radius in [inner, outer] { context.addArc(center: center, radius: radius, startAngle: gapEnd, endAngle: gapStart + 2 * .pi, clockwise: false); context.strokePath() }
}

/// Fabric with a faint weave, clipped to `path`.
func fabric(_ context: CGContext, _ path: CGPath) {
    context.addPath(path); context.setFillColor(color(0xF4ECDD)); context.fillPath()
    context.saveGState(); context.addPath(path); context.clip()
    context.setStrokeColor(color(0xD9C7A8, 0.35)); context.setLineWidth(2)
    for x in stride(from: CGFloat(100), through: 924, by: 18) { context.move(to: CGPoint(x: x, y: 100)); context.addLine(to: CGPoint(x: x, y: 924)) }
    for y in stride(from: CGFloat(100), through: 924, by: 18) { context.move(to: CGPoint(x: 100, y: y)); context.addLine(to: CGPoint(x: 924, y: y)) }
    context.strokePath(); context.restoreGState()
}

/// The ring sits in a machine hoop (a rounded-rectangle plastic frame with its mounting bracket on the
/// left and a centering grid), with the design's edit points drawn over the stitches as in the app.
func digitizeDesign(_ context: CGContext) {
    // The hoop's mounting bracket, then the frame.
    let bracket = CGPath(roundedRect: CGRect(x: 150, y: 400, width: 90, height: 200), cornerWidth: 16, cornerHeight: 16, transform: nil)
    context.addPath(bracket); context.setFillColor(color(0x9AA3AD)); context.fillPath()
    for y in [440, 530] as [CGFloat] {
        context.addPath(CGPath(roundedRect: CGRect(x: 170, y: y, width: 40, height: 30), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.setFillColor(color(0x5F6873)); context.fillPath()
    }
    let outerFrame = CGRect(x: 215, y: 150, width: 610, height: 700), innerFrame = outerFrame.insetBy(dx: 46, dy: 46)
    let frame = CGMutablePath()
    frame.addPath(CGPath(roundedRect: outerFrame, cornerWidth: 90, cornerHeight: 90, transform: nil))
    frame.addPath(CGPath(roundedRect: innerFrame, cornerWidth: 50, cornerHeight: 50, transform: nil))
    context.saveGState(); context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x000000, 0.35))
    context.addPath(frame); context.setFillColor(color(0xE9ECEF)); context.fillPath(using: .evenOdd); context.restoreGState()
    context.saveGState(); context.addPath(frame); context.clip(using: .evenOdd)
    context.drawLinearGradient(gradient(0xF6F7F8, 0xC9CFD6), start: CGPoint(x: 512, y: 850), end: CGPoint(x: 512, y: 150), options: [])
    context.restoreGState()
    let fabricPath = CGPath(roundedRect: innerFrame, cornerWidth: 50, cornerHeight: 50, transform: nil)
    fabric(context, fabricPath)
    context.setStrokeColor(color(0x8A939D)); context.setLineWidth(4)
    context.addPath(fabricPath); context.strokePath()
    // The centering marks printed on a hoop's template.
    let center = CGPoint(x: outerFrame.midX, y: outerFrame.midY)
    context.setStrokeColor(color(0x34507A, 0.35)); context.setLineWidth(3); context.setLineDash(phase: 0, lengths: [14, 10])
    context.move(to: CGPoint(x: center.x, y: innerFrame.minY + 10)); context.addLine(to: CGPoint(x: center.x, y: innerFrame.maxY - 10))
    context.move(to: CGPoint(x: innerFrame.minX + 10, y: center.y)); context.addLine(to: CGPoint(x: innerFrame.maxX - 10, y: center.y))
    context.strokePath(); context.setLineDash(phase: 0, lengths: [])
    let inner: CGFloat = 115, outer: CGFloat = 190, gapStart: CGFloat = 0.12, gapEnd: CGFloat = 0.95
    satinRing(context, center: center, inner: inner, outer: outer, gapStart: gapStart, gapEnd: gapEnd)
    // Edit points: the ring's middle line with square nodes; one is selected and shows its curve handles.
    let middle = (inner + outer) / 2
    context.setStrokeColor(color(0xFFFFFF, 0.9)); context.setLineWidth(4)
    context.addArc(center: center, radius: middle, startAngle: gapEnd, endAngle: gapStart + 2 * .pi, clockwise: false); context.strokePath()
    let nodes: [CGFloat] = [gapEnd, 2.2, 3.4, 4.6, 5.7, gapStart + 2 * .pi]
    for (index, angle) in nodes.enumerated() {
        let p = point(center, angle, middle), selected = index == 2
        if selected {
            // Handles run along the curve's direction at this node.
            let direction = CGPoint(x: -sin(angle), y: cos(angle))
            let a = CGPoint(x: p.x - direction.x * 95, y: p.y - direction.y * 95), b = CGPoint(x: p.x + direction.x * 95, y: p.y + direction.y * 95)
            context.setStrokeColor(color(0x34507A)); context.setLineWidth(4)
            context.move(to: a); context.addLine(to: b); context.strokePath()
            for h in [a, b] { context.addEllipse(in: CGRect(x: h.x - 11, y: h.y - 11, width: 22, height: 22)); context.setFillColor(color(0x34507A)); context.fillPath() }
        }
        let square = CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32)
        context.addRect(square); context.setFillColor(color(selected ? 0x34507A : 0xFFFFFF)); context.fillPath()
        context.addRect(square); context.setStrokeColor(color(0x34507A)); context.setLineWidth(4); context.strokePath()
    }
}

/// Draws the icon into a square context `size` pixels wide. All measurements are on a 1024 grid, scaled to fit.
func draw(_ context: CGContext, size: CGFloat) {
    context.scaleBy(x: size / 1024, y: size / 1024)
    tile(context)
    context.saveGState()
    context.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)); context.clip()
    digitizeDesign(context)
    context.restoreGState()
}

/// Renders the icon at `pixels` wide and returns PNG data.
func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext, size: CGFloat(pixels))
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

// An .iconset folder holds each size at 1x and 2x; iconutil turns it into one .icns file.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try png(1024).write(to: folder.appendingPathComponent("AppIcon-preview.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", folder.appendingPathComponent("AppIcon.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote \(folder.path)/AppIcon.icns" : "iconutil failed")
