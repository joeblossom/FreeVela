import SwiftUI

/// The simple flow: pick your bike's keys → connect → unlock → control.
/// Everything low-level lives in Developer tools (LabView).
struct HomeView: View {
    @EnvironmentObject private var keys: KeyStore
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var log: LabLog
    @EnvironmentObject private var updater: FirmwareUpdater
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var busy: String?
    /// What the user just picked, shown until the bike's state catches up.
    @State private var pendingAssist: BikeProtocol.AssistMode?
    @State private var pendingToggles: [String: Bool] = [:]
    @State private var pendingLight: Int?
    @State private var ecoDraft: Double?
    @State private var sounding = false
    @State private var confirmSound = false

    private var bike: BikeKeys? { keys.bikes.first { $0.id == selectedID } }
    private var connected: Bool { link.phase == .connected && link.ready }

    var body: some View {
        NavigationStack {
            Form {
                KeysView(selectedID: $selectedID)
                if bike != nil { bikeSection }
                if link.isUnlocked { statusSection; controlsSection }
                Section {
                    NavigationLink("Developer tools") { LabView(selectedID: $selectedID) }
                    ShareLink("Share log with developer", item: log.exportText)
                } footer: {
                    Text("Something not working? Share the log — it never contains your keys.")
                }
            }
            .navigationTitle("FreeVela")
        }
        .onAppear { if selectedID == nil { selectedID = keys.bikes.first?.id } }
        .onChange(of: selectedID, initial: true) { link.bike = bike; autoConnect() }
        .onChange(of: keys.bikes) { link.bike = bike }
        .onChange(of: link.bluetooth) { autoConnect() }
        .onChange(of: scenePhase) { if scenePhase == .active { autoConnect() } }
    }

    /// Looks for the bike once whenever the app opens or comes back, if it isn't connected.
    private func autoConnect() {
        guard bike != nil, busy == nil, !updater.running, link.bluetooth == .poweredOn,
              link.phase != .connecting, link.phase != .scanning, !connected else { return }
        busy = "Looking for your bike…"
        Task { await connect() }
    }

    // MARK: Connect + unlock

    private var statusLine: String {
        if let busy { return busy }
        if link.bluetooth != .poweredOn { return "Bluetooth is \(link.bluetooth.label)." }
        if link.isUnlocked { return "Connected and unlocked." }
        if connected { return "Connected, but locked. Tap Unlock." }
        if link.phase == .connecting { return "Connecting…" }
        return "Not connected. Wake the bike (hold the brake and the button), then tap Connect."
    }

    private var bikeSection: some View {
        Section {
            Text(statusLine)
            if busy != nil {
                ProgressView()
            } else if !connected {
                Button("Connect") { Task { await connect() } }.fontWeight(.semibold)
            } else if !link.isUnlocked {
                Button("Unlock") { Task { await unlock() } }.fontWeight(.semibold)
                Button("Disconnect", role: .destructive) { link.disconnect() }
            } else {
                Button("Disconnect", role: .destructive) { link.disconnect() }
            }
        } header: {
            Text("Bike")
        } footer: {
            if !link.isUnlocked {
                Text("Close the old Vela app first — the bike only talks to one phone at a time. Unlocking takes a couple of seconds.")
            }
        }
    }

    private func connect() async {
        busy = "Looking for your bike…"
        defer { busy = nil }
        guard let p = await link.findBike() else { return }
        busy = "Connecting…"
        if await link.connectAndWait(p) { await unlock() }
    }

    private func unlock() async {
        busy = "Unlocking…"
        defer { busy = nil }
        _ = await link.unlock { busy = $0 }
    }

    // MARK: Dashboard

    private func value(_ path: String) -> String? { link.values[path] }

    private var assistMode: BikeProtocol.AssistMode? {
        BikeProtocol.AssistMode(ast: value("motor.ast"), save: value("pwr.save"))
    }

    private var odometer: String {
        guard let pulses = value("motor.pulse").flatMap(Double.init) else { return "—" }
        let km = pulses * BikeProtocol.kmPerPulse, mi = pulses * BikeProtocol.miPerPulse
        return String(format: "%.1f km · %.1f mi", km, mi)
    }

    private func isOn(_ path: String) -> Bool {
        pendingToggles[path] ?? (value(path) == "1" || value(path) == "true")
    }

    private func toggle(_ path: String, on: Bool, _ json: String) {
        pendingToggles[path] = on
        Task {
            await link.dispatch(json, base64Text: false)
            pendingToggles[path] = nil
        }
    }

