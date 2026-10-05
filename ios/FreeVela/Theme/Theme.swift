import SwiftUI

/// The app's colors: the chosen paint plus the cream "tyre" neutrals. Read with `@Environment(\.theme)`.
/// Dark appearance uses an interim palette (the Ride screen's browns) until a dark design exists.
struct Theme {
    var paint: PaintColors
    var ink, inkMuted, cream, surface, tile, toggleOff: Color
    /// The interim dark palette is in use.
    var dark: Bool

    // Ride is always dark.
    static let rideBg = Color(hex: 0x16110E)
    static let rideControl = Color(hex: 0x2A211B)
    static let rideMuted = Color(hex: 0x9C8F82)
    static let rideBarOff = Color(hex: 0x33291F)
    static let rideLightOn = Color(hex: 0xF2C14E)
    static let rideLightOff = Color(hex: 0x4A3F36)
    static let creamFixed = Color(hex: 0xF1E9DA)

    init(paint: Paint, dark: Bool) {
        self.paint = paint.colors
        self.dark = dark
        if dark {
            ink = Color(hex: 0xF1E9DA)
            inkMuted = Color(hex: 0x9C8F82)
            cream = Color(hex: 0x16110E)
            surface = Color(hex: 0x2A211B)
            tile = Color(hex: 0x33291F)
            toggleOff = Color(hex: 0x4A3F36)
        } else {
            ink = Color(hex: 0x231B16)
            inkMuted = Color(hex: 0x5E5046)
            cream = Color(hex: 0xF1E9DA)
            surface = Color(hex: 0xFAF6EE)
            tile = Color(hex: 0xE4D9C6)
            toggleOff = Color(hex: 0xD9CDB8)
        }
    }

    /// Text and icons on an `ink` fill (cream in light mode, dark brown in dark mode).
    var onInk: Color { cream }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(paint: .oxblood, dark: false)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Puts the theme for the chosen paint and the current appearance into the environment.
struct Themed: ViewModifier {
    @AppStorage("paint") private var paint: Paint = .oxblood
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .environment(\.theme, Theme(paint: paint, dark: scheme == .dark))
            .tint(Theme(paint: paint, dark: scheme == .dark).ink)
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }
}
