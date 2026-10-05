import SwiftUI

/// Home while the bike isn't connected: one status (ring animation, headline, 3-step bar) and the
/// one action that helps. Ends with a short "Connected" moment before the dashboard.
struct ConnectView: View {
    enum Phase: Equatable {
        case bluetooth, searching, connecting, unlocking, locked, asleep, success

        init(_ status: Session.Status) {
            switch status {
            case .bluetooth: self = .bluetooth
            case .searching: self = .searching
            case .connecting: self = .connecting
            case .unlocking: self = .unlocking
            case .locked: self = .locked
            case .asleep: self = .asleep
            case .connected: self = .success
            }
        }

        var symbol: String {
            switch self {
            case .bluetooth: "antenna.radiowaves.left.and.right.slash"
            case .searching: "dot.radiowaves.left.and.right"
            case .connecting: "wave.3.right"
            case .unlocking: "lock.open.fill"
            case .locked: "lock.fill"
            case .asleep: "moon.fill"
            case .success: "checkmark"
            }
        }

        var headline: String {
            switch self {
            case .bluetooth: "Bluetooth is off"
            case .searching: "Looking for your bike"
            case .connecting: "Connecting"
            case .unlocking: "Unlocking"
            case .locked: "Connected, but locked"
            case .asleep: "Bike is asleep"
            case .success: "Connected"
            }
        }

        var message: String {
            switch self {
            case .bluetooth: "FreeVela needs Bluetooth to talk to your bike."
            case .searching: "Make sure you're close to the bike to connect."
            case .connecting: "Found it. Stay close."
            case .unlocking: "Almost there — a couple of seconds."
            case .locked: "Connected, but locked. Unlocking takes a couple of seconds."
            case .asleep: "Hold the brake lever and the handlebar button together to wake it. Or you're not close enough to it."
            case .success: "Unlocked and ready to ride."
            }
        }

        /// Find · Connect · Unlock: steps done, and the step in progress (nil = none).
        var steps: (done: Int, current: Int?)? {
            switch self {
            case .searching: (0, 0)
            case .connecting: (1, 1)
            case .unlocking: (2, 2)
            case .locked: (2, nil)
            case .success: (3, nil)
            case .bluetooth, .asleep: nil
            }
        }
    }

    var phase: Phase
    var onSettings: () -> Void
    @EnvironmentObject private var session: Session
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                RingStack(phase: phase)
                    .accessibilityHidden(true)
                VStack(spacing: 12) {
                    Text(phase.headline)
                        .display(46)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-4)
                    Text(phase.message)
                        .font(.archivo(16, weight: 400))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .id(phase)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .padding(.top, 30)
                if let steps = phase.steps {
                    StepBar(done: steps.done, current: steps.current)
                        .padding(.top, 30)
                        .transition(.opacity)
                }
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
            .foregroundStyle(theme.paint.on)

            action
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(theme.paint.frame.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: phase)
        .sensoryFeedback(.success, trigger: phase == .success)
        .onChange(of: phase.headline) { AccessibilityNotification.Announcement(phase.headline).post() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text(session.bike?.name ?? "FreeVela").display(34, tracking: 0.01).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.paint.on)
                    .frame(width: 44, height: 44)
                    .background(theme.paint.deep, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 10)
        .padding(.horizontal, -8)   // the header uses 20 pt margins, the rest 28
    }

    /// The one action that helps, on the paint; none while the app is working on it.
    @ViewBuilder private var action: some View {
        switch phase {
        case .bluetooth:
            InkBarButton(title: "Open Settings", symbol: "arrow.right", style: .onPaint) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        case .locked:
            InkBarButton(title: "Unlock", symbol: "arrow.right", style: .onPaint) { Task { await session.unlock() } }
        case .asleep:
            InkBarButton(title: "Connect", symbol: "arrow.right", style: .onPaint) { Task { await session.connect() } }
        case .searching, .connecting, .unlocking, .success:
            Color.clear.frame(height: 60)
        }
    }
}

// MARK: - Ring stack

/// The 220 pt status graphic: track, ripples (searching outward, connecting inward), a dashed orbit,
/// the unlocking arc, the success pop, and the disc with the state's symbol.
private struct RingStack: View {
    var phase: ConnectView.Phase
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var successStart: Date?

