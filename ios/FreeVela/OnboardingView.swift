import SwiftUI

/// First run: signed out (set up the bike, or add keys), then wake and connect it.
struct OnboardingView: View {
    var onFinish: () -> Void
    @EnvironmentObject private var keys: KeyStore
    @State private var settingUp = Self.demoSetup

    #if DEBUG
    private static let demoSetup = ProcessInfo.processInfo.arguments.contains("-demoSetup")
    #else
    private static let demoSetup = false
    #endif

    var body: some View {
        Group {
            if settingUp {
                SetupView(onCancel: { settingUp = false }, onFinish: onFinish)
            } else if keys.bikes.isEmpty {
                SignedOutView { settingUp = true }
            } else {
                WakeView(onFinish: onFinish)
            }
        }
        .paintedScreen()
    }
}

/// "Wake your bike", with the connect steps ticking off as they happen.
private struct WakeView: View {
    var onFinish: () -> Void
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @Environment(\.theme) private var theme

    /// 0 looking, 1 connecting, 2 unlocking, 3 done.
    private var step: Int {
        if link.isUnlocked { return 3 }
        if let busy = session.busy, busy.hasPrefix("Unlock") || busy.hasPrefix("Retrying") { return 2 }
        if session.busy == "Connecting…" || link.phase == .connecting { return 1 }
        return 0
    }

    private var working: Bool { session.busy != nil }

    var body: some View {
        PaintedLayout {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "bicycle").font(.system(size: 54, weight: .regular))
                    Image(systemName: "hand.raised.fill").font(.system(size: 30, weight: .semibold))
                }
                Text("Wake your bike").display(44)
                Text("Stand next to it and hold the brake lever and the handlebar button together. Neither one alone wakes it.")
                    .font(.archivo(17, weight: 400))
                    .opacity(0.9)
            }
        } panel: {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(["Looking for your bike", "Connecting", "Unlocking"].enumerated()), id: \.offset) { i, label in
                    stepRow(i, label)
                }
                if link.bluetooth != .poweredOn {
                    Text("Bluetooth is \(link.bluetooth.label).").font(.archivo(14, weight: 500)).foregroundStyle(.red)
                }
                button.padding(.top, 6)
            }
        }
        .onAppear { session.autoConnect() }
    }

    private func stepRow(_ i: Int, _ label: String) -> some View {
        let done = i < step, now = i == step && working
        return HStack(spacing: 12) {
            Group {
                if now {
                    ProgressView().tint(theme.ink)
                } else {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? theme.actionColor : theme.tile)
                }
            }
            .font(.system(size: 24, weight: .semibold))
            .frame(width: 28)
            Text(now ? label + "…" : label)
                .display(20, tracking: 0.03)
                .foregroundStyle(done || now ? theme.ink : theme.inkMuted)
        }
    }

    @ViewBuilder private var button: some View {
        if step == 3 {
            InkBarButton(title: "Done", symbol: "arrow.right", action: onFinish)
        } else if working {
            Text("Waiting for your bike…")
                .display(20, tracking: 0.04)
                .foregroundStyle(theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(theme.tile, in: RoundedRectangle(cornerRadius: 16))
        } else {
            InkBarButton(title: "Try again", symbol: "arrow.clockwise") { Task { await session.connect() } }
        }
    }
}

/// A painted band (frame color) over a cream tyre panel that sits at the bottom of the screen.
struct PaintedLayout<Band: View, Panel: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var band: Band
    @ViewBuilder var panel: Panel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                band
                    .foregroundStyle(theme.paint.on)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 36 + 28)
                    .background(theme.paint.frame)
                panel
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .background(TyreBackground())
                    .padding(.top, -36)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { VStack(spacing: 0) { theme.paint.frame; theme.cream }.ignoresSafeArea() }
    }
}

extension View {
    /// A full screen with a painted top: an empty navigation bar sets the status bar for the paint.
    func paintedScreen() -> some View { modifier(PaintedScreen()) }
}

private struct PaintedScreen: ViewModifier {
    func body(content: Content) -> some View { content.paintStatusBar() }
}
