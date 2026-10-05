import Foundation
import CryptoKit

/// One bike's credentials. `key` / `releasedKey` are the base64 strings from
/// Vela's Firestore record; on the wire we send the decoded 32 bytes.
struct BikeKeys: Codable, Identifiable, Hashable {
    var id: String            // BLE device id (Firestore doc id)
    var key: String
    var releasedKey: String
    var displayName: String?
    var sku: String?
    var serial: String?

    var keyBytes: Data? { Data(base64Encoded: key.trimmingCharacters(in: .whitespaces)) }
    var releasedKeyBytes: Data? { Data(base64Encoded: releasedKey.trimmingCharacters(in: .whitespaces)) }

    var title: String { displayName ?? id }
    /// Keys pasted without a device id get a temporary one until the bike's own id is known.
    static func pendingID() -> String { "pending-" + UUID().uuidString.prefix(8).lowercased() }
    var hasPendingID: Bool { id.hasPrefix("pending-") }

    /// What the screens call the bike.
    var name: String { displayName ?? "My Bike" }

    /// The same bike with a fresh random key and releasedKey. They must differ: the app writes
    /// releasedKey to RELEASE on each unlock, and the bike forgets its key if RELEASE matches it.
    func withNewKeys() -> BikeKeys {
        var b = self
        b.key = Self.randomKey()
        repeat { b.releasedKey = Self.randomKey() } while b.releasedKey == b.key
        return b
    }

    private static func randomKey() -> String {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
    }

    /// Short, non-reversible tag so logs can show *which* key was used without leaking it.
    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

/// `vela-backup.json` as written by tools/web/free-my-vela.html.
struct VelaBackup: Codable {
    var bikes: [BikeKeys]

    /// Writes a backup the app (and free-my-vela.html's format) can import again; returns the file.
    static func file(for bikes: [BikeKeys]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vela-backup.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(VelaBackup(bikes: bikes)).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func decode(_ data: Data) throws -> [BikeKeys] {
        let bikes = try JSONDecoder().decode(VelaBackup.self, from: data).bikes
        return bikes.filter { $0.keyBytes != nil && $0.releasedKeyBytes != nil }
    }
}
