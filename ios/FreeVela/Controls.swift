import SwiftUI

/// Readings from the bike's STATE, in the shapes the screens use.
extension BikeLink {
    func flag(_ path: String) -> Bool? { values[path].map { $0 == "1" || $0 == "true" } }

    var battery: Int? { values["pwr.fuel"].flatMap(Int.init) }
    var batterySymbol: String { flag("pwr.chr") == true ? "battery.100percent.bolt" : "battery.75percent" }
    var odometerPulses: Double? { values["motor.pulse"].flatMap(Double.init) }

    func speed(_ units: Units) -> Double? {
        guard let rps = values["motor.rps"].flatMap(Double.init) else { return nil }
        return rps * BikeProtocol.metersPerRev * (units == .kmh ? 3.6 : 2.237)
    }

    var assistMode: BikeProtocol.AssistMode? {
        BikeProtocol.AssistMode(ast: values["motor.ast"], save: values["pwr.save"])
    }

    /// Whether the connected bike's firmware supports a feature (see BLE/Firmware.swift).
    func can(_ c: Capability) -> Bool { firmware?.has(c) ?? false }
}

/// Distance from odometer pulses, e.g. "1,288.1 km".
func distance(pulses: Double, _ units: Units) -> String {
    let value = pulses * (units == .kmh ? BikeProtocol.kmPerPulse : BikeProtocol.miPerPulse)
    return value.formatted(.number.precision(.fractionLength(1))) + " " + units.distance
}

extension BikeProtocol.AssistMode {
    var symbol: String {
        switch self {
        case .off: "power"
        case .low: "leaf.fill"
        case .auto: "sparkles"
        case .high: "bolt.fill"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self)! }

    func summary(eco: Int?) -> String {
        switch self {
        case .off: "No motor help — rides like a regular bike."
        case .low: "Gentle eco assist, all the time. Longest range."
        case .auto: "Full assist until the battery drops below \(eco ?? 20)%, then eco."
        case .high: "Full assist, always."
        }
    }
}

/// Motor settings in FreeVela firmware (`fv.tune`, see modules/motor `tune`). Speeds are wheel rps.
enum MotorTune: String, CaseIterable {
    case top, btn, mg, sl, cr

    /// FreeVela's defaults (the stock curves, with a faster climb back after coasting).
    var `default`: Double {
        switch self {
        case .top: (225 - 83 - 18) / 29.0
        case .btn: 0
        case .mg: 18
        case .sl: 29
        case .cr: 0.4
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .top: 2.5...5.3
        case .btn: 0...1
        case .mg: 0...60
        case .sl: 15...45
        case .cr: 0...1
        }
    }

    static func speed(rps: Double, _ units: Units) -> Double {
        rps * BikeProtocol.metersPerRev * (units == .kmh ? 3.6 : 2.237)
    }

    static func rps(speed: Double, _ units: Units) -> Double {
        speed / (BikeProtocol.metersPerRev * (units == .kmh ? 3.6 : 2.237))
    }
}

/// Light modes as the firmware numbers them (light/MODE_SET). The app offers only On and Off:
/// "On" is the firmware's auto, which lights whenever the bike is awake and turns off when it idles
/// (60 s without use). The firmware's always-on mode kept the light on while idle, so the app
/// moves a bike that has it back to auto (see Session).
enum LightMode: Int, CaseIterable {
    case auto = 0, alwaysOn = 1, off = -1
    var isOn: Bool { self != .off }
    var label: String { isOn ? "On" : "Off" }
    var symbol: String { isOn ? "lightbulb.fill" : "lightbulb.slash" }
    var next: LightMode { isOn ? .off : .auto }
}

/// A value the user just picked, waiting for the bike to report it.
struct Pending {
    let value: String
    let until: Date

    /// How long to keep showing a pick the bike hasn't confirmed before going back to what it reports.
    static let patience: TimeInterval = 5

    var expired: Bool { until < .now }

    /// Numbers compare as numbers (the bike may write 4.8 as "4.8" or "4.800"), booleans as 1/0.
    func matches(_ bike: String?) -> Bool {
        guard let bike else { return false }
        let norm = { (s: String) in s == "true" ? "1" : s == "false" ? "0" : s }
        if let a = Double(norm(value)), let b = Double(norm(bike)) { return abs(a - b) < 0.001 }
        return value == bike
    }
}

/// Bike commands with optimistic UI. A pick shows right away and keeps showing, through reads that
/// still have the old value and through the steps of multi-part commands, until the bike reports it
/// (or `Pending.patience` passes). A newer pick replaces an older one, so rapid changes don't fight.
extension Session {
    /// The bike's value for a pending key. "assist" is derived from two paths.
    func bikeValue(_ key: String, in values: [String: String]) -> String? {
        key == "assist" ? BikeProtocol.AssistMode(ast: values["motor.ast"], save: values["pwr.save"])?.rawValue : values[key]
    }

