import SwiftUI

/// Settings → Bikes & keys → Add a bike: set one up (recommended) or add keys you already have.
/// The setup cover, file importer and paste sheet are presented by Settings (see BikesSection).
struct AddBikeView: View {
    var onSetUp: () -> Void
    var onImport: () -> Void
    var onPaste: () -> Void
    @EnvironmentObject private var keys: KeyStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false
    @State private var startCount = 0

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recommended")
                        .font(.archivo(11, weight: 700))
                        .tracking(1.32)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.paint.on)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.paint.frame, in: Capsule())
                    Text("Set up a new bike").display(28).foregroundStyle(theme.ink)
                    Text("No keys needed. It installs FreeVela firmware, resets the bike's keys and pairs this phone, in about 10–15 minutes.")
                        .font(.archivo(15, weight: 400))
                        .foregroundStyle(theme.inkMuted)
                    InkBarButton(title: "Set up a new bike", symbol: "arrow.right", action: onSetUp)
                }
                .padding(.vertical, 8)
            }
            .paintRows()

            PaintSection {
                Button(action: onImport) { SettingsRow("Import backup…", "square.and.arrow.down") }
                Button(action: onPaste) { SettingsRow("Paste keys…", "doc.on.clipboard") }
                Button { showGuide = true } label: { SettingsRow("Get keys from my Vela account", "laptopcomputer") }
            } header: {
                Text("Already have its keys?")
            } footer: {
                Text("Keys keep the bike's original firmware. Get them from your Vela account on a computer, while Vela's sign-in still answers.")
            }
        }
        .paintList()
        .paintNavBar("Add a bike")
        .sheet(isPresented: $showGuide) {
            VelaAccountSheet(onImport: { showGuide = false; onImport() },
                             onSetUp: { showGuide = false; onSetUp() })
                .themed()
        }
        .onAppear { startCount = keys.bikes.count }
        // Imported or pasted: back to Settings.
        .onChange(of: keys.bikes.count) { if keys.bikes.count > startCount { dismiss() } }
    }
}
