import SwiftUI

/// No bikes on this phone: set the bike up here (recommended), import keys, or fetch them from a
/// Vela account on a computer.
struct SignedOutView: View {
    var onSetUp: () -> Void
    @EnvironmentObject private var session: Session
    @Environment(\.theme) private var theme
    @State private var askKeys = false
    @State private var importing = false
    @State private var pasting = false
    @State private var showGuide = false
    @State private var error: String?

    var body: some View {
        PaintedLayout {
            HStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.paint.on, lineWidth: 2))
                Text("Keep your Vela riding").display(34)
            }
        } panel: {
            VStack(alignment: .leading, spacing: 16) {
                recommended
                SectionHeader("Other ways")
                VStack(spacing: 0) {
                    otherRow("key.fill", "I already have my keys", "Import vela-backup.json, or paste them.") { askKeys = true }
                    Rectangle().fill(theme.tile).frame(height: 1).padding(.leading, 60)
                    otherRow("laptopcomputer", "Get my keys from my Vela account",
                             "Needs a computer and some tech know-how. Keeps the bike's original firmware.") { showGuide = true }
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
                Button { session.startDemo() } label: {
                    HStack(spacing: 6) {
                        Text("No bike with you?").font(.archivo(15, weight: 400))
                        Text("Try without a bike").font(.archivo(15, weight: 700)).underline()
                    }
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                if let error { Text(error).font(.archivo(14, weight: 500)).foregroundStyle(.red) }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 15))
                    Text("Keys are end-to-end encrypted in your iCloud Keychain (you can turn that off). Close the old Vela app — the bike talks to one phone at a time.")
                        .font(.archivo(13, weight: 400))
                }
                .foregroundStyle(theme.inkMuted)
            }
        }
        .confirmationDialog("Add your bike's keys", isPresented: $askKeys, titleVisibility: .visible) {
            Button("Import backup…") { importing = true }
            Button("Paste keys…") { pasting = true }
        }
        .sheet(isPresented: $showGuide) {
            VelaAccountSheet(onImport: { showGuide = false; importing = true },
                             onSetUp: { showGuide = false; onSetUp() })
                .themed()
        }
        .keyImport(importing: $importing, pasting: $pasting, error: $error)
    }

    private var recommended: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended")
                .font(.archivo(11, weight: 700))
                .tracking(1.32)
                .textCase(.uppercase)
                .foregroundStyle(theme.paint.on)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.paint.frame, in: Capsule())
            Text("Set up my bike").display(28).foregroundStyle(theme.ink)
            Text("No computer needed. It all happens on this phone, in about 10–15 minutes. Works whether or not you have your old keys.")
                .font(.archivo(15, weight: 400))
                .foregroundStyle(theme.inkMuted)
            InkBarButton(title: "Set up my bike", symbol: "arrow.right", action: onSetUp)
        }
        .padding(.top, 18)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func otherRow(_ symbol: String, _ title: String, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SettingsIcon(symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.archivo(16, weight: 600)).foregroundStyle(theme.ink)
                    Text(text).font(.archivo(13, weight: 400)).foregroundStyle(theme.inkMuted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.inkMuted)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// How to fetch keys from a Vela account (a computer and the GitHub guide), with a way back to setup.
struct VelaAccountSheet: View {
    var onImport: () -> Void
    var onSetUp: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private static let guide = URL(string: "https://github.com/joeblossom/FreeVela#1-rescue-your-keys--do-this-now")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.display(16)).foregroundStyle(theme.ink)
                }
                Text("Get your keys from your Vela account").display(32).foregroundStyle(theme.ink)
                Label("Works while Vela's sign-in still answers", systemImage: "clock")
                    .font(.archivo(13, weight: 600))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.tile, in: Capsule())
                HStack(alignment: .top, spacing: 14) {
                    SettingsIcon("terminal")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You'll need a computer and some tech know-how").display(18).foregroundStyle(theme.ink)
                        Text("You'll download the project from GitHub and run one command in Terminal. If that's not for you, ask a friend who's comfortable with it.")
                            .font(.archivo(14, weight: 400)).foregroundStyle(theme.inkMuted)
                    }
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                Link(destination: Self.guide) {
                    HStack(spacing: 12) {
                        Image(systemName: "link").font(.system(size: 18, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open the guide on GitHub").display(16, tracking: 0.04)
                            Text("github.com/joeblossom/FreeVela").font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square").font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.ink, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 14) {
                    numbered(1, "On a computer, open the guide on GitHub", "Follow \u{201C}Rescue your keys\u{201D} to start the Free My Vela page.")
                    numbered(2, "Sign in the way you did in the Vela app", "Apple, Google or email.")
                    numbered(3, "Click Download backup", "You get a file called vela-backup.json.")
                    numbered(4, "AirDrop it here, then tap Import backup", "FreeVela finds your bike and connects.")
                }
                InkBarButton(title: "Import backup…", symbol: "arrow.right", action: onImport)
                Button(action: onSetUp) {
                    (Text("Easier: ").font(.archivo(15, weight: 400)) + Text("set up on this phone instead").font(.archivo(15, weight: 700)))
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .background(theme.cream.ignoresSafeArea())
    }

    private func numbered(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.display(17))
                .foregroundStyle(theme.onInk)
                .frame(width: 30, height: 30)
                .background(theme.ink, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.archivo(16, weight: 600)).foregroundStyle(theme.ink)
                Text(text).font(.archivo(14, weight: 400)).foregroundStyle(theme.inkMuted)
            }
        }
    }
}
