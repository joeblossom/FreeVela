import CryptoKit
import Foundation
import UIKit

/// A firmware image FreeVela is willing to install. A file is only sent if its size and
/// SHA-256 match an entry here exactly, so add one for each release.
struct FirmwareImage: Identifiable, Hashable {
    let name: String
    /// What the bike reports once it runs this image: `fv.ver` for FreeVela firmware, `sys.ver` for Vela's.
    let version: String
    let freeVela: Bool
    let size: Int
    let sha256: String
    /// Where the app can download it (a GitHub release asset). Vela's image isn't redistributed.
    var url: URL? = nil
    var id: String { sha256 }

    static let known: [FirmwareImage] = [
        FirmwareImage(name: "Vela 2306052112 (original)", version: "2306052112", freeVela: false,
                      size: 1_083_232, sha256: "b41f83d63310defd2543595a6a9efa75a97ed5ab987b14beba2ade5f5a8c28ea"),
        // Vela's behavior plus: fv.ver in STATE, brake+button wake, and a trial boot that switches
        // back to the previous firmware unless the app unlocks the bike within 10 min / 3 boots.
        FirmwareImage(name: "FreeVela 0.1.0 (pre-release)", version: "0.1.0", freeVela: true,
                      size: 769_200, sha256: "6ecf684908de661d9649b515b3f67120204582b089cf3549ef60277ce4e4cb47",
                      url: release("firmware-v0.1.0", "freevela-0.1.0.bin")),
    ]

    private static func release(_ tag: String, _ file: String) -> URL? {
        URL(string: "https://github.com/joeblossom/FreeVela/releases/download/\(tag)/\(file)")
    }

    enum DownloadError: LocalizedError {
        case http(Int), wrongImage
        var errorDescription: String? {
            switch self {
            case .http(let code): "the server answered \(code)"
            case .wrongImage: "the file isn't the expected image"
            }
        }
    }

    /// Downloads the image and checks it like an imported file (exact size and SHA-256).
    func download() async throws -> CheckedImage {
        guard let url else { throw DownloadError.http(404) }
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DownloadError.http(code) }
        let checked = try CheckedImage(data: data)
        guard checked.image == self else { throw DownloadError.wrongImage }
        return checked
    }

    var label: String { freeVela ? "FreeVela \(version)" : "Vela \(version)" }
}

/// An image file that matched `FirmwareImage.known` and looks like an ESP32 app image.
struct CheckedImage: Identifiable {
    let data: Data
    let image: FirmwareImage
    var id: String { image.sha256 }

    enum Problem: LocalizedError {
        case unknown(sha256: String, size: Int), notESP32
        var errorDescription: String? {
            switch self {
            case .unknown(let sha, let size):
                "Not a firmware image FreeVela knows (\(size) bytes, SHA-256 \(sha.prefix(16))…). Only listed images can be installed."
            case .notESP32: "The file doesn't look like an ESP32 firmware image."
            }
        }
    }

    init(data: Data) throws {
        let data = Data(data)   // zero-based indices
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let image = FirmwareImage.known.first(where: { $0.sha256 == sha }), data.count == image.size else {
            throw Problem.unknown(sha256: sha, size: data.count)
        }
        // ESP-IDF app image header: magic 0xE9, segment count, chip id 0 (ESP32) at 12–13,
        // and the "SHA-256 appended" flag at 23 (the bike's esp_ota_end checks that hash).
        let h = [UInt8](data.prefix(24))
        guard h.count == 24, h[0] == 0xE9, (1...16).contains(h[1]), h[12] == 0, h[13] == 0, h[23] == 1 else {
            throw Problem.notESP32
        }
        self.data = data
        self.image = image
    }
}

/// Verified images kept on the phone, so a previous version can always be sent again.
enum FirmwareStore {
    private static var dir: URL {
        URL.applicationSupportDirectory.appending(path: "Firmware", directoryHint: .isDirectory)
    }

    static func save(_ c: CheckedImage) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try c.data.write(to: dir.appending(path: "\(c.image.sha256).bin"), options: .atomic)
    }

    /// Re-checks every stored file; anything that no longer verifies is skipped.
    static func all() -> [CheckedImage] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in (try? Data(contentsOf: url)).flatMap { try? CheckedImage(data: $0) } }
            .sorted { $0.image.name < $1.image.name }
    }
}

/// Sends a firmware image to the bike and confirms it took: success is only reported after the
/// bike restarts, unlocks again and reports the new version (see docs/protocol.md).
@MainActor
final class FirmwareUpdater: ObservableObject {
    enum Stage: Equatable {
        case idle
        case working(String)
        case sending(Double)
        case succeeded(String)
        case failed(String)
    }

