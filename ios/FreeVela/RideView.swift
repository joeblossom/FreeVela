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

    private let dim = Color(white: 0.92, opacity: 0.6)
    private let control = Color(white: 0.11)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Button { units = units.toggled } label: { speed }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)
            assist
            bottomBar
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            started = .now
            startPulses = link.odometerPulses
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: link.odometerPulses) { if startPulses == nil { startPulses = $1 } }
    }

    private var topBar: some View {
        HStack {
            Label(link.battery.map { "\($0)%" } ?? "—", systemImage: link.batterySymbol)
                .labelStyle(TintedIconLabel(tint: .green))
                .monospacedDigit()
            Spacer()
            HStack(spacing: 14) {
                if recorder.recording {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red).accessibilityLabel("Recording")
                }
                Image(systemName: (session.light ?? .auto).symbol)
                    .foregroundStyle(session.light?.isOn == false ? Color.white.opacity(0.3) : .yellow)
                Image(systemName: link.isUnlocked ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(link.isUnlocked ? .blue : .red)
            }
            .font(.title3)
        }
        .font(.headline)
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private var speed: some View {
        VStack(spacing: 0) {
            Text(link.isUnlocked ? link.speed(units).map { "\(Int($0.rounded()))" } ?? "—" : "—")
                .font(.system(size: 200, weight: .bold).monospacedDigit())
                .tracking(-10)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(units.label).font(.title2.weight(.semibold)).foregroundStyle(dim)
            HStack(spacing: 28) {
                stat(tripDistance, "Trip")
                TimelineView(.periodic(from: started, by: 1)) { context in
                    stat(Duration.seconds(context.date.timeIntervalSince(started))
                        .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1))), "Time")
                }
            }
            .padding(.top, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var tripDistance: String {
        guard let now = link.odometerPulses, let start = startPulses else { return "—" }
        return distance(pulses: max(0, now - start), units)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).fixedSize()
            Text(label).font(.subheadline).foregroundStyle(dim)
        }
    }

    private var assist: some View {
        let modes = BikeProtocol.AssistMode.allCases
        let current = session.assist?.index ?? 0
        return HStack(spacing: 14) {
            roundButton("minus") { session.setAssist(modes[max(current - 1, 0)]) }
                .accessibilityLabel("Less assist")
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(modes.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i > 0 && i <= current ? Color.blue : Color(white: 0.17))
                            .frame(width: 18, height: CGFloat(10 + i * 10))
                    }
                }
                .frame(height: 40, alignment: .bottom)
                Label(modes[current].rawValue, systemImage: modes[current].symbol)
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: current)
            roundButton("plus") { session.setAssist(modes[min(current + 1, modes.count - 1)]) }
                .accessibilityLabel("More assist")
        }
        .disabled(!link.isUnlocked || !link.can(.assistModes))
        .sensoryFeedback(.selection, trigger: current)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .frame(width: 76, height: 76)
                .background(control, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        let light = session.light ?? .auto
        return HStack(spacing: 12) {
            Button { session.setLight(light.next) } label: {
                Label { Text("Light \(light.label)") } icon: {
                    Image(systemName: light.symbol).foregroundStyle(light.isOn ? .yellow : Color.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(control, in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!link.isUnlocked || !link.can(.light))
            Button { dismiss() } label: {
                Text("End ride")
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .buttonStyle(.plain)
        .font(.headline)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
