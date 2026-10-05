import SwiftUI

/// The frame colors the app can be painted in (Settings → Paint).
enum Paint: String, CaseIterable, Identifiable {
    case oxblood, olive, signalRed, coral, sunflower, midnight, sage, sky, petal, graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .oxblood: "Oxblood"
        case .olive: "Olive"
        case .signalRed: "Signal Red"
        case .coral: "Coral"
        case .sunflower: "Sunflower"
        case .midnight: "Midnight"
        case .sage: "Sage"
        case .sky: "Sky"
        case .petal: "Petal"
        case .graphite: "Graphite"
        }
    }

    /// The home-screen icon for this paint: nil is the primary icon (Oxblood), the rest are
    /// alternate icon sets named AppIcon-<Paint> in the asset catalog.
    var iconName: String? {
        self == .oxblood ? nil : "AppIcon-" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Switches the home-screen icon to match. iOS tells the user it changed.
    @MainActor
    func applyIcon() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != iconName else { return }
        app.setAlternateIconName(iconName)
    }

    var colors: PaintColors {
        switch self {
        case .oxblood: PaintColors(frame: 0x6C1D23, on: 0xF4E7CF, deep: 0x4B1217, lit: 0xC9545A, pin: 0xE9D5AE)
        case .olive: PaintColors(frame: 0x525A38, on: 0xF3EAD3, deep: 0x3B4128, lit: 0xA3AE72, pin: 0xE7D9B2)
        case .signalRed: PaintColors(frame: 0xB3292E, on: 0xFBEFDB, deep: 0x871D22, lit: 0xE4555A, pin: 0xF1DFBC)
        case .coral: PaintColors(frame: 0xD97B63, on: 0x2B1712, deep: 0xB65F49, lit: 0xEA9580, pin: 0xFBEBDD, isLight: true)
        case .sunflower: PaintColors(frame: 0xE7B62C, on: 0x2A1F0E, deep: 0xC0921A, lit: 0xEDC14A, pin: 0xFFF4D6, isLight: true)
        case .midnight: PaintColors(frame: 0x26334F, on: 0xF1E9DA, deep: 0x18223A, lit: 0x7D93C2, pin: 0xE9D5AE)
        case .sage: PaintColors(frame: 0x8DB59E, on: 0x1C2A22, deep: 0x6F9682, lit: 0x9DC4AD, pin: 0xF4EEDF, isLight: true)
        case .sky: PaintColors(frame: 0x86AECB, on: 0x16242F, deep: 0x668FAD, lit: 0x96BCD7, pin: 0xF4EEDF, isLight: true)
        case .petal: PaintColors(frame: 0xE2A3A9, on: 0x2E1719, deep: 0xC3848A, lit: 0xE9B1B6, pin: 0xFBEFE6, isLight: true)
        case .graphite: PaintColors(frame: 0x3A3734, on: 0xF1E9DA, deep: 0x262422, lit: 0xB5ABA0, pin: 0xD9C9A8)
        }
    }
}

/// One paint's roles: `frame` is the paint, `on` is text and icons on it, `deep` a darker frame,
/// `lit` the version for dark backgrounds (Ride), `pin` the pinstripe accent.
struct PaintColors {
    let frame, on, deep, lit, pin: Color
    /// A light paint with dark text on it, so the status bar needs dark text too.
    let isLight: Bool

    init(frame: UInt32, on: UInt32, deep: UInt32, lit: UInt32, pin: UInt32, isLight: Bool = false) {
        self.frame = Color(hex: frame)
        self.on = Color(hex: on)
        self.deep = Color(hex: deep)
        self.lit = Color(hex: lit)
        self.pin = Color(hex: pin)
        self.isLight = isLight
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
