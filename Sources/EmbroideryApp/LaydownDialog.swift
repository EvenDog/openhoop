// The Laydown dialog: choose how far the laydown reaches past the design, how open it is, its angle,
// one or two layers and its thread, see it under the design, then add it.
import SwiftUI
import EmbroideryCore

extension GuidedDialog {
    /// The settings used last, so the next laydown starts from them.
    static var lastLaydown = LaydownSettings()
    /// The Laydown dialog for laydown under the objects in `ids` (the whole design if empty): returns the laydown
    /// fills, or nil if the person cancelled.
    static func laydown(_ design: Design, under ids: Set<UUID>, color: ThreadColor) -> [RunObject]? {
        var made: [RunObject] = []   // the dialog's closure writes the laydown here before it closes
        let confirmed = run(width: 760) { finish in
            LaydownView(design: design, ids: ids, settings: lastLaydown, color: color) { settings, laydown in
                lastLaydown = settings; made = laydown ?? []; finish(laydown?.isEmpty == false)
            }
        }
        return confirmed ? made : nil
    }
}

struct LaydownView: View {
    let design: Design
    let ids: Set<UUID>
    @State var settings: LaydownSettings
    @State var color: ThreadColor
    /// Called with the settings and the laydown (nil for Cancel).
    let done: (LaydownSettings, [RunObject]?) -> Void
    /// The latest laydown, or a problem; nil while it's being worked out.
    @State private var built: Result<[RunObject], Error>?

    /// The threads to choose from: the current one, then the design's own in sewing order.
    private var threads: [ThreadColor] {
        var list = [color]
        for object in design.objects where !list.contains(object.color) { list.append(object.color) }
        return list
    }
    private var covered: [RunObject] { design.objects.filter { (ids.isEmpty || ids.contains($0.id)) && $0.kind != .vector } }

    var body: some View {
        DialogFrame(eyebrow: "Laydown", title: "Add a laydown",
                    subtitle: "A light, open fill sewn first under \(ids.isEmpty ? "the whole design" : "the selection"). It flattens the pile of towels, fleece and velvet so the stitches on top don't sink in.",
                    primary: "Add Laydown",
                    finish: { add in
                        if !add { done(settings, nil) } else if case .success(let laydown)? = built, !laydown.isEmpty { done(settings, laydown) }
                    }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    stepper("Reaches past the edge", value: $settings.offset, in: LaydownSettings.offsets, step: 0.5)
                    stepper("Row spacing", value: $settings.spacing, in: LaydownSettings.spacings, step: 0.5)
                    stepper("Stitch length", value: $settings.stitchLength, in: LaydownSettings.stitchLengths, step: 0.5)
                    Stepper(value: $settings.angle, in: -90...180, step: 15) {
                        Text("Angle: \(settings.angle.formatted())°").font(Theme.body(13, weight: .semibold))
                    }
                    Picker("Layers", selection: $settings.layers) {
                        Text("One").tag(1); Text("Two, crossed").tag(2)
                    }.pickerStyle(.segmented).font(Theme.body(13, weight: .semibold))
                    Picker("Thread", selection: $color) {
                        ForEach(threads, id: \.self) { thread in Text(thread.name).tag(thread) }
                    }.font(Theme.body(13, weight: .semibold))
                    Text("Two crossed layers pin deep pile both ways; one is enough for low pile. A thread matching the fabric hides best.")
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 280, alignment: .leading)
                ZStack {
                    Theme.ground
                    switch built {
                    case .success(let laydown)?: StitchThumbnail(objects: laydown + covered, label: "Preview of the laydown under the design")
                    case .failure(let error)?: Text(error.localizedDescription).font(Theme.body(12)).foregroundStyle(.orange).padding()
                    case nil: ProgressView().controlSize(.small)
                    }
                }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        // Work the laydown out again in the background whenever a setting changes.
        .task(id: [settings.offset, settings.spacing, settings.stitchLength, settings.angle, Double(settings.layers), Double(color.hex)]) {
            built = nil
            let design = design, ids = ids, settings = settings, color = color
            let result = await Task.detached(priority: .userInitiated) { Result { try design.laydown(under: ids, settings: settings, color: color) } }.value
            if !Task.isCancelled { built = result }
        }
    }
    private func stepper(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) -> some View {
        Stepper(value: value, in: range, step: step) {
            Text("\(label): \(value.wrappedValue.formatted()) mm").font(Theme.body(13, weight: .semibold))
        }
    }
}
