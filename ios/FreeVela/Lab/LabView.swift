import SwiftUI

/// Developer tools: read-only views of the bike (state, charger probe), the ride recorder, motor
/// tuning, and the shareable log. Nothing here sends arbitrary commands to the bike.
struct LabView: View {
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var log: LabLog

    var body: some View {
        Form {
            PaintSection("Motor") {
                NavigationLink { RideRecorderView() } label: {
                    LabeledContent { Text(recorder.recording ? "Recording" : "") } label: {
                        SettingsRow("Ride recorder", "record.circle", plain: true)
                    }
                }
                NavigationLink { MotorTuningView() } label: {
                    SettingsRow("Motor tuning", "slider.horizontal.3", plain: true)
                }
            }
            PaintSection("Bike") {
                NavigationLink { LabPage("State", needsConnection: true) { StateSection() } } label: {
                    SettingsRow("State", "waveform.path.ecg", plain: true)
                }
            }
            PaintSection("Log") {
                ForEach(log.entries.suffix(4).reversed()) { e in
                    Text(log.line(e)).font(.caption2.monospaced()).foregroundStyle(color(e.kind))
                }
                NavigationLink { LogView() } label: {
                    LabeledContent("Full log") { Text("\(log.entries.count)") }
                }
            }
        }
        .paintList()
        .paintNavBar("Developer tools")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: log.exportText) { Label("Share log", systemImage: "square.and.arrow.up") }
            }
        }
    }
}

/// One developer-tools screen. Pages that need the bike say so instead of showing dead buttons.
private struct LabPage<Content: View>: View {
    @EnvironmentObject private var link: BikeLink
    let title: String
    var needsConnection = false
    @ViewBuilder var content: Content

    init(_ title: String, needsConnection: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.needsConnection = needsConnection
        self.content = content()
    }

    var body: some View {
        Form {
            if needsConnection && link.phase != .connected && link.phase != .connecting {
                PaintSection {
                    Text("Not connected. Open the app next to your bike so it connects, then come back.").foregroundStyle(.secondary)
                }
            } else {
                content
            }
        }
        .paintList()
        .paintNavBar(title)
    }
}

// MARK: - State

private struct StateSection: View {
    @EnvironmentObject private var link: BikeLink

    private func pressed(_ path: String) -> String {
        switch link.values[path] { case "1": "Pressed"; case "0": "—"; default: "?" }
    }

    var body: some View {
        if link.values["fv.adc.c0"] != nil {
            PaintSection {
                ForEach(["c0": "GPIO 36", "c3": "GPIO 39", "c6": "GPIO 34", "c7": "GPIO 35 (battery)"].sorted { $0.key < $1.key }, id: \.key) { key, pin in
                    LabeledContent(pin, value: link.values["fv.adc.\(key)"] ?? "—").monospacedDigit()
                }
                LabeledContent("Charging (estimated)", value: link.flag("pwr.chr") == true ? "Yes" : "No")
            } header: {
                Text("Charger probe")
            } footer: {
                Text("Raw readings (0–1023) of the board's spare analog inputs, updated with each read. Note them with the charger unplugged, then plugged in: an input that changes a lot is a charger signal. Share the log or a screenshot with the developer.")
            }
        }
        if link.values["fv.io.brk"] != nil {
            PaintSection {
                LabeledContent("Button, GPIO 3", value: pressed("fv.io.b3"))
                LabeledContent("Button, GPIO 0", value: pressed("fv.io.b0"))
                LabeledContent("Brake, GPIO 32", value: pressed("fv.io.brk"))
            } header: {
                Text("Inputs")
            } footer: {
                Text("Live with Subscribe on. Hold the handlebar button, then the brake: whichever line says Pressed is the pin that can wake the bike (GPIO 0 and 32 can, GPIO 3 can't). Changes also go to the log.")
            }
        }
        PaintSection("State") {
            HStack {
                Button("Read STATE") { Task { await link.attempt("read STATE") { try await link.read(BikeProtocol.state) } } }
                    .buttonStyle(.borderless)
                Spacer()
                Button(link.notifying ? "Unsubscribe" : "Subscribe") { link.setNotify(!link.notifying) }
                    .buttonStyle(.borderless)
            }
            if !link.changedPaths.isEmpty {
                Text("Changed: " + link.changedPaths.sorted().joined(separator: ", "))
                    .font(.caption).foregroundStyle(.orange)
            }
            if !link.stateText.isEmpty {
                Text(link.stateText).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }

}

private func color(_ kind: LogEntry.Kind) -> Color {
    switch kind {
    case .error: .red
    case .ok: .green
    case .tx: .blue
    default: .primary
    }
}

struct LogView: View {
    @EnvironmentObject private var log: LabLog

    var body: some View {
        List(log.entries) { e in
            Text(log.line(e)).font(.caption2.monospaced()).foregroundStyle(color(e.kind)).textSelection(.enabled)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .paintList()
        .paintNavBar("Log")
        .toolbar {
            ShareLink(item: log.exportText)
            Button("Clear", role: .destructive) { log.clear() }
        }
    }
}
