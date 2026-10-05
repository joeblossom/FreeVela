import Combine
import SwiftUI

/// Which bike is selected and the connect → unlock flow, shared by Home, Ride and onboarding.
@MainActor
final class Session: ObservableObject {
    @Published var selectedID: String? {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "selectedBikeID")
            link.bike = bike
        }
    }
    /// What the app is doing right now ("Looking for your bike…"), or nil.
    @Published private(set) var busy: String?
    /// Set while "Set up your bike" runs, so auto-connect doesn't take the bike over.
    var setupRunning = false

    /// What the user just picked, by STATE path, shown until the bike reports it (see Controls.swift).
    @Published var pending: [String: Pending] = [:]
    @Published var ecoDraft: Int?
    @Published var sirenEnds: Date?
    private var watch: AnyCancellable?
    private var lightFix: AnyCancellable?

    let keys: KeyStore
    let link: BikeLink
    let updater: FirmwareUpdater

    init(keys: KeyStore, link: BikeLink, updater: FirmwareUpdater) {
        self.keys = keys
        self.link = link
        self.updater = updater
        let saved = UserDefaults.standard.string(forKey: "selectedBikeID")
        selectedID = keys.bikes.contains { $0.id == saved } ? saved : keys.bikes.first?.id
        link.bike = bike
        // Each STATE read: forget picks the bike has caught up with, or that it never confirmed in time.
        watch = link.$values.dropFirst().sink { [weak self] values in
            guard let self, !self.pending.isEmpty else { return }
            let settled = self.pending.filter { key, p in p.expired || p.matches(self.bikeValue(key, in: values)) }
            for key in settled.keys { self.pending[key] = nil }
        }
        // The light's always-on mode stops it turning off when the bike idles; the app's "On" is auto.
        lightFix = link.$values.sink { [weak self] values in
            guard let self, values["light.mode"] == "1", self.pending["light.mode"] == nil, self.link.can(.light) else { return }
            self.link.log.add(.info, "light was always on; switching it to auto so it turns off when the bike idles")
            self.setLight(.auto)
        }
    }

    var bike: BikeKeys? { keys.bikes.first { $0.id == selectedID } }
    var connected: Bool { link.phase == .connected && link.ready }

    /// Call when the bike list changes, so the selection never points at a removed bike.
    func bikesChanged() {
        if bike == nil { selectedID = keys.bikes.first?.id } else { link.bike = bike }
    }

    /// Looks for the bike once whenever the app opens or comes back, if it isn't connected.
    func autoConnect() {
        guard bike != nil, busy == nil, !setupRunning, !updater.running, link.bluetooth == .poweredOn,
              link.phase != .connecting, link.phase != .scanning, !connected else { return }
        busy = "Looking for your bike…"
        Task { await connect() }
    }

    func connect() async {
        busy = "Looking for your bike…"
        defer { busy = nil }
        guard let p = await link.findBike() else { return }
        busy = "Connecting…"
        if await link.connectAndWait(p) { await unlock() }
    }

    func unlock() async {
        busy = "Unlocking…"
        defer { busy = nil }
        _ = await link.unlock { busy = $0 }
    }

    /// Gives the bike new keys and saves them. Returns false if the bike didn't take them.
    func resetKeys() async -> Bool {
        busy = "Resetting keys…"
        defer { busy = nil }
        guard let new = await link.resetKeys() else { return false }
        keys.add([new])
        keys.markNeedsBackup(new.id)
        bikesChanged()
        return true
    }

    // MARK: Status shown on Home

    enum Status: Equatable {
        case bluetooth(String), searching(String), locked, connected, asleep
    }

    var status: Status {
        if link.bluetooth != .poweredOn { return .bluetooth(link.bluetooth.label) }
        if link.isUnlocked { return .connected }
        if let busy { return .searching(busy) }
        if link.phase == .connecting || link.phase == .scanning { return .searching("Looking for your bike…") }
        if connected { return .locked }
        return .asleep
    }
}

/// App-wide display preferences.
enum Units: String, CaseIterable {
    case kmh, mph
    var label: String { self == .kmh ? "km/h" : "mph" }
    var distance: String { self == .kmh ? "km" : "mi" }
    var toggled: Units { self == .kmh ? .mph : .kmh }
}

enum Appearance: String, CaseIterable {
    case system, light, dark
    var label: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