    private static let searchCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.6),
                                                      endControlPoint: UnitPoint(x: 0.3, y: 1))

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let since = successStart.map { context.date.timeIntervalSince($0) } ?? 99
            let on = theme.paint.on
            ZStack {
                Circle().stroke(on.opacity(0.1), lineWidth: 2).frame(width: 220, height: 220)

                // Ripples
                ForEach(0..<3, id: \.self) { i in
                    let r = ripple(i, t)
                    Circle().stroke(on, lineWidth: 2)
                        .frame(width: 220, height: 220)
                        .scaleEffect(r.scale)
                        .opacity(r.opacity)
                }
                .opacity(!reduceMotion && (phase == .searching || phase == .connecting) ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: phase)

                // Orbit
                Circle()
                    .stroke(on.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                    .frame(width: 148, height: 148)
                    .rotationEffect(.degrees(phase == .asleep && !reduceMotion ? (t / 40).truncatingRemainder(dividingBy: 1) * 360 : 0))
                    .opacity(phase == .asleep || phase == .locked ? 1 : phase == .bluetooth ? 0.45 : 0)
                    .animation(.easeInOut(duration: 0.35), value: phase)

                // Unlocking arc
                ZStack {
                    Circle().stroke(on.opacity(0.15), lineWidth: 3)
                    Circle().trim(from: 0, to: 0.25)
                        .stroke(on, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
                }
                .frame(width: 124, height: 124)
                .opacity(phase == .unlocking ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: phase)

                // Success pop
                if phase == .success, !reduceMotion, since < 0.8 {
                    let p = since / 0.8
                    Circle().stroke(on, lineWidth: 3)
                        .frame(width: 220, height: 220)
                        .scaleEffect(0.55 + 0.65 * UnitCurve.easeOut.value(at: p))
                        .opacity(1 - p)
                }

                // Disc
                Circle()
                    .fill(phase == .success ? on : theme.paint.deep)
                    .frame(width: 108, height: 108)
                    .overlay {
                        Image(systemName: phase.symbol)
                            .font(.system(size: 46, weight: .semibold))
                            .foregroundStyle(phase == .success ? theme.paint.frame : on)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .scaleEffect(discScale(t, since))
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
            .frame(width: 220, height: 220)
        }
        .onChange(of: phase, initial: true) { successStart = phase == .success ? .now : nil }
    }

    /// Scale and opacity of ripple `i` at time `t`.
    private func ripple(_ i: Int, _ t: TimeInterval) -> (scale: Double, opacity: Double) {
        if phase == .connecting {
            let p = cycle(t, period: 1.5, delay: Double(i) * 0.5)
            let e = UnitCurve.easeIn.value(at: p)
            return (1.15 - 0.65 * e, ramp(p, peak: 0.4, max: 0.5))
        }
        let p = cycle(t, period: 2.4, delay: Double(i) * 0.8)
        let e = Self.searchCurve.value(at: p)
        return (0.5 + 0.65 * e, ramp(p, peak: 0.15, max: 0.6))
    }

    private func cycle(_ t: TimeInterval, period: Double, delay: Double) -> Double {
        let x = (t - delay).truncatingRemainder(dividingBy: period)
        return (x < 0 ? x + period : x) / period
    }

    /// 0 → max at `peak` → 0 at the end.
    private func ramp(_ p: Double, peak: Double, max: Double) -> Double {
        p < peak ? max * p / peak : max * (1 - (p - peak) / (1 - peak))
    }

    private func discScale(_ t: TimeInterval, _ since: Double) -> Double {
        if reduceMotion { return 1 }
        switch phase {
        case .searching: return 1 + 0.025 * (1 - cos(2 * .pi * cycle(t, period: 2.4, delay: 0)))
        case .asleep: return 1 + 0.025 * (1 - cos(2 * .pi * cycle(t, period: 4.8, delay: 0)))
        case .success: return since < 0.5 ? 1 + 0.12 * sin(.pi * since / 0.5) : 1
        default: return 1
        }
    }
}

// MARK: - Step bar

/// Find · Connect · Unlock. The step in progress fills and empties in a loop.
private struct StepBar: View {
    var done: Int
    var current: Int?
    @Environment(\.theme) private var theme

    private let labels = ["Find", "Connect", "Unlock"]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.paint.deep)
                            Capsule().fill(theme.paint.on)
                                .scaleEffect(x: fill(i, t), anchor: .leading)
                        }
                        .frame(height: 4)
                        Text(labels[i])
                            .display(13, weight: 700, tracking: 0.1)
                            .opacity(i < done || i == current ? 1 : 0.45)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: done)
    }

    private func fill(_ i: Int, _ t: TimeInterval) -> Double {
        if i < done { return 1 }
        guard i == current else { return 0 }
        // 0.08 → 1 over 1.1 s, then back (autoreverse), ease in-out.
        let x = (t / 1.1).truncatingRemainder(dividingBy: 2)
        let p = x < 1 ? x : 2 - x
        return 0.08 + 0.92 * UnitCurve.easeInOut.value(at: p)
    }
}
