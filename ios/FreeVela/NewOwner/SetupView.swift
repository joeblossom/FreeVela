import SwiftUI

/// "Set up your bike": the walkthrough screens for SetupModel.
struct SetupView: View {
    var onCancel: () -> Void
    var onFinish: () -> Void
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var keys: KeyStore
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var updater: FirmwareUpdater
    @Environment(\.theme) private var theme
    @StateObject private var holder = Holder()
    @AppStorage("acceptedFirmwareRisk") private var acceptedRisk = false
    @State private var confirmCancel = false
    @State private var skipBackup = false

    /// Builds the model once the environment objects are available.
    private final class Holder: ObservableObject { var model: SetupModel? }

    private var model: SetupModel {
        if let m = holder.model { return m }
        let m = SetupModel(link: link, keys: keys, session: session, updater: updater)
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoSetup"), i + 1 < args.count { m.loadDemo(args[i + 1]) }
        #endif
        holder.model = m
        return m
    }

    var body: some View {
        SetupScreens(model: model, acceptedRisk: $acceptedRisk, skipBackup: $skipBackup,
                     onCancel: { if model.trialEnds != nil || updater.running { confirmCancel = true } else { stop() } },
                     onFinish: { model.finish(); onFinish() })
            .confirmationDialog("Stop setting up?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Stop", role: .destructive) { stop() }
            } message: {
                Text("If FreeVela firmware is on trial, the bike switches back to its old firmware when the 10 minutes run out. That's safe.")
            }
            .alert("Skip the backup?", isPresented: $skipBackup) {
                Button("Later") { model.step = .done }
                Button("Save backup") { model.saveBackup() }.keyboardShortcut(.defaultAction)
            } message: {
                Text("Without one, a lost phone means a locked bike. You can save it any time in Settings → Bikes & keys.")
            }
    }

    private func stop() {
        model.cancel()
        onCancel()
    }
}

