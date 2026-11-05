// The current tool's choices, shown at the top of the Properties panel: the next shape's shape and stitches (shape
// tools, while nothing is selected), the selected point's type (Edit Nodes), and how Edit Stitches works. They used to
// float in a bar over the canvas.
import SwiftUI
import EmbroideryCore

/// The tool's choices at the top of Properties. Shows nothing for tools
/// without choices.
struct ToolOptions: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// True for the tools whose choices live in Properties, so picking one opens the panel if it's closed.
    static func applies(to tool: Tool) -> Bool { NextShapeOptions.shows(tool) || tool == .node || tool == .stitchEdit || tool == .hooping || tool == .wreath || tool == .scatter || tool == .paintStitches }
    /// True when Properties shows the next shape's choices: with a shape tool on, while nothing is selected or just
    /// after the tool was picked. They then stand in for the selection's properties.
    static func showsNextShape(_ state: EditorState) -> Bool {
        NextShapeOptions.shows(state.tool) && (state.selected == nil || state.toolPicked)
    }
    var body: some View {
        if Self.showsNextShape(state) {
            NextShapeOptions(state: state)
        } else if state.tool == .wreath {
            WreathOptions(state: state)
        } else if state.tool == .scatter {
            ScatterOptions(state: state)
        } else if state.tool == .paintStitches {
            StitchPaintOptions(state: state)
        } else if state.tool == .hooping {
            HoopingOptions(state: state)   // HoopingOptions.swift
        } else if state.tool == .node, let node = state.selectedPathNode {
            // The selected point's type, so it can be seen and switched without knowing the right-click or the key.
            VStack(alignment: .leading, spacing: 6) {
                ToolCaption(text: "POINT")
                Picker("Point", selection: Binding(get: { node.smooth }, set: { state.setSelectedNode(smooth: $0) })) {
                    Text("Corner").tag(false)
                    Text("Smooth").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("A corner turns sharply; a smooth point curves through. \(preferences.key(.play)) or a right-click switches it too.")
                Text("\(preferences.key(.play)) or a right-click switches it").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
            }
            Divider()
        } else if state.tool == .stitchEdit {
            let key = preferences.key
            VStack(alignment: .leading, spacing: 6) {
                ToolCaption(text: "EDIT STITCHES")
                Text("Drag needle points to move them · ⌥-click a stitch adds one · \(key(.delete)) removes")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                Button("Done") { AppDelegate.shared.perform(.done) }.controlSize(.small).help("Leave Edit Stitches (\(key(.done)))")
            }
            Divider()
        }
    }
}

/// Wreath's choices: how many copies go round and whether every other one is mirrored, then Apply. The canvas shows the
/// result as dashed outlines while these change.
struct WreathOptions: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolCaption(text: state.wreathMirrored ? "KALEIDOSCOPE" : "WREATH")
            HStack(spacing: 8) {
                Text("Copies")
                Spacer(minLength: 8)
                Text("\(state.wreathCopies)").monospacedDigit()
                // A kaleidoscope steps by 2, so its mirrored copies always pair up.
                Stepper("Copies", value: $state.wreathCopies, in: Design.wreathCopies, step: state.wreathMirrored ? 2 : 1).labelsHidden()
            }
            .help("How many go round the circle, counting the selection itself")
            Toggle("Mirror every other (kaleidoscope)", isOn: $state.wreathMirrored)
                .help("Every other copy is a mirror image, so neighbours face each other in pairs")
            HStack {
                Button("Apply") { state.applyWreath() }.disabled(state.wreathCenter == nil)
                    .help("Make the wreath (\(preferences.key(.finishPath)))")
                Button("Cancel") { AppDelegate.shared.perform(.done) }.help("Leave the wreath unmade (\(preferences.key(.done)))")
            }
            .controlSize(.small)
            Text(state.wreathCenter == nil ? "Click the center on the canvas." : "Click again to move the center.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.body(12))
        Divider()
    }
}

