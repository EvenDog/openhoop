// Properties with nothing selected: the whole design. On top, its figures (size, stitches, thread steps, trims and
// stops, sewing time) and whether it fits the sewing area; below, the design's own settings (fabric, sewing area,
// holding the fabric, trims), the same ones the Design panel shows, so they can be changed from either place.
import SwiftUI
import EmbroideryCore

extension InspectorPanel {
    @ViewBuilder var designOverview: some View {
        let summary = state.summary
        VStack(alignment: .leading, spacing: 2) {
            // The file's name without ".stitchproj" (an unsaved design shows its window title, such as "Untitled").
            Text(state.document.map { $0.fileURL?.deletingPathExtension().lastPathComponent ?? $0.displayName } ?? "This design")
                .font(Theme.heading(pro ? 15 : 18)).lineLimit(2)
            Text("The whole design · click an object to edit it").font(Theme.body(11)).foregroundStyle(Theme.inkSecondary)
        }
        if summary.stitchCount == 0 {
            Text("No stitches yet. Draw a shape or add lettering, and its size, stitch count and sewing time show here.")
                .font(Theme.body(11)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        } else {
            let speed = preferences.data.machineSpeed ?? ProductionSummary.defaultSpeed
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: pro ? 6 : 9) {
                GridRow {
                    figure(preferences.unit.size(summary.width, summary.height), "design size")
                    figure(summary.stitchCount.formatted(), "stitches")
                }
                GridRow {
                    figure(summary.steps.count.formatted(), "thread step\(summary.steps.count == 1 ? "" : "s") · \(ProStats.count(summary.trims, "trim")) · \(ProStats.count(summary.stops, "stop"))")
                    figure("≈ \(ProductionSummary.duration(summary.sewingMinutes(speed: speed)))", "sewing time")
                        .help("At \(speed) stitches per minute (set on the production worksheet), plus time for trims, thread changes and stops")
                }
            }
            hoopCheck
        }
        sectionDivider
        designSection
    }

    /// One figure: the number large, what it counts small underneath.
    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: pro ? 12 : 13, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
            Text(caption).font(Theme.body(10)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
        }
    }

    /// Whether every stitch lands inside the sewing area: the stitch generator warns when one doesn't (AreaEngine.swift).
    @ViewBuilder private var hoopCheck: some View {
        let hoop = preferences.unit.size(state.design.hoop.width, state.design.hoop.height, decimals: preferences.unit == .inches ? 1 : 0)
        if state.plan.warnings.contains(where: { $0.contains("beyond the sewing area") }) {
            Label("Some stitches are outside the \(hoop) sewing area", systemImage: "exclamationmark.circle.fill")
                .font(Theme.body(11, weight: .semibold)).foregroundStyle(Color.orange)
        } else {
            Label("Fits the \(hoop) sewing area", systemImage: "checkmark.circle.fill")
                .font(Theme.body(11, weight: .semibold)).foregroundStyle(Theme.success)
        }
    }
}
