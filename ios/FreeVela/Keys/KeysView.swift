import SwiftUI
import UniformTypeIdentifiers

/// Import bike keys from a vela-backup.json or by pasting them.
struct KeysView: View {
    @EnvironmentObject private var keys: KeyStore
    @Binding var selectedID: String?
    @State private var importing = false
    @State private var pasting = false
    @State private var error: String?

    var body: some View {
        Section {
            if keys.bikes.isEmpty {
                Text("No bike keys yet. Import the vela-backup.json from free-my-vela.html (AirDrop it to this phone), or paste the values.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Picker("Bike", selection: $selectedID) {
                    ForEach(keys.bikes) { Text($0.title).tag(Optional($0.id)) }
                }
                if let bike = keys.bikes.first(where: { $0.id == selectedID }) {
                    LabeledContent("Device ID", value: bike.id)
                    LabeledContent("key", value: bike.keyBytes.map { "\($0.count)B · fp \(BikeKeys.fingerprint($0))" } ?? "invalid")
                    LabeledContent("releasedKey", value: bike.releasedKeyBytes.map { "\($0.count)B · fp \(BikeKeys.fingerprint($0))" } ?? "invalid")
                    Button("Remove this bike", role: .destructive) { keys.remove(bike); selectedID = keys.bikes.first?.id }
                }
            }
            HStack {
                Button("Import backup…") { importing = true }
                Spacer()
                Button("Paste keys…") { pasting = true }
            }
            .buttonStyle(.borderless)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Keys")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let bikes = try VelaBackup.decode(Data(contentsOf: url))
                guard !bikes.isEmpty else { error = "No bikes with valid keys in that file."; return }
                keys.add(bikes)
                selectedID = bikes[0].id
                error = nil
            } catch {
                self.error = "Couldn't read backup: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $pasting) {
            PasteKeysSheet { bike in
                keys.add([bike])
                selectedID = bike.id
            }
        }
    }
}

private struct PasteKeysSheet: View {
    var onSave: (BikeKeys) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    @State private var key = ""
    @State private var released = ""

    private var bike: BikeKeys {
        BikeKeys(id: id.trimmingCharacters(in: .whitespaces), key: key, releasedKey: released)
    }
    private var valid: Bool {
        !bike.id.isEmpty && bike.keyBytes?.count == 32 && bike.releasedKeyBytes?.count == 32
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Device ID (e.g. b2349…)", text: $id)
                TextField("key (base64)", text: $key)
                TextField("releasedKey (base64)", text: $released)
                if !key.isEmpty && bike.keyBytes?.count != 32 { Text("key must be base64 of 32 bytes").foregroundStyle(.red) }
                if !released.isEmpty && bike.releasedKeyBytes?.count != 32 { Text("releasedKey must be base64 of 32 bytes").foregroundStyle(.red) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .navigationTitle("Paste keys")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(bike); dismiss() }.disabled(!valid)
                }
            }
        }
    }
}
