import Foundation
import Security

/// Bike credentials, persisted as one JSON blob in the Keychain
/// (this device only, never synced).
final class KeyStore: ObservableObject {
    @Published private(set) var bikes: [BikeKeys] = []

    private let account = "bikes"
    private let service = "FreeVela"

    init() { bikes = load() }

    func add(_ new: [BikeKeys]) {
        var merged = bikes
        for bike in new {
            if let i = merged.firstIndex(where: { $0.id == bike.id }) { merged[i] = bike } else { merged.append(bike) }
        }
        save(merged)
    }

    func remove(_ bike: BikeKeys) {
        save(bikes.filter { $0.id != bike.id })
        BikePhoto.remove(bike.id)
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save(bikes.map { var b = $0; if b.id == id { b.displayName = trimmed.isEmpty ? nil : trimmed }; return b })
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func load() -> [BikeKeys] {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return [] }
        return (try? JSONDecoder().decode([BikeKeys].self, from: data)) ?? []
    }

    private func save(_ list: [BikeKeys]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
        bikes = list
    }
}
