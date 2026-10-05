import SwiftUI
import UIKit

/// Archivo, bundled as one variable font (weight 100–900, width 62–125). "Condensed" is width 62.
extension Font {
    static func archivo(_ size: CGFloat, weight: CGFloat = 500, condensed: Bool = false) -> Font {
        Font(UIFont.archivo(size, weight: weight, width: condensed ? 62 : 100))
    }

    /// Poster type: condensed Archivo with tabular figures. Pair with `.textCase(.uppercase)` where needed.
    static func display(_ size: CGFloat, weight: CGFloat = 800) -> Font {
        archivo(size, weight: weight, condensed: true).monospacedDigit()
    }
}

extension UIFont {
    private static let wght = 0x7767_6874   // 'wght'
    private static let wdth = 0x7764_7468   // 'wdth'
    private static var cache: [String: UIFont] = [:]

    static func archivo(_ size: CGFloat, weight: CGFloat, width: CGFloat) -> UIFont {
        let key = "\(size)-\(weight)-\(width)"
        if let font = cache[key] { return font }
        let base = UIFontDescriptor(fontAttributes: [.name: "Archivo-SemiBold"])
        let descriptor = base.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight, wdth: width],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        cache[key] = font
        return font
    }
}

extension View {
    /// Condensed poster label: uppercase with letter spacing given as a fraction of the size (0.08 = +8%).
    func display(_ size: CGFloat, weight: CGFloat = 800, tracking: CGFloat = 0) -> some View {
        font(.display(size, weight: weight)).tracking(size * tracking).textCase(.uppercase)
    }
}
