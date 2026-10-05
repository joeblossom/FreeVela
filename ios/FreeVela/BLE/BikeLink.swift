import CoreBluetooth
import Foundation

/// Thin CoreBluetooth wrapper for the Lab. Every step (scan, connect, each
/// read/write) is individually callable and logs raw results, because the
/// protocol is still being confirmed. Key bytes never reach the log.
@MainActor
final class BikeLink: NSObject, ObservableObject {
    struct Found: Identifiable {
        let peripheral: CBPeripheral
        var name: String?
        var rssi: Int
        var services: [CBUUID]
        /// The bike's device id from the scan response (the id in key backups), lowercase hex.
        var deviceID: String?
        var id: UUID { peripheral.identifier }
        var advertisesVela: Bool { services.contains(where: BikeProtocol.scanServices.contains) }
    }

    enum Phase: String { case idle, scanning, connecting, connected, disconnected }

    enum LinkError: LocalizedError {
        case notConnected, noCharacteristic(CBUUID), timeout, refused(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: "not connected"
            case .noCharacteristic(let u): "characteristic \(BikeProtocol.name(of: u) ?? u.uuidString) not found"
            case .timeout: "timed out"
            case .refused(let why): why
            }
        }
    }

    @Published private(set) var bluetooth: CBManagerState = .unknown
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var found: [Found] = []
    @Published private(set) var services: [CBService] = []
    @Published private(set) var notifying = false
    @Published private(set) var stateText = ""
    @Published private(set) var changedPaths: Set<String> = []
    /// Flattened state ("pwr.fuel" → "24"), empty until the bike sends real JSON.
    @Published private(set) var values: [String: String] = [:]
    /// Firmware version and capabilities, from the latest STATE.
    @Published private(set) var firmware: FirmwareInfo?
    /// GATT discovered and ready for reads/writes.
    @Published private(set) var ready = false

    let log: LabLog
    /// The selected bike — used for auth writes and to redact key bytes in logs.
    var bike: BikeKeys?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var pendingReads: [CBUUID: (token: UUID, cont: CheckedContinuation<Data, Error>)] = [:]
    private var pendingWrites: [CBUUID: (token: UUID, cont: CheckedContinuation<Void, Error>)] = [:]
    private var stateBuffer = Data()
    private var lastState: [String: String] = [:]
    private var readyWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var quietReads: Set<CBUUID> = []
    private var pollTask: Task<Void, Never>?
    /// Async locks: one per characteristic (so GATT ops wait their turn instead of
    /// superseding each other) plus "command" (so multi-step commands don't interleave).
    private var held: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    /// Bumped on each assist request; queued requests that are no longer the latest are skipped.
    private var assistGeneration = 0

    init(log: LabLog) {
        self.log = log
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var connectedName: String? { peripheral?.name }

    /// The device id of the connected (or last) bike, from its advertisement.
    var connectedDeviceID: String? {
        guard let p = peripheral else { return nil }
        return found.first { $0.id == p.identifier }?.deviceID
    }

    // MARK: Scan / connect

    func startScan(quiet: Bool = false) {
        guard bluetooth == .poweredOn else { log.add(.error, "Bluetooth is \(bluetooth.label)"); return }
        found = []
        phase = .scanning
        // No service filter: the bike may not advertise its service UUIDs.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        if !quiet { log.add(.info, "scanning") }
    }

    func stopScan() {
        central.stopScan()
        if phase == .scanning { phase = .idle }
    }

    func connect(_ f: Found) {
        connect(f.peripheral)
    }

    func connect(_ p: CBPeripheral) {
        central.stopScan()
        // Ignore repeat taps on the bike we're already connecting/connected to.
        if p === peripheral, phase == .connecting || phase == .connected { return }
        disconnect()
        peripheral = p
        p.delegate = self
        phase = .connecting
        ready = false
        log.add(.info, "connecting to \(p.name ?? "unnamed") [\(p.identifier.uuidString.prefix(8))]")
        central.connect(p)
    }

    func disconnect() {
        if let p = peripheral, phase == .connecting || phase == .connected { central.cancelPeripheralConnection(p) }
    }

    /// Connects (or reconnects to the last bike) and waits until GATT is discovered.
    func connectAndWait(_ p: CBPeripheral? = nil, timeout: TimeInterval = 10) async -> Bool {
        guard let target = p ?? peripheral else { return false }
        if target === peripheral, ready { return true }
        connect(target)
        let token = UUID()
        return await withCheckedContinuation { cont in
            readyWaiters[token] = cont
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.readyWaiters.removeValue(forKey: token)?.resume(returning: false)
            }
        }
    }

    private func resolveReady(_ ok: Bool) {
        ready = ok
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.values.forEach { $0.resume(returning: ok) }
    }

    /// Scans for up to `timeout` seconds and returns the most likely bike:
    /// name containing the device id, then "Vela"-named, then advertising Vela services.
    /// `quiet` (background looking) only logs when it finds the bike.
    func findBike(timeout: TimeInterval = 10, quiet: Bool = false) async -> CBPeripheral? {
        startScan(quiet: quiet)
        defer { stopScan() }
        let start = Date()
        var firstSeen: Date?
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(for: .milliseconds(400))
            if let best = bestBike() {
                if likeliness(best) == 4 { break }   // this bike, by its id
                firstSeen = firstSeen ?? Date()
                // Give it a moment to collect RSSI from nearby candidates.
                if Date().timeIntervalSince(firstSeen!) > 1.5 { break }
            }
        }
        let best = bestBike()
        if let best {
            log.add(.info, "found \(best.name ?? "bike") rssi \(best.rssi)")
        } else if !quiet {
            log.add(.error, "no bike found nearby")
        }
        return best?.peripheral
    }

    /// 4: broadcasts this bike's device id. 0: broadcasts a different id (someone else's Vela).
    /// Otherwise by name and services, for bikes whose id isn't known (yet).
    func likeliness(_ f: Found) -> Int {
        if let id = bike?.id, !bike!.hasPendingID, let seen = f.deviceID {
            return seen.caseInsensitiveCompare(id) == .orderedSame ? 4 : 0
        }
        let name = f.name ?? ""
        if let id = bike?.id, name.localizedCaseInsensitiveContains(id) { return 3 }
        if name.localizedCaseInsensitiveContains("vela") { return 2 }
        return f.advertisesVela ? 1 : 0
    }

    private func bestBike() -> Found? {
        found.filter { likeliness($0) > 0 }.max { (likeliness($0), $0.rssi) < (likeliness($1), $1.rssi) }
    }

    // MARK: GATT operations

    func characteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        services.lazy.compactMap(\.characteristics).joined().first { $0.uuid == uuid }
    }

    private func acquire(_ key: String) async {
        if held.insert(key).inserted { return }
        await withCheckedContinuation { waiters[key, default: []].append($0) }
        // Ownership is handed over by release(); `held` still contains key.
    }

    private func release(_ key: String) {
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue
            next.resume()
        } else {
            held.remove(key)
        }
    }

    /// `quiet` skips logging the request and raw value (used for background polling).
    @discardableResult
    func read(_ uuid: CBUUID, quiet: Bool = false) async throws -> Data {
        guard let p = peripheral, phase == .connected else { throw LinkError.notConnected }
        guard let c = characteristic(uuid) else { throw LinkError.noCharacteristic(uuid) }
        let lock = "gatt:" + uuid.uuidString
        await acquire(lock)
        defer { release(lock) }
        guard phase == .connected else { throw LinkError.notConnected }
        if !quiet { log.add(.tx, "read \(label(uuid))") }
        let token = UUID()
        return try await withCheckedThrowingContinuation { cont in
            pendingReads[uuid]?.cont.resume(throwing: LinkError.refused("superseded by a newer read"))
            pendingReads[uuid] = (token, cont)
            if quiet { quietReads.insert(uuid) } else { quietReads.remove(uuid) }
            p.readValue(for: c)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.pendingReads[uuid]?.token == token else { return }
                self.pendingReads.removeValue(forKey: uuid)?.cont.resume(throwing: LinkError.timeout)
            }
        }
    }

    /// `logAs` replaces the bytes in the log, for values derived from the bike's secrets.
    func write(_ uuid: CBUUID, _ data: Data, logAs: String? = nil) async throws {
        guard let p = peripheral, phase == .connected else { throw LinkError.notConnected }
        guard let c = characteristic(uuid) else { throw LinkError.noCharacteristic(uuid) }
        if c.service?.uuid == BikeProtocol.firmwareService {
            throw LinkError.refused("refusing to write to the firmware service (use Firmware update)")
        }
        let lock = "gatt:" + uuid.uuidString
        await acquire(lock)
        defer { release(lock) }
        guard phase == .connected else { throw LinkError.notConnected }
        log.add(.tx, "write \(label(uuid)) \(logAs ?? describe(data))")
        guard c.properties.contains(.write) else {
            p.writeValue(data, for: c, type: .withoutResponse)
            log.add(.info, "(write without response — no confirmation)")
            return
        }
        try await writeWithResponse(p, c, data, timeout: 6)
    }

    /// Writes to the firmware update service. Only FirmwareUpdater calls this, and
    /// individual writes aren't logged (an image is thousands of them).
    func writeFirmwareService(_ uuid: CBUUID, _ data: Data, timeout: TimeInterval = 6) async throws {
        guard let p = peripheral, phase == .connected else { throw LinkError.notConnected }
        guard let c = characteristic(uuid), c.service?.uuid == BikeProtocol.firmwareService else {
            throw LinkError.noCharacteristic(uuid)
        }
        guard c.properties.contains(.write) else { throw LinkError.refused("\(label(uuid)) doesn't confirm writes") }
        let lock = "gatt:" + uuid.uuidString
        await acquire(lock)
        defer { release(lock) }
        guard phase == .connected else { throw LinkError.notConnected }
        try await writeWithResponse(p, c, data, timeout: timeout)
    }

    /// Largest firmware chunk that fits in one ATT packet (MTU − 3). Larger "with response"
    /// writes become long (prepared) writes on iOS, which the bike may not support.
    var firmwareChunkSize: Int? {
        guard let p = peripheral, phase == .connected, characteristic(BikeProtocol.otaData) != nil else { return nil }
        return min(p.maximumWriteValueLength(for: .withoutResponse), 509)
    }

    private func writeWithResponse(_ p: CBPeripheral, _ c: CBCharacteristic, _ data: Data, timeout: TimeInterval) async throws {
        let uuid = c.uuid
        let token = UUID()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pendingWrites[uuid]?.cont.resume(throwing: LinkError.refused("superseded by a newer write"))
            pendingWrites[uuid] = (token, cont)
            p.writeValue(data, for: c, type: .withResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, self.pendingWrites[uuid]?.token == token else { return }
                self.pendingWrites.removeValue(forKey: uuid)?.cont.resume(throwing: LinkError.timeout)
            }
        }
    }

    func setNotify(_ on: Bool, _ uuid: CBUUID = BikeProtocol.state) {
        guard let p = peripheral, let c = characteristic(uuid) else { log.add(.error, "notify: \(LinkError.noCharacteristic(uuid).localizedDescription)"); return }
        log.add(.tx, "\(on ? "subscribe" : "unsubscribe") \(label(uuid))")
        p.setNotifyValue(on, for: c)
    }

    /// Runs `op`, logging success or the full error (CoreBluetooth ATT codes included).
    func attempt(_ what: String, _ op: () async throws -> Void) async {
        do {
            try await op()
            log.add(.ok, what)
        } catch {
            log.add(.error, "\(what): \(errorText(error))")
        }
    }

    // MARK: Keys

    /// Replaces the bike's key: RELEASE ← current key (the bike forgets it), then KEY ← the new key
    /// (the bike registers it and stays unlocked). Returns the new keys once the bike has them; the
    /// caller must save them. If KEY fails after RELEASE, the bike has no key and the next unlock
    /// re-pairs it with the old one.
    func resetKeys() async -> BikeKeys? {
        guard isUnlocked, let bike, let old = bike.keyBytes else { log.add(.error, "unlock the bike first"); return nil }
        let new = bike.withNewKeys()
        guard let newKey = new.keyBytes else { return nil }
        await acquire("command")
        defer { release("command") }
        log.add(.info, "— reset keys (old fp \(BikeKeys.fingerprint(old)), new fp \(BikeKeys.fingerprint(newKey))) —")
        do {
            try await write(BikeProtocol.release, old, logAs: "<current key>")
            try await write(BikeProtocol.key, newKey, logAs: "<new key>")
            try await Task.sleep(for: .milliseconds(300))
            // A bike that didn't take the key answers "undefined" instead of JSON.
            guard try await read(BikeProtocol.state).first == UInt8(ascii: "{") else {
                log.add(.error, "reset keys: the bike didn't accept the new key")
                return nil
            }
        } catch {
            log.add(.error, "reset keys: \(errorText(error))")
            return nil
        }
        log.add(.ok, "keys reset")
        return new
    }

    // MARK: New owner

    /// FreeVela 0.2.0+: the public status (firmware, owner key, trial, reset hold, battery).
    /// Nil on Vela's firmware, which doesn't have it.
    func readInfo() async -> BikeInfo? {
        guard characteristic(BikeProtocol.fvInfo) != nil,
              let data = try? await read(BikeProtocol.fvInfo, quiet: true) else { return nil }
        return try? JSONDecoder().decode(BikeInfo.self, from: data)
    }

    enum PairResult { case paired, alreadyOwned, failed }

    /// Gives a bike that has no owner key this phone's new key. The bike registers it and unlocks;
    /// a bike that already has an owner refuses and disconnects.
    func pairNewOwner(_ keys: BikeKeys) async -> PairResult {
        guard let key = keys.keyBytes else { return .failed }
        bike = keys
        await acquire("command")
        defer { release("command") }
        log.add(.info, "— pair as new owner (fp \(BikeKeys.fingerprint(key))) —")
        do {
            try await write(BikeProtocol.key, key, logAs: "<new key>")
            try await Task.sleep(for: .milliseconds(300))
            guard try await read(BikeProtocol.state).first == UInt8(ascii: "{") else {
                log.add(.error, "pair: the bike didn't accept the key (it may already have an owner)")
                return .alreadyOwned
            }
        } catch {
            log.add(.error, "pair: \(errorText(error))")
            return phase == .connected ? .failed : .alreadyOwned
        }
        log.add(.ok, "paired as the new owner")
        setNotify(true)
        startPolling()
        return .paired
    }

    /// Sends one action, in order with any other commands.
    func dispatch(_ json: String, base64Text: Bool) async {
        await acquire("command")
        defer { release("command") }
        await sendAction(json, base64Text: base64Text)
    }

    /// The write + read-back; callers hold the "command" lock.
    private func sendAction(_ json: String, base64Text: Bool) async {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: raw)) != nil else {
            log.add(.error, "not valid JSON: \(trimmed)")
            return
        }
        let payload = base64Text ? Data(raw.base64EncodedString().utf8) : raw
        await attempt("dispatch\(base64Text ? " (base64 text)" : "")") {
            try await write(BikeProtocol.dispatch, payload)
        }
        // The bike doesn't reliably notify, so read back the result.
        try? await Task.sleep(for: .milliseconds(400))
        _ = try? await read(BikeProtocol.state, quiet: true)
    }

    func setAssist(_ mode: BikeProtocol.AssistMode) async {
        await setAssist(saver: mode.saver)
    }

    /// Assist on, using the eco curve at or below `percent` battery
    /// (100 = always eco, 0 = never). Any value 0–100 works.
    func setEcoThreshold(_ percent: Int) async {
        await setAssist(saver: min(max(percent, 0), 100))
    }

    /// nil = motor off; otherwise saver level then ASSIST_SET 1.
    /// Rapid requests collapse: only the latest one queued actually runs.
    private func setAssist(saver: Int?) async {
        assistGeneration += 1
        let generation = assistGeneration
        await acquire("command")
        defer { release("command") }
        guard generation == assistGeneration else { return }   // a newer request is queued
        if let saver {
            await sendAction(#"{"type":"pwr/SAVER_UPDATED","payload":\#(saver)}"#, base64Text: false)
            try? await Task.sleep(for: .milliseconds(150))
            await sendAction(#"{"type":"motor/ASSIST_SET","payload":1}"#, base64Text: false)
        } else {
            await sendAction(#"{"type":"motor/ASSIST_SET","payload":0}"#, base64Text: false)
        }
    }

    /// Sounds the siren via alarm/TRIGGER (15 s, set by the firmware), then
    /// clears the trigger and wheel lock with DESARM, re-arming if it was armed.
    func soundAlarm() async {
        let wasArmed = values["alarm.armed"] == "1" || values["alarm.armed"] == "true"
        await dispatch(#"{"type":"alarm/TRIGGER"}"#, base64Text: false)
        try? await Task.sleep(for: .seconds(15.5))
        await acquire("command")
        defer { release("command") }
        await sendAction(#"{"type":"alarm/DESARM"}"#, base64Text: false)
        if wasArmed {
            try? await Task.sleep(for: .milliseconds(300))
            await sendAction(#"{"type":"alarm/ARM"}"#, base64Text: false)
        }
    }

    /// The bike doesn't send STATE notifications (as of firmware 2306052112),
    /// so poll it while connected. State changes are still logged by feedState.
    /// How often STATE is read while connected; the ride recorder shortens it.
    var pollInterval: Duration = .seconds(1.5)

    func startPolling() {
        let interval = pollInterval
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, self.phase == .connected, self.ready else { return }
                _ = try? await self.read(BikeProtocol.state, quiet: true)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: State handling

    #if DEBUG
    /// Simulator screenshots (launch with `-demo`): a sample unlocked bike on FreeVela firmware.
    func loadDemoState(rps: Double = 4.2, assist: (ast: Int, save: Int) = (1, 20)) {
        let json = #"{"sys":{"idle":0,"ver":"2306052112"},"alarm":{"armed":false},"pas":{"pedal":true},"#
            + #""light":{"mode":0},"pwr":{"fuel":78,"save":\#(assist.save),"chr":0},"button":false,"#
            + #""motor":{"boost":false,"rps":"\#(rps)","pulse":3302820,"brk":false,"ast":\#(assist.ast),"ebc":1},"#
            + #""fv":{"ver":"0.2.0-beta2","caps":["key-reset","sleep-timer","motor-tune"],"trial":0,"lock":1,"sleep":0,"#
            + #""tune":{"top":4.276,"btn":0,"mg":18,"sl":29,"cr":0.4},"live":{"out":225,"crv":"drive"}}}"#
        feedState(Data(json.utf8))
    }
    #endif

    /// STATE may arrive split across notifications if it's larger than the MTU,
    /// so buffer until it parses.
    private func feedState(_ data: Data) {
        if data.first == UInt8(ascii: "{") { stateBuffer = data } else { stateBuffer.append(data) }
        guard let obj = try? JSONSerialization.jsonObject(with: stateBuffer) as? [String: Any] else {
            if stateBuffer.count > 16_384 { stateBuffer = Data() }
            else if stateBuffer.first == UInt8(ascii: "{") { log.add(.info, "STATE partial (\(stateBuffer.count) bytes buffered)") }
            return
        }
        stateBuffer = Data()
        var flat: [String: String] = [:]
        flatten(obj, into: &flat)
        let changes = flat.keys.sorted().filter { lastState[$0] != flat[$0] }
        // sys.date / sys.live tick every second, fv.live is the live throttle and fv.adc raw readings;
        // leave them out of the log.
        let noteworthy = changes.filter {
            $0 != "sys.date" && $0 != "sys.live" && !$0.hasPrefix("fv.live.") && !$0.hasPrefix("fv.adc.")
        }
        if !lastState.isEmpty && !noteworthy.isEmpty {
            log.add(.info, "STATE changed: " + noteworthy.map { "\($0) \(lastState[$0] ?? "∅")→\(flat[$0]!)" }.joined(separator: ", "))
        }
        changedPaths = Set(changes)
        lastState = flat
        values = flat
        if let info = FirmwareInfo(state: obj), info != firmware {
            if firmware == nil || firmware?.version != info.version {
                log.add(.info, "firmware: \(info.label), capabilities: \(info.capabilities.map(\.rawValue).sorted().joined(separator: ", "))")
            }
            firmware = info
        }
        if let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            stateText = String(decoding: pretty, as: UTF8.self)
        }
    }

    private func flatten(_ value: Any, prefix: String = "", into out: inout [String: String]) {
        if let dict = value as? [String: Any] {
            for (k, v) in dict { flatten(v, prefix: prefix.isEmpty ? k : "\(prefix).\(k)", into: &out) }
        } else {
            out[prefix] = "\(value)"
        }
    }

    // MARK: Formatting

    func label(_ uuid: CBUUID) -> String {
        BikeProtocol.name(of: uuid) ?? uuid.uuidString
    }

    /// Human-readable bytes, with the bike's secrets replaced by placeholders.
    func describe(_ data: Data) -> String {
        if data.isEmpty { return "(empty)" }
        if let b = bike {
            if data == b.keyBytes { return "<key, \(data.count) bytes, fp \(BikeKeys.fingerprint(data))>" }
            if data == b.releasedKeyBytes { return "<releasedKey, \(data.count) bytes, fp \(BikeKeys.fingerprint(data))>" }
        }
        if let s = String(data: data, encoding: .utf8), s.allSatisfy({ !$0.isASCII || $0.isPrintable }) {
            return "\(data.count)B \"\(s)\""
        }
        return "\(data.count)B 0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    private func errorText(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == CBATTErrorDomain || ns.domain == CBErrorDomain {
            return "\(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
        }
        return error.localizedDescription
    }

    private func failPending(_ error: Error) {
        pendingReads.values.forEach { $0.cont.resume(throwing: error) }
        pendingWrites.values.forEach { $0.cont.resume(throwing: error) }
        pendingReads.removeAll()
        pendingWrites.removeAll()
    }
}

// MARK: - CBCentralManagerDelegate

extension BikeLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetooth = central.state
            log.add(.info, "Bluetooth \(central.state.label)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
            let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
            let deviceID = serviceData?[BikeProtocol.authService].map { $0.map { String(format: "%02x", $0) }.joined() }
            let rssi = RSSI.intValue
            if let i = found.firstIndex(where: { $0.id == peripheral.identifier }) {
                found[i].rssi = rssi
                if let name { found[i].name = name }
                if !uuids.isEmpty { found[i].services = uuids }
                if let deviceID { found[i].deviceID = deviceID }
            } else {
                found.append(Found(peripheral: peripheral, name: name, rssi: rssi, services: uuids, deviceID: deviceID))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            phase = .connected
            services = []
            lastState = [:]
            stateText = ""
            log.add(.ok, "connected to \(peripheral.name ?? "unnamed")")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            phase = .disconnected
            resolveReady(false)
            log.add(.error, "connect failed: \(error.map(errorText) ?? "unknown")")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            phase = .disconnected
            notifying = false
            values = [:]
            firmware = nil
            resolveReady(false)
            failPending(LinkError.notConnected)
            log.add(error == nil ? .info : .error, "disconnected\(error.map { ": " + errorText($0) } ?? "")")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BikeLink: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error { log.add(.error, "service discovery: \(errorText(error))"); return }
            for s in peripheral.services ?? [] {
                log.add(.rx, "service \(label(s.uuid))")
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            if let error { log.add(.error, "characteristics of \(label(service.uuid)): \(errorText(error))"); return }
            for c in service.characteristics ?? [] {
                log.add(.rx, "  char \(label(c.uuid)) [\(c.properties.label)]")
            }
            services = peripheral.services ?? []
            let done = services.allSatisfy { $0.characteristics != nil }
            if done {
                resolveReady(true)
                log.add(.info, "GATT discovered. Max write: \(peripheral.maximumWriteValueLength(for: .withResponse))B with response, \(peripheral.maximumWriteValueLength(for: .withoutResponse))B without")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            let uuid = characteristic.uuid
            let pending = pendingReads.removeValue(forKey: uuid)
            if let error {
                if let pending { pending.cont.resume(throwing: error) } else { log.add(.error, "\(label(uuid)): \(errorText(error))") }
                return
            }
            let data = characteristic.value ?? Data()
            let quiet = pending != nil && quietReads.remove(uuid) != nil
            if !quiet { log.add(.rx, "\(pending == nil ? "notify" : "value") \(label(uuid)) \(describe(data))") }
            if uuid == BikeProtocol.state { feedState(data) }
            pending?.cont.resume(returning: data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let pending = pendingWrites.removeValue(forKey: characteristic.uuid) else { return }
            if let error { pending.cont.resume(throwing: error) } else { pending.cont.resume() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                log.add(.error, "notify \(label(characteristic.uuid)): \(errorText(error))")
            } else {
                log.add(.ok, "notify \(label(characteristic.uuid)) \(characteristic.isNotifying ? "on" : "off")")
            }
            if characteristic.uuid == BikeProtocol.state { notifying = characteristic.isNotifying }
        }
    }
}

// MARK: - Labels

extension CBManagerState {
    var label: String {
        switch self {
        case .poweredOn: "on"
        case .poweredOff: "off"
        case .unauthorized: "not permitted (Settings → FreeVela → Bluetooth)"
        case .unsupported: "unsupported"
        case .resetting: "resetting"
        default: "unknown"
        }
    }
}

extension CBCharacteristicProperties {
    var label: String {
        var parts: [String] = []
        if contains(.read) { parts.append("read") }
        if contains(.write) { parts.append("write") }
        if contains(.writeWithoutResponse) { parts.append("writeNR") }
        if contains(.notify) { parts.append("notify") }
        if contains(.indicate) { parts.append("indicate") }
        if contains(.authenticatedSignedWrites) { parts.append("signed") }
        return parts.joined(separator: " ")
    }
}

private extension Character {
    var isPrintable: Bool { isASCII && (asciiValue! >= 0x20 && asciiValue! < 0x7f || self == "\n" || self == "\t") }
}
