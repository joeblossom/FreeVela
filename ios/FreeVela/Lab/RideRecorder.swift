import Combine
import SwiftUI

/// Records speed, throttle and controls from every STATE read while on, for tuning the motor.
/// Reads STATE more often while recording. Needs FreeVela firmware with `motor-tune` for the throttle columns.
@MainActor
final class RideRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var rows: [[String]] = []
    private var started = Date.now
    private var watch: AnyCancellable?
    private let link: BikeLink

    static let columns = ["t", "rps", "kmh", "mph", "out", "curve", "pedal", "brake", "boost", "button",
                          "assist", "save", "fuel", "top", "btn", "mg", "sl", "cr"]

    init(link: BikeLink) { self.link = link }

    func start() {
        rows = []
        started = .now
        recording = true
        link.pollInterval = .milliseconds(400)
        if link.isUnlocked { link.startPolling() }
        watch = link.$values.dropFirst().sink { [weak self] in self?.add($0) }
    }

    func stop() {
        recording = false
        watch = nil
        link.pollInterval = .seconds(1.5)
        if link.isUnlocked { link.startPolling() }
    }

    private func add(_ v: [String: String]) {
        guard !v.isEmpty else { return }
        let rps = v["motor.rps"].flatMap(Double.init) ?? 0
        rows.append([
            String(format: "%.2f", Date.now.timeIntervalSince(started)),
            String(format: "%.1f", rps),
            String(format: "%.1f", MotorTune.speed(rps: rps, .kmh)),
            String(format: "%.1f", MotorTune.speed(rps: rps, .mph)),
            v["fv.live.out"] ?? "", v["fv.live.crv"] ?? "",
            v["pas.pedal"] ?? "", v["motor.brk"] ?? "", v["motor.boost"] ?? "", v["button"] ?? "",
            v["motor.ast"] ?? "", v["pwr.save"] ?? "", v["pwr.fuel"] ?? "",
        ] + ["top", "btn", "mg", "sl", "cr"].map { v["fv.tune.\($0)"] ?? "" })
    }

    var csv: String {
        ([Self.columns] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// The recording as a CSV file to share.
    func file() throws -> URL {
        let stamp = started.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let url = URL.temporaryDirectory.appending(path: "freevela-ride-\(stamp).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Developer tools → Ride recorder.
struct RideRecorderView: View {
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var link: BikeLink
    @AppStorage("units") private var units: Units = .kmh

    var body: some View {
        Form {
            PaintSection {
                if recorder.recording {
                    Button("Stop recording", role: .destructive) { recorder.stop() }.fontWeight(.semibold)
                } else {
                    Button(recorder.rows.isEmpty ? "Start recording" : "Start a new recording") { recorder.start() }
                        .fontWeight(.semibold)
                        .disabled(!link.isUnlocked)
                }
                LabeledContent("Samples", value: "\(recorder.rows.count)")
                if !recorder.recording, !recorder.rows.isEmpty, let file = try? recorder.file() {
                    ShareLink(item: file) { Label("Share recording (CSV)", systemImage: "square.and.arrow.up") }
                }
            } footer: {
                Text("Reads the bike about twice a second. Keep FreeVela open on the Ride screen while you ride (it keeps the screen on); recording pauses if the phone locks. Then share the CSV with the developer.")
            }
            if link.isUnlocked {
                PaintSection("Now") {
                    LabeledContent("Speed", value: link.speed(units).map { String(format: "%.1f \(units.label)", $0) } ?? "—")
                    LabeledContent("Throttle", value: link.values["fv.live.out"].map { "\($0) of 254" } ?? "—")
                    LabeledContent("Curve", value: link.values["fv.live.crv"] ?? "—")
                    LabeledContent("Pedalling", value: link.flag("pas.pedal").map { $0 ? "Yes" : "No" } ?? "—")
                    LabeledContent("Brake", value: link.flag("motor.brk").map { $0 ? "Held" : "Off" } ?? "—")
                }
            }
        }
        .paintList()
        .paintNavBar("Ride recorder")
    }
}

/// Developer tools → Motor tuning: the curve numbers behind Top speed, for experiments.
struct MotorTuningView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @State private var drafts: [MotorTune: Double] = [:]

    var body: some View {
        Form {
            if !link.can(.motorTune) {
                PaintSection { Text("Needs FreeVela firmware 0.2.0 or later.").foregroundStyle(.secondary) }
            } else {
                PaintSection {
                    row(.mg, "Margin above speed", step: 1, format: "%.0f")
                    row(.sl, "Throttle per wheel turn/s", step: 1, format: "%.0f")
                    row(.cr, "Climb at speed (per 50 ms)", step: 0.02, format: "%.2f")
                } footer: {
                    Text("The throttle (83 off – 254 full) never drops below 83 + margin + rate × wheel speed while you pedal, climbs toward a ceiling of 83 + margin + rate × top speed, and above about 16 mph climbs by the last number every 50 ms. The stock values are 18, 29 and 0.06.")
                }
                PaintSection {
                    Button("Restore FreeVela defaults") {
                        session.setTune(Dictionary(uniqueKeysWithValues: MotorTune.allCases.map { ($0, $0.default) }))
                    }
                }
            }
        }
        .paintList()
        .paintNavBar("Motor tuning")
    }

    private func row(_ key: MotorTune, _ title: String, step: Double, format: String) -> some View {
        let value = drafts[key] ?? session.tune(key)
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) { Text(String(format: format, value)).monospacedDigit() }
            PaintSlider(value: Binding(get: { value }, set: { drafts[key] = $0 }), range: key.range, step: step) { editing in
                guard !editing, let draft = drafts[key] else { return }
                session.setTune(key, draft)
                drafts[key] = nil
            }
        }
    }
}
