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

    /// Short, non-reversible tag so logs can show *which* key was used without leaking it.
    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

/// `vela-backup.json` as written by tools/web/free-my-vela.html.
struct VelaBackup: Decodable {
    var bikes: [BikeKeys]

    static func decode(_ data: Data) throws -> [BikeKeys] {
        let bikes = try JSONDecoder().decode(VelaBackup.self, from: data).bikes
        return bikes.filter { $0.keyBytes != nil && $0.releasedKeyBytes != nil }
    }
}
