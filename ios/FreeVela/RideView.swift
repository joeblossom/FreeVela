import SwiftUI

/// Handlebar mode: dark, huge speed, big targets. Keeps the screen on while open.
struct RideView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var recorder: RideRecorder
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units: Units = .kmh
    @State private var started = Date.now
    @State private var startPulses: Double?

    @Environment(\.theme) private var theme

    private let cream = Theme.creamFixed

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Button { units = units.toggled } label: { speed }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)
            assist
            bottomBar
        }
        .foregroundStyle(cream)
        .background(Theme.rideBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            started = .now
            startPulses = link.odometerPulses
            UIApplication.shared.isIdleTimerDisabled = true
            StatusBar.set(lightText: true)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            StatusBar.set(lightText: !theme.paint.isLight)
        }
        .onChange(of: link.odometerPulses) { if startPulses == nil { startPulses = $1 } }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Batt \(link.battery.map { "\($0)%" } ?? "—")")
                if link.flag("pwr.chr") == true { Image(systemName: "bolt.fill").font(.system(size: 16, weight: .bold)) }
            }
            .display(20, tracking: 0.06)
            Spacer()
            HStack(spacing: 14) {
                if recorder.recording {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red).accessibilityLabel("Recording")
                }
                Image(systemName: (session.light ?? .auto).symbol)
                    .foregroundStyle(session.light?.isOn == false ? Theme.rideLightOff : Theme.rideLightOn)
                Image(systemName: link.isUnlocked ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(link.isUnlocked ? Theme.rideMuted : .red)
            }
            .font(.system(size: 22, weight: .semibold))
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var speed: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(link.isUnlocked ? link.speed(units).map { "\(Int($0.rounded()))" } ?? "—" : "—")
                .font(.display(300, weight: 900))
                .tracking(-6)
                .foregroundStyle(theme.paint.lit)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText())
                .padding(.vertical, -30)
            VStack(spacing: 10) {
                Rectangle().fill(cream).frame(height: 2)
                HStack(alignment: .top, spacing: 0) {
                    stat("Units", units.label.uppercased())
                    stat("Trip", tripDistance)
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        stat("Time", Duration.seconds(context.date.timeIntervalSince(started))
                            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1))))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var tripDistance: String {
        guard let now = link.odometerPulses, let start = startPulses else { return "—" }
        return distance(pulses: max(0, now - start), units)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).display(13, weight: 700, tracking: 0.1).foregroundStyle(Theme.rideMuted)
            Text(value).font(.display(26)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assist: some View {
        let modes = BikeProtocol.AssistMode.allCases
        let mode = session.assist ?? .off
        let current = mode.index
        return HStack(spacing: 8) {
            squareButton("minus") { session.setAssist(modes[max(current - 1, 0)]) }
                .accessibilityLabel("Less assist")
            VStack(spacing: 10) {
                // Low lights one bar, Auto two, High three; Off none.
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(1...3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i <= current ? theme.paint.lit : Theme.rideBarOff)
                            .frame(width: 18, height: CGFloat(2 + i * 10))
                    }
                }
                .frame(height: 32, alignment: .bottom)
                Text(mode.rawValue).display(20, tracking: 0.04)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.rideControl, in: RoundedRectangle(cornerRadius: 18))
            .animation(.easeInOut(duration: 0.2), value: current)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Assist \(mode.rawValue)")
            squareButton("plus") { session.setAssist(modes[min(current + 1, modes.count - 1)]) }
                .accessibilityLabel("More assist")
        }
        .disabled(!link.isUnlocked || !link.can(.assistModes))
        .sensoryFeedback(.selection, trigger: current)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func squareButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .frame(width: 84, height: 84)
                .background(Theme.rideControl, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        let light = session.light ?? .auto
        return HStack(spacing: 8) {
            Button { session.setLight(light.next) } label: {
                HStack(spacing: 10) {
                    Image(systemName: light.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(light.isOn ? Theme.rideLightOn : Theme.rideLightOff)
                    Text("Light \(light.label)").display(20, tracking: 0.04)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Theme.rideControl, in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!link.isUnlocked || !link.can(.light))
            Button { dismiss() } label: {
                Text("End ride")
                    .display(20, weight: 900, tracking: 0.04)
                    .foregroundStyle(Theme.rideBg)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(theme.paint.lit, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
