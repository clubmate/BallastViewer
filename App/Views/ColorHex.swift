import AppKit
import BallastCore
import SwiftUI

extension Color {
    /// Parses `#RRGGBB` or `#RRGGBBAA` (canonical alpha-last order, C8).
    init?(hex: String) {
        guard let parsed = HexColor.parse(hex) else { return nil }
        self.init(
            red: Double(parsed.red) / 255.0,
            green: Double(parsed.green) / 255.0,
            blue: Double(parsed.blue) / 255.0,
            opacity: Double(parsed.alpha) / 255.0
        )
    }

    /// Canonical `#RRGGBBAA` (C8) via sRGB — nil for colors outside sRGB.
    var canonicalHex: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func channel(_ value: CGFloat) -> UInt8 {
            UInt8((value.clamped(to: 0...1) * 255).rounded())
        }
        return HexColor(
            red: channel(srgb.redComponent),
            green: channel(srgb.greenComponent),
            blue: channel(srgb.blueComponent),
            alpha: channel(srgb.alphaComponent)
        ).formatted
    }
}

extension CGFloat {
    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
