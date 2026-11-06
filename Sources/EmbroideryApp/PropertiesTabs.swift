// The top of Properties for a selected object: a picture of its stitches with its name on it (and, for a fill, its
// style menu and an angle dial), then tabs that split its settings into short pages: its stitches, its underlay, how
// it finishes, and the object itself. The pages' contents are the sections in ProViews.swift.
import SwiftUI
import EmbroideryCore

/// The pages Properties splits an object's settings into.
enum PropertiesTab: String, CaseIterable {
    case stitch, underlay, finish, object

    /// The tabs `object` has: Underlay only when it sews one, Finish for everything but unstitched outlines.
    static func tabs(for object: RunObject) -> [PropertiesTab] {
        var tabs: [PropertiesTab] = [.stitch]
        if object.hasUnderlaySettings { tabs.append(.underlay) }
        if object.kind != .vector { tabs.append(.finish) }
        tabs.append(.object)
        return tabs
    }

    /// The tab's name. The first is named after what the object is: Fill, Satin, Line, Lettering and so on.
    func title(for object: RunObject) -> String {
        switch self {
        case .stitch:
            if object.lettering != nil { return "Lettering" }
            switch object.kind {
            case .fill: return "Fill"
            case .satin: return "Satin"
            case .run: return "Line"
            case .vector: return object.guideFor == nil ? "Outline" : "Guide"
            case .raw: return "Stitches"
            }
        case .underlay: return "Underlay"
        case .finish: return "Finish"
        case .object: return "Object"
        }
    }
}

extension RunObject {
    /// True when the object sews an underlay with settings of its own: satins, and fills other than stipple, motif
    /// and cross stitch (which sew without one).
    var hasUnderlaySettings: Bool {
        kind == .satin || (kind == .fill && ![.stipple, .motif, .crossStitch].contains(settings.fillStyle ?? .tatami))
    }
}

/// The row of tabs: the picked one is lit. Picking one is remembered for the next object selected.
struct PropertiesTabBar: View {
    @ObservedObject var state: EditorState
    let object: RunObject
    var body: some View {
        let tabs = PropertiesTab.tabs(for: object), current = state.shownTab(for: object)
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                let on = tab == current
                Button { state.propertiesTab = tab } label: {
                    Text(tab.title(for: object)).font(Theme.body(10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.card : Color.clear).shadow(color: .black.opacity(on ? 0.15 : 0), radius: 1, y: 1))
                        .foregroundStyle(on ? Theme.accent : Theme.inkSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.divider, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A dial for a fill's row direction: the line across it shows the angle, and dragging turns it (whole degrees, or
/// 15° steps with Shift held). The rows have no front or back, so pointing either way gives the same rows.
struct AngleDial: View {
    let angle: Double
    /// Called with each new angle while dragging; `dragStart` is the same for one whole drag (so it can be one undo step).
    let change: (_ angle: Double, _ dragStart: Date) -> Void
    @State private var dragStart = Date()
    var body: some View {
        let size: CGFloat = 38
        // Degrees count counterclockwise from pointing right, with y up as in the design; the screen's y points down.
        let radians = angle * .pi / 180
        let reach = CGPoint(x: cos(radians) * 14, y: -sin(radians) * 14)
        ZStack {
            Circle().fill(Theme.card.opacity(0.94)).shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            Path { path in
                path.move(to: CGPoint(x: size / 2 - reach.x, y: size / 2 - reach.y))
                path.addLine(to: CGPoint(x: size / 2 + reach.x, y: size / 2 + reach.y))
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle().fill(Theme.accent).frame(width: 7, height: 7).offset(x: reach.x, y: reach.y)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if drag.translation == .zero { dragStart = Date() }   // a new drag
                let dx = drag.location.x - size / 2, dy = size / 2 - drag.location.y
                guard dx * dx + dy * dy > 16 else { return }   // too near the middle to tell a direction
                let step = NSEvent.modifierFlags.contains(.shift) ? 15.0 : 1.0
                change((atan2(dy, dx) * 180 / .pi / step).rounded() * step, dragStart)
            })
        .help("Drag to turn the fill's rows (hold Shift for 15° steps)")
        .accessibilityElement()
        .accessibilityLabel("Fill angle")
        .accessibilityValue("\(Int(angle.rounded())) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(min(180, angle + 1), Date())
            case .decrement: change(max(-180, angle - 1), Date())
            @unknown default: break
            }
        }
    }
}

extension EditorState {
    /// The tab Properties shows for `object`: the one last picked, or its first tab when it doesn't have that one.
    func shownTab(for object: RunObject) -> PropertiesTab {
        PropertiesTab.tabs(for: object).contains(propertiesTab) ? propertiesTab : .stitch
    }
}
