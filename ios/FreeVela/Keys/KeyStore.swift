import Foundation
import Security

/// Bike credentials, persisted as one JSON blob in the Keychain. By default it stays on this phone
/// (it usually survives deleting and reinstalling the app). With iCloud sync on, the item is
/// synchronizable, so it's end-to-end encrypted in iCloud Keychain and appears on the person's other devices.
final class KeyStore: ObservableObject {
    @Published private(set) var bikes: [BikeKeys] = []
    /// Bikes whose keys were made on this phone (setup or Reset keys) and haven't been backed up yet.
    @Published private(set) var needsBackup: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "needsBackup") ?? [])

    private let account = "bikes"
    private let service = "FreeVela"

    /// Whether the keys sync through iCloud Keychain.
    @Published private(set) var syncsWithICloud = false

    init() {
        (bikes, syncsWithICloud) = load()
        // On by default: new installs, and once for keys saved before this setting existed.
        if !UserDefaults.standard.bool(forKey: "keySyncChosen") {
            UserDefaults.standard.set(true, forKey: "keySyncChosen")
            syncsWithICloud = true
            if !bikes.isEmpty { save(bikes) }
        }
    }

    /// Turning it off removes the synced copy (from iCloud and the other devices); this phone keeps the keys.
    func setICloudSync(_ on: Bool) {
        UserDefaults.standard.set(true, forKey: "keySyncChosen")
        syncsWithICloud = on
        save(bikes)
    }

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
        setNeedsBackup(needsBackup.subtracting([bike.id]))
    }

    /// Replaces a temporary id with the bike's real one (keeping its name, photo and backup status).
    /// If keys for that id are already saved, the temporary entry is dropped.
    func replaceID(_ old: String, with new: String) {
        guard old != new, let i = bikes.firstIndex(where: { $0.id == old }) else { return }
        var list = bikes
        if list.contains(where: { $0.id == new }) {
            list.remove(at: i)
        } else {
            list[i].id = new
            BikePhoto.move(old, to: new)
        }
        if needsBackup.contains(old) { setNeedsBackup(needsBackup.subtracting([old]).union([new])) }
        save(list)
    }

    func markNeedsBackup(_ id: String) { setNeedsBackup(needsBackup.union([id])) }
    func markBackedUp(_ ids: [String]) { setNeedsBackup(needsBackup.subtracting(ids)) }

    private func setNeedsBackup(_ ids: Set<String>) {
        needsBackup = ids
        UserDefaults.standard.set(Array(ids), forKey: "needsBackup")
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save(bikes.map { var b = $0; if b.id == id { b.displayName = trimmed.isEmpty ? nil : trimmed }; return b })
    }

    /// Matches the item whether or not it syncs.
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
    }

    private func load() -> ([BikeKeys], Bool) {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let item = out as? [String: Any],
              let data = item[kSecValueData as String] as? Data else { return ([], false) }
        let synced = (item[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false
        return ((try? JSONDecoder().decode([BikeKeys].self, from: data)) ?? [], synced)
    }

    private func save(_ list: [BikeKeys]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrSynchronizable as String] = syncsWithICloud
        // A synced item can't be "this device only".
        q[kSecAttrAccessible as String] = syncsWithICloud ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
        bikes = list
    }
}