    /// Whether the connected bike's firmware supports a feature (see BLE/Firmware.swift).
    private func can(_ c: Capability) -> Bool { link.firmware?.has(c) ?? false }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Battery", value: value("pwr.fuel").map { "\($0)%" } ?? "—")
            LabeledContent("Charging", value: value("pwr.chr").map { _ in isOn("pwr.chr") ? "Yes" : "No" } ?? "—")
            LabeledContent("Speed", value: value("motor.rps").flatMap(Double.init).map {
                String(format: "%.0f km/h · %.0f mph", $0 * BikeProtocol.metersPerRev * 3.6, $0 * BikeProtocol.metersPerRev * 2.237)
            } ?? "—")
            LabeledContent("Odometer", value: odometer)
            LabeledContent("Alarm", value: value("alarm.armed").map { _ in isOn("alarm.armed") ? "Armed" : "Off" } ?? "—")
            LabeledContent("Firmware", value: link.firmware?.label ?? value("sys.ver") ?? "—")
            if link.firmware?.kind == .velaUnknown {
                Text("This firmware version hasn't been tested with FreeVela, so only the basic controls are shown.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var controlsSection: some View {
        Group {
            if can(.assistModes) {
            Section {
                Picker("Assist", selection: Binding(
                    get: { pendingAssist ?? assistMode },
                    set: { mode in
                        guard let mode, mode != (pendingAssist ?? assistMode) else { return }
                        pendingAssist = mode
                        Task {
                            await link.setAssist(mode)
                            pendingAssist = nil
                        }
                    }
                )) {
                    ForEach(BikeProtocol.AssistMode.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                if can(.ecoThreshold), (pendingAssist ?? assistMode) == .auto, let save = value("pwr.save").flatMap(Double.init) {
                    let shown = ecoDraft ?? save
                    VStack(alignment: .leading) {
                        Text("Switch to eco below \(Int(shown))% battery")
                        Slider(value: Binding(get: { shown }, set: { ecoDraft = $0 }), in: 5...95, step: 5) { editing in
                            guard !editing, let draft = ecoDraft else { return }
                            Task {
                                await link.setEcoThreshold(Int(draft))
                                ecoDraft = nil
                            }
                        }
                    }
                }
            } header: {
                Text("Assist")
            } footer: {
                Text("Off: no motor help. Low: gentle eco assist always. Auto: full assist until the battery drops to the level above, then eco. High: full assist always. Hold the handlebar button while pedalling for boost, or without pedalling for walk assist.")
            }
            }

            if can(.alarm) || can(.ebrake) {
            Section {
                if can(.alarm) {
                Toggle("Alarm", isOn: Binding(
                    get: { isOn("alarm.armed") },
                    set: { toggle("alarm.armed", on: $0, $0 ? #"{"type":"alarm/ARM"}"# : #"{"type":"alarm/DESARM"}"#) }
                ))
                }
                if can(.ebrake) {
                Toggle("E-brake", isOn: Binding(
                    get: { isOn("motor.ebc") },
                    set: { toggle("motor.ebc", on: $0, #"{"type":"motor/EBC_SET","payload":\#($0 ? 1 : 0)}"#) }
                ))
                }
            } footer: {
                Text("E-brake makes the motor brake when you pull the brake lever above about 18 km/h. Arming the alarm uses the same brake to make the rear wheel hard to turn.")
            }
            }

            if can(.findMyBike) {
            Section {
                Button(sounding ? "Sounding…" : "Sound alarm") { confirmSound = true }
                    .disabled(sounding)
                    .confirmationDialog("Sound the bike's siren for 15 seconds?", isPresented: $confirmSound, titleVisibility: .visible) {
                        Button("Sound alarm", role: .destructive) {
                            sounding = true
                            Task {
                                await link.soundAlarm()
                                sounding = false
                            }
                        }
                    }
            } header: {
                Text("Find my bike")
            } footer: {
                Text("The siren is loud. FreeVela clears the alarm afterwards, so stay connected for the 15 seconds; if the connection drops, disarm the alarm to release the rear wheel.")
            }
            }

            if can(.light) {
            Section {
                Picker("Light", selection: Binding(
                    get: { pendingLight ?? Int(value("light.mode") ?? "") },
                    set: { mode in
                        guard let mode else { return }
                        pendingLight = mode
                        Task {
                            await link.dispatch(#"{"type":"light/MODE_SET","payload":\#(mode)}"#, base64Text: false)
                            pendingLight = nil
                        }
                    }
                )) {
                    Text("Auto").tag(Optional(0))
                    Text("On").tag(Optional(1))
                    Text("Off").tag(Optional(-1))
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Light")
            } footer: {
                Text("Auto turns the light on whenever the bike is awake.")
            }
            }
        }
    }

}
