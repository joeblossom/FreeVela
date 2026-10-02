import Foundation

/// Features the app can offer. Each screen asks `FirmwareInfo.has(_:)` before showing a control.
enum Capability: String, CaseIterable {
    // Basic controls: any Vela firmware should support these.
    case alarm, assistModes, ebrake, sleep
    // Supported by Vela firmware 2306052112.
    case ecoThreshold, light, findMyBike
    // Reserved for FreeVela firmware; enabled only when the firmware declares them in `fv.caps`.
    case assistStrength = "assist-strength"
    case softStart = "soft-start"
    case pushState = "push-state"
}

/// What firmware the bike is running, and what it can do. Built from each STATE read.
struct FirmwareInfo: Equatable {
    enum Kind: Equatable {
        case velaKnown        // Vela firmware we've verified
        case velaUnknown      // Vela firmware we haven't seen: basic controls only
        case freeVela         // FreeVela firmware: declares its own capabilities
    }

    let kind: Kind
    let version: String
    let capabilities: Set<Capability>

    func has(_ c: Capability) -> Bool { capabilities.contains(c) }

    /// The basic commands: safe on any Vela firmware.
    static let velaAppBaseline: Set<Capability> = [.alarm, .assistModes, .ebrake, .sleep]

    /// Vela versions we've verified on a real bike, and what each supports.
    static let knownVela: [String: Set<Capability>] = [
        "2306052112": velaAppBaseline.union([.ecoThreshold, .light, .findMyBike]),
    ]

    /// From the raw STATE JSON. FreeVela firmware adds `"fv": {"ver": "...", "caps": [...]}`.
    init?(state: [String: Any]) {
        if let fv = state["fv"] as? [String: Any] {
            let caps = (fv["caps"] as? [String] ?? []).compactMap(Capability.init(rawValue:))
            kind = .freeVela
            version = fv["ver"] as? String ?? "?"
            // FreeVela keeps everything the original firmware did, plus what it declares.
            capabilities = Self.knownVela["2306052112", default: []].union(caps)
            return
        }
        guard let sys = state["sys"] as? [String: Any], let ver = sys["ver"] else { return nil }
        version = "\(ver)"
        if let caps = Self.knownVela[version] {
            kind = .velaKnown
            capabilities = caps
        } else {
            kind = .velaUnknown
            capabilities = Self.velaAppBaseline
        }
    }

    var label: String {
        switch kind {
        case .velaKnown: "Vela \(version)"
        case .velaUnknown: "Vela \(version) (unrecognized)"
        case .freeVela: "FreeVela \(version)"
        }
    }
}
