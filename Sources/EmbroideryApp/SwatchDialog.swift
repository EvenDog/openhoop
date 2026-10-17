// The Make Test Swatches dialog: pick one setting of the selected object and the values to try (a start, a step and
// how many), see the swatches laid out in the hoop, then open them as a new design to sew and compare.
import SwiftUI
import EmbroideryCore

extension GuidedDialog {
    /// The Make Test Swatches dialog for `object`: returns the swatch design, or nil if the person cancelled.
    static func testSwatches(_ object: RunObject, hoop: Hoop) -> Design? {
        var made: Design?
        let confirmed = run(width: 760) { finish in
            SwatchView(object: object, hoop: hoop) { design in made = design; finish(design != nil) }
        }
        return confirmed ? made : nil
    }
}

struct SwatchView: View {
    let object: RunObject
    let hoop: Hoop
    /// Called with the swatch design (nil for Cancel).
    let done: (Design?) -> Void
    @State private var setting: SwatchSetting
    @State private var start: Double
    @State private var step: Double
    @State private var count = 5

    init(object: RunObject, hoop: Hoop, done: @escaping (Design?) -> Void) {
        self.object = object; self.hoop = hoop; self.done = done
        let setting = SwatchSetting.available(for: object.kind).first ?? .stitchLength
        _setting = State(initialValue: setting)
        _start = State(initialValue: setting.value(of: object))
        _step = State(initialValue: setting.step)
    }

    private var values: [Double] { TestSwatches.values(start: start, step: step, count: count) }
    private var built: Result<Design, Error> { Result { try TestSwatches.design(object, setting: setting, values: values, hoop: hoop) } }

    var body: some View {
        DialogFrame(eyebrow: "Test swatches", title: "Make test swatches",
                    subtitle: "Copies of “\(object.name)” in a new design, each with one setting stepped, so one hoop sews them side by side. Each copy is named after its value; they sew in order, top left first.",
                    primary: "Make Swatches",
                    finish: { make in
                        if !make { done(nil) } else if case .success(let design) = built { done(design) }
                    }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Setting", selection: $setting) {
                        ForEach(SwatchSetting.available(for: object.kind), id: \.self) { Text($0.title).tag($0) }
                    }.font(Theme.body(13, weight: .semibold))
                    .onChange(of: setting) { _, new in start = new.value(of: object); step = new.step }
                    numberRow("Start at", value: $start)
                    numberRow("Step", value: $step)
                    Stepper(value: $count, in: 2...25) { Text("Swatches: \(count)").font(Theme.body(13, weight: .semibold)) }
                    Text(values.map(setting.label).joined(separator: " · "))
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    Text("This object now: \(setting.label(setting.value(of: object))).")
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSecondary)
                }.frame(width: 280, alignment: .leading)
                ZStack {
                    Theme.ground
                    switch built {
                    case .success(let design): StitchThumbnail(objects: design.objects, label: "Preview of the swatches in the hoop")
                    case .failure(let error): Text(error.localizedDescription).font(Theme.body(12)).foregroundStyle(.orange).padding()
                    }
                }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    /// A labeled number field with the setting's unit after it.
    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(Theme.body(13, weight: .semibold)); Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 80)
            Text(setting.unit).font(Theme.body(12)).foregroundStyle(Theme.inkSecondary).frame(width: 24, alignment: .leading)
        }
    }
}