    /// What to show for `key`: the pending pick if there is one, else the bike's value.
    func shown(_ key: String) -> String? {
        if let p = pending[key], !p.expired { return p.value }
        return bikeValue(key, in: link.values)
    }

    private func expect(_ key: String, _ value: String) {
        pending[key] = Pending(value: value, until: .now + Pending.patience)
    }

    var assist: BikeProtocol.AssistMode? { shown("assist").flatMap(BikeProtocol.AssistMode.init(rawValue:)) }

    /// The battery % below which Auto uses eco: the bike's value while in Auto, otherwise what Auto will use.
    var eco: Int {
        ecoDraft ?? (assist == .auto ? shown("pwr.save").flatMap(Int.init) : nil) ?? Self.ecoBelow
    }

    /// Remembered so choosing Auto again uses the level picked in Settings.
    static var ecoBelow: Int {
        get { UserDefaults.standard.object(forKey: "ecoBelow") as? Int ?? 20 }
        set { UserDefaults.standard.set(newValue, forKey: "ecoBelow") }
    }
    var light: LightMode? { shown("light.mode").flatMap(Int.init).flatMap(LightMode.init) }
    func isOn(_ path: String) -> Bool { shown(path).map { $0 == "1" || $0 == "true" } ?? false }

    func setAssist(_ mode: BikeProtocol.AssistMode) {
        guard mode != assist else { return }
        expect("assist", mode.rawValue)
        if mode == .auto { expect("pwr.save", "\(Self.ecoBelow)") }
        Task {
            if mode == .auto { await link.setEcoThreshold(Self.ecoBelow) } else { await link.setAssist(mode) }
        }
    }

    /// Saves the slider's level; sends it now only if the bike is in Auto (other modes use pwr.save themselves).
    func commitEco() {
        guard let draft = ecoDraft else { return }
        Self.ecoBelow = draft
        ecoDraft = nil
        guard assist == .auto else { return }
        expect("pwr.save", "\(draft)")
        Task { await link.setEcoThreshold(draft) }
    }

    /// FreeVela firmware with `motor-tune`: a motor setting as the bike has it (or as just picked).
    func tune(_ key: MotorTune) -> Double {
        shown("fv.tune.\(key.rawValue)").flatMap(Double.init) ?? key.default
    }

    func setTune(_ key: MotorTune, _ value: Double) {
        setTune([key: value])
    }

    func setTune(_ changes: [MotorTune: Double]) {
        for (key, value) in changes { expect("fv.tune.\(key.rawValue)", "\(value)") }
        let payload = changes.map { "\"\($0.key.rawValue)\":\($0.value)" }.joined(separator: ",")
        Task { await link.dispatch(#"{"type":"fv/TUNE_SET","payload":{\#(payload)}}"#, base64Text: false) }
    }

    /// FreeVela firmware with `sleep-timer`: minutes without use before the bike sleeps (0 = never).
    var sleepAfter: Int? { shown("fv.sleep").flatMap(Int.init) }

    func setSleepAfter(_ minutes: Int) {
        send("fv.sleep", "\(minutes)", #"{"type":"fv/SLEEP_SET","payload":\#(minutes)}"#)
    }

    func setLight(_ mode: LightMode) {
        send("light.mode", "\(mode.rawValue)", #"{"type":"light/MODE_SET","payload":\#(mode.rawValue)}"#)
    }

    func setAlarm(_ on: Bool) {
        send("alarm.armed", on ? "1" : "0", on ? #"{"type":"alarm/ARM"}"# : #"{"type":"alarm/DESARM"}"#)
    }

    func setEbrake(_ on: Bool) {
        send("motor.ebc", on ? "1" : "0", #"{"type":"motor/EBC_SET","payload":\#(on ? 1 : 0)}"#)
    }

    /// FreeVela 0.2.0+: whether brake + button for 15 s may erase the key (`fv.lock` 0) or not (1).
    func setBikeReset(_ allowed: Bool) {
        send("fv.lock", allowed ? "0" : "1", #"{"type":"fv/LOCK_SET","payload":\#(allowed ? 0 : 1)}"#)
    }

    private func send(_ path: String, _ expected: String, _ json: String) {
        expect(path, expected)
        Task { await link.dispatch(json, base64Text: false) }
    }

    /// Sounds the siren for 15 seconds; `sirenEnds` drives the countdown.
    func soundSiren() {
        guard sirenEnds == nil else { return }
        sirenEnds = .now + 15
        Task {
            await link.soundAlarm()
            sirenEnds = nil
        }
    }

    func sleep() {
        Task { await link.dispatch(#"{"type":"pwr/SLEEP_REQUESTED"}"#, base64Text: false) }
    }
}
