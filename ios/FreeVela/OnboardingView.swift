import SwiftUI

/// First run: add your bike's keys, then wake and connect it.
struct OnboardingView: View {
    var onFinish: () -> Void
    @EnvironmentObject private var keys: KeyStore
    @State private var importing = false
    @State private var pasting = false
    @State private var error: String?

    var body: some View {
        if keys.bikes.isEmpty {
            welcome
        } else {
            WakeView(onFinish: onFinish)
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Keep your Vela riding")
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 24)
            Text("FreeVela talks to your bike directly over Bluetooth. No Vela app or servers needed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 22) {
                point("key.fill", "Your bike's keys", "Download vela-backup.json from free-my-vela.html on a computer, then AirDrop it here.")
                point("lock.fill", "Stays on this phone", "Keys are never sent anywhere or written to the log.")
                point("iphone", "Close the old Vela app", "The bike only talks to one phone at a time.")
            }
            .padding(.top, 40)
            Spacer(minLength: 24)
            if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.bottom, 8) }
            Button { importing = true } label: {
                Text("Import backup…").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            Button("Paste keys instead") { pasting = true }
                .frame(minHeight: 44)
                .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 12)
        .keyImport(importing: $importing, pasting: $pasting, error: $error)
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// "Wake your bike", with the connect steps ticking off as they happen.
private struct WakeView: View {
    var onFinish: () -> Void
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink

    /// 0 looking, 1 connecting, 2 unlocking, 3 done.
    private var step: Int {
        if link.isUnlocked { return 3 }
        if let busy = session.busy, busy.hasPrefix("Unlock") || busy.hasPrefix("Retrying") { return 2 }
        if session.busy == "Connecting…" || link.phase == .connecting { return 1 }
        return 0
    }

    private var working: Bool { session.busy != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            illustration
            Text("Wake your bike").font(.system(size: 28, weight: .bold)).padding(.top, 28)
            (Text("Stand next to it and hold the ") + Text("brake lever").bold().foregroundColor(.primary)
             + Text(" and the ") + Text("handlebar button").bold().foregroundColor(.primary)
             + Text(" together. Neither one alone wakes it."))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(["Looking for your bike", "Connecting", "Unlocking"].enumerated()), id: \.offset) { i, label in
                    stepRow(i, label)
                }
            }
            .padding(.top, 28)
            if link.bluetooth != .poweredOn {
                Text("Bluetooth is \(link.bluetooth.label).").font(.footnote).foregroundStyle(.red).padding(.top, 14)
            }
            Spacer(minLength: 24)
            button
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { session.autoConnect() }
    }

    private var illustration: some View {
        VStack(spacing: 12) {
            Image(systemName: "bicycle").font(.system(size: 72, weight: .light))
            Label("Brake lever + handlebar button", systemImage: "hand.raised.fill").font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func stepRow(_ i: Int, _ label: String) -> some View {
        let done = i < step, now = i == step && working
        return HStack(spacing: 12) {
            Group {
                if now {
                    ProgressView()
                } else {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                }
            }
            .font(.title3)
            .frame(width: 24)
            Text(now ? label + "…" : label).foregroundStyle(done || now ? .primary : .secondary)
        }
    }

    @ViewBuilder private var button: some View {
        if step == 3 {
            wide("Done", action: onFinish).buttonStyle(.borderedProminent)
        } else if working {
            wide("Waiting for your bike…") {}.buttonStyle(.bordered).disabled(true)
        } else {
            wide("Try again") { Task { await session.connect() } }.buttonStyle(.borderedProminent)
        }
    }

    private func wide(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .buttonBorderShape(.roundedRectangle(radius: 14))
    }
}
