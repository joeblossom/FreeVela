import SwiftUI

/// Speed first, painted in the bike's frame color: a huge number over a cream "tyre" panel with
/// assist, quick actions and Start ride. Keys, units and developer tools live in Settings.
struct HomeView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @Environment(\.theme) private var theme
    @AppStorage("units") private var units: Units = .kmh
    @State private var showSettings = false
    @State private var riding = false
    @State private var confirmSiren = false
    /// Heights of the parts above and below the flexible gap, so the speed sits on the panel.
    @State private var topHeight: CGFloat = 0
    @State private var speedHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0
    /// The short "Connected" moment between the connecting screen and the dashboard.
    @State private var showingSuccess = false

    private var ok: Bool { link.isUnlocked }
    private var connected: Bool { session.status == .connected }
    private var showsConnect: Bool { !connected || showingSuccess || Self.demoSuccess }

    #if DEBUG
    private static let demoSuccess: Bool = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoConnect"), i + 1 < args.count else { return false }
        return args[i + 1] == "success"
    }()
    #else
    private static let demoSuccess = false
    #endif

    var body: some View {
        Group {
            if showsConnect {
                ConnectView(phase: showingSuccess || Self.demoSuccess ? .success : ConnectView.Phase(session.status)) {
                    showSettings = true
                }
                .transition(.opacity)
            } else {
                dashboard
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.5), value: showsConnect)
        .onChange(of: connected) { was, now in
            // Not when the app opens already connected: only after connecting here.
            guard now, !was else { return }
            showingSuccess = true
            Task {
                try? await Task.sleep(for: .seconds(0.9))
                showingSuccess = false
            }
        }
        .background {
            VStack(spacing: 0) { theme.paint.frame; showsConnect ? theme.paint.frame : theme.cream }.ignoresSafeArea()
        }
        .paintStatusBar()
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoSettings") { showSettings = true }
            if args.contains("-demoRide") { riding = true }
        }
        #endif
        .sheet(isPresented: $showSettings) { SettingsView().themed() }
        .fullScreenCover(isPresented: $riding) { RideView().themed() }
        .confirmationDialog("Sound the bike's siren for 15 seconds? It's loud. Stay connected until it stops.",
                            isPresented: $confirmSiren, titleVisibility: .visible) {
            Button("Sound alarm", role: .destructive) { session.soundSiren() }
        }
    }

    /// The connected Home: speed, assist, quick actions, Start ride.
    private var dashboard: some View {
        GeometryReader { geo in
            // From the current measurements (an onChange copy went stale when the dashboard
            // appeared after the connecting screen, leaving a screen-high gap).
            let gap = max(16, geo.size.height - topHeight - (speedHeight + panelHeight - 36))
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            StatusBanner()
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                        Color.clear.frame(height: gap)
                        speedRow(size: min(250, geo.size.height * 0.34))
                            .opacity(ok ? 1 : 0.35)
                            .animation(.easeInOut(duration: 0.3), value: ok)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { speedHeight = $0 }
                    }
                    .foregroundStyle(theme.paint.on)
                    .background(theme.paint.frame)
                    panel
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Painted area

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.bike?.name ?? "FreeVela").display(34, tracking: 0.01).lineLimit(1).minimumScaleFactor(0.6)
                StatusChip()
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.paint.on)
                    .frame(width: 44, height: 44)
                    .background(theme.paint.deep, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var speedText: String {
        ok ? link.speed(units).map { "\(Int($0.rounded()))" } ?? "—" : "—"
    }

    private func speedRow(size: CGFloat) -> some View {
        Button { units = units.toggled } label: {
            HStack(alignment: .bottom, spacing: 12) {
                Text(speedText)
                    .font(.display(size, weight: 900))
                    .tracking(-size * 0.02)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .padding(.vertical, -size * 0.104)
                    .padding(.bottom, -4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                specBlock.frame(width: 118)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ok)
        .accessibilityLabel("Speed \(speedText) \(units.label)")
        .accessibilityHint("Switches between km/h and mph")
    }

    private var specBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(units.label).display(30)
            rule
            HStack(alignment: .firstTextBaseline) {
                Text("Batt").display(13, weight: 700, tracking: 0.1)
                Spacer()
                Text(link.battery.map { "\($0)%" } ?? "—").display(22)
                if link.flag("pwr.chr") == true { Image(systemName: "bolt.fill").font(.system(size: 13, weight: .bold)) }
            }
            rule
            VStack(alignment: .leading, spacing: 0) {
                Text("Odo").display(13, weight: 700, tracking: 0.1)
                Text(link.odometerPulses.map { distance(pulses: $0, units) } ?? "—")
                    .font(.display(20)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var rule: some View { Rectangle().fill(theme.paint.on).frame(height: 2) }

    // MARK: Tyre panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                if !ok || link.can(.assistModes) { assist }
                quickActions
            }
            .opacity(ok ? 1 : 0.35)
            .disabled(!ok)
            .animation(.easeInOut(duration: 0.3), value: ok)
            InkBarButton(title: "Start ride", symbol: "arrow.right") { riding = true }
                .opacity(ok ? 1 : 0.35)
                .disabled(!ok)
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(TyreBackground())
        .padding(.top, -36)
    }

    private var assistTitle: String {
        guard let mode = session.assist else { return "Assist" }
        return mode == .auto ? "Assist — Auto · eco below \(session.eco)%" : "Assist — \(mode.rawValue)"
    }

    private var assist: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(assistTitle)
            AssistTiles(mode: session.assist) { session.setAssist($0) }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 6) {
            if !ok || link.can(.light) {
                let light = session.light ?? .auto
                QuickAction(symbol: light.symbol, label: "Light \(light.label)", on: light.isOn) {
                    session.setLight(light.next)
                }
            }
            if !ok || link.can(.alarm) {
                let armed = session.isOn("alarm.armed")
                QuickAction(symbol: armed ? "checkmark.shield.fill" : "shield.slash",
                            label: armed ? "Armed" : "Alarm off", on: armed) {
                    session.setAlarm(!armed)
                }
            }
            if !ok || link.can(.findMyBike) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = session.sirenEnds.map { max(0, Int($0.timeIntervalSince(context.date).rounded(.up))) }
                    QuickAction(symbol: "speaker.wave.3.fill", label: left.map { "\($0)s…" } ?? "Find bike", on: left != nil) {
                        if session.sirenEnds == nil { confirmSiren = true }
                    }
                }
            }
            if !ok || link.can(.sleep) {
                QuickAction(symbol: "moon.fill", label: "Sleep", on: false) { session.sleep() }
            }
        }
    }
}

