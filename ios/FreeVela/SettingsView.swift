import SwiftUI

/// Bike, keys, riding, display, firmware and help. Developer tools sit at the bottom.
struct SettingsView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var link: BikeLink
    @EnvironmentObject private var log: LabLog
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units: Units = .kmh
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var confirmingReset = false
    @State private var resetResult: String?
    @State private var topDraft: Double?

    var body: some View {
        NavigationStack {
            Form {
                if let bike = session.bike { Section { BikeCard(bike: bike) } }
                BikesSection()
                if session.bike != nil { keySection }
                if link.isUnlocked, link.can(.ebrake) || link.can(.ecoThreshold) { riding }
                if link.isUnlocked, link.can(.motorTune) { motor }
                if link.isUnlocked, link.can(.sleepTimer) { power }
                display
                firmware
                Section {
                    ShareLink(item: log.exportText) { SettingsRow("Share log with developer", "square.and.arrow.up", .blue) }
                } header: {
                    Text("Help")
                } footer: {
                    Text("The log never contains your keys.")
                }
                Section {
                    NavigationLink { LabView() } label: { SettingsRow("Developer tools", "wrench.and.screwdriver.fill", Color(.darkGray), plain: true) }
                } footer: {
                    Text("Raw Bluetooth, unlock steps and the full log.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var keySection: some View {
        Section {
            if let file = try? VelaBackup.file(for: session.keys.bikes) {
                ShareLink(item: file) { SettingsRow("Save key backup", "square.and.arrow.down", .blue) }
            }
            if link.isUnlocked {
                Button { confirmingReset = true } label: { SettingsRow("Reset keys…", "key.fill", .red) }
                    .disabled(session.busy != nil)
                    .confirmationDialog("Reset keys?", isPresented: $confirmingReset, titleVisibility: .visible) {
                        Button("Reset keys", role: .destructive) {
                            Task {
                                resetResult = await session.resetKeys()
                                    ? "The bike has new keys, saved on this phone. Your old backup and any other phone with the old keys no longer work. Save a new key backup now."
                                    : "The keys weren't changed. Stay next to the bike and try again, or share the log."
                            }
                        }
                    } message: {
                        Text("Makes new keys for this bike and pairs this phone with them. Old backups and other phones stop working.")
                    }
            }
            if link.isUnlocked, link.can(.keyReset) {
                Toggle(isOn: Binding(get: { !session.isOn("fv.lock") }, set: { session.setBikeReset($0) })) {
                    SettingsRow("Reset from the bike", "hand.raised.fill", .orange, plain: true)
                }
            }
        } header: {
            Text("Keys")
        } footer: {
            if link.isUnlocked, link.can(.keyReset) {
                Text("Keep a key backup somewhere safe: without it, a lost phone means a locked bike. With Reset from the bike on, holding the brake lever and the button together for 15 seconds erases the keys so any phone can pair. Leave it off unless you need it.")
            } else {
                Text("Keep a key backup somewhere safe: without it, a lost phone means a locked bike.")
            }
        }
        .alert("Reset keys", isPresented: Binding(get: { resetResult != nil }, set: { if !$0 { resetResult = nil } })) {
            Button("OK") { resetResult = nil }
        } message: {
            Text(resetResult ?? "")
        }
    }

    private var riding: some View {
        Section {
            if link.can(.ebrake) {
                Toggle(isOn: Binding(get: { session.isOn("motor.ebc") }, set: { session.setEbrake($0) })) {
                    SettingsRow("E-brake", "exclamationmark.octagon.fill", .blue, plain: true)
                }
            }
            if link.can(.ecoThreshold) {
                VStack(spacing: 6) {
                    LabeledContent {
                        Text("\(session.eco)% battery").monospacedDigit()
                    } label: {
                        SettingsRow("Eco below", "leaf.fill", .green, plain: true)
                    }
                    Slider(value: Binding(get: { Double(session.eco) }, set: { session.ecoDraft = Int($0) }),
                           in: 5...95, step: 5) { editing in
                        if !editing { session.commitEco() }
                    }
                }
            }
        } header: {
            Text("Riding")
        } footer: {
            Text(link.can(.ebrake) && link.can(.ecoThreshold)
                 ? "E-brake: the motor helps brake when you pull the brake lever above about 18 km/h. Eco below: in Auto, assist switches to eco when the battery drops below this level."
                 : link.can(.ebrake) ? "The motor helps brake when you pull the brake lever above about 18 km/h."
                 : "In Auto, assist switches to eco when the battery drops below this level.")
        }
    }

    private var motor: some View {
        let range = MotorTune.top.range
        let low = MotorTune.speed(rps: range.lowerBound, units).rounded(.up)
        let high = MotorTune.speed(rps: range.upperBound, units).rounded(.down)
        let top = topDraft ?? MotorTune.speed(rps: session.tune(.top), units).rounded()
        return Section {
            VStack(spacing: 6) {
                LabeledContent {
                    Text("\(Int(top)) \(units.label)").monospacedDigit()
                } label: {
                    SettingsRow("Top speed", "gauge.with.dots.needle.67percent", .red, plain: true)
                }
                Slider(value: Binding(get: { min(max(top, low), high) }, set: { topDraft = $0 }), in: low...high, step: 1) { editing in
                    guard !editing, let draft = topDraft else { return }
                    session.setTune(.top, min(max(MotorTune.rps(speed: draft, units), range.lowerBound), range.upperBound))
                    topDraft = nil
                }
            }
            LabeledContent {
                Picker("Button", selection: Binding(get: { session.tune(.btn) > 0 }, set: { session.setTune(.btn, $0 ? 1 : 0) })) {
                    Text("Boost").tag(false)
                    Text("Throttle").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            } label: {
                SettingsRow("Button", "hand.point.up.left.fill", .orange, plain: true)
            }
        } header: {
            Text("Motor")
        } footer: {
            Text("Top speed is how fast assist and the throttle aim for; \(Int(MotorTune.speed(rps: MotorTune.top.default, units).rounded())) \(units.label) is the stock setting. The motor controller may stop helping sooner on its own — record a ride in Developer tools to see. Boost: hold the button while pedalling for full power, or without pedalling for walk assist. Throttle: hold the button to ride up to the top speed without pedalling; there's no walk assist. The brake always cuts the motor.")
        }
    }

    private static let sleepChoices = [0, 5, 10, 15, 30, 60, 120]

    private var power: some View {
        let current = session.sleepAfter ?? 0
        let choices = Self.sleepChoices.contains(current) ? Self.sleepChoices : (Self.sleepChoices + [current]).sorted()
        return Section {
            Picker(selection: Binding(get: { current }, set: { session.setSleepAfter($0) })) {
                ForEach(choices, id: \.self) { Text(Self.sleepLabel($0)) }
            } label: {
                SettingsRow("Sleep after", "moon.zzz.fill", .indigo, plain: true)
            }
        } header: {
            Text("Power")
        } footer: {
            Text("The bike goes to sleep after this long without riding, pedalling, the button, the brake or a command from the app. It stays awake while the alarm is armed. Wake it by holding the brake lever and the handlebar button together.")
        }
    }

    private static func sleepLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Never"
        case let m where m % 60 == 0: m == 60 ? "1 hour" : "\(m / 60) hours"
        default: "\(minutes) min"
        }
    }

    private var display: some View {
        Section {
            LabeledContent {
                Picker("Units", selection: $units) {
                    ForEach(Units.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            } label: {
                SettingsRow("Units", "speedometer", .orange, plain: true)
            }
            LabeledContent {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented)
                .frame(width: 186)
            } label: {
                SettingsRow("Appearance", "circle.lefthalf.filled", .indigo, plain: true)
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Units apply to speed, trip and odometer. Tip: tap the speed on Home to switch quickly.")
        }
    }

    private var latest: FirmwareImage? { FirmwareImage.known.last { $0.freeVela } }

    private var updateNote: String {
        guard let fw = link.firmware else { return "Connect to check" }
        guard let latest else { return fw.label }
        return fw.kind == .freeVela && fw.version == latest.version ? "Up to date" : "\(latest.label) available"
    }

    private var firmware: some View {
        Section {
            LabeledContent {
                Text(link.firmware?.label ?? "—")
            } label: {
                SettingsRow("Installed", "cpu", .gray, plain: true)
            }
            NavigationLink { FirmwareUpdateView() } label: {
                HStack(spacing: 12) {
                    SettingsIcon("arrow.down.circle.fill", .green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Firmware update")
                        Text(updateNote).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Firmware")
        } footer: {
            if link.firmware?.kind == .velaUnknown {
                Text("This firmware version hasn't been tested with FreeVela, so only the basic controls are shown.")
            } else {
                Text("Needs at least \(FirmwareUpdater.minBattery)% battery and the bike standing still. If the new firmware can't be unlocked, the bike switches back by itself.")
            }
        }
    }
}

/// The colored rounded-square icon used on Settings rows.
struct SettingsIcon: View {
    var symbol: String
    var color: Color
    init(_ symbol: String, _ color: Color) { self.symbol = symbol; self.color = color }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Icon + title. Action rows are tinted; `plain` rows (toggles, links, values) use the primary color.
struct SettingsRow: View {
    var title: String
    var symbol: String
    var color: Color
    var plain = false
    init(_ title: String, _ symbol: String, _ color: Color, plain: Bool = false) {
        self.title = title; self.symbol = symbol; self.color = color; self.plain = plain
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol, color)
            Text(title).foregroundStyle(plain ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
        }
    }
}
