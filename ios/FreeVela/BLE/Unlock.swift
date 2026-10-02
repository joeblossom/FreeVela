import CommonCrypto
import CryptoKit
import Foundation

/// The bike sends a 16-byte CHALLENGE and expects a response on KEY derived
/// from it and the per-bike secret. The exact transform isn't known yet
/// (see docs/protocol.md), so we try plausible ones and remember what works.
struct UnlockMethod: Identifiable {
    let id: String
    let label: String
    /// Write RELEASE ← releasedKey before KEY.
    var writeRelease = false
    let response: (_ challenge: Data, _ bike: BikeKeys) -> Data?

    static let all: [UnlockMethod] = {
        typealias Secret = (name: String, bytes: (BikeKeys) -> Data?)
        let secrets: [Secret] = [("key", \.keyBytes), ("releasedKey", \.releasedKeyBytes)]
        var list: [UnlockMethod] = [
            UnlockMethod(id: "raw", label: "key as-is") { _, b in b.keyBytes },
            UnlockMethod(id: "raw+release", label: "releasedKey → RELEASE, then key as-is", writeRelease: true) { _, b in b.keyBytes },
        ]
        for s in secrets {
            let n = s.name
            list += [
                UnlockMethod(id: "hmac-\(n)", label: "HMAC-SHA256(\(n), challenge)") { c, b in
                    s.bytes(b).map { Data(HMAC<SHA256>.authenticationCode(for: c, using: SymmetricKey(data: $0))) }
                },
                UnlockMethod(id: "hmac-rev-\(n)", label: "HMAC-SHA256(challenge, \(n))") { c, b in
                    s.bytes(b).map { Data(HMAC<SHA256>.authenticationCode(for: $0, using: SymmetricKey(data: c))) }
                },
                UnlockMethod(id: "sha-c\(n)", label: "SHA256(challenge + \(n))") { c, b in
                    s.bytes(b).map { Data(SHA256.hash(data: c + $0)) }
                },
                UnlockMethod(id: "sha-\(n)c", label: "SHA256(\(n) + challenge)") { c, b in
                    s.bytes(b).map { Data(SHA256.hash(data: $0 + c)) }
                },
                UnlockMethod(id: "aes256enc-\(n)", label: "AES-256-ECB encrypt(challenge) with \(n)") { c, b in
                    s.bytes(b).flatMap { aesECB(c, key: $0, encrypt: true) }
                },
                UnlockMethod(id: "aes256dec-\(n)", label: "AES-256-ECB decrypt(challenge) with \(n)") { c, b in
                    s.bytes(b).flatMap { aesECB(c, key: $0, encrypt: false) }
                },
                UnlockMethod(id: "aes128enc-\(n)", label: "AES-128-ECB encrypt(challenge) with first half of \(n)") { c, b in
                    s.bytes(b).flatMap { aesECB(c, key: $0.prefix(16), encrypt: true) }
                },
                UnlockMethod(id: "xor-\(n)", label: "challenge XOR first half of \(n)") { c, b in
                    s.bytes(b).map { Data(zip(c, $0.prefix(16)).map { $0 ^ $1 }) }
                },
            ]
        }
        // Try AES-ECB decrypt of the challenge first.
        list.insert(UnlockMethod(id: "aes256dec-key+release", label: "releasedKey → RELEASE, then AES-256-ECB decrypt(challenge) with key", writeRelease: true) { c, b in
            b.keyBytes.flatMap { aesECB(c, key: $0, encrypt: false) }
        }, at: 0)
        let first = ["aes256dec-key", "aes256dec-key+release", "aes256dec-releasedKey", "aes256enc-key", "aes256enc-releasedKey"]
        return first.compactMap { id in list.first { $0.id == id } } + list.filter { !first.contains($0.id) }
    }()
}

/// The unlock handshake (docs/protocol.md):
/// response = AES-256-CBC-decrypt(challenge, key: key, iv: current value of KEY),
/// written to CHALLENGE. If CHALLENGE is empty, `key` is written to KEY instead.
func challengeResponse(challenge: Data, iv: Data, key: Data) -> Data? {
    guard challenge.count % 16 == 0, iv.count == 16, key.count == 32 else { return nil }
    var out = Data(count: challenge.count + kCCBlockSizeAES128)
    var moved = 0
    let outCount = out.count
    let status = out.withUnsafeMutableBytes { o in
        challenge.withUnsafeBytes { d in
            key.withUnsafeBytes { k in
                iv.withUnsafeBytes { v in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(0),
                            k.baseAddress, key.count, v.baseAddress, d.baseAddress, challenge.count, o.baseAddress, outCount, &moved)
                }
            }
        }
    }
    return status == kCCSuccess ? out.prefix(moved) : nil
}

