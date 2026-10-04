import SwiftUI

/// Speed first: a huge number, one big assist slider and round quick actions.
/// Keys, units and developer tools live in Settings.
struct HomeView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @AppStorage("units") private var units: Units = .kmh
    @State private var showSettings = false
    @State private var riding = false
    @State private var confirmSiren = false

    private var ok: Bool { link.isUnlocked }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    StatusBanner()
                    VStack(spacing: 0) {
                        speed.frame(maxHeight: .infinity)
                        if !ok || link.can(.assistModes) { assist }
                        quickActions
                        startRide
                    }
                    .opacity(ok ? 1 : 0.35)
                    .disabled(!ok)
                    .animation(.easeInOut(duration: 0.3), value: ok)
                }
                .padding(.bottom, 16)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $riding) { RideView() }
        .confirmationDialog("Sound the bike's siren for 15 seconds? It's loud. Stay connected until it stops.",
                            isPresented: $confirmSiren, titleVisibility: .visible) {
            Button("Sound alarm", role: .destructive) { session.soundSiren() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(session.bike?.name ?? "FreeVela").font(.title2.bold())
                StatusLabel()
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var speed: some View {
        Button { units = units.toggled } label: {
            VStack(spacing: 0) {
                Text(ok ? link.speed(units).map { "\(Int($0.rounded()))" } ?? "—" : "—")
                    .font(.system(size: 148, weight: .bold).monospacedDigit())
                    .tracking(-6)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(units.label).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Label(link.battery.map { "\($0)%" } ?? "—%", systemImage: link.batterySymbol)
                        .labelStyle(TintedIconLabel(tint: .green))
                    Label(link.odometerPulses.map { distance(pulses: $0, units) } ?? "—",
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .labelStyle(TintedIconLabel(tint: .secondary))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Switches between km/h and mph")
    }

    private var assist: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Assist").fontWeight(.semibold)
                Spacer()
                Text(session.assist == .auto ? "Auto · eco below \(session.eco)%" : session.assist?.rawValue ?? "")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 10)
            AssistSlider(mode: session.assist) { session.setAssist($0) }
        }
        .padding(.horizontal, 20)
    }

    private var quickActions: some View {
        HStack(alignment: .top, spacing: 0) {
            if !ok || link.can(.light) {
                let light = session.light ?? .auto
                QuickAction(symbol: light.symbol, label: "Light \(light.label)",
                            fill: light.isOn ? .orange : nil, tint: light.isOn ? .white : .gray) {
                    session.setLight(light.next)
                }
            }
            if !ok || link.can(.alarm) {
                let armed = session.isOn("alarm.armed")
                QuickAction(symbol: armed ? "checkmark.shield.fill" : "shield.slash",
                            label: armed ? "Armed" : "Alarm off",
                            fill: armed ? .green : nil, tint: armed ? .white : .gray) {
                    session.setAlarm(!armed)
                }
            }
            if !ok || link.can(.findMyBike) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = session.sirenEnds.map { max(0, Int($0.timeIntervalSince(context.date).rounded(.up))) }
                    QuickAction(symbol: "speaker.wave.3.fill", label: left.map { "\($0)s" } ?? "Find bike",
                                fill: left == nil ? nil : .red, tint: left == nil ? .red : .white) {
                        if session.sirenEnds == nil { confirmSiren = true }
                    }
                }
            }
            if !ok || link.can(.sleep) {
                QuickAction(symbol: "moon.fill", label: "Sleep", fill: nil, tint: .indigo) { session.sleep() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 22)
    }

    private var startRide: some View {
        Button { riding = true } label: {
            Label("Start ride", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(Color(.systemBackground))
                .background(Color.primary, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }
}

// MARK: - Status

/// "● Connected" under the bike's name.
struct StatusLabel: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink

    var body: some View {
        let (text, color): (String, Color) = switch session.status {
        case .connected: ("Connected", .green)
        case .locked: ("Locked", .orange)
        case .searching: ("Searching…", .orange)
        case .bluetooth: ("Bluetooth off", .gray)
        case .asleep: ("Asleep", .gray)
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Explains why the controls are dimmed, with the one action that helps.
struct StatusBanner: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink

    var body: some View {
        if let content {
            HStack(spacing: 10) {
                if content.spinning {
                    ProgressView().frame(width: 22)
                } else {
                    Image(systemName: content.symbol).font(.title3).foregroundStyle(.orange).frame(width: 22)
                }
                (Text(content.title).bold() + Text(" " + content.text))
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let button = content.button {
                    Button(button.0, action: button.1)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    private struct Content {
        var symbol = "", title: String, text: String, spinning = false
        var button: (String, () -> Void)?
    }

    private var content: Content? {
        switch session.status {
        case .connected:
            return nil
        case .bluetooth(let state):
            return Content(symbol: "antenna.radiowaves.left.and.right.slash", title: "Bluetooth is \(state).",
                           text: "FreeVela needs Bluetooth to talk to your bike.")
        case .searching(let what):
            return Content(title: what, text: "Stand next to it. Close the old Vela app — the bike talks to one phone at a time.",
                           spinning: true)
        case .locked:
            return Content(symbol: "lock.fill", title: "Connected, but locked.", text: "Unlocking takes a couple of seconds.",
                           button: ("Unlock", { Task { await session.unlock() } }))
        case .asleep:
            return Content(symbol: "moon.fill", title: "Bike is asleep.",
                           text: "Hold the brake lever and the handlebar button together to wake it.",
                           button: ("Connect", { Task { await session.connect() } }))
        }
    }
}

// MARK: - Controls

/// One fat 4-stop slider: drag or tap anywhere on it. Sends the mode when you let go.
struct AssistSlider: View {
    var mode: BikeProtocol.AssistMode?
    var onChange: (BikeProtocol.AssistMode) -> Void
    @State private var dragging: Int?

    private let modes = BikeProtocol.AssistMode.allCases
    private let height: CGFloat = 64

    var body: some View {
        let shown = dragging ?? mode?.index ?? 0
        let frac = CGFloat(shown) / CGFloat(modes.count - 1)
        GeometryReader { geo in
            let pad = height / 2, track = geo.size.width - height
            let x = pad + track * frac
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.secondarySystemBackground))
                Capsule()
                    .fill(shown == 0 ? Color(.systemGray).opacity(0.35) : .accentColor)
                    .frame(width: x + pad)
                ForEach(Array(modes.enumerated()), id: \.offset) { i, m in
                    Text(m.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(i < shown ? AnyShapeStyle(.white.opacity(0.9)) : i == shown ? AnyShapeStyle(.clear) : AnyShapeStyle(.secondary))
                        .frame(width: 60)
                        .position(x: pad + track * CGFloat(i) / CGFloat(modes.count - 1), y: height / 2)
                }
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                    .frame(width: height - 8, height: height - 8)
                    .overlay {
                        Image(systemName: modes[shown].symbol)
                            .font(.system(size: 22))
                            .foregroundStyle(shown == 0 ? Color(.systemGray) : .accentColor)
                    }
                    .position(x: x, y: height / 2)
            }
            .animation(.snappy(duration: 0.18), value: shown)
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragging = index(at: $0.location.x, pad: pad, track: track) }
                .onEnded {
                    let i = index(at: $0.location.x, pad: pad, track: track)
                    dragging = nil
                    onChange(modes[i])
                })
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: shown)
        .accessibilityElement()
        .accessibilityLabel("Assist")
        .accessibilityValue(modes[shown].rawValue)
        .accessibilityAdjustableAction { direction in
            let i = direction == .increment ? min(shown + 1, modes.count - 1) : max(shown - 1, 0)
            onChange(modes[i])
        }
    }

    private func index(at x: CGFloat, pad: CGFloat, track: CGFloat) -> Int {
        let f = min(max((x - pad) / track, 0), 1)
        return Int((f * CGFloat(modes.count - 1)).rounded())
    }
}

/// A round 56 pt button with a caption. `fill == nil` means the quiet gray background.
struct QuickAction: View {
    var symbol: String
    var label: String
    var fill: Color?
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(fill ?? Color(.secondarySystemBackground), in: Circle())
                Text(label).font(.caption).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: fill)
    }
}

/// A label whose icon has its own color.
struct TintedIconLabel<S: ShapeStyle>: LabelStyle {
    var tint: S
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