extension PatchStitch {
    var title: String { switch self { case .tatami: "Tatami"; case .satin: "Satin"; case .line: "Line"; case .leaveOut: "Leave out" } }
    var hint: String {
        switch self {
        case .tatami: "Rows of fill stitches, for wide areas"
        case .satin: "Smooth stitches across, for parts up to about 8 mm; wider ones get split stitches"
        case .line: "A triple running stitch down a thin part's middle, or round a wider part's edge"
        case .leaveOut: "Not stitched, so the fabric shows"
        }
    }
    /// Its color on the canvas and in Properties: tatami denim, satin terracotta, line green, leave out grey.
    var tint: NSColor {
        switch self {
        case .tatami: NSColor(srgbRed: 0.20, green: 0.38, blue: 0.70, alpha: 1)
        case .satin: NSColor(srgbRed: 0.85, green: 0.38, blue: 0.16, alpha: 1)
        case .line: NSColor(srgbRed: 0.18, green: 0.60, blue: 0.32, alpha: 1)
        case .leaveOut: NSColor(white: 0.5, alpha: 1)
        }
    }
}

/// Paint Stitches' choices: the brush (each with how many parts have its stitch), how many were set by hand with a
/// way back to auto-digitize's choices, then Add Stitches or Cancel. The canvas tints each part by its stitch.
struct StitchPaintOptions: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        let count = state.stitchPaint?.patches.count ?? 0
        let counts = Dictionary(grouping: (0..<count).map(state.paintedStitch), by: { $0 }).mapValues(\.count)
        VStack(alignment: .leading, spacing: 8) {
            ToolCaption(text: "PAINT STITCHES")
            Text("Pick a stitch, then click parts on the canvas, or drag across several, to give them that stitch.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            ForEach(PatchStitch.allCases, id: \.self) { stitch in
                let picked = state.paintBrush == stitch
                Button { state.paintBrush = stitch } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: stitch.tint).opacity(stitch == .leaveOut ? 0 : 0.6))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: stitch.tint), style: StrokeStyle(lineWidth: 1.5, dash: stitch == .leaveOut ? [3, 2] : [])))
                            .frame(width: 16, height: 16)
                        Text(stitch.title).font(Theme.body(12, weight: picked ? .bold : .regular))
                        Spacer(minLength: 8)
                        Text("\(counts[stitch] ?? 0)").monospacedDigit().foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 6).fill(picked ? Theme.accent.opacity(0.15) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(picked ? Theme.accent : .clear))
                }
                .buttonStyle(.plain).help(stitch.hint)
                .accessibilityLabel("\(stitch.title), \(counts[stitch] ?? 0) parts").accessibilityAddTraits(picked ? .isSelected : [])
            }
            Text(state.paintBrush.hint).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(state.paintChoices.isEmpty ? "All as auto-digitize chose" : "\(state.paintChoices.count) set by hand")
                    .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                Button("Reset") { state.paintChoices = state.paintStart }.disabled(state.paintChoices == state.paintStart || state.paintBuilding)
                    .help("Put back the stitches the parts had when you came from the Auto-Digitize window")
            }
            .controlSize(.small)
            HStack {
                Button("Add Stitches") { state.applyStitchPaint() }.disabled(state.paintBuilding)
                    .help("Make the stitches and add them over your image (\(preferences.key(.finishPath)))")
                Button("Cancel") { AppDelegate.shared.perform(.done) }.help("Add nothing (\(preferences.key(.done)))")
                if state.paintBuilding { ProgressView().controlSize(.small) }
            }
            .controlSize(.small)
        }
        .font(Theme.body(12))
        Divider()
    }
}