private struct SetupScreens: View {
    @ObservedObject var model: SetupModel
    @Binding var acceptedRisk: Bool
    @Binding var skipBackup: Bool
    var onCancel: () -> Void
    var onFinish: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            switch model.step {
            case .checklist: checklist
            case .find: find
            case .alreadyFreeVela: alreadyFreeVela
            case .install: install
            case .installing: installing
            case .installed: installed
            case .reset: reset
            case .pair: pair
            case .backup: backup
            case .done: done
            case .notFound:
                errorPage(icon: "antenna.radiowaves.left.and.right.slash", "Can't find your bike",
                          "It may be asleep, or still talking to another phone.",
                          points: [("bicycle", "Wake it", "Hold the brake lever and the handlebar button together."),
                                   ("xmark", "Close the old Vela app", "On every phone nearby."),
                                   ("iphone", "Stand right next to it", "Bluetooth only reaches a few metres.")],
                          button: ("Try again", "arrow.clockwise", { model.find() }))
            case .lowBattery: lowBattery
            case .installStopped:
                errorPage(icon: "exclamationmark.arrow.triangle.2.circlepath", "The install stopped",
                          "The connection dropped, so the bike kept its old firmware. Nothing changed.",
                          points: [("iphone", "Keep this screen open", "The install needs the app in front."),
                                   ("bicycle", "Stay next to the bike", "Within a metre or two the whole time.")],
                          button: ("Try again", "arrow.clockwise", { model.install() }))
            case .windowRanOut:
                errorPage(icon: "clock.badge.xmark", "The bike switched back",
                          "The 10 minutes ran out, so it went back to its old firmware. That's safe. Install again to have another go.",
                          points: [("checkmark.shield.fill", "Nothing is lost", "The bike works as before."),
                                   ("hand.raised.fill", "Have both hands free", "The reset needs the brake lever and the button.")],
                          button: ("Install again", "arrow.clockwise", { model.find() }))
            case .noChirps: noChirps
            case .otherPhone:
                errorPage(icon: "iphone.slash", "Another phone got there first",
                          "This bike was just paired with a different phone.",
                          points: [("iphone", "Keep other phones away", "Close FreeVela on any other phone nearby."),
                                   ("key.fill", "Reset the keys again", "Then pair straight after the long tone.")],
                          button: ("Reset again", "arrow.clockwise", { model.startReset() }))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.step)
    }

    // MARK: Layout

    private func page<Panel: View, Bottom: View>(
        icons: [String] = [], _ title: String, _ text: String,
        back: Bool = true,
        @ViewBuilder panel: () -> Panel, @ViewBuilder bottom: () -> Bottom
    ) -> some View {
        PaintedLayout {
            VStack(alignment: .leading, spacing: 14) {
                WalkthroughHeader(step: model.step.number, timerEnds: model.step.showsTimer ? model.trialEnds : nil,
                                  onBack: back ? { model.step == .checklist ? onCancel() : model.back() } : nil,
                                  onCancel: onCancel)
                    .padding(.top, -16)
                    .padding(.bottom, 6)
                if !icons.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(Array(icons.enumerated()), id: \.offset) { i, icon in
                            Image(systemName: icon).font(.system(size: i == 0 ? 54 : 30, weight: i == 0 ? .regular : .semibold))
                        }
                    }
                }
                Text(title).display(44)
                Text(text).font(.archivo(17, weight: 400)).opacity(0.9)
            }
        } panel: {
            VStack(alignment: .leading, spacing: 16) { panel() }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) { bottom() }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(theme.cream.ignoresSafeArea())
        }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).display(18, tracking: 0.02).foregroundStyle(theme.ink)
                Text(text).font(.archivo(15, weight: 400)).foregroundStyle(theme.inkMuted)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.archivo(14, weight: 400)).foregroundStyle(theme.inkMuted)
    }

    private func waiting(_ text: String) -> some View {
        Text(text)
            .display(20, tracking: 0.04)
            .foregroundStyle(theme.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(theme.tile, in: RoundedRectangle(cornerRadius: 16))
    }

    private func textButton(_ title: String, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).display(16, tracking: 0.04).foregroundStyle(muted ? theme.inkMuted : theme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func stepRow(_ label: String, done: Bool, now: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if now { ProgressView().tint(theme.ink) } else {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? theme.actionColor : theme.tile)
                }
            }
            .font(.system(size: 24, weight: .semibold))
            .frame(width: 28)
            Text(now ? label + "…" : label).display(20, tracking: 0.03).foregroundStyle(done || now ? theme.ink : theme.inkMuted)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorPage(icon: String, _ title: String, _ text: String, points: [(String, String, String)],
                           outline: (String, String)? = nil, button: (String, String, () -> Void)) -> some View {
        page(icons: [icon], title, text) {
            SectionHeader("Try this")
            ForEach(points, id: \.1) { point($0.0, $0.1, $0.2) }
            if let outline {
                VStack(alignment: .leading, spacing: 6) {
                    Text(outline.0).display(18, tracking: 0.02).foregroundStyle(theme.ink)
                    Text(outline.1).font(.archivo(14, weight: 400)).foregroundStyle(theme.inkMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.ink, lineWidth: 2))
            }
        } bottom: {
            InkBarButton(title: button.0, symbol: button.1, action: button.2)
        }
    }

    // MARK: Step 0

    private var checklist: some View {
        page(icons: ["person.badge.plus"], "Set up your bike",
             "You'll install FreeVela firmware, reset the bike's keys, then pair this phone as its owner. No old keys needed.") {
            SectionHeader("Before you start")
            point("iphone", "Phone next to the bike", "Keep it within a metre or two the whole time.")
            point("battery.75percent", "Charged to at least 40%", "Installing firmware needs some battery in reserve.")
            point("bicycle", "On its stand, wheel still", "The reset only works when the wheel isn't moving.")
            point("clock", "About 10–15 minutes", "Most of it is waiting for the install.")
            point("xmark", "Old Vela app closed", "On every phone nearby. The bike talks to one phone at a time.")
        } bottom: {
            InkBarButton(title: "Start", symbol: "arrow.right") { model.find() }
        }
    }

    // MARK: Step 1

    private var find: some View {
        page(icons: ["bicycle", "hand.raised.fill"], "Wake and find your bike",
             "Hold the brake lever and the handlebar button together. Neither one alone wakes it.") {
            if model.searching {
                stepRow("Looking for your bike", done: false, now: true)
                note("Stay right next to it. If the old Vela app is open on any phone, close it.")
            } else {
                SectionHeader("Found")
                foundCard(title: "Vela V2")
                note("This phone can see the bike but can't control it yet. The next steps fix that.")
            }
        } bottom: {
            if model.searching { waiting("Waiting for your bike…") } else {
                InkBarButton(title: "Continue", symbol: "arrow.right") { model.continueFromFound() }
            }
        }
    }

    private func foundCard(title: String) -> some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: "bicycle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 64, height: 64)
                    .overlay(Circle().strokeBorder(theme.ink, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).display(26).foregroundStyle(theme.ink)
                    Text([model.deviceID.map { String($0.prefix(8)) }, model.info.map { "\($0.fuel)% battery" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(theme.inkMuted)
                }
            }
            Rectangle().fill(theme.tile).frame(height: 1)
            LabeledContent("Firmware") { Text(model.info.map { "FreeVela \($0.ver)" } ?? "Vela original") }
            LabeledContent("Keys on this phone") { Text("None yet") }
        }
        .font(.archivo(15, weight: 500))
        .foregroundStyle(theme.ink)
    }

    private var alreadyFreeVela: some View {
        let keyless = model.info?.keyed == 0
        return page(icons: ["checkmark.circle.fill"], "Already on FreeVela",
                    "This bike already runs FreeVela firmware, so you can skip the install and go straight to the reset.") {
            foundCard(title: "Vela V2")
            note(keyless ? "It has no owner yet, so you can pair this phone straight away." : "No install needed. Next, reset the keys on the bike.")
        } bottom: {
            InkBarButton(title: keyless ? "Pair this phone" : "Go to the reset", symbol: "arrow.right") {
                keyless ? model.pair() : model.startReset()
            }
        }
    }

    // MARK: Step 2

    private var install: some View {
        page("Install FreeVela firmware",
             "No keys needed. The bike checks the firmware itself and keeps its old one if anything goes wrong.") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock").font(.system(size: 16, weight: .semibold))
                note("About 3–4 minutes. Then you'll have 10 minutes for the reset and pairing.")
            }
            .foregroundStyle(theme.inkMuted)
            if !model.onFreeVela {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "battery.75percent").font(.system(size: 16, weight: .semibold))
                    note("Check it's charged to at least 40% — on its original firmware the bike can't tell the app its battery level.")
                }
                .foregroundStyle(theme.inkMuted)
            }
            riskCard
            if let error = model.error { Text(error).font(.archivo(14, weight: 500)).foregroundStyle(.red) }
        } bottom: {
            InkBarButton(title: "Install \(FirmwareImage.setup.label)", symbol: "arrow.down") { model.install() }
                .opacity(acceptedRisk ? 1 : 0.35)
                .disabled(!acceptedRisk)
        }
    }

    private var riskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 26)).foregroundStyle(.red)
                Text("Use at your own risk").display(24, tracking: 0.02).foregroundStyle(theme.ink)
            }
            Text("FreeVela isn't made or supported by Vela. It's tested, but not on every bike. Something could go wrong, up to a bike that no longer works.")
                .font(.archivo(14, weight: 400)).foregroundStyle(theme.ink)
            Text("The FreeVela developers aren't responsible for any damage, injury or loss.")
                .font(.archivo(14, weight: 600)).foregroundStyle(theme.ink)
            Rectangle().fill(theme.tile).frame(height: 1)
            Button { acceptedRisk.toggle() } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(acceptedRisk ? theme.ink : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.ink, lineWidth: 2))
                        .overlay { if acceptedRisk { Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(theme.onInk) } }
                        .frame(width: 26, height: 26)
                    Text("I understand and accept the risk").font(.archivo(15, weight: 600)).foregroundStyle(theme.ink)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(acceptedRisk ? .isSelected : [])
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.ink, lineWidth: 3))
    }

    private var installing: some View {
        page("Install FreeVela firmware",
             "No keys needed. The bike checks the firmware itself and keeps its old one if anything goes wrong.", back: false) {
            HStack(alignment: .lastTextBaseline) {
                (Text("\(Int(model.installFraction * 100))").font(.display(96, weight: 900))
                 + Text("%").font(.display(40)))
                    .foregroundStyle(theme.ink)
                    .contentTransition(.numericText())
                Spacer()
                Text(model.downloading ? "Downloading" : "About 3–4 minutes").display(13, weight: 700, tracking: 0.1).foregroundStyle(theme.inkMuted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.tile)
                    Capsule().fill(theme.paint.frame).frame(width: geo.size.width * model.installFraction)
                }
            }
            .frame(height: 6)
            stepRow("Sending firmware", done: model.installPhase > 0, now: model.installPhase == 0)
            stepRow("Installing", done: model.installPhase > 1, now: model.installPhase == 1)
            stepRow("Restarting the bike", done: false, now: model.installPhase == 2)
            note("Keep the phone next to the bike and this screen open.")
        } bottom: {
            waiting(model.downloading ? "Downloading…" : "Installing…")
        }
    }

    private var installed: some View {
        page(icons: ["timer"], "Installed. Now 10 minutes.",
             "The bike restarted with FreeVela firmware on trial. Finish the next two steps before the timer runs out.") {
            card {
                SectionHeader("Time to finish")
                TrialClock(ends: model.trialEnds).font(.display(40, weight: 900)).foregroundStyle(theme.ink)
                HStack(spacing: 6) {
                    ForEach(["3 · Reset keys", "4 · Pair phone"], id: \.self) { label in
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(theme.paint.frame).frame(height: 6)
                            Text(label).display(12, weight: 700, tracking: 0.08).foregroundStyle(theme.inkMuted)
                        }
                    }
                }
            }
            note("If time runs out, the bike switches back to its old firmware by itself. That's safe — you'd just install again. Most people need about two minutes.")
        } bottom: {
            InkBarButton(title: "Reset the keys", symbol: "arrow.right") { model.startReset() }
        }
    }

    private var lowBattery: some View {
        let fuel = model.info?.fuel ?? 0
        return page(icons: ["battery.25percent"], "Charge to at least 40% first",
                    "Installing firmware needs a bit of battery in reserve. Your bike is at \(fuel)%.") {
            card {
                HStack {
                    Text("Battery").display(15, weight: 700, tracking: 0.08).foregroundStyle(theme.inkMuted)
                    Spacer()
                    Text("\(fuel)%").display(22).foregroundStyle(theme.ink)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.tile)
                        Capsule().fill(theme.paint.frame).frame(width: geo.size.width * Double(fuel) / 100)
                        Rectangle().fill(theme.ink).frame(width: 2, height: 18).offset(x: geo.size.width * 0.4)
                    }
                }
                .frame(height: 10)
                Text("40% needed").font(.archivo(12, weight: 600)).foregroundStyle(theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            note("Plug the bike in. You can leave this screen open — it carries on by itself once there's enough charge.")
        } bottom: {
            waiting("Waiting for 40%")
        }
    }

    // MARK: Step 3

    private var reset: some View {
        let held = model.hold
        return page("Reset the keys on the bike",
                    "With the wheel still, let go of everything. Then hold the brake lever and the handlebar button together for 15 seconds.") {
            HStack(alignment: .lastTextBaseline) {
                (Text("\(held)").font(.display(104, weight: 900)) + Text(" of 15 s").font(.display(22)).foregroundColor(theme.inkMuted))
                    .foregroundStyle(theme.ink)
                    .contentTransition(.numericText())
                Spacer()
                Label("Live from bike", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.archivo(12, weight: 700)).textCase(.uppercase).foregroundStyle(theme.inkMuted)
            }
            HoldTimeline(held: held)
            card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: held == 0 ? "hand.raised.fill" : held <= 5 ? "hourglass" : held < 15 ? "waveform" : "speaker.wave.3.fill")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.ink).frame(width: 24)
                    resetStatus(held).font(.archivo(15, weight: 400)).foregroundStyle(theme.ink)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                note("• Start fresh: let go of both first, even if you just used them to wake the bike.")
                note("• Keep the wheel still the whole time.")
            }
        } bottom: {
            waiting(held >= 15 ? "Bike restarting…" : "Waiting for the long tone…")
            HStack {
                textButton("No chirps?", muted: true) { model.step = .noChirps }
                textButton("I heard the long tone") { model.pair() }
            }
        }
    }

    private func resetStatus(_ held: Int) -> Text {
        switch held {
        case 0: Text("Ready.").bold() + Text(" Start holding both now. The count starts on the bike.")
        case 1...5: Text("Keep holding.").bold() + Text(" It's quiet for the first 5 seconds.")
        case 6..<15: Text("Keep holding.").bold() + Text(" A short chirp every second until 15.")
        default: Text("Long tone.").bold() + Text(" Let go. The bike is erasing its keys and restarting.")
        }
    }

    private var noChirps: some View {
        errorPage(icon: "speaker.slash.fill", "No chirps?", "The bike didn't start counting. Check these, then hold again.",
                  points: [("hand.raised.fill", "Let go of both first", "Then press the brake lever and the button again."),
                           ("bicycle", "Keep the wheel still", "Any movement stops the count."),
                           ("hand.point.up.left.fill", "Press both at once", "The brake lever and the handlebar button together.")],
                  button: ("Hold again", "arrow.clockwise", { model.startReset() }))
    }

    // MARK: Step 4

    private var pair: some View {
        page(icons: ["iphone.radiowaves.left.and.right"], "Pair this phone",
             "FreeVela makes new keys and gives them to the bike. The first phone to do this becomes the owner, so keep other phones with FreeVela away.") {
            stepRow("Looking for your bike", done: model.pairStage > 0, now: model.pairStage == 0 && !model.pairFailed)
            stepRow("Making new keys", done: model.pairStage > 1, now: model.pairStage == 1)
            stepRow("Pairing this phone", done: model.pairStage > 2, now: model.pairStage == 2)
            if model.pairStage == 3 {
                card {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 24)).foregroundStyle(theme.actionColor)
                        (Text("This phone is the owner.").bold() + Text(" The bike keeps FreeVela firmware now, so the 10-minute timer is gone."))
                            .font(.archivo(15, weight: 400)).foregroundStyle(theme.ink)
                    }
                }
            } else if model.pairFailed {
                Text("Couldn't pair. Stay next to the bike and try again.").font(.archivo(14, weight: 500)).foregroundStyle(.red)
            } else {
                note("Stay next to the bike. This takes a few seconds.")
            }
        } bottom: {
            if model.pairStage == 3 {
                InkBarButton(title: "Continue", symbol: "arrow.right") { model.step = .backup }
            } else if model.pairFailed {
                InkBarButton(title: "Try again", symbol: "arrow.clockwise") { model.pair() }
            } else {
                waiting("Pairing…")
            }
        }
    }

    // MARK: Steps 5 and 6

    private var backup: some View {
        page(icons: ["key.fill"], "Save your key backup", "Without a backup, a lost phone means a locked bike.", back: false) {
            card {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(theme.ink, lineWidth: 2)
                        .frame(width: 44, height: 54)
                        .overlay(Image(systemName: "key.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.ink))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("vela-backup.json").font(.archivo(16, weight: 600)).foregroundStyle(theme.ink)
                        Text("Vela V2 · the new keys for this bike").font(.archivo(13, weight: 400)).foregroundStyle(theme.inkMuted)
                    }
                }
            }
            SectionHeader("Somewhere safe, like")
            point("key.viewfinder", "Your password manager", "Save it as a secure note or file.")
            point("folder.fill", "Files, on iCloud Drive", "Somewhere you'll find it on a new phone.")
            point("laptopcomputer", "AirDrop to your computer", "Keep a second copy off the phone.")
            note("Anyone with this file can control the bike, so don't post it or send it to others.")
        } bottom: {
            InkBarButton(title: "Save key backup", symbol: "square.and.arrow.up") { model.saveBackup() }
            textButton("Later") { skipBackup = true }
        }
    }

    private var done: some View {
        page(icons: ["checkmark.seal.fill"], "Your bike is set up", "This phone is the owner. Ride on.", back: false) {
            card {
                doneRow("bicycle", "Ready to ride", "FreeVela connects to the bike whenever you open the app nearby.")
                Rectangle().fill(theme.tile).frame(height: 1)
                if model.backupSaved {
                    doneRow("key.fill", "Key backup saved", "Keep it somewhere safe. You'll need it if you change phones.")
                } else {
                    doneRow("key.fill", "No key backup yet", "Save one from Settings → Bikes & keys before you ride far.")
                }
            }
        } bottom: {
            InkBarButton(title: "Go to bike", symbol: "arrow.right", action: onFinish)
        }
    }

    private func doneRow(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).display(16, tracking: 0.02).foregroundStyle(theme.ink)
                Text(text).font(.archivo(14, weight: 400)).foregroundStyle(theme.inkMuted)
            }
        }
    }
}

