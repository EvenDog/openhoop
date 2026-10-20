// The helper returns verified bytes; the app alone owns the final user-selected destination.
import AppKit
import EmbroideryCore
import Darwin
import UniformTypeIdentifiers

struct ExportRequest: Encodable {
    var version = 1
    var format = "pes"
    var pesVersion: Int
    var plan: StitchPlan
    var hoop: Hoop
}
struct ExportResponse: Decodable {
    var version: Int
    var ok: Bool
    var bytes: Data?
    var stitchCount: Int?
    var width: Double?
    var height: Double?
    var warnings: [String]?
    var error: String?
    var threadCSV: String?
    var format: String?
}

enum Exporter {
    /// Run the bundled converter without a shell or dependencies on the user's Python installation.
    static func prepare(plan: StitchPlan, hoop: Hoop, pesVersion: Int, format: MachineFormat = .pes) throws -> ExportResponse {
        guard let resource = Bundle.main.resourceURL else { throw DesignError.invalid("The application resources are unavailable.") }
        let executable = resource.appendingPathComponent("format-helper/format-helper")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw DesignError.invalid("The format helper is missing. Build the app with scripts/build.sh.") }
        let bytes = try JSONEncoder().encode(ExportRequest(format: format.rawValue, pesVersion: pesVersion, plan: plan, hoop: hoop))
        let result = try runHelper(bytes: bytes, executable: executable)
        let response = try JSONDecoder().decode(ExportResponse.self, from: result)
        guard response.version == 1, response.ok, response.format == format.rawValue, response.bytes != nil else { throw DesignError.invalid(response.error ?? "Invalid export response.") }
        return response
    }
    static func runHelper(bytes: Data, executable: URL) throws -> Data {
        let process = Process(); process.executableURL = executable
        let input = Pipe(), output = Pipe()
        // A failed child must yield a write error, never SIGPIPE-terminate the editor.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw DesignError.invalid("Could not prepare the format helper pipe.") }
        // Stderr cannot back up an unread pipe; diagnostics stay in the response protocol.
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        defer {
            timeout.cancel(); if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close()
        }
        try input.fileHandleForWriting.write(contentsOf: bytes)
        try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !result.isEmpty else { throw DesignError.invalid("The format helper failed or exceeded its 30-second time limit.") }
        return result
    }
}

struct ImportRequest:Encodable {
    var version=1
    var operation="import"
    var format:String
    var bytes:Data
}
struct ImportResponse:Decodable {
    var version:Int
    var ok:Bool
    var format:String?
    var plan:StitchPlan?
    var warnings:[String]?
    var width:Double?
    var height:Double?
    var stitchCount:Int?
    var error:String?
}
extension Exporter {
    static func readMachine(_ data:Data,format:MachineFormat)throws->ImportResponse {
        guard data.count<=5_000_000,let resource=Bundle.main.resourceURL else{throw DesignError.invalid("Choose a machine file under 5 MB.")}
        let executable=resource.appendingPathComponent("format-helper/format-helper")
        let bytes=try JSONEncoder().encode(ImportRequest(format:format.rawValue,bytes:data))
        let response=try JSONDecoder().decode(ImportResponse.self,from:runHelper(bytes:bytes,executable:executable))
        guard response.version==1,response.ok,response.format==format.rawValue,response.plan != nil else{throw DesignError.invalid(response.error ?? "Invalid machine import response.")}
        return response
    }
}

/// The Format popup at the bottom of the export save window: one entry per machine format, PES twice for its two
/// versions. Picking one changes the file name's extension to match. The thread list (a .csv file) uses it too,
/// since the format decides which thread palette the list names.
@MainActor final class ExportFormatPicker: NSObject {
    struct Choice { let id: String; let title: String; let format: MachineFormat; let pesVersion: Int }
    static let choices: [Choice] = [
        Choice(id: "pes6", title: "PES 6 — Brother / Baby Lock", format: .pes, pesVersion: 6),
        Choice(id: "pes1", title: "PES 1 — older Brother machines", format: .pes, pesVersion: 1),
        Choice(id: "pec", title: "PEC — Brother", format: .pec, pesVersion: 6),
        Choice(id: "dst", title: "DST — Tajima", format: .dst, pesVersion: 6),
        Choice(id: "exp", title: "EXP — Melco / Bernina", format: .exp, pesVersion: 6),
        Choice(id: "jef", title: "JEF — Janome", format: .jef, pesVersion: 6),
        Choice(id: "vp3", title: "VP3 — Husqvarna / Pfaff", format: .vp3, pesVersion: 6),
        Choice(id: "xxx", title: "XXX — Singer", format: .xxx, pesVersion: 6),
    ]
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shown: [Choice]
    private weak var panel: NSSavePanel?
    private let threadListOnly: Bool
    /// Fills the popup (the thread list needs only one PES entry) and selects `remembered`, the id last exported
    /// with, or PES 6.
    init(panel: NSSavePanel, threadListOnly: Bool, remembered: String?) {
        self.panel = panel; self.threadListOnly = threadListOnly
        shown = threadListOnly ? Self.choices.filter { $0.id != "pes1" } : Self.choices
        super.init()
        popup.addItems(withTitles: shown.map(\.title))
        popup.selectItem(at: shown.firstIndex { $0.id == remembered } ?? 0)
        popup.target = self; popup.action = #selector(changed)
        changed()
    }
    var choice: Choice { shown[max(0, popup.indexOfSelectedItem)] }
    /// "Format:" and the popup, laid out for the save window's accessory area.
    var accessoryView: NSView {
        let row = NSStackView(views: [NSTextField(labelWithString: "Format:"), popup])
        row.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return row
    }
    /// Gives the file name the chosen format's extension (the thread list stays a .csv file).
    @objc private func changed() {
        guard let panel else { return }
        let ext = threadListOnly ? "csv" : choice.format.rawValue
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = (base.isEmpty ? "Design" : base) + "." + ext
    }
}
