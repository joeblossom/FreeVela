import CoreBluetooth

/// GATT map and action vocabulary. See docs/protocol.md — most of this is
/// still unverified on a real bike; the Lab exists to confirm it.
enum BikeProtocol {
    private static func uuid(_ short: String) -> CBUUID {
        CBUUID(string: "\(short)-7320-4cda-9830-697df55e369a")
    }

    static let authService = uuid("00000100")
    static let challenge   = uuid("00000101")  // read
    static let key         = uuid("00000102")  // write <- key (32 raw bytes)
    static let release     = uuid("00000199")  // read/write <- releasedKey (32 raw bytes)

    static let reduxService = uuid("00000200")
    static let state        = uuid("00000201")  // read + notify, UTF-8 JSON
    static let dispatch     = uuid("00000202")  // write w/ response, UTF-8 JSON

    /// Firmware update service. Only FirmwareUpdater writes here; the Lab refuses to.
    static let firmwareService = uuid("00000300")
    static let otaState        = uuid("00000301")  // write: any byte = install what was sent
    static let otaData         = uuid("00000302")  // write: raw image bytes, in order

    static let scanServices = [authService, reduxService]

    static func name(of uuid: CBUUID) -> String? {
        switch uuid {
        case authService: "Auth service"
        case challenge: "CHALLENGE"
        case key: "KEY"
        case release: "RELEASE"
        case reduxService: "Redux service"
        case state: "STATE"
        case dispatch: "DISPATCH"
        case firmwareService: "Firmware update"
        case otaState: "OTA state (install)"
        case otaData: "OTA data"
        default: nil
        }
    }

    /// Assist modes (docs/firmware.md): `motor.ast` 0 disables the motor;
    /// otherwise the eco curve is used whenever battery % ≤ `pwr.save`.
    /// Manual modes set the saver level, then 150 ms later ASSIST_SET 1.
    enum AssistMode: String, CaseIterable, Identifiable {
        case off = "Off", low = "Low", auto = "Auto", high = "High"
        var id: String { rawValue }

        var saver: Int? {
            switch self {
            case .off: nil
            case .low: 100   // always eco
            case .auto: 20   // eco only below 20% battery
            case .high: 0    // never eco
            }
        }

        init?(ast: String?, save: String?) {
            guard let ast else { return nil }
            if ast == "0" || ast == "false" { self = .off; return }
            switch save {
            case "100": self = .low
            case "0": self = .high
            case nil: return nil
            default: self = .auto
            }
        }
    }

    /// Wheel: 6 pulses per revolution, 0.39 m per pulse (2.34 m circumference).
    static let metersPerRev = 2.34

    /// Odometer: the app shows motor.pulse × 0.00039 km (× 0.00023 mi).
    static let kmPerPulse = 0.00039
    static let miPerPulse = 0.00023

    struct Preset: Identifiable {
        let label: String
        let json: String
        var id: String { json }
    }

    static let presets: [Preset] = [
        Preset(label: "Alarm arm", json: #"{"type":"alarm/ARM"}"#),
        Preset(label: "Alarm off", json: #"{"type":"alarm/DESARM"}"#),
        Preset(label: "ASSIST_SET 1", json: #"{"type":"motor/ASSIST_SET","payload":1}"#),
        Preset(label: "ASSIST_SET 0", json: #"{"type":"motor/ASSIST_SET","payload":0}"#),
        Preset(label: "Saver 0", json: #"{"type":"pwr/SAVER_UPDATED","payload":0}"#),
        Preset(label: "Saver 20", json: #"{"type":"pwr/SAVER_UPDATED","payload":20}"#),
        Preset(label: "Saver 100", json: #"{"type":"pwr/SAVER_UPDATED","payload":100}"#),
        Preset(label: "Sleep", json: #"{"type":"pwr/SLEEP_REQUESTED"}"#),
        Preset(label: "E-brake on", json: #"{"type":"motor/EBC_SET","payload":1}"#),
        Preset(label: "E-brake off", json: #"{"type":"motor/EBC_SET","payload":0}"#),
        // Supported by Vela firmware 2306052112 (see Capability.light).
        Preset(label: "Light auto", json: #"{"type":"light/MODE_SET","payload":0}"#),
        Preset(label: "Light on", json: #"{"type":"light/MODE_SET","payload":1}"#),
        Preset(label: "Light off", json: #"{"type":"light/MODE_SET","payload":-1}"#),
    ]
}
