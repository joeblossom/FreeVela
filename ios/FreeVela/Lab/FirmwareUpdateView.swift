import SwiftUI

/// Install a firmware image on the bike. Only images listed in FirmwareImage.known can be
/// imported, and success is only reported once the bike restarts and reports the new version.
struct FirmwareUpdateView: View {
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var updater: FirmwareUpdater
    @State private var images: [CheckedImage] = []
    @State private var selectedID: String?
    @State private var importing = false
    @State private var importError: String?
    @State private var confirming = false
    @State private var downloading: String?

    private var selected: CheckedImage? { images.first { $0.id == selectedID } }

    var body: some View {
        Form {
            bikeSection
            imageSection
            installSection
        }
        .navigationTitle("Firmware update")
        .navigationBarBackButtonHidden(updater.running)
        .onAppear(perform: reload)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            importFile(result)
        }
    }

    private var bikeSection: some View {
        Section("Bike") {
            LabeledContent("Firmware", value: link.firmware?.label ?? (link.isUnlocked ? "—" : "Not connected"))
            LabeledContent("Battery", value: link.values["pwr.fuel"].map { "\($0)%" } ?? "—")
            LabeledContent("Charging", value: link.values["pwr.chr"].map { $0 == "1" || $0 == "true" ? "Yes" : "No" } ?? "—")
        }
    }

    private var imageSection: some View {
        Section {
            ForEach(images) { c in
                Button { selectedID = c.id } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.image.name)
                            Text("\(c.data.count.formatted()) bytes · \(c.image.sha256.prefix(12))…")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.id == selectedID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .tint(.primary)
            }
            ForEach(FirmwareImage.known.filter { im in im.url != nil && !images.contains { $0.id == im.id } }) { im in
                HStack {
                    VStack(alignment: .leading) {
                        Text(im.name)
                        Text("\(im.size.formatted()) bytes · not downloaded").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if downloading == im.id {
                        ProgressView()
                    } else {
                        Button("Download") { Task { await download(im) } }
                            .buttonStyle(.borderless)
                            .disabled(downloading != nil)
                    }
                }
            }
            Button("Import image file…") { importing = true }
            if let importError {
                Text(importError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Image")
        } footer: {
            Text("FreeVela firmware downloads from the project's GitHub releases. Imported or downloaded, only images FreeVela recognizes (exact size and SHA-256) are accepted. They stay on this phone so an earlier version can be sent again. Known: " + FirmwareImage.known.map(\.name).joined(separator: ", ") + ".")
        }
    }

    private var installSection: some View {
        let blockers = updater.problems(link)
        return Section {
            if !updater.running {
                ForEach(blockers, id: \.self) { Text($0).foregroundStyle(.red) }
                Button(selected.map { "Install \($0.image.label)" } ?? "Choose an image") { confirming = true }
                    .fontWeight(.semibold)
                    .disabled(selected == nil || !blockers.isEmpty)
                    .confirmationDialog("Install \(selected?.image.label ?? "")?", isPresented: $confirming, titleVisibility: .visible) {
                        Button("Install") {
                            guard let c = selected else { return }
                            Task { await updater.install(c, link: link) }
                        }
                    } message: {
                        if let c = selected { Text(updater.warnings(link, c).joined(separator: "\n\n")) }
                    }
            }
            switch updater.stage {
            case .idle:
                EmptyView()
            case .working(let text):
                HStack { ProgressView(); Text(text) }
            case .sending(let fraction):
                ProgressView(value: fraction) { Text("Sending… \(Int(fraction * 100))%") }
                Button("Cancel", role: .destructive) { updater.cancel() }
            case .succeeded(let text):
                Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let text):
                Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        } header: {
            Text("Install")
        } footer: {
            Text("FreeVela sends the image, asks the bike to install it, then waits for it to restart, unlocks it again and checks the version it reports. The bike checks the image itself and keeps its old firmware if the image is bad. Needs at least \(FirmwareUpdater.minBattery)% battery and the bike standing still.")
        }
    }

    private func reload() {
        images = FirmwareStore.all()
        if selectedID == nil || selected == nil { selectedID = images.first?.id }
    }

    private func download(_ image: FirmwareImage) async {
        importError = nil
        downloading = image.id
        defer { downloading = nil }
        do {
            let c = try await image.download()
            try FirmwareStore.save(c)
            reload()
            selectedID = c.id
        } catch {
            importError = "Couldn't download \(image.name): \(error.localizedDescription)"
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        importError = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let c = try CheckedImage(data: Data(contentsOf: url))
            try FirmwareStore.save(c)
            reload()
            selectedID = c.id
        } catch {
            importError = error.localizedDescription
        }
    }
}
