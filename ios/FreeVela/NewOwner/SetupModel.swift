import CoreBluetooth
import SwiftUI

/// Drives "Set up your bike": find the bike, install FreeVela firmware without keys, wait for the
/// 15-second reset on the bike, pair this phone as the owner, then a key backup.
@MainActor
final class SetupModel: ObservableObject {
    enum Step: Equatable {
        case checklist, find, alreadyFreeVela, install, installing, installed, reset, pair, backup, done
        case notFound, lowBattery, installStopped, windowRanOut, noChirps, otherPhone

        /// Which of the 6 steps this screen belongs to (0 = the checklist, before step 1).
        var number: Int {
            switch self {
            case .checklist: 0
            case .find, .alreadyFreeVela, .notFound: 1
            case .install, .installing, .installed, .lowBattery, .installStopped, .windowRanOut: 2
            case .reset, .noChirps: 3
            case .pair, .otherPhone: 4
            case .backup: 5
            case .done: 6
            }
        }

        /// Steps where the trial window is running and its timer shows.
        var showsTimer: Bool { [.reset, .noChirps, .pair].contains(self) }
    }

    @Published var step: Step = .checklist
    @Published private(set) var searching = false
    /// Public status of the found bike; nil on Vela's firmware.
    @Published private(set) var info: BikeInfo?
    @Published private(set) var deviceID: String?
    @Published private(set) var downloading = false
    /// 0 sending, 1 installing, 2 restarting.
    @Published private(set) var installPhase = 0
    @Published private(set) var installFraction = 0.0
    /// When the trial window closes; nil when there's none.
    @Published private(set) var trialEnds: Date?
    /// 0 looking for the bike, 1 making keys, 2 pairing, 3 paired.
    @Published private(set) var pairStage = 0
    @Published private(set) var pairFailed = false
    @Published private(set) var backupSaved = false
    @Published var error: String?

    let link: BikeLink
    let keys: KeyStore
    let session: Session
    let updater: FirmwareUpdater
    private var peripheral: CBPeripheral?
    private var watch: Task<Void, Never>?
    /// Highest hold seen in this reset, so a restart after 15 s moves on to pairing.
    private var heldTo15 = false

    init(link: BikeLink, keys: KeyStore, session: Session, updater: FirmwareUpdater) {
        self.link = link
        self.keys = keys
        self.session = session
        self.updater = updater
        session.setupRunning = true
    }

    /// Hands the bike back to the app (auto-connect, the selected bike).
    func finish() {
        watch?.cancel()
        session.setupRunning = false
        session.bikesChanged()
    }

    var onFreeVela: Bool { info != nil }
    var hold: Int { info?.hold ?? 0 }

    // MARK: Step 1: find

    func find() {
        step = .find
        searching = true
        info = nil
        error = nil
        Task {
            defer { searching = false }
            link.stopPolling()
            link.disconnect()
            link.bike = nil
            guard let p = await link.findBike(timeout: 20), await link.connectAndWait(p, timeout: 15) else {
                step = .notFound
                return
            }
            peripheral = p
            deviceID = link.connectedDeviceID
            info = await link.readInfo()
            if let info { noteTrial(info) }
        }
    }

    /// Continue from a found bike: install on Vela firmware, or straight to the reset on FreeVela.
    func continueFromFound() {
        if let info {
            step = info.keyed == 0 ? .pair : .alreadyFreeVela
            if info.keyed == 0 { pair() }
        } else {
            step = .install
        }
    }

    // MARK: Step 2: install

