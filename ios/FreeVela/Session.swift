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
    private var readyWatch: AnyCancellable?
    private var lookout: Task<Void, Never>?
    /// The app is in the foreground (set by RootView), so it's worth looking for the bike.
    var foreground = false
    /// Scanning in the background while the "asleep" screen shows; Home keeps showing asleep.
    private var quietScan = false
    /// After a failed unlock, don't retry on our own for a minute (it would just fail again).
    private var unlockFailedAt: Date?

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
        #if DEBUG
        if Self.demoTransition {
            Task { [weak self] in try? await Task.sleep(for: .seconds(3.1)); self?.objectWillChange.send() }
        }
        #endif
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
        // Connected but not unlocked, by any route (a slow connect, a reconnect): unlock on our own.
        readyWatch = link.$ready.removeDuplicates().sink { [weak self] ready in
            guard ready else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.connected, !self.link.isUnlocked, self.mayActOnItsOwn else { return }
                await self.unlock()
            }
        }
        // While the bike seems asleep (or out of range) and the app is open, keep looking quietly.
        lookout = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self else { return }
                guard self.foreground, self.status == .asleep, self.mayActOnItsOwn,
                      self.link.phase != .connecting, self.link.phase != .scanning else { continue }
                self.quietScan = true
                let found = await self.link.findBike(timeout: 8, quiet: true)
                self.quietScan = false
                guard let found, self.mayActOnItsOwn, !self.connected else { continue }
                self.busy = "Connecting…"
                let up = await self.link.connectAndWait(found, timeout: 15)
                self.busy = nil
                if up, !self.link.isUnlocked { await self.unlock() }
            }
        }
    }

    /// Nothing else is driving the connection, and an unlock hasn't just failed.
    private var mayActOnItsOwn: Bool {
        bike != nil && !link.demo && busy == nil && !setupRunning && !updater.running && link.bluetooth == .poweredOn
            && (unlockFailedAt.map { Date().timeIntervalSince($0) > 60 } ?? true)
    }

    var bike: BikeKeys? { link.demo ? Self.demoBike : keys.bikes.first { $0.id == selectedID } }

    // MARK: Demo ("Try without a bike")

    /// Not saved anywhere: the demo bike never reaches the keychain or iCloud.
    private static let demoBike = BikeKeys(id: "demo", key: "", releasedKey: "", displayName: "Demo bike")
    var demo: Bool { link.demo }

    func startDemo() {
        pending = [:]
        link.startDemo()
        link.bike = bike
        objectWillChange.send()
    }

    func stopDemo() {
        pending = [:]
        link.stopDemo()
        link.bike = bike
        objectWillChange.send()
        autoConnect()
    }
    var connected: Bool { link.phase == .connected && link.ready }

    /// Call when the bike list changes, so the selection never points at a removed bike.
    func bikesChanged() {
        if link.demo, !keys.bikes.isEmpty { stopDemo() }
        if bike == nil { selectedID = keys.bikes.first?.id } else { link.bike = bike }
    }

    /// Looks for the bike once whenever the app opens or comes back, if it isn't connected.
    func autoConnect() {
        guard bike != nil, !link.demo, busy == nil, !setupRunning, !updater.running, link.bluetooth == .poweredOn,
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
        if await link.unlock(progress: { busy = $0 }) {
            unlockFailedAt = nil
            adoptDeviceID()
        } else {
            unlockFailedAt = Date()
        }
    }

    /// Once unlocked, remember the id the bike broadcasts, so it's found by that id next time.
    /// Keys pasted without a device id also take it as their id.
    private func adoptDeviceID() {
        guard let bike, let real = link.connectedDeviceID else { return }
        if bike.hasPendingID {
            link.log.add(.info, "device id \(real) learned from the bike")
            keys.replaceID(bike.id, with: real)
            selectedID = real
        } else if bike.radioID != real && bike.id.caseInsensitiveCompare(real) != .orderedSame {
            link.log.add(.info, "Bluetooth id \(real) learned from the bike (device id \(bike.id))")
            keys.setRadioID(real, for: bike.id)
            bikesChanged()
        }
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
        case bluetooth(String), searching, connecting, unlocking, locked, connected, asleep
    }

    var status: Status {
        #if DEBUG
        if let demo = Self.demoStatus { return demo }
        if Self.demoTransition { return Date() < Self.demoStart + 3 ? .searching : .connected }
        #endif
        if link.demo { return .connected }
        if link.bluetooth != .poweredOn { return .bluetooth(link.bluetooth.label) }
        if link.isUnlocked { return .connected }
        if let busy {
            if busy.hasPrefix("Connecting") { return .connecting }
            if busy.hasPrefix("Unlock") || busy.hasPrefix("Retrying") { return .unlocking }
            return .searching
        }
        if link.phase == .connecting { return .connecting }
        if link.phase == .scanning { return quietScan ? .asleep : .searching }
        if connected { return .locked }
        return .asleep
    }

    #if DEBUG
    /// `-demoTransition`: "searching" for 3 s, then connected (to check the dashboard's entrance).
    private static let demoTransition = ProcessInfo.processInfo.arguments.contains("-demoTransition")
    private static let demoStart = Date()

    /// Simulator screenshots: `-demoConnect <state>` forces the status Home shows.
    private static var demoStatus: Status? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoConnect"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "bluetooth": return .bluetooth("off")
        case "searching": return .searching
        case "connecting": return .connecting
        case "unlocking": return .unlocking
        case "locked": return .locked
        case "asleep": return .asleep
        default: return nil
        }
    }
    #endif
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
