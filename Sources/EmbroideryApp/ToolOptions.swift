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
    static func applies(to tool: Tool) -> Bool { NextShapeOptions.shows(tool) || tool == .node || tool == .stitchEdit || tool == .hooping }
    /// True when Properties shows the next shape's choices: with a shape tool on, while nothing is selected or just
    /// after the tool was picked. They then stand in for the selection's properties.
    static func showsNextShape(_ state: EditorState) -> Bool {
        NextShapeOptions.shows(state.tool) && (state.selected == nil || state.toolPicked)
    }
    var body: some View {
        if Self.showsNextShape(state) {
            NextShapeOptions(state: state)
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
                    Text(title(tool, shapes)).font(Theme.heading(18)).lineLimit(1)
                }
            }
            if tool == .basicShape {
                caption("Shape")
                row("Shape", help: "The shape you'll drag out next") {
                    Picker("Shape", selection: setting(\.basicShape)) { ForEach(BasicShape.basicChoices, id: \.self) { Text($0.title).tag($0) } }
                }
                if shapes.basicShape == .polygon {
                    row("Sides", help: "How many sides the polygon has") {
                        stepper("\(shapes.polygonSides)") { Stepper("Sides", value: setting(\.polygonSides), in: ShapeSettings.polygonSideRange) }
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

/// A small drawing of the next shape with the current choices (sides, points, depth or corners), filled when it
/// gets a fill.
private struct ShapePreview: View {
    let shape: BasicShape
    let settings: ShapeSettings
    let filled: Bool
    var body: some View {
        // The outline in a 20 mm box around the middle, drawn 1.6 points per mm with y flipped (designs count y up).
        let nodes = ShapeGeometry.nodes(shape, in: (Point(-10, -10), Point(10, 10)), settings: settings, keepProportions: true)
        let place = { (p: Point) in CGPoint(x: (p.x + 10) * 1.6, y: (10 - p.y) * 1.6) }
        let outline = Path { path in
            guard let first = nodes.first else { return }
            path.move(to: place(first.point))
            for (index, node) in nodes.enumerated() {
                let next = nodes[(index + 1) % nodes.count]
                // A curve where either end has a handle (ellipses, hearts, round corners); a straight edge otherwise.
                if node.outHandle != nil || next.inHandle != nil {
                    path.addCurve(to: place(next.point), control1: place(node.outHandle ?? node.point), control2: place(next.inHandle ?? next.point))
                } else {
                    path.addLine(to: place(next.point))
                }
            }
            path.closeSubpath()
        }
        ZStack {
            if filled { outline.fill(Theme.accent.opacity(0.35)) }
            outline.stroke(Theme.accent, lineWidth: 1.5)
        }
        .frame(width: 32, height: 32)
        .padding(8)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}