    func install() {
        if let info, info.fuel < FirmwareUpdater.minBattery {
            step = .lowBattery
            waitForCharge()
            return
        }
        step = .installing
        installPhase = 0
        installFraction = 0
        error = nil
        Task {
            guard let image = await setupImage() else { step = .install; return }
            if link.phase != .connected, let peripheral { _ = await link.connectAndWait(peripheral, timeout: 15) }
            let progress = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self else { return }
                    switch self.updater.stage {
                    case .sending(let f): self.installPhase = 0; self.installFraction = f
                    case .working(let text): self.installPhase = text.hasPrefix("Restarting") ? 2 : 1; self.installFraction = 1
                    default: break
                    }
                }
            }
            let ok = await updater.installKeyless(image, link: link)
            progress.cancel()
            guard ok else { step = .installStopped; return }
            info = await link.readInfo()
            if let info { noteTrial(info) }
            step = .installed
            watchTrial()
        }
    }

    /// The setup image from this phone's store, or downloaded from the GitHub release.
    private func setupImage() async -> CheckedImage? {
        let wanted = FirmwareImage.setup
        if let have = FirmwareStore.all().first(where: { $0.image == wanted }) { return have }
        downloading = true
        defer { downloading = false }
        do {
            let c = try await wanted.download()
            try FirmwareStore.save(c)
            return c
        } catch {
            self.error = "Couldn't download \(wanted.label): \(error.localizedDescription). Check the connection and try again."
            return nil
        }
    }

    private func waitForCharge() {
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if let info = await self.link.readInfo() {
                    self.info = info
                    if info.fuel >= FirmwareUpdater.minBattery { self.install(); return }
                }
            }
        }
    }

    // MARK: Trial window

    private func noteTrial(_ info: BikeInfo) {
        trialEnds = info.trial > 0 ? .now + Double(info.trial) : nil
    }

    /// Keeps the trial timer in step with the bike and notices when it runs out.
    private func watchTrial() {
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.pairStage < 3 else { return }
                if let ends = self.trialEnds, ends < .now, [.installed, .reset, .noChirps, .pair].contains(self.step) {
                    self.step = .windowRanOut
                    return
                }
                if self.step == .installed, let info = await self.link.readInfo() {
                    self.info = info
                    self.noteTrial(info)
                }
            }
        }
    }

    // MARK: Step 3: reset

    func startReset() {
        step = .reset
        heldTo15 = false
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                if let ends = self.trialEnds, ends < .now { self.step = .windowRanOut; return }
                if self.link.phase == .connected, let info = await self.link.readInfo() {
                    self.info = info
                    if info.hold >= 15 { self.heldTo15 = true }
                    if info.keyed == 0 { self.pair(); return }   // reset done (bike already back up)
                } else if self.heldTo15 || self.link.phase != .connected {
                    // The bike restarts after the long tone.
                    if self.heldTo15 { self.pair(); return }
                    if let p = self.peripheral { _ = await self.link.connectAndWait(p, timeout: 5) }
                }
            }
        }
    }

    // MARK: Step 4: pair

    func pair() {
        watch?.cancel()
        step = .pair
        pairStage = 0
        pairFailed = false
        Task {
            // The bike restarts after the reset; find it again.
            var connected = false
            for _ in 0..<20 where !connected {
                if let p = peripheral, await link.connectAndWait(p, timeout: 6) {
                    connected = true
                } else if let p = await link.findBike(timeout: 6), await link.connectAndWait(p, timeout: 10) {
                    peripheral = p
                    connected = true
                }
            }
            guard connected else { pairFailed = true; return }
            deviceID = link.connectedDeviceID ?? deviceID
            if let info = await link.readInfo() {
                self.info = info
                noteTrial(info)
                if info.keyed == 1 { step = .otherPhone; return }
            }
            pairStage = 1
            let id = deviceID ?? "bike-" + (peripheral?.identifier.uuidString.prefix(8).lowercased() ?? "new")
            let new = BikeKeys(id: id, key: "", releasedKey: "").withNewKeys()
            try? await Task.sleep(for: .milliseconds(400))
            pairStage = 2
            switch await link.pairNewOwner(new) {
            case .paired:
                keys.add([new])
                keys.markNeedsBackup(new.id)
                session.selectedID = new.id
                pairStage = 3
                trialEnds = nil
            case .alreadyOwned:
                step = .otherPhone
            case .failed:
                pairFailed = true
            }
        }
    }

    // MARK: Step 5: backup

    func saveBackup() {
        BackupShare.present(keys) { [weak self] saved in
            guard let self, saved else { return }
            self.backupSaved = true
            self.step = .done
        }
    }

    func cancel() {
        if updater.running { updater.cancel() }
        finish()
    }

    /// Back: where each screen returns to.
    func back() {
        watch?.cancel()
        switch step {
        case .find, .notFound: step = .checklist
        case .alreadyFreeVela, .install, .lowBattery, .installStopped, .windowRanOut: find()
        case .reset, .noChirps: step = onFreeVela && trialEnds == nil ? .alreadyFreeVela : .installed
        case .pair, .otherPhone: startReset()
        case .backup: step = .pair
        default: break
        }
    }

    #if DEBUG
    /// Simulator screenshots: `-demoSetup <step>` shows that screen with sample data.
    func loadDemo(_ name: String) {
        let demo = BikeInfo(ver: "0.2.0", keyed: 1, trial: 504, boots: 2, hold: 8, fuel: 72)
        deviceID = "b2349a1f0c22d4"
        trialEnds = .now + 504
        switch name {
        case "find": step = .find; searching = true
        case "found": step = .find
        case "already": info = demo; step = .alreadyFreeVela
        case "install": step = .install
        case "installing": step = .installing; installPhase = 0; installFraction = 0.42
        case "installed": info = demo; step = .installed
        case "reset": info = demo; step = .reset
        case "pair": info = demo; step = .pair; pairStage = 2
        case "paired": info = demo; step = .pair; pairStage = 3; trialEnds = nil
        case "backup": step = .backup
        case "done": step = .done
        case "notFound": step = .notFound
        case "lowBattery": info = BikeInfo(ver: "0.2.0", keyed: 1, trial: 0, boots: 0, hold: 0, fuel: 31); step = .lowBattery
        case "installStopped": step = .installStopped
        case "windowRanOut": step = .windowRanOut
        case "noChirps": info = demo; step = .noChirps
        case "otherPhone": step = .otherPhone
        default: step = .checklist
        }
    }
    #endif
}