/// Scatter's choices: how many copies, their smallest and largest size, the gap between them, whether they turn, and
/// Shuffle for another random layout, then Apply. The canvas shows the copies dashed until then.
struct ScatterOptions: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        let s = state.scatterSettings, placed = state.scatterPreview?.placed
        VStack(alignment: .leading, spacing: 8) {
            ToolCaption(text: "SCATTER")
            stepper("Copies", "\(s.copies)", value: $state.scatterSettings.copies, in: ScatterSettings.copyRange, step: 1, help: "How many to scatter; fewer go in when no more fit")
            stepper("Smallest", "\(Int(s.smallest))%", value: Binding(get: { s.smallest }, set: { state.scatterSettings.smallest = $0; state.scatterSettings.largest = max(state.scatterSettings.largest, $0) }),
                    in: ScatterSettings.sizeRange, step: 10, help: "The smallest a copy can be, as a share of the original")
            stepper("Largest", "\(Int(s.largest))%", value: Binding(get: { s.largest }, set: { state.scatterSettings.largest = $0; state.scatterSettings.smallest = min(state.scatterSettings.smallest, $0) }),
                    in: ScatterSettings.sizeRange, step: 10, help: "The largest a copy can be, as a share of the original")
            stepper("Gap", preferences.unit.short(s.gap), value: $state.scatterSettings.gap, in: ScatterSettings.gapRange, step: 0.5, help: "The least space between copies, and between a copy and the shape's edge")
            Toggle("Turn at random", isOn: $state.scatterSettings.turns).help("Each copy turned any which way; off, they all stay upright")
            HStack {
                Button("Shuffle") { state.scatterSettings.seed += 1 }.help("Another random layout with the same settings")
                Button("Apply") { state.applyScatter() }.disabled(placed == nil).help("Make it (\(preferences.key(.finishPath)))")
                Button("Cancel") { AppDelegate.shared.perform(.done) }.help("Leave it unmade (\(preferences.key(.done)))")
            }
            .controlSize(.small)
            Text(placed.map { $0 < s.copies ? "Only \($0) of \(s.copies) fit. Make them smaller or the gap narrower for more." : "All \(s.copies) fit." } ?? "None fit. Make them smaller, or the gap narrower.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.body(12))
        Divider()
    }
    /// A labeled value with a stepper beside it.
    private func stepper<V: Strideable>(_ title: String, _ shown: String, value: Binding<V>, in range: ClosedRange<V>, step: V.Stride, help: String) -> some View {
        HStack(spacing: 8) {
            Text(title); Spacer(minLength: 8); Text(shown).monospacedDigit()
            Stepper(title, value: value, in: range, step: step).labelsHidden()
        }
        .help(help)
    }
}

/// A small accent caption over a tool's choices, like "NEXT SHAPE".
struct ToolCaption: View {
    let text: String
    var body: some View { Text(text).font(Theme.caption).tracking(0.8).foregroundStyle(Theme.accent).lineLimit(1) }
}