    enum UpdateError: LocalizedError {
        case canceled, noService
        var errorDescription: String? {
            switch self {
            case .canceled: "Canceled."
            case .noService: "The bike doesn't offer the firmware update service."
            }
        }
    }

    @Published private(set) var stage: Stage = .idle
    var running: Bool {
        switch stage {
        case .working, .sending: true
        default: false
        }
    }

    static let minBattery = 40
    private var cancelRequested = false

    /// Boot time of the bike when a transfer was interrupted and its update session may still hold a
    /// partial image. The bike appends to that, so it has to be cleared first (or the bike restarted).
    private var dirtyBoot: Date? {
        get { UserDefaults.standard.object(forKey: "firmwareDirtyBoot") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "firmwareDirtyBoot") }
    }

    func cancel() { cancelRequested = true }

    /// When the bike booted, from `sys.live` (seconds since boot).
    private func bootTime(_ link: BikeLink) -> Date? {
        link.values["sys.live"].flatMap(Double.init).map { Date().addingTimeInterval(-$0) }
    }

    private func flag(_ link: BikeLink, _ path: String) -> Bool {
        link.values[path] == "1" || link.values[path] == "true"
    }

    /// Reasons an install can't start right now.
    func problems(_ link: BikeLink) -> [String] {
        guard link.isUnlocked else { return ["Connect and unlock the bike first."] }
        var out: [String] = []
        if link.firmwareChunkSize == nil { out.append(UpdateError.noService.localizedDescription) }
        if let fuel = link.values["pwr.fuel"].flatMap(Int.init) {
            if fuel < Self.minBattery { out.append("The battery is at \(fuel)%. Charge it to at least \(Self.minBattery)% first.") }
        } else {
            out.append("The battery level is unknown.")
        }
        if (link.values["motor.rps"].flatMap(Double.init) ?? 0) > 0 || flag(link, "pas.pedal") {
            out.append("The bike is moving. Stop it first.")
        }
        return out
    }

    /// Things to say in the confirmation before installing.
    func warnings(_ link: BikeLink, _ c: CheckedImage) -> [String] {
        var out: [String] = []
        if let fw = link.firmware {
            if fw.version == c.image.version && (fw.kind == .freeVela) == c.image.freeVela {
                out.append("The bike already runs \(fw.label). This reinstalls it.")
            } else if fw.kind == .freeVela && !c.image.freeVela {
                out.append("This replaces FreeVela firmware with Vela's original firmware.")
            }
        }
        if c.image.freeVela && link.firmware?.kind != .freeVela {
            out.append("If FreeVela can't unlock the bike within 10 minutes of installing, the bike switches back to its current firmware by itself.")
        }
        if !flag(link, "pwr.chr") { out.append("Plug in the charger if you can.") }
        let writes = (c.data.count + (link.firmwareChunkSize ?? 244) - 1) / (link.firmwareChunkSize ?? 244)
        let minutes = max(1, Int((Double(writes) * 0.05 / 60).rounded(.up)))
        out.append("Keep the phone next to the bike with FreeVela open until it finishes (about \(minutes) min).")
        return out
    }

    func install(_ c: CheckedImage, link: BikeLink) async {
        guard !running else { return }
        let blockers = problems(link)
        guard blockers.isEmpty else { stage = .failed(blockers.joined(separator: " ")); return }
        cancelRequested = false
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let log = link.log
        let from = link.firmware?.label ?? "unknown firmware"
        log.add(.info, "— firmware update: \(from) → \(c.image.label) (\(c.data.count) B, sha256 \(c.image.sha256.prefix(12))…) —")
        link.stopPolling()
        let started = Date()

        // 1. Clear a partial image left by an interrupted attempt, then send the new one.
        do {
            if let dirty = dirtyBoot, bootTime(link).map({ abs($0.timeIntervalSince(dirty)) < 15 }) ?? true {
                try await resetSession(link)
            } else {
                dirtyBoot = nil
            }
            try await transfer(c, link)
        } catch {
            await abandon(link, error)
            return
        }

        // 2. Ask the bike to install. It checks the image, and restarts only if it's valid.
        //    It may restart before answering, so a timeout or disconnect here is expected.
        stage = .working("Asking the bike to install it…")
        try? await Task.sleep(for: .milliseconds(200))
        do {
            try await link.writeFirmwareService(BikeProtocol.otaState, Data([1]), timeout: 30)
            log.add(.info, "install command acknowledged")
        } catch {
            log.add(.info, "install command: \(error.localizedDescription) (expected if the bike restarted)")
        }
        // Either way the bike's session is fresh now: it restarted, or it rejected the image and reset it.
        dirtyBoot = nil

        // 3. A valid image makes the bike restart, which drops the connection.
        stage = .working("Waiting for the bike to restart…")
        if !(await waitUntil(seconds: 30) { link.phase != .connected }) {
            _ = try? await link.read(BikeProtocol.state, quiet: true)
            link.startPolling()
            fail(log, "The bike didn't restart, so it didn't accept the image. It's still running \(link.firmware?.label ?? "its old firmware").")
            return
        }
        log.add(.info, "bike disconnected (restarting)")

        // 4. Reconnect and unlock.
        stage = .working("Reconnecting…")
        try? await Task.sleep(for: .seconds(5))
        let deadline = Date().addingTimeInterval(120)
        var unlocked = false
        while Date() < deadline {
            if await link.connectAndWait(timeout: 15), await link.unlock(progress: { _ in }) {
                unlocked = true
                break
            }
            try? await Task.sleep(for: .seconds(3))
        }
        guard unlocked else {
            fail(log, "The bike restarted, but FreeVela couldn't reconnect within 2 minutes. Wake the bike (hold the brake and the button), connect from the home screen, and check the firmware version there.")
            return
        }

        // 5. Only now decide: it must have restarted after we started, and report the new version.
        stage = .working("Checking the version…")
        let fw = link.firmware
        let versionOK = fw?.version == c.image.version && (fw?.kind == .freeVela) == c.image.freeVela
        let restarted = bootTime(link).map { $0 > started } ?? false
        if versionOK && restarted {
            stage = .succeeded("Installed. The bike restarted and reports \(fw!.label).")
            log.add(.ok, "firmware update confirmed: \(fw!.label)")
        } else if !versionOK {
            fail(log, "The bike restarted but reports \(fw?.label ?? "no version"), not \(c.image.label). The update didn't take effect.")
        } else {
            fail(log, "The bike reports \(fw!.label), but FreeVela couldn't confirm it restarted, so it can't confirm the install.")
        }
    }

    private func transfer(_ c: CheckedImage, _ link: BikeLink) async throws {
        guard let chunk = link.firmwareChunkSize, chunk >= 20 else { throw UpdateError.noService }
        let size = c.data.count
        link.log.add(.info, "sending \(size) B in \((size + chunk - 1) / chunk) writes of up to \(chunk) B")
        stage = .sending(0)
        dirtyBoot = bootTime(link) ?? .distantPast
        var offset = 0
        var lastTenth = 0
        // `offset < size`, not `<=`: no empty final write.
        while offset < size {
            if cancelRequested { throw UpdateError.canceled }
            let end = min(offset + chunk, size)
            // FreeVela firmware erases the update slot on the first write (Vela's does it at boot).
            try await link.writeFirmwareService(BikeProtocol.otaData, c.data.subdata(in: offset..<end),
                                                timeout: offset == 0 ? 30 : 6)
            offset = end
            let fraction = Double(offset) / Double(size)
            if Int(fraction * 1000) != Int((stage.sendingFraction ?? 0) * 1000) { stage = .sending(fraction) }
            if Int(fraction * 10) > lastTenth {
                lastTenth = Int(fraction * 10)
                link.log.add(.info, "sent \(lastTenth * 10)%")
            }
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    /// Clears a partial image: an install command on it fails the bike's image check, and the
    /// bike then starts a fresh session (erasing the update partition, which takes a few seconds).
    private func resetSession(_ link: BikeLink) async throws {
        stage = .working("Clearing an earlier, interrupted update…")
        link.log.add(.info, "clearing the bike's partial update session")
        try? await link.writeFirmwareService(BikeProtocol.otaState, Data([1]), timeout: 30)
        try await Task.sleep(for: .seconds(15))
        guard link.phase == .connected else { throw BikeLink.LinkError.notConnected }
        dirtyBoot = nil
    }

    private func abandon(_ link: BikeLink, _ error: Error) async {
        if link.phase == .connected, dirtyBoot != nil { try? await resetSession(link) }
        if link.phase == .connected { link.startPolling() }
        var why = (error as? UpdateError) == .canceled ? "Canceled." : "The transfer stopped: \(error.localizedDescription)."
        why += " The bike is still on its old firmware."
        if dirtyBoot != nil {
            why += " It may be holding part of the image; FreeVela clears that before the next attempt, or you can restart the bike."
        }
        fail(link.log, why)
    }

    private func fail(_ log: LabLog, _ message: String) {
        stage = .failed(message)
        log.add(.error, "firmware update: \(message)")
    }

    private func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return condition()
    }
}

extension FirmwareUpdater.Stage {
    var sendingFraction: Double? {
        if case .sending(let f) = self { return f }
        return nil
    }
}