// MARK: - Pieces

/// Back, Cancel, the 6-step progress and the trial timer, at the top of the painted band.
private struct WalkthroughHeader: View {
    var step: Int
    var timerEnds: Date?
    var onBack: (() -> Void)?
    var onCancel: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold))
                            Text("Back").display(16, tracking: 0.04)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onCancel) {
                    Text("Cancel")
                        .display(16, tracking: 0.04)
                        .foregroundStyle(theme.paint.frame)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(theme.paint.on, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            if step > 0 {
                HStack(spacing: 4) {
                    ForEach(1...6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(theme.paint.on.opacity(i <= step ? 1 : 0.3)).frame(height: 4)
                    }
                }
                HStack {
                    Text("Step \(step) of 6").display(13, weight: 700, tracking: 0.1)
                    Spacer()
                    if let timerEnds {
                        HStack(spacing: 6) {
                            Image(systemName: "timer").font(.system(size: 16, weight: .semibold))
                            TrialClock(ends: timerEnds, suffix: " left").font(.display(14)).tracking(0.56)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(theme.paint.deep, in: Capsule())
                    }
                }
            }
        }
    }
}

/// "8:24" counting down to `ends`.
private struct TrialClock: View {
    var ends: Date?
    var suffix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int((ends ?? context.date).timeIntervalSince(context.date)))
            Text(String(format: "%d:%02d", left / 60, left % 60) + suffix).textCase(.uppercase).monospacedDigit()
        }
    }
}