/// The choices for the next shape: the shape itself (the Basic Shapes tool's star, polygon, heart or arrow, with its
/// points or sides; the rectangle's corners) and its stitches (for closed shapes, a fill and an outline). Changes are
/// saved straight away and shared by every design window.
struct NextShapeOptions: View {
    @ObservedObject var state: EditorState
    @ObservedObject var preferences = Preferences.shared
    /// True for the tools that have next-shape choices.
    static func shows(_ tool: Tool) -> Bool { tool.isShapeTool || tool.dragsShape }
    var body: some View {
        let tool = state.tool, shapes = preferences.shapes
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let shape = dragged(tool, shapes) {
                    ShapePreview(shape: shape, settings: shapes, filled: shapes.closedFill != nil)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ToolCaption(text: "NEXT SHAPE")
                    Text(title(tool, shapes)).font(Theme.heading(18)).lineLimit(1).minimumScaleFactor(0.7)   // long names shrink to fit
                }
            }
            if tool == .basicShape {
                BasicShapeGrid(picked: shapes.basicShape, settings: shapes, filled: shapes.closedFill != nil) { setting(\.basicShape).wrappedValue = $0 }
                if shapes.basicShape == .polygon {
                    row("Sides", help: "How many sides the polygon has") {
                        stepper("\(shapes.polygonSides)") { Stepper("Sides", value: setting(\.polygonSides), in: ShapeSettings.polygonSideRange) }
                    }
                }
                if !shapes.basicShape.isFrame {
                    row("Open middle", help: "Leave the shape's middle open, so only a band round its edge is sewn (a frame)") {
                        Toggle("Open middle", isOn: setting(\.openMiddle)).toggleStyle(.checkbox)
                    }
                }
                if shapes.basicShape.isFrame || shapes.openMiddle {
                    row("Band", help: "How wide the frame's band is, from its outside edge in to the open middle") {
                        stepper(preferences.unit.short(shapes.frameWidth)) { Stepper("Band", value: setting(\.frameWidth), in: ShapeSettings.frameWidthRange, step: 0.5) }
                    }
                }
                if shapes.basicShape == .star {
                    row("Points", help: "How many points the star has") {
                        stepper("\(shapes.starPoints)") { Stepper("Points", value: setting(\.starPoints), in: ShapeSettings.starPointRange) }
                    }
                    row("Depth", help: "How far in the star's inner corners go") {
                        Picker("Depth", selection: setting(\.starInner)) {
                            Text("Shallow points").tag(0.65); Text("Medium points").tag(0.5); Text("Deep points").tag(0.35)
                        }
                    }
                }
            }
            if tool == .rectangle {
                row("Corners", help: "How round the corners are (0 is square)") {
                    stepper(preferences.unit.short(shapes.cornerRadius)) { Stepper("Corners", value: setting(\.cornerRadius), in: ShapeSettings.cornerRadiusRange, step: 0.5) }
                }
            }
            caption("Stitches")
            if tool.makesOpenShape {
                row("Stitch", help: "The stitch the next open shape gets. Change it later in Properties.") {
                    NewLineStitchMenu(label: "Stitch", current: shapes.openStitch, color: state.currentColor) { value in
                        if let value { setting(\.openStitch).wrappedValue = value }
                    }.frame(width: menuWidth)
                }
            } else {
                // Both are optional: nil is "None".
                row("Fill", help: "The fill the next shape gets, or None for just an outline. Change it later in Properties.") {
                    NewShapeFillMenu(current: shapes.closedFill, color: state.currentColor) { setting(\.closedFill).wrappedValue = $0 }
                        .frame(width: menuWidth)
                }
                row("Outline", help: "The stitch sewn along the next shape's edge, after its fill. With a fill, the two are grouped.") {
                    NewLineStitchMenu(label: "Outline", current: shapes.closedOutline, offersNone: true, color: state.currentColor) { setting(\.closedOutline).wrappedValue = $0 }
                        .frame(width: menuWidth)
                }
            }
            if (tool.makesOpenShape ? shapes.openStitch : shapes.closedOutline) == .satin {
                let width = preferences.data.satinLineWidth ?? SatinLine.defaultWidth
                row("Satin width", help: "How wide the satin is, centered on the line") {
                    stepper("\(width.formatted()) mm") { Stepper("Satin width", value: Binding(get: { width }, set: { preferences.data.satinLineWidth = $0; preferences.save() }), in: SatinLine.widths, step: 0.5) }
                }
            }
            // How to draw it (the same hint as the tool strip).
            let hint = ToolStrip.hint(for: state)
            Text(hint.how.prefix(1).uppercased() + hint.how.dropFirst())
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 8))
        }
        .font(Theme.body(12))
    }
    /// How wide the stitch picture menus are, as in Properties.
    private var menuWidth: CGFloat { 120 }
    /// The shape a drag tool draws, for the preview; nil for the tools that trace a path.
    private func dragged(_ tool: Tool, _ shapes: ShapeSettings) -> BasicShape? {
        switch tool {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .basicShape: return shapes.basicShape
        default: return nil
        }
    }
    /// The heading: what the next shape is.
    private func title(_ tool: Tool, _ shapes: ShapeSettings) -> String {
        switch tool {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .basicShape: return shapes.basicShape.title
        case .openShape: return "Open shape"
        case .closedShape: return "Closed shape"
        case .freehandOpen: return "Freehand line"
        case .freehandClosed: return "Freehand shape"
        default: return "Shape"
        }
    }
    private func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.caption).tracking(0.8).foregroundStyle(Theme.inkSecondary).padding(.top, 2)
    }
    /// One labelled row: the name on the left, the control on the right.
    private func row<Control: View>(_ title: String, help: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            control().labelsHidden().pickerStyle(.menu).fixedSize()
        }
        .help(help)
    }
    /// A stepper with its value written beside it (the row hides controls' own labels).
    private func stepper<Control: View>(_ value: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: 4) { Text(value).monospacedDigit(); control() }
    }
    /// A two-way link between a control and one of the saved shape settings.
    private func setting<Value>(_ key: WritableKeyPath<ShapeSettings, Value>) -> Binding<Value> {
        Binding(get: { preferences.shapes[keyPath: key] }, set: { value in preferences.updateShapes { $0[keyPath: key] = value } })
    }
}

