import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The bikes on this phone: pick one, swipe to remove, or add keys from a backup or by pasting.
struct BikesSection: View {
    @EnvironmentObject private var keys: KeyStore
    @EnvironmentObject private var session: Session
    @Environment(\.theme) private var theme
    @State private var importing = false
    @State private var pasting = false
    @State private var settingUp = false
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(keys.bikes) { bike in
                Button { session.selectedID = bike.id } label: {
                    HStack(spacing: 12) {
                        SettingsIcon("bicycle")
                        VStack(alignment: .leading, spacing: 0) {
                            Text(bike.name).font(.archivo(16, weight: 500)).foregroundStyle(theme.ink)
                            Text("\(bike.id.prefix(8)) · \(bike.keyBytes != nil && bike.releasedKeyBytes != nil ? "keys OK" : "keys invalid")")
                                .font(.footnote.monospaced()).foregroundStyle(theme.inkMuted)
                        }
                        Spacer()
                        if bike.id == session.selectedID {
                            Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.actionColor)
                        }
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { keys.remove(bike); session.bikesChanged() }
                }
            }
            Button { BackupShare.present(keys) } label: {
                SettingsRow("Save key backup", "square.and.arrow.up",
                            detail: keys.bikes.contains { keys.needsBackup.contains($0.id) } ? "Not saved yet" : nil)
            }
            Button { importing = true } label: { SettingsRow("Import backup…", "square.and.arrow.down") }
            Button { pasting = true } label: { SettingsRow("Paste keys…", "doc.on.clipboard") }
            Button { settingUp = true } label: { SettingsRow("Set up a new bike…", "person.badge.plus") }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            SectionHeader("Bikes & keys")
        } footer: {
            Text(keys.syncsWithICloud
                 ? "Keys sync through iCloud Keychain to your other Apple devices. Swipe a bike to remove it."
                 : "Keys stay on this phone. Save a backup somewhere safe: without one, a lost phone means a locked bike. Swipe a bike to remove it.")
                .font(.archivo(13, weight: 400)).foregroundStyle(theme.inkMuted)
        }
        .paintRows()
        .keyImport(importing: $importing, pasting: $pasting, error: $error)
        .fullScreenCover(isPresented: $settingUp) {
            SetupView(onCancel: { settingUp = false; session.bikesChanged(); session.autoConnect() },
                      onFinish: { settingUp = false })
                .paintedScreen()
                .themed()
        }
    }
}

extension View {
    /// The backup-file importer and paste sheet. New keys are saved and the first new bike is selected.
    func keyImport(importing: Binding<Bool>, pasting: Binding<Bool>, error: Binding<String?>) -> some View {
        modifier(KeyImport(importing: importing, pasting: pasting, error: error))
    }
}

private struct KeyImport: ViewModifier {
    @EnvironmentObject private var keys: KeyStore
    @EnvironmentObject private var session: Session
    @Binding var importing: Bool
    @Binding var pasting: Bool
    @Binding var error: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let bikes = try VelaBackup.decode(Data(contentsOf: url))
                    guard !bikes.isEmpty else { error = "No bikes with valid keys in that file."; return }
                    keys.add(bikes)
                    session.selectedID = bikes[0].id
                    error = nil
                } catch {
                    self.error = "Couldn't read backup: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $pasting) {
                PasteKeysSheet { bike in
                    keys.add([bike])
                    session.selectedID = bike.id
                    error = nil
                }
                .themed()
            }
    }
}

private struct PasteKeysSheet: View {
    var onSave: (BikeKeys) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
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
                Section {
                    TextField("Device ID (e.g. b2349…)", text: $id)
                    TextField("key (base64)", text: $key)
                    TextField("releasedKey (base64)", text: $released)
                }
                .paintRows()
                if !key.isEmpty && bike.keyBytes?.count != 32 { Text("key must be base64 of 32 bytes").foregroundStyle(.red) }
                if !released.isEmpty && bike.releasedKeyBytes?.count != 32 { Text("releasedKey must be base64 of 32 bytes").foregroundStyle(.red) }
            }
            .paintList()
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .paintNavBar("Paste keys")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(bike); dismiss() }.disabled(!valid)
                }
            }
        }
    }
}

/// Name and photo of the selected bike. Tap the name to rename, the photo to change it.
struct BikeCard: View {
    @EnvironmentObject private var keys: KeyStore
    @Environment(\.theme) private var theme
    let bike: BikeKeys
    @State private var name = ""
    @State private var picked: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var renaming = false
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $picked, matching: .images) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Image(systemName: "bicycle").font(.system(size: 26, weight: .semibold)).foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(theme.surface)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.ink, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bike photo")
            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    TextField("My Bike", text: $name)
                        .font(.display(26))
                        .foregroundStyle(theme.ink)
                        .focused($editing)
                        .submitLabel(.done)
                        .onSubmit { finishRename() }
                        .onAppear { editing = true }
                } else {
                    Button { renaming = true } label: {
                        Text(bike.name).display(26).foregroundStyle(theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Renames the bike")
                }
                Text("Vela V2 · tap the name to rename").font(.archivo(13, weight: 400)).foregroundStyle(theme.inkMuted)
            }
        }
        .padding(.vertical, 4)
        .onAppear { name = bike.displayName ?? ""; photo = BikePhoto.load(bike.id) }
        .onChange(of: bike.id) { name = bike.displayName ?? ""; photo = BikePhoto.load(bike.id) }
        .onChange(of: editing) { if !editing { finishRename() } }
        .onChange(of: picked) {
            Task {
                guard let data = try? await picked?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                photo = BikePhoto.save(image, for: bike.id)
            }
        }
    }

    private func finishRename() {
        keys.rename(bike.id, to: name)
        renaming = false
    }
}

/// Bike photos, one small JPEG per bike in Application Support.
enum BikePhoto {
    private static func url(_ id: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "bike-photos/\(id).jpg")
    }

    static func load(_ id: String) -> UIImage? { UIImage(contentsOfFile: url(id).path) }

    /// Scales the image down to 512 pt and saves it; returns what was saved.
    static func save(_ image: UIImage, for id: String) -> UIImage {
        let side: CGFloat = 512, scale = min(1, side / min(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        let file = url(id)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? small.jpegData(compressionQuality: 0.8)?.write(to: file)
        return small
    }

    static func remove(_ id: String) { try? FileManager.default.removeItem(at: url(id)) }
}