/// The 15-second hold: 5 quiet seconds, 9 chirps, then the long tone.
private struct HoldTimeline: View {
    var held: Int
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                // 14 one-second cells and the long-tone cell at 2.2× their width, 3 pt apart.
                let unit = (geo.size.width - 14 * 3) / (14 + 2.2)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(1...14, id: \.self) { i in
                        VStack(spacing: 4) {
                            if i >= 6 {
                                Circle().fill(theme.paint.frame).opacity(i <= held ? 1 : 0.3).frame(width: 5, height: 5)
                            }
                            RoundedRectangle(cornerRadius: 5)
                                .fill(i <= held ? (i <= 5 ? theme.inkMuted.opacity(0.55) : theme.paint.frame) : theme.tile)
                                .frame(height: i <= 5 ? 22 : 32)
                        }
                        .frame(width: unit)
                    }
                    RoundedRectangle(cornerRadius: 6)
                        .fill(held >= 15 ? theme.ink : theme.tile)
                        .overlay(Image(systemName: "speaker.wave.3.fill").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(held >= 15 ? theme.onInk : theme.inkMuted))
                        .frame(width: unit * 2.2, height: 44)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 44)
            .animation(.easeInOut(duration: 0.15), value: held)
            HStack(alignment: .top) {
                Text("0–5 s\nNothing")
                Spacer()
                Text("6–14 s · a short\nchirp each second").multilineTextAlignment(.center)
                Spacer()
                Text("15 s\nLong tone").multilineTextAlignment(.trailing)
            }
            .font(.archivo(11, weight: 700))
            .textCase(.uppercase)
            .foregroundStyle(theme.inkMuted)
        }
    }
}
