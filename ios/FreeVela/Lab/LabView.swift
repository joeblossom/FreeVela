import SwiftUI
import CoreBluetooth

/// Protocol lab: every step of talking to the bike, one screen per area,
/// with a shareable log. Used to confirm docs/protocol.md on real bikes.
struct LabView: View {
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var log: LabLog

    var body: some View {
        Form {
            Section {
                NavigationLink { LabPage("Scan & devices") { ScanSection() } } label: {
                    SettingsRow("Scan & devices", "dot.radiowaves.left.and.right", .blue, plain: true)
                }
                NavigationLink { LabPage("Connection & GATT", needsConnection: true) { ConnectionSection() } } label: {
                    LabeledContent { Text(link.phase == .connected ? "Connected" : "—") } label: {
                        SettingsRow("Connection & GATT", "antenna.radiowaves.left.and.right", .blue, plain: true)
                    }
                }
                NavigationLink { LabPage("State", needsConnection: true) { StateSection() } } label: {
                    SettingsRow("State", "waveform.path.ecg", .orange, plain: true)
                }
                NavigationLink { LabPage("Dispatch", needsConnection: true) { DispatchSection() } } label: {
                    SettingsRow("Dispatch", "paperplane.fill", .orange, plain: true)
                }
            } header: {
                Text("Bluetooth")
            } footer: {
                Text("Change assist from Dispatch only with the bike on a stand.")
            }
            Section("Motor") {
                NavigationLink { RideRecorderView() } label: {
                    LabeledContent { Text(recorder.recording ? "Recording" : "") } label: {
                        SettingsRow("Ride recorder", "record.circle", .red, plain: true)
                    }
                }
                NavigationLink { MotorTuningView() } label: {
                    SettingsRow("Motor tuning", "slider.horizontal.3", .red, plain: true)
                }
            }
            Section("Unlock") {
                NavigationLink { LabPage("Auth steps", needsConnection: true) { AuthSection() } } label: {
                    SettingsRow("Auth steps", "key.fill", .gray, plain: true)
                }
                NavigationLink { LabPage("Unlock methods", needsConnection: true) { UnlockSection() } } label: {
                    SettingsRow("Unlock methods", "lock.open.fill", .gray, plain: true)
                }
            }
            Section("Log") {
                ForEach(log.entries.suffix(4).reversed()) { e in
                    Text(log.line(e)).font(.caption2.monospaced()).foregroundStyle(color(e.kind))
                }
                NavigationLink { LogView() } label: {
                    LabeledContent("Full log") { Text("\(log.entries.count)") }
                }
            }
        }
        .navigationTitle("Developer tools")
        .navigationBarTitleDisplayMode(.inline)
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
                Section {
                    Text("Not connected. Connect from Scan & devices, or let Home find your bike.").foregroundStyle(.secondary)
                }
            } else {
                content
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Scan

private struct ScanSection: View {
    @EnvironmentObject private var link: BikeLink
    @State private var showAll = false

    private var visible: [BikeLink.Found] {
        link.found
            .filter { showAll || $0.name != nil || $0.advertisesVela }
            .sorted { (rank($0), $0.rssi) > (rank($1), $1.rssi) }
    }

    private func rank(_ f: BikeLink.Found) -> Int { link.likeliness(f) }

    var body: some View {
        Section {
            HStack {
                if link.phase == .scanning {
                    Button("Stop scan") { link.stopScan() }
                    Spacer()
                    ProgressView()
                } else {
                    Button("Scan") { link.startScan() }
                }
            }
            Toggle("Show unnamed devices", isOn: $showAll)
            ForEach(visible.prefix(30)) { f in
                Button { link.connect(f) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(f.name ?? "unnamed").fontWeight(rank(f) > 0 ? .semibold : .regular)
                            Text(f.id.uuidString.prefix(8) + (f.advertisesVela ? " · Vela services" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(f.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tint(rank(f) >= 2 ? .green : .primary)
                .disabled(link.phase == .connecting)
            }
        } header: {
            Text("Scan")
        } footer: {
            Text("Close the old Vela app first — the bike talks to one phone at a time. Tap a device to connect. Likely bikes are bold; green means the name matches your bike.")
        }
    }

}

// MARK: - Connection / GATT

private struct ConnectionSection: View {
    @EnvironmentObject private var link: BikeLink

    var body: some View {
        Section("Connection — \(link.phase.rawValue)") {
            if let name = link.connectedName { LabeledContent("Peripheral", value: name) }
            ForEach(link.services, id: \.uuid) { s in
                DisclosureGroup(link.label(s.uuid)) {
                    ForEach(s.characteristics ?? [], id: \.uuid) { c in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(link.label(c.uuid)).font(.callout)
                                Text(c.properties.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if c.properties.contains(.read) {
                                Button("Read") { Task { await link.attempt("read \(link.label(c.uuid))") { try await link.read(c.uuid) } } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            Button("Disconnect", role: .destructive) { link.disconnect() }
        }
    }

}

// MARK: - Auth

private struct AuthSection: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @State private var writeRelease = true
    private var bike: BikeKeys? { session.bike }

    var body: some View {
        Section {
            Button("1. Read CHALLENGE") { Task { await link.attempt("read CHALLENGE") { try await link.read(BikeProtocol.challenge) } } }
            Button("2. Read RELEASE") { Task { await link.attempt("read RELEASE") { try await link.read(BikeProtocol.release) } } }
            Button("3. Write RELEASE ← releasedKey") { Task { await link.writeReleasedKey() } }.disabled(bike == nil)
            Button("4. Write KEY ← key") { Task { await link.writeKey() } }.disabled(bike == nil)
            Toggle("Write RELEASE in full sequence", isOn: $writeRelease)
            Button("Run full sequence") { Task { await link.runAuth(writeRelease: writeRelease) } }
                .fontWeight(.semibold).disabled(bike == nil)
        } header: {
            Text("Auth")
        } footer: {
            Text("Low-level steps: the bike sends a 16-byte CHALLENGE and expects a response on KEY. Key bytes are redacted in the log (shown as a fingerprint).")
        }
    }

}

// MARK: - Unlock methods

private struct UnlockSection: View {
    @EnvironmentObject private var link: BikeLink

    var body: some View {
        Section {
            Button("Unlock handshake") { Task { _ = await link.unlockHandshake() } }.fontWeight(.semibold)
            Button("Unlock handshake, without writing RELEASE") { Task { _ = await link.unlockHandshake(writeRelease: false) } }
            ForEach(UnlockMethod.all) { m in
                Button(m.label) { Task { _ = await link.tryUnlock(m) } }.font(.callout)
            }
        } header: {
            Text("Unlock methods")
        } footer: {
            Text("The unlock handshake is the one that works. The rest are older guesses, kept for comparison. Each tries one way of answering the challenge, then checks whether STATE returns real data. A wrong answer usually makes the bike disconnect; the next try reconnects automatically.")
        }
    }

}

// MARK: - State

private struct StateSection: View {
    @EnvironmentObject private var link: BikeLink

    var body: some View {
        if link.values["fv.adc.c0"] != nil {
            Section {
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
        Section("State") {
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

// MARK: - Dispatch

private struct DispatchSection: View {
    @EnvironmentObject private var link: BikeLink
    @State private var dispatchText = #"{"type":"alarm/ARM"}"#
    @State private var base64Text = false

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(BikeProtocol.presets) { p in
                        Button(p.label) { dispatchText = p.json }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            TextField("JSON action", text: $dispatchText, axis: .vertical)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle("Send as base64 text (fallback)", isOn: $base64Text)
            Button("Send") { Task { await link.dispatch(dispatchText, base64Text: base64Text) } }
                .fontWeight(.semibold)
        } header: {
            Text("Dispatch")
        } footer: {
            Text("Start with Alarm arm / Alarm off and watch the state for alarm.armed. Change assist only with the bike on a stand.")
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
        }
        .listStyle(.plain)
        .navigationTitle("Log")
        .toolbar {
            ShareLink(item: log.exportText)
            Button("Clear", role: .destructive) { log.clear() }
        }
    }
}