// MARK: - Status banner

/// Explains why the controls are dimmed, with the one action that helps.
struct StatusBanner: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var keys: KeyStore
    @Environment(\.theme) private var theme

    var body: some View {
        if let content {
            HStack(spacing: 12) {
                if content.spinning {
                    ProgressView().tint(theme.ink).frame(width: 22)
                } else {
                    Image(systemName: content.symbol).font(.system(size: 20, weight: .semibold)).frame(width: 22)
                }
                (Text(content.title).font(.archivo(14, weight: 700)) + Text(" " + content.text).font(.archivo(14, weight: 400)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let button = content.button {
                    Button(action: button.1) {
                        Text(button.0)
                            .display(15, tracking: 0.04)
                            .foregroundStyle(theme.paint.on)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(theme.paint.frame, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private struct Content {
        var symbol = "", title: String, text: String, spinning = false
        var button: (String, () -> Void)?
    }

    /// Only on the connected Home now; the not-connected states are ConnectView.
    private var content: Content? {
        guard session.status == .connected, let bike = session.bike, keys.needsBackup.contains(bike.id) else { return nil }
        return Content(symbol: "key.fill", title: "No key backup yet.",
                       text: "Without one, a lost phone means a locked bike.",
                       button: ("Save", { BackupShare.present(keys) }))
    }
}

// MARK: - Controls

/// Four assist tiles; a tap sends the mode at once.
struct AssistTiles: View {
    @Environment(\.theme) private var theme
    var mode: BikeProtocol.AssistMode?
    var onChange: (BikeProtocol.AssistMode) -> Void

    private let modes = BikeProtocol.AssistMode.allCases

    var body: some View {
        HStack(spacing: 6) {
            ForEach(modes) { m in
                let on = m == mode
                let fill = on ? (m == .off ? theme.ink : theme.paint.frame) : theme.tile
                let text = on ? (m == .off ? theme.onInk : theme.paint.on) : theme.ink
                Button { onChange(m) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: m.symbol).font(.system(size: 22, weight: .semibold))
                        Text(m.rawValue).display(16, tracking: 0.04)
                    }
                    .foregroundStyle(text)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(fill, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.18), value: mode)
        .sensoryFeedback(.selection, trigger: mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assist")
        .accessibilityValue(mode?.rawValue ?? "")
        .accessibilityAdjustableAction { direction in
            let i = mode?.index ?? 0
            onChange(modes[direction == .increment ? min(i + 1, modes.count - 1) : max(i - 1, 0)])
        }
    }
}

/// A quick action: ink outline when off, ink fill with cream when on.
struct QuickAction: View {
    @Environment(\.theme) private var theme
    var symbol: String
    var label: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(label).display(12, tracking: 0.06).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? theme.onInk : theme.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(on ? theme.ink : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: on)
    }
}
