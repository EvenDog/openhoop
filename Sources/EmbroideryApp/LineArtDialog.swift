// The Line Art dialog: pick one of the ready-made running-stitch drawings (LineArt.swift) from a grid of pictures,
// choose its size and stitch, see it, then add it to the design as one group.
import SwiftUI
import EmbroideryCore

/// What the Line Art dialog chose: the drawing, how wide it is (mm), and whether it's sewn as bean stitch.
struct LineArtChoice: Equatable {
    var design: LineArtDesign = .flower
    var size = LineArt.defaultSize
    var bean = false
}

extension GuidedDialog {
    /// The choices used last, so the dialog opens where it was left.
    static var lastLineArt = LineArtChoice()
    /// The Line Art dialog: returns the choice, or nil if the person cancelled.
    static func lineArt(color: ThreadColor) -> LineArtChoice? {
        var made: LineArtChoice?   // the dialog's closure writes the choice here before it closes
        let confirmed = run(width: 780) { finish in
            LineArtView(choice: lastLineArt, color: color) { choice in
                if let choice { lastLineArt = choice }
                made = choice; finish(choice != nil)
            }
        }
        return confirmed ? made : nil
    }
}

struct LineArtView: View {
    @State var choice: LineArtChoice
    let color: ThreadColor
    /// Called with the choice (nil for Cancel).
    let done: (LineArtChoice?) -> Void

    /// Each drawing's lines at the default size, for the grid's pictures: worked out once, the first time the dialog
    /// opens (joining a drawing's strokes takes a moment), and kept until the app quits.
    @MainActor private static var pictures: [LineArtDesign: [RunObject]] = [:]
    private func picture(_ design: LineArtDesign) -> [RunObject] {
        if let made = Self.pictures[design] { return made }
        let made = LineArt.objects(design, size: LineArt.defaultSize, bean: false, color: color)
        Self.pictures[design] = made
        return made
    }
    /// The chosen drawing at the chosen size, as it will be added.
    private var preview: [RunObject] { LineArt.objects(choice.design, size: choice.size, bean: choice.bean, color: color) }

    var body: some View {
        DialogFrame(eyebrow: "Line art", title: "Add line art",
                    subtitle: "A ready-made drawing in running stitch: dividers, a frame, flowers and more. Touching lines are joined, so most sew in one go without trims.",
                    primary: "Add Line Art", finish: { add in done(add ? choice : nil) }) {
            HStack(alignment: .top, spacing: 20) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(92), spacing: 8), count: 4), spacing: 8) {
                    ForEach(LineArtDesign.allCases, id: \.self) { design in tile(design) }
                }
                .frame(width: 400, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 12) {
                    let lines = preview
                    ZStack {
                        Theme.ground
                        StitchThumbnail(objects: lines, label: "Preview of the \(choice.design.title.lowercased())")
                    }
                    .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14))
                    Text(sizeNote(lines)).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    Stepper(value: $choice.size, in: LineArt.sizes, step: 5) {
                        Text("Width: \(Preferences.shared.unit.short(choice.size))").font(Theme.body(13, weight: .semibold))
                    }
                    Picker("Stitch", selection: $choice.bean) {
                        Text("Running").tag(false)
                        Text("Bean (triple)").tag(true)
                    }
                    .pickerStyle(.segmented).font(Theme.body(13, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: color.nsColor)).frame(width: 12, height: 12)
                        Text("Sews in \(color.name), the current thread.").foregroundStyle(Theme.inkSecondary)
                    }.font(Theme.body(12))
                }
            }
        }
    }

    /// One drawing in the grid: its picture and name, outlined when it's the one chosen.
    private func tile(_ design: LineArtDesign) -> some View {
        Button { choice.design = design } label: {
            VStack(spacing: 3) {
                StitchThumbnail(objects: picture(design), label: design.title, padding: 8).frame(width: 84, height: 70)
                Text(design.title).font(Theme.body(11)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(choice.design == design ? Theme.accentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(choice.design == design ? Theme.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(design.title)
        .accessibilityValue(choice.design == design ? "Chosen" : "")
    }

    /// How big the drawing comes out, and how many separate lines (each one more jump) it has.
    private func sizeNote(_ lines: [RunObject]) -> String {
        let points = lines.flatMap { $0.outlinePaths.flatMap { $0 } }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return "" }
        let unit = Preferences.shared.unit
        let parts = lines.count == 1 ? "one continuous line" : "\(lines.count) lines (\(lines.count - 1) jump\(lines.count == 2 ? "" : "s"))"
        return "About \(unit.short((maxX - minX).rounded())) × \(unit.short((maxY - minY).rounded())), \(parts)."
    }
}