/// Every shape the Basic Shapes tool draws, as small pictures in their groups (Geometric, Badges & labels, Nature,
/// Objects). Clicking one picks it; the picked one is highlighted, and hovering shows its name.
private struct BasicShapeGrid: View {
    let picked: BasicShape
    let settings: ShapeSettings
    let filled: Bool
    let pick: (BasicShape) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(BasicShape.groups, id: \.title) { group in
                Text(group.title.uppercased()).font(Theme.caption).tracking(0.8).foregroundStyle(Theme.inkSecondary).padding(.top, 2)
                FlowLayout(spacing: 4) {
                    ForEach(group.shapes, id: \.self) { shape in
                        Button { pick(shape) } label: {
                            ShapeDrawing(shape: shape, settings: settings, filled: filled, size: 22)
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(shape == picked ? Theme.accentSoft : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(shape == picked ? Theme.accent : Theme.controlBorder))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(shape.title)
                        .accessibilityLabel(shape.title)
                        .accessibilityAddTraits(shape == picked ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// A small drawing of the next shape with the current choices (sides, points, depth or corners), filled when it
/// gets a fill.
private struct ShapePreview: View {
    let shape: BasicShape
    let settings: ShapeSettings
    let filled: Bool
    var body: some View {
        ShapeDrawing(shape: shape, settings: settings, filled: filled, size: 32)
            .padding(8)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

/// `shape`'s outline drawn `size` points square, kept in proportion, and filled when it gets a fill. A frame shows
/// its open middle, with a band 3 mm wide of the 20 mm drawing (its real width depends on how big it's dragged).
private struct ShapeDrawing: View {
    let shape: BasicShape
    let settings: ShapeSettings
    let filled: Bool
    let size: CGFloat
    var body: some View {
        // The outline in a 20 mm box around the middle, scaled to `size` with y flipped (designs count y up).
        let nodes = ShapeGeometry.nodes(shape, in: (Point(-10, -10), Point(10, 10)), settings: settings, keepProportions: true)
        let holes = ShapeGeometry.holes(shape, around: nodes, settings: { var drawn = settings; drawn.frameWidth = 3; return drawn }())
        let scale = Double(size) / 20
        let place = { (p: Point) in CGPoint(x: (p.x + 10) * scale, y: (10 - p.y) * scale) }
        // The outside edge, then each hole, in one path.
        let outline = Path { path in
            for ring in [nodes] + holes {
                guard let first = ring.first else { continue }
                path.move(to: place(first.point))
                for (index, node) in ring.enumerated() {
                    let next = ring[(index + 1) % ring.count]
                    // A curve where either end has a handle (ellipses, hearts, round corners); a straight edge otherwise.
                    if node.outHandle != nil || next.inHandle != nil {
                        path.addCurve(to: place(next.point), control1: place(node.outHandle ?? node.point), control2: place(next.inHandle ?? next.point))
                    } else {
                        path.addLine(to: place(next.point))
                    }
                }
                path.closeSubpath()
            }
        }
        ZStack {
            // Even-odd filling leaves a hole unfilled (`SwiftUI.` because the design's fill styles share the name).
            if filled { outline.fill(Theme.accent.opacity(0.35), style: SwiftUI.FillStyle(eoFill: true)) }
            outline.stroke(Theme.accent, lineWidth: size < 30 ? 1.2 : 1.5)
        }
        .frame(width: size, height: size)
    }
}
