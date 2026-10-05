import CommonCrypto
import Foundation

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

extension BikeLink {
    /// The bike answers STATE with the text "undefined" until it's unlocked.
    var isUnlocked: Bool { !values.isEmpty }

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
