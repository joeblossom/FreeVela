import SwiftUI
import UniformTypeIdentifiers

/// One bike's keys: visible and copyable, with the backup, iCloud sync, reset and remove.
struct BikeDetailView: View {
    let bikeID: String
    @EnvironmentObject private var keys: KeyStore
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var copied: String?
    @State private var confirmingReset = false
    @State private var confirmingRemove = false
    @State private var resetResult: String?

    private var bike: BikeKeys? { keys.bikes.first { $0.id == bikeID } }
    private var selected: Bool { session.selectedID == bikeID }

    var body: some View {
        Form {
            if let bike {
                PaintSection {
                    keyRow("Device ID", bike.id)
                    keyRow("Key", bike.key)
                    keyRow("Released key", bike.releasedKey)
                } header: {
                    Text("Keys")
                } footer: {
                    Text("Anyone with these can unlock the bike and turn off its alarm. Copies stay on this phone and clear from the clipboard after 2 minutes.")
                }

                PaintSection {
                    Button { BackupShare.present(keys) } label: {
                        SettingsRow("Save key backup", "square.and.arrow.up",
                                    detail: keys.needsBackup.contains(bikeID) ? "Not saved yet" : nil)
                    }
                    Toggle(isOn: Binding(get: { keys.syncsWithICloud }, set: { keys.setICloudSync($0) })) {
                        SettingsRow("Sync with iCloud Keychain", "icloud.fill", plain: true)
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text(keys.syncsWithICloud
                         ? "Your keys are end-to-end encrypted in iCloud Keychain, so they come back on a new phone or after reinstalling. Turning this off removes them from iCloud and your other devices; this phone keeps them. Applies to all your bikes."
                         : "Off: keys stay on this phone only. They usually survive reinstalling the app, but not a new phone, so keep a backup somewhere safe. Applies to all your bikes.")
                }

                PaintSection {
                    if !selected {
                        Button { session.selectedID = bikeID; session.autoConnect() } label: {
                            SettingsRow("Use this bike", "bicycle")
                        }
                    }
                    if selected, link.isUnlocked {
                        Button { confirmingReset = true } label: { SettingsRow("Reset keys…", "key.fill", destructive: true) }
                            .disabled(session.busy != nil)
                    }
                    Button { confirmingRemove = true } label: { SettingsRow("Remove this bike", "trash.fill", destructive: true) }
                } footer: {
                    Text(selected && link.isUnlocked
                         ? "Reset keys makes new ones; old backups and other phones stop working. Removing the bike deletes its keys from this phone" + (keys.syncsWithICloud ? " and iCloud." : ".")
                         : "Reset keys needs the bike connected. Removing the bike deletes its keys from this phone" + (keys.syncsWithICloud ? " and iCloud." : "."))
                }
            }
        }
        .paintList()
        .paintNavBar(bike?.name ?? "Bike")
        .confirmationDialog("Reset keys?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset keys", role: .destructive) {
                Task {
                    resetResult = await session.resetKeys()
                        ? "The bike has new keys, saved on this phone. Your old backup and any other phone with the old keys no longer work. Save a new key backup now."
                        : "The keys weren't changed. Stay next to the bike and try again, or share the log."
                }
            }
        } message: {
            Text("Makes new keys for this bike and pairs this phone with them. Old backups and other phones stop working.")
        }
        .confirmationDialog("Remove this bike?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let bike {
                    keys.remove(bike)
                    session.bikesChanged()
                }
                dismiss()
            }
        } message: {
            Text("Its keys are deleted from this phone. Without a backup, you'd need to set the bike up again.")
        }
        .alert("Reset keys", isPresented: Binding(get: { resetResult != nil }, set: { if !$0 { resetResult = nil } })) {
            Button("OK") { resetResult = nil }
        } message: {
            Text(resetResult ?? "")
        }
    }

    private func keyRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).display(14, weight: 700, tracking: 0.08).foregroundStyle(theme.inkMuted)
                Spacer()
                Button { copy(value, label) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied == label ? "checkmark" : "doc.on.doc").font(.system(size: 13, weight: .semibold))
                        Text(copied == label ? "Copied" : "Copy").font(.archivo(14, weight: 600))
                    }
                    .foregroundStyle(theme.ink)
                }
                .buttonStyle(.borderless)
            }
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    /// Copies for this phone only (no Universal Clipboard), expiring after 2 minutes.
    private func copy(_ value: String, _ label: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: value]],
                                      options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
        copied = label
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == label { copied = nil }
        }
    }
}
