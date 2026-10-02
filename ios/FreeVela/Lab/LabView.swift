import SwiftUI
import CoreBluetooth

/// Protocol lab: every step of talking to the bike, one button at a time,
/// with a shareable log. Used to confirm docs/protocol.md on real bikes.
struct LabView: View {
    @EnvironmentObject private var keys: KeyStore
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var log: LabLog
    @Binding var selectedID: String?
    @State private var showAll = false
    @State private var dispatchText = #"{"type":"alarm/ARM"}"#
    @State private var base64Text = false
    @State private var writeRelease = true

    private var bike: BikeKeys? { keys.bikes.first { $0.id == selectedID } }
    private var connected: Bool { link.phase == .connected }

    var body: some View {
        Group {
            Form {
                Section {
                    NavigationLink("Firmware update") { FirmwareUpdateView() }
                }
                scanSection
                if connected || link.phase == .connecting { connectionSection }
                if connected {
                    authSection
                    unlockSection
                    stateSection
                    dispatchSection
                }
                logSection
            }
            .navigationTitle("Developer tools")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: log.exportText) { Label("Share log", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }

    // MARK: Scan

    private var visible: [BikeLink.Found] {
        link.found
            .filter { showAll || $0.name != nil || $0.advertisesVela }
            .sorted { (rank($0), $0.rssi) > (rank($1), $1.rssi) }
    }

    private func rank(_ f: BikeLink.Found) -> Int { link.likeliness(f) }

    private var scanSection: some View {
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

    // MARK: Connection / GATT

    private var connectionSection: some View {
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

    // MARK: Auth

    private var authSection: some View {
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

    // MARK: Unlock methods

    private var unlockSection: some View {
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

    // MARK: State

    private var stateSection: some View {
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

    // MARK: Dispatch

    private var dispatchSection: some View {
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

    // MARK: Log

    private var logSection: some View {
        Section {
            ForEach(log.entries.suffix(8).reversed()) { e in
                Text(log.line(e)).font(.caption2.monospaced()).foregroundStyle(color(e.kind))
            }
            NavigationLink("Full log (\(log.entries.count))") { LogView() }
        } header: {
            Text("Log")
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
