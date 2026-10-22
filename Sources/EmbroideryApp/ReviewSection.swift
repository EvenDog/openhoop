// The Review section at the top of Properties while reviewing the sewing order (View › Review Sewing Order): which
// step this is, how the needle gets here from the step before, and where it starts and ends, with buttons to set them.
import SwiftUI
import EmbroideryCore

struct ReviewSection: View {
    @ObservedObject var state: EditorState
    var body: some View {
        let steps = state.sewingSteps, current = state.reviewStep
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(current.map { "Review · step \($0.index + 1) of \(steps.count)" } ?? "Review").textCase(.uppercase)
                    .font(Theme.caption).tracking(0.8).foregroundStyle(Theme.accent)
                Spacer()
                stepButton(-1, symbol: "chevron.left", label: "Previous step")
                stepButton(1, symbol: "chevron.right", label: "Next step")
            }
            if let current { details(current.index, current.step, in: steps) }
            else { hint("Click an object, or a step in Sewing order, to see how it sews. → starts at the first step.") }
            hint("← → step through it · Esc finishes")
        }
        .padding(10)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
    }

    /// The step's name and what it is, the way here from the step before, and its start and end points.
    @ViewBuilder private func details(_ index: Int, _ step: SewingStep, in steps: [SewingStep]) -> some View {
        let objects = step.objects.compactMap { id in state.design.objects.first { $0.id == id } }
        if let first = objects.first, let last = objects.last {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.stepName(step)).font(Theme.body(15, weight: .bold)).lineLimit(1)
                Text("\(first.lettering == nil ? first.stitchTitle : "Lettering") · \(first.color.name) · \(step.stitches.formatted()) stitches")
                    .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let travel = step.travel {
                    Text("Before it: " + travel.summary(unit: Preferences.shared.unit)).font(Theme.body(12, weight: .semibold))
                    Text("From the end of \(state.stepName(steps[index - 1])) (faint ×) to this start (+)").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("The first step: the machine starts sewing here.").font(Theme.body(12, weight: .semibold))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.controlBorder))
            // Lettering starts on its first letter and ends on its last.
            pointRow(end: false, isSet: first.entry != nil, name: state.stepName(step))
            pointRow(end: true, isSet: last.exit != nil, name: state.stepName(step))
            hint("Drag the + or × on the canvas to move them.")
        }
    }

    /// The Start or End line: its marker, whether it was set or is automatic, and Set… to place it with the Start &
    /// End tool.
    private func pointRow(end: Bool, isSet: Bool, name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: end ? "xmark" : "plus").font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(nsColor: end ? Theme.Canvas.endMarker : Theme.Canvas.startMarker)).frame(width: 14)
            Text(end ? "End" : "Start").font(Theme.body(12, weight: .semibold))
            Text(isSet ? "· set" : "· automatic").font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
            Spacer()
            Button("Set…") {
                AppDelegate.shared.perform(.entryExitTool)
                state.status = end ? "Option-click where \(name) should end sewing · Esc when done" : "Click where \(name) should start sewing · Esc when done"
            }
            .buttonStyle(ThemedButtonStyle())
            .help(end ? "Option-click on the canvas to set where it ends (the Start & End tool)." : "Click on the canvas to set where it starts (the Start & End tool).")
        }
    }

    private func stepButton(_ delta: Int, symbol: String, label: String) -> some View {
        Button { state.stepReview(by: delta) } label: { Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 24, height: 22) }
            .buttonStyle(ThemedButtonStyle(prominent: delta > 0))
            .help(label).accessibilityLabel(label)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

extension SewingTravel {
    /// What happens between two steps, in a few words: "Trim, then 18.6 mm", "Trim and thread change, then 9.0 mm",
    /// "Jump of 6.0 mm, not trimmed", or "Stitched across, 1.0 mm".
    func summary(unit: LengthUnit) -> String {
        let length = unit.text(self.length)
        var events = [trimmed ? "trim" : nil, stopped ? "stop" : nil, colorChange ? "thread change" : nil].compactMap { $0 }
        if events.isEmpty {
            if jumped { return "Jump of \(length), not trimmed" }
            return self.length < 0.05 ? "Carries straight on" : "Stitched across, \(length)"
        }
        let last = events.removeLast()
        let said = events.isEmpty ? last : events.joined(separator: ", ") + " and " + last
        return said.prefix(1).uppercased() + said.dropFirst() + (jumped ? ", then \(length)" : "")
    }
}