private func aesECB(_ data: Data, key: Data, encrypt: Bool) -> Data? {
    var out = Data(count: data.count + kCCBlockSizeAES128)
    var moved = 0
    let outCount = out.count
    let status = out.withUnsafeMutableBytes { o in
        data.withUnsafeBytes { d in
            key.withUnsafeBytes { k in
                CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                        k.baseAddress, key.count, nil, d.baseAddress, data.count, o.baseAddress, outCount, &moved)
            }
        }
    }
    return status == kCCSuccess ? out.prefix(moved) : nil
}

extension BikeLink {
    private static let methodKey = "unlockMethod."

    func knownMethod(for bike: BikeKeys) -> UnlockMethod? {
        let id = UserDefaults.standard.string(forKey: Self.methodKey + bike.id)
        return UnlockMethod.all.first { $0.id == id }
    }

    /// The bike answers STATE with the text "undefined" until it's unlocked.
    var isUnlocked: Bool { !values.isEmpty }

    /// One attempt: read CHALLENGE, write the response, then check STATE.
    func tryUnlock(_ m: UnlockMethod) async -> Bool {
        guard let bike else { return false }
        guard await connectAndWait() else { log.add(.error, "couldn't (re)connect"); return false }
        log.add(.info, "— trying: \(m.label) —")
        do {
            let challenge = try await read(BikeProtocol.challenge)
            guard let response = m.response(challenge, bike) else { log.add(.error, "couldn't compute response"); return false }
            if m.writeRelease, let rel = bike.releasedKeyBytes { try await write(BikeProtocol.release, rel) }
            log.add(.tx, "response \(response.count)B fp \(BikeKeys.fingerprint(response))")
            try await write(BikeProtocol.key, response)
            try await Task.sleep(for: .milliseconds(300))
            try await read(BikeProtocol.state)
        } catch {
            log.add(.error, "\(m.label): \(error.localizedDescription)")
            await resetConnection()
            return false
        }
        if isUnlocked {
            UserDefaults.standard.set(m.id, forKey: Self.methodKey + bike.id)
            log.add(.ok, "UNLOCKED with: \(m.label)")
            setNotify(true)
            startPolling()
            return true
        }
        // Start the next attempt from a fresh connection (and a fresh challenge).
        await resetConnection()
        return false
    }

    private func resetConnection() async {
        disconnect()
        for _ in 0..<30 where phase == .connected || phase == .connecting {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The unlock handshake (see challengeResponse).
    func unlockHandshake(writeRelease: Bool = true) async -> Bool {
        guard let bike, let key = bike.keyBytes else { log.add(.error, "load a bike's keys first"); return false }
        guard await connectAndWait() else { log.add(.error, "couldn't (re)connect"); return false }
        log.add(.info, "— unlock handshake (write RELEASE: \(writeRelease ? "yes" : "no")) —")
        do {
            try await read(BikeProtocol.release)
            if writeRelease, let rel = bike.releasedKeyBytes {
                try await write(BikeProtocol.release, rel)
            }
            let challenge = try await read(BikeProtocol.challenge)
            let iv = try await read(BikeProtocol.key)
            if challenge.isEmpty {
                try await write(BikeProtocol.key, key)
            } else {
                guard let response = challengeResponse(challenge: challenge, iv: iv, key: key) else {
                    log.add(.error, "can't compute response (challenge \(challenge.count)B, KEY/IV \(iv.count)B)")
                    return false
                }
                try await write(BikeProtocol.challenge, response,
                                logAs: "<response \(response.count)B, fp \(BikeKeys.fingerprint(response))>")
            }
            try await Task.sleep(for: .milliseconds(300))
            try await read(BikeProtocol.state)
        } catch {
            log.add(.error, "handshake: \(error.localizedDescription)")
            await resetConnection()
            return false
        }
        if isUnlocked {
            log.add(.ok, "UNLOCKED")
            setNotify(true)
            startPolling()
            return true
        }
        log.add(.error, "handshake finished but STATE is still locked")
        await resetConnection()
        return false
    }

    func unlock(progress: (String) -> Void) async -> Bool {
        progress("Unlocking…")
        if await unlockHandshake(writeRelease: true) { return true }
        progress("Retrying without releasing the key…")
        if await unlockHandshake(writeRelease: false) { return true }
        log.add(.error, "unlock failed — share this log")
        return false
    }
}
