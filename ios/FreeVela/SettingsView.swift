import SwiftUI

/// Bike, paint, keys, riding, display, firmware and help. Developer tools sit at the bottom.
struct SettingsView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var log: LabLog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage("units") private var units: Units = .kmh
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("paint") private var paint: Paint = .oxblood
    @State private var settingUp = false
    @State private var adding = false
    @State private var importing = false
    @State private var pasting = false
    @State private var keyError: String?
    @State private var showBike = false
    @State private var topDraft: Double?
    @State private var showLab = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                band
                Form {
                    if let bike = session.bike { Section { BikeCard(bike: bike) }.listRowBackground(Color.clear) }
                    paintSection
                    BikesSection(onAdd: { adding = true }, error: keyError)
                        if link.isUnlocked, link.can(.ebrake) || link.can(.ecoThreshold) { riding }
                    if link.isUnlocked, link.can(.motorTune) { motor }
                    if link.isUnlocked, link.can(.sleepTimer) { power }
                    display
                    firmware
                    Section {
                        ShareLink(item: log.exportText) { SettingsRow("Share log with developer", "paperplane.fill") }
                    } header: {
                        SectionHeader("Help")
                    } footer: {
                        footer("The log never contains your keys.")
                    }
                    .paintRows()
                    Section {
                        NavigationLink { LabView() } label: { SettingsRow("Developer tools", "wrench.and.screwdriver.fill", plain: true) }
                    } footer: {
                        footer("Raw Bluetooth, unlock steps and the full log.")
                    }
                    .paintRows()
                }
                .paintList()
                .listSectionSpacing(18)
                .contentMargins(.top, 30, for: .scrollContent)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
                .overlay(alignment: .top) {
                    RimLine(radius: 24)
                        .stroke(theme.ink, lineWidth: 3)
                        .frame(height: 26)
                        .padding(.horizontal, 9)
                        .padding(.top, 9)
                        .allowsHitTesting(false)
                }
                .padding(.top, -30)
            }
            .background { VStack(spacing: 0) { theme.paint.frame; theme.cream }.ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showLab) { LabView() }
            .navigationDestination(isPresented: $showBike) { BikeDetailView(bikeID: session.selectedID ?? "") }
            .confirmationDialog("Add a bike", isPresented: $adding, titleVisibility: .visible) {
                Button("Set up a new bike") { settingUp = true }
                Button("Import backup…") { importing = true }
                Button("Paste keys…") { pasting = true }
            } message: {
                Text("Set up works without keys: it installs FreeVela firmware and pairs this phone. Or add keys you already have.")
            }
            .keyImport(importing: $importing, pasting: $pasting, error: $keyError)
            .fullScreenCover(isPresented: $settingUp) {
                SetupView(onCancel: { settingUp = false; session.bikesChanged(); session.autoConnect() },
                          onFinish: { settingUp = false })
                    .paintedScreen()
                    .themed()
            }
            #if DEBUG
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-demoLab") { showLab = true }
                if args.contains("-demoBike") { showBike = true }
                if args.contains("-demoPaste") { Task { try? await Task.sleep(for: .seconds(1)); pasting = true } }
                if args.contains("-demoSetupCover") {
                    Task { try? await Task.sleep(for: .seconds(1)); settingUp = true }
                }
            }
            #endif
        }
    }

    private var band: some View {
        HStack {
            Text("Settings").display(40).foregroundStyle(theme.paint.on)
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .display(16, tracking: 0.04)
                    .foregroundStyle(theme.paint.frame)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(theme.paint.on, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 44)
        .background(theme.paint.frame)
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.archivo(13, weight: 400)).foregroundStyle(theme.inkMuted)
    }

    // MARK: Paint

    private var paintSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 10) {
                ForEach(Paint.allCases) { p in
                    Button { paint = p; p.applyIcon() } label: { PaintSwatch(paint: p, selected: p == paint) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
            .sensoryFeedback(.selection, trigger: paint)
        } header: {
            SectionHeader("Paint", trailing: paint.name)
        }
        .paintRows()
    }

    // MARK: Keys

    // MARK: Riding, motor, power

    private func valueLabel(_ text: String) -> some View {
        Text(text).display(20).foregroundStyle(theme.ink)
    }

    private var riding: some View {
        Section {
            if link.can(.ebrake) {
                Toggle(isOn: Binding(get: { session.isOn("motor.ebc") }, set: { session.setEbrake($0) })) {
                    SettingsRow("E-brake", "exclamationmark.octagon.fill", plain: true)
                }
            }
            if link.can(.ecoThreshold) {
                VStack(spacing: 10) {
                    LabeledContent {
                        valueLabel("\(session.eco)% battery")
                    } label: {
                        SettingsRow("Eco below", "leaf.fill", plain: true)
                    }
                    PaintSlider(value: Binding(get: { Double(session.eco) }, set: { session.ecoDraft = Int($0) }),
                                range: 5...95, step: 5) { editing in
                        if !editing { session.commitEco() }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            SectionHeader("Riding")
        } footer: {
            footer(link.can(.ebrake) && link.can(.ecoThreshold)
                   ? "E-brake: the motor helps brake when you pull the brake lever above about 18 km/h. Eco below: in Auto, assist switches to eco when the battery drops below this level."
                   : link.can(.ebrake) ? "The motor helps brake when you pull the brake lever above about 18 km/h."
                   : "In Auto, assist switches to eco when the battery drops below this level.")
        }
        .paintRows()
    }

    private var motor: some View {
        let range = MotorTune.top.range
        let low = MotorTune.speed(rps: range.lowerBound, units).rounded(.up)
        let high = MotorTune.speed(rps: range.upperBound, units).rounded(.down)
        let top = topDraft ?? MotorTune.speed(rps: session.tune(.top), units).rounded()
        return Section {
            VStack(spacing: 10) {
                LabeledContent {
                    valueLabel("\(Int(top)) \(units.label)")
                } label: {
                    SettingsRow("Top speed", "gauge.with.dots.needle.67percent", plain: true)
                }
                PaintSlider(value: Binding(get: { min(max(top, low), high) }, set: { topDraft = $0 }),
                            range: low...high, step: 1) { editing in
                    guard !editing, let draft = topDraft else { return }
                    session.setTune(.top, min(max(MotorTune.rps(speed: draft, units), range.lowerBound), range.upperBound))
                    topDraft = nil
                }
            }
            .padding(.vertical, 4)
            LabeledContent {
                PaintSegmented(selection: Binding(get: { session.tune(.btn) > 0 }, set: { session.setTune(.btn, $0 ? 1 : 0) }),
                               options: [(false, "Boost"), (true, "Throttle")])
            } label: {
                SettingsRow("Button", "hand.point.up.left.fill", plain: true)
            }
        } header: {
            SectionHeader("Motor")
        } footer: {
            footer("Top speed is how fast assist and the throttle aim for; \(Int(MotorTune.speed(rps: MotorTune.top.default, units).rounded())) \(units.label) is the stock setting. The motor controller may stop helping sooner on its own — record a ride in Developer tools to see. Boost: hold the button while pedalling for full power, or without pedalling for walk assist. Throttle: hold the button to ride up to the top speed without pedalling; there's no walk assist. The brake always cuts the motor.")
        }
        .paintRows()
    }

    private static let sleepChoices = [0, 5, 10, 15, 30, 60, 120]

    private var power: some View {
        let current = session.sleepAfter ?? 0
        let choices = Self.sleepChoices.contains(current) ? Self.sleepChoices : (Self.sleepChoices + [current]).sorted()
        return Section {
            Picker(selection: Binding(get: { current }, set: { session.setSleepAfter($0) })) {
                ForEach(choices, id: \.self) { Text(Self.sleepLabel($0)) }
            } label: {
                SettingsRow("Sleep after", "moon.zzz.fill", plain: true)
            }
            .tint(theme.ink)
        } header: {
            SectionHeader("Power")
        } footer: {
            footer("The bike goes to sleep after this long without riding, pedalling, the button, the brake or a command from the app. It stays awake while the alarm is armed. Wake it by holding the brake lever and the handlebar button together.")
        }
        .paintRows()
    }

    private static func sleepLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Never"
        case let m where m % 60 == 0: m == 60 ? "1 hour" : "\(m / 60) hours"
        default: "\(minutes) min"
        }
    }

    // MARK: Display

    private var display: some View {
        Section {
            LabeledContent {
                PaintSegmented(selection: $units, options: Units.allCases.map { ($0, $0.label) })
            } label: {
                SettingsRow("Units", "speedometer", plain: true)
            }
            LabeledContent {
                PaintSegmented(selection: $appearance, options: Appearance.allCases.map { ($0, $0.label) })
            } label: {
                SettingsRow("Appearance", "circle.lefthalf.filled", plain: true)
            }
        } header: {
            SectionHeader("Display")
        } footer: {
            footer("Units apply to speed, trip and odometer. Tip: tap the speed on Home to switch quickly.")
        }
        .paintRows()
    }

    // MARK: Firmware

    private var latest: FirmwareImage? { FirmwareImage.known.last { $0.freeVela } }

    private var updateNote: String {
        guard let fw = link.firmware else { return "Connect to check" }
        guard let latest else { return fw.label }
        return fw.kind == .freeVela && fw.version == latest.version ? "Up to date" : "\(latest.label) available"
    }

    private var firmware: some View {
        Section {
            LabeledContent {
                Text(link.firmware?.label ?? "—").foregroundStyle(theme.inkMuted)
            } label: {
                SettingsRow("Installed", "cpu", plain: true)
            }
            NavigationLink { FirmwareUpdateView() } label: {
                HStack(spacing: 12) {
                    SettingsIcon("arrow.down.circle.fill")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Firmware update").font(.archivo(16, weight: 500))
                        Text(updateNote).font(.archivo(13, weight: 400)).foregroundStyle(theme.inkMuted)
                    }
                }
            }
        } header: {
            SectionHeader("Firmware")
        } footer: {
            if link.firmware?.kind == .velaUnknown {
                footer("This firmware version hasn't been tested with FreeVela, so only the basic controls are shown.")
            } else {
                footer("Needs at least \(FirmwareUpdater.minBattery)% battery and the bike standing still. If the new firmware can't be unlocked, the bike switches back by itself.")
            }
        }
        .paintRows()
    }
}

/// A paint chip: the color in a circle with the downtube's two pinstripes, and its name.
struct PaintSwatch: View {
    @Environment(\.theme) private var theme
    var paint: Paint
    var selected: Bool

    var body: some View {
        let c = paint.colors
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(c.frame)
                HStack(spacing: 3) {
                    Rectangle().fill(c.pin).frame(width: 2)
                    Rectangle().fill(c.pin).frame(width: 2)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 9 - 3)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(c.on)
                }
            }
            .clipShape(Circle())
            .padding(3)
            .frame(width: 50, height: 50)
            .overlay(Circle().strokeBorder(selected ? theme.ink : .clear, lineWidth: 3))
            Text(paint.name).display(11).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paint.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
